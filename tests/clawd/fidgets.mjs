import assert from 'node:assert/strict';
import { NAMES, STAND, SIT, PERCH, pool, pick } from '../../payload/clawd/js/fidgets.mjs';
import { readFileSync } from 'node:fs';

const manifest = JSON.parse(readFileSync(new URL('../../payload/clawd/sprites/clawd.json', import.meta.url))).animations;
let seed = 11;
const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;

// every fidget is a strip the manifest has, on the pet's own canvas: one-shots standing and perched (they end by themselves), loops seated (held like sit)
assert.deepEqual(NAMES, [...STAND, ...SIT, ...PERCH]);
assert.equal(new Set(NAMES).size, NAMES.length);
for (const name of NAMES) {
  const clip = manifest[name];
  assert.ok(clip, `${name} missing`);
  assert.ok(!clip.w && !clip.h, `${name}: the pet's own canvas`);
  assert.equal(clip.loop, SIT.includes(name), `${name} loop`);
  assert.equal(!!clip.grip, PERCH.includes(name), `${name} grip`);
}

// a calm day reaches every fidget of a pose, never twice in a row
for (const [pose, list] of [['stand', STAND], ['sit', SIT], ['perch', PERCH]]) {
  const seen = new Set();
  let prev = '';
  for (let i = 0; i < 2000; i++) {
    const p = pick(pose, { mood: '', sleepy: false, prev }, rnd);
    assert.ok(list.includes(p), `${pose}: ${p}`);
    assert.notEqual(p, prev, `${pose}: ${p} twice in a row`);
    seen.add(p);
    prev = p;
  }
  assert.equal(seen.size, list.length, pose);
}

// moods keep to what suits them: no games when he is worn out or in bad weather, nothing seated (moodSit has its own poses)
const games = ['bubble', 'butterfly', 'yoyo', 'whistle', 'skip'];
for (const mood of ['drowsy', 'exhausted', 'rain', 'snow']) {
  const stand = Object.keys(pool('stand', { mood }));
  assert.ok(stand.length >= 3 && stand.every(n => STAND.includes(n) && !games.includes(n)), `${mood}: ${stand}`);
  assert.deepEqual(pool('sit', { mood }), {}, mood);
  assert.equal(pick('sit', { mood }, rnd), '');
}
assert.deepEqual(Object.keys(pool('perch', { mood: 'drowsy' })), ['perch_yawn']);
assert.deepEqual(pool('perch', { mood: 'rain' }), {});
assert.deepEqual(pool('stand', { mood: 'unknown' }), {});
assert.ok(pool('stand', { mood: 'drowsy' }).yawn > pool('stand', { mood: 'drowsy' }).scratch);
assert.ok(pool('stand', { mood: 'snow' }).sneeze > pool('stand', { mood: 'snow' }).shake);

// his nap is near: mostly yawns, no games; a mood wins over it
const sleepy = pool('stand', { sleepy: true });
assert.ok(sleepy.yawn >= 2 * Math.max(...Object.entries(sleepy).filter(([n]) => n !== 'yawn').map(([, w]) => w)));
assert.ok(Object.keys(sleepy).every(n => !games.includes(n)) && sleepy.doze > 0);
assert.deepEqual(pool('stand', { mood: 'rain', sleepy: true }), pool('stand', { mood: 'rain' }));
let yawns = 0;
for (let i = 0; i < 1000; i++) if (pick('stand', { sleepy: true, prev: '' }, rnd) === 'yawn') yawns++;
assert.ok(yawns > 350, `sleepy yawns: ${yawns}`);

// the filter, the edges of the roll, a single candidate (prev cannot empty the pool), unknown poses
assert.equal(pick('stand', {}, rnd, n => n === 'tap'), 'tap');
assert.equal(pick('stand', { prev: 'tap' }, rnd, n => n === 'tap'), 'tap');
assert.equal(pick('stand', {}, rnd, () => false), '');
assert.equal(pick('stand', {}, () => 0), STAND[0]);
assert.ok(STAND.includes(pick('stand', {}, () => 0.999999)));
assert.equal(pick('perch', { mood: 'exhausted', prev: 'perch_yawn' }, rnd), 'perch_yawn');
assert.equal(pick('nope', {}, rnd), '');
assert.equal(pick('stand', undefined, () => 0), STAND[0]);
console.log('CLAWD_FIDGETS_PASS');
