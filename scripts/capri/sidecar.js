#!/usr/bin/env node
'use strict';

// Capri sidecar: JSON lines on stdout for the shell, JSON lines on stdin from it.
// Keeps the upstream HTTP bridge (127.0.0.1:47823) so the upstream hooks work unchanged.
// stdout carries protocol only: route every log line to stderr.
console.log = console.error;

const readline = require('node:readline');
const { createBridge } = require('./lib/bridge');
const { steamGame } = require('./world');
const {ChatService}=require('./chat-service');
const chat=new ChatService(emit);

const parser = import('./reminder-parser.mjs');

const PORT = Number(process.env.CAPRI_PORT) || 47823;

function emit(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

const server = createBridge({ port: PORT, onEvent: (evt) => {if(!require('./llm').isChatSession(evt.session_id))emit({ t: 'event', evt });} });
// A shell reload briefly overlaps the old helper. Retry binding after it releases the port.
let bindRetries = 0;
server.on('error', error => {
  if (error.code === 'EADDRINUSE' && bindRetries++ < 10) setTimeout(() => server.listen(PORT, '127.0.0.1'), 500);
});

const input = readline.createInterface({ input: process.stdin });
input.on('line', (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if(chat.handle(message))return;
  if (message?.t === 'foreground') emit({ t: 'pc', game: steamGame(message) });
  if (message?.t === 'reminder.parse' && typeof message.text === 'string' && message.text.length <= 2000) {
    parser.then(p => { const now = Date.now(), when = p.parseWhen(message.text, now)?.at; emit({t:'reminder.parsed', id:message.id, reminder:p.parseReminder(message.text, now), when:when - now >= 5000 && when - now <= 604800000 ? when : null}); });
  }
  if (message?.t === 'ping') emit({ t: 'pong', id: message.id });
});
// The shell closes stdin when Capri turns off or the shell exits: never outlive it.
function shutdown() { chat.stop(); server.close(); setTimeout(()=>process.exit(0),100).unref(); }
input.on('close', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
