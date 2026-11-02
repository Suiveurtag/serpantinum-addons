// Hyprland supplies global logical pixels; the body and effects use overlay-local pixels.
export function monitors(screens, native) {
  return screens.map(s => {
    const m = native.find(m => m.name === s.name) || {};
    const ipc = m.lastIpcObject || {};
    return { id: s.name, x: m.x ?? s.x, y: m.y ?? s.y, w: s.width, h: s.height,
      floor: s.height - Math.max(0, (ipc.reserved || [0, 0, 0, 0])[3]),
      workspace: m.activeWorkspace ? m.activeWorkspace.id : null,
      special: ipc.specialWorkspace ? ipc.specialWorkspace.id : 0 };
  });
}

export function windows(clients, displays, here, foreground) {
  if (!here) return { fg: 0, wins: [] };
  const visible = clients.filter(c => {
    if (!c.at || !c.size || c.hidden || c.mapped === false || c.minimized) return false;
    const workspace = c.workspace ? c.workspace.id : null;
    const shown = c.pinned || displays.some(d => workspace === d.workspace || (d.special && workspace === d.special));
    return shown && c.at[0] < here.x + here.w && c.at[0] + c.size[0] > here.x
      && c.at[1] < here.y + here.h && c.at[1] + c.size[1] > here.y;
  });
  visible.sort((a, b) => {
    // Focus history approximates floating stacking; pinned/floating surfaces cover tiles.
    const layer = c => c.fullscreen ? 2 : c.floating || c.pinned ? 1 : 0;
    const focus = c => c.focusHistoryID >= 0 ? c.focusHistoryID : Infinity;
    return layer(b) - layer(a) || focus(a) - focus(b);
  });
  return { fg: foreground || 0, wins: visible.map(c => ({ id: c.address,
    x: c.at[0] - here.x, y: c.at[1] - here.y, w: c.size[0], h: c.size[1],
    max: !!(c.fullscreen || c.maximized) })) };
}

export function beyond(displays, here, side, y) {
  if (!here) return null;
  const gy = here.y + y;
  return displays.find(d => d.id !== here.id && gy >= d.y && gy < d.y + d.h
    && (side > 0 ? Math.abs(d.x - here.x - here.w) <= 2 : Math.abs(d.x + d.w - here.x) <= 2)) || null;
}

export function cursor(displays, here, p) {
  if (!p || !here) return null;
  const screen = displays.find(d => p.x >= d.x && p.x < d.x + d.w && p.y >= d.y && p.y < d.y + d.h);
  return { x: p.x - here.x, y: p.y - here.y, display: screen ? screen.id : null, inside: !!screen && screen.id === here.id };
}

// Subtract every cover from the visible pieces. Unlike even-odd clipping, overlapping covers
// remain holes. One path and one draw also preserve the effect's random drawing and alpha.
export function uncovered(rect, covers) {
  let pieces = [rect];
  for (const c of covers) {
    const next = [];
    for (const r of pieces) {
      const x = Math.max(r.x, c.x), y = Math.max(r.y, c.y);
      const right = Math.min(r.x + r.w, c.x + c.w), bottom = Math.min(r.y + r.h, c.y + c.h);
      if (right <= x || bottom <= y) { next.push(r); continue; }
      if (y > r.y) next.push({ x: r.x, y: r.y, w: r.w, h: y - r.y });
      if (bottom < r.y + r.h) next.push({ x: r.x, y: bottom, w: r.w, h: r.y + r.h - bottom });
      if (x > r.x) next.push({ x: r.x, y, w: x - r.x, h: bottom - y });
      if (right < r.x + r.w) next.push({ x: right, y, w: r.x + r.w - right, h: bottom - y });
    }
    pieces = next;
  }
  return pieces;
}

export function device(properties) {
  const p = properties;
  if (!['add', 'remove'].includes(p.ACTION)) return null;
  const drive = p.SUBSYSTEM === 'block' && p.DEVTYPE === 'disk' && (p.ID_BUS === 'usb' || /\/usb\d+\//.test(p.DEVPATH || ''));
  if (!drive && !(p.SUBSYSTEM === 'usb' && p.DEVTYPE === 'usb_device')) return null;
  // USB mass-storage gets one reaction when its disk appears, not another for the parent USB node.
  if (!drive && (p.ID_USB_DRIVER === 'usb-storage' || p.ID_USB_INTERFACES?.includes(':080'))) return null;
  const name = (p.ID_MODEL_FROM_DATABASE || p.ID_MODEL || p.NAME || p.PRODUCT || 'USB device').split('_').join(' ');
  const cls = p.ID_USB_INTERFACES || '';
  const kind = drive ? 'drive' : /controller|gamepad|xbox|dualsense|dualshock|joy.con/i.test(name) ? 'controller'
    : /phone|iphone|android|samsung|pixel|galaxy/i.test(name) ? 'phone'
    : /:01/.test(cls) ? 'audio' : /:0e/.test(cls) ? 'camera' : /:03/.test(cls) ? 'input' : 'device';
  return { in: p.ACTION === 'add', kind, name, id: p.DEVNAME || p.DEVPATH || '' };
}

export function deviceBlock(block) {
  const props = {};
  for (const line of block.split('\n')) {
    const eq = line.indexOf('=');
    if (eq > 0) props[line.slice(0, eq)] = line.slice(eq + 1);
  }
  return device(props);
}
