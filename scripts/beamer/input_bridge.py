#!/usr/bin/env python3
"""Host-side uinput bridge for Beamer. Only clients in this user session may connect."""
import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess

from evdev import UInput, ecodes as e

SOCKET = Path(os.environ['XDG_RUNTIME_DIR']) / 'beamer-addon' / 'input.sock'
BUTTONS = {e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE, e.BTN_SIDE, e.BTN_EXTRA}
KEYS = {value for name, value in e.ecodes.items()
        if name.startswith('KEY_') and name not in ('KEY_RESERVED', 'KEY_MAX', 'KEY_CNT')
        and isinstance(value, int)}


class Input:
    def __init__(self, keyboard, pointer=None):
        self.keyboard = keyboard
        self.pointer = pointer if pointer is not None else keyboard
        self.held = set()
        self.wheel = [0, 0]

    def handle(self, msg):
        op = msg.get('op')
        if op == 'key':
            code, down = msg.get('code'), msg.get('down')
            if type(code) is not int or code not in KEYS | BUTTONS or type(down) is not bool:
                raise ValueError('invalid key')
            if not down and code not in self.held:
                return
            self.held.add(code) if down else self.held.discard(code)
            device = self.pointer if code in BUTTONS else self.keyboard
            device.write(e.EV_KEY, code, int(down))
        elif op == 'move':
            x, y = msg.get('x'), msg.get('y')
            if type(x) is not int or type(y) is not int or max(abs(x), abs(y)) > 32767:
                raise ValueError('invalid motion')
            self.pointer.write(e.EV_REL, e.REL_X, x)
            self.pointer.write(e.EV_REL, e.REL_Y, y)
        elif op == 'scroll':
            x, y = msg.get('x'), msg.get('y')
            if type(x) is not int or type(y) is not int or max(abs(x), abs(y)) > 12000:
                raise ValueError('invalid scroll')
            self.pointer.write(e.EV_REL, e.REL_HWHEEL_HI_RES, x)
            self.pointer.write(e.EV_REL, e.REL_WHEEL_HI_RES, y)
            for axis, value, code in ((0, x, e.REL_HWHEEL), (1, y, e.REL_WHEEL)):
                self.wheel[axis] += value
                clicks = int(self.wheel[axis] / 120)
                self.wheel[axis] -= clicks * 120
                if clicks:
                    self.pointer.write(e.EV_REL, code, clicks)
        elif op == 'place':
            x, y = msg.get('x'), msg.get('y')
            if type(x) is not int or type(y) is not int or max(abs(x), abs(y)) > 100000:
                raise ValueError('invalid position')
            result = subprocess.run(
                ['hyprctl', 'dispatch', f'hl.dsp.cursor.move({{ x = {x}, y = {y} }})'],
                check=True, capture_output=True, text=True, timeout=2)
            # hyprctl may report a dispatcher error on stdout while exiting successfully.
            if result.stdout.strip() != 'ok':
                raise ValueError(f'Hyprland cursor placement failed: {result.stdout.strip()}')
        elif op == 'release':
            self.release()
            return
        else:
            raise ValueError('unknown operation')
        if op == 'key':
            device.syn()
        elif op in ('move', 'scroll'):
            self.pointer.syn()

    def release(self):
        for code in self.held:
            (self.pointer if code in BUTTONS else self.keyboard).write(e.EV_KEY, code, 0)
        self.held.clear()
        self.wheel = [0, 0]
        self.keyboard.syn()
        if self.pointer is not self.keyboard:
            self.pointer.syn()


def serve():
    SOCKET.parent.mkdir(mode=0o700, exist_ok=True)
    st = SOCKET.parent.stat()
    if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
        raise RuntimeError('unsafe socket directory')
    if SOCKET.exists():
        raise RuntimeError('socket already exists; stop the existing bridge first')
    caps = {e.EV_KEY: sorted(BUTTONS), e.EV_REL: [e.REL_X, e.REL_Y,
            e.REL_WHEEL, e.REL_HWHEEL, e.REL_WHEEL_HI_RES, e.REL_HWHEEL_HI_RES]}
    with UInput({e.EV_KEY: sorted(KEYS)}, name='Beamer addon keyboard') as keyboard, \
         UInput(caps, name='Beamer addon pointer') as pointer, socket.socket(socket.AF_UNIX) as server:
        server.bind(str(SOCKET))
        os.chmod(SOCKET, 0o600)
        server.listen(1)
        try:
            while True:
                conn, _ = server.accept()
                input_ = Input(keyboard, pointer)
                try:
                    with conn, conn.makefile('rb') as stream:
                        while line := stream.readline(1025):
                            if len(line) > 1024:
                                break
                            try:
                                input_.handle(json.loads(line))
                            except (ValueError, TypeError, AttributeError, subprocess.SubprocessError):
                                break
                finally:
                    input_.release()
        finally:
            SOCKET.unlink(missing_ok=True)


if __name__ == '__main__':
    def stop(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        serve()
    except KeyboardInterrupt:
        pass
