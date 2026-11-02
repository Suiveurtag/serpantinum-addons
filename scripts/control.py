#!/usr/bin/env python3
"""Narrow, atomic Hyprland edits for the native Guide tabs."""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'serpantinum-addons-v2'


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        STATE.mkdir(parents=True, exist_ok=True)
        (STATE / (path.name + '.' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))).write_bytes(path.read_bytes())
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    with os.fdopen(fd, 'w') as f:
        f.write(text)
    os.replace(name, path)


def keybinds():
    path = CONFIG / 'hypr/config/keybinds.lua'
    text = path.read_text()
    rows = []
    # Change only the first argument. Dispatcher tables, flags and loops stay intact.
    pattern = re.compile(r'hl\.bind\((mainMod\s*\.\.\s*)?("(?:\\.|[^"\\])*")\s*,\s*(.*)')
    for number, line in enumerate(text.splitlines()):
        m = pattern.search(line)
        if not m:
            continue
        chord = ('SUPER' if m[1] else '') + json.loads(m[2])
        action = m[3].strip()
        command_match = re.search(r'hl\.dsp\.exec_cmd\(("(?:\\.|[^"\\])*")', action)
        command = json.loads(command_match[1]) if command_match else None
        label = command if command is not None else action.split('(')[0].replace('hl.dsp.', '').replace('.', ' ').title()
        rows.append(dict(line=number, key=chord, action=label, command=command, original=line))
    return dict(revision=hashlib.sha256(text.encode()).hexdigest(), rows=rows)


def save_keys(payload):
    path = CONFIG / 'hypr/config/keybinds.lua'
    old = path.read_text()
    if hashlib.sha256(old.encode()).hexdigest() != payload['revision']:
        raise ValueError('Bindings changed outside this editor. Reload before saving.')
    lines = old.splitlines(keepends=True)
    source_rows = {r['line']: r for r in keybinds()['rows']}
    seen = set()
    edited = {}
    additions = []
    for row in payload['rows']:
        chord = row['key'].strip()
        if not chord or any(ord(c) < 32 for c in chord):
            raise ValueError('Empty or invalid shortcut')
        normalized = re.sub(r'\s+', '', chord).upper()
        if normalized in seen:
            raise ValueError('Duplicate shortcut: ' + chord)
        seen.add(normalized)
        index = int(row['line'])
        if index == -1:
            command = str(row.get('command', '')).strip()
            if not command: raise ValueError('New shortcut needs a command')
            additions.append('hl.bind(' + json.dumps(chord, ensure_ascii=False) + ', hl.dsp.exec_cmd(' + json.dumps(command, ensure_ascii=False) + '))\n')
            continue
        if index not in source_rows or lines[index].rstrip('\n') != row['original']:
            raise ValueError('Binding source changed')
        prefix = re.search(r'hl\.bind\((mainMod\s*\.\.\s*)?("(?:\\.|[^"\\])*")(?=\s*,)', lines[index])
        if not prefix: raise ValueError('Unsupported binding')
        replacement = 'hl.bind(' + json.dumps(chord, ensure_ascii=False)
        line = lines[index][:prefix.start()] + replacement + lines[index][prefix.end():]
        original_command = source_rows[index]['command']
        if original_command is not None:
            command = str(row.get('command', original_command))
            if not command.strip() or any(ord(c) < 32 for c in command): raise ValueError('Invalid command')
            match = re.search(r'hl\.dsp\.exec_cmd\(("(?:\\.|[^"\\])*")', line)
            line = line[:match.start(1)] + json.dumps(command, ensure_ascii=False) + line[match.end(1):]
        edited[index] = line
    # Only delete managed literal bindings, never generated workspace loops.
    lines = [edited.get(i, line) for i, line in enumerate(lines) if i not in source_rows or i in edited]
    if additions:
        lines.append('\n-- Custom shortcuts from Serpantinum addons v2\n')
        lines.extend(additions)
    write(path, ''.join(lines))
    try:
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
    except Exception:
        write(path, old)
        run('hyprctl', 'reload')
        raise
    return keybinds()


def monitors():
    return json.loads(run('hyprctl', 'monitors', '-j'))


def save_monitors(rows):
    current = {m['name']: m for m in monitors()}
    if {r['name'] for r in rows} != set(current):
        raise ValueError('Connected monitors changed. Reload before applying.')
    lines = ['-- Serpantinum addons v2: monitor layout\n']
    for row in rows:
        mon = current[row['name']]
        mode = row['mode']
        if mode not in mon.get('availableModes', []):
            raise ValueError('Unsupported display mode: ' + mode)
        x, y = int(row['x']), int(row['y'])
        transform = int(row['transform'])
        if transform not in range(8):
            raise ValueError('Invalid rotation')
        scale = float(row.get('scale', mon['scale']))
        if not 0.25 <= scale <= 4:
            raise ValueError('Invalid scale')
        lines.append('hl.monitor({ output = %s, mode = %s, position = %s, scale = %s, transform = %s })\n' % (json.dumps(row['name']), json.dumps(mode.replace('Hz', '')), json.dumps(f'{x}x{y}'), scale, transform))
    path = CONFIG / 'hypr/config/monitors.lua'
    old = path.read_text()
    write(path, ''.join(lines))
    try:
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
    except Exception:
        write(path, old)
        run('hyprctl', 'reload')
        raise
    return monitors()


def keyboard_layouts():
    path = CONFIG / 'hypr/config/settings.lua'
    text = path.read_text()
    setting = re.compile(r'(?m)^([ \t]*kb_layout[ \t]*=[ \t]*)(["\'])([^"\'\r\n]*)\2([ \t]*,?[ \t]*(?:--.*)?)$')
    matches = list(setting.finditer(text))
    if len(matches) != 1:
        raise ValueError('Could not find exactly one kb_layout setting in settings.lua')

    layouts_path = Path('/usr/share/X11/xkb/rules/base.lst')
    if not layouts_path.is_file():
        layouts_path = Path('/usr/share/X11/xkb/rules/evdev.lst')
    if not layouts_path.is_file():
        raise ValueError('XKB layout list is unavailable')

    layouts = []
    in_layouts = False
    for line in layouts_path.read_text().splitlines():
        if line.startswith('!'):
            in_layouts = line[1:].strip() == 'layout'
        elif in_layouts:
            match = re.match(r'^\s*([a-zA-Z0-9_+-]+)\s+(.+?)\s*$', line)
            if match:
                layouts.append({'code': match[1], 'name': match[2]})

    if not layouts:
        raise ValueError('No XKB layouts were found')
    layouts.sort(key=lambda item: (item['name'].casefold(), item['code']))
    selected = list(dict.fromkeys(code.strip() for code in matches[0][3].split(',') if code.strip()))
    if not selected:
        raise ValueError('At least one keyboard layout must be selected')
    available = {layout['code'] for layout in layouts}
    for code in selected:
        if code not in available:
            layouts.insert(0, {'code': code, 'name': 'Current layout'})
    return {
        'selected': selected,
        'layouts': layouts,
        'revision': hashlib.sha256(text.encode()).hexdigest(),
    }


def save_keyboard_layout(payload):
    path = CONFIG / 'hypr/config/settings.lua'
    old = path.read_text()
    revision = hashlib.sha256(old.encode()).hexdigest()
    if revision != payload['revision']:
        raise ValueError('Keyboard settings changed outside this editor. Reload before applying.')

    setting = re.compile(r'(?m)^([ \t]*kb_layout[ \t]*=[ \t]*)(["\'])([^"\'\r\n]*)\2([ \t]*,?[ \t]*(?:--.*)?)$')
    matches = list(setting.finditer(old))
    if len(matches) != 1:
        raise ValueError('Could not find exactly one kb_layout setting in settings.lua')
    match = matches[0]
    selected = payload.get('layouts')
    if not isinstance(selected, list) or not selected or any(not isinstance(code, str) or not code or code != code.strip() or ',' in code for code in selected):
        raise ValueError('Select at least one valid keyboard layout')
    if len(selected) != len(set(selected)):
        raise ValueError('A keyboard layout can only be added once')
    available = {item['code'] for item in keyboard_layouts()['layouts']}
    if any(code not in available for code in selected):
        raise ValueError('Unsupported keyboard layout')

    layout_line = match[1] + match[2] + ','.join(selected) + match[2] + match[4]
    updated = old[:match.start()] + layout_line + old[match.end():]
    option_setting = re.compile(r'(?m)^([ \t]*kb_options[ \t]*=[ \t]*)(["\'])([^"\'\r\n]*)\2([ \t]*,?[ \t]*(?:--.*)?)$')
    option_matches = list(option_setting.finditer(updated))
    if len(option_matches) > 1:
        raise ValueError('Could not find exactly one kb_options setting in settings.lua')
    needs_toggle = len(selected) > 1
    if option_matches:
        option = option_matches[0]
        options = [value.strip() for value in option[3].split(',') if value.strip() and value.strip() != 'grp:alt_shift_toggle']
        if needs_toggle:
            options.append('grp:alt_shift_toggle')
        option_line = option[1] + option[2] + ','.join(options) + option[2] + option[4]
        updated = updated[:option.start()] + option_line + updated[option.end():]
    elif needs_toggle:
        if re.search(r'(?m)^[ \t]*kb_options[ \t]*=', updated):
            raise ValueError('Unsupported kb_options setting in settings.lua')
        layout_match = setting.search(updated)
        if ',' not in layout_match[4]:
            # The layout line was the last table field. Adding a field after it needs a comma.
            fixed = layout_match[1] + layout_match[2] + layout_match[3] + layout_match[2] + ',' + layout_match[4]
            updated = updated[:layout_match.start()] + fixed + updated[layout_match.end():]
            layout_match = setting.search(updated)
        newline = '\r\n' if '\r\n' in updated else '\n'
        indent = re.match(r'[ \t]*', layout_match[1]).group(0)
        updated = updated[:layout_match.end()] + newline + indent + 'kb_options = "grp:alt_shift_toggle",' + updated[layout_match.end():]

    write(path, updated)
    try:
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
    except Exception:
        write(path, old)
        run('hyprctl', 'reload')
        raise
    return keyboard_layouts()


if __name__ == '__main__':
    try:
        action = sys.argv[1]
        payload = json.loads(sys.argv[2]) if len(sys.argv) > 2 else None
        result = {
            'keys': keybinds,
            'save-keys': lambda: save_keys(payload),
            'monitors': monitors,
            'save-monitors': lambda: save_monitors(payload),
            'keyboard-layout': keyboard_layouts,
            'set-keyboard-layout': lambda: save_keyboard_layout(payload),
        }[action]()
        print(json.dumps({'ok': True, 'data': result}))
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        sys.exit(1)
