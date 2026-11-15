#!/usr/bin/env python3
"""Persistent per-trackpad controls for Hyprland's Lua configuration."""
import hashlib
import json
import math
import subprocess
import sys
import os
from pathlib import Path

from control import CONFIG, run, write

MAIN = CONFIG / 'hypr/hyprland.lua'
LUA = CONFIG / 'hypr/config/serpantinum_trackpad.lua'
SETTINGS = CONFIG / 'hypr/config/serpantinum_trackpad.json'
HOOK = '\n-- Serpantinum addons v2: trackpad\nrequire("config/serpantinum_trackpad")\n'


def touchpads():
    mice = json.loads(run('hyprctl', 'devices', '-j'))['mice']
    names = set()
    # Use udev's touchpad classification, including hardware without "touchpad"
    # in its name. Do not change ordinary mice or TrackPoints.
    for event in Path('/sys/class/input').glob('event*'):
        try:
            props = run('udevadm', 'info', '--query=property', '--path=' + str(event))
            if 'ID_INPUT_TOUCHPAD=1' in props.splitlines():
                name = (event / 'device/name').read_text().strip().lower().replace(' ', '-')
                names.add(name)
        except (OSError, subprocess.CalledProcessError):
            continue
    return [m for m in mice if m['name'] in names]


def revision():
    digest = hashlib.sha256()
    for path in (MAIN, LUA, SETTINGS):
        digest.update(str(path).encode())
        digest.update(b'present' + path.read_bytes() if path.exists() else b'absent')
    return digest.hexdigest()


def status():
    if os.environ.get("NIRI_SOCKET"):
        import niri_trackpad
        return niri_trackpad.status()
    devices = touchpads()
    saved = json.loads(SETTINGS.read_text()) if SETTINGS.exists() else None
    dwt = json.loads(run('hyprctl', 'getoption', 'input:touchpad:disable_while_typing', '-j'))['bool']
    speed = json.loads(run('hyprctl', 'getoption', 'input:sensitivity', '-j'))['float']
    settings = saved or dict(speed=speed,
                            disableWhileTyping=dwt, disableClicksWhileTyping=False)
    return dict(settings=settings, devices=[d['name'] for d in devices],
                revision=revision(), available=bool(devices))


def lua_settings(settings, devices):
    # JSON strings are Lua-compatible for ordinary device names and paths.
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    lines = ['-- Managed by Serpantinum addons v2: trackpad\n']
    for name in devices:
        lines.append('hl.device({ name = %s, sensitivity = %s, disable_while_typing = %s })\n' %
                     (quote(name), settings['speed'], str(settings['disableWhileTyping']).lower()))
    if settings['disableClicksWhileTyping']:
        script = Path(__file__).resolve().with_name('trackpad_guard.lua')
        lines.append('local guard = dofile(%s)\nguard({%s})\n' %
                     (quote(str(script)), ', '.join(map(quote, devices))))
    return ''.join(lines)


def save(payload):
    if os.environ.get("NIRI_SOCKET"):
        import niri_trackpad
        return niri_trackpad.save(payload)
    current = status()
    if not current['available']:
        raise ValueError('No touchpad detected.')
    if payload['revision'] != current['revision']:
        raise ValueError('Trackpad configuration changed outside this editor. Reopen Addons before saving.')
    if payload['devices'] != current['devices']:
        raise ValueError('Connected trackpads changed. Reopen Addons before saving.')
    settings = payload['settings']
    speed = settings['speed']
    if isinstance(speed, bool) or not isinstance(speed, (int, float)) or not math.isfinite(speed) or not -1 <= speed <= 1:
        raise ValueError('Trackpad speed must be between -1 and 1.')
    for key in ('disableWhileTyping', 'disableClicksWhileTyping'):
        if not isinstance(settings[key], bool):
            raise ValueError('Invalid trackpad switch value.')
    settings = {key: settings[key] for key in ('speed', 'disableWhileTyping', 'disableClicksWhileTyping')}
    old = {path: path.read_text() if path.exists() else None for path in (MAIN, LUA, SETTINGS)}
    main = old[MAIN]
    if 'require("config/serpantinum_trackpad")' not in main:
        main = main.rstrip() + '\n' + HOOK
    try:
        write(LUA, lua_settings(settings, current['devices']))
        write(SETTINGS, json.dumps(settings, indent=2) + '\n')
        if main != old[MAIN]:
            write(MAIN, main)
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
    except Exception:
        for path, text in old.items():
            if text is None:
                path.unlink(missing_ok=True)
            else:
                write(path, text)
        run('hyprctl', 'reload')
        raise
    return status()


if __name__ == '__main__':
    try:
        action = sys.argv[1]
        if action == 'status':
            data = status()
        elif action == 'save':
            data = save(json.loads(sys.argv[2]))
        else:
            raise ValueError('Unknown trackpad action')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:
        print(json.dumps(dict(ok=False, error=str(error))))
        sys.exit(1)
