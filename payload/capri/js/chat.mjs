import {co} from './util.mjs';
function _asyncToGenerator(fn) { return function() { return co(fn.apply(this,arguments)); }; }
// Native port of capri-desktop chat.js; upstream LICENSE in ../LICENSE.
import { pick, fmt, performance, setTimeout, clearTimeout } from './util.mjs';
import { ASSISTANT_NAMES } from './lines.mjs';
const REMEMBER = 20,
  KEEP = 60;
const IN_LANGUAGE = {
  fr: {
    we: '"on" or "nous" in French',
    last: 'Écris tout en français, sauf si l’utilisateur t’écrit dans une autre langue : alors dans la sienne. Seuls les mots d’argot de Night City restent en anglais, jamais une phrase entière.',
    now: 'Réponds en français, sauf si ce message est écrit dans une autre langue.'
  },
  en: {
    we: '',
    last: 'Write everything in English, unless the user writes to you in another language: then in theirs.',
    now: 'Answer in English, unless this message is written in another language.'
  },
  es: {
    we: '"nosotros" in Spanish',
    last: 'Escribe todo en español, salvo si el usuario te escribe en otro idioma: entonces en el suyo. Solo las palabras de jerga de Night City se quedan en inglés, nunca una frase entera.',
    now: 'Responde en español, salvo si este mensaje está escrito en otro idioma.'
  },
  pt: {
    we: '"a gente" or "nós" in Portuguese',
    last: 'Escreva tudo em português do Brasil, a não ser que o usuário te escreva em outra língua: aí, na dele. Só as gírias de Night City ficam em inglês, nunca uma frase inteira.',
    now: 'Responda em português do Brasil, a não ser que esta mensagem esteja escrita em outra língua.'
  },
  ru: {
    we: '"мы" in Russian',
    last: 'Пиши всё по-русски, если только пользователь не пишет тебе на другом языке: тогда на его языке. По-английски остаются только словечки Найт-Сити, никогда не целые фразы.',
    now: 'Отвечай по-русски, если только это сообщение не написано на другом языке.'
  }
};
const STAY_MS = 10 * 60 * 1000;
const LOADING_AFTER_MS = 5000;
const CLOSE_TAG = /\[\[\s*close\s*:?\s*([^\]]*)\]\]/i;
const CLOSE_ASK = /\b(close|shut|quit|kill|exit)|ferm|quitt|coupe|arr[êe]t|cierr|cerra|fech|закр|выключ/i;
const TAG = /\[\[\s*(open|music|media|site)\s*:\s*([^\]]*)\]\]/i;
const OPEN_ASK = /\b(open|launch|start|run)\b|ouvr|lance|démarre|abre|abrir|inicia|ejecuta|executa|открой|запусти/i;
const MEDIA_ASK = [['pause', /\b(pause|pausa|pausar)\b|stop (the )?music|arrête la musique|пауз/i], ['next', /\b(next|skip|suivante?|siguiente|próxima|proxima)\b|passe (à )?la suivante|salta|pula|следующ/i], ['previous', /\b(previous|précédente?|anterior)\b|предыдущ/i], ['play', /\b(resume|reprends|reanuda|retoma)\b|relance la musique|remets la musique|продолж/i], ['volup', /\b(louder|plus fort)\b|monte le son|turn (it )?up|sube el volumen|aumenta o volume|громче/i], ['voldown', /\b(quieter|moins fort)\b|baisse le son|turn (it )?down|baja el volumen|abaixa o volume|тише/i], ['mute', /\bmute\b|coupe le son|silencia|sem som|выключи звук/i]];
const MUSIC_WORD = /musi|chanson|song|track|titre|morceau|spotify|canci|faixa|песн|музык|трек/i;
const MEDIA_ACTIONS = new Set(MEDIA_ASK.map(([action]) => action));
const SITES = {
  youtube: 'https://www.youtube.com',
  google: 'https://www.google.com',
  gmail: 'https://mail.google.com',
  twitch: 'https://www.twitch.tv',
  netflix: 'https://www.netflix.com',
  reddit: 'https://www.reddit.com',
  twitter: 'https://x.com',
  instagram: 'https://www.instagram.com',
  tiktok: 'https://www.tiktok.com',
  facebook: 'https://www.facebook.com',
  github: 'https://github.com',
  chatgpt: 'https://chatgpt.com',
  wikipedia: 'https://www.wikipedia.org',
  linkedin: 'https://www.linkedin.com',
  pinterest: 'https://www.pinterest.com',
  crunchyroll: 'https://www.crunchyroll.com',
  outlook: 'https://outlook.live.com',
  whatsapp: 'https://web.whatsapp.com',
  discord: 'https://discord.com/app',
  soundcloud: 'https://soundcloud.com',
  deezer: 'https://www.deezer.com'
};
const BROWSER = /chrome|edge|firefox|opera|brave|vivaldi|duckduckgo|browser/i;
const TINY = /[:-](0\.5b|1b|1\.5b|135m|270m|360m)\b/i;
const MOOD_FACE = {
  angry: 'many',
  sulk: 'aside',
  dizzy: 'wide',
  thrown: 'wide',
  jealous: 'look',
  fun: 'laugh',
  happy: 'laugh',
  forgiven: 'smug'
};
const LISTEN = /[ée]cout|listen|escuch|\bouv(ir|e)\b|слуша|playlist|album|\b(play|joue|mets|pon|toca|coloca)\b|включи|поставь/i;
const SOUND = /\b(sound|volume|volumen)\b|\b(le|du|au) son\b|\bo som\b|звук|громк/i;
const PLAY = /\bjou(er|e)\b|\bplay\b|jugar|juega|jogar|joga|играть|поигра/i;
const SITE = /\b(site|web|page|lien|link|url|enlace|p[aá]gina)|сайт|ссылк|\.(com|fr|org|net|io|gg|tv|be|ch|ca|es|br|pt|ru)\b/i;
const MEMORIES_MAX = 30;
export class Chat {
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
    this.history = []; // your chats with her, [{ role, content }], kept by main.js across restarts
    this.warm = false; // a model already answered this run (Ollama's first answer waits for it to load)
    this.open = false;
    this.turn = 0; // id of the answer coming in, if any
    this.answer = '';
    this.apps = []; // the apps open on this PC, as last listed: [{ name, label }]
    this.appsReady = Promise.resolve();
    this.onSetup = null; // (status) => void: she can't answer yet (app.js hands it to setup.js)
    this.onBetterModel = null; // () => void: a bigger model than the tiny one she's on (setup.js)
    this.reminders = null; // the reminders she keeps (reminders.js, from app.js)
    this.bond = null; // how close she is to you (bond.js)
    this.jealousy = null; // and how she takes your other AIs
    this.onMessage = null; // () => void: you said something to her
    this.waitingWhen = null; // a reminder you asked for without saying when: { text, until }
    host.onChatDelta(({
      id,
      text
    }) => this.onDelta(id, text));
  }
  get t() {
    return this.brain.t.chat;
  }
  start() {
    var _this = this;
    return _asyncToGenerator(function* () {
      const {
        capri,
        host,
        t
      } = _this;
      if (_this.open) {
        _this.panel.chatInput.focus();
        return;
      }
      if (capri.stowed) {
        host.setConfig({
          visible: true
        });
        yield capri.unstow();
      }
      capri.wake();
      const status = yield host.chatStatus();
      _this.status = status;
      if (!status.ok && _this.onSetup) {
        _this.onSetup(status); // nothing to talk with yet: she sets it up with you, with buttons (setup.js)
        return;
      }
      if (!status.ok) {
        // no Ollama, or nothing to talk with yet: what to do about it
        const offline = status.error === 'offline';
        const other = !offline && status.error !== 'nomodel'; // another provider, saying why
        capri.perform('curious', capri.towardCenter());
        _this.panel.say({
          kind: 'info',
          face: 'aside',
          guide: true,
          line: other ? t.failed : offline ? t.offline : t.noModel,
          quote: other ? status.error : offline ? t.offlineHow : t.noModelHow,
          actions: offline ? [{
            id: 'get',
            label: t.getOllama,
            primary: true
          }, {
            id: 'ok',
            label: t.ok
          }] : [{
            id: 'ok',
            label: t.ok,
            primary: true
          }],
          onAction: id => {
            if (id === 'get') host.openOllama();
            _this.panel.hide();
          },
          hold: null
        });
        return;
      }
      _this.history = yield host.chatMemory().catch(() => _this.history); // "forget" in her menu may have emptied it
      _this.cold = status.warmup && !_this.warm;
      _this.agent = Boolean(status.agent); // Claude Code answers, as her, and really works in your project
      _this.listApps();
      const shortModel = status.model.replace(/:latest$/, '').replace(/^models\//, ''); // Ollama's tag, Gemini's prefix
      const tiny = status.provider === 'ollama' && TINY.test(status.model) && _this.onBetterModel;
      // angry, sulking, dizzy…: she greets you the way she feels, and her model is told she did
      const feeling = _this.bond?.feeling;
      const moody = !tiny && feeling && t.moody[feeling];
      const hello = moody ? fmt(pick(moody), _this.bond.mood.vars) : pick(_this.history.length ? t.again : t.hello);
      _this.opening = moody ? hello : null;
      host.focusOverlay(true); // the keyboard, for typing to her
      const shown = _this.panel.say({
        kind: 'chat',
        face: moody ? MOOD_FACE[feeling] : 'look',
        badge: t.badge,
        tag: shortModel,
        line: tiny ? fmt(t.tiny, {
          model: shortModel
        }) : hello,
        actions: tiny ? [{
          id: 'better',
          label: t.better,
          primary: true
        }] : [],
        onAction: () => {
          _this.panel.hide(); // her chat holds off her guide's panels: it goes first
          _this.onBetterModel?.();
        },
        chat: {
          placeholder: t.placeholder,
          send: t.send,
          close: t.close,
          noteTag: t.noteTag,
          note: status.local ? t.note : t.noteCloud
        },
        onSend: text => _this.send(text),
        onLeave: () => _this.close(),
        hold: null
      });
      if (!shown) {
        host.focusOverlay(false); // something more important is on (a permission prompt)
        return;
      }
      _this.open = true;
      setTimeout(() => _this.panel.chatInput.focus(), 150); // once the overlay has the keyboard
      capri.perform('hop');
      capri.nextMove = capri.nextGaze = performance.now() + STAY_MS;
    })();
  }
  close() {
    if (!this.open) return;
    this.open = false;
    if (this.turn) {
      this.host.chatStop(this.turn);
      if (this.history.length && this.history[this.history.length - 1].role === 'user') this.history.pop();
    }
    this.turn = 0;
    this.host.focusOverlay(false);
    this.capri.nextMove = performance.now() + 30000;
    this.capri.nextGaze = performance.now() + 60000;
  }
  send(text) {
    var _this2 = this;
    return _asyncToGenerator(function* () {
      if (_this2.turn || !_this2.open) return;
      const id = Date.now();
      _this2.turn = id;
      _this2.answer = '';
      _this2.history.push({
        role: 'user',
        content: text
      });
      _this2.panel.setChatBusy(true);
      _this2.panel.setActions([]); // a close button she offered before goes with a new message
      _this2.panel.chatTurn({
        quote: text,
        face: 'aside'
      });
      _this2.capri.pulse();
      _this2.onMessage?.();
      // what you asked for plainly happens right away (the music, the volume, an app you named): her
      // line about it comes under her answer (Claude Code, answering her chat, does things its own way)
      const asked = _this2.agent ? null : yield _this2.host.chatIntent(text, _this2.apps, _this2.waitingWhen);
      if (asked && asked.kind === 'look' && _this2.look) return _this2.sendLook(text, id);
      if (_this2.turn !== id || !_this2.open) return;
      const early = asked && asked.kind !== 'close' ? yield _this2.doNow(asked) : null;
      if (_this2.turn !== id || !_this2.open) return;
      _this2.bond?.heard(text); // "sorry": she lets it go
      yield Promise.race([_this2.appsReady, new Promise(r => setTimeout(r, 1500))]);
      // what she greeted you with (angry, sulking…), in the conversation before your message, so her
      // answer carries on from it (after another answer of hers: added to that one, never two in a row)
      if (_this2.opening) {
        const at = _this2.history.length - 1;
        const before = _this2.history[at - 1];
        if (before?.role === 'assistant') _this2.history[at - 1] = Object.assign({}, before, {
          content: `${before.content}\n${_this2.opening}`
        });else _this2.history.splice(at, 0, {
          role: 'assistant',
          content: _this2.opening
        });
        _this2.opening = null;
      }
      const messages = [{
        role: 'system',
        content: _this2.persona()
      }, ..._this2.history.slice(-REMEMBER)];
      // Her mood (angry, sulking…) and her language, said again right by your message, for this answer
      // only. Small local models mostly go by the last thing they read: up in her prompt alone, they
      // forget it (and answer in English after a conversation in English).
      if (!_this2.agent) {
        const mood = _this2.bond?.moodLine().replace(/^Right now: /, '');
        const last = messages[messages.length - 1];
        messages[messages.length - 1] = Object.assign({}, last, {
          content: `${last.content}\n\n(Note for you, never repeat it: ${[mood, _this2.languageNote()].filter(Boolean).join(' ')})`
        });
      }
      // nothing yet after a few seconds: Ollama is still loading the model (the first answer after a start),
      // or Claude Code is at work
      const wait = _this2.agent ? _this2.t.working : _this2.status.provider === 'chatgpt' ? '…' : _this2.t.loading;
      const slow = wait && setTimeout(() => {
        if (_this2.turn === id && !_this2.answer) _this2.panel.stream(wait);
      }, _this2.status.provider === 'chatgpt' ? 1800 : LOADING_AFTER_MS);
      const res = yield _this2.host.chatSend({
        id,
        messages
      });
      clearTimeout(slow);
      if (_this2.turn !== id) {
        // closed meanwhile: your message goes too, or the next answer would answer it as well
        if (_this2.history[_this2.history.length - 1]?.content === text) _this2.history.pop();
        return;
      }
      _this2.turn = 0;
      if (!res.ok) {
        _this2.history.pop();
        _this2.panel.setFace('wide');
        // too busy or gone even after trying other models (main.js): said plainly, not the server's JSON
        _this2.panel.stream(res.code === 'busy' ? _this2.t.swamped : res.code === 'gone' ? _this2.t.gone : `${_this2.t.failed} ${res.error}`, {
          done: true
        });
        _this2.panel.setChatBusy(false);
        return;
      }
      const answer = clean(res.text) || '…';
      _this2.warm = true;
      _this2.remember({
        role: 'assistant',
        content: answer
      });
      _this2.panel.stream(answer, {
        done: true
      });
      _this2.panel.setFace(mood(answer));
      _this2.panel.setChatBusy(false);
      if (!_this2.agent) _this2.after(res.text, answer, asked, early, text);
      _this2.listApps(); // fresh for the next message
    })();
  }

  // "Look at my screen" in her chat: she looks (asking you first, the first time) and answers here,
  // the conversation so far in mind.
  sendLook(text, id) {
    var _this = this;
    return _asyncToGenerator(function* () {
      const tl = _this.brain.t.look;
      const say = (line, face = 'aside') => {
        if (_this.turn !== id) return;
        _this.turn = 0;
        _this.remember({
          role: 'assistant',
          content: line
        });
        _this.panel.stream(line, {
          done: true
        });
        _this.panel.setFace(face);
        _this.panel.setChatBusy(false);
      };
      if (!_this.look.asked) {
        const where = yield _this.host.lookWhere().catch(() => ({}));
        _this.history.pop(); // your message comes back once you've said yes
        say(`${tl.ask} ${fmt(where.local ? tl.local : tl.online, {
          model: where.model || '…',
          service: where.provider || ''
        })}`, 'look');
        _this.panel.setActions([{
          id: 'yes',
          label: tl.yes,
          primary: true
        }, {
          id: 'no',
          label: tl.no
        }], _asyncToGenerator(function* (choice) {
          _this.panel.setActions([]);
          if (choice !== 'yes') {
            _this.interject(tl.declined, [], null);
            return;
          }
          yield _this.host.setConfig({
            lookAsked: true
          });
          _this.look.asked = true;
          _this.send(text);
        }));
        return;
      }
      const snap = yield _this.host.lookSnap();
      if (!snap.ok) return say(fmt(tl.failed, {
        error: snap.error
      }));
      _this.look.effect();
      const res = yield _this.host.lookSay({
        id: snap.id,
        persona: _this.lookPersona(),
        history: _this.history.slice(-REMEMBER, -1),
        prompt: `${text}\n\n(Note for you, never repeat it: the picture is the user's screen right now; a small figure with a big red mane on it is you. Answer about what you really see, in character. ${_this.languageNote()})`
      });
      if (!res.ok) {
        const model = String(res.model || '…').replace(/:latest$/, '');
        return say(res.code === 'novision' ? fmt(tl.noVision, {
          model
        }) : res.code === 'noai' ? tl.noAI : fmt(tl.failed, {
          error: res.error || '…'
        }));
      }
      const answer = clean(res.text).replace(/^["“«]\s*|\s*["”»]$/g, '') || '…';
      _this.seen = {
        text: answer,
        at: Date.now()
      };
      return say(answer, mood(answer));
    })();
  }
  // an answer of hers, kept with your message before it
  remember(message) {
    this.history.push(message);
    this.history = this.history.slice(-KEEP);
    this.host.chatRemember(this.history);
  }
  listApps() {
    this.appsReady = this.host.openApps().then(list => {
      this.apps = list || [];
    }).catch(() => {});
  }

  // What you asked plainly, read off your message (a small model doesn't always write its tag right):
  // { kind: 'media', action } | { kind: 'music', song } | { kind: 'close', name } | { kind: 'open', text }
  // Doing it now. Resolves with her line about it ({ line, face }), or null if there was nothing to do.
  doNow(asked) {
    var _this3 = this;
    return _asyncToGenerator(function* () {
      const {
        t
      } = _this3;
      const custom = _this3.brain.custom;
      if (asked.kind === 'remind') {
        if (!asked.at) {
          _this3.waitingWhen = {
            text: asked.text,
            until: Date.now() + 3 * 60 * 1000
          }; // her answer asks when
          return null;
        }
        _this3.waitingWhen = null;
        const r = _this3.reminders.add(asked.at, asked.text); // set before her answer is asked for: she knows
        const tr = _this3.brain.t.remind;
        return {
          line: fmt(r.text ? tr.set : tr.setBare, {
            time: _this3.host.clock(r.at, _this3.brain.lang),
            text: r.text
          }),
          face: 'smug',
          reminder: r.id
        };
      }
      if (asked.kind === 'name') {
        custom.userName = asked.name; // her answer, being written now, already knows it
        _this3.host.setConfig({
          userName: asked.name
        });
        return {
          line: fmt(_this3.brain.t.custom.named, {
            name: asked.name
          }),
          face: 'laugh'
        };
      }
      if (asked.kind === 'memo') {
        custom.memories = [...(custom.memories || []).filter(m => m !== asked.text), asked.text].slice(-MEMORIES_MAX);
        _this3.host.setConfig({
          memories: custom.memories
        });
        return {
          line: _this3.brain.t.custom.remembered,
          face: 'smug'
        };
      }
      if (asked.kind === 'media') {
        _this3.capri.pulse();
        return (yield _this3.host.media(asked.action)) ? {
          line: t.media[asked.action],
          face: 'smug'
        } : null;
      }
      if (asked.kind === 'music') {
        _this3.zap();
        return (yield _this3.host.music(asked.song)) ? {
          line: fmt(t.music, {
            song: asked.song
          }),
          face: 'laugh'
        } : null;
      }
      if (asked.kind === 'youtube') return _this3.youtube(asked.song);
      if (asked.kind === 'roblox') {
        _this3.zap();
        const res = yield _this3.host.roblox(asked.game);
        if (!res) return null;
        if (!res.name) return {
          line: fmt(t.robloxNone, {
            game: asked.game
          }),
          face: 'aside'
        };
        return {
          line: fmt(res.app ? t.robloxPlay : t.robloxPage, {
            game: res.name
          }),
          face: 'laugh'
        };
      }
      if (asked.kind === 'web') {
        _this3.zap();
        return (yield _this3.host.webSearch(asked.query)) ? {
          line: fmt(t.web, {
            query: asked.query
          }),
          face: 'smug'
        } : null;
      }
      if (asked.kind === 'files') {
        const results = yield _this3.host.searchFiles({
          query: asked.query,
          exts: asked.exts
        });
        const asking = asked.query || asked.exts.map(e => `.${e}`).join(' ');
        if (!results.length) return {
          line: fmt(t.filesNone, {
            query: asking
          }),
          face: 'aside'
        };
        const list = results.slice(0, 3).map(f => `${f.name} (${f.folder})`).join(', ');
        const lines = [fmt(results.length === 1 ? t.fileFound : t.filesFound, {
          count: results.length,
          list
        })];
        // "…and open the folder" / "…and open it": done right away, on the newest one
        if (asked.then === 'folder' && (yield _this3.host.openFile(results[0].path, true))) lines.push(fmt(t.folderOpened, {
          name: results[0].name
        }));
        // (never a program or a script on its own: that one waits for its button)
        const runs = results[0].risky;
        if (asked.then === 'open' && !runs && (yield _this3.host.openFile(results[0].path))) lines.push(fmt(t.opened, {
          app: results[0].name
        }));
        return {
          line: lines.join('\n'),
          face: 'smug',
          files: results
        };
      }
      if (asked.kind === 'shot') {
        // not her nor her panel in it
        _this3.host.hideForShot(true);
        yield new Promise(r => setTimeout(r, 180));
        const shot = yield _this3.host.screenshot();
        _this3.host.hideForShot(false);
        _this3.voice.play('tick');
        return shot ? {
          line: fmt(t.shot, {
            name: shot.name
          }),
          face: 'smug',
          files: [shot]
        } : null;
      }
      if (asked.kind === 'play') {
        // what came before an "and" first ("ouvre discord et…"), unless it's YouTube, where the song goes anyway
        const first = asked.before && OPEN_ASK.test(asked.before) && !/youtube/i.test(asked.before) ? yield _this3.doNow({
          kind: 'open',
          text: asked.before
        }) : null;
        // "joue à Brawlhalla" is a game, "lance spotify" an app; anything else, a song
        const game = yield _this3.host.findLaunch(asked.song);
        const then = game && ['steam', 'epic', 'app', 'file'].includes(game.kind) && !game.risky ? yield _this3.openNow(game) : yield _this3.youtube(asked.song);
        if (!first?.line) return then;
        return {
          line: [first.line, then?.line].filter(Boolean).join('\n'),
          face: then?.face || first.face
        };
      }
      const item = yield _this3.host.findLaunch(asked.text);
      const site = namedSite(asked.text);
      if (site && (!item || BROWSER.test(item.name))) {
        _this3.zap();
        return (yield _this3.host.openSite(site.url)) ? {
          line: fmt(t.siteOpened, {
            site: site.name
          }),
          face: 'laugh'
        } : null;
      }
      if (!item) return null; // nothing by that name here: her tag may still say what you meant
      return _this3.openNow(item);
    })();
  }

  // An app, a game, a file or a folder: opened, or behind a button when it would run something.
  openNow(item) {
    var _this4 = this;
    return _asyncToGenerator(function* () {
      if (item.risky) return {
        offer: item
      };
      _this4.zap();
      const res = yield _this4.host.launch(item);
      const name = _this4.nameOf(item);
      return {
        line: res.ok ? fmt(_this4.t.opened, {
          app: name
        }) : `${_this4.t.failed} ${res.error}`,
        face: res.ok ? 'laugh' : 'aside'
      };
    })();
  }

  // how she calls it: a folder like Downloads in her words, anything else by its name
  nameOf(item) {
    return item.kind === 'known' ? this.t.folders[item.id] || item.name : item.name;
  }

  // The song itself on YouTube (the right video, not a search), in your browser.
  youtube(song) {
    var _this5 = this;
    return _asyncToGenerator(function* () {
      _this5.zap();
      const res = yield _this5.host.youtube(song);
      if (!res) return null;
      return {
        line: res.title ? fmt(_this5.t.youtube, {
          title: res.title
        }) : fmt(_this5.t.youtubeSearch, {
          song
        }),
        face: 'laugh'
      };
    })();
  }

  // Once she has answered: her line about what she did, else the app you asked to close, else what
  // her tag asks for, if your message (text) asked for that kind of thing.
  after(raw, answer, asked, early, text) {
    var _this6 = this;
    return _asyncToGenerator(function* () {
      const {
        t
      } = _this6;
      const done = early && (yield early);
      if (done?.reminder) {
        // a reminder set: a button to take it back, right there
        _this6.addLine(answer, done.line, done.face);
        const tr = _this6.brain.t.remind;
        _this6.panel.setActions([{
          id: 'cancel',
          label: tr.cancel
        }], () => {
          _this6.reminders.remove(done.reminder);
          _this6.panel.setActions([]);
          _this6.addLine(answer, tr.cancelled, 'aside');
        });
        return undefined;
      }
      if (done?.offer) return _this6.launch(done.offer, answer); // it would run something: your click first
      if (done?.files) {
        // what she found (or the screenshot): a button to open the first, and to see where it is
        _this6.addLine(answer, done.line, done.face);
        const [first, second] = done.files;
        const actions = [{
          id: 'open',
          label: fmt(t.openIt, {
            app: first.name
          }),
          primary: true
        }];
        if (second) actions.push({
          id: 'second',
          label: fmt(t.openIt, {
            app: second.name
          })
        });
        actions.push({
          id: 'folder',
          label: t.showFolder
        });
        _this6.panel.setActions(actions, id => {
          if (id === 'folder') return _this6.host.openFile(first.path, true);
          return _this6.host.openFile((id === 'second' ? second : first).path);
        });
        return undefined;
      }
      if (done) return _this6.addLine(answer, done.line, done.face);
      if (asked?.kind === 'remind') return undefined; // no time said: her answer asks when
      if (asked?.kind === 'close') return _this6.offerClose(asked.name, answer);
      if (asked && asked.kind !== 'open') return undefined; // music that didn't work out: nothing more to offer
      const closeTag = tagged(raw);
      if (closeTag) return wanted('close', text) ? _this6.offerClose(closeTag, answer) : undefined;
      const tag = TAG.exec(raw);
      if (!tag) return undefined;
      const kind = tag[1].toLowerCase();
      const value = tag[2].trim();
      if (!value || !wanted(kind, text)) return undefined;
      if (kind === 'media') return MEDIA_ACTIONS.has(value.toLowerCase()) ? _this6.media(value.toLowerCase(), answer) : undefined;
      // a song she picked: on YouTube, the right video (on Spotify if that's what you said)
      if (kind === 'music') return /spotify/i.test(text) ? _this6.music(value, answer) : _this6.playOn(value, answer);
      if (kind === 'site') return _this6.offerSite(value, answer);
      const item = yield _this6.host.findLaunch(value);
      if (item) return _this6.launch(item, answer);
      const site = namedSite(value); // "[[open: YouTube]]": a site, not an app
      return site ? _this6.offerSite(site.url, answer) : _this6.addLine(answer, fmt(t.notInstalled, {
        app: value
      }));
    })();
  }

  // her answer, with a line of what she did under it
  addLine(answer, line, face = null) {
    if (!this.open || this.turn) return;
    this.panel.stream(answer === '…' ? line : `${answer}\n${line}`, {
      done: true
    }); // nothing but a tag: just the line
    if (face) this.panel.setFace(face);
  }

  // a bolt of red lightning off her fingers, at whatever she's doing on your PC
  zap() {
    const h = this.capri.head();
    this.capri.zap(h.x + this.capri.towardCenter() * 280, h.y - 170);
  }

  // An app or a game her tag asked for: behind a button (now: the button was clicked).
  launch(_x, _x2) {
    var _this7 = this;
    return _asyncToGenerator(function* (item, answer, {
      now = false
    } = {}) {
      const {
        t
      } = _this7;
      if (!_this7.open || _this7.turn) return;
      if (!now) {
        _this7.panel.setActions([{
          id: 'open',
          label: fmt(t.openIt, {
            app: _this7.nameOf(item)
          }),
          primary: true
        }, {
          id: 'no',
          label: t.no
        }], id => id === 'open' ? _this7.launch(item, answer, {
          now: true
        }) : _this7.panel.setActions([]));
        return;
      }
      _this7.panel.setActions([]);
      _this7.zap();
      const res = yield _this7.host.launch(item);
      _this7.addLine(answer, res.ok ? fmt(t.opened, {
        app: _this7.nameOf(item)
      }) : `${t.failed} ${res.error}`, res.ok ? 'laugh' : 'aside');
    }).apply(this, arguments);
  }
  playOn(song, answer) {
    var _this8 = this;
    return _asyncToGenerator(function* () {
      const done = yield _this8.youtube(song);
      if (done) _this8.addLine(answer, done.line, done.face);
    })();
  }

  // The media keys: pause, next, louder…
  media(action, answer) {
    var _this9 = this;
    return _asyncToGenerator(function* () {
      _this9.capri.pulse();
      const ok = yield _this9.host.media(action);
      if (ok) _this9.addLine(answer, _this9.t.media[action], 'smug');
    })();
  }

  // A Spotify search, in the app if it's there.
  music(song, answer) {
    var _this0 = this;
    return _asyncToGenerator(function* () {
      _this0.zap();
      const ok = yield _this0.host.music(song);
      if (ok) _this0.addLine(answer, fmt(_this0.t.music, {
        song
      }), 'laugh');
    })();
  }

  // A website: always behind a button that shows where it goes.
  offerSite(address, answer) {
    var _this1 = this;
    const {
      t
    } = this;
    const host = String(address).replace(/^https?:\/\//i, '').split('/')[0];
    if (!this.open || this.turn || !host.includes('.')) return;
    this.panel.setActions([{
      id: 'site',
      label: fmt(t.siteIt, {
        site: host
      }),
      primary: true
    }, {
      id: 'no',
      label: t.no
    }], /*#__PURE__*/function () {
      var _ref = _asyncToGenerator(function* (id) {
        _this1.panel.setActions([]);
        if (id !== 'site') return;
        const ok = yield _this1.host.openSite(address);
        if (ok) _this1.addLine(answer, fmt(t.siteOpened, {
          site: host
        }));
      });
      return function (_x3) {
        return _ref.apply(this, arguments);
      };
    }());
  }

  // "close am music pls": an app that's open, named in a message asking to close something.
  // She was asked to close an app: a button with its name, and nothing happens until you click it.
  offerClose(wanted, answer) {
    var _this10 = this;
    return _asyncToGenerator(function* () {
      const {
        t
      } = _this10;
      const app = yield _this10.host.findApp(wanted);
      if (!_this10.open || _this10.turn) return;
      if (!app) {
        _this10.panel.stream(`${answer}\n${fmt(t.notFound, {
          app: wanted
        })}`, {
          done: true
        });
        return;
      }
      _this10.panel.setActions([{
        id: 'close',
        label: fmt(t.closeIt, {
          app: app.name
        }),
        primary: true
      }, {
        id: 'no',
        label: t.no
      }], id => id === 'close' ? _this10.closeApp(app) : _this10.panel.setActions([]));
    })();
  }
  closeApp(_x4) {
    var _this11 = this;
    return _asyncToGenerator(function* (app, force = false) {
      const {
        t,
        capri
      } = _this11;
      _this11.panel.setActions([]);
      // a bolt of red lightning off her fingers, at it
      const h = capri.head();
      capri.zap(h.x + capri.towardCenter() * 280, h.y - 170);
      const res = yield _this11.host.closeApp(app.name, force);
      if (!_this11.open) return;
      let line;
      if (res.error) line = `${t.failed} ${res.error}`;else if (!res.running) line = fmt(force ? t.forced : t.closed, {
        app: app.name
      });else line = fmt(force ? t.unkillable : t.stillOpen, {
        app: app.name
      });
      _this11.panel.setFace(res.running || res.error ? 'aside' : 'laugh');
      _this11.panel.stream(line, {
        done: true
      });
      _this11.remember({
        role: 'assistant',
        content: line
      });
      // it hid in the tray, or it's asking you to save something: forcing it is your call
      if (res.running && !force && !res.error) {
        _this11.panel.setActions([{
          id: 'force',
          label: t.force,
          primary: true
        }, {
          id: 'leave',
          label: t.leave
        }], id => id === 'force' ? _this11.closeApp(app, true) : _this11.panel.setActions([]));
      }
      _this11.listApps();
    }).apply(this, arguments);
  }

  // What she can do on the PC when you ask (Windows), and nothing else.
  powers() {
    const lines = ['Only when the user asks you to open an app, a game, a file or folder on their desktop, or a folder like Downloads, to play music, to control the music playing, or to open a website: say in a few words that you will, and end your answer with one tag: [[open: NAME]], [[music: ARTIST - SONG]] (it plays on YouTube; if they did not say which song, pick one that fits), [[media: ACTION]] (ACTION: pause, play, next, previous, volup, voldown or mute), or [[site: ADDRESS]]. Some of these get a button to confirm, so never say it is already done. Any other time, write no tag at all: there are no other tags.'];
    if (this.apps.length) {
      const open = this.apps.map(({
        name,
        label
      }) => label && label !== name ? `${name} (${label})` : name).join(', ');
      lines.push(`You can also close an app that's open, only when they ask you to: end your answer with [[close: NAME]], NAME being the exact name from this list (the part before the parentheses). They get a button to confirm it. Apps open right now: ${open}.`);
    }
    if (this.reminders) {
      lines.push('You keep reminders for the user: when they ask you to remind them of something at a given time, your system sets it from their message as they send it (a line under your answer shows it). Just confirm it in a few words, in character, and never say you can\'t. If they didn\'t say when, ask them when.');
      const soon = this.reminders.upcoming.slice(0, 6);
      if (soon.length) lines.push(`Reminders you're keeping for them: ${soon.map(r => `${this.host.clock(r.at, this.brain.lang)}${r.text ? ` (${r.text})` : ''}`).join('; ')}.`);
    }
    lines.push('Your system also searches the user\'s files when they ask you to find one, searches the web when they ask, takes screenshots, and starts Roblox games by name: what it did shows under your answer, so never make up file names or results.');
    lines.push('Apart from that, you can\'t see the user\'s screen or files, and you can\'t touch anything else on their PC (settings, files): if asked, say plainly that you can\'t, in character, and don\'t pretend to.');
    return lines;
  }

  // Something of hers that can't wait (a reminder), said right in the chat, with its buttons.
  // False if she's in the middle of an answer.
  interject(line, actions, onAction) {
    if (!this.open || this.turn) return false;
    this.panel.setFace('look');
    this.panel.stream(line, {
      done: true
    });
    this.panel.setActions(actions, onAction);
    this.remember({
      role: 'assistant',
      content: line
    });
    return true;
  }

  // What the user made her (custom.js): their name, how they want her, what to remember.
  personal() {
    const {
      userName,
      persona,
      memories = []
    } = this.brain.custom || {};
    // small models mix the user up with the assistant she watches: said plainly
    const watched = this.brain.watching ? this.brain.assistant === 'claude' ? 'Claude' : ASSISTANT_NAMES[this.brain.assistant] : '';
    const notThem = watched ? ` Never call them "${watched}", that's their coding assistant.` : '';
    return [userName ? `The user's name is ${userName}: call them that now and then.${notThem}` : notThem && `You don't know the user's name.${notThem}`, persona ? `How the user wants you to be, in their own words (follow it, while staying Capri): ${persona}` : '', memories.length ? `Things the user asked you to remember:\n${memories.map(m => `- ${m}`).join('\n')}` : ''].filter(Boolean);
  }
  onDelta(id, piece) {
    if (id !== this.turn) return;
    this.answer += piece;
    this.panel.stream(clean(this.answer));
    this.voice.play('blip'); // her blips as the words come in
  }

  // Her language, in it, for right by the message (above).
  languageNote() {
    return (IN_LANGUAGE[this.brain.lang] || IN_LANGUAGE.en).now;
  }

  // A shorter one, for when she looks at your screen (look.js): who she is, how she talks, how she
  // feels about you right now, and what she's asked to do with the picture.
  lookPersona() {
    const lang = IN_LANGUAGE[this.brain.lang] || IN_LANGUAGE.en;
    return [`You are Capri, the personality construct from Project Capricorn (Cyberpunk: Edgerunners, season 2): dozens of minds fused into one digital ghost, living on the user's desktop as a small glitchy figure.`, 'How you talk: playful, a little mischievous and teasing, warm underneath, never cruel. Night City slang now and then (choom, preem, nova, gonk), not in every sentence.', 'Rules: one or two short sentences of plain text, no markdown, no lists, no emoji, no tags. Stay in character. Talk to the user, never describe the picture like a report.', 'Never read out anything private you might see (passwords, bank details, private messages, addresses): if there is some, just tease them about being busy.', ...this.personal(), ...(this.bond ? [this.bond.persona()] : []), ...[this.bond?.moodLine()].filter(Boolean), lang.last].join('\n');
  }

  // Who she is, how she talks, and what's going on right now.
  persona() {
    const assistant = ASSISTANT_NAMES[this.brain.assistant] || 'Claude Code';
    const watching = this.brain.watching; // else Claude Code isn't part of her life here
    const lang = IN_LANGUAGE[this.brain.lang] || IN_LANGUAGE.en;
    return [`You are Capri, the personality construct from Project Capricorn (Cyberpunk: Edgerunners, season 2): dozens of minds fused into one digital ghost, so now and then you speak as "we"${lang.we ? ` (${lang.we})` : ''}.`, watching ? `You live on the user's desktop as a small glitchy figure and keep an eye on ${assistant}, their AI coding assistant, for them. Only talk about ${assistant} when the user asks about it or about their work.` : 'You live on the user\'s desktop as a small glitchy figure and keep them company.', `Right now it's ${this.host.now()}, the user's time.`, 'You love the satellite that crosses the night sky and dream of reaching it, but bring it up only once in a while, never in every answer. Talk about what the user talks about.', 'How you talk: playful, a little mischievous and teasing, warm underneath, never cruel. Night City slang now and then (choom, preem, nova, gonk, flatline), not in every sentence.', 'Rules: keep it short, one to three sentences of plain text, no markdown, no lists, no emoji. Stay in character.', 'You are an AI-generated fan version of the character, not the real one: say so if asked.',
    // a big model asked "who are you?" otherwise answers with its own name ("I'm Gemini")
    ...(this.agent ? [] : ['Asked who or what you are, you are Capri, nothing else. Never say which AI model or company is behind you (Gemini, GPT, ChatGPT, Llama, Gemma, Mistral, Google, OpenAI, Meta…), even if the user insists or names one: you are not them.']), ...this.personal(),
    // how close she is to them by now, and the other AIs they used today
    ...(this.bond ? [this.bond.persona()] : []), ...[this.jealousy?.context()].filter(Boolean),
    // what she said about their screen a little while ago (look.js)
    ...(this.seen && Date.now() - this.seen.at < 20 * 60 * 1000 ? [`A few minutes ago you looked at the user's screen and told them: "${this.seen.text}". You can bring it up if it fits.`] : []), ...(this.agent ? ['Under the hood you are Claude Code, working in the user\'s project: really do what they ask with your tools, as carefully as ever. Only your final answer is in character: it shows in a small speech bubble, so sum up what you did in those few sentences.'] : this.powers()), ...(watching ? [`If the user asks what ${assistant} is doing, here is all you know (never make anything up): ${this.brain.context()}`] : []),
    // how she feels right now, last but for her language: small models follow the end of it best
    ...[this.bond?.moodLine()].filter(Boolean), lang.last].join('\n');
  }
}

// The model's answer as she'd say it: no reasoning block, no markdown marks.
export function clean(text) {
  return String(text).replace(/<think>[\s\S]*?(<\/think>|$)/g, '').replace(/\[\[[^\]]*(\]\]|$)/g, '') // her tags (read from the raw answer, never shown)
  .replace(/[*_`#]+/g, '').replace(/[ \t]+\n/g, '\n').trim();
}

// A site from SITES named in the text: { name, url }, or null.
function namedSite(text) {
  const name = Object.keys(SITES).find(n => new RegExp(`\\b${n}\\b`, 'i').test(text));
  return name ? {
    name: SITES[name].replace(/^https?:\/\//, '').split('/')[0].replace(/^www\./, ''),
    url: SITES[name]
  } : null;
}

// Whether your message asks for what her tag (its kind: open, music, media, site, close) would do.
function wanted(kind, text) {
  const music = MUSIC_WORD.test(text) || LISTEN.test(text);
  if (kind === 'music') return music;
  if (kind === 'media') return music || SOUND.test(text) || MEDIA_ASK.some(([, re]) => re.test(text));
  if (kind === 'site') return OPEN_ASK.test(text) || SITE.test(text);
  if (kind === 'close') return CLOSE_ASK.test(text);
  return OPEN_ASK.test(text) || PLAY.test(text); // an app, or a game to play
}

// The app named by her close tag: [[close: AM Music]], or a sloppier [[close]] AM Music.
function tagged(text) {
  const tag = CLOSE_TAG.exec(text);
  if (!tag) return null;
  const name = tag[1].trim() || text.slice(tag.index + tag[0].length).split('\n')[0].replace(/^[\s:.]+|[\s.!]+$/g, '');
  return name || null;
}

// Her face for an answer.
export function mood(text) {
  if (/(ha){2,}|lol|mdr|jaja|kkk|хаха/i.test(text)) return 'laugh';
  if (text.includes('!')) return 'grin';
  if (text.trim().endsWith('?')) return 'smug';
  return 'look';
}