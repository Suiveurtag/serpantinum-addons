import {co} from './util.mjs';
function _asyncToGenerator(fn) { return function() { return co(fn.apply(this,arguments)); }; }
// Native port of capri-desktop setup.js; upstream LICENSE in ../LICENSE.
// Setting up who she talks with, with buttons, so nobody has to open a terminal: on this PC
// (Ollama installed, woken up and a model fetched for you, with how far along it is), online with
// no account (Pollinations), or with a key you paste in her panel. And Claude Code or Codex for
// free, run through Ollama. Each step is a panel of her guide (guide.js).

import { fmt } from './util.mjs';

// the services that take a key, in the order she offers them (the first two have a free tier)
const KEYED = ['groq', 'gemini', 'openrouter', 'openai', 'mistral', 'deepseek'];
const NAMES = {
  groq: 'Groq',
  gemini: 'Gemini',
  openrouter: 'OpenRouter',
  openai: 'OpenAI',
  mistral: 'Mistral',
  deepseek: 'DeepSeek'
};
const ROOMY = 12 * 2 ** 30; // enough memory for the bigger model

export class Setup {
  constructor({
    guide,
    panel,
    host,
    brain,
    capri,
    voice
  }) {
    this.guide = guide;
    this.panel = panel;
    this.host = host;
    this.brain = brain;
    this.capri = capri;
    this.voice = voice;
    this.onReady = null; // () => void: she can talk now, and you said you want to (app.js opens her chat)
    this.pulling = false;
    host.onSetupProgress(p => this.progress(p));
  }
  get t() {
    return this.brain.t.setup;
  }

  // Her chat can't answer yet (status: what chat:status said), or "Set it up with her" in her menu.
  chat() {
    var _this = this;
    return _asyncToGenerator(function* (status = null) {
      let ready = false;
      yield _this.guide.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        ready = yield _this.choose(status);
      }));
      if (ready) _this.onReady?.();
    }).apply(this, arguments);
  }

  // "API key or address" in her menu: for the service she's on, else which one.
  key() {
    var _this2 = this;
    return _asyncToGenerator(function* () {
      let ready = false;
      yield _this2.guide.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        const {
          provider
        } = yield _this2.host.getConfig();
        if (KEYED.includes(provider)) ready = yield _this2.paste(provider);else if (provider === 'custom') ready = yield _this2.address();else ready = yield _this2.pickKeyed();
      }));
      if (ready) _this2.onReady?.();
    })();
  }

  // A bigger model than the tiny one her chat is on: picked, fetched, and her chat back on it.
  better() {
    var _this3 = this;
    return _asyncToGenerator(function* () {
      let ready = false;
      yield _this3.guide.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        if (!(yield _this3.ollamaUp())) return;
        const name = yield _this3.pickModel(_this3.t.bigger);
        if (!name) return;
        const res = yield _this3.pull(name);
        if (res.ok) ready = yield _this3.done();else if (res.error !== 'stopped') yield _this3.fail(_this3.t.pullFailed, res.error);
      }));
      if (ready) _this3.onReady?.();
    })();
  }

  // Claude Code or Codex for free (the one she watches), run through Ollama in a window of its own.
  free() {
    var _this4 = this;
    return _asyncToGenerator(function* () {
      yield _this4.guide.scene(() => _this4.freeNow());
    })();
  }

  // ---------- steps ----------

  // Who answers her: why she can't talk yet if she knows, then the choice. True once she can talk.
  choose(status) {
    var _this5 = this;
    return _asyncToGenerator(function* () {
      const t = _this5.t;
      let why = '';
      if (status && !status.ok) {
        if (status.code === 'nokey') return _this5.paste(status.provider);
        if (status.code === 'nourl') return _this5.address();
        if (!status.provider || status.provider === 'ollama') {
          const state = yield _this5.host.ollamaState();
          why = !state.installed ? t.why.noOllama : !state.running ? t.why.asleep : t.why.noModel;
        } else {
          why = `${t.failed} ${status.error}`;
        }
      }
      _this5.capri.perform('curious', _this5.capri.towardCenter());
      const id = yield _this5.guide.ask({
        face: 'smug',
        line: t.who,
        quote: [why, t.whoHow].filter(Boolean).join('\n'),
        actions: [{
          id: 'local',
          label: t.local,
          primary: true
        }, {
          id: 'online',
          label: t.online
        }, {
          id: 'key',
          label: t.key
        }, {
          id: 'later',
          label: t.later
        }]
      });
      if (id === 'local') return _this5.ollama();
      if (id === 'online') return _this5.use('pollinations');
      if (id === 'key') return _this5.pickKeyed();
      return false;
    })();
  }

  // Ollama as far as it needs to go: installed, awake, with a model.
  ollama() {
    var _this6 = this;
    return _asyncToGenerator(function* () {
      if (!(yield _this6.ollamaUp())) return false;
      const state = yield _this6.host.ollamaState();
      if (state.models?.length) {
        const res = yield _this6.host.useProvider({
          provider: 'ollama'
        });
        return res.ok ? _this6.done() : _this6.fail(_this6.t.failed, res.error);
      }
      const name = yield _this6.pickModel();
      if (!name) return false;
      const res = yield _this6.pull(name);
      if (res.ok) return _this6.done();
      return res.error === 'stopped' ? false : _this6.fail(_this6.t.pullFailed, res.error);
    })();
  }

  // Ollama installed (with winget, on your click) and awake. True once it answers.
  ollamaUp() {
    var _this7 = this;
    return _asyncToGenerator(function* () {
      const t = _this7.t;
      let state = yield _this7.host.ollamaState();
      if (state.running) return true;
      if (!state.installed) {
        if (!state.winget) {
          const id = yield _this7.guide.ask({
            face: 'aside',
            line: t.noWinget,
            quote: t.noWingetHow,
            actions: [{
              id: 'site',
              label: t.site,
              primary: true
            }, {
              id: 'later',
              label: t.later
            }]
          });
          if (id === 'site') _this7.host.openOllama();
          return false;
        }
        const id = yield _this7.guide.ask({
          face: 'look',
          line: t.install,
          quote: t.installHow,
          actions: [{
            id: 'install',
            label: t.installBtn,
            primary: true
          }, {
            id: 'site',
            label: t.site
          }, {
            id: 'later',
            label: t.later
          }]
        });
        if (id === 'site') _this7.host.openOllama();
        if (id !== 'install') return false;
        _this7.working(t.installing, t.installingHow);
        const res = yield _this7.host.installOllama();
        state = yield _this7.host.ollamaState();
        if (!state.installed) return _this7.fail(t.installFailed, res.error || '');
        if (state.running) return true;
      }
      _this7.working(t.waking, t.wakingHow);
      const res = yield _this7.host.startOllama();
      return res.ok ? true : _this7.fail(t.wakeFailed, t.wakeFailedHow);
    })();
  }

  // Which model to fetch: the better one first when the PC has room for it, then Ollama's free cloud
  // ones if you're signed in to it.
  pickModel() {
    var _this8 = this;
    return _asyncToGenerator(function* (line = _this8.t.model) {
      const t = _this8.t;
      const info = yield _this8.host.setupInfo();
      const models = info.ram >= ROOMY ? info.models : [...info.models].reverse();
      const cloud = info.cloud || [];
      const id = yield _this8.guide.ask({
        face: 'look',
        line,
        quote: cloud.length ? `${t.modelHow}\n${t.cloudHow}` : t.modelHow,
        actions: [...models.map((m, i) => ({
          id: m.name,
          label: `${m.name} · ${_this8.size(m.bytes)}`,
          primary: i === 0
        })), ...cloud.map(name => ({
          id: name,
          label: `${name.replace(/:cloud$/, '')} · ${t.cloudFree}`
        })), {
          id: 'later',
          label: t.later
        }]
      });
      return models.some(m => m.name === id) || cloud.includes(id) ? id : null;
    }).apply(this, arguments);
  }

  // Fetching it: a bar that fills, how much is done, and a button to stop.
  pull(name) {
    var _this9 = this;
    return _asyncToGenerator(function* () {
      const t = _this9.t;
      _this9.pulling = true;
      _this9.panel.say({
        kind: 'work',
        face: 'calm',
        guide: true,
        hold: null,
        token: Symbol('setup'),
        line: fmt(t.pulling, {
          model: name
        }),
        quote: t.pullStart,
        progress: 0,
        actions: [{
          id: 'cancel',
          label: t.cancel
        }],
        onAction: () => _this9.host.cancelSetup()
      });
      try {
        return yield _this9.host.pullModel(name);
      } finally {
        _this9.pulling = false;
      }
    })();
  }
  progress(p) {
    if (p.kind !== 'pull' || !this.pulling || !p.total || this.panel.current?.kind !== 'work') return;
    const k = p.completed / p.total;
    this.panel.setProgress(k);
    this.panel.setQuote(fmt(this.t.progress, {
      done: this.size(p.completed),
      total: this.size(p.total),
      percent: Math.floor(k * 100)
    }));
  }

  // A service with no key needed (Pollinations): tried, then ready.
  use(provider) {
    var _this0 = this;
    return _asyncToGenerator(function* () {
      _this0.working(_this0.t.checking);
      const res = yield _this0.host.useProvider({
        provider
      });
      return res.ok ? _this0.done() : _this0.fail(_this0.t.failed, res.error);
    })();
  }
  pickKeyed() {
    var _this1 = this;
    return _asyncToGenerator(function* () {
      const t = _this1.t;
      const id = yield _this1.guide.ask({
        face: 'smug',
        line: t.which,
        quote: t.whichHow,
        actions: [...KEYED.map((p, i) => ({
          id: p,
          label: NAMES[p],
          primary: i === 0
        })), {
          id: 'back',
          label: t.back
        }]
      });
      if (id === 'back') return _this1.choose(null);
      return KEYED.includes(id) ? _this1.paste(id) : false;
    })();
  }

  // Her panel with a line to paste the key into (hidden as you type), and the page to get one.
  paste(_x) {
    var _this10 = this;
    return _asyncToGenerator(function* (provider, error = '') {
      const t = _this10.t;
      const got = yield _this10.guide.askText({
        face: error ? 'wide' : 'look',
        line: fmt(t.paste, {
          name: NAMES[provider] || provider
        }),
        quote: error ? `${t.keyBad} ${error}` : t.pasteHow,
        secret: true,
        placeholder: t.placeholder,
        tag: t.keyTag,
        note: t.keyNote,
        actions: [{
          id: 'page',
          label: t.where
        }, {
          id: 'other',
          label: t.other
        }],
        onAction: id => id === 'page' && (_this10.host.keyPage(provider), true)
      });
      if (got?.action === 'other') return _this10.choose(null);
      if (!got?.text) return false;
      _this10.working(t.checking);
      const res = yield _this10.host.useProvider({
        provider,
        key: got.text
      });
      return res.ok ? _this10.done() : _this10.paste(provider, res.error);
    }).apply(this, arguments);
  }

  // The address of an OpenAI-compatible server of your own (LM Studio, llama.cpp…).
  address() {
    var _this11 = this;
    return _asyncToGenerator(function* (error = '') {
      const t = _this11.t;
      const got = yield _this11.guide.askText({
        face: error ? 'wide' : 'look',
        line: t.address,
        quote: error ? `${t.failed} ${error}` : t.addressHow,
        placeholder: 'http://127.0.0.1:1234/v1',
        tag: 'URL',
        note: t.addressNote,
        actions: [{
          id: 'other',
          label: t.other
        }]
      });
      if (got?.action === 'other') return _this11.choose(null);
      if (!got?.text) return false;
      _this11.working(t.checking);
      const res = yield _this11.host.useProvider({
        provider: 'custom',
        url: got.text
      });
      return res.ok ? _this11.done() : _this11.address(res.error);
    }).apply(this, arguments);
  }

  // Claude Code or Codex through Ollama: her hooks in first (so she sees it), Ollama up, then its window.
  freeNow() {
    var _this12 = this;
    return _asyncToGenerator(function* () {
      const t = _this12.t;
      const integration = _this12.brain.assistant === 'codex' ? 'codex' : 'claude';
      const name = integration === 'codex' ? 'Codex' : 'Claude Code';
      const id = yield _this12.guide.ask({
        face: 'smug',
        line: fmt(t.freeLine, {
          name
        }),
        quote: fmt(t.freeHow, {
          name
        }),
        actions: [{
          id: 'go',
          label: t.freeBtn,
          primary: true
        }, {
          id: 'later',
          label: t.later
        }]
      });
      if (id !== 'go') return false;
      const hooks = yield _this12.host.hooksStatus();
      if (!hooks.installed) {
        const res = yield _this12.host.installHooks();
        if (!res.ok) return _this12.fail(t.failed, res.error);
      }
      if (!(yield _this12.ollamaUp())) return false;
      const res = yield _this12.host.launchThroughOllama(integration);
      if (!res.ok) return _this12.fail(t.failed, '');
      _this12.voice.play('hello');
      _this12.capri.perform('hop');
      yield _this12.guide.ask({
        kind: 'done',
        face: 'look',
        line: t.freeOpened,
        quote: fmt(t.freeOpenedHow, {
          name
        }),
        actions: [{
          id: 'ok',
          label: t.ok,
          primary: true
        }]
      });
      return true;
    })();
  }

  // ---------- panels ----------

  // While something runs: what she's doing, no buttons (the scene's end, or the next panel, takes it away).
  working(line, quote = '') {
    this.capri.pulse();
    this.panel.say({
      kind: 'work',
      face: 'calm',
      line,
      quote,
      guide: true,
      hold: null,
      token: Symbol('setup')
    });
  }

  // She can talk: true if you want to now (her chat opens).
  done() {
    var _this13 = this;
    return _asyncToGenerator(function* () {
      _this13.voice.play('hello');
      _this13.capri.perform('hop');
      const id = yield _this13.guide.ask({
        kind: 'done',
        face: 'laugh',
        line: _this13.t.ready,
        quote: _this13.t.readyHow,
        actions: [{
          id: 'talk',
          label: _this13.t.talk,
          primary: true
        }, {
          id: 'later',
          label: _this13.t.later
        }]
      });
      return id === 'talk';
    })();
  }
  fail(line, quote) {
    var _this14 = this;
    return _asyncToGenerator(function* () {
      _this14.capri.hurt();
      yield _this14.guide.ask({
        kind: 'error',
        face: 'wide',
        line,
        quote,
        actions: [{
          id: 'ok',
          label: _this14.t.ok,
          primary: true
        }]
      });
      return false;
    })();
  }
  size(bytes) {
    const gb = bytes >= 1e9;
    // no Intl in QML's JavaScript: the decimal comma by hand
    const n = (gb ? (bytes / 1e9).toFixed(1).replace(/\.0$/, '') : String(Math.round(bytes / 1e6))).replace('.', this.brain.lang === 'en' ? '.' : ',');
    return `${n} ${gb ? this.t.gb : this.t.mb}`;
  }
}