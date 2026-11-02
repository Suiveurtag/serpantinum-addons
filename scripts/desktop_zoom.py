#!/usr/bin/env python3
"""Animate live compositor zoom; restore the session on close, EOF or SIGTERM."""
import json
import math
import os
from pathlib import Path
import select
import signal
import socket
import sys
import time


def request(path, command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(str(path))
        client.sendall(command.encode())
        chunks = []
        while chunk := client.recv(4096):
            chunks.append(chunk)
    return b''.join(chunks).decode()


def clamp(value):
    value = float(value)
    if not math.isfinite(value):
        raise ValueError('Invalid zoom factor')
    return max(1.0, min(6.0, value))


def configure(path, sections):
    def literal(value):
        if isinstance(value, bool):
            return str(value).lower()
        return str(value) if isinstance(value, int) else f'{value:.5f}'
    fields = ','.join(section + '={' + ','.join(key + '=' + literal(value) for key, value in values.items()) + '}'
                      for section, values in sections.items())
    reply = request(path, 'eval hl.config({' + fields + '})')
    if reply.strip() != 'ok':
        raise RuntimeError(reply)


def scroll(path, enabled):
    # The keybinds.lua scroll binds consume the wheel, so they only run while zoom is open.
    reply = request(path, 'eval for _, bind in ipairs(serpantinumDesktopZoomScroll or {}) do bind:set_enabled('
                    + str(enabled).lower() + ') end')
    if reply.strip() != 'ok':
        raise RuntimeError(reply)


def main():
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / os.environ['HYPRLAND_INSTANCE_SIGNATURE'] / '.socket.sock'
    saved = {'cursor': {}, 'binds': {}}
    for section, key, kind in [('cursor', 'zoom_factor', 'float'), ('cursor', 'zoom_rigid', 'bool'),
                               ('cursor', 'zoom_detached_camera', 'bool'), ('binds', 'scroll_event_delay', 'int')]:
        saved[section][key] = json.loads(request(path, f'j/getoption {section}:{key}'))[kind]
    stopped = False

    def stop(*_):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    current = target = saved['cursor']['zoom_factor']
    last = time.monotonic()
    closing = False
    buffer = b''
    try:
        # Hyprland ignores wheel binds for 300 ms after each one by default, and those ticks scroll the app instead.
        configure(path, {'cursor': {'zoom_rigid': True, 'zoom_detached_camera': False}, 'binds': {'scroll_event_delay': 0}})
        scroll(path, True)
        point = json.loads(request(path, 'j/cursorpos'))
        print(json.dumps({'ready': True, 'factor': current, 'x': point['x'], 'y': point['y']}), flush=True)
        while not stopped:
            if select.select([sys.stdin], [], [], 1 / 120)[0]:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data:
                    break
                buffer += data
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    message = json.loads(line)
                    closing = message.get('close', False)
                    target = saved['cursor']['zoom_factor'] if closing else clamp(message['factor'])
            now = time.monotonic()
            # Exponential glide: bursts of wheel ticks blend into one motion instead of restarting a curve.
            value = target + (current - target) * math.exp(-(now - last) / 0.07)
            last = now
            if abs(target - value) < 0.0005:
                value = target
            if abs(value - current) > 0.00001:
                configure(path, {'cursor': {'zoom_factor': value}})
                current = value
                print(json.dumps({'factor': current}), flush=True)
            if closing and value == target:
                break
    finally:
        try:
            scroll(path, False)
        finally:
            configure(path, saved)


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError, RuntimeError) as error:
        print(f'Desktop zoom: {error}', file=sys.stderr)
        sys.exit(1)
