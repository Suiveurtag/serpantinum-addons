import assert from 'node:assert/strict';
import * as U from '../../payload/capri/js/util.mjs';
import {Brain} from '../../payload/capri/js/brain.mjs';
import {Panel} from '../../payload/capri/js/panel.mjs';
import {Mission} from '../../payload/capri/js/mission.mjs';
import {Bond,Jealousy} from '../../payload/capri/js/bond.mjs';
import {Runtime,rivalKeys} from '../../payload/capri/js/brain-runtime.mjs';
import {linesFor} from '../../payload/capri/js/lines.mjs';
import {Reminders} from '../../payload/capri/js/reminders.mjs';
import {parseReminder,parseWhen} from '../../scripts/capri/reminder-parser.mjs';
const originalNow=Date.now;let now=Date.now();Date.now=()=>now;
const advance=async ms=>{now+=ms;U.pump();for(let i=0;i<12;i++)await Promise.resolve();};
const storage=new Map();U.storage.getItem=k=>storage.get(k)||null;U.storage.setItem=(k,v)=>storage.set(k,v);
const config={};let quiet=false,changes=0;
const host={quiet:()=>quiet,changed:()=>changes++,setConfig:p=>Object.assign(config,p),date:()=>'',clock:()=>'',cursor:()=>Promise.resolve(null),get:(k,d)=>config[k.toLowerCase()]??d,lang:()=> 'en',menu(){}};
const panel=new Panel(host),mission=new Mission();
const calls=[];
const c={windows:{fg:'work',wins:[{id:'work',x:100,y:100,w:500,h:400,max:false}]},mode:'idle',stance:'stand',stowed:false,busy:false,act:null,view:{w:1280,h:720},pos:{x:800,y:700},free:true,
 wake(){calls.push('wake');},attend(){},goToWork(){this.mode='work';},setMode(m){this.mode=m;},pulse(){},spark(){},hurt(){calls.push('hurt');},perform(){return Promise.resolve(true);},towardCenter(){return 1;},stopPointing(){calls.push('unpoint');},canPoint(){return true;},pointAt(){calls.push('point');return Promise.resolve(true);},toPointer(){return Promise.resolve(null);},teleport(){return Promise.resolve(true);},spot(){return {};},celebrate({onSpeak}){onSpeak();},earnUplink(){calls.push('uplink');},flourish(){},gaze(){return true;},jealous(){return Promise.resolve(true);},head(){return {x:1,y:1,top:1};}};
const brain=new Brain({capri:c,panel,mission,host,voice:{play(){}},lang:'en',assistant:'codex'});brain.linked=true;
const event=(name,more={})=>brain.handle({hook_event_name:name,session_id:'codex:shared',cwd:'/p/test',...more});
await event('UserPromptSubmit',{prompt:'Do work'});assert.equal(brain.sessions.get('codex:shared').working,true);
await event('PreToolUse',{tool_name:'Edit',tool_input:{file_paths:['a.js','b.js'],file_path:'a.js'}});assert.equal(brain.sessions.get('codex:shared').files.size,2);
c.windows.fg='elsewhere';await event('Notification',{notification_type:'permission_prompt',message:'Approve?'});
assert.equal(c.mode,'alert');assert.equal(panel.current.hold,null);assert.equal(panel.current.kind,'alert');assert.ok(calls.includes('point'));
await event('PostToolUse');assert.equal(c.mode,'work');assert.ok(calls.includes('unpoint'));
panel.hide();await advance(16000);brain.thinkTick();assert.equal(panel.tickerAction.thinking,true);
await advance(26000);brain.thinkTick();assert.equal(brain.thinking.said,1);
await advance(80000);brain.thinkTick();assert.equal(brain.thinking.said,2);
await event('PostToolUseFailure',{error:'Exit code 1\nUseful failure',tool_name:'Bash'});assert.equal(mission.day.errors,1);assert.equal(panel.current.log[1].target,'Useful failure');
await event('Stop',{last_assistant_message:'# Answer\n**Done**\n- item'});assert.equal(panel.current.reply,'Answer\nDone\n• item');assert.equal(panel.current.hold,null);assert.equal(mission.day.missions,1);assert.equal(mission.day.files,2);
brain.onWindows({fg:'work'});assert.equal(panel.visible,false);
const before=JSON.stringify(mission.day);await brain.handle({hook_event_name:'UserPromptSubmit',session_id:'demo',demo:true});await brain.handle({hook_event_name:'Stop',session_id:'demo',demo:true});assert.equal(JSON.stringify(mission.day),before);
await event('SessionEnd');assert.equal(brain.sessions.has('codex:shared'),false);
let rival='';brain.onRival=k=>rival=k;await brain.handle({hook_event_name:'PreToolUse',session_id:'claude-real'});assert.equal(rival,'');assert.equal(brain.sessions.has('claude-real'),true);assert.equal(brain.name,'Claude');await brain.handle({hook_event_name:'PreToolUse',session_id:'agy:x'});assert.equal(rival,'gemini');assert.equal(brain.sessions.has('agy:x'),false);
for(const lang of ['fr','en','es','pt','ru']) {
 for(const assistant of ['codex','agy']) {const t=linesFor(lang,assistant);assert.ok(t.report.title);const values=v=>typeof v==='string'?v:v&&typeof v==='object'?Object.values(v).map(values).join(' '):'';assert.ok(!/Claude|settings\.json|\.claude/.test(values(t)));}
}
assert.equal(U.pluralCategory(21,'ru'),'one');assert.equal(U.pluralCategory(12,'ru'),'many');assert.equal(U.pluralCategory(24,'ru'),'few');
for(const text of ['rappelle-moi dans 2 minutes de boire','remind me in 2 minutes to drink','recuérdame en 2 minutos beber','me lembra em 2 minutos beber','напомни через 2 минуты пить']) {const r=parseReminder(text,now);assert.equal(r.at,now+120000,text);assert.ok(r.text);}
assert.equal(parseReminder('remind me to drink',now).at,null);assert.equal(parseReminder('remind me in 8 days',now).at,null);assert.ok(parseWhen('at 6pm',now).at>now);
const bond=new Bond({host,data:{xp:299}});let stage=0;bond.onStage=n=>stage=n;bond.add('click',10);assert.equal(bond.data.xp,303);assert.equal(stage,2);bond.add('click',10);assert.equal(bond.data.xp,303);bond.lose(100);assert.equal(bond.data.xp,300);
for(const text of ['sorry','désolée','lo siento','foi mal','прости']) {bond.feel('angry');assert.equal(bond.heard(text),true,text);}
bond.feel('angry');assert.equal(bond.heard('unsorrying'),false);
const jealous=new Jealousy({capri:c,panel,brain,bond,chat:{open:false},guide:{running:false}});panel.hide();c.mode='idle';jealous.onWindows({fg:'rival',ai:['codex','chatgpt']});assert.equal(jealous.front.key,'chatgpt');await advance(4000);assert.ok(jealous.noticed.chatgpt);assert.ok(jealous.lately.chatgpt>=1000);assert.equal(jealous.rivalOf(['codex']),null);
assert.deepEqual(rivalKeys('ChatGPT / Claude','browser'),['chatgpt','claude']);
const rs=new Reminders({host});const rem=rs.add(now-1000,'drink');let fired=0;rs.onDue=()=>fired++;rs.check();rs.check();assert.equal(fired,1);rs.snooze(rem.id,600000);assert.equal(rs.firing.size,0);assert.equal(rs.list[0].at,now+600000);rs.remove(rem.id);assert.equal(rs.list.length,0);
panel.hide();panel.say({kind:'alert',line:'!',hold:null});assert.equal(panel.say({kind:'idle',line:'x'}),false);await advance(2700);assert.equal(panel.say({kind:'idle',line:'x'}),true);panel.hide();panel.say({kind:'report',report:{},line:'r',hold:null});await advance(3000);assert.equal(panel.say({kind:'work',line:'x'}),false);
quiet=true;assert.equal(panel.say({kind:'remind',line:'x'}),false);quiet=false;
// Rehydrate the actual stores and ensure debounced writes did not lose the last action.
mission.save();assert.equal(new Mission().day.missions,1);bond.save(true);assert.equal(config.bond.xp,300);
U.reset();storage.clear();config.reminders=[];quiet=false;c.windows.fg='work';c.busy=false;c.mode='idle';c.act=null;
const runtime=new Runtime(c,host);runtime.panel.hide();runtime.pc('low',{level:.12});assert.ok(runtime.panel.current.line.includes('12%'));runtime.panel.hide();
const rr=runtime.reminders.add(now-100,'water');runtime.reminders.check();await advance(100);
assert.equal(runtime.panel.current.kind,'remind');runtime.panel.action('done');assert.equal(runtime.reminders.list.length,0);assert.equal(runtime.bond.data.caps.remind,2);
quiet=true;await runtime.brain.handle({hook_event_name:'UserPromptSubmit',session_id:'codex:q'});await runtime.brain.handle({hook_event_name:'Stop',session_id:'codex:q'});assert.equal(runtime.mission.day.missions,1);quiet=false;
runtime.parsed({reminder:{at:null,text:'water'}});assert.ok(runtime.waitingWhen);assert.equal(runtime.parsed({when:now+600000}),true);assert.equal(runtime.reminders.list.length,1);
// A dismissed quick reminder returns in 2 minutes; a readable one counts as seen.
runtime.panel.hide();runtime.reminders.list[0].at=now-1;runtime.reminders.check();await advance(100);runtime.panel.hide();assert.ok(runtime.reminders.list[0].at>=now+120000);
runtime.reminders.list[0].at=now-1;runtime.reminders.check();await advance(100);await advance(2600);runtime.panel.hide();assert.equal(runtime.reminders.list.length,0);
U.reset();Date.now=originalNow;
console.log('CAPRI_BRAIN_PASS',changes);
