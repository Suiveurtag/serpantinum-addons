import assert from 'node:assert/strict';
import { DREAMS, NAMES, MUMBLES, BLANKET_MUMBLES, byId, pick, pickKind, record, book, nextSleepEvent, tickMs } from '../../payload/clawd/js/dreams.mjs';

let seed = 11;
const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
const always = v => () => v;

// registry, lookup, NAMES
assert.equal(byId('surf').scene, 'ClawdDreamSurf');
assert.equal(byId('gemini').jump, 11.0);
assert.equal(byId('nope'), null);
for (const n of ['dream', 'nightmare', 'blanket', 'sleepwalk', 'dream_surf', 'nightmare_gemini', 'nightmare_ouroboros', 'nightmare_bsod', 'nightmare_panic']) assert.ok(NAMES.includes(n), n);
assert.equal(NAMES.length, 4 + DREAMS.length);
assert.ok(MUMBLES.length >= 5 && BLANKET_MUMBLES.length >= 1);

// pick: kind filter, fallback, unseen boost (x2 => ~2/3 vs 1/3 with two equal entries; use a temp-free check via counts on same kind)
assert.equal(pick('dream', rnd, {}), 'surf');
assert.ok(['gemini', 'ouroboros', 'bsod', 'panic'].includes(pick('nightmare', rnd, {})));
for (const id of ['bsod', 'panic']) { assert.equal(byId(id).kind, 'nightmare'); assert.ok(byId(id).jump < byId(id).duration, id); }
assert.equal(byId('ouroboros').scene, 'ClawdNightmareOuroboros');
assert.equal(byId('ouroboros').kind, 'nightmare');
assert.ok(byId('ouroboros').jump < byId('ouroboros').duration);
assert.equal(pick('zzz', rnd, {}), '');
let nm = 0, N = 4000;
for (let i = 0; i < N; i++) if (byId(pick(null, rnd, {})).kind === 'nightmare') nm++;
assert.ok(nm / N > 0.18 && nm / N < 0.32, 'nightmare ratio ' + nm / N);
assert.equal(pickKind(always(0.1)), 'nightmare');
assert.equal(pickKind(always(0.9)), 'dream');
// unseen x2: across both kinds with kind=null fallback is not testable; check weight via mixed pool by seeding pick(null) with fixed kind roll
// pick(null) with rnd sequence: kind roll then weight roll -> total weights 2 (unseen) for single entry, still returns it
assert.equal(pick(null, (() => { let i = 0; return () => [0.9, 0.5][i++ % 2]; })(), { surf: { n: 1 } }), 'surf');

// record: immutability, counts, cap, malformed state
const s0 = { seen: { surf: { n: 1, first: 5, last: 5 } }, log: [{ id: 'surf', kind: 'dream', at: 5 }] };
const frozen = JSON.stringify(s0);
const s1 = record(s0, 'surf', 'dream', 100);
assert.equal(JSON.stringify(s0), frozen);
assert.deepEqual(s1.seen.surf, { n: 2, first: 5, last: 100 });
assert.deepEqual(s1.log[0], { id: 'surf', kind: 'dream', at: 100 });
assert.equal(s1.log.length, 2);
for (const bad of [null, undefined, 5, 'x', {}, { seen: 3, log: 'a' }]) {
  const r = record(bad, 'gemini', 'nightmare', 7);
  assert.deepEqual(r.seen.gemini, { n: 1, first: 7, last: 7 });
  assert.equal(r.log.length, 1);
}
let st = null;
for (let i = 0; i < 60; i++) st = record(st, 'surf', 'dream', i);
assert.equal(st.log.length, 40);
assert.equal(st.log[0].at, 59);
assert.equal(st.seen.surf.n, 60);
assert.equal(record(st, 'surf', 'dream', 99, 5).log.length, 5);

// book merge
const b = book({ seen: { gemini: { n: 3, first: 1, last: 9 } } });
assert.equal(b.length, DREAMS.length);
assert.deepEqual(b.find(e => e.id === 'gemini'), { id: 'gemini', kind: 'nightmare', title: 'Gemini', glyph: DREAMS[1].glyph, seen: true, n: 3, first: 1, last: 9 });
assert.equal(b.find(e => e.id === 'surf').seen, false);
assert.equal(book(null).every(e => !e.seen), true);

// nextSleepEvent: thresholds and cooldowns (rnd 0 = every roll succeeds, first eligible wins in order roll, dream, talk, walk)
const base = { sleptMs: 10 * 60000, now: 100 * 60000, kind: 'sleep', bubble: false, last: {}, lowMotion: false, canWalk: true, hasRoll: true };
const ev = (over, r) => nextSleepEvent(r || always(0), { ...base, ...over });
assert.equal(ev({}), 'roll');
assert.equal(ev({ hasRoll: false }), 'dream');
assert.equal(ev({ hasRoll: false, bubble: true }), 'talk');
assert.equal(ev({ hasRoll: false, sleptMs: 30000 }), 'talk');
assert.equal(ev({ last: { roll: base.now - 59000 }, hasRoll: true }), 'dream');
assert.equal(ev({ last: { roll: base.now - 1000, dream: base.now - 239000 } }), 'talk');
assert.equal(ev({ last: { roll: base.now - 1000, dream: base.now - 1000, talk: base.now - 89000 } }), 'walk');
assert.equal(ev({ last: { roll: base.now - 1000, dream: base.now - 1000, talk: base.now - 91000 } }), 'talk');
const cool = { roll: base.now, dream: base.now, talk: base.now };
assert.equal(ev({ last: cool }), 'walk');
assert.equal(ev({ last: cool, lowMotion: true }), '');
assert.equal(ev({ last: cool, canWalk: false }), '');
assert.equal(ev({ last: cool, sleptMs: 170000 }), '');
assert.equal(ev({ last: { ...cool, walk: base.now - 800000 } }), '');
assert.equal(ev({}, always(0.99)), '');
let rolls = 0;
for (let i = 0; i < 4000; i++) if (ev({ hasRoll: true }, rnd) === 'roll') rolls++;
assert.ok(rolls / 4000 > 0.15 && rolls / 4000 < 0.25);

// tickMs
assert.equal(tickMs(true, rnd), 60000);
for (let i = 0; i < 200; i++) { const t = tickMs(false, rnd); assert.ok(t >= 14000 && t <= 28000, String(t)); }
assert.equal(tickMs(false, always(0)), 14000);
assert.equal(tickMs(false, always(0.999999)), 28000);
console.log('CLAWD_DREAMS_PASS');
