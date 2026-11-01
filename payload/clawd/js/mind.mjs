// Clawd's reaction arbiter, pure: decide() says what an event may do to him right now, commit() records that he did it.
// state = the pet's context (filled by the caller on every call) + memory (kept between calls, returned by commit):
//   drag, menu, petpet (bools: input owns him), hook ('' | 'work' | 'alert'), asleep, reactions ('all' | 'quiet' | 'off'),
//   dead, scene (bools: another system owns him), dnd, lowMotion, mode (his current mode); memory: last {kind: ms}, recent [ms of counted ambient reactions].
// decide -> {act: 'react' | 'glance' | 'bubble' | 'mood' | 'none', anim, tier}. Physics (falling, landing) never comes here.

export const TIERS = { input: 100, alert: 90, work: 80, urgent: 70, ambient: 40, explore: 20 };

// kind: tier, per-kind cooldown in ms, anim ('look' = toward the event: the pet resolves the direction).
// glance: a look only in a resting pose; bubble: a bubble, no motion; mood: a lasting mood, not a one-shot;
// motion: a lasting motion that low-motion mode forbids; notif: muted by do-not-disturb unless critical.
export const EVENTS = {
  window_open: { tier: 'ambient', cooldown: 6000, anim: 'look' },
  window_close_near: { tier: 'ambient', cooldown: 4000, anim: 'startled' },
  focus: { tier: 'ambient', cooldown: 3000, anim: 'look', glance: true },
  workspace: { tier: 'ambient', cooldown: 2500, anim: 'stumble' },
  layer: { tier: 'ambient', cooldown: 5000, anim: 'look_up' },
  notif: { tier: 'ambient', cooldown: 4000, anim: 'look_up', notif: true },
  notif_critical: { tier: 'urgent', cooldown: 0, anim: 'alert', notif: true, critical: true },
  timer_ring: { tier: 'urgent', cooldown: 0, anim: 'alert' },
  mute: { tier: 'ambient', cooldown: 10000, anim: 'shush' },
  brightness_low: { tier: 'ambient', cooldown: 60000, anim: 'drowsy', mood: true },
  battery_low: { tier: 'ambient', cooldown: 300000, anim: 'exhausted', mood: true },
  battery_critical: { tier: 'urgent', cooldown: 600000, anim: 'exhausted' },
  charging: { tier: 'ambient', cooldown: 60000, anim: 'happy' },
  track: { tier: 'ambient', cooldown: 0, anim: '', bubble: true },
  clock_hour: { tier: 'ambient', cooldown: 3000000, anim: 'chime' },
  rain: { tier: 'ambient', cooldown: 1800000, anim: 'umbrella', mood: true },
  music: { tier: 'ambient', cooldown: 0, anim: 'dance', motion: true },
  shell_menu: { tier: 'ambient', cooldown: 5000, anim: 'look', glance: true },   // launcher / clipboard / context menu opened
};

// Bubble ranks: a lower one never replaces a higher one (equal replaces). Shell bubbles are the lowest.
export const RANKS = { permission: 5, error: 4, done: 3, waiting: 3, notif: 1, music: 1 };
export function rank(kind) { return Object.prototype.hasOwnProperty.call(RANKS, kind) ? RANKS[kind] : 2; }
export function outranks(kind, than) { return rank(kind) >= rank(than); }

export const GLANCE_MODES = ['idle', 'sit', 'perch'];
export const MERGE_MS = 1000;      // the same kind twice within 1 s is one event
export const MINUTE_CAP = 6;       // ambient reactions per minute
export const GAP_MS = 5000;        // between two ambient reactions

export function memory() { return { last: {}, recent: [] }; }

function event(kind) { return Object.prototype.hasOwnProperty.call(EVENTS, kind) ? EVENTS[kind] : null; }

export function decide(state, kind, now, info = {}) {
  const e = event(kind), s = state || {};
  const none = { act: 'none', anim: '', tier: e ? e.tier : '' };
  if (!e || s.drag || s.menu || s.petpet || s.dead || s.scene) return none;  // dead / a scene (limit, revive, blast...) owns him
  const urgent = TIERS[e.tier] >= TIERS.urgent;
  // asleep: only urgent wakes him
  if (s.asleep && !urgent) return none;
  const reactions = s.reactions || 'all';
  if (reactions === 'off' && !urgent) return none;
  if (reactions === 'quiet' && !urgent && !e.bubble && !e.mood) return none;
  if (s.dnd && e.notif && !e.critical) return none;
  // a hook alert: urgent only glances; at work: urgent reacts (then back to work), only bubbles otherwise
  if (s.hook === 'alert' && !urgent) return none;
  if (s.hook === 'work' && !urgent && !e.bubble) return none;
  if (s.lowMotion && e.motion) return none;
  if (e.glance && GLANCE_MODES.indexOf(s.mode) < 0) return none;
  const last = s.last && Object.prototype.hasOwnProperty.call(s.last, kind) ? s.last[kind] : null;
  if (last !== null && now - last < Math.max(MERGE_MS, e.cooldown)) return none;
  if (counted(e)) {
    // low motion halves the ambient budget
    const recent = (s.recent || []).filter(t => now - t < 60000);
    const cap = s.lowMotion ? MINUTE_CAP / 2 : MINUTE_CAP, gap = s.lowMotion ? GAP_MS * 2 : GAP_MS;
    if (recent.length >= cap || recent.length && now - Math.max(...recent) < gap) return none;
  }
  const act = e.bubble ? 'bubble' : e.mood ? 'mood' : s.hook === 'alert' || e.glance ? 'glance' : 'react';
  return { act, anim: e.anim, tier: e.tier };
}

// Ambient motions count against the budget; bubbles and urgent events never do.
function counted(e) { return e.tier === 'ambient' && !e.bubble; }

export function commit(state, kind, now) {
  const e = event(kind), s = state || {};
  const last = Object.assign({}, s.last || {});
  if (e) last[kind] = now;
  let recent = (s.recent || []).filter(t => now - t < 60000);
  if (e && counted(e)) recent = recent.concat([now]);
  return Object.assign({}, s, { last, recent });
}
