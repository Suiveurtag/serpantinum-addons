'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
  spawn,
  execFile
} = require('node:child_process');
const error = message => Object.assign(new Error(message), {
  code: /rate limit|usage limit|429|quota/i.test(message) ? 'busy' : null
});
function models(cfg) {
  return new Promise((resolve, reject) => execFile('codex', ['login', 'status'], {
    timeout: 10000
  }, (err, out, stderr) => {
    if (!err && /Logged in using ChatGPT/.test(out + stderr)) resolve([cfg.codexModel || 'ChatGPT']);else reject(Object.assign(new Error('Sign in with ChatGPT using: codex login'), {
      code: 'signin'
    }));
  }));
}
async function chat(cfg, {
  messages,
  images = []
}, onDelta, signal) {
  signal.throwIfAborted();
  const base = path.join(process.env.XDG_RUNTIME_DIR || os.tmpdir(), `capri-chat-${process.getuid()}`);
  fs.mkdirSync(base, {
    recursive: true,
    mode: 0o700
  });
  const dir = fs.mkdtempSync(path.join(base, 'codex-'));
  fs.chmodSync(dir, 0o700);
  const empty = path.join(dir, 'empty'),
    persona = path.join(dir, 'persona.md');
  fs.mkdirSync(empty, {
    mode: 0o700
  });
  fs.writeFileSync(persona, (messages[0]?.content || 'You are Capri. Answer briefly.') + '\nNever call tools or inspect files. Desktop actions are handled by the companion, outside this conversation.', {
    mode: 0o600
  });
  const args = ['exec', '--json', '--ephemeral', '--skip-git-repo-check', '--ignore-user-config', '-s', 'read-only', '-c', 'approval_policy="never"', '-c', 'model_reasoning_effort="low"', '-c', `model_instructions_file=${JSON.stringify(persona)}`, '--disable', 'hooks', '--disable', 'memories', '--disable', 'plugins', '--disable', 'apps', '--disable', 'shell_tool', '--disable', 'unified_exec', '--disable', 'browser_use', '--disable', 'computer_use', '-c', 'web_search="disabled"', '-C', empty];
  // a picture of the screen (look): attached by the CLI itself, before -C so "-" stays the prompt
  images.forEach((jpeg, i) => {
    const file = path.join(dir, `screen-${i}.jpg`);
    fs.writeFileSync(file, Buffer.from(jpeg, 'base64'), {
      mode: 0o600
    });
    args.splice(args.indexOf('-C'), 0, '-i', file);
  });
  args.push('-m', cfg.codexModel || 'gpt-5.6-luna');
  args.push('-');
  const history = messages.slice(1, -1).map(m => `${m.role === 'user' ? 'User' : 'Capri'}: ${m.content}`).join('\n');
  const prompt = `Conversation so far:\n${history}\n\nUser's new message:\n${messages.at(-1).content}`;
  // Keep subscription authentication, discard injected API credentials and project/session environment.
  const env = {
    PATH: process.env.PATH,
    HOME: os.homedir(),
    LANG: process.env.LANG || 'C.UTF-8'
  };
  for (const k of ['CODEX_HOME', 'XDG_RUNTIME_DIR', 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'NO_PROXY', 'SSL_CERT_FILE']) if (process.env[k]) env[k] = process.env[k];
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn('python3', [path.join(__dirname, 'cli-runner.py'), String(process.pid), 'codex', ...args], {
        cwd: empty,
        env,
        stdio: ['pipe', 'pipe', 'pipe']
      });
      let buffer = '',
        text = '',
        errors = '',
        failure = null,
        completed = false;
      const kill = () => child.kill('SIGTERM'),
        timeout = setTimeout(() => {
          failure = error('Codex timed out after 90 seconds');
          kill();
        }, 90000);
      signal.addEventListener('abort', kill, {
        once: true
      });
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
        if (signal.aborted) return reject(new Error('stopped'));
        if (failure) return reject(failure);
        if (code !== 0 || !completed || !text) return reject(error(errors.trim().slice(0, 300) || 'Codex gave no answer'));
        resolve(text);
      });
      if (signal.aborted) kill();
    });
  } finally {
    fs.rmSync(dir, {
      recursive: true,
      force: true
    });
  }
}
module.exports = {
  models,
  chat
};
