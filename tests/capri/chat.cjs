'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),http=require('node:http');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'capri-chat-test-'));
process.env.XDG_STATE_HOME=path.join(dir,'state');process.env.XDG_RUNTIME_DIR=dir;
const {spawn}=require('node:child_process');
const {ChatService}=require('../../scripts/capri/chat-service'),{score,webUrl,Actions}=require('../../scripts/capri/actions'),codex=require('../../scripts/capri/codex');
(async()=>{let calls=0,mode='success',seen=[];const server=http.createServer(async(req,res)=>{
  if(req.url==='/v1/models'){res.end(JSON.stringify({data:[{id:'busy'},{id:'fallback'}]}));return;}
  let body='';for await(const chunk of req)body+=chunk;const m=JSON.parse(body);seen.push(m);calls++;
  if(mode==='busy'&&m.model==='busy'){res.writeHead(429);res.end('{"error":{"message":"busy"}}');return;}
  if(mode==='partial'){res.writeHead(200,{'content-type':'text/event-stream'});res.write('data: {"choices":[{"delta":{"content":"Half"}}]}\n\n');res.write('data: {"error":{"message":"overloaded"}}\n\n');res.end();return;}
  res.writeHead(200,{'content-type':'text/event-stream'});res.write('data: {"choices":[{"delta":{"content":"Salut, "}}]}\n\n');res.end('data: {"choices":[{"delta":{"content":"choom!"}}]}\n\ndata: [DONE]\n\n');
});await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}/v1`,deltas=[],s=new ChatService(m=>deltas.push(m));
try {
  const status=await s.configure({provider:'custom',customUrl:url,apiKey:'private-test-key'});assert(status.ok);assert(!JSON.stringify(s.publicConfig()).includes('private-test-key'));assert.equal(fs.statSync(path.join(s.dir,'chat.json')).mode&0o777,0o600);
  const old=s.cfg;await assert.rejects(s.configure({provider:'openai'}));assert.equal(s.cfg,old);
  const messages=[{role:'system',content:'Capri persona'},{role:'user',content:'Hello'}];assert.equal((await s.send({id:1,messages})).text,'Salut, choom!');assert.equal(deltas.length,2);assert.deepEqual(seen[0].messages,messages);
  mode='busy';calls=0;s.cfg.chatModel='busy';assert.equal((await s.send({id:2,messages})).model,'fallback');assert.equal(calls,3);
  mode='partial';calls=0;await assert.rejects(s.send({id:3,messages}));assert.equal(calls,1,'never retry after a delta');
  await s.request({method:'remember',args:{history:Array.from({length:80},()=>({role:'assistant',content:'hi'}))}});assert.equal(new ChatService(()=>{}).memory.history.length,60);await s.request({method:'forget'});assert.equal(s.memory.history.length,0);
  const {lines}=require('../../scripts/capri/stream');
  const encoded=Buffer.from('é\nfinal');const parsed=[];for await(const line of lines((async function*(){yield encoded.subarray(0,1);yield encoded.subarray(1,3);yield encoded.subarray(3);})()))parsed.push(line);
  assert.deepEqual(parsed,['é','final']);
  const intent=await import('../../scripts/capri/intent.mjs');
  for(const text of ['appelle-moi Éléonore','call me Alice','llámame Rosa','me chama de Luís','зови меня Саша'])assert.equal(intent.parseIntent(text).kind,'name');
  assert.equal(intent.parseIntent('remember that I like cats').kind,'memo');assert.equal(intent.parseIntent('rappelle-moi de boire dans 10 minutes').kind,'remind');assert.equal(intent.parseIntent('dans 10 minutes',[],{text:'boire',until:Date.now()+10000}).text,'boire');
  for(const text of ['in 1 second','in 999 hours'])assert.equal(intent.parseIntent(text,[],{text:'water',until:Date.now()+10000}).at,null);
  assert.equal(intent.parseIntent('close firefox',[{name:'firefox',label:'Firefox'}]).kind,'close');assert.equal(intent.parseIntent('pause').action,'pause');assert.equal(intent.parseIntent('find my blender project').kind,'files');
  assert(score('ouvre firefox','Firefox')>0);assert.throws(()=>webUrl('file:///etc/passwd'));assert.throws(()=>webUrl('javascript:alert(1)'));assert.equal(webUrl('example.com'),'https://example.com/');
  for(const bad of ['http://127.0.0.1:8080/admin','http://192.168.1.1/','http://localhost./','http://[::1]/','http://169.254.169.254/'])assert.throws(()=>webUrl(bad),bad);
  const a=new Actions();await assert.rejects(a.openFile('/etc/passwd'));await assert.rejects(a.launch({kind:'app',desktop:'injected'}));await assert.rejects(a.media('$(touch /tmp/capri-should-not-exist)'));
  const executable=path.join(dir,'run.sh');fs.writeFileSync(executable,'echo hi',{mode:0o700});assert((await a.file(executable)).risky);
  // Fake CLI proves exact invocation, stdin history, no inherited credentials, JSONL/errors and cancellation.
  const bin=path.join(dir,'bin');fs.mkdirSync(bin);const trace=path.join(dir,'trace.json');
  fs.writeFileSync(path.join(bin,'codex'),`#!/usr/bin/env node\nconst fs=require('fs');let text='';process.stdin.on('data',s=>text+=s);process.stdin.on('end',()=>{fs.writeFileSync(${JSON.stringify(trace)},JSON.stringify({args:process.argv.slice(2),text,cwd:process.cwd(),env:process.env,pid:process.pid}));if(text.includes('HANG'))setTimeout(()=>{},60000);else if(text.includes('RATE')){console.log(JSON.stringify({type:'turn.failed',error:{message:'usage limit 429'}}));process.exitCode=1;}else {console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'Capri test'}}));process.stdout.write(JSON.stringify({type:'turn.completed'}));}});\n`,{mode:0o700});
  const oldPath=process.env.PATH;process.env.PATH=bin+':'+oldPath;process.env.OPENAI_API_KEY='must-not-inherit';
  assert.equal(await codex.chat({},{messages},()=>{},new AbortController().signal),'Capri test');const traceData=JSON.parse(fs.readFileSync(trace));const args=traceData.args;
  for(const flag of ['--json','--ephemeral','--skip-git-repo-check','--ignore-user-config'])assert(args.includes(flag));assert.equal(args[args.indexOf('-s')+1],'read-only');for(const f of ['hooks','memories','plugins','apps'])assert(args.includes(f));assert(!traceData.env.OPENAI_API_KEY);assert.equal(traceData.text.includes('Hello'),true);assert(!fs.existsSync(traceData.cwd),'temporary prompt/workspace cleaned');
  await assert.rejects(codex.chat({},{messages:[...messages.slice(0,-1),{role:'user',content:'RATE'}]},()=>{},new AbortController().signal),e=>e.code==='busy');
  const ctrl=new AbortController();const pending=codex.chat({},{messages:[messages[0],{role:'user',content:'HANG'}]},()=>{},ctrl.signal);setTimeout(()=>ctrl.abort(),150);await assert.rejects(pending);// Abrupt sidecar death must kill the CLI too (the Linux parent-death supervisor).
  fs.rmSync(trace,{force:true});
  const worker=path.join(dir,'worker.cjs');fs.writeFileSync(worker,`require(${JSON.stringify(require.resolve('../../scripts/capri/codex'))}).chat({}, {messages:[{role:'system',content:'Capri'},{role:'user',content:'HANG'}]},()=>{},new AbortController().signal);`);
  const parent=spawn(process.execPath,[worker],{stdio:'ignore'});
  for(let n=0;n<40&&!fs.existsSync(trace);n++)await new Promise(r=>setTimeout(r,25));
  assert(fs.existsSync(trace),'CLI launched');const cliPid=JSON.parse(fs.readFileSync(trace)).pid;
  parent.kill('SIGKILL');await new Promise(r=>parent.on('exit',r));await new Promise(r=>setTimeout(r,150));
  let alive=false;try{alive=!/^State:\s+Z/m.test(fs.readFileSync(`/proc/${cliPid}/status`,'utf8'));}catch{}
  assert.equal(alive,false,'no orphan CLI after abrupt sidecar exit');
  process.env.PATH=oldPath;
  console.log('CAPRI_CHAT_PASS providers, fallback, streaming, memory, 5 languages, Linux boundaries, Codex isolation and abort');
}finally{server.closeAllConnections();server.close();s.stop();fs.rmSync(dir,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
