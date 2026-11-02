import assert from 'node:assert/strict';
import { create, push, tempo } from '../../payload/clawd/js/beat.mjs';

// deterministic noise
let seed = 12345;
const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;

function run(level, seconds, start = 0) {
  let s = create(), t = start;
  const seen = [];
  for (; t < start + seconds * 1000; t += 50) { s = push(s, level(t - start), t); seen.push(s.bpm); }
  return { s, seen };
}
// a pulse of two samples every `period` ms over a quiet floor
const pulse = period => t => (t % period) < 100 ? 0.8 : 0.05;

for (const bpm of [100, 120, 140]) {
  const { s } = run(pulse(60000 / bpm), 12);
  assert.ok(Math.abs(s.bpm - bpm) <= 5, `${bpm} BPM -> ${s.bpm}`);
}
assert.ok(Math.abs(run(pulse(500), 12).s.bpm - 120) <= 5);
// a slow pulse folds into range (60 BPM -> 120 or 60 both mean the same beat; it must be in 70-170 or 0)
const slow = run(pulse(1000), 14).s.bpm;
assert.ok(slow === 0 || (slow >= 70 && slow <= 170), 'slow ' + slow);
// a wobbly 120 BPM pulse with a noisy floor still locks
assert.ok(Math.abs(run(t => (t % 500) < 100 ? 0.7 + rnd() * 0.2 : rnd() * 0.12, 12).s.bpm - 120) <= 6);

// silence, constant level and noise never produce a tempo
assert.equal(run(() => 0, 10).s.bpm, 0);
assert.equal(run(() => 0.5, 10).s.bpm, 0);
for (let i = 0; i < 5; i++) assert.ok(run(() => rnd(), 20).seen.slice(40).every(b => b === 0), 'noise ' + i);

// the music stops: the tempo is forgotten
let s = run(pulse(500), 10).s, t = 10000;
for (; t < 15000; t += 50) s = push(s, 0, t);
assert.equal(s.bpm, 0);
// bad input is harmless; push never mutates
const a = create(), b = push(a, NaN, 0);
assert.equal(a.hist.length, 0);
assert.equal(b.bpm, 0);
assert.equal(tempo([]), 0);
console.log('CLAWD_BEAT_PASS');
