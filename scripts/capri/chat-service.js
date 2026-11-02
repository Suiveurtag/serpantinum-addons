'use strict';

const fs = require('node:fs'),
  path = require('node:path'),
  os = require('node:os');
const llm = require('./llm'),
  ollama = require('./ollama'),
  {
    Actions
  } = require('./actions');
const intents = import('./intent.mjs');
const setup = require('./setup');
const { execFile } = require('node:child_process');
const HOOKS = { claude: require('./scripts/install-hooks'), codex: require('./scripts/install-codex-hooks'), agy: require('./scripts/install-hooks-agy') };
const HELP = { claude: 'https://code.claude.com/docs/en/quickstart', codex: 'https://learn.chatgpt.com/docs/hooks', agy: 'https://antigravity.google/docs/hooks' };
const OLLAMA_SITE = 'https://ollama.com/download/linux';
const SOUND_EXT = /\.(mp3|wav|ogg|m4a)$/i;
const soundsDir = () => path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'serpantinum', 'capri', 'sounds');
const hooksOf = id => HOOKS[id] || HOOKS.claude;
const capture = (cmd, args) => new Promise((resolve, reject) => execFile(cmd, args, { encoding: 'buffer', maxBuffer: 32 * 1024 * 1024, timeout: 10000 }, (e, out) => e ? reject(e) : resolve(out)));
const validHistory = h => Array.isArray(h) ? h.filter(m => m && ['user', 'assistant'].includes(m.role) && typeof m.content === 'string').slice(-60).map(m => ({
  role: m.role,
  content: m.content.slice(0, 16000)
})) : [];
class ChatService {
  constructor(emit) {
    this.emit = emit;
    this.actions = new Actions();
    this.turns = new Map();
    this.chatModels = [];
    this.snaps = new Map(); // look: id -> base64 JPEG, in memory a moment, never on disk
    this.pulling = null;
    this.dir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'serpantinum', 'capri');
    fs.mkdirSync(this.dir, {
      recursive: true,
      mode: 0o700
    });
    fs.chmodSync(this.dir, 0o700);
    this.cfg = {
      provider: 'ollama',
      chatModel: null,
      apiKeys: {},
      ...this.read('chat.json', {})
    };
    this.memory = this.read('memory.json', {
      history: [],
      claude: null
    });
    llm.restoreClaude(this.memory.claude);
  }
  read(name, fallback) {
    try {
      return JSON.parse(fs.readFileSync(path.join(this.dir, name), 'utf8'));
    } catch {
      return fallback;
    }
  }
  save(name, data) {
    const p = path.join(this.dir, name),
      tmp = p + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2), {
      mode: 0o600
    });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, p);
  }
  publicConfig() {
    const {
      apiKeys,
      ...cfg
    } = this.cfg;
    return {
      ...cfg,
      keys: Object.keys(apiKeys || {}),
      providers: Object.entries(llm.PROVIDERS).map(([id, p]) => ({
        id,
        label: p.label
      })),
      models: this.chatModels
    };
  }
  async status() {
    const provider = this.cfg.provider;
    this.chatModels = await llm.models(provider, this.cfg);
    if (!this.chatModels) return {
      ok: false,
      error: 'offline',
      provider
    };
    if (!this.chatModels.length) return {
      ok: false,
      error: 'nomodel',
      provider
    };
    const model = this.chatModels.includes(this.cfg.chatModel) ? this.cfg.chatModel : this.chatModels.find(m => !ollama.isCloud(m)) || this.chatModels[0];
    this.cfg.chatModel = model;
    llm.warm(provider, model);
    return {
      ok: true,
      provider,
      model,
      agent: provider === 'claude',
      local: llm.isLocal(provider, this.cfg, model),
      warmup: provider === 'ollama' && !ollama.isCloud(model)
    };
  }
  async configure(patch) {
    if (!patch || typeof patch !== 'object') throw new Error('Invalid configuration');
    const old = this.cfg,
      oldModels = this.chatModels,
      next = {
        ...old,
        apiKeys: {
          ...old.apiKeys
        }
      };
    if (patch.provider !== undefined) {
      if (!Object.hasOwn(llm.PROVIDERS, patch.provider)) throw new Error('Unknown provider');
      next.provider = patch.provider;
      if (next.provider !== old.provider) next.chatModel = null;
    }
    for (const key of ['chatModel', 'codexModel', 'customUrl', 'claudeCwd', 'claudeMode']) if (patch[key] !== undefined) {
      if (typeof patch[key] !== 'string' || patch[key].length > 2000) throw new Error('Invalid ' + key);
      next[key] = patch[key];
    }
    if (next.customUrl) {
      const u = new URL(next.customUrl);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) throw new Error('Use an HTTP(S) server address');
    }
    if (patch.apiKey !== undefined) {
      if (typeof patch.apiKey !== 'string' || patch.apiKey.length > 4096) throw new Error('Invalid key');
      if (patch.apiKey) next.apiKeys[next.provider] = patch.apiKey;
    }
    if (patch.removeKey) delete next.apiKeys[next.provider];
    this.cfg = next;
    try {
      const status = await this.status();
      if (!status.ok) throw new Error(status.error);
      this.save('chat.json', this.cfg);
      if (next.claudeCwd !== old.claudeCwd) {
        llm.resetClaude();
        this.memory.claude = null;
        this.save('memory.json', this.memory);
      }
      return {
        ...status,
        config: this.publicConfig()
      };
    } catch (e) {
      this.cfg = old;
      this.chatModels = oldModels;
      throw e;
    }
  }
  async send({
    id,
    messages
  }) {
    if (this.turns.size) throw new Error('An answer is already running');
    if (!Array.isArray(messages) || messages.length > 21 || !messages.length || messages.some(m => !m || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string' || m.content.length > 32000) || messages.at(-1).role !== 'user') throw new Error('Invalid conversation');
    const ctrl = new AbortController();
    this.turns.set(id, ctrl);
    const timeout = setTimeout(() => ctrl.abort(), 90000);
    let streamed = false,
      model = this.cfg.chatModel,
      tried = new Set(),
      busy = 0;
    try {
      if (!model) {
        const s = await this.status();
        if (!s.ok) throw new Error(s.error);
        model = s.model;
      }
      for (;;) {
        try {
          const text = await llm.chat(this.cfg.provider, this.cfg, {
            model,
            messages
          }, piece => {
            if (!ctrl.signal.aborted) {
              streamed = true;
              this.emit({
                t: 'chat.delta',
                id,
                text: piece
              });
            }
          }, ctrl.signal);
          this.cfg.chatModel = model;
          this.save('chat.json', this.cfg);
          this.memory.claude = llm.claudeMemory();
          this.save('memory.json', this.memory);
          return {
            ok: true,
            text,
            model
          };
        } catch (e) {
          if (ctrl.signal.aborted || streamed || !['busy', 'gone', 'signin'].includes(e.code) || this.cfg.provider === 'claude') throw e;
          if (e.code === 'busy' && busy++ === 0) {
            await new Promise(r => {
              const t = setTimeout(r, 1500);
              ctrl.signal.addEventListener('abort', () => {
                clearTimeout(t);
                r();
              }, {
                once: true
              });
            });
            ctrl.signal.throwIfAborted();
            continue;
          }
          tried.add(model);
          const next = this.chatModels.find(m => !tried.has(m) && !ollama.isCloud(m)) || this.chatModels.find(m => !tried.has(m));
          if (!next || tried.size >= 3) throw e;
          model = next;
          busy = 0;
        }
      }
    } finally {
      clearTimeout(timeout);
      this.turns.delete(id);
    }
  }
  // She looks at your screen (look.js): the screen she's on, 1280 px wide at most, JPEG in memory.
  async lookSnap(output) {
    if (typeof output !== 'string' || !/^[\w.-]+$/.test(output)) throw new Error('no screen');
    const mon = JSON.parse(String(await capture('hyprctl', ['monitors', '-j']))).find(o => o.name === output);
    if (!mon) throw new Error('no screen');
    const scale = Math.min(mon.scale || 1, 1280 / (mon.width / (mon.scale || 1)));
    const jpeg = await capture('grim', ['-o', output, '-t', 'jpeg', '-q', '72', '-s', String(Math.round(scale * 1000) / 1000), '-']);
    if (!jpeg.length) throw new Error('no picture of the screen');
    const id = require('node:crypto').randomUUID();
    this.snaps.set(id, jpeg.toString('base64'));
    setTimeout(() => this.snaps.delete(id), 120000).unref();
    return { ok: true, id };
  }
  lookWhere() {
    const model = this.cfg.chatModel || '';
    const provider = this.cfg.provider === 'ollama' && ollama.isCloud(model) ? 'Ollama' : llm.PROVIDERS[this.cfg.provider]?.label || this.cfg.provider;
    return { local: llm.isLocal(this.cfg.provider, this.cfg, model), provider, model };
  }
  // What her AI says about that picture, as her: 'noai' (nothing to ask), 'novision' (can't see pictures).
  async lookSay({ id, persona, prompt, history = [] }) {
    const image = this.snaps.get(id);
    this.snaps.delete(id);
    if (!image) return { ok: false, error: 'the picture is gone' };
    if (typeof persona !== 'string' || typeof prompt !== 'string' || persona.length > 32000 || prompt.length > 4000) throw new Error('Invalid request');
    const status = await this.status().catch(() => ({ ok: false }));
    if (!status.ok) return { ok: false, code: 'noai' };
    const { provider } = this.cfg, model = status.model;
    if (provider === 'claude') return { ok: false, code: 'novision', model: 'Claude Code' };
    if (provider === 'ollama' && !(await ollama.canSee(model))) return { ok: false, code: 'novision', model };
    const user = provider === 'ollama' ? { role: 'user', content: prompt, images: [image] }
      : provider === 'chatgpt' ? { role: 'user', content: prompt }
      : { role: 'user', content: [{ type: 'text', text: prompt }, { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } }] };
    const messages = [{ role: 'system', content: persona }, ...validHistory(history).slice(-20), user];
    for (let attempt = 0; ; attempt++) {
      try {
        const text = await llm.chat(provider, this.cfg, { model, messages, images: provider === 'chatgpt' ? [image] : [] }, () => {}, AbortSignal.timeout(120000));
        return { ok: true, text, model };
      } catch (err) {
        if (err.code === 'busy' && attempt === 0) {
          await new Promise(r => setTimeout(r, 1500));
          continue;
        }
        const novision = /image|vision|multimodal|modalit|image_url|content.*(part|type)/i.test(err.message);
        return { ok: false, error: String(err.message).slice(0, 300), code: novision ? 'novision' : err.code || null, model };
      }
    }
  }
  // Setting her up with buttons (setup.js): who answers, with its key or address, tried and undone if it fails.
  async useProvider({ provider, key, url }) {
    try {
      const res = await this.configure({ provider, ...(key && { apiKey: String(key).trim() }), ...(url && { customUrl: String(url).trim() }) });
      return { ok: true, model: res.model };
    } catch (e) {
      return { ok: false, error: String(e.message || e).slice(0, 300) };
    }
  }
  async setupInfo() {
    let cloud = [];
    if (await ollama.models().catch(() => null)) {
      const account = await ollama.account().catch(() => null);
      if (account?.name) cloud = await ollama.freeModels().catch(() => []);
    }
    return { models: setup.MODELS, cloud, ram: os.totalmem(), keyed: Object.keys(setup.KEY_PAGES) };
  }
  async pullModel(name) {
    if (!setup.MODELS.some(m => m.name === name) && !(typeof name === 'string' && /^[\w.-]+:cloud$/.test(name))) return { ok: false, error: 'unknown model' };
    this.pulling?.abort();
    const abort = new AbortController();
    this.pulling = abort;
    try {
      await setup.pullModel(name, p => this.emit({ t: 'setup.progress', kind: 'pull', completed: p.completed, total: p.total }), abort.signal);
      const res = await this.useProvider({ provider: 'ollama' });
      const model = this.chatModels.find(m => m === name || m.startsWith(`${name}:`));
      if (model) await this.configure({ chatModel: model });
      return res.ok ? { ok: true, model } : res;
    } catch (err) {
      return { ok: false, error: abort.signal.aborted ? 'stopped' : String(err.message).slice(0, 300) };
    } finally {
      if (this.pulling === abort) this.pulling = null;
    }
  }
  async ollamaSignin() {
    const account = await ollama.account().catch(() => null);
    if (account?.signin) setup.openUrl(account.signin);
    return { ok: Boolean(account?.signin), signedIn: Boolean(account?.name) };
  }
  // Her guide: the assistant's folder (~/.claude, ~/.codex, ~/.gemini/config), its settings file shown.
  async openClaudeFolder(id) {
    const file = hooksOf(id).status().file, dir = path.dirname(file);
    if (!fs.existsSync(dir)) return { found: false, dir };
    const has = fs.existsSync(file);
    if (has) {
      try {
        await require('./actions').run('dbus-send', ['--session', '--dest=org.freedesktop.FileManager1', '--type=method_call', '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1.ShowItems', `array:string:${require('node:url').pathToFileURL(file).href}`, 'string:']);
      } catch {
        setup.openUrl(dir);
      }
    } else setup.openUrl(dir);
    return { found: true, dir, file: has, label: path.basename(has ? file : dir) };
  }
  sounds() {
    try {
      return fs.readdirSync(soundsDir()).filter(f => SOUND_EXT.test(f)).map(f => ({ name: f.replace(SOUND_EXT, '').toLowerCase(), file: path.join(soundsDir(), f) }));
    } catch {
      return [];
    }
  }
  async request(m) {
    const a = m.args || {};
    switch (m.method) {
      case 'status':
        return this.status();
      case 'config':
        return this.publicConfig();
      case 'configure':
        return this.configure(a);
      case 'memory':
        return validHistory(this.memory.history);
      case 'remember':
        this.memory.history = validHistory(a.history);
        this.save('memory.json', this.memory);
        return true;
      case 'forget':
        for (const c of this.turns.values()) c.abort();
        llm.resetClaude();
        this.memory = {
          history: [],
          claude: null
        };
        this.save('memory.json', this.memory);
        return true;
      case 'stop':
        this.turns.get(a.id)?.abort();
        return true;
      case 'send':
        return this.send(a);
      case 'lookSnap':
        return this.lookSnap(a.output).catch(e => ({ ok: false, error: String(e.message || e).slice(0, 200) }));
      case 'lookWhere':
        return this.lookWhere();
      case 'lookSay':
        return this.lookSay(a);
      case 'setupInfo':
        return this.setupInfo();
      case 'ollamaState':
        return setup.ollamaState();
      case 'installOllama':
        return setup.installOllama();
      case 'startOllama': {
        const res = await setup.startOllama();
        await this.status().catch(() => null);
        return res;
      }
      case 'pullModel':
        return this.pullModel(a.name);
      case 'cancelSetup':
        this.pulling?.abort();
        return true;
      case 'useProvider':
        return this.useProvider(a);
      case 'keyPage':
        if (setup.KEY_PAGES[a.provider]) setup.openUrl(setup.KEY_PAGES[a.provider]);
        return true;
      case 'openOllama':
        setup.openUrl(OLLAMA_SITE);
        return true;
      case 'ollamaSignin':
        return this.ollamaSignin();
      case 'launchFree':
        return setup.launchThroughOllama(a.integration);
      case 'hooksStatus':
        return hooksOf(a.assistant).status();
      case 'installHooks':
        try {
          return { ok: true, data: hooksOf(a.assistant).install() };
        } catch (e) {
          return { ok: false, error: String(e.message || e).slice(0, 300) };
        }
      case 'uninstallHooks':
        try {
          return { ok: true, data: hooksOf(a.assistant).uninstall() };
        } catch (e) {
          return { ok: false, error: String(e.message || e).slice(0, 300) };
        }
      case 'claudeFound':
        return fs.existsSync(path.dirname(hooksOf(a.assistant).status().file));
      case 'openHelp':
        setup.openUrl(HELP[a.assistant] || HELP.claude);
        return true;
      case 'openClaudeFolder':
        return this.openClaudeFolder(a.assistant);
      case 'sounds':
        return this.sounds();
      case 'openSounds':
        fs.mkdirSync(soundsDir(), { recursive: true });
        setup.openUrl(soundsDir());
        return true;
      case 'intent':
        if (typeof a.text !== 'string' || a.text.length > 2000) throw new Error('Message too long');
        return (await intents).parseIntent(a.text, Array.isArray(a.apps) ? a.apps : [], a.waitingWhen);
      default:
        if (!['openApps', 'findApp', 'closeApp', 'findLaunch', 'launch', 'openSite', 'media', 'music', 'youtube', 'roblox', 'webSearch', 'searchFiles', 'openFile', 'screenshot'].includes(m.method)) throw new Error('Unknown method');
        return this.actions[m.method](...(Array.isArray(a.values) ? a.values : []));
    }
  }
  handle(m) {
    if (!m || typeof m !== 'object' || m.t !== 'chat.request') return false;
    if (typeof m.id !== 'string' || m.id.length > 80) return true;
    Promise.resolve().then(() => this.request(m)).then(data => this.emit({
      t: 'chat.result',
      id: m.id,
      data
    })).catch(e => this.emit({
      t: 'chat.result',
      id: m.id,
      data: {
        ok: false,
        error: String(e.message || e).slice(0, 300),
        code: e.code || null
      }
    }));
    return true;
  }
  stop() {
    for (const c of this.turns.values()) c.abort();
  }
}
module.exports = {
  ChatService,
  validHistory
};
