// Her guide, setup, "make her yours" and screen looks (guide/setup/custom/look.mjs), driven through
// the real Panel with stub host/body: the buttons, where she points, what reaches the sidecar.
import assert from 'node:assert/strict';
import {Guide} from '../../payload/capri/js/guide.mjs';
import {Setup} from '../../payload/capri/js/setup.mjs';
import {Custom} from '../../payload/capri/js/custom.mjs';
import {Look} from '../../payload/capri/js/look.mjs';
import {Panel} from '../../payload/capri/js/panel.mjs';
import {linesFor} from '../../payload/capri/js/lines.mjs';
import {SOUNDS} from '../../payload/capri/js/sounds.mjs';
import {pump, reset} from '../../payload/capri/js/util.mjs';

const settle = async () => { for (let i = 0; i < 8; i++) { await new Promise(setImmediate); pump(); } };
let quiet = false;
const panel = new Panel({quiet: () => quiet, changed() {}});
const brain = {t: linesFor('fr', 'codex'), lang: 'fr', assistant: 'codex', watching: true, custom: {}, sessions: new Map()};
const pointed = [], calls = [];
const win = {id: '0xclaude', x: 100, y: 100, w: 800, h: 600};
const capri = {
  stowed: false, stance: 'stand', mode: 'idle', windows: {wins: [win], fg: '0xother'}, view: {w: 1920, floor: 1040}, pos: {x: 50},
  perform() {}, towardCenter: () => 1, wake() {}, hurt() { calls.push('hurt'); }, pulse() {}, unstow: async () => { capri.stowed = false; },
  pointAt: async (rect, opts) => { pointed.push([rect, opts.label]); }, stopPointing() { pointed.push('stop'); }, canPoint: w => w.id !== '0xbehind',
  coversOf: () => [], cutinAt: () => [0, 0, 1], chipAt: () => ({x: 60, y: 980}),
};
let hooks = {installed: false}, found = true;
const host = {
  focusOverlay() {}, setConfig(p) { calls.push(['config', p]); },
  hooksStatus: async () => hooks, claudeFound: async () => found,
  installHooks: async () => { calls.push('install'); hooks = {installed: true}; return {ok: true}; },
  openClaudeHelp() { calls.push('help'); }, trayPlace: async () => ({icon: null, corner: {x: 10, y: 920, w: 100, h: 120}}),
  openClaudeFolder: async () => ({found: true, dir: '/home/u/.codex', file: true, label: 'hooks.json'}),
  onSetupProgress(fn) { host.progress = fn; }, getConfig: async () => ({provider: 'groq'}),
  ollamaState: async () => host.ollama, installOllama: async () => ({ok: false}), startOllama: async () => { host.ollama = {running: true, installed: true, models: []}; return {ok: true}; },
  setupInfo: async () => ({models: [{name: 'gemma3:4b', bytes: 3.3e9}, {name: 'llama3.2', bytes: 2e9}], cloud: [], ram: 32e9}),
  pullModel: async name => { calls.push(['pull', name]); host.progress({kind: 'pull', completed: 1.65e9, total: 3.3e9}); return {ok: true, model: name}; },
  cancelSetup() {}, useProvider: async args => { calls.push(['use', args]); return args.key === 'bad' ? {ok: false, error: 'invalid key'} : {ok: true}; },
  keyPage(p) { calls.push(['page', p]); }, openOllama() { calls.push('site'); },
  launchThroughOllama: async integration => { calls.push(['launch', integration]); return {ok: true}; },
  lookWhere: async () => ({local: false, provider: 'ChatGPT', model: 'ChatGPT'}),
  lookSnap: async () => ({ok: true, id: 'snap'}), lookSay: async req => { calls.push(['say', req.id]); return host.lookAnswer; },
};
const guide = new Guide({capri, panel, voice: {play() {}}, host, brain});
const setup = new Setup({guide, panel, host, brain, capri, voice: {play() {}}});
const custom = new Custom({guide, host, brain, capri, voice: {play() {}}});
guide.setup = setup; guide.custom = custom;
const ids = () => (panel.current.actions || []).map(a => a.id);

// Do Not Disturb holds what she says on her own, never her guide you opened
quiet = true;
let done = guide.menu(); await settle();
assert.equal(panel.visible, true, 'the guide shows in DND');
assert.deepEqual(ids(), ['connect', 'icon', 'claude', 'folder', 'talk', 'custom', 'close']);
assert.equal(panel.say({kind: 'info', line: 'on her own', hold: 1000}), false, 'DND still holds her own lines');
quiet = false;

// Plug me in: one click installs the hooks, then she points at Claude's window if she knows it
brain.sessions.set('s', {window: '0xclaude', seen: 1});
panel.action('connect'); await settle();
assert.equal(panel.current.line, brain.t.welcome.hi);
assert.deepEqual(ids(), ['connect', 'free', 'later'], 'Free with Ollama is offered for Codex');
panel.action('connect'); await settle();
assert.ok(calls.includes('install'));
assert.deepEqual(pointed.at(-1), [win, 'CODEX'], 'she shows where to restart it');
assert.equal(panel.current.kind, 'done');
panel.action('ok'); await done;
assert.equal(guide.running, false); assert.equal(pointed.at(-1), 'stop', 'the scene ends with the arm back');

// Where's Claude: unknown, behind, there
brain.sessions.clear();
done = guide.scene(() => guide.claude()); await settle();
assert.equal(panel.current.line, brain.t.guide.claude.unknown); panel.action('ok'); await done;
brain.sessions.set('s', {window: '0xbehind', seen: 2}); capri.windows.wins.push({id: '0xbehind', x: 0, y: 0, w: 10, h: 10});
done = guide.scene(() => guide.claude()); await settle();
assert.equal(panel.current.line, brain.t.guide.claude.behind); panel.action('ok'); await done;
brain.sessions.set('s', {window: '0xclaude', seen: 3});
done = guide.scene(() => guide.claude()); await settle();
assert.equal(panel.current.line, brain.t.guide.claude.there); assert.deepEqual(pointed.at(-1), [win, 'CODEX']);
panel.dismiss = null; panel.hide(); await done;
assert.equal(guide.running, false, 'closing the panel ends the scene');

// Where's my icon: no tray here, her chip's corner and the Linux keys
done = guide.scene(() => guide.icon()); await settle();
assert.equal(pointed.at(-1)[0].y, 920);
assert.match(panel.current.quote, /Ctrl\+Alt\+C/); assert.match(panel.current.quote, /Super\+Shift\+K/);
panel.action('ok'); await done;

// Claude's folder: opened, then the window in front pointed at, then her hook explained
done = guide.scene(() => guide.folder());
await settle(); capri.windows.fg = '0xclaude'; await new Promise(r => setTimeout(r, 150)); await settle(); // she looks every 100 ms
assert.match(panel.current.line, /\.codex/); assert.equal(pointed.at(-1)[1], 'hooks.json');
panel.action('next'); await settle(); assert.equal(panel.current.line, brain.t.guide.folder.hook);
panel.action('ok'); await done;

// Her chat setup: on this PC, Ollama awake but empty: the bigger model on a roomy PC, its bar filling
host.ollama = {running: true, installed: true, models: []};
done = setup.chat(); await settle();
assert.deepEqual(ids(), ['local', 'online', 'key', 'later']);
panel.action('local'); await settle();
assert.deepEqual(ids(), ['gemma3:4b', 'llama3.2', 'later']);
assert.match(panel.current.actions[0].label, /3,3 Go/, 'sizes in her language');
panel.action('gemma3:4b'); await settle();
assert.deepEqual(calls.find(c => c[0] === 'pull'), ['pull', 'gemma3:4b']);
assert.equal(panel.current.kind, 'done');
panel.action('later'); await done;

// A key, pasted in her panel (hidden), checked, and asked again when it's wrong
done = setup.key(); await settle();
assert.equal(panel.current.chat.secret, true);
panel.action('page'); assert.deepEqual(calls.at(-1), ['page', 'groq'], 'the page to get one, panel stays');
panel.send('bad'); await settle();
assert.match(panel.current.quote, /invalid key/); assert.equal(panel.current.face, 'wide');
panel.send('gsk_good'); await settle();
assert.deepEqual(calls.filter(c => c[0] === 'use').at(-1), ['use', {provider: 'groq', key: 'gsk_good'}]);
panel.action('later'); await done;

// Ollama not installed: off Windows, the site
host.ollama = {running: false, installed: false, winget: false};
done = setup.chat({ok: false, provider: 'ollama'}); await settle();
panel.action('local'); await settle();
assert.deepEqual(ids(), ['site', 'later']); panel.action('site'); await done;
assert.ok(calls.includes('site'));

// Free with Ollama: hooks already in, Ollama awake, a terminal on `ollama launch codex`
host.ollama = {running: true, installed: true, models: ['m']};
done = setup.free(); await settle();
panel.action('go'); await settle();
assert.deepEqual(calls.at(-1), ['launch', 'codex']);
panel.action('ok'); await done;

// Make her yours: name, how she is, lines of yours, things to remember
done = custom.open(); await settle();
panel.send('Léa'); await settle();
assert.equal(brain.custom.userName, 'Léa');
panel.send('plus taquine'); await settle();
panel.send('Salut {name}'); await settle();
assert.deepEqual(brain.custom.myLines, ['Salut {name}']);
assert.match(panel.current.quote, /Salut \{name\}/);
panel.action('done'); await settle();
assert.equal(panel.current.actions[0].label, brain.t.custom.skip); panel.action('done'); await settle(); // nothing to remember yet: skipped
assert.equal(panel.current.kind, 'done'); panel.action('ok'); await done;
assert.equal(brain.custom.persona, 'plus taquine');

// Looking at her screen: asked first, then one look, shown in DND because you asked
const fx = {cutin() {}, scan() { calls.push('scan'); }};
const chat = {open: false, lookPersona: () => 'persona', languageNote: () => ''};
const look = new Look({capri, panel, brain, chat, guide, host, fx, voice: {play() {}}, active: () => 0});
host.lookAnswer = {ok: true, text: '« Du code partout, encore ? »'};
quiet = true;
done = look.once(); await settle();
assert.equal(panel.current.line, brain.t.look.ask); assert.match(panel.current.quote, /ChatGPT/);
panel.action('yes'); await done; await settle();
assert.ok(calls.includes('scan'));
assert.equal(panel.current.badge, 'SCAN'); assert.equal(panel.current.line, 'Du code partout, encore ?', 'no quotes around her line');
assert.equal(chat.seen.text, 'Du code partout, encore ?', 'her chat remembers it');
panel.hide(); quiet = false;
host.lookAnswer = {ok: false, code: 'novision', model: 'llama3.2:latest'};
look.auto = true;
await look.now({manual: true}); await settle();
assert.match(panel.current.line, /llama3\.2/);
assert.deepEqual(calls.at(-1), ['config', {watchScreen: false}], 'a model that cannot see stops her looking on her own');
panel.hide();
// on her own: only when you're there, on another window, and she's free
look.nextAt = 0; look.lastFg = capri.windows.fg; look.lastAt = Date.now();
const before = calls.filter(c => c === 'scan').length;
look.tick(); await settle();
assert.equal(calls.filter(c => c === 'scan').length, before, 'same window a moment ago: no look');

// every upstream cue has rendered sounds
for (const cue of ['teleport-out', 'teleport-in', 'done', 'alert', 'error', 'hello', 'blip:talk', 'tick', 'star', 'land', 'rise', 'bolt', 'charge', 'possess', 'throw:1', 'crash:2', 'remind', 'jealous'])
  assert.ok(SOUNDS[cue] && SOUNDS[cue].length, cue);

reset();
console.log('CAPRI_GUIDE_PASS guide topics, DND, setup (Ollama/key/free), make her yours, screen looks, sounds');
