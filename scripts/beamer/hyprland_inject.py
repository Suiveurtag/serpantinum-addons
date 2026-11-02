"""Beamer's Wayland injector backed by the user's explicitly started uinput bridge."""
import json
import logging
import os
import socket
import threading

import desktop_portal
import inject_portal as original
import inject_x11
import xkb_x11
from Xlib import X, display

LOG = logging.getLogger(__name__)
_lock = threading.RLock()
_socket = None
_display = None
_keymap = None
_layout = None
_state = inject_x11.KeyState()
_scroll = [0.0, 0.0]


def _send(msg):
    global _socket, _state
    try:
        if _socket is None:
            _socket = socket.socket(socket.AF_UNIX)
            _socket.settimeout(2)
            _socket.connect(os.path.join(os.environ['XDG_RUNTIME_DIR'], 'beamer-addon', 'input.sock'))
        _socket.sendall((json.dumps(msg, separators=(',', ':')) + '\n').encode())
        return True
    except OSError as exc:
        if _socket is not None:
            _socket.close()
            _socket = None
        _state = inject_x11.KeyState()
        LOG.error('Beamer input bridge unavailable: %s', exc)
        if original.on_permission:
            original.on_permission('unavailable', 'Beamer input bridge unavailable: ' + str(exc), True)
        if original.on_problem:
            original.on_problem('Beamer input bridge unavailable: ' + str(exc))
        return False


def _open_keyboard():
    global _display, _keymap, _layout
    if _display is None:
        _display = display.Display()
        _keymap = xkb_x11.Keymap(_display.get_display_name())
        _layout = original.WaylandLayout(_keymap)
    changed = False
    while _display.pending_events():
        event = _display.next_event()
        if event.type == X.MappingNotify and event.request in (X.MappingKeyboard, X.MappingModifier):
            changed = True
    if changed:
        _keymap.reload()
        _layout = original.WaylandLayout(_keymap)
    mask = _display.screen().root.query_pointer().mask
    return (mask >> 13) & 3, mask & (inject_x11.LOCK_MASK | inject_x11.NUM_LOCK_MASK)


def _keys(steps):
    for code, down in original.wayland_steps(steps):
        if not _send({'op': 'key', 'code': code, 'down': down}):
            break


def inject_key(name, down, us=None):
    with _lock:
        try:
            group, locks = _open_keyboard()
            _keys(inject_x11.plan_key(name, down, us, _state, _layout, group, locks))
        except Exception:
            LOG.exception('Could not inject key using XKB')


def inject_text(text):
    with _lock:
        try:
            group, locks = _open_keyboard()
            _keys(inject_x11.plan_text(text, _state, _layout, group, locks))
        except Exception:
            LOG.exception('Could not inject text using XKB')


def move_to(x, y):
    with _lock:
        if _send({'op': 'place', 'x': int(x), 'y': int(y)}):
            desktop_portal.note_position(x, y)


def inject_mouse_move(dx, dy):
    with _lock:
        if _send({'op': 'move', 'x': int(dx), 'y': int(dy)}):
            x, y = desktop_portal.cursor_position()
            desktop_portal.note_position(x + dx, y + dy)


def push(x, y, moves, wanted):
    with _lock:
        if wanted():
            move_to(x, y)
            for dx, dy in moves:
                inject_mouse_move(dx, dy)


def inject_mouse_button(button, down):
    code = original.BUTTONS.get(button)
    if code is not None:
        with _lock:
            _send({'op': 'key', 'code': code, 'down': bool(down)})


def inject_scroll(dy, dx=0., mode='line'):
    with _lock:
        kind, x, y = original.scroll_steps(dy, dx, mode, _scroll)
        # The input protocol uses libei's 120 units per detent and evdev's opposite Y sign.
        if kind == 'pixels':
            x, y = x * 3, y * 3
        _send({'op': 'scroll', 'x': int(x), 'y': -int(y)})


def release_all():
    global _state
    with _lock:
        _send({'op': 'release'})
        _state = inject_x11.KeyState()


def start():
    with _lock:
        ready = _send({'op': 'release'})
        if original.on_permission:
            original.on_permission('ready' if ready else 'unavailable',
                                   '' if ready else 'Beamer input bridge unavailable', not ready)
        if ready:
            desktop_portal.set_mover(lambda x, y: move_to(x, y))


def stop():
    global _socket, _display, _keymap, _layout, _state
    with _lock:
        if _socket:
            _send({'op': 'release'})
            if _socket:
                _socket.close()
                _socket = None
        if _keymap:
            _keymap.close()
        if _display:
            _display.close()
        _display = _keymap = _layout = None
        _state = inject_x11.KeyState()


def install():
    for name in ('inject_key', 'inject_text', 'inject_mouse_move', 'move_to', 'push',
                 'inject_mouse_button', 'inject_scroll', 'release_all', 'start', 'stop'):
        setattr(original, name, globals()[name])
    original.request_again = start
