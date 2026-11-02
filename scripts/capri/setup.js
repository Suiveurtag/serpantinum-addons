'use strict';

// Linux port of capri-desktop src/main/setup.js (upstream LICENSE beside): setting her up with
// buttons. There is no winget here, so like upstream off Windows she sends you to Ollama's site
// when it isn't installed; she can still wake it, fetch a model with its progress, and open a
// terminal on `ollama launch claude|codex`.

const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFile } = require('node:child_process');
const ollama = require('./ollama');

const MODELS = [
  { name: 'gemma3:4b', bytes: 3.3e9 }, // better in languages other than English, and it can see
  { name: 'llama3.2', bytes: 2.0e9 },  // lighter
];

const KEY_PAGES = {
  groq: 'https://console.groq.com/keys',
  gemini: 'https://aistudio.google.com/apikey',
  openrouter: 'https://openrouter.ai/keys',
  openai: 'https://platform.openai.com/api-keys',
  mistral: 'https://console.mistral.ai/api-keys',
  deepseek: 'https://platform.deepseek.com/api_keys',
};

// argv after the terminal's name to run a command in it
const TERMINALS = [
  ['xdg-terminal-exec', []], ['kitty', []], ['foot', []], ['ghostty', ['-e']], ['alacritty', ['-e']],
  ['wezterm', ['start', '--']], ['konsole', ['-e']], ['gnome-terminal', ['--']], ['xterm', ['-e']],
];

function which(cmd) {
  return new Promise((resolve) => execFile('which', [cmd], { timeout: 5000 }, (err, out) => resolve(err ? null : String(out).trim() || null)));
}

const detach = (file, args) => {
  const child = spawn(file, args, { detached: true, stdio: 'ignore' });
  child.on('error', () => {});
  child.unref();
  return child;
};

async function ollamaState() {
  const models = await ollama.models().catch(() => null);
  if (models) return { running: true, installed: true, models, winget: false };
  return { running: false, installed: Boolean(await which('ollama')), models: null, winget: false };
}

// No package manager she may drive without root: the site, as upstream does off Windows.
async function installOllama() {
  return { ok: false, error: 'Install Ollama with your package manager (e.g. pacman -S ollama), or from ollama.com.' };
}

async function startOllama() {
  const cli = await which('ollama');
  if (!cli) return { ok: false, error: 'Ollama is not installed' };
  detach(cli, ['serve']);
  for (let i = 0; i < 40; i++) {
    if (await ollama.models().catch(() => null)) return { ok: true };
    await new Promise((r) => setTimeout(r, 750));
  }
  return { ok: false, error: 'Ollama did not answer' };
}

// Ollama sends its pieces one after the other: onProgress({ completed, total }) adds them up.
async function pullModel(name, onProgress, signal) {
  const res = await fetch(`${ollama.base()}/api/pull`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: name, stream: true }),
    signal,
  });
  if (!res.ok) throw new Error(`Ollama answered ${res.status}`);
  const pieces = new Map();
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of res.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      if (msg.error) throw new Error(msg.error);
      if (msg.digest && msg.total) pieces.set(msg.digest, { completed: msg.completed || 0, total: msg.total });
      let completed = 0;
      let total = 0;
      for (const p of pieces.values()) {
        completed += p.completed;
        total += p.total;
      }
      onProgress?.({ completed, total, status: msg.status });
      if (msg.status === 'success') return;
    }
  }
}

async function terminal() {
  const own = process.env.TERMINAL && path.basename(process.env.TERMINAL.split(/\s+/)[0]);
  const list = own ? [[own, (TERMINALS.find(([n]) => n === own) || [own, ['-e']])[1]], ...TERMINALS] : TERMINALS;
  for (const [name, args] of list) {
    const file = await which(name);
    if (file) return [file, args];
  }
  return null;
}

// Claude Code or Codex through Ollama, in a terminal window of its own.
async function launchThroughOllama(integration) {
  if (!['claude', 'codex'].includes(integration)) return { ok: false, error: 'unknown integration' };
  const [cli, term] = await Promise.all([which('ollama'), terminal()]);
  if (!cli || !term) return { ok: false, error: cli ? 'no terminal found' : 'Ollama is not installed' };
  detach(term[0], [...term[1], cli, 'launch', integration]);
  return { ok: true };
}

const openUrl = (url) => detach('xdg-open', [url]);

module.exports = { MODELS, KEY_PAGES, ollamaState, installOllama, startOllama, pullModel, launchThroughOllama, openUrl, terminal };
