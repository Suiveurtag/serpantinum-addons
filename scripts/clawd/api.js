'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// OpenAI-compatible chat/completions: covers hosted APIs (OpenAI, OpenRouter, Groq...) and local servers (Ollama, llama.cpp, LM Studio).
const PRESETS = {
  api: { url: 'https://api.openai.com/v1', model: 'gpt-4o-mini', key: true },
  local: { url: 'http://127.0.0.1:11434/v1', model: 'llama3.2', key: false }
};
const TIMEOUT_MS = 90000;
const error = (message, code = null) => Object.assign(new Error(message), { code });

// Key: CLAWD_CHAT_API_KEY, else the first line of $XDG_CONFIG_HOME/serpantinum/clawd/api-key (keep it 0600). Never in settings.json.
function apiKey() {
  if (process.env.CLAWD_CHAT_API_KEY) return process.env.CLAWD_CHAT_API_KEY.trim();
  try {
    const base = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
    return fs.readFileSync(path.join(base, 'serpantinum', 'clawd', 'api-key'), 'utf8').split('\n')[0].trim();
  } catch {
    return '';
  }
}

function resolve(provider, cfg = {}) {
  const preset = PRESETS[provider];
  if (!preset) throw error('Unknown provider');
  const url = String(cfg.url || preset.url).replace(/\/+$/, '');
  if (!/^https?:\/\//.test(url)) throw error('Bad chat URL');
  // the key only goes to the hosted provider, and never in clear over http to a remote host
  if (preset.key && !/^https:\/\//.test(url) && !/^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(url)) throw error('API key needs https');
  return { url, model: String(cfg.model || preset.model), key: preset.key ? apiKey() : '', needsKey: preset.key };
}

const headers = r => ({ 'content-type': 'application/json', ...(r.key ? { authorization: `Bearer ${r.key}` } : {}) });

function fail(status, body) {
  const msg = String(body || '').slice(0, 300) || `HTTP ${status}`;
  if (status === 401 || status === 403) return error(msg, 'signin');
  if (status === 429 || status === 503) return error(msg, 'busy');
  return error(msg);
}

async function chat({ persona, prompt, images = [], provider, config, timeoutMs = TIMEOUT_MS }, onDelta, signal) {
  signal.throwIfAborted();
  const r = resolve(provider, config);
  if (r.needsKey && !r.key) throw error('No API key', 'signin');
  const content = images.length
    ? [{ type: 'text', text: prompt }, ...images.map(j => ({ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${j}` } }))]
    : prompt;
  const ctrl = new AbortController();
  const kill = () => ctrl.abort();
  signal.addEventListener('abort', kill, { once: true });
  const timer = setTimeout(kill, timeoutMs);
  try {
    let res;
    try {
      res = await fetch(`${r.url}/chat/completions`, {
        method: 'POST',
        headers: headers(r),
        body: JSON.stringify({ model: r.model, stream: true, messages: [{ role: 'system', content: persona }, { role: 'user', content }] }),
        signal: ctrl.signal
      });
    } catch (e) {
      if (signal.aborted) throw error('stopped', 'stopped');
      throw error(ctrl.signal.aborted ? 'Chat API timed out' : `Cannot reach ${r.url}`);
    }
    if (!res.ok) throw fail(res.status, await res.text().catch(() => ''));
    let text = '', buffer = '';
    const decoder = new TextDecoder();
    try {
      for await (const chunk of res.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let nl;
        while ((nl = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, nl).trim();
          buffer = buffer.slice(nl + 1);
          if (!line.startsWith('data:') || line.slice(5).trim() === '[DONE]') continue;
          let m;
          try { m = JSON.parse(line.slice(5)); } catch { continue; }
          if (m.error) throw error(String(m.error.message || 'Chat API error'));
          const piece = m.choices?.[0]?.delta?.content;
          if (typeof piece === 'string' && piece) {
            text += piece;
            onDelta(piece);
          }
        }
      }
    } catch (e) {
      if (signal.aborted) throw error('stopped', 'stopped');
      if (ctrl.signal.aborted) throw error('Chat API timed out');
      if (e.code === null) throw e;
      throw error('Chat API connection lost');
    }
    if (!text.trim()) throw error('Chat API gave no answer');
    return text;
  } finally {
    clearTimeout(timer);
    signal.removeEventListener('abort', kill);
  }
}

// Reachable (local) / reachable with a key (api): for the settings card.
async function status(provider, config) {
  try {
    const r = resolve(provider, config);
    if (r.needsKey && !r.key) return { ready: false, note: 'no api key' };
    const res = await fetch(`${r.url}/models`, { headers: headers(r), signal: AbortSignal.timeout(5000) });
    if (res.status === 401 || res.status === 403) return { ready: false, note: 'key rejected' };
    if (!res.ok) return { ready: false, note: `HTTP ${res.status}` };
    return { ready: true, note: r.model };
  } catch {
    return { ready: false, note: 'unreachable' };
  }
}

module.exports = { chat, status, resolve, PRESETS };
