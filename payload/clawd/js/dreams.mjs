// Clawd's sleep life, pure: the dream registry, the dream book (what he has seen) and what happens next while he sleeps.
// Kind choice: pick(null, ...) first rolls pickKind() (~25% nightmare, 75% dream), then picks inside that kind; an empty kind falls back to all entries.
// Plain loops only: Qt's JS engine lacks some Array statics (Array.from etc.).
// To add a dream: one entry here + a QML scene + the type in clawd.py TYPES.
export const DREAMS = [
  { id: 'surf', kind: 'dream', title: 'Rainbow surf', glyph: '✦', scene: 'ClawdDreamSurf', duration: 24, weight: 1 },
  { id: 'gemini', kind: 'nightmare', title: 'Gemini', glyph: '☠', scene: 'ClawdNightmareGemini', duration: 11.7, jump: 11.0, weight: 1 },
  { id: 'ouroboros', kind: 'nightmare', title: 'Ouroboros', glyph: '∞', scene: 'ClawdNightmareOuroboros', duration: 13.5, jump: 12.8, weight: 1 },
  { id: 'bsod', kind: 'nightmare', title: 'Blue screen', glyph: ':(', scene: 'ClawdNightmareBsod', duration: 12.5, jump: 11.6, weight: 1 },
  { id: 'panic', kind: 'nightmare', title: 'Kernel panic', glyph: '#', scene: 'ClawdNightmarePanic', duration: 12.5, jump: 11.6, weight: 1 },
];

export const NAMES = (() => {
  const out = ['dream', 'nightmare', 'blanket', 'sleepwalk'];
  for (let i = 0; i < DREAMS.length; i++) out.push(DREAMS[i].kind + '_' + DREAMS[i].id);
  return out;
})();

export const MUMBLES = ['five more minutes…', 'no, not the rate limit…', 'ctx 99%…', 'mmh… tokens…', 'just one more commit…', 'it compiled… zzz', 'regenerate… regenerate…', 'is it a tool call or a dream…', 'sudo make me a sandwich…', 'git blame… me?'];
export const BLANKET_MUMBLES = ['…where\'s my blanket', 'cold… blanket…', 'who took my blanket…'];

const TICK_MIN = 14000, TICK_MAX = 28000, TICK_LOW = 60000;
const NIGHTMARE_CHANCE = 0.25;

export function byId(id) {
  for (let i = 0; i < DREAMS.length; i++) if (DREAMS[i].id === id) return DREAMS[i];
  return null;
}

export function pickKind(rnd) { return rnd() < NIGHTMARE_CHANCE ? 'nightmare' : 'dream'; }

// weighted choice among registry entries of `kind` (null = roll the kind first); entries absent from `seen` weigh x2. Returns the entry id or ''.
export function pick(kind, rnd, seen) {
  const k = kind || pickKind(rnd), s = seen || {};
  let pool = [];
  for (let i = 0; i < DREAMS.length; i++) if (DREAMS[i].kind === k) pool.push(DREAMS[i]);
  if (!pool.length && !kind) pool = DREAMS.slice();
  if (!pool.length) return '';
  const ws = [];
  let total = 0;
  for (let i = 0; i < pool.length; i++) {
    const w = (pool[i].weight > 0 ? pool[i].weight : 1) * (s[pool[i].id] ? 1 : 2);
    ws.push(w); total += w;
  }
  let r = rnd() * total;
  for (let i = 0; i < pool.length; i++) { r -= ws[i]; if (r < 0) return pool[i].id; }
  return pool[pool.length - 1].id;
}

// pure: returns a new state, never mutates `state`; null/malformed state is treated as empty
export function record(state, id, kind, now, cap) {
  const max = cap > 0 ? cap : 40;
  const seen = {}, log = [];
  const old = state && typeof state === 'object' && state.seen && typeof state.seen === 'object' ? state.seen : {};
  for (const key in old) {
    const e = old[key];
    if (e && typeof e === 'object') seen[key] = { n: Number(e.n) || 0, first: Number(e.first) || 0, last: Number(e.last) || 0 };
  }
  const prev = seen[id];
  seen[id] = { n: (prev ? prev.n : 0) + 1, first: prev && prev.first ? prev.first : now, last: now };
  log.push({ id, kind, at: now });
  const oldLog = state && Array.isArray(state.log) ? state.log : [];
  for (let i = 0; i < oldLog.length && log.length < max; i++) {
    const l = oldLog[i];
    if (l && typeof l === 'object') log.push({ id: l.id, kind: l.kind, at: l.at });
  }
  return { seen, log };
}

export function book(state) {
  const seen = state && typeof state === 'object' && state.seen && typeof state.seen === 'object' ? state.seen : {};
  const out = [];
  for (let i = 0; i < DREAMS.length; i++) {
    const d = DREAMS[i], e = seen[d.id];
    out.push({ id: d.id, kind: d.kind, title: d.title, glyph: d.glyph, seen: !!e, n: e ? Number(e.n) || 0 : 0, first: e ? Number(e.first) || 0 : 0, last: e ? Number(e.last) || 0 : 0 });
  }
  return out;
}

// what happens next in his sleep: 'roll' | 'dream' | 'talk' | 'walk' | '' (nothing). ctx = { sleptMs, now, bubble, last: {roll, dream, talk, walk} ms, lowMotion, canWalk, hasRoll }
export function nextSleepEvent(rnd, ctx) {
  const c = ctx || {}, last = c.last || {}, now = c.now || 0, slept = c.sleptMs || 0;
  const ready = (key, cooldown) => now - (last[key] || 0) >= cooldown;
  const cands = [];
  if (c.hasRoll && ready('roll', 60000)) cands.push(['roll', 0.2]);
  if (slept >= 40000 && !c.bubble && ready('dream', 240000)) cands.push(['dream', 0.18]);
  if (ready('talk', 90000)) cands.push(['talk', 0.12]);
  if (slept >= 180000 && c.canWalk && !c.lowMotion && ready('walk', 900000)) cands.push(['walk', 0.03]);
  for (let i = 0; i < cands.length; i++) if (rnd() < cands[i][1]) return cands[i][0];
  return '';
}

export function tickMs(lowMotion, rnd) { return lowMotion ? TICK_LOW : Math.round(TICK_MIN + rnd() * (TICK_MAX - TICK_MIN)); }
