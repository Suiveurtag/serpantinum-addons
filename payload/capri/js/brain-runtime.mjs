// Brain wiring from upstream app.js; chat attaches in CapriChat.qml.
import {Brain} from './brain.mjs';
import {Bond, Jealousy, RIVALS} from './bond.mjs';
import {Mission} from './mission.mjs';
import {Reminders} from './reminders.mjs';
import {Panel} from './panel.mjs';
import {pick, fmt, performance, setTimeout, setInterval, sleep, co} from './util.mjs';

export function rivalKeys(title, app) {
  const s=String(title || '')+' '+String(app || '');
  const patterns={chatgpt:/\bChatGPT\b/i,claude:/\bClaude\b/i,codex:/\bCodex\b/i,gemini:/\bGemini\b/i,copilot:/\bCopilot\b/i,perplexity:/\bPerplexity\b/i,deepseek:/\bDeepSeek\b/i,grok:/\bGrok\b/i,lechat:/\bLe Chat\b|\bMistral AI\b/i,characterai:/character\.ai/i,metaai:/\bMeta AI\b/i};
  return Object.keys(patterns).filter(k=>patterns[k].test(s));
}
export class Runtime {
  constructor(capri,host) {
    this.capri=capri; this.host=host; this.startedAt=Date.now(); this.lastMove=performance.now(); this.pointer=null;
    this.panel=new Panel(host);
    this.mission=new Mission();
    // Keep hook bookkeeping in DND, suppress attention moves as well as the panel.
    const facade={};
    for(const key of Object.keys(capri).concat(Object.getOwnPropertyNames(Object.getPrototypeOf(capri)))) {
      if(key==='constructor') continue;
      Object.defineProperty(facade,key,{configurable:true,get:()=> {
        const value=capri[key];
        return typeof value==='function' ? (...args)=> (!host.quiet() || ['setMode','stopPointing'].includes(key) ? value.apply(capri,args) : false) : value;
      },set:value=>capri[key]=value});
    }
    this.voice=host.voice || {play(){}};
    this.brain=new Brain({capri:facade,panel:this.panel,voice:this.voice,host,mission:this.mission,lang:host.lang(),assistant:host.get('Assistant','codex')});
    this.bond=new Bond({host,data:host.get('Bond',null)}); this.brain.bond=this.bond; capri.fondness=this.bond.stage;
    this.jealousy=new Jealousy({capri,panel:this.panel,brain:this.brain,bond:this.bond,chat:{open:false},guide:{running:false}});
    const free=this.jealousy.free.bind(this.jealousy); this.jealousy.free=()=>!host.quiet() && free();
    this.brain.onRival=k=>this.jealousy.onRivalEvent(k);
    this.reminders=new Reminders({host,list:host.get('Reminders',[])});
    this.reminders.onDue=r=>this.remind(r).catch(error=>{console.warn("Capri reminder:",error);this.reminders.snooze(r.id,60000);});
    this.brain.linked=host.get('Linked',false);
    this.brain.onLinked=()=> {host.setConfig({linked:true,welcomed:true}); if(!host.quiet()) {this.voice.play('hello');capri.perform('hop');this.panel.say({kind:'done',badge:'LINK',line:this.brain.t.welcome.linked,hold:6000});} };
    this.newStage=0; this.throws=[];
    this.bond.onStage=stage=> {this.newStage=stage; capri.fondness=stage;};
    this.bond.onCalm=()=> {this.jealousy.forgive();capri.refuseUntil=0;};
    capri.onClick=()=> {if(this.panel.visible)this.panel.hide(); else if(!this.jealousy.onClick()){this.brain.status();this.bond.add('click',1);} };
    capri.onMenu=()=>host.menu();
    capri.onDodge=()=>this.panel.say({kind:'info',face:'smug',line:pick(this.brain.t.thrown.dodge),hold:2500});
    capri.onThrown=data=>this.thrown(data);
    capri.onGaze=when=> {if(!this.panel.visible && Math.random()<(when==='end'?0.6:0.4))this.panel.say({kind:'info',line:pick(when==='end'?this.brain.t.uplink:this.brain.t.gaze),hold:3800});};
    setInterval(()=>this.stage(),3000);
    setInterval(()=> {if(performance.now()-this.lastMove<600000 && !capri.stowed)this.bond.add('time',1);},600000);
    setInterval(()=> {const d=this.mission.day;if(new Date().getHours()>=18 && !d.reported && d.missions>=3 && !this.brain.busySessions.length && this.quiet() && capri.mode!=='sleep'){if(this.brain.report()){this.mission.markReported();capri.perform('curious');}}},60000);
    this.configure();
  }
  configure() {
    const b=this.brain,h=this.host,c=this.capri,assistant=h.get('Assistant','codex'),watching=h.get('Watching',true);
    if(b.assistant!==assistant || b.watching!==watching) {
      this.panel.hide();c.stopPointing();b.replyFor=null;b.sessions.clear();this.panel.setTicker(null);c.setMode('idle');
      b.linked=h.get('Linked',false); this.jealousy.front=null;
    }
    b.assistant=assistant;b.watching=watching;b.lang=h.lang();
    b.custom={userName:h.get('UserName',''),persona:h.get('Persona',''),memories:h.get('Memories',[]),myLines:h.get('MyLines',[])};
    this.jealousy.enabled=h.get('Jealous',true);
    if(!this.jealousy.enabled){this.jealousy.front=null;this.jealousy.forgive();}
    this.reminders.sync(h.get('Reminders',[]));
    c.wander=h.get('Wander',true);c.possessWindows=h.get('Possess',true);c.restOn=h.get('Rest','corner');
  }
  quiet() {const c=this.capri;return !this.host.quiet() && !c.busy && !c.act && !c.dragging && !c.stowed && !c.dormant && !c.hidden && c.mode!=='alert' && !this.panel.visible && ['stand','sit'].includes(c.stance);}
  windows(data) {this.brain.onWindows(data);this.jealousy.onWindows(data);}
  moved(p) {
    if(!p || (this.pointer && this.pointer.x===p.x && this.pointer.y===p.y))return;
    const away=performance.now()-this.lastMove;this.lastMove=performance.now();this.pointer=p;
    if(away>=900000 && this.bond.stage>=2 && !this.capri.stowed){this.capri.wake();setTimeout(()=>{if(this.quiet()){this.capri.perform('hop');this.panel.say({kind:'idle',face:'look',line:pick(this.brain.t.bond.back),hold:3500});}},700);}
  }
  stage() {
    if(!this.newStage || !this.quiet())return;
    const n=this.newStage;this.newStage=0;const up=this.brain.t.bond.up[n],b=this.bond,c=this.capri;
    if(!['angry','sulk'].includes(b.feeling))b.feel('happy',{percent:b.percent});
    this.voice.play('star');
    co(function*(){yield c.perform('split');c.perform('hop');this.panel.say({kind:'done',badge:this.brain.t.state.info+' '+b.percent+'%',face:n>=3?'laugh':'look',line:fmt(up.line,{percent:b.percent}),quote:up.quote,progress:b.percent/100,hold:9000});}.call(this));
  }
  thrown({how,hard=0}) {
    const b=this.bond,c=this.capri,t=this.brain.t.thrown,now=performance.now();let face='smug',feel=null,line;
    if(how==='leap'){if(Math.random()<0.4)this.panel.say({kind:'info',face,line:pick(this.brain.t.screens.hello),hold:3000});return;}
    this.throws=this.throws.filter(t=>now-t<=120000);this.throws.push(now);
    if(this.throws.length>=3){this.throws=[];line=pick(t.angry);face='many';feel='angry';c.refuseUntil=now+25000;b.lose(1);if(c.mouse)c.zap(c.mouse.x,c.mouse.y);}
    else if(how==='ledge')line=pick(t.ledge);
    else if(how==='feet')line=pick(t.feet);
    else if(this.throws.length===2){line=pick(t.again);face='aside';feel='dizzy';}
    else if(hard>0.75 && Math.random()<0.5){line=pick(t.screen);face='laugh';feel='thrown';}
    else if(b.stage>=3){line=pick(t.fun);face='laugh';feel='fun';}
    else {line=pick(t.ow);face='wide';feel='thrown';}
    if(feel && b.feeling!=='angry')b.feel(feel);
    this.panel.say({kind:'info',face,line,hold:3800});
  }
  pc(kind,data={}) {
    if((kind==='low' || kind==='critical') && typeof data.level==='number')data=Object.assign({},data,{level:Math.round(data.level*100)});
    let lines=this.brain.t.pc[kind];
    if(kind==='plugIn'||kind==='plugOut')lines=lines[data.kind] || lines.device;
    const cue={hot:'charge',offline:'error',online:'hello'}[kind];
    if(lines && cue)this.voice.play(cue);
    if(lines)this.panel.say({kind:kind==='critical'?'error':'info',line:fmt(pick(lines),data),hold:4500});
  }
  remind(r) {
    const self=this;
    return co(function*(){
      const {capri:c,host:h,panel:p,reminders:rs}=self;
      if(h.quiet() || c.mode==='alert'){rs.snooze(r.id,60000);return;}
      const t=self.brain.t.remind,time=h.clock(r.at,self.brain.lang),missed=r.at<self.startedAt-60000;
      const line=missed?fmt(r.text?t.missed:t.missedBare,{text:r.text,time}):fmt(pick(r.text?t.now:t.nowBare),{text:r.text});
      let answered=false;
      self.voice.play('remind');
      const onAction=id=> {answered=true;if(id==='snooze'){rs.snooze(r.id,600000);p.hide();p.say({kind:'info',line:t.snoozed,hold:2500});}else {rs.remove(r.id);self.bond.add('remind',2);p.hide();p.say({kind:'info',line:pick(t.doneLine),hold:2500});}};
      if(self.chat && self.chat.open) {
        const until=performance.now()+30000;
        while(self.chat.open && self.chat.turn && performance.now()<until)yield sleep(500);
        if(self.chat.open && self.chat.turn){rs.snooze(r.id,60000);return;}
        if(self.chat.open) {
          const actions=[{id:'done',label:t.done,primary:true},{id:'snooze',label:t.snooze}];
          const done=id=>{answered=true;if(id==='snooze'){rs.snooze(r.id,600000);self.chat.interject(t.snoozed,[],null);}else {rs.remove(r.id);self.bond.add('remind',2);self.chat.interject(pick(t.doneLine),[],null);}};
          if(self.chat.interject(line,actions,done)) {p.current.onLeave=()=>{self.chat.close();if(!answered)rs.remove(r.id);};return;}
        }
      }
      if(c.stowed)yield c.unstow();c.wake();
      const until=performance.now()+8000;while((c.busy||c.dragging)&&performance.now()<until)yield sleep(100);
      if(c.busy || c.dragging || h.quiet() || c.mode==='alert'){rs.snooze(r.id,60000);return;}
      yield c.toPointer(yield h.cursor());c.perform('hop');const at=performance.now();
      if(!p.say({kind:'remind',face:'look',line,quote:missed?'':fmt(t.asked,{time}),hold:null,actions:[{id:'done',label:t.done,primary:true},{id:'snooze',label:t.snooze}],onAction,onLeave:()=>{if(!answered){if(performance.now()-at>2500)rs.remove(r.id);else rs.snooze(r.id,120000);}}}))rs.snooze(r.id,60000);
    }());
  }
  parsed(msg) {
    const t=this.brain.t.remind;let r=msg.reminder;
    if(!r && this.waitingWhen && Date.now()<this.waitingWhen.until && msg.when)r={at:msg.when,text:this.waitingWhen.text};
    if(!r){if(this.host.parseError)this.host.parseError();return false;}
    if(!r.at){this.waitingWhen={text:r.text,until:Date.now()+180000};if(this.host.askWhen)this.host.askWhen();return false;}
    this.waitingWhen=null;
    if(r.at<=Date.now() || r.at-Date.now()>604800000)return false;
    if(this.host.reminderSaved)this.host.reminderSaved();
    const saved=this.reminders.add(r.at,r.text),time=this.host.clock(r.at,this.brain.lang);
    this.panel.say({kind:'info',face:'smug',line:fmt(r.text?t.set:t.setBare,{time,text:r.text}),hold:8000,actions:[{id:'cancel',label:t.cancel}],onAction:()=>{this.reminders.remove(saved.id);this.panel.hide();this.panel.say({kind:'info',line:t.cancelled,hold:2500});}});
    return true;
  }
  flush() {this.bond.save(true);this.mission.save();}
}
