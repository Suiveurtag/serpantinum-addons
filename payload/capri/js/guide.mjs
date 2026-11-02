import {co} from './util.mjs';
function _asyncToGenerator(fn) { return function() { return co(fn.apply(this,arguments)); }; }
// Native port of capri-desktop guide.js; upstream LICENSE in ../LICENSE.
// Showing you around: short tutorials where she goes places, points at things with her finger
// and pulls faces. Each topic is a little scene: what she says (and with which face), what she
// points at, and the buttons that move it on. Anything else coming up (Claude doing something,
// you closing the panel) ends it.

import { fmt, performance, setTimeout } from './util.mjs';
const IDLE_FOR = 10 * 60 * 1000; // no wandering off while she's showing you something

// "Where's my icon?" on Serpantinum: no tray icon by the clock; her menu is on her, and Ctrl+Alt+C puts
// her away in that corner.
const ICON = {
  en: { line: 'No icon by the clock here: I’m the icon.', quote: 'Right-click me: my menu. Ctrl+Alt+C tucks me away down here, Super+Shift+K turns me on or off, and Settings › Addons › Capri has the rest.' },
  fr: { line: 'Ici, pas d’icône près de l’horloge : l’icône, c’est moi.', quote: 'Clic droit sur moi : mon menu. Ctrl+Alt+C me range ici, en bas, Super+Shift+K m’allume ou m’éteint, et Réglages › Addons › Capri a le reste.' },
  es: { line: 'Aquí no tengo icono junto al reloj: el icono soy yo.', quote: 'Clic derecho sobre mí: mi menú. Ctrl+Alt+C me guarda aquí abajo, Super+Shift+K me enciende o me apaga, y Ajustes › Addons › Capri tiene el resto.' },
  pt: { line: 'Aqui não tenho ícone perto do relógio: o ícone sou eu.', quote: 'Clique com o botão direito em mim: meu menu. Ctrl+Alt+C me guarda aqui embaixo, Super+Shift+K me liga ou desliga, e Configurações › Addons › Capri tem o resto.' },
  ru: { line: 'Здесь у меня нет значка у часов: значок — это я.', quote: 'Правый клик по мне — моё меню. Ctrl+Alt+C прячет меня сюда, вниз, Super+Shift+K включает и выключает меня, а остальное — в Настройки › Addons › Capri.' },
};

export class Guide {
  constructor({
    capri,
    panel,
    voice,
    host,
    brain
  }) {
    this.capri = capri;
    this.panel = panel;
    this.voice = voice;
    this.host = host;
    this.brain = brain;
    this.waiting = null; // { token, resolve } of the panel on screen
    this.running = false;
    this.sceneId = 0;
    this.setup = null; // setup.js: getting her chat going, and the free way to run Claude Code
    this.onTalk = null; // () => void: "Talk to me" picked in her menu (app.js opens her chat)
    this.custom = null; // custom.js: what she calls you, how she is, your lines
    panel.onAction = id => this.answer(id);
    panel.onDismiss = msg => {
      if (this.waiting && msg.token === this.waiting.token) this.answer(null);
    };
  }
  get t() {
    return this.brain.t.guide;
  }

  // One panel of the guide; resolves with the id of the button you click, or null if it went away.
  ask({
    kind = 'info',
    face,
    line,
    quote,
    badge,
    actions
  }) {
    this.answer(null);
    const token = Symbol('guide');
    return new Promise(resolve => {
      this.waiting = {
        token,
        resolve
      };
      // something more important on screen (a permission prompt, Claude's answer): no guide now
      if (!this.panel.say({
        kind,
        face,
        line,
        quote,
        badge,
        actions,
        guide: true,
        hold: null,
        token
      })) this.answer(null);
    });
  }

  // One of her guide's panels with a line to type in (secret: hidden as you type). Resolves with
  // { text } (what you typed), { action } (a button that ends it), or null if it went away.
  // onAction(id) true: that button did its thing, the panel stays.
  askText({
    face,
    line,
    quote,
    secret = false,
    placeholder,
    send = this.brain.t.setup.save,
    tag,
    note,
    actions = [],
    onAction = () => false
  }) {
    this.answer(null);
    const token = Symbol('guide');
    return new Promise(resolve => {
      let over = false;
      const finish = value => {
        if (over) return;
        over = true;
        if (this.waiting?.token === token) this.waiting = null;
        this.host.focusOverlay(false);
        resolve(value);
      };
      // like ask(): the next panel of a scene, or answer(id), ends it
      this.waiting = {
        token,
        resolve: id => finish(id === null ? null : {
          action: id
        })
      };
      const shown = this.panel.say({
        kind: 'info',
        face,
        line,
        quote,
        guide: true,
        hold: null,
        token,
        chat: {
          placeholder,
          send,
          close: this.brain.t.setup.later,
          noteTag: tag,
          note,
          secret
        },
        actions,
        onAction: id => onAction(id) || finish({
          action: id
        }),
        onSend: text => finish({
          text
        }),
        onLeave: () => finish(null)
      });
      if (!shown) return finish(null);
      this.host.focusOverlay(true); // the keyboard, to type in it
    });
  }
  answer(id) {
    const waiting = this.waiting;
    this.waiting = null;
    waiting?.resolve(id);
  }
  ok(primary = true) {
    return [{
      id: 'ok',
      label: this.t.ok,
      primary
    }];
  }

  // Run a scene: she stays put meanwhile, and stops pointing at the end whatever happened.
  // A new scene ends the one that was on (its panel goes, it returns); only the last one cleans up.
  scene(play) {
    var _this = this;
    return _asyncToGenerator(function* () {
      const {
        capri
      } = _this;
      const id = ++_this.sceneId;
      _this.answer(null);
      capri.stopPointing(); // whatever the last scene was showing
      if (capri.stowed) {
        _this.host.setConfig({
          visible: true
        });
        yield capri.unstow();
      }
      capri.wake();
      _this.running = true;
      capri.nextMove = capri.nextGaze = performance.now() + IDLE_FOR;
      try {
        yield play();
      } finally {
        if (id === _this.sceneId) {
          _this.running = false;
          capri.stopPointing();
          capri.nextMove = performance.now() + 30000;
          capri.nextGaze = performance.now() + 60000;
          if (_this.panel.current?.token) _this.panel.hide();
        }
      }
    })();
  }

  // ---------- topics ----------

  // First launch, or nothing hooked up yet: who she is, and plugging her into Claude Code.
  welcome() {
    var _this2 = this;
    return _asyncToGenerator(function* () {
      let talk = false;
      yield _this2.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        const w = _this2.brain.t.welcome;
        const [hooks, found] = yield Promise.all([_this2.host.hooksStatus(), _this2.host.claudeFound()]);
        if (!_this2.brain.watching) {
          // not watching Claude Code: she's just here to keep you company
          _this2.capri.perform('curious', _this2.capri.towardCenter());
          yield _this2.ask({
            face: 'grin',
            line: w.hi,
            quote: `${w.alone}\n${w.menu}`,
            actions: [{
              id: 'ok',
              label: w.ok,
              primary: true
            }]
          });
        } else if (hooks.installed) {
          _this2.capri.perform('curious', _this2.capri.towardCenter());
          const id = yield _this2.ask({
            face: 'look',
            line: w.ready,
            quote: w.readyHow,
            actions: [{
              id: 'ok',
              label: w.ok,
              primary: true
            }, {
              id: 'more',
              label: _this2.t.more
            }]
          });
          if (id === 'more') talk = (yield _this2.menuNow()) === 'talk';
        } else if (found) {
          yield _this2.connect();
        } else {
          const id = yield _this2.ask({
            face: 'aside',
            line: w.hi,
            quote: `${w.noClaude}\n${w.menu}`,
            actions: [{
              id: 'claude',
              label: w.whatClaude,
              primary: true
            }, ...(_this2.freeWay ? [{
              id: 'free',
              label: _this2.brain.t.setup.free
            }] : []), {
              id: 'later',
              label: w.justHang
            }]
          });
          if (id === 'free') {
            yield _this2.setup.freeNow();
          } else if (id === 'claude') {
            _this2.host.openClaudeHelp();
            yield _this2.ask({
              face: 'smug',
              line: w.hi,
              quote: w.afterInstall,
              actions: [{
                id: 'ok',
                label: w.ok
              }]
            });
          } else if (id === 'later') {
            _this2.host.setConfig({
              claude: false
            }); // just hanging out: no more word of Claude (her menu turns it back on)
          }
        }
        _this2.host.setConfig({
          welcomed: true
        });
      }));
      if (talk) _this2.onTalk?.();
    })();
  }

  // Claude Code and Codex can run for free through Ollama (`ollama launch`): she offers it for those two
  get freeWay() {
    return Boolean(this.setup) && ['claude', 'codex'].includes(this.brain.assistant);
  }

  // "How does it work?" in her menu: what she can show you.
  menu() {
    var _this3 = this;
    return _asyncToGenerator(function* () {
      let talk = false;
      yield _this3.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        talk = (yield _this3.menuNow()) === 'talk';
      }));
      if (talk) _this3.onTalk?.();
    })();
  }
  menuNow() {
    var _this4 = this;
    return _asyncToGenerator(function* () {
      const t = _this4.t;
      const hooks = yield _this4.host.hooksStatus();
      const actions = [];
      const watching = _this4.brain.watching; // else nothing about Claude to show
      if (watching && !hooks.installed) actions.push({
        id: 'connect',
        label: t.topics.connect,
        primary: true
      });
      actions.push({
        id: 'icon',
        label: t.topics.icon,
        primary: !watching || hooks.installed
      });
      if (watching) {
        actions.push({
          id: 'claude',
          label: t.topics.claude
        });
        actions.push({
          id: 'folder',
          label: t.topics.folder
        });
      }
      actions.push({
        id: 'talk',
        label: t.topics.talk
      });
      if (_this4.custom) actions.push({
        id: 'custom',
        label: t.topics.custom
      });
      actions.push({
        id: 'close',
        label: t.topics.close
      });
      _this4.capri.perform('curious', _this4.capri.towardCenter());
      const id = yield _this4.ask({
        face: 'smug',
        line: t.menu.line,
        quote: t.menu.quote,
        actions
      });
      if (id === 'talk') return 'talk'; // her chat opens once the scene is over (menu, welcome)
      if (id === 'custom') yield _this4.custom.steps();
      if (id === 'connect') yield _this4.connect();else if (id === 'icon') yield _this4.icon();else if (id === 'claude') yield _this4.claude();else if (id === 'folder') yield _this4.folder();
    })();
  }

  // Plugging her into Claude Code: one click, then a fresh Claude Code session.
  connect() {
    var _this5 = this;
    return _asyncToGenerator(function* () {
      const w = _this5.brain.t.welcome;
      const id = yield _this5.ask({
        face: 'grin',
        line: w.hi,
        quote: `${w.about}\n${w.connect}\n${w.menu}`,
        actions: [{
          id: 'connect',
          label: w.connectBtn,
          primary: true
        }, ...(_this5.freeWay ? [{
          id: 'free',
          label: _this5.brain.t.setup.free
        }] : []), {
          id: 'later',
          label: w.later
        }]
      });
      if (id === 'free') {
        yield _this5.setup.freeNow(); // her hooks, then Claude Code (or Codex) through Ollama
        return;
      }
      if (id !== 'connect') return;
      const result = yield _this5.host.installHooks();
      if (!result.ok) {
        _this5.capri.hurt();
        yield _this5.ask({
          kind: 'error',
          face: 'wide',
          line: fmt(w.failed, {
            error: result.error
          }),
          actions: _this5.ok()
        });
        return;
      }
      _this5.voice.play('hello');
      _this5.capri.perform('hop');
      // she knows where Claude is if you've used it with her before: she shows you where to restart it
      const win = _this5.claudeWindow();
      const scene = _this5.sceneId;
      if (win && _this5.capri.canPoint(win)) yield _this5.capri.pointAt(win, {
        label: _this5.t.labels.claude
      });
      if (scene !== _this5.sceneId) return; // another scene took over meanwhile
      yield _this5.ask({
        kind: 'done',
        face: 'laugh',
        line: w.connected,
        quote: w.restart,
        actions: [{
          id: 'ok',
          label: w.ok
        }]
      });
    })();
  }

  // Where her tray icon is: she goes down to the clock and points at it.
  icon() {
    var _this6 = this;
    return _asyncToGenerator(function* () {
      const t = ICON[_this6.brain.lang] || ICON.en; // no tray icon on this shell: her chip's corner instead
      const place = yield _this6.host.trayPlace();
      const scene = _this6.sceneId;
      yield _this6.capri.pointAt(place.icon || place.corner, {
        label: _this6.t.labels.icon
      });
      if (scene !== _this6.sceneId) return; // another scene took over meanwhile
      yield _this6.ask({
        face: 'look',
        line: t.line,
        quote: t.quote,
        actions: _this6.ok()
      });
    })();
  }

  // Where Claude is: the window you typed your last prompt in.
  claude() {
    var _this7 = this;
    return _asyncToGenerator(function* () {
      const t = _this7.t.claude;
      const win = _this7.claudeWindow();
      if (!win) {
        yield _this7.ask({
          face: 'aside',
          line: t.unknown,
          quote: t.unknownHow,
          actions: _this7.ok()
        });
      } else if (!_this7.capri.canPoint(win)) {
        yield _this7.ask({
          face: 'calm',
          line: t.behind,
          quote: t.behindHow,
          actions: _this7.ok()
        });
      } else {
        const scene = _this7.sceneId;
        yield _this7.capri.pointAt(win, {
          label: _this7.t.labels.claude
        });
        if (scene !== _this7.sceneId) return; // another scene took over meanwhile
        yield _this7.ask({
          face: 'look',
          line: t.there,
          quote: t.thereHow,
          actions: _this7.ok()
        });
      }
    })();
  }

  // Claude Code's folder: she opens it, waits for the window to come up, and points at it.
  folder() {
    var _this8 = this;
    return _asyncToGenerator(function* () {
      const t = _this8.t.folder;
      const {
        capri
      } = _this8;
      const before = capri.windows.fg;
      const opened = yield _this8.host.openClaudeFolder();
      if (!opened.found) {
        yield _this8.ask({
          face: 'wide',
          line: t.missing,
          quote: t.missingHow,
          actions: _this8.ok()
        });
        return;
      }
      // Explorer comes up in front: a new window, or the one already showing that folder, brought back
      const front = () => capri.windows.wins.find(w => w.id === capri.windows.fg) || null;
      const win = (yield _this8.until(() => capri.windows.fg !== before ? front() : null, 2500)) || front();
      const scene = _this8.sceneId;
      if (win && capri.canPoint(win)) yield capri.pointAt(win, {
        label: opened.label || (_this8.brain.assistant === 'claude' ? 'settings.json' : 'hooks.json')
      });
      if (scene !== _this8.sceneId) return; // another scene took over meanwhile
      const id = yield _this8.ask({
        face: 'smug',
        line: fmt(t.line, {
          dir: opened.dir
        }),
        quote: opened.file ? t.what : t.empty,
        actions: [{
          id: 'next',
          label: _this8.t.next,
          primary: true
        }, {
          id: 'close',
          label: _this8.t.ok
        }]
      });
      if (id !== 'next') return;
      yield _this8.ask({
        face: 'calm',
        line: t.hook,
        quote: t.hookHow,
        actions: _this8.ok()
      });
    })();
  }

  // ---------- helpers ----------

  // Claude's window: the one you typed your last prompt in, if it's still around.
  claudeWindow() {
    const {
      wins
    } = this.capri.windows;
    const sessions = [...this.brain.sessions.values()].filter(s => s.window).sort((a, b) => b.seen - a.seen);
    for (const s of sessions) {
      const win = wins.find(w => w.id === s.window);
      if (win) return win;
    }
    return null;
  }
  until(find, max) {
    return new Promise(resolve => {
      const t0 = performance.now();
      const look = () => {
        const found = find();
        if (found || performance.now() - t0 > max) resolve(found || null);else setTimeout(look, 100);
      };
      look();
    });
  }
}