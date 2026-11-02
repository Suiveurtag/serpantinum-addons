// Clawd's world, pure geometry in GLOBAL logical px (Hyprland layout coordinates). Adapted from Capri's world.mjs.

// Quickshell screens + Hyprland monitors (Quickshell HyprlandMonitor or raw `hyprctl monitors -j` objects) -> displays.
// floor = where he stands (above the reserved bottom area), top = under the bar (reserved top).
export function monitors(screens, native) {
  return screens.map(s => {
    const m = (native || []).find(m => m.name === s.name) || null;
    const ipc = m ? m.lastIpcObject || m : {};
    const r = Array.isArray(ipc.reserved) ? ipc.reserved : [0, 0, 0, 0];
    const x = m && Number.isFinite(m.x) ? m.x : s.x, y = m && Number.isFinite(m.y) ? m.y : s.y;
    const ws = m && m.activeWorkspace ? m.activeWorkspace.id : null;
    return { id: s.name, x, y, w: s.width, h: s.height,
      floor: y + s.height - Math.max(0, r[3] || 0), top: y + Math.max(0, r[1] || 0),
      workspace: Number.isFinite(ws) ? ws : null, special: ipc.specialWorkspace && ipc.specialWorkspace.id || 0 };
  });
}

// The display containing (gx, gy), else the nearest one.
export function displayAt(displays, gx, gy) {
  let best = null, gap = Infinity;
  for (const d of displays) {
    const dx = Math.max(d.x - gx, 0, gx - d.x - d.w), dy = Math.max(d.y - gy, 0, gy - d.y - d.h);
    if (dx + dy < gap) { gap = dx + dy; best = d; }
  }
  return best;
}

// j/clients -> the windows on screen, front first: fullscreen > floating/pinned > tiled, then focus history
// (approximates Hyprland's stacking). minimized: {address: true} from the foreign-toplevel protocol.
export function windows(clients, displays, minimized) {
  const shown = (clients || []).filter(c => {
    if (!c || !c.address || !c.at || !c.size || c.hidden || c.mapped === false || c.minimized || minimized && minimized[c.address]) return false;
    const ws = c.workspace ? c.workspace.id : null;
    return c.pinned || displays.some(d => ws === d.workspace || (d.special && ws === d.special));
  });
  const layer = c => c.fullscreen ? 2 : c.floating || c.pinned ? 1 : 0;
  const focus = c => c.focusHistoryID >= 0 ? c.focusHistoryID : Infinity;
  shown.sort((a, b) => layer(b) - layer(a) || focus(a) - focus(b));
  return shown.map(c => {
    const x = c.at[0], y = c.at[1], w = c.size[0], h = c.size[1];
    const d = displayAt(displays, x + w / 2, y + h / 2);
    return { id: c.address, x, y, w, h, max: !!(c.fullscreen || c.maximized), floating: !!(c.floating || c.pinned), display: d ? d.id : null };
  });
}

// Is any part of [x0, x1] at height y covered by a window in front of window `id`? (Unknown id: every window counts.)
export function covered(wins, id, x0, x1, y) {
  const i = wins.findIndex(w => w.id === id);
  const front = i < 0 ? wins : wins.slice(0, i);
  return front.some(w => w.x < x1 && w.x + w.w > x0 && y >= w.y && y < w.y + w.h);
}

// The uncovered piece of a ledge's top line around cx: {x0, x1}, or null when cx itself is covered or off the ledge.
export function span(wins, ledge, cx) {
  if (!ledge || cx < ledge.x || cx > ledge.x + ledge.w) return null;
  let x0 = ledge.x, x1 = ledge.x + ledge.w;
  if (ledge.kind === 'floor') return { x0, x1 };
  const i = wins.findIndex(w => w.id === ledge.id);
  for (const w of i < 0 ? wins : wins.slice(0, i)) {
    if (ledge.y < w.y || ledge.y >= w.y + w.h || w.x + w.w <= x0 || w.x >= x1) continue;
    if (cx >= w.x && cx <= w.x + w.w) return null;
    if (w.x + w.w <= cx) x0 = Math.max(x0, w.x + w.w); else x1 = Math.min(x1, w.x);
  }
  return { x0, x1 };
}

// Where he can stand: window tops (not maximized, wide enough, room above under the bar, above the floor),
// widget tops (5d: {id, x, y, w, h, display}) and one floor per display.
export function ledges({ wins = [], widgets = [], displays = [], petW = 0, petH = 0 }) {
  const out = [];
  const add = (kind, r) => {
    const d = displays.find(d => d.id === r.display) || displayAt(displays, r.x + r.w / 2, r.y);
    if (!d || r.max || r.w <= petW + 40 || r.y < d.top + petH + 8 || r.y > d.floor - petH) return;
    out.push({ id: r.id, kind, x: r.x, y: r.y, w: r.w, display: d.id });
  };
  for (const w of wins) add('win', w);
  for (const w of widgets) add('widget', w);
  for (const d of displays) out.push({ id: 'floor:' + d.id, kind: 'floor', x: d.x, y: d.floor, w: d.w, display: d.id });
  return out;
}

// Settling on a ledge with his contact near cx: cx clamped so his body stays on the ledge, then moved to the nearest
// uncovered point if a front window sits there; null when the ledge has none left.
export function standAt(wins, ledge, cx, half) {
  const h = Math.min(half, ledge.w / 2), lo = ledge.x + h, hi = ledge.x + ledge.w - h, clamp = v => Math.max(lo, Math.min(hi, v));
  if (ledge.kind === 'floor') return clamp(cx);
  const i = wins.findIndex(w => w.id === ledge.id), c = [clamp(cx), lo, hi];
  for (const w of i < 0 ? wins : wins.slice(0, i)) if (ledge.y >= w.y && ledge.y < w.y + w.h) c.push(clamp(w.x - 1), clamp(w.x + w.w + 1));
  const free = c.filter(v => span(wins, ledge, v)).sort((a, b) => Math.abs(a - cx) - Math.abs(b - cx));
  return free.length ? free[0] : null;
}

// Falling with his feet at (cx, feetY): the first free ledge he meets (top at/below his feet, spans cx, not covered at cx),
// else the floor of the display under cx.
export function landing(ledges, wins, cx, feetY, displays) {
  let best = null;
  for (const l of ledges) {
    if (l.kind === 'floor' || l.y < feetY - 1 || cx < l.x || cx > l.x + l.w || best && l.y >= best.y) continue;
    if (l.kind !== 'floor' && !span(wins, l, cx)) continue;  // same edge rule as span: a window edge at cx covers it
    best = l;
  }
  if (best) return best;
  const floors = ledges.filter(l => l.kind === 'floor');
  const d = displayAt(displays || floors.map(f => ({ id: f.display, x: f.x, y: f.y - 1, w: f.w, h: 1 })), cx, feetY);
  return d && floors.find(f => f.display === d.id) || floors[0] || null;
}

// The display touching d on that side (+1 right, -1 left) at height gy.
export function beyond(displays, d, side, gy) {
  if (!d) return null;
  return displays.find(o => o.id !== d.id && gy >= o.y && gy < o.y + o.h
    && (side > 0 ? Math.abs(o.x - d.x - d.w) <= 2 : Math.abs(o.x + o.w - d.x) <= 2)) || null;
}

// Where the cursor is: global point, its display, and whether it is on his display.
export function cursor(displays, here, p) {
  if (!p || !here) return null;
  const screen = displays.find(d => p.x >= d.x && p.x < d.x + d.w && p.y >= d.y && p.y < d.y + d.h);
  return { x: p.x, y: p.y, display: screen ? screen.id : null, inside: !!screen && screen.id === here.id };
}

// Two {id: rect} maps -> what opened, what closed (with its last rect) and what moved or resized.
export function diff(prev, next) {
  const opened = [], closed = [], moved = [];
  for (const id of Object.keys(next)) {
    const a = prev[id], b = next[id];
    if (!a) opened.push(id);
    else if (a.x !== b.x || a.y !== b.y || a.w !== b.w || a.h !== b.h) moved.push(id);
  }
  for (const id of Object.keys(prev)) if (!next[id]) closed.push({ id, rect: prev[id] });
  return { opened, closed, moved };
}

// 5b. Climbable window sides on display d: a window whose bottom is near the floor (he can walk up to it), at least his
// height tall, with room beside it; its outer strip must stay free of other windows (and its edge not hidden by a front
// one) over >= 60 % of the height. side -1 = its left edge (he is on its left, the wall on his right), 1 = its right edge.
export function sides(wins, d, petH) {
  const out = [];
  if (!d) return out;
  for (const w of wins) {
    if (w.display !== d.id || w.max || d.floor - (w.y + w.h) >= petH) continue;
    const y0 = Math.max(w.y, d.top), y1 = Math.min(w.y + w.h, d.floor);
    if (y1 - y0 < petH) continue;
    for (const side of [-1, 1]) {
      const x = side < 0 ? w.x : w.x + w.w, room = petH * 1.5;
      if (side < 0 ? x - d.x < room : d.x + d.w - x < room) continue;
      const s0 = side < 0 ? x - 12 : x + 2, s1 = side < 0 ? x - 2 : x + 12, n = Math.ceil((y1 - y0) / 16);
      let free = 0;
      for (let i = 0; i < n; i++) {
        const y = y0 + (i + 0.5) * (y1 - y0) / n;
        if (!wins.some(o => o.id !== w.id && !o.max && o.x < s1 && o.x + o.w > s0 && y >= o.y && y < o.y + o.h) && !covered(wins, w.id, x - 1, x + 1, y)) free++;
      }
      if (free / n >= 0.6) out.push({ id: w.id, side, x, y0, y1, display: d.id });
    }
  }
  return out;
}

// 5b. The bar's underside on display d, where he can hang: {x, y, w} (y = the bar's bottom edge, d.top) or null (not at
// the top, autohide, a fullscreen window, no reserved space). Its x extent comes from the matching `quickshell` layer
// (level 2, near the top, about bar.height tall) when layers() knows it, else the display minus the 4 px margins.
export function bar(d, raw, layers, fullscreen) {
  const b = raw || {};
  if (!d || fullscreen || (b.position || 'top') !== 'top' || b.autohide || !(d.top > d.y)) return null;
  const h = Number(b.height);
  const r = layers && (layers.rects || []).find(r => r.ns === 'quickshell' && r.level === 2 && r.display === d.id && r.y - d.y <= 16
    && (!Number.isFinite(h) || Math.abs(r.h - h) <= 14));
  const x = r ? r.x : d.x + 4, w = r ? r.w : d.w - 8;
  return w > 0 ? { x, y: d.top, w } : null;
}

const KINDS = [['launcher', /launcher/], ['clipboard', /clipboard/], ['desktopmenu', /desktop[-_]?menu/], ['traymenu', /tray[-_]?menu/],
  ['osd', /osd/], ['sidemusic', /side[-_]?music/]];

// 5b. What a layer namespace is for the pet (null: nothing he cares about).
export function layerKind(ns) {
  const s = String(ns || '').toLowerCase();
  if (s === 'qs-popups') return 'popups';
  if (s === 'qs-master') return 'master';
  const k = KINDS.find(([, re]) => re.test(s));
  return k ? k[0] : null;
}

// 5b. Hyprland `j/layers` ({monitor: {level: [{namespace, x, y, w, h}]}}, monitor-local px) -> rects in global px
// [{ns, level, display, x, y, w, h}], the widgets among them (`qs-widget-<type>-<id>`, inset by the 8 px aura; not
// visualizers, not huge ones) and the namespaces of the layers with a kind.
export function layers(json, displays = []) {
  const rects = [], widgets = [];
  if (json && typeof json === 'object') for (const mon of Object.keys(json)) {
    const d = displays.find(d => d.id === mon), lv = json[mon] && typeof json[mon] === 'object' ? json[mon] : {};
    for (const level of Object.keys(lv)) for (const l of Array.isArray(lv[level]) ? lv[level] : []) {
      if (!l || typeof l.namespace !== 'string' || ![l.x, l.y, l.w, l.h].every(Number.isFinite)) continue;
      const r = { ns: l.namespace, level: Number(level), display: mon, x: l.x + (d ? d.x : 0), y: l.y + (d ? d.y : 0), w: l.w, h: l.h };
      rects.push(r);
      const m = /^qs-widget-([^-]+)-/.exec(r.ns);
      if (m && m[1] !== 'visualizer' && !(d && (r.h > d.h / 2 || r.w > d.w * 0.8)))
        widgets.push({ id: r.ns, type: m[1], display: mon, x: r.x + 8, y: r.y + 8, w: r.w - 16, h: r.h - 16 });
    }
  }
  const open = [...new Set(rects.filter(r => layerKind(r.ns)).map(r => r.ns))];
  return { widgets, open, rects };
}

// 5d. A widget's type (the `<type>` of `qs-widget-<type>-<id>`) -> what Clawd does with it: clock (the hourly chime) | music (a dance spot) | null.
export function widgetKind(type) {
  const t = String(type || '').toLowerCase();
  return t === 'time' || t === 'clock' ? 'clock' : t === 'music' ? 'music' : null;
}

// 5d. Weather.currentIcon (a nerd-font glyph from scripts/weather.sh wmo_map) -> rain | snow | storm | clear | other.
// rainy U+F0597 (drizzle, rain, showers), snow U+F2DC, storm U+F0E7, sunny U+F185 / clear night U+F186.
export function weatherKind(icon) {
  const c = String(icon || '').trim().codePointAt(0);
  return c === 0xf0597 ? 'rain' : c === 0xf2dc ? 'snow' : c === 0xf0e7 ? 'storm' : c === 0xf185 || c === 0xf186 ? 'clear' : 'other';
}
