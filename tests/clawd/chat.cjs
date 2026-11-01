'use strict';
// Clawd chat sidecar: Codex CLI turns with exact flags, the brain protocol, screen pictures,
// history, busy retry, stop, stdin close, and no orphan CLI after the sidecar is SIGKILLed.
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..', '..', 'scripts', 'clawd');
const BRAIN = path.join(ROOT, 'brain.js');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ok = line => console.log('ok ' + line);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawd-chat-test-'));
const run = path.join(dir, 'run'), state = path.join(dir, 'state'), tools = path.join(dir, 'tools');
const trace = path.join(dir, 'trace.json'), calls = path.join(dir, 'calls.log'), grimLog = path.join(dir, 'grim.log');
const fakeCodex = path.join(tools, 'codex'), fakeGrim = path.join(tools, 'grim'), fakeHypr = path.join(tools, 'hyprctl');
const base = path.join(run, `clawd-chat-${process.getuid()}`);
const DISABLED = ['hooks', 'memories', 'plugins', 'apps', 'shell_tool', 'unified_exec', 'browser_use', 'computer_use'];

fs.mkdirSync(run, { recursive: true, mode: 0o700 });
fs.mkdirSync(tools);
fs.writeFileSync(fakeCodex, `#!/usr/bin/env node
const fs = require('fs');
const TRACE = ${JSON.stringify(trace)}, CALLS = ${JSON.stringify(calls)};
const a = process.argv.slice(2);
if (a[0] === 'login') {
  if (process.env.FAKE_SIGNED === '0') { console.error('Not logged in'); process.exit(1); }
  console.log('Logged in using ChatGPT');
  process.exit(0);
}
const prefix = 'model_instructions_file=';
const personaPath = JSON.parse(a.find(x => x.startsWith(prefix)).slice(prefix.length));
let text = '';
process.stdin.on('data', s => { text += s; });
process.stdin.on('end', () => {
  const images = [];
  a.forEach((x, k) => { if (x === '-i') images.push({ file: a[k + 1], bytes: fs.readFileSync(a[k + 1], 'utf8'), mode: fs.statSync(a[k + 1]).mode & 0o777 }); });
  fs.writeFileSync(TRACE, JSON.stringify({ args: a, text, cwd: process.cwd(), env: process.env, pid: process.pid, images, persona: fs.readFileSync(personaPath, 'utf8'), personaMode: fs.statSync(personaPath).mode & 0o777 }));
  fs.appendFileSync(CALLS, text.includes('RATE') ? 'RATE ' : 'call ');
  if (text.includes('HANG')) { setTimeout(() => {}, 60000); return; }
  if (text.includes('RATE')) { console.log(JSON.stringify({ type: 'turn.failed', error: { message: 'usage limit 429' } })); process.exitCode = 1; return; }
  console.log(JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: 'Clawd test' } }));
  console.log(JSON.stringify({ type: 'turn.completed' }));
});
`, { mode: 0o700 });
fs.writeFileSync(fakeGrim, `#!/bin/sh\necho "$@" >> ${JSON.stringify(grimLog)}\nprintf 'fake-jpeg'\n`, { mode: 0o700 });
fs.writeFileSync(fakeHypr, `#!/bin/sh\necho '[{"name":"DP-1","width":2560,"height":1440,"scale":1}]'\n`, { mode: 0o700 });

Object.assign(process.env, {
  XDG_RUNTIME_DIR: run, XDG_STATE_HOME: state, CLAWD_CODEX: fakeCodex, CLAWD_GRIM: fakeGrim, CLAWD_HYPRCTL: fakeHypr,
  OPENAI_API_KEY: 'must-not-inherit'
});
const codex = require(path.join(ROOT, 'codex.js'));

const readTrace = () => JSON.parse(fs.readFileSync(trace, 'utf8'));
const traceHas = text => { try { return readTrace().text.includes(text); } catch { return false; } };
const leftovers = () => (fs.existsSync(base) ? fs.readdirSync(base) : []);
const countRate = () => (fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').split('RATE').length - 1 : 0);
const until = async check => { const end = Date.now() + 15000; while (!check()) { if (Date.now() > end) throw new Error('timed out'); await sleep(20); } };
const alive = pid => { try { return !/^State:\s+Z/m.test(fs.readFileSync(`/proc/${pid}/status`, 'utf8')); } catch { return false; } };

// A brain sidecar with its JSON-line protocol: send requests, read every reply.
function session(env = {}) {
  const child = spawn(process.execPath, [BRAIN], { env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'ignore'] });
  const msgs = [];
  let buf = '', n = 0;
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', s => {
    buf += s;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      msgs.push(JSON.parse(buf.slice(0, i)));
      buf = buf.slice(i + 1);
    }
  });
  const send = (method, args = {}) => {
    const id = `r${++n}`;
    child.stdin.write(JSON.stringify({ t: 'chat.request', id, method, args }) + '\n');
    return id;
  };
  const reply = async id => { await until(() => msgs.some(m => m.t === 'chat.result' && m.id === id)); return msgs.find(m => m.t === 'chat.result' && m.id === id).data; };
  const call = async (method, args) => reply(send(method, args));
  return { child, msgs, send, reply, call };
}

(async () => {
  const sessions = [];
  try {
    // Codex turn in-process: exact flags, persona, env, stdin, cleanup
    const persona = 'You are Clawd, a tiny test mascot. Never call tools.';
    const answer = await codex.chat({ persona, prompt: 'Hello' }, () => {}, new AbortController().signal);
    assert.equal(answer, 'Clawd test');
    const t = readTrace();
    const shape = [...t.args];
    shape[shape.findIndex(x => x.startsWith('model_instructions_file='))] = '<persona>';
    shape[shape.indexOf('-C') + 1] = '<empty>';
    assert.deepEqual(shape, ['exec', '--json', '--ephemeral', '--skip-git-repo-check', '--ignore-user-config',
      '-s', 'read-only', '-c', 'approval_policy="never"', '-c', 'model_reasoning_effort="low"', '-c', '<persona>',
      ...DISABLED.flatMap(f => ['--disable', f]), '-c', 'web_search="disabled"', '-C', '<empty>', '-m', 'gpt-6-luna', '-']);
    assert.equal(path.basename(t.cwd), 'empty');
    assert.equal(t.env.OPENAI_API_KEY, undefined, 'API key not inherited');
    assert.ok(t.env.PATH, 'PATH kept');
    assert.match(t.persona, /Clawd/);
    assert.equal(t.personaMode, 0o600);
    assert.equal(t.text, 'Hello', 'prompt on stdin');
    assert.deepEqual(leftovers(), [], 'temporary dir cleaned');
    ok('codex: exact flags, persona file 0600, no inherited API key, stdin prompt, cleanup');

    await assert.rejects(codex.chat({ persona, prompt: 'RATE' }, () => {}, new AbortController().signal), e => e.code === 'busy');
    assert.deepEqual(leftovers(), [], 'cleaned after busy');
    ok('codex: usage limit maps to busy');

    const ctrl = new AbortController();
    const pending = codex.chat({ persona, prompt: 'HANG' }, () => {}, ctrl.signal);
    setTimeout(() => ctrl.abort(), 300);
    await assert.rejects(pending, e => e.code === 'stopped');
    assert.deepEqual(leftovers(), [], 'cleaned after abort');
    ok('codex: abort stops the CLI and cleans up');

    // status as a one-shot command, signed in and out
    const oneShot = extra => JSON.parse(spawnSync(process.execPath, [BRAIN, 'status'], { env: { ...process.env, ...extra }, encoding: 'utf8', timeout: 20000 }).stdout);
    assert.deepEqual(oneShot({ FAKE_SIGNED: '1' }), { ok: true, data: { signedIn: true } });
    assert.deepEqual(oneShot({ FAKE_SIGNED: '0' }), { ok: true, data: { signedIn: false } });
    ok('status: signedIn true and false');

    // the brain protocol
    const s = session();
    sessions.push(s);
    assert.deepEqual(await s.call('status'), { ok: true, signedIn: true });
    assert.deepEqual(await s.call('send', { text: 'Hello', context: 'desk: terminal' }), { ok: true, text: 'Clawd test' });
    assert.ok(s.msgs.some(m => m.t === 'chat.delta' && m.text === 'Clawd test'), 'answer streamed');
    let last = readTrace();
    assert.ok(last.text.startsWith('Conversation so far:\n'));
    assert.ok(last.text.endsWith("Context (live, do not recite):\ndesk: terminal\n\nUser's new message:\nHello"), 'context reaches stdin');
    const model = last.args.indexOf('-m');
    assert.deepEqual(last.args.slice(model, model + 2), ['-m', 'gpt-6-luna']);
    assert.equal(fs.statSync(path.join(state, 'serpantinum', 'clawd')).mode & 0o777, 0o700, 'state dir 0700');
    assert.equal(fs.statSync(path.join(state, 'serpantinum', 'clawd', 'chat.json')).mode & 0o777, 0o600, 'history file 0600');
    ok('brain: send with context, streamed answer, dir 0700 and file 0600');

    await s.call('send', { text: 'Again' });
    last = readTrace();
    assert.ok(last.text.includes('User: Hello\nClawd: Clawd test'), 'history sent back');
    assert.deepEqual(await s.call('history'), {
      ok: true, history: [
        { role: 'user', text: 'Hello' }, { role: 'clawd', text: 'Clawd test' },
        { role: 'user', text: 'Again' }, { role: 'clawd', text: 'Clawd test' }
      ]
    });
    ok('brain: history kept and sent back');

    const beforeRate = countRate();
    assert.deepEqual(await s.call('send', { text: 'RATE' }), { ok: false, error: 'usage limit 429', code: 'busy' });
    assert.equal(countRate() - beforeRate, 2, 'one retry after busy');
    ok('brain: busy retried once, then code busy');

    assert.deepEqual(await s.call('send', { text: 'look', look: true, output: 'DP-1; rm -rf ~' }), { ok: false, error: 'no screen', code: 'failed' });
    ok('brain: injected output name rejected');

    assert.deepEqual(await s.call('send', { text: 'What is on screen?', look: true, output: 'DP-1' }), { ok: true, text: 'Clawd test' });
    last = readTrace();
    assert.equal(last.images.length, 1);
    assert.equal(last.images[0].bytes, 'fake-jpeg', 'picture reached codex');
    assert.equal(last.images[0].mode, 0o600);
    const cut = last.args.indexOf('-C');
    assert.equal(last.args[cut - 2], '-i', '-i right before -C');
    assert.equal(last.args[cut - 1], last.images[0].file);
    assert.equal(fs.existsSync(last.images[0].file), false, 'picture deleted after use');
    assert.match(fs.readFileSync(grimLog, 'utf8'), /-o DP-1 .*-s 0\.5 /, 'picture capped at 1280 px');
    ok('brain: look attaches one JPEG with -i before -C and deletes it');

    const hangId = s.send('send', { text: 'HANG' });
    await until(() => traceHas('HANG'));
    assert.equal((await s.call('send', { text: 'Hi' })).code, 'running', 'one answer at a time');
    assert.deepEqual(await s.call('stop', { id: hangId }), { ok: true });
    assert.deepEqual(await s.reply(hangId), { ok: false, error: 'stopped', code: 'stopped' });
    ok('brain: running code while busy, stop aborts the answer');

    const tight = session({ CLAWD_CHAT_BUDGET_MS: '1500' });
    sessions.push(tight);
    const t0 = Date.now();
    const tr = await tight.call('send', { text: 'HANG' });
    assert.equal(tr.ok, false);
    assert.ok(Date.now() - t0 < 6000, 'total budget bounds the answer');
    tight.child.stdin.end();
    ok('brain: total budget bounds a hanging answer');

    assert.deepEqual(await s.call('forget'), { ok: true });
    assert.deepEqual(await s.call('history'), { ok: true, history: [] });
    ok('brain: forget clears history');

    // stdin closed: the sidecar exits
    const exited = new Promise(r => s.child.once('exit', r));
    s.child.stdin.end();
    await exited;
    ok('brain: exits when stdin closes');

    // abrupt death of the sidecar must not leave the CLI running
    const s2 = session();
    sessions.push(s2);
    const exited2 = new Promise(r => s2.child.once('exit', r));
    s2.send('send', { text: 'HANG' });
    await until(() => traceHas('HANG'));
    const cliPid = readTrace().pid;
    s2.child.kill('SIGKILL');
    await exited2;
    await sleep(200);
    assert.equal(alive(cliPid), false, 'no orphan CLI after SIGKILL of the sidecar');
    ok('brain: no orphan CLI after SIGKILL');

    console.log('CLAWD_CHAT_PASS status, codex flags, protocol, history, busy, stop, look, orphan control');
  } finally {
    for (const s of sessions) if (s.child.exitCode === null) s.child.kill('SIGKILL');
    fs.rmSync(dir, { recursive: true, force: true });
  }
})().catch(e => {
  console.error(e);
  process.exitCode = 1;
});
