#!/usr/bin/env python3
"""Connect Clawd to Claude Code / Codex hooks.
Usage: hooks.py <status|install|uninstall> <claude|codex|statusline>  ->  {"ok": true, "data": {...}} | {"ok": false, "error": "..."}
Adds one hook group per event next to whatever is already there (Capri...), backs the file up before every write,
and only ever removes commands that run clawd-hook.js.
statusline: Claude's statusLine runs clawd-status.js (stats relay), wrapping any existing status line command."""
import json
import os
import shlex
import shutil
import sys
from datetime import datetime
from pathlib import Path

MARK = 'clawd-hook.js'
SCRIPT = Path(__file__).resolve().parent/'hooks'/MARK
STATUS_MARK = 'clawd-status.js'
STATUS_SCRIPT = SCRIPT.with_name(STATUS_MARK)
AGENTS = {
    'claude': {
        'file': lambda: Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home()/'.claude')/'settings.json',
        'events': ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'PreCompact', 'SubagentStart', 'SubagentStop', 'Stop', 'StopFailure', 'SessionEnd'],
        'hook': {'async': True, 'timeout': 3},
        'args': '',
    },
    'codex': {
        'file': lambda: Path(os.environ.get('CODEX_HOME') or Path.home()/'.codex')/'hooks.json',
        'events': ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'SubagentStart', 'SubagentStop', 'Stop', 'SessionEnd', 'Interrupt'],
        'hook': {'timeout': 3},  # Codex runs hooks synchronously; the script gives up after 500 ms
        'args': ' --agent codex',
    },
}


def ours(hook):
    return isinstance(hook, dict) and MARK in str(hook.get('command', ''))


def read(file):
    text = file.read_text() if file.is_file() else ''
    try:
        settings = json.loads(text) if text.strip() else {}
    except ValueError as error:
        raise ValueError(f'{file} is not valid JSON ({error}); nothing changed') from None
    hooks = settings.get('hooks', {}) if isinstance(settings, dict) else None
    # Never rewrite a file we do not fully understand.
    if not isinstance(hooks, dict) or any(not isinstance(groups, list) or any(not isinstance(g, dict) or not isinstance(g.get('hooks'), list) for g in groups)
                                          for groups in hooks.values()):
        raise ValueError(f'{file} has an unexpected hooks layout; nothing changed')
    return settings


def status(agent):
    spec = AGENTS[agent]
    file = spec['file']()
    settings = read(file)
    events = [event for event, groups in settings.get('hooks', {}).items() if any(ours(h) for g in groups for h in g['hooks'])]
    return {'file': str(file), 'installed': all(e in events for e in spec['events']), 'events': events}


def configure(agent, install):
    spec = AGENTS[agent]
    file = spec['file']()
    settings = read(file)
    before = json.dumps(settings, sort_keys=True)
    hooks = settings.setdefault('hooks', {})
    for event in list(hooks):
        # Drop only our command, even inside a group shared with another hook.
        kept = []
        for group in hooks[event]:
            mine = [h for h in group['hooks'] if not ours(h)]
            if len(mine) == len(group['hooks']): kept.append(group)
            elif mine: kept.append({**group, 'hooks': mine})
        if kept: hooks[event] = kept
        else: del hooks[event]
    if install:
        command = 'node ' + shlex.quote(str(SCRIPT)) + spec['args']
        for event in spec['events']:
            hooks.setdefault(event, []).append({'hooks': [{'type': 'command', 'command': command, **spec['hook']}]})
    if not hooks: del settings['hooks']
    changed = write(file, settings, before, install)
    return {**status(agent), 'changed': changed}


def write(file, settings, before, create):
    changed = json.dumps(settings, sort_keys=True) != before
    if changed and (create or file.is_file()):
        file.parent.mkdir(parents=True, exist_ok=True)
        if file.is_file():
            shutil.copy2(file, file.with_name(f'{file.name}.clawd-backup-{datetime.now().strftime("%Y-%m-%dT%H-%M-%S-%f")}'))
        tmp = file.with_name(file.name + '.clawd-tmp')
        tmp.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + '\n')
        if file.is_file(): shutil.copymode(file, tmp)
        os.replace(tmp, file)
    return changed


def wrapped(line):
    # (ours, original command or None) for Claude's statusLine; ours is 'node <script> [-- <original>]'.
    command = line.get('command') if isinstance(line, dict) else None
    if not isinstance(command, str) or STATUS_MARK not in command: return False, None
    try: words = shlex.split(command)
    except ValueError: words = []
    if len(words) == 2: return True, None
    if len(words) == 4 and words[2] == '--': return True, words[3]
    raise ValueError(f'unexpected Clawd statusLine command {command!r}; nothing changed')


def statusline_status():
    file = AGENTS['claude']['file']()
    ours, original = wrapped(read(file).get('statusLine'))
    return {'file': str(file), 'installed': ours, 'wrapped': original}


def statusline(install):
    file = AGENTS['claude']['file']()
    settings = read(file)
    before = json.dumps(settings, sort_keys=True)
    line = settings.get('statusLine')
    ours, original = wrapped(line)
    if install:
        if not ours and line is not None and not (isinstance(line, dict) and isinstance(line.get('command'), str)):
            raise ValueError(f'{file} has an unexpected statusLine; nothing changed')
        if not ours and line is not None: original = line['command']
        command = 'node ' + shlex.quote(str(STATUS_SCRIPT)) + ('' if original is None else ' -- ' + shlex.quote(original))
        settings['statusLine'] = {**line, 'command': command} if line is not None else {'type': 'command', 'command': command, 'padding': 0}
    elif ours and original is not None: settings['statusLine'] = {**line, 'command': original}
    elif ours: del settings['statusLine']
    changed = write(file, settings, before, install)
    return {**statusline_status(), 'changed': changed}


def main(argv):
    try:
        if len(argv) != 2 or argv[0] not in ('status', 'install', 'uninstall') or argv[1] not in (*AGENTS, 'statusline'):
            raise ValueError('usage: hooks.py <status|install|uninstall> <claude|codex|statusline>')
        action, target = argv
        if target == 'statusline': data = statusline_status() if action == 'status' else statusline(action == 'install')
        else: data = status(target) if action == 'status' else configure(target, action == 'install')
        print(json.dumps({'ok': True, 'data': data}))
        return 0
    except (OSError, ValueError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
