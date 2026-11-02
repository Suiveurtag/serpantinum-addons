// The sidecar side of her guide/setup/look: a model download with its progress against a fake
// Ollama, the terminal on `ollama launch`, the screen picture handed to `codex exec -i` (and
// gone afterwards), Antigravity hooks in a temporary home, and what she refuses.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), http = require('node:http');

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'capri-setup-'));
  const bin = path.join(dir, 'bin'), trace = path.join(dir, 'trace');
  fs.mkdirSync(bin);
  const record = name => fs.writeFileSync(path.join(bin, name), `#!/bin/sh\necho "${name} $*" >> ${JSON.stringify(trace)}\n`, {mode: 0o700});
  ['ollama', 'kitty'].forEach(record);
  // codex: keeps the attached picture's bytes, answers like the CLI
  fs.writeFileSync(path.join(bin, 'codex'), `#!/usr/bin/env node
const fs=require('fs'),a=process.argv.slice(2),i=a.indexOf('-i');
if(a[0]==='login'){console.log('Logged in using ChatGPT');process.exit(0);}
fs.writeFileSync(${JSON.stringify(trace + '.codex')},JSON.stringify({args:a,image:i>=0?fs.readFileSync(a[i+1],'base64'):null}));
process.stdin.resume();process.stdin.on('end',()=>{console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'Je vois ton terminal.'}}));console.log(JSON.stringify({type:'turn.completed'}));});
`, {mode: 0o700});
  Object.assign(process.env, {PATH: bin + ':' + process.env.PATH, XDG_STATE_HOME: path.join(dir, 'state'), XDG_CONFIG_HOME: path.join(dir, 'config'), AGY_CONFIG_DIR: path.join(dir, 'agy')});
  delete process.env.TERMINAL;

  // a fake Ollama: one model to pull, in two pieces
  const server = http.createServer((req, res) => {
    if (req.url === '/api/tags') return res.end(JSON.stringify({models: [{name: 'gemma3:4b'}]}));
    if (req.url === '/api/pull') {
      res.write(JSON.stringify({status: 'pulling', digest: 'a', total: 100, completed: 50}) + '\n');
      res.write(JSON.stringify({status: 'pulling', digest: 'b', total: 300, completed: 300}) + '\n');
      return res.end(JSON.stringify({status: 'success'}) + '\n');
    }
    res.end('{}');
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  process.env.OLLAMA_HOST = '127.0.0.1:' + server.address().port;

  const {ChatService} = require('../../scripts/capri/chat-service');
  const setup = require('../../scripts/capri/setup');
  const sent = [];
  const s = new ChatService(m => sent.push(m));

  const pulled = await s.request({method: 'pullModel', args: {name: 'gemma3:4b'}});
  assert.equal(pulled.ok, true, JSON.stringify(pulled));
  const bar = sent.filter(m => m.t === 'setup.progress').map(m => [m.completed, m.total]);
  assert.deepEqual([bar[0], bar.at(-1)], [[50, 100], [350, 400]], 'pieces added up, once from empty to full');
  assert.equal(s.cfg.provider, 'ollama');
  assert.equal((await s.request({method: 'pullModel', args: {name: '../etc'}})).ok, false, 'only the offered models');
  assert.equal((await s.request({method: 'ollamaState'})).running, true);

  assert.deepEqual(await setup.launchThroughOllama('codex'), {ok: true});
  assert.deepEqual(await setup.launchThroughOllama('rm -rf'), {ok: false, error: 'unknown integration'});
  for (let i = 0; i < 20 && !fs.existsSync(trace); i++) await new Promise(r => setTimeout(r, 50));
  assert.match(fs.readFileSync(trace, 'utf8'), new RegExp(`^kitty ${bin}/ollama launch codex$`, 'm'), 'a terminal on ollama launch');

  // the picture goes to codex -i, never kept: one use, and the temporary file is gone
  s.cfg = {provider: 'chatgpt', chatModel: null, apiKeys: {}};
  const jpeg = Buffer.from('fake-jpeg').toString('base64');
  s.snaps.set('id', jpeg);
  const seen = await s.request({method: 'lookSay', args: {id: 'id', persona: 'Capri', prompt: 'What do you see?'}});
  {
    assert.equal(seen.ok, true, JSON.stringify(seen));
    assert.equal(seen.text, 'Je vois ton terminal.');
    const call = JSON.parse(fs.readFileSync(trace + '.codex'));
    assert.equal(call.image, jpeg, 'the picture reached codex');
    const at = call.args.indexOf('-i');
    assert.ok(at >= 0 && call.args[at + 2] === '-C', '-i before -C, the prompt stays on stdin');
    assert.equal(fs.existsSync(call.args[at + 1]), false, 'the picture file is removed');
  }
  assert.equal(s.snaps.has('id'), false, 'a picture is used once');
  assert.deepEqual(await s.request({method: 'lookSay', args: {id: 'id', persona: 'Capri', prompt: 'again'}}), {ok: false, error: 'the picture is gone'});
  assert.deepEqual(await s.request({method: 'lookSnap', args: {output: 'DP-1; rm -rf ~'}}), {ok: false, error: 'no screen'});

  // Antigravity hooks: installed and removed in its own folder, other hooks kept
  fs.mkdirSync(process.env.AGY_CONFIG_DIR, {recursive: true});
  fs.writeFileSync(path.join(process.env.AGY_CONFIG_DIR, 'hooks.json'), JSON.stringify({mine: {enabled: true}}));
  assert.equal((await s.request({method: 'installHooks', args: {assistant: 'agy'}})).ok, true);
  assert.equal((await s.request({method: 'hooksStatus', args: {assistant: 'agy'}})).installed, true);
  assert.equal((await s.request({method: 'claudeFound', args: {assistant: 'agy'}})), true);
  assert.equal((await s.request({method: 'uninstallHooks', args: {assistant: 'agy'}})).ok, true);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(process.env.AGY_CONFIG_DIR, 'hooks.json'))), {mine: {enabled: true}});

  // custom sounds: named after a cue, the right kinds of files only
  fs.mkdirSync(path.join(dir, 'config/serpantinum/capri/sounds'), {recursive: true});
  for (const f of ['done.mp3', 'Alert.WAV', 'notes.txt']) fs.writeFileSync(path.join(dir, 'config/serpantinum/capri/sounds', f), '');
  assert.deepEqual((await s.request({method: 'sounds'})).map(x => x.name).sort(), ['alert', 'done']);

  server.close();
  fs.rmSync(dir, {recursive: true, force: true});
  console.log('CAPRI_SETUP_PASS pull progress, ollama launch, codex picture, agy hooks, custom sounds, refusals');
})().catch(e => { console.error(e); process.exit(1); });
