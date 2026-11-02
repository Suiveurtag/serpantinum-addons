import {co} from './util.mjs';
function _asyncToGenerator(fn) { return function() { return co(fn.apply(this,arguments)); }; }
// Native port of capri-desktop look.js; upstream LICENSE in ../LICENSE. The picture is taken by the
// sidecar (grim, the screen she's on), kept in its memory a moment, never written to disk.
// She looks at your screen and says something about it: when you ask (her menu › Look at my screen),
// or on her own now and then (her menu, off until you turn it on). The first time, she tells you
// where the picture goes: to the AI behind her chat, on your PC with a local model, else to that
// service. Then: a picture of the screen she's on (main.js keeps it in memory a moment, never on
// disk), her eyes on the window in front while a scanline sweeps it, and one or two sentences from
// her AI, in character. Her chat remembers what she said, for a while.

import { fmt, rand, setInterval } from './util.mjs';
import { clean, mood } from './chat.mjs';
const FIRST_AFTER = 2 * 60 * 1000; // turned on: her first look a couple of minutes later
const EVERY = [8, 15]; // then every 8 to 15 minutes…
const ACTIVE_MS = 90 * 1000; // …if you're at your PC (the pointer moved lately)…
const SAME_WINDOW_MS = 25 * 60 * 1000; // …and on another window than last time (or a good while later)
// what her AI is asked about the picture
const PROMPT = 'This is a picture of the user\'s screen right now. If you see a small figure with a big red mane, that\'s you: leave it out. Name one concrete thing you really see on it (the app or website, a title, a picture, a word), then react to it in character: curious, playful or teasing. One or two short sentences, talking to them.';
export class Look {
  constructor({
    capri,
    panel,
    brain,
    chat,
    guide,
    host,
    fx,
    voice,
    active
  }) {
    this.capri = capri;
    this.panel = panel;
    this.brain = brain;
    this.chat = chat;
    this.guide = guide;
    this.host = host;
    this.fx = fx;
    this.voice = voice;
    this.active = active; // () => ms since the pointer last moved
    this.auto = false; // her menu: Look at my screen now and then
    this.asked = false; // you've been told what it means, and said yes
    this.looking = false;
    this.nextAt = 0;
    this.lastFg = null;
    this.lastAt = 0;
    setInterval(() => this.tick(), 30000);
  }
  get t() {
    return this.brain.t.look;
  }
  configure({
    watchScreen,
    lookAsked
  }) {
    const on = Boolean(watchScreen);
    if (on && !this.auto) this.nextAt = Date.now() + FIRST_AFTER;
    this.auto = on;
    this.asked = Boolean(lookAsked);
  }

  // What looking means (where the picture goes), before the first time. True if you said yes.
  ask() {
    var _this = this;
    return _asyncToGenerator(function* ({
      auto = false
    } = {}) {
      const where = yield _this.host.lookWhere().catch(() => ({}));
      const t = _this.t;
      const model = where.model || '…';
      let yes = false;
      yield _this.guide.scene(/*#__PURE__*/_asyncToGenerator(function* () {
        _this.capri.perform('curious', _this.capri.towardCenter());
        const id = yield _this.guide.ask({
          face: 'look',
          line: t.ask,
          quote: [fmt(where.local ? t.local : t.online, {
            model,
            service: where.provider || ''
          }), auto ? t.auto : ''].filter(Boolean).join('\n'),
          actions: [{
            id: 'yes',
            label: t.yes,
            primary: true
          }, {
            id: 'no',
            label: t.no
          }]
        });
        yes = id === 'yes';
      }));
      if (yes) {
        _this.asked = true;
        yield _this.host.setConfig(Object.assign({
          lookAsked: true
        }, auto && {
          watchScreen: true
        }));
      }
      return yes;
    }).apply(this, arguments);
  }

  // From her menu: turned on (she asks first, the first time) or off.
  setAuto(on) {
    var _this2 = this;
    return _asyncToGenerator(function* () {
      if (!on) {
        _this2.host.setConfig({
          watchScreen: false
        });
        return;
      }
      if (!_this2.asked && !(yield _this2.ask({
        auto: true
      }))) return;
      if (_this2.asked) yield _this2.host.setConfig({
        watchScreen: true
      });
      _this2.panel.say({
        kind: 'info',
        asked: true,
        face: 'smug',
        line: _this2.t.on,
        hold: 3500
      });
    })();
  }

  // From her menu: one look, now.
  once() {
    var _this3 = this;
    return _asyncToGenerator(function* () {
      if (!_this3.asked && !(yield _this3.ask())) return;
      _this3.now({
        manual: true
      });
    })();
  }

  // On her own: now and then, when you're there, on another window than last time, and she's free.
  tick() {
    if (!this.auto || !this.asked || this.looking || Date.now() < this.nextAt) return;
    if (this.active() > ACTIVE_MS || !this.free()) return;
    const fg = this.capri.windows.fg;
    if (fg === this.lastFg && Date.now() - this.lastAt < SAME_WINDOW_MS) return;
    this.nextAt = Date.now() + rand(EVERY[0], EVERY[1]) * 60 * 1000;
    this.now();
  }
  free() {
    const {
      capri,
      panel
    } = this;
    if (capri.busy || capri.dragging || capri.stowed || capri.dormant || capri.hidden || capri.act || capri.pointing) return false;
    if (!['stand', 'sit'].includes(capri.stance) || capri.mode === 'alert' || capri.mode === 'sleep') return false;
    return !this.chat.open && !this.guide.running && !panel.visible;
  }

  // her eyes on the window in front (or the whole screen) while a scanline sweeps it
  effect() {
    const {
      wins,
      fg
    } = this.capri.windows;
    const win = wins.find(w => w.id === fg && !w.max);
    const {
      w,
      floor
    } = this.capri.view;
    const rect = win ? () => this.capri.windows.wins.find(o => o.id === win.id) || null : () => ({
      x: 0,
      y: 0,
      w,
      h: floor
    });
    const toward = win ? Math.sign(win.x + win.w / 2 - this.capri.pos.x) || 1 : this.capri.towardCenter();
    this.capri.perform('curious', toward);
    this.fx.cutin(...this.capri.cutinAt(-toward), {
      kind: 'eyes',
      life: 520
    });
    this.fx.scan(rect, {
      covers: () => win ? this.capri.coversOf(win.id) : []
    });
    this.voice.play('charge');
  }
  now() {
    var _this4 = this;
    return _asyncToGenerator(function* ({
      manual = false
    } = {}) {
      if (_this4.looking) return;
      _this4.looking = true;
      const t = _this4.t;
      try {
        if (manual) {
          if (_this4.capri.stowed) {
            _this4.host.setConfig({
              visible: true
            });
            yield _this4.capri.unstow();
          }
          _this4.capri.wake();
        }
        const snap = yield _this4.host.lookSnap();
        if (!snap.ok) {
          if (manual) _this4.panel.say({
            kind: 'info',
            asked: manual, // you asked: shown even in Do Not Disturb
            face: 'aside',
            line: fmt(t.failed, {
              error: snap.error
            }),
            hold: 6000
          });
          return;
        }
        _this4.lastFg = _this4.capri.windows.fg;
        _this4.lastAt = Date.now();
        _this4.effect();
        const res = yield _this4.host.lookSay({
          id: snap.id,
          persona: _this4.chat.lookPersona(),
          prompt: `${PROMPT}\n${_this4.chat.languageNote()}`
        });
        if (!res.ok) {
          if (res.code === 'novision') {
            // her model can't see: said once, and she stops trying on her own
            _this4.panel.say({
              kind: 'info',
              asked: manual, // you asked: shown even in Do Not Disturb
              face: 'aside',
              line: fmt(t.noVision, {
                model: String(res.model || '…').replace(/:latest$/, '')
              }),
              hold: 9000
            });
            if (_this4.auto) _this4.host.setConfig({
              watchScreen: false
            });
          } else if (manual) {
            _this4.panel.say({
              kind: 'info',
              asked: manual, // you asked: shown even in Do Not Disturb
              face: 'aside',
              line: res.code === 'noai' ? t.noAI : fmt(t.failed, {
                error: res.error || '…'
              }),
              hold: 7000
            });
          }
          return;
        }
        const text = clean(res.text).replace(/^["“«]\s*|\s*["”»]$/g, ''); // no quotes around what she says
        if (!text) return;
        _this4.chat.seen = {
          text,
          at: Date.now()
        };
        _this4.panel.say({
          kind: 'info',
          asked: manual, // you asked: shown even in Do Not Disturb
          badge: 'SCAN',
          face: mood(text),
          line: text,
          hold: Math.min(13000, Math.max(5000, 2500 + text.length * 55))
        });
      } finally {
        _this4.looking = false;
      }
    }).apply(this, arguments);
  }
}