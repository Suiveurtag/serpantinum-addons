#!/usr/bin/env node
'use strict';

// Clawd brain: JSON lines on stdout for the desktop pet, JSON lines on stdin from it.
// stdout carries protocol only: route every log line to stderr.
console.log = console.error;

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');
const { execFile } = require('node:child_process');
const codex = require('./codex');

const PERSONA = [
  "You are Clawd, the small orange pixel mascot of Claude Code living on the user's Serpantinum (Hyprland) desktop.",
  'Playful, kind, brief: at most 3 short sentences, plain text, no markdown.',
  "Always reply in the language of the user's message.",
  'If a screenshot is attached, describe or answer about the screen, and ignore the small orange pixel creature and the terminal-style chat box: that is you.',
  'Never call tools or inspect files.'
].join('\n');

const KEEP = 60;
const SEND = 20;
const MAX_TEXT = 2000;
const MAX_CONTEXT = 4000;
const BUSY_RETRY_MS = 1500;
const BUDGET_MS = Number(process.env.CLAWD_CHAT_BUDGET_MS) || 85000; // whole answer, retry included; the desktop gives up at 95 s
const MIN_RETRY_MS = 5000;
const CODES = ['signin', 'busy', 'stopped', 'failed', 'running'];

let history = [];
let generation = 0; // bumped by forget: an answer that began before it is not remembered
let current = null; // { id, ctrl } of the one answer running

const bin = () => process.env.CLAWD_CODEX || 'codex';
const stateDir = () => path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'serpantinum', 'clawd');
const chatFile = () => path.join(stateDir(), 'chat.json');
const fail = (message, code = 'failed') => Object.assign(new Error(message), { code });

function emit(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

function readHistory() {
  try {
    const list = JSON.parse(fs.readFileSync(chatFile(), 'utf8')).history;
    return Array.isArray(list)
      ? list.filter(m => m && (m.role === 'user' || m.role === 'clawd') && typeof m.text === 'string').slice(-KEEP)
      : [];
  } catch {
    return [];
  }
}

function saveHistory(list) {
  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.chmodSync(dir, 0o700);
  const file = chatFile(), tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify({ history: list }, null, 2), { mode: 0o600 });
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, file);
}

function prompt(text, context) {
  const past = history.slice(-SEND).map(m => `${m.role === 'user' ? 'User' : 'Clawd'}: ${m.text}`).join('\n');
  return `Conversation so far:\n${past}\n\nContext (live, do not recite):\n${context}\n\nUser's new message:\n${text}`;
}

function capture(file, args) {
  return new Promise((resolve, reject) => execFile(file, args, {
    encoding: 'buffer',
    maxBuffer: 32 * 1024 * 1024,
    timeout: 10000
  }, (err, out) => (err ? reject(err) : resolve(out))));
}

// The screen the user is on, 1280 px wide at most, JPEG kept in memory only.
async function snapshot(output) {
  if (typeof output !== 'string' || !/^[\w.-]+$/.test(output)) throw fail('no screen');
  const monitors = JSON.parse(String(await capture(process.env.CLAWD_HYPRCTL || 'hyprctl', ['monitors', '-j'])));
  const mon = monitors.find(o => o.name === output);
  if (!mon || !(mon.width > 0)) throw fail('no screen');
  const scale = Math.min(1, 1280 / mon.width);
  const jpeg = await capture(process.env.CLAWD_GRIM || 'grim', ['-o', output, '-t', 'jpeg', '-q', '72', '-s', String(Math.floor(scale * 1000) / 1000), '-']);
  if (!jpeg.length) throw fail('no picture of the screen');
  return jpeg.toString('base64');
}

function signedIn() {
  return new Promise(resolve => execFile(bin(), ['login', 'status'], { timeout: 10000 }, (err, out, stderr) => {
    resolve(!err && /Logged in using ChatGPT/.test(String(out) + String(stderr)));
  }));
}

function pause(ms, signal) {
  return new Promise(resolve => {
    const t = setTimeout(resolve, ms);
    signal.addEventListener('abort', () => {
      clearTimeout(t);
      resolve();
    }, { once: true });
  });
}

async function send(id, args) {
  if (current) return { ok: false, error: 'An answer is already running', code: 'running' };
  const text = args.text;
  const context = args.context === undefined ? '' : args.context;
  if (typeof text !== 'string' || !text.trim() || text.length > MAX_TEXT) throw fail('Message too long or empty');
  if (typeof context !== 'string' || context.length > MAX_CONTEXT) throw fail('Context too long');
  const ctrl = new AbortController();
  const gen = generation, deadline = Date.now() + BUDGET_MS;
  current = { id, ctrl };
  try {
    const images = args.look === true ? [await snapshot(args.output)] : [];
    const question = prompt(text, context);
    let streamed = false;
    const ask = () => codex.chat({ persona: PERSONA, prompt: question, images, timeoutMs: Math.max(1000, deadline - Date.now()) }, piece => {
      if (!ctrl.signal.aborted) {
        streamed = true;
        emit({ t: 'chat.delta', id, text: piece });
      }
    }, ctrl.signal);
    let answer;
    try {
      answer = await ask();
    } catch (e) {
      if (ctrl.signal.aborted || streamed || e.code !== 'busy' || deadline - Date.now() < BUSY_RETRY_MS + MIN_RETRY_MS) throw e;
      await pause(BUSY_RETRY_MS, ctrl.signal);
      ctrl.signal.throwIfAborted();
      answer = await ask();
    }
    if (gen === generation) {
      history = [...history, { role: 'user', text }, { role: 'clawd', text: answer }].slice(-KEEP);
      try {
        saveHistory(history);
      } catch {
        // the answer still reaches the user; only the memory of it is lost
      }
    }
    return { ok: true, text: answer };
  } catch (e) {
    if (ctrl.signal.aborted) return { ok: false, error: 'stopped', code: 'stopped' };
    let code = e.code;
    if (!CODES.includes(code)) code = (await signedIn()) ? 'failed' : 'signin';
    return { ok: false, error: String(e.message || e).slice(0, 300), code };
  } finally {
    current = null;
  }
}

async function run(id, method, args) {
  switch (method) {
    case 'send':
      return send(id, args);
    case 'history':
      return { ok: true, history: history.map(({ role, text }) => ({ role, text })) };
    case 'forget':
      if (current) current.ctrl.abort();
      generation++;
      history = [];
      try {
        saveHistory(history);
      } catch {
        // nothing stored, nothing to forget
      }
      return { ok: true };
    case 'stop':
      if (current && current.id === args.id) current.ctrl.abort();
      return { ok: true };
    case 'status':
      return { ok: true, signedIn: await signedIn() };
    default:
      throw fail('Unknown method');
  }
}

function handle(m) {
  if (!m || typeof m !== 'object' || m.t !== 'chat.request') return;
  if (typeof m.id !== 'string' || m.id.length > 80) return;
  const args = m.args && typeof m.args === 'object' ? m.args : {};
  Promise.resolve()
    .then(() => run(m.id, m.method, args))
    .catch(e => ({ ok: false, error: String(e.message || e).slice(0, 300), code: CODES.includes(e.code) ? e.code : 'failed' }))
    .then(data => emit({ t: 'chat.result', id: m.id, data }));
}

function serve() {
  history = readHistory();
  const input = readline.createInterface({ input: process.stdin });
  input.on('line', line => {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }
    handle(message);
  });
  // The desktop closes stdin when Clawd turns off: never outlive it, and stop any answer in progress.
  const shutdown = () => {
    if (current) current.ctrl.abort();
    process.exit(0);
  };
  input.on('close', shutdown);
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

if (process.argv[2] === 'status') {
  signedIn().then(value => process.stdout.write(JSON.stringify({ ok: true, data: { signedIn: value } }) + '\n'));
} else {
  serve();
}
