import assert from 'node:assert/strict';
import { style, textColor, sparks, RAINBOW } from '../../payload/clawd/js/effort.mjs';

// Claude: the surge helpers' colours
assert.deepEqual(style('claude', 'low', 0), { mode: 0, color: '#FFC107' });
assert.deepEqual(style('claude', 'medium', 0), { mode: 0, color: '#4EBA65' });
assert.deepEqual(style('claude', 'high', 0), { mode: 0, color: '#B1B9F9' });
assert.deepEqual(style('claude', 'xhigh', 0), { mode: 1, color: '#AF87FF' });
assert.equal(style('claude', 'max', 0).mode, 2);
assert.deepEqual(style('claude', 'ultracode', 0), { mode: 3, color: '#9BF6FF' });
// fake ultracode: 2+ sub-agents, same effects in #EB83FF; the real one wins; one sub-agent changes nothing
assert.deepEqual(style('claude', 'medium', 2), { mode: 3, color: '#EB83FF' });
assert.deepEqual(style('claude', 'low', 5), { mode: 3, color: '#EB83FF' });
assert.deepEqual(style('claude', 'ultracode', 3), { mode: 3, color: '#9BF6FF' });
assert.deepEqual(style('claude', 'medium', 1), { mode: 0, color: '#4EBA65' });
// Codex
assert.equal(style('codex', 'low', 0).color, '#92FFE7');
assert.equal(style('codex', 'light', 0).color, '#92FFE7');
assert.equal(style('codex', 'medium', 0).color, '#FFFFFF');
assert.equal(style('codex', 'high', 0).color, '#0093FF');
assert.equal(style('codex', 'xhigh', 0).color, '#FF6363');
assert.equal(style('codex', 'max', 0).mode, 4);
assert.equal(style('codex', 'ultra', 0).mode, 5);
assert.equal(style('codex', 'medium', 4).color, '#FFFFFF');   // sub-agents only matter for Claude
// unknown: nothing
assert.equal(style('claude', '', 0), null);
assert.equal(style('claude', undefined, 0), null);
assert.equal(style('claude', 'turbo', 0), null);
assert.equal(style('codex', 'turbo', 0), null);
assert.equal(style('gemini', 'high', 0), null);
assert.equal(style('claude', 'HIGH', 0).color, '#B1B9F9');
// spinner colour
assert.equal(textColor(null, 0), '');
assert.equal(textColor(style('claude', 'high', 0), 7), '#B1B9F9');
assert.equal(textColor(style('claude', 'max', 0), 0), RAINBOW[0]);
assert.equal(textColor(style('claude', 'max', 0), 7), RAINBOW[1]);
assert.notEqual(textColor(style('codex', 'max', 0), 0), textColor(style('codex', 'max', 0), 1));
assert.notEqual(textColor(style('codex', 'ultra', 0), 0), textColor(style('codex', 'ultra', 0), 1));
// particles
assert.equal(sparks(style('claude', 'high', 0)), false);
assert.equal(sparks(style('claude', 'xhigh', 0)), false);
assert.equal(sparks(style('claude', 'ultracode', 0)), true);
assert.equal(sparks(style('codex', 'max', 0)), true);
assert.equal(sparks(null), false);
console.log('CLAWD_EFFORT_PASS');
