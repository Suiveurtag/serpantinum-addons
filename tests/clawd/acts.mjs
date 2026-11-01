import assert from 'node:assert/strict';
import { NAMES, plan, pick } from '../../payload/clawd/js/acts.mjs';
import { readFileSync } from 'node:fs';

const manifest = JSON.parse(readFileSync(new URL('../../payload/clawd/sprites/clawd.json', import.meta.url))).animations;
let seed = 7;
const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;

// every special is a non-empty sequence of strips the manifest has; loop strips need a hold or a go, one-shots must end by themselves
for (const name of NAMES) {
  for (let n = 0; n < 20; n++) {
    const steps = plan(name, rnd);
    assert.ok(steps.length > 0, name);
    for (const s of steps) {
      const clip = manifest[s.clip];
      assert.ok(clip, `${name}: ${s.clip} missing`);
      if (s.go) { assert.ok(clip.loop && clip.frames > 1 && s.go.max >= s.go.min && s.go.v.length === 3, `${name}: ${s.clip} go`); continue; }
      if (clip.loop) assert.ok(s.ms > 0, `${name}: loop ${s.clip} needs a hold`);
      else assert.equal(s.ms, undefined, `${name}: one-shot ${s.clip} ends by itself`);
    }
  }
}
assert.deepEqual(plan('nope', rnd), []);
// pick never repeats the previous one, honours the filter, and reaches every special
const seen = new Set();
for (let i = 0; i < 400; i++) { const p = pick('book', rnd); assert.notEqual(p, 'book'); seen.add(p); }
assert.equal(seen.size, NAMES.length - 1);
assert.equal(pick('', rnd, n => n === 'nap'), 'nap');
assert.equal(pick('', rnd, () => false), '');
console.log('CLAWD_ACTS_PASS');
