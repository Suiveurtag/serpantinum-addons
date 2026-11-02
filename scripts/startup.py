#!/usr/bin/env python3
"""Commands launched once when the Hyprland session and its shell start."""
import hashlib
import json
import sys

from control import CONFIG, run, write

MAIN = CONFIG / 'hypr/hyprland.lua'
LUA = CONFIG / 'hypr/config/serpantinum_startup.lua'
SETTINGS = CONFIG / 'hypr/config/serpantinum_startup.json'
HOOK = '\n-- Serpantinum addons v2: startup commands\nrequire("config/serpantinum_startup")\n'


def revision():
    return hashlib.sha256(SETTINGS.read_bytes() if SETTINGS.exists() else b'absent').hexdigest()


def status():
    commands = json.loads(SETTINGS.read_text())['commands'] if SETTINGS.exists() else []
    return dict(commands=commands, revision=revision())


def lua(commands):
    # JSON strings without \u escapes are valid Lua string literals.
    body = ''.join('  hl.exec_cmd(%s)\n' % json.dumps(command, ensure_ascii=False) for command in commands)
    return 'hl.on("hyprland.start", function()\n' + body + 'end)\n'


def save(payload):
    if payload['revision'] != revision():
        raise ValueError('Startup commands changed outside this editor. Reload before saving.')
    commands = payload['commands']
    if not isinstance(commands, list) or not all(
            isinstance(command, str) and command.strip() and all(ord(c) >= 32 for c in command) for command in commands):
        raise ValueError('Each startup command must be a single non-empty line.')
    commands = [command.strip() for command in commands]
    old = {path: path.read_text() if path.exists() else None for path in (MAIN, LUA, SETTINGS)}
    main = old[MAIN]
    if 'require("config/serpantinum_startup")' not in main:
        main = main.rstrip() + HOOK
    try:
        write(LUA, lua(commands))
        write(SETTINGS, json.dumps(dict(commands=commands), indent=2, ensure_ascii=False) + '\n')
        if main != old[MAIN]:
            write(MAIN, main)
        # Reload only validates the fragment: hyprland.start fires once per session.
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
            raise ValueError('Unknown startup action')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:
        print(json.dumps(dict(ok=False, error=str(error))))
        sys.exit(1)
