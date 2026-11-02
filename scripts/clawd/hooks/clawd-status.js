#!/usr/bin/env node
'use strict';

// Claude Code status line -> Clawd: relays the session's stats (model, effort, context, cost, rate limits) as one
// "Status" line into clawd.sock. Never fails, never delays the status line: the socket is abandoned after 500 ms.
// Usage (settings.json statusLine.command): node clawd-status.js [-- <original status line command>]
// Wrapped, the original runs through sh -c with the same stdin and its stdout is forwarded untouched; unwrapped, prints nothing.

const net = require('node:net');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { ancestors, text, clean, SOCKET } = require('./clawd-hook.js');

const args = process.argv.slice(2);
const ORIGINAL = args[0] === '--' && args.length > 1 ? args.slice(1).join(' ') : null;
const MAX = 8 * 1024 * 1024;

const num = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : undefined);
const obj = (value) => (value && typeof value === 'object' ? value : {});

function status(evt) {
  const cwd = evt.cwd || obj(evt.workspace).current_dir;
  const limits = obj(evt.rate_limits);
  const five = obj(limits.five_hour);
  return {
    agent: 'claude', event: 'Status', session_id: text(evt.session_id, 80), dir: text(typeof cwd === 'string' ? path.basename(cwd) : '', 40),
    model: clean(obj(evt.model).display_name, 40), effort: clean(obj(evt.effort).level, 16),
    ctx: num(obj(evt.context_window).used_percentage), ctx_size: num(obj(evt.context_window).context_window_size), cost: num(obj(evt.cost).total_cost_usd),
    five_hour: num(five.used_percentage), seven_day: num(obj(limits.seven_day).used_percentage), five_hour_resets: num(five.resets_at), seven_day_resets: num(obj(limits.seven_day).resets_at),
  };
}

function run() {
  let pending = ORIGINAL ? 2 : 1;  // the socket send, plus the wrapped status line when there is one
  const settle = () => { if (--pending <= 0) process.exit(0); };
  let sent = false;
  const sendDone = () => { if (!sent) { sent = true; settle(); } };
  const chunks = [];
  let size = 0;
  const finish = () => {
    const raw = Buffer.concat(chunks);
    if (ORIGINAL) {
      let child;
      try { child = spawn('sh', ['-c', ORIGINAL], { stdio: ['pipe', 'inherit', 'inherit'] }); } catch { child = null; }
      if (child) {
        let ended = false;  // a failed spawn may emit both 'error' and 'close'
        const childDone = () => { if (!ended) { ended = true; settle(); } };
        child.on('error', childDone);
        child.on('close', childDone);
        child.stdin.on('error', () => {});  // the original may not read its stdin
        child.stdin.end(raw);
      } else settle();
    }
    setTimeout(sendDone, 500).unref();
    let evt;
    try { evt = JSON.parse(raw.toString('utf8')); } catch { return sendDone(); }
    if (!evt || typeof evt !== 'object' || Array.isArray(evt)) return sendDone();
    const socket = net.createConnection(SOCKET);
    socket.on('error', sendDone);
    socket.on('close', sendDone);
    socket.end(JSON.stringify({ ...status(evt), pids: ancestors(process.ppid) }) + '\n');
  };
  process.stdin.on('data', (chunk) => {
    if (size > MAX) return;
    size += chunk.length;
    chunks.push(chunk);
    if (size > MAX) { process.stdin.pause(); finish(); }
  });
  process.stdin.on('error', () => { if (size <= MAX) { size = MAX + 1; finish(); } });
  process.stdin.on('end', () => { if (size <= MAX) finish(); });
}

module.exports = { status };
if (require.main === module) run();
