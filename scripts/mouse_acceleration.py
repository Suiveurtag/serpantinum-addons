#!/usr/bin/env python3
"""Persistent global mouse acceleration toggle for Hyprland."""
import hashlib
import json
import sys
import niri_config

from control import CONFIG, run, write

MAIN = CONFIG / 'hypr/hyprland.lua'
LUA = CONFIG / 'hypr/config/serpantinum_mouse_acceleration.lua'
SETTINGS = CONFIG / 'hypr/config/serpantinum_mouse_acceleration.json'
HOOK = '\n-- Serpantinum addons v2: mouse acceleration\nrequire("config/serpantinum_mouse_acceleration")\n'


def profile():
    if niri_config.active():
        from niri_ipc import addon
        return addon('snapshot')['input']['mouseProfile']
    value = json.loads(run('hyprctl', 'getoption', 'input:accel_profile', '-j'))
    return value.get('str', '')


def revision():
    if niri_config.active():
        return niri_config.revision()
    digest = hashlib.sha256()
    for path in (MAIN, LUA, SETTINGS):
        digest.update(str(path).encode())
        digest.update(b'present' + path.read_bytes() if path.exists() else b'absent')
    digest.update(profile().encode())
    return digest.hexdigest()


def status():
    current = profile()
    return dict(enabled=current != 'flat', profile=current, revision=revision())


def save(payload):
    current = status()
    if payload['revision'] != current['revision']:
        raise ValueError('Mouse acceleration changed outside this editor. Reopen Addons before saving.')
    enabled = payload['enabled']
    if not isinstance(enabled, bool):
        raise ValueError('Invalid mouse acceleration value.')

    target_profile = 'adaptive' if enabled else 'flat'
    if niri_config.active():
        niri_config.update("mouse", niri_config.input_fragment("mouse", {"accel-profile": json.dumps(target_profile)}), verify=lambda: profile() == target_profile,
                           extra={SETTINGS: json.dumps(dict(enabled=enabled, profile=target_profile), indent=2) + "\n"})
        return status()
    old = {path: path.read_text() if path.exists() else None for path in (MAIN, LUA, SETTINGS)}
    main = old[MAIN]
    if 'require("config/serpantinum_mouse_acceleration")' not in main:
        main = main.rstrip() + HOOK
    try:
        write(LUA, 'hl.config({ input = { accel_profile = %s } })\n' % json.dumps(target_profile))
        write(SETTINGS, json.dumps(dict(enabled=enabled, profile=target_profile), indent=2) + '\n')
        if main != old[MAIN]:
            write(MAIN, main)
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
        applied_profile = profile()
        if applied_profile != target_profile:
            raise ValueError('Hyprland kept the %s acceleration profile.' % applied_profile)
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
            raise ValueError('Unknown mouse acceleration action')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:
        print(json.dumps(dict(ok=False, error=str(error))))
        sys.exit(1)
