// Clawd's idle fidgets (lot 9), pure: pick() chooses the next one for his pose and state.
// stand: one-shots on the floor, each starts and ends on idle's first frame; sit: seated loops, held like `sit`;
// perch: one-shots on a window top, each starts and ends on perch's first frame.
export const STAND = ['yawn', 'stretch', 'scratch', 'sneeze', 'look_around', 'tap', 'shake', 'doze', 'bubble', 'butterfly', 'yoyo', 'whistle', 'skip'];
export const SIT = ['sit_sway', 'sit_gaze'];
export const PERCH = ['perch_kick', 'perch_yawn'];
export const NAMES = [...STAND, ...SIT, ...PERCH];

const WEIGHT = { yawn: 2, stretch: 2, scratch: 3, sneeze: 1, look_around: 3, tap: 2, shake: 1.5, doze: 0.5, bubble: 1.5, butterfly: 1, yoyo: 1.5, whistle: 1.5, skip: 1,
                 sit_sway: 1, sit_gaze: 1, perch_kick: 2, perch_yawn: 1 };
// A mood keeps only what suits it (no games when he is worn out or under the rain), with its own weights.
const MOODS = {
  drowsy: { yawn: 4, doze: 3, stretch: 1, scratch: 1, perch_yawn: 1 },
  exhausted: { yawn: 3, doze: 4, scratch: 1, perch_yawn: 1 },
  rain: { shake: 3, sneeze: 2, look_around: 2, tap: 2, yawn: 1 },
  snow: { sneeze: 4, shake: 2, look_around: 1, tap: 1 },
};
// His nap is near (most of the idle delay has passed): he yawns and nods off, and no longer plays.
const SLEEPY = { yawn: 6, doze: 3, stretch: 2, scratch: 1, look_around: 1, perch_yawn: 3, sit_gaze: 1 };

// {name: weight} for a pose ('stand' | 'sit' | 'perch') and a state {mood, sleepy}.
export function pool(pose, state) {
  const list = pose === 'stand' ? STAND : pose === 'sit' ? SIT : pose === 'perch' ? PERCH : [];
  const mood = state && state.mood || '';
  const table = mood ? (Object.prototype.hasOwnProperty.call(MOODS, mood) ? MOODS[mood] : {}) : state && state.sleepy ? SLEEPY : WEIGHT;
  const out = {};
  for (const name of list) if (table[name] > 0) out[name] = table[name];
  return out;
}

// A random fidget (weighted) that is not state.prev; `ok(name)` filters out those the manifest lacks. '' when there is none.
export function pick(pose, state, rnd, ok) {
  const weights = pool(pose, state);
  let names = Object.keys(weights).filter(n => !ok || ok(n));
  if (names.length > 1) names = names.filter(n => n !== (state && state.prev));
  const total = names.reduce((a, n) => a + weights[n], 0);
  let r = rnd() * total;
  for (const n of names) { r -= weights[n]; if (r < 0) return n; }
  return names.length ? names[names.length - 1] : '';
}
