import assert from 'node:assert/strict';
import { monitors, displayAt, windows, covered, span, ledges, landing, standAt, beyond, cursor, diff, sides, bar, layers, layerKind, widgetKind, weatherKind } from '../../payload/clawd/js/world.mjs';

// Two screens side by side (the live layout: HDMI-A-1 left of DP-1, bars on top) + a third one far away.
const screens = [{ name: 'DP-1', x: 0, y: 31, width: 1920, height: 1080 }, { name: 'HDMI-A-1', x: -1920, y: 27, width: 1920, height: 1080 },
  { name: 'far', x: 5000, y: 0, width: 800, height: 600 }];
const native = [
  { name: 'DP-1', x: 0, y: 31, activeWorkspace: { id: 2 }, lastIpcObject: { reserved: [0, 45, 0, 0], specialWorkspace: { id: 0 } } },
  // raw `hyprctl monitors -j` shape (fixtures): reserved at the top level
  { name: 'HDMI-A-1', x: -1920, y: 27, activeWorkspace: { id: 1 }, reserved: [0, 45, 0, 30], specialWorkspace: { id: -98 } },
];
const displays = monitors(screens, native);
const [dp, hdmi, far] = displays;
assert.deepEqual(dp, { id: 'DP-1', x: 0, y: 31, w: 1920, h: 1080, floor: 1111, top: 76, workspace: 2, special: 0 });
assert.deepEqual(hdmi, { id: 'HDMI-A-1', x: -1920, y: 27, w: 1920, h: 1080, floor: 1077, top: 72, workspace: 1, special: -98 });
assert.deepEqual(far, { id: 'far', x: 5000, y: 0, w: 800, h: 600, floor: 600, top: 0, workspace: null, special: 0 });
assert.deepEqual(monitors([{ name: 'solo', x: 0, y: 0, width: 100, height: 50 }], []), [{ id: 'solo', x: 0, y: 0, w: 100, h: 50, floor: 50, top: 0, workspace: null, special: 0 }]);
assert.equal(displayAt(displays, 10, 40).id, 'DP-1');
assert.equal(displayAt(displays, -5, 500).id, 'HDMI-A-1');
assert.equal(displayAt(displays, 4000, 500).id, 'far');  // nearest

// Windows: visible ones only, global coords, front first.
const client = (address, more = {}) => ({ address, at: [100, 300], size: [600, 400], workspace: { id: 2 }, mapped: true, focusHistoryID: 5, ...more });
const clients = [
  client('tile', { focusHistoryID: 0, at: [8, 84], size: [1904, 1019] }),
  client('float', { floating: true, focusHistoryID: 1, at: [786, 445], size: [1065, 587] }),
  client('back', { floating: true, focusHistoryID: 3, at: [600, 700], size: [500, 300] }),
  client('hidden', { hidden: true }), client('unmapped', { mapped: false }), client('min', { minimized: true }),
  client('foreignmin', { floating: true }), client('other-ws', { workspace: { id: 7 } }),
  client('left', { workspace: { id: 1 }, at: [-1800, 500], size: [800, 400], floating: true, focusHistoryID: 2 }),
  client('special', { workspace: { id: -98 }, floating: true, focusHistoryID: 9, at: [-1000, 200], size: [300, 300] }),
  client('pinned', { workspace: { id: 9 }, pinned: true, focusHistoryID: 8, at: [1500, 100], size: [200, 200] }),
  client('full', { fullscreen: 2, focusHistoryID: 6, workspace: { id: 1 }, at: [-1920, 27], size: [1920, 1080] }),
  { address: 'broken' },
];
const wins = windows(clients, displays, { foreignmin: true });
assert.deepEqual(wins.map(w => w.id), ['full', 'float', 'left', 'back', 'pinned', 'special', 'tile']);
assert.deepEqual(wins[1], { id: 'float', x: 786, y: 445, w: 1065, h: 587, max: false, floating: true, display: 'DP-1' });
assert.equal(wins[0].max, true);
assert.equal(wins.find(w => w.id === 'left').display, 'HDMI-A-1');
assert.equal(wins.find(w => w.id === 'tile').floating, false);
assert.deepEqual(windows([], displays), []);

// Covered: windows in front only.
assert.equal(covered(wins, 'back', 800, 820, 700), true);    // float (in front) covers back's top there
assert.equal(covered(wins, 'back', 600, 700, 700), false);   // float starts at x 786
assert.equal(covered(wins, 'float', 800, 900, 445), false);  // nothing in front of it on DP-1
assert.equal(covered(wins, 'tile', 800, 900, 445), true);
assert.equal(covered(wins, 'nope', 800, 900, 445), true);     // unknown id: every window counts

// Ledges: window tops with room above under the bar, wide enough, not maximized, above the floor; one floor per display.
const petW = 84, petH = 56;
const flat = ledges({ wins, displays, petW, petH });
assert.deepEqual(flat.filter(l => l.kind === 'win').map(l => l.id), ['float', 'left', 'back', 'special']);
assert.deepEqual(flat.find(l => l.id === 'float'), { id: 'float', kind: 'win', x: 786, y: 445, w: 1065, display: 'DP-1' });
// tile: top 84 is 8 px under the bar (76); pinned: 200 px wide but its top (100) has no room; full: maximized
assert.deepEqual(flat.filter(l => l.kind === 'floor').map(l => [l.id, l.y, l.x, l.w]), [['floor:DP-1', 1111, 0, 1920], ['floor:HDMI-A-1', 1077, -1920, 1920], ['floor:far', 600, 5000, 800]]);
assert.equal(ledges({ wins: [{ id: 'narrow', x: 0, y: 500, w: 120, h: 100, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'win').length, 0);
assert.equal(ledges({ wins: [{ id: 'low', x: 0, y: 1100, w: 500, h: 11, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'win').length, 0);
// widgets (5d) use the same rules
assert.deepEqual(ledges({ widgets: [{ id: 'clock', x: 100, y: 400, w: 300, h: 120, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'widget').map(l => l.id), ['clock']);
assert.equal(ledges({ displays }).length, 3);

// Span: the uncovered part of a ledge around cx.
const back = flat.find(l => l.id === 'back');
assert.deepEqual(span(wins, back, 650), { x0: 600, x1: 786 });  // float covers back's top from x 786
assert.equal(span(wins, back, 900), null);
assert.equal(span(wins, back, 2000), null);                       // off the ledge
assert.deepEqual(span(wins, flat.find(l => l.id === 'float'), 1000), { x0: 786, x1: 1851 });
assert.deepEqual(span(wins, flat.find(l => l.kind === 'floor'), 50), { x0: 0, x1: 1920 });

// Landing: first free ledge at/below his feet spanning cx, else the floor under cx.
assert.equal(landing(flat, wins, 1000, 100, displays).id, 'float');
assert.equal(landing(flat, wins, 1000, 446, displays).id, 'float');   // 1 px tolerance
assert.equal(landing(flat, wins, 1000, 450, displays).id, 'floor:DP-1');
assert.equal(landing(flat, wins, 650, 100, displays).id, 'back');
assert.equal(landing(flat, wins, 900, 500, displays).id, 'floor:DP-1');   // under float, back is covered there
assert.equal(landing(flat, wins, -1500, 100, displays).id, 'floor:HDMI-A-1');  // the fullscreen window covers 'left'
assert.equal(landing(flat, wins.filter(w => w.id !== 'full'), -1500, 100, displays).id, 'left');
assert.equal(landing(flat, wins, -100, 100, displays).id, 'floor:HDMI-A-1');
assert.equal(landing(flat, wins, 5100, 0, displays).id, 'floor:far');
assert.equal(landing(flat.filter(l => l.kind === 'floor'), [], 100, 100).id, 'floor:DP-1');  // no displays: floors' spans
assert.equal(landing([], [], 0, 0, displays), null);
// exact window edge: landing and span agree (float covers back from x 786, inclusive), so no fall loop
assert.equal(span(wins, back, 786), null);
assert.equal(landing(flat, wins, 786, 100, displays).id, 'float');
assert.equal(landing(flat, wins, 785, 100, displays).id, 'back');

// standAt: clamped onto the ledge, then to the nearest uncovered point; null when the ledge has none.
assert.equal(standAt(wins, back, 650, 42), 650);
assert.equal(standAt(wins, back, 610, 42), 642);                    // clamped to the ledge ends
assert.equal(standAt(wins, back, 790, 42), 785);                    // 790 is under float: the nearest free point
assert.equal(standAt(wins, flat.find(l => l.id === 'float'), 5, 42), 828);
assert.equal(standAt(wins, flat.find(l => l.kind === 'floor'), 5, 42), 42);
assert.equal(standAt([{ id: 'top', x: 0, y: 0, w: 100, h: 900 }, { id: 'low', x: 0, y: 500, w: 100, h: 10 }], { id: 'low', kind: 'win', x: 0, y: 500, w: 100, h: 10, display: 'x' }, 50, 42), null);

// Beyond / cursor in global coords.
assert.equal(beyond(displays, dp, -1, 500).id, 'HDMI-A-1');
assert.equal(beyond(displays, hdmi, 1, 500).id, 'DP-1');
assert.equal(beyond(displays, dp, 1, 500), null);
assert.equal(beyond(displays, dp, -1, 10), null);   // above HDMI's top (27)
assert.equal(beyond(displays, null, 1, 0), null);
assert.deepEqual(cursor(displays, dp, { x: -100, y: 600 }), { x: -100, y: 600, display: 'HDMI-A-1', inside: false });
assert.deepEqual(cursor(displays, dp, { x: 100, y: 600 }), { x: 100, y: 600, display: 'DP-1', inside: true });
assert.deepEqual(cursor(displays, dp, { x: 3000, y: 600 }), { x: 3000, y: 600, display: null, inside: false });
assert.equal(cursor(displays, dp, null), null);

// Diff.
const r = (x, y = 0) => ({ x, y, w: 10, h: 10 });
assert.deepEqual(diff({ a: r(0), b: r(5), c: r(9) }, { a: r(0), b: r(6), d: r(1) }), { opened: ['d'], closed: [{ id: 'c', rect: r(9) }], moved: ['b'] });
assert.deepEqual(diff({}, {}), { opened: [], closed: [], moved: [] });
// 5b sides: windows whose bottom is near the floor, tall enough, with room beside them and a free outer strip.
const sw = [
  { id: 'a', x: 400, y: 600, w: 300, h: 500, max: false, display: 'DP-1' },      // bottom 1100: floor 1111 - 1100 < 56
  { id: 'hi', x: 1000, y: 100, w: 300, h: 400, max: false, display: 'DP-1' },    // bottom 500: far above the floor
  { id: 'short', x: 1400, y: 1080, w: 200, h: 40, max: false, display: 'DP-1' }, // shorter than him
  { id: 'edge', x: 8, y: 600, w: 300, h: 500, max: false, display: 'DP-1' },     // no room on its left
  { id: 'big', x: 0, y: 76, w: 1920, h: 1035, max: true, display: 'DP-1' },
  { id: 'other', x: -900, y: 600, w: 300, h: 450, max: false, display: 'HDMI-A-1' },
];
const ss = sides(sw.filter(w => w.id !== 'big'), dp, petH);
assert.deepEqual(ss.map(s => [s.id, s.side, s.x, s.y0, s.y1]), [['a', -1, 400, 600, 1100], ['a', 1, 700, 600, 1100], ['edge', 1, 308, 600, 1100]]);
assert.equal(ss[0].display, 'DP-1');
assert.deepEqual(sides(sw.filter(w => w.id === 'other'), hdmi, petH).map(s => [s.id, s.side]), [['other', -1], ['other', 1]]);
assert.deepEqual(sides(sw, null, petH), []);
// a neighbour hugging the right edge hides it; a front window covering most of the edge too; a small cover is fine
const near = [{ id: 'a', x: 400, y: 600, w: 300, h: 500, display: 'DP-1' }, { id: 'n', x: 705, y: 500, w: 300, h: 700, display: 'DP-1' }];
assert.deepEqual(sides(near, dp, petH).map(s => [s.id, s.side]), [['a', -1], ['n', 1]]);   // the facing edges are hidden
const front = [{ id: 'f', x: 380, y: 650, w: 100, h: 440, display: 'DP-1' }, { id: 'a', x: 400, y: 600, w: 300, h: 500, display: 'DP-1' }];
assert.equal(sides(front, dp, petH).some(s => s.id === 'a' && s.side === -1), false);
assert.equal(sides([{ id: 'f', x: 380, y: 1000, w: 100, h: 60, display: 'DP-1' }, { id: 'a', x: 400, y: 600, w: 300, h: 500, display: 'DP-1' }], dp, petH).some(s => s.id === 'a' && s.side === -1), true);

// 5b bar: only at the top, no autohide, no fullscreen, with reserved space; x from the quickshell layer when known.
const cfg = { position: 'top', height: 36, autohide: false };
assert.deepEqual(bar(dp, cfg, null, false), { x: 4, y: 76, w: 1912 });
assert.deepEqual(bar(dp, undefined, null, false), { x: 4, y: 76, w: 1912 });
assert.equal(bar(dp, { ...cfg, position: 'bottom' }, null, false), null);
assert.equal(bar(dp, { ...cfg, autohide: true }, null, false), null);
assert.equal(bar(dp, cfg, null, true), null);
assert.equal(bar(far, cfg, null, false), null);   // nothing reserved
assert.equal(bar(null, cfg, null, false), null);
const lj = { 'DP-1': { 0: [{ namespace: 'qs-widget-clock-7', x: 100, y: 200, w: 300, h: 120 }, { namespace: 'qs-widget-visualizer-2', x: 0, y: 0, w: 100, h: 100 },
  { namespace: 'qs-widget-notes-3', x: 0, y: 0, w: 1800, h: 900 }], 2: [{ namespace: 'quickshell', x: 4, y: 4, w: 1912, h: 41 }, { namespace: 'qs-master', x: 0, y: 0, w: 1920, h: 1080 }, { namespace: 'quickshell', x: 10, y: 600, w: 50, h: 41 }],
  3: [{ namespace: 'qs-popups', x: 1500, y: 10, w: 400, h: 100 }] }, 'HDMI-A-1': { 2: [{ namespace: 'quickshell', x: 20, y: 4, w: 1880, h: 41 }] }, junk: 5 };
const ly = layers(lj, displays);
assert.deepEqual(ly.open, ['qs-master', 'qs-popups']);
assert.deepEqual(ly.widgets, [{ id: 'qs-widget-clock-7', type: 'clock', display: 'DP-1', x: 108, y: 239, w: 284, h: 104 }]);
assert.deepEqual(ly.rects.find(r => r.ns === 'qs-popups'), { ns: 'qs-popups', level: 3, display: 'DP-1', x: 1500, y: 41, w: 400, h: 100 });
assert.deepEqual(bar(dp, cfg, ly, false), { x: 4, y: 76, w: 1912 });
assert.deepEqual(bar(hdmi, cfg, ly, false), { x: -1900, y: 72, w: 1880 });
assert.deepEqual(bar(dp, { ...cfg, height: 100 }, ly, false), { x: 4, y: 76, w: 1912 });   // no layer of about that height: the default
assert.deepEqual(layers(null), { widgets: [], open: [], rects: [] });
assert.deepEqual(layers({ a: { 2: [{ namespace: 5 }, null, { namespace: 'x', x: 'a' }] } }).rects, []);
assert.equal(layerKind('qs-master'), 'master');
assert.equal(layerKind('qs-popups'), 'popups');
assert.equal(layerKind('qs-Launcher'), 'launcher');
assert.equal(layerKind('qs-clipboard'), 'clipboard');
assert.equal(layerKind('qs-desktop-menu'), 'desktopmenu');
assert.equal(layerKind('qs-traymenu'), 'traymenu');
assert.equal(layerKind('qs-osd'), 'osd');
assert.equal(layerKind('qs-side-music'), 'sidemusic');
assert.equal(layerKind('quickshell'), null);
assert.equal(layerKind('qs-widget-clock-7'), null);
assert.equal(layerKind(undefined), null);

// 5d: widgets are ledges (inset rect), a front window covers them, and the kinds Clawd cares about.
const wl = ledges({ wins: [], widgets: ly.widgets, displays, petW: 56, petH: 56 }).find(l => l.kind === 'widget');
assert.deepEqual(wl, { id: 'qs-widget-clock-7', kind: 'widget', x: 108, y: 239, w: 284, display: 'DP-1' });
assert.equal(ledges({ wins: [], widgets: ly.widgets.map(w => ({ ...w, w: 90 })), displays, petW: 56, petH: 56 }).some(l => l.kind === 'widget'), false);   // too narrow
assert.equal(ledges({ wins: [], widgets: ly.widgets.map(w => ({ ...w, y: 90 })), displays, petW: 56, petH: 56 }).some(l => l.kind === 'widget'), false);   // no room under the bar
assert.deepEqual(span([], wl, 200), { x0: 108, x1: 392 });
const over = [{ id: 'wnd', x: 150, y: 200, w: 100, h: 300, display: 'DP-1' }];   // widgets sit on the Bottom layer: every window is in front
assert.equal(span(over, wl, 200), null);
assert.deepEqual(span(over, wl, 300), { x0: 250, x1: 392 });
assert.ok(span(over, wl, standAt(over, wl, 200, 28)));
assert.equal(widgetKind('time'), 'clock');
assert.equal(widgetKind('Clock'), 'clock');
assert.equal(widgetKind('music'), 'music');
assert.equal(widgetKind('weather'), null);
assert.equal(widgetKind(undefined), null);
const glyph = n => String.fromCodePoint(n);
assert.equal(weatherKind(glyph(0xf0597)), 'rain');
assert.equal(weatherKind(glyph(0xf2dc)), 'snow');
assert.equal(weatherKind(glyph(0xf0e7)), 'storm');
assert.equal(weatherKind(glyph(0xf185)), 'clear');
assert.equal(weatherKind(glyph(0xf186) + ' '), 'clear');
assert.equal(weatherKind(glyph(0xf0c2)), 'other');   // cloudy / unknown
assert.equal(weatherKind(glyph(0xf0591)), 'other');   // mist
assert.equal(weatherKind(''), 'other');
assert.equal(weatherKind(undefined), 'other');
console.log('CLAWD_WORLD_PASS');
