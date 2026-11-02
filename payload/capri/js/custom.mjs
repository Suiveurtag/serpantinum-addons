import {co} from './util.mjs';
function _asyncToGenerator(fn) { return function() { return co(fn.apply(this,arguments)); }; }
// Native port of capri-desktop custom.js; upstream LICENSE in ../LICENSE.
// Making her yours, from her menu: what she calls you, how you want her to be (her chat), lines of
// yours she says now and then, and things to remember. Each one a panel of her guide with a line
// to type in; each can be skipped. Her chat also takes "call me Max" and "remember that…" (chat.js).

import { fmt } from './util.mjs';
const LINES_MAX = 30;
const MEMORIES_MAX = 30;
export class Custom {
  constructor({
    guide,
    host,
    brain,
    capri,
    voice
  }) {
    this.guide = guide;
    this.host = host;
    this.brain = brain;
    this.capri = capri;
    this.voice = voice;
  }
  get t() {
    return this.brain.t.custom;
  }

  // "Make her yours" in her menu
  open() {
    return this.guide.scene(() => this.steps());
  }
  steps() {
    var _this = this;
    return _asyncToGenerator(function* () {
      const t = _this.t;
      const {
        custom
      } = _this.brain;
      _this.capri.perform('curious', _this.capri.towardCenter());
      const name = yield _this.field({
        line: t.name,
        quote: custom.userName ? fmt(t.nameNow, {
          name: custom.userName
        }) : t.nameHow,
        placeholder: t.namePlaceholder
      });
      if (!name) return;
      if (name.text) yield _this.save({
        userName: name.text.slice(0, 24)
      });
      const persona = yield _this.field({
        line: t.persona,
        quote: custom.persona ? fmt(t.personaNow, {
          persona: custom.persona
        }) : t.personaHow,
        placeholder: t.personaPlaceholder,
        clear: Boolean(custom.persona)
      });
      if (!persona) return;
      if (persona.action === 'clear') yield _this.save({
        persona: ''
      });else if (persona.text) yield _this.save({
        persona: persona.text.slice(0, 500)
      });
      if (!(yield _this.list('myLines', {
        line: t.lines,
        how: t.linesHow,
        count: t.linesCount,
        placeholder: t.linePlaceholder,
        max: LINES_MAX
      }))) return;
      if (!(yield _this.list('memories', {
        line: t.memories,
        how: t.memoriesHow,
        count: t.memoriesCount,
        placeholder: t.memoryPlaceholder,
        max: MEMORIES_MAX
      }))) return;
      _this.voice.play('hello');
      _this.capri.perform('hop');
      yield _this.guide.ask({
        kind: 'done',
        face: 'laugh',
        line: t.saved,
        quote: t.savedHow,
        actions: [{
          id: 'ok',
          label: t.done,
          primary: true
        }]
      });
    })();
  }

  // One line to type in: { text } (trimmed), { action: 'skip' | 'clear' }, or null if it went away.
  field(_x) {
    var _this2 = this;
    return _asyncToGenerator(function* ({
      line,
      quote,
      placeholder,
      clear = false
    }) {
      const t = _this2.t;
      const got = yield _this2.guide.askText({
        face: 'look',
        line,
        quote,
        placeholder,
        send: t.save,
        actions: [{
          id: 'skip',
          label: t.skip
        }, ...(clear ? [{
          id: 'clear',
          label: t.clear
        }] : [])]
      });
      return got && (got.action ? got : {
        text: got.text.trim()
      });
    }).apply(this, arguments);
  }

  // A list you add to one at a time (your lines, what she remembers), until "done". False if it went away.
  list(_x2, _x3) {
    var _this3 = this;
    return _asyncToGenerator(function* (key, {
      line,
      how,
      count,
      placeholder,
      max
    }) {
      const t = _this3.t;
      for (;;) {
        const items = _this3.brain.custom[key] || [];
        const got = yield _this3.guide.askText({
          face: items.length ? 'smug' : 'look',
          line,
          quote: items.length ? fmt(count, {
            count: items.length,
            last: items[items.length - 1]
          }) : how,
          placeholder,
          send: t.add,
          actions: [{
            id: 'done',
            label: items.length ? t.done : t.skip
          }, ...(items.length ? [{
            id: 'clear',
            label: t.clear
          }] : [])]
        });
        if (!got) return false;
        if (got.action === 'done') return true;
        if (got.action === 'clear') {
          yield _this3.save({
            [key]: []
          });
          continue;
        }
        const text = got.text.trim().slice(0, 200);
        if (text) yield _this3.save({
          [key]: [...items.filter(i => i !== text), text].slice(-max)
        });
      }
    }).apply(this, arguments);
  }

  // Saved, and known right away (brain.custom), before the config comes back around.
  save(patch) {
    var _this4 = this;
    return _asyncToGenerator(function* () {
      Object.assign(_this4.brain.custom, patch);
      yield _this4.host.setConfig(patch);
    })();
  }
}