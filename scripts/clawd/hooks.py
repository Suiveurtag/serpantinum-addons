#!/usr/bin/env python3
"""Connect Clawd to Claude Code, Codex, OpenCode and Hermes session hooks.
Usage: hooks.py <status|install|uninstall> <claude|codex|opencode|hermes|statusline>  ->  {"ok": true, "data": {...}} | {"ok": false, "error": "..."}
Adds one hook group per event next to whatever is already there (Capri...), backs the file up before every write,
and only ever removes commands that run clawd-hook.js.
statusline: Claude's statusLine runs clawd-status.js (stats relay), wrapping any existing status line command."""
import json
import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

MARK = 'clawd-hook.js'
SCRIPT = Path(__file__).resolve().parent/'hooks'/MARK
STATUS_MARK = 'clawd-status.js'
STATUS_SCRIPT = SCRIPT.with_name(STATUS_MARK)
OPENCODE_SCRIPT = SCRIPT.with_name('clawd-opencode-plugin.js')
HERMES_PLUGIN = SCRIPT.parent/'hermes-plugin'
HERMES_PLUGIN_NAME = 'clawd-session-watch'
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
HOOKS = (*AGENTS, 'opencode', 'hermes')


def backup(file):
    if file.exists():
        shutil.copy2(file, file.with_name(f'{file.name}.clawd-backup-{datetime.now().strftime("%Y-%m-%dT%H-%M-%S-%f")}'))


def configure_opencode(install):
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home()/'.config')/'opencode'
    link = config/'plugins'/'clawd-session-watch.js'
    file = link.resolve() if link.is_symlink() else link
    expected = OPENCODE_SCRIPT.read_bytes()
    changed = False
    if install:
        if link.exists() and (not link.is_file() or b'Clawd session watch' not in link.read_bytes()):
            raise ValueError(f'{link} already belongs to another plugin; nothing changed')
        if not file.is_file() or file.read_bytes() != expected:
            file.parent.mkdir(parents=True, exist_ok=True)
            backup(file)
            tmp = file.with_name(file.name + '.clawd-tmp')
            tmp.write_bytes(expected)
            os.replace(tmp, file)
            changed = True
    elif link.exists():
        if not link.is_file() or b'Clawd session watch' not in link.read_bytes():
            raise ValueError(f'{link} is not Clawd-owned; nothing changed')
        backup(link)
        link.unlink()
        changed = True
        try: link.parent.rmdir()
        except OSError: pass
    return {**status_opencode(), 'changed': changed}


def status_opencode():
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home()/'.config')/'opencode'
    file = config/'plugins'/'clawd-session-watch.js'
    return {'file': str(file), 'installed': file.is_file() and file.read_bytes() == OPENCODE_SCRIPT.read_bytes()}


def hermes_home():
    configured = os.environ.get('HERMES_HOME')
    if configured:
        return Path(configured).expanduser()
    command = shutil.which('hermes')
    if command:
        try:
            result = subprocess.run([command, 'config', 'path'], capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired:
            raise ValueError('Hermes CLI did not respond') from None
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'Hermes config path lookup failed')
        config = Path(result.stdout.strip()).expanduser()
        if not config.is_absolute() or config.name != 'config.yaml':
            raise ValueError('Hermes returned an invalid config path')
        return config.parent
    return Path.home()/'.hermes'


def hermes_enabled():
    command = shutil.which('hermes')
    if not command:
        return False   # no CLI: the plugin cannot be enabled (install reports this separately)
    try:
        result = subprocess.run([command, 'plugins', 'list', '--json'], capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        raise ValueError('Hermes CLI did not respond') from None
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'Hermes plugin status failed')
    try:
        plugins = json.loads(result.stdout)
    except ValueError:
        raise ValueError('Hermes returned an invalid plugin list') from None
    return any(p.get('name') == HERMES_PLUGIN_NAME and p.get('status') == 'enabled' for p in plugins if isinstance(p, dict))


def status_hermes():
    dest = hermes_home()/'plugins'/HERMES_PLUGIN_NAME
    sources = {p.name: p for p in HERMES_PLUGIN.iterdir() if p.is_file()} if HERMES_PLUGIN.is_dir() else {}
    installed = bool(sources) and dest.is_dir() and all((dest/name).is_file() and (dest/name).read_bytes() == source.read_bytes()
                                                        for name, source in sources.items()) and all(
                                                            p.name in {*sources, '__pycache__'} for p in dest.iterdir())
    enabled = hermes_enabled()
    return {'file': str(dest), 'installed': installed and enabled, 'enabled': enabled}


def remove_hermes_files(dest):
    if not dest.exists(): return False
    manifest = dest/'plugin.yaml'
    if not dest.is_dir() or not manifest.is_file() or b'Clawd session watch' not in manifest.read_bytes():
        raise ValueError(f'{dest} is not Clawd-owned; nothing changed')
    sources = {p.name: p for p in HERMES_PLUGIN.iterdir() if p.is_file()} if HERMES_PLUGIN.is_dir() else {}
    changed = False
    for source in sources.values():
        target = dest/source.name
        if target.is_file():
            backup(target)
            target.unlink()
            changed = True
    cache = dest/'__pycache__'
    if cache.is_dir(): shutil.rmtree(cache)
    try: dest.rmdir()
    except OSError: pass
    return changed


def configure_hermes(install):
    home = hermes_home()
    dest = home/'plugins'/HERMES_PLUGIN_NAME
    changed = False
    command = shutil.which('hermes')
    if install and not command:
        raise ValueError('Hermes CLI not found')
    if not install and not dest.exists():
        # Nothing of ours to remove: do not wait for a possibly broken CLI.
        return {'file': str(dest), 'installed': False, 'enabled': False, 'changed': False}
    if not install and not command:
        changed = remove_hermes_files(dest)
        return {'file': str(dest), 'installed': False, 'enabled': False, 'changed': changed}
    if install:
        sources = {p.name: p for p in HERMES_PLUGIN.iterdir() if p.is_file()}
        if not sources:
            raise ValueError(f'{HERMES_PLUGIN} is missing its plugin files')
        if dest.exists():
            owned = (dest/'plugin.yaml').is_file() and b'Clawd session watch' in (dest/'plugin.yaml').read_bytes()
            if not dest.is_dir() or any(p.name not in {*sources, '__pycache__'} for p in dest.iterdir()) or (not owned and any(
                    (dest/name).exists() and (not (dest/name).is_file() or (dest/name).read_bytes() != source.read_bytes())
                    for name, source in sources.items())):
                raise ValueError(f'{dest} already contains an unrelated plugin; nothing changed')
        dest.mkdir(parents=True, exist_ok=True)
        for source in sorted(sources.values(), key=lambda item: (item.name != 'plugin.yaml', item.name)):
            target = dest/source.name
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                backup(target)
                shutil.copy2(source, target)
                changed = True
        if not hermes_enabled():
            result = subprocess.run([command, 'plugins', 'enable', HERMES_PLUGIN_NAME, '--no-allow-tool-override'],
                                    capture_output=True, text=True, timeout=30)
            if result.returncode:
                raise ValueError(result.stderr.strip() or result.stdout.strip() or 'Hermes plugin enable failed')
            changed = True
    else:
        if dest.exists():
            manifest = dest/'plugin.yaml'
            if not dest.is_dir() or not manifest.is_file() or b'Clawd session watch' not in manifest.read_bytes():
                raise ValueError(f'{dest} is not Clawd-owned; nothing changed')
        if hermes_enabled():
            result = subprocess.run([command, 'plugins', 'disable', HERMES_PLUGIN_NAME], capture_output=True, text=True, timeout=30)
            if result.returncode:
                raise ValueError(result.stderr.strip() or result.stdout.strip() or 'Hermes plugin disable failed')
            changed = True
        changed = remove_hermes_files(dest) or changed
    return {**status_hermes(), 'changed': changed}


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
    if agent == 'opencode': return status_opencode()
    if agent == 'hermes': return status_hermes()
    spec = AGENTS[agent]
    file = spec['file']()
    settings = read(file)
    events = [event for event, groups in settings.get('hooks', {}).items() if any(ours(h) for g in groups for h in g['hooks'])]
    return {'file': str(file), 'installed': all(e in events for e in spec['events']), 'events': events}


def configure(agent, install):
    if agent == 'opencode': return configure_opencode(install)
    if agent == 'hermes': return configure_hermes(install)
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
    file = file.resolve() if file.is_symlink() else file
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
        if len(argv) != 2 or argv[0] not in ('status', 'install', 'uninstall') or argv[1] not in (*HOOKS, 'statusline'):
            raise ValueError('usage: hooks.py <status|install|uninstall> <claude|codex|opencode|hermes|statusline>')
        action, target = argv
        if target == 'statusline': data = statusline_status() if action == 'status' else statusline(action == 'install')
        else: data = status(target) if action == 'status' else configure(target, action == 'install')
        print(json.dumps({'ok': True, 'data': data}))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
