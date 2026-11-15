"""Animate the local Niri compositor's magnifier and restore it on exit."""
import json
import math
import os
import select
import signal
import sys
import time
from niri_ipc import addon


def main():
    capabilities = addon('capabilities')
    if not capabilities.get('zoom'):
        raise RuntimeError('This Niri build does not provide the Serpantinum zoom extension')
    state = addon('snapshot')
    original = current = target = state['zoomFactor']
    scroll = state['scrollSteps']
    stopped = False
    closing = False
    buffer = b''
    last = time.monotonic()
    def stop(*_):
        nonlocal stopped
        stopped = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(json.dumps(dict(ready=True, factor=current, **state['pointer'])), flush=True)
    try:
        while not stopped:
            if select.select([sys.stdin], [], [], 1 / 60)[0]:
                chunk = os.read(sys.stdin.fileno(), 4096)
                if not chunk:
                    break
                buffer += chunk
                if len(buffer) > 65536:
                    raise ValueError('Oversized zoom command')
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    message = json.loads(line)
                    closing = bool(message.get('close'))
                    value = original if closing else float(message['factor'])
                    if not math.isfinite(value):
                        raise ValueError('Invalid zoom factor')
                    target = max(1., min(6., value))
            now = time.monotonic()
            value = target + (current - target) * math.exp(-(now - last) / .07)
            last = now
            if abs(target - value) < .0005:
                value = target
            response = addon('zoom', factor=value, scroll=not closing)
            current = value
            delta = response['scrollSteps'] - scroll
            scroll = response['scrollSteps']
            if delta and not closing:
                target = max(1., min(6., target * 1.15 ** max(-20, min(20, delta))))
                if target <= 1.:
                    closing = True
                    target = original
            print(json.dumps(dict(factor=current, targetFactor=target)), flush=True)
            if closing and current == target:
                break
    finally:
        addon('zoom', factor=original)
