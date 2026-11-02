// Clawd's colour by the lead session's effort, pure: which tint his body gets while he works (shaders/tint.frag modes),
// and the colour of the spinner line over his head. Claude's colours are the surge helpers' (ClawdSurge.qml).
// Modes: 0 flat, 1 glint sweeping, 2 flowing rainbow, 3 electric, 4 gold with sparkles, 5 space with stars.
// Plain loops only: Qt's JS engine lacks some Array statics.
export const RAINBOW = ['#FF9E7A', '#FFD966', '#8FE3A0', '#9BD3FF', '#C9B5FF', '#FF9CB0'];
const GOLD = ['#FFD34D', '#FFF2B8'];
const SPACE = ['#9B7BFF', '#6FB6FF'];

const CLAUDE = {
  low: { mode: 0, color: '#FFC107' },
  medium: { mode: 0, color: '#4EBA65' },
  high: { mode: 0, color: '#B1B9F9' },
  xhigh: { mode: 1, color: '#AF87FF' },
  max: { mode: 2, color: '#FFB38A' },
  ultracode: { mode: 3, color: '#9BF6FF' },
};
const FAKE_ULTRACODE = { mode: 3, color: '#EB83FF' };     // Claude with 2 or more sub-agents working at once
const CODEX = {
  low: { mode: 0, color: '#FFFFFF' },
  medium: { mode: 0, color: '#ACFFD8' },
  high: { mode: 0, color: '#0093FF' },
  xhigh: { mode: 0, color: '#FF6363' },
  max: { mode: 4, color: '#FFD34D' },
  ultra: { mode: 5, color: '#7A5CFF' },
};
const ALIASES = { light: 'low', extra_high: 'xhigh', 'extra-high': 'xhigh', ultra_code: 'ultracode' };

// {mode, color} for an agent ('claude' | 'codex'), its effort and the number of sub-agents running; null = keep his own colour.
export function style(agent, effort, subCount) {
  let key = String(effort || '').toLowerCase();
  if (ALIASES[key]) key = ALIASES[key];
  if (agent === 'codex') return CODEX[key] || null;
  if (agent !== 'claude') return null;
  if (key !== 'ultracode' && subCount >= 2) return FAKE_ULTRACODE;
  return CLAUDE[key] || null;
}

// The spinner colour for a style at step i (the glyph and the verb): the flowing and sparkling modes cycle.
export function textColor(st, i) {
  if (!st) return '';
  const n = Math.max(0, Math.floor(i || 0));
  if (st.mode === 2) return RAINBOW[n % RAINBOW.length];
  if (st.mode === 4) return GOLD[n % 2];
  if (st.mode === 5) return SPACE[n % 2];
  return st.color;
}

// Whether the style has particles around him (electric, gold, space).
export function sparks(st) { return !!st && st.mode >= 3; }
