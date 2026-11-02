#!/usr/bin/env python3
"""The dash zoom of the surge scene: the real compositor zoom, centred on Clawd, driven frame by frame by the scene.
stdin: one JSON per line {"f": zoom factor, "x": global px, "y": global px}, or {"close": true}.
The pointer is parked on him (the zoom follows it) and hidden; the zoom, the cursor options and the pointer are restored
on close, EOF or SIGTERM."""
import json
import math
import os
from pathlib import Path
import select
import signal
import socket
import sys


def request(path, command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(str(path))
        client.sendall(command.encode())
        chunks = []
        while chunk := client.recv(4096):
            chunks.append(chunk)
    return b''.join(chunks).decode()


def literal(value):
    return str(value).lower() if isinstance(value, bool) else f'{value:.5f}'


def configure(path, values):
    request(path, 'eval hl.config({cursor={' + ','.join(k + '=' + literal(v) for k, v in values.items()) + '}})')


def warp(path, x, y):
    request(path, 'dispatch hl.dsp.cursor.move({ x = %.1f, y = %.1f })' % (x, y))


def main():
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / os.environ['HYPRLAND_INSTANCE_SIGNATURE'] / '.socket.sock'
    saved = {key: json.loads(request(path, f'j/getoption cursor:{key}'))[kind]
             for key, kind in [('zoom_factor', 'float'), ('zoom_rigid', 'bool'), ('zoom_detached_camera', 'bool'), ('inactive_timeout', 'float')]}
    home = json.loads(request(path, 'j/cursorpos'))
    stopped = False

    def stop(*_):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    last = (None, None, None)
    buffer = b''
    try:
        configure(path, {'zoom_rigid': True, 'zoom_detached_camera': False, 'inactive_timeout': 0.05})
        print(json.dumps({'ready': True}), flush=True)
        while not stopped:
            if not select.select([sys.stdin], [], [], 0.25)[0]:
                continue
            data = os.read(sys.stdin.fileno(), 65536)
            if not data:
                break
            buffer += data
            message = None
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                message = json.loads(line)   # only the newest matters
                if message.get('close'):
                    stopped = True
                    break
            if message and not message.get('close'):
                f, x, y = float(message['f']), float(message['x']), float(message['y'])
                if not math.isfinite(f + x + y):
                    continue
                if last[1] is None or abs(x - last[1]) > 0.5 or abs(y - last[2]) > 0.5:
                    warp(path, x, y)
                if last[0] is None or abs(f - last[0]) > 0.0005:
                    configure(path, {'zoom_factor': max(1.0, min(6.0, f))})
                last = (f, x, y)
    finally:
        try:
            configure(path, saved)
        finally:
            warp(path, home['x'], home['y'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError, RuntimeError) as error:
        print(f'Surge zoom: {error}', file=sys.stderr)
        sys.exit(1)
