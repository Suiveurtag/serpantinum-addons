import assert from 'node:assert/strict';
import { TIERS, EVENTS, GLANCE_MODES, RANKS, rank, outranks, memory, decide, commit } from '../../payload/clawd/js/mind.mjs';

const calm = (more = {}) => ({ ...memory(), mode: 'idle', hook: '', reactions: 'all', ...more });
const act = (state, kind, now, info) => decide(state, kind, now, info).act;

// Table sanity: every event has a known tier, a cooldown and an anim (bubbles have none).
for (const [kind, e] of Object.entries(EVENTS)) {
  assert.ok(TIERS[e.tier] !== undefined, kind);
  assert.ok(Number.isFinite(e.cooldown) && e.cooldown >= 0, kind);
  assert.equal(typeof e.anim, 'string', kind);
}
assert.ok(TIERS.input > TIERS.alert && TIERS.alert > TIERS.work && TIERS.work > TIERS.urgent && TIERS.urgent > TIERS.ambient && TIERS.ambient > TIERS.explore);
assert.deepEqual(decide(calm(), 'window_open', 0), { act: 'react', anim: 'look', tier: 'ambient' });
assert.deepEqual(decide(calm(), 'workspace', 0), { act: 'react', anim: 'stumble', tier: 'ambient' });
assert.deepEqual(decide(calm(), 'window_close_near', 0), { act: 'react', anim: 'startled', tier: 'ambient' });
assert.equal(act(calm(), 'nope', 0), 'none');
assert.equal(act(calm(), 'constructor', 0), 'none');
assert.equal(act(calm(), 'toString', 0), 'none');

// Input owns him.
for (const k of ['drag', 'menu', 'petpet', 'dead', 'scene']) assert.equal(act(calm({ [k]: true }), 'notif_critical', 0), 'none', k);  // dead / scene: another system owns him

// Focus is a glance, only in a resting pose.
assert.deepEqual(GLANCE_MODES, ['idle', 'sit', 'perch']);
for (const mode of GLANCE_MODES) assert.equal(act(calm({ mode }), 'focus', 0), 'glance', mode);
for (const mode of ['walk', 'work', 'react', 'fall']) assert.equal(act(calm({ mode }), 'focus', 0), 'none', mode);

// Asleep: only urgent, or a really loud volume.
assert.equal(act(calm({ asleep: true }), 'window_open', 0), 'none');
assert.equal(act(calm({ asleep: true }), 'notif_critical', 0), 'react');
assert.equal(act(calm({ asleep: true }), 'volume_loud', 0, { level: 90 }), 'none');
assert.equal(act(calm({ asleep: true }), 'volume_loud', 0, { level: 96 }), 'react');

// Reactions setting.
assert.equal(act(calm({ reactions: 'off' }), 'window_open', 0), 'none');
assert.equal(act(calm({ reactions: 'off' }), 'track', 0), 'none');
assert.equal(act(calm({ reactions: 'off' }), 'timer_ring', 0), 'react');
assert.equal(act(calm({ reactions: 'quiet' }), 'window_open', 0), 'none');
assert.equal(act(calm({ reactions: 'quiet' }), 'track', 0), 'bubble');
assert.equal(act(calm({ reactions: 'quiet' }), 'rain', 0), 'mood');
assert.equal(act(calm({ reactions: 'quiet' }), 'notif_critical', 0), 'react');

// Do not disturb: notifications muted except critical ones.
assert.equal(act(calm({ dnd: true }), 'notif', 0), 'none');
assert.equal(act(calm({ dnd: true }), 'notif_critical', 0), 'react');
assert.equal(act(calm({ dnd: true }), 'window_open', 0), 'react');

// Hooks: an alert lets urgent things glance only; work lets urgent react and bubbles through.
assert.equal(act(calm({ hook: 'alert' }), 'window_open', 0), 'none');
assert.equal(act(calm({ hook: 'alert' }), 'notif_critical', 0), 'glance');
assert.equal(act(calm({ hook: 'work', mode: 'work' }), 'workspace', 0), 'none');
assert.equal(act(calm({ hook: 'work', mode: 'work' }), 'track', 0), 'bubble');
assert.equal(act(calm({ hook: 'work', mode: 'work' }), 'timer_ring', 0), 'react');

// Low motion: no lasting motions.
assert.equal(act(calm({ lowMotion: true }), 'music', 0), 'none');
assert.equal(act(calm(), 'music', 0), 'react');
assert.equal(act(calm({ lowMotion: true }), 'window_open', 0), 'react');

// Same kind within 1 s merged; per-kind cooldown.
let s = commit(calm(), 'window_open', 1000);
assert.deepEqual(s.last, { window_open: 1000 });
assert.deepEqual(s.recent, [1000]);
assert.equal(act({ ...s, mode: 'idle' }, 'window_open', 1500), 'none');
assert.equal(act({ ...s, mode: 'idle' }, 'window_open', 6999), 'none');
assert.equal(act({ ...s, mode: 'idle' }, 'window_open', 7000), 'react');
let t = commit(calm(), 'track', 0);
assert.equal(act(t, 'track', 999), 'none');   // cooldown 0, still merged within 1 s
assert.equal(act(t, 'track', 1000), 'bubble');
assert.deepEqual(t.recent, []);               // bubbles never count against the budget
let u = commit(calm(), 'notif_critical', 0);
assert.equal(act(u, 'notif_critical', 500), 'none');
assert.equal(act(u, 'notif_critical', 1000), 'react');
assert.deepEqual(u.recent, []);               // urgent ones either

// Ambient budget: one per 5 s, six per minute (halved in low motion); urgent events ignore it.
s = commit(calm(), 'window_open', 0);
assert.equal(act(s, 'workspace', 4999), 'none');
assert.equal(act(s, 'workspace', 5000), 'react');
assert.equal(act(s, 'notif_critical', 100), 'react');
assert.equal(act({ ...s, lowMotion: true }, 'workspace', 9999), 'none');
assert.equal(act({ ...s, lowMotion: true }, 'workspace', 10000), 'react');
s = calm();
const kinds = ['window_open', 'workspace', 'window_close_near', 'layer', 'notif', 'mute'];
kinds.forEach((k, i) => { assert.equal(act(s, k, i * 5000), 'react', k); s = commit(s, k, i * 5000); });
assert.equal(s.recent.length, 6);
assert.equal(act(s, 'charging', 30000), 'none');    // seventh within a minute
assert.equal(act(s, 'charging', 60001), 'react');   // the first one aged out
assert.deepEqual(commit(s, 'charging', 70000).recent, [15000, 20000, 25000, 70000]);
s = calm({ lowMotion: true });
for (const [i, k] of kinds.slice(0, 3).entries()) { assert.equal(act(s, k, i * 10000), 'react', k); s = commit(s, k, i * 10000); }
assert.equal(act(s, 'notif', 30000), 'none');      // three per minute in low motion
assert.equal(act(s, 'notif', 60001), 'react');

// commit never mutates and ignores unknown kinds.
const before = calm();
const after = commit(before, 'workspace', 5);
assert.deepEqual(before.last, {});
assert.deepEqual(commit(after, 'nope', 9).last, { workspace: 5 });
assert.deepEqual(decide(undefined, 'window_open', 0).act, 'react');

// 5c: bubble ranks (permission > error > done/waiting > notif/music; equal replaces), shell menus glance, the real reactions / dnd values.
assert.ok(RANKS.permission > RANKS.error && RANKS.error > RANKS.done && RANKS.done === RANKS.waiting && RANKS.done > RANKS.notif && RANKS.notif === RANKS.music);
assert.ok(!outranks('notif', 'done') && !outranks('music', 'permission') && !outranks('done', 'error') && outranks('error', 'done') && outranks('notif', 'music'));
assert.equal(rank('toString'), 2);
assert.equal(act(calm({ mode: 'sit' }), 'shell_menu', 0), 'glance');
assert.equal(act(calm({ mode: 'walk' }), 'shell_menu', 0), 'none');
assert.equal(act(calm({ reactions: 'quiet' }), 'shell_menu', 0), 'none');
assert.equal(act(calm({ reactions: 'quiet' }), 'brightness_low', 0), 'mood');
assert.equal(act(calm({ reactions: 'off' }), 'battery_critical', 0), 'react');
assert.equal(act(calm({ reactions: 'off' }), 'music', 0), 'none');
assert.equal(act(calm({ dnd: true }), 'timer_ring', 0), 'react');
console.log('CLAWD_MIND_PASS');
