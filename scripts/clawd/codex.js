'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const DEFAULT_MODEL = 'gpt-6-luna';
const TIMEOUT_MS = 90000;
const DISABLED = ['hooks', 'memories', 'plugins', 'apps', 'shell_tool', 'unified_exec', 'browser_use', 'computer_use'];
const error = message => Object.assign(new Error(message), {
  code: /rate limit|usage limit|429|quota/i.test(message) ? 'busy' : null
});

// The session PATH misses tools installed since login (npm -g, cargo...): append the usual per-user bin directories.
function userBinPath(base = process.env.PATH || '') {
  const home = os.homedir();
  const e = process.env;
  const dirs = [e.NPM_CONFIG_PREFIX && path.join(e.NPM_CONFIG_PREFIX, 'bin'), e.PNPM_HOME, e.BUN_INSTALL && path.join(e.BUN_INSTALL, 'bin'), e.VOLTA_HOME && path.join(e.VOLTA_HOME, 'bin'), e.NVM_BIN, path.join(home, '.local/bin'), path.join(home, '.npm-global/bin'), path.join(home, '.npm-packages/bin'), path.join(home, '.local/share/pnpm'), path.join(home, '.bun/bin'), path.join(home, '.volta/bin'), path.join(home, '.cargo/bin'), path.join(home, '.yarn/bin'), path.join(home, '.asdf/shims'), path.join(home, '.local/share/mise/shims'), '/usr/local/bin'];
  for (const root of [path.join(home, '.nvm/versions/node'), path.join(home, '.local/share/fnm/node-versions'), path.join(home, '.local/share/mise/installs/node')]) {
    try {
      for (const v of fs.readdirSync(root).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))) dirs.push(path.join(root, v, root.includes('fnm') ? 'installation/bin' : 'bin'));
    } catch {}
  }
  const have = base.split(':').filter(Boolean);
  for (const d of dirs) if (d && !have.includes(d) && fs.existsSync(d)) have.push(d);
  return have.join(':');
}

// One Codex CLI turn: prompt on stdin, persona as the instructions file, pictures as -i, no tools, no files.
async function chat({ persona, prompt, images = [], model = DEFAULT_MODEL, timeoutMs = TIMEOUT_MS }, onDelta, signal) {
  signal.throwIfAborted();
  const runtime = process.env.XDG_RUNTIME_DIR;
  let base;
  if (runtime) {
    base = path.join(runtime, `clawd-chat-${process.getuid()}`);
    fs.mkdirSync(base, { recursive: true, mode: 0o700 });
    const st = fs.lstatSync(base);
    if (!st.isDirectory() || st.isSymbolicLink() || st.uid !== process.getuid()) throw error('Unsafe chat directory');
    fs.chmodSync(base, 0o700);
  } else {
    base = fs.mkdtempSync(path.join(os.tmpdir(), 'clawd-chat-'));
  }
  const dir = fs.mkdtempSync(path.join(base, 'codex-'));
  fs.chmodSync(dir, 0o700);
  try {
    const empty = path.join(dir, 'empty');
    const personaFile = path.join(dir, 'persona.md');
    fs.mkdirSync(empty, { mode: 0o700 });
    fs.writeFileSync(personaFile, persona, { mode: 0o600 });
    const args = ['exec', '--json', '--ephemeral', '--skip-git-repo-check', '--ignore-user-config',
      '-s', 'read-only', '-c', 'approval_policy="never"', '-c', 'model_reasoning_effort="low"',
      '-c', `model_instructions_file=${JSON.stringify(personaFile)}`,
      ...DISABLED.flatMap(feature => ['--disable', feature]),
      '-c', 'web_search="disabled"', '-C', empty];
    // a picture of the screen: attached by the CLI itself, before -C so "-" stays the prompt
    images.forEach((jpeg, i) => {
      const picture = path.join(dir, `screen-${i}.jpg`);
      fs.writeFileSync(picture, Buffer.from(jpeg, 'base64'), { mode: 0o600 });
      args.splice(args.indexOf('-C'), 0, '-i', picture);
    });
    args.push('-m', model, '-');
    // Keep subscription authentication, discard injected API credentials and project/session environment.
    const env = {
      PATH: userBinPath(),
      HOME: os.homedir(),
      LANG: process.env.LANG || 'C.UTF-8'
    };
    for (const k of ['CODEX_HOME', 'XDG_RUNTIME_DIR', 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'NO_PROXY', 'SSL_CERT_FILE']) if (process.env[k]) env[k] = process.env[k];
    const bin = process.env.CLAWD_CODEX || 'codex';

    return await new Promise((resolve, reject) => {
      const child = spawn('python3', [path.join(__dirname, 'cli-runner.py'), String(process.pid), bin, ...args], {
        cwd: empty,
        env,
        stdio: ['pipe', 'pipe', 'pipe']
      });
      let buffer = '', text = '', errors = '', failure = null, completed = false;
      const kill = () => child.kill('SIGTERM');
      const timeout = setTimeout(() => {
        failure = error(`Codex timed out after ${Math.round(timeoutMs / 1000)} seconds`);
        kill();
      }, timeoutMs);
      signal.addEventListener('abort', kill, { once: true });
      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      function line(raw) {
        let m;
        try {
          m = JSON.parse(raw);
        } catch {
          return;
        }
        if (m.type === 'item.completed' && m.item?.type === 'agent_message' && typeof m.item.text === 'string') {
          text += m.item.text;
          onDelta(m.item.text);
        }
        if (m.type === 'turn.completed') completed = true;
        if (m.type === 'error' || m.type === 'turn.failed') failure = error(m.message || m.error?.message || 'Codex failed');
      }
      child.stdout.on('data', s => {
        buffer += s;
        let nl;
        while ((nl = buffer.indexOf('\n')) >= 0) {
          line(buffer.slice(0, nl));
          buffer = buffer.slice(nl + 1);
        }
      });
      child.stderr.on('data', s => {
        errors = (errors + s).slice(-2000);
      });
      child.stdin.on('error', () => {});
      child.stdin.end(prompt);
      child.on('error', e => {
        failure = e;
      });
      child.on('close', code => {
        clearTimeout(timeout);
        signal.removeEventListener('abort', kill);
        if (buffer) line(buffer);
        if (signal.aborted) return reject(Object.assign(new Error('stopped'), { code: 'stopped' }));
        if (failure) return reject(failure);
        if (code !== 0 || !completed || !text) return reject(error(errors.trim().slice(0, 300) || 'Codex gave no answer'));
        resolve(text);
      });
      if (signal.aborted) kill();
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    if (!runtime) fs.rmSync(base, { recursive: true, force: true });
  }
}

module.exports = { chat, DEFAULT_MODEL };
