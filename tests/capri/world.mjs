import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { monitors, windows, beyond, cursor, uncovered, device, deviceBlock } from '../../payload/capri/js/world.mjs';
import { Pc } from '../../payload/capri/js/pc.mjs';
const { steamGame } = createRequire(import.meta.url)('../../scripts/capri/world.js');

const displays = monitors([{ name: 'left', x: -1920, y: 27, width: 1920, height: 1080 },
  { name: 'right', x: 0, y: 31, width: 1280, height: 720 }], [
  { name: 'left', x: -1920, y: 27, activeWorkspace: { id: 1 }, lastIpcObject: {} },
  { name: 'right', x: 0, y: 31, activeWorkspace: { id: 5 }, lastIpcObject: { reserved: [0, 45, 0, 30], specialWorkspace: { id: -99 } } }
]);
const [left, right] = displays;
assert.equal(right.floor, 690);
assert.equal(beyond(displays, left, 1, 100), right);
assert.equal(beyond(displays, right, -1, 100), left);
assert.equal(beyond(displays, left, 1, 2), null);
assert.equal(beyond([left, { ...right, x: 10 }], left, 1, 100), null);
assert.deepEqual(cursor(displays, left, { x: 100, y: 100 }), { x: 2020, y: 73, display: 'right', inside: false });
const client = (id, more = {}) => ({ address: id, at: [-100, 300], size: [600, 400], workspace: { id: 5 }, mapped: true, ...more });
const data = windows([client('tile', { focusHistoryID: 0 }), client('float', { floating: true, focusHistoryID: 4 }),
  client('back', { floating: true, focusHistoryID: 8 }), client('hidden', { hidden: true }),
  client('min', { minimized: true }), client('other-workspace', { workspace: { id: 8 } }),
  client('special', { workspace: { id: -99 }, floating: true, focusHistoryID: -1 })], displays, left, 'tile');
assert.deepEqual(data.wins.map(w => w.id), ['float', 'back', 'special', 'tile']);
assert.deepEqual(data.wins[0], { id: 'float', x: 1820, y: 273, w: 600, h: 400, max: false });
assert.equal(data.fg, 'tile');
// Two overlapping covers remove their union (60*60 + 60*60 - 40*40), never reveal it.
const rect = { x: 0, y: 0, w: 100, h: 100 };
const covers = [{ x: 10, y: 10, w: 60, h: 60 }, { x: 30, y: 30, w: 60, h: 60 }];
const pieces = uncovered(rect, covers);
assert.equal(pieces.reduce((a, r) => a + r.w * r.h, 0), 4400);
for (let y = 0; y < 100; y++) for (let x = 0; x < 100; x++) {
  const inside = r => x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
  assert.equal(pieces.filter(inside).length, covers.some(inside) ? 0 : 1);
}
assert.deepEqual(uncovered(rect, [rect]), []);
assert.deepEqual(uncovered(rect, [{ x: 110, y: 110, w: 5, h: 5 }]), [rect]);

const calls = [], reactions = [];
const c = { free: true, stowed: false, view: { w: 1280, h: 720 }, wake() {}, hurt() { calls.push('hurt'); },
  perform(a) { calls.push(a); }, drain() { calls.push('drain'); }, recharge() { calls.push('recharge'); },
  stow() { this.stowed = true; calls.push('stow'); }, unstow() { this.stowed = false; calls.push('unstow'); },
  visit() { calls.push('visit'); }, zap() { calls.push('zap'); } };
const pc = new Pc(c, k => reactions.push(k));
pc.sample({ cpu: 90 }, 0); pc.sample({ cpu: 90 }, 14999);
assert.equal(calls.length, 0);
pc.sample({ cpu: 90 }, 15000); assert.deepEqual(calls, ['overheat']);
pc.sample({ cpu: 90 }, 30000); assert.equal(calls.length, 1);
pc.sample({ cpu: 50 }, 31000); assert(reactions.includes('cool'));
pc.sample({ cpu: 90 }, 32000); pc.sample({ cpu: 90 }, 47000); assert.equal(calls.length, 1);
pc.sample({ battery: { level: 0.15, charging: false } }, 50000);
pc.sample({ battery: { level: 0.1, charging: false } }, 51000);
pc.sample({ battery: { level: 0.05, charging: false } }, 52000);
assert.equal(calls.filter(k => k === 'drain').length, 2);
pc.sample({ battery: { level: 0.05, charging: true } }, 53000); assert(calls.includes('recharge'));
pc.sample({ online: false }, 60000); pc.sample({ online: true }, 63000); assert(!calls.includes('hurt'));
pc.sample({ online: false }, 64000); pc.sample({ online: false }, 68000); assert(calls.includes('hurt'));
pc.sample({ online: true }, 69000); assert(calls.includes('hop'));
pc.sample({ game: 'Game' }, 70000); pc.sample({ game: 'Game' }, 76000);
assert(!c.stowed); pc.sample({ game: 'Game' }, 78599); assert(!c.stowed);
pc.sample({ game: 'Game' }, 78600); assert(c.stowed);
pc.sample({}, 79000); pc.sample({}, 86999); assert(c.stowed);
pc.sample({}, 87000); assert(!c.stowed);
// A manually stowed pet must stay stowed when a game leaves.
c.stowed = true; pc.sample({ game: 'Game' }, 90000); pc.sample({ game: 'Game' }, 100000);
pc.sample({}, 101000); pc.sample({}, 109000); assert(c.stowed);
c.stowed = false; calls.length = 0;
pc.sample({ cpu: 90, online: false, battery: { level: 0.01, charging: false } }, 2000000, false);
pc.sample({ cpu: 90, online: false }, 2020000, false); assert.deepEqual(calls, []);
pc.device({ kind: 'input', in: true }, 2020000, false); assert.deepEqual(calls, []);
pc.device({ kind: 'drive', in: true }, 2020000); pc.sample({}, 2020001); assert(calls.includes('visit'));
calls.length = 0;
pc.device({ kind: 'controller', in: true }, 2030000); pc.device({ kind: 'controller', in: true }, 2031000);
assert.deepEqual(calls, ['zap']);

assert.equal(steamGame({ pid: 3, class: 'steam_app_2357570', title: 'Overwatch' }), 'Overwatch');
assert.equal(steamGame({ pid: 3, class: 'native', title: 'Native' }, () => 'SteamAppId=123\0'), 'Native');
assert.equal(steamGame({ pid: 3, class: 'kitty', title: 'Terminal' }, () => { throw Error('gone'); }), '');
assert.equal(steamGame({ pid: '../oops' }), '');
assert.equal(device({ ACTION: 'change' }), null);
assert.equal(device({ ACTION: 'add', SUBSYSTEM: 'usb', DEVTYPE: 'usb_interface' }), null);
assert.equal(device({ ACTION: 'add', SUBSYSTEM: 'usb', DEVTYPE: 'usb_device', ID_USB_INTERFACES: ':080650:' }), null);
assert.equal(device({ ACTION: 'add', SUBSYSTEM: 'block', DEVTYPE: 'partition', ID_BUS: 'usb' }), null);
assert.equal(device({ ACTION: 'add', SUBSYSTEM: 'block', DEVTYPE: 'disk', ID_BUS: 'usb' }).kind, 'drive');
assert.equal(device({ ACTION: 'add', SUBSYSTEM: 'usb', DEVTYPE: 'usb_device', ID_MODEL: 'Xbox_Controller' }).kind, 'controller');
assert.equal(deviceBlock('ACTION=add\nSUBSYSTEM=usb\nDEVTYPE=usb_device\nID_MODEL=Headset\nID_USB_INTERFACES=:010100:').kind, 'audio');
console.log('CAPRI_WORLD_PASS');
