"""Niri implementations of the Guide's compositor controls."""
import hashlib
import json
import math
import re
from pathlib import Path
from control import CONFIG, write
from niri_world import request
import niri_config

TRANSFORMS = ['normal', '90', '180', '270', 'flipped', 'flipped-90', 'flipped-180', 'flipped-270']


def monitors():
    result = []
    for name, output in request('Outputs').items():
        logical = output.get('logical')
        index = output.get('current_mode')
        if not logical or index is None:
            continue
        mode = output['modes'][index]
        result.append(dict(name=name, width=mode['width'], height=mode['height'],
            refreshRate=mode['refresh_rate'] / 1000, scale=logical['scale'],
            x=logical['x'], y=logical['y'], transform=['Normal', '90', '180', '270', 'Flipped', 'Flipped90', 'Flipped180', 'Flipped270'].index(logical['transform']),
            availableModes=[f"{m['width']}x{m['height']}@{m['refresh_rate']/1000:.3f}Hz" for m in output['modes']]))
    return result


def save_monitors(rows):
    current = {m['name']: m for m in monitors()}
    if {r['name'] for r in rows} != set(current):
        raise ValueError('Connected monitors changed. Reload before applying.')
    lines = []
    for row in rows:
        if row['mode'] not in current[row['name']]['availableModes']:
            raise ValueError('Unsupported display mode')
        transform = int(row['transform'])
        scale = float(row.get('scale', current[row['name']]['scale']))
        if transform not in range(8) or not math.isfinite(scale) or not .25 <= scale <= 4:
            raise ValueError('Invalid scale or rotation')
        lines.append('output ' + json.dumps(row['name']) + ' { mode ' + json.dumps(row['mode'].removesuffix('Hz')) +
                     f'; position x={int(row["x"])} y={int(row["y"])}; scale {scale}; transform "{TRANSFORMS[transform]}"; }}\n')
    niri_config.update('monitors', ''.join(lines))
    return monitors()


def keyboard_layouts():
    from niri_kdl import value
    existing = niri_config.effective_node('input', 'keyboard', 'xkb')
    match = None
    if existing:
        node = next((n for n in existing[1].children if n.name == 'layout'), None)
        if node and node.header:
            match = value(node.header[0])
    layouts = []
    inside = False
    for line in Path('/usr/share/X11/xkb/rules/base.lst').read_text().splitlines():
        if line.startswith('!'):
            inside = line[1:].strip() == 'layout'
        elif inside:
            entry = re.match(r'\s*(\S+)\s+(.+)', line)
            if entry:
                layouts.append(dict(code=entry[1], name=entry[2]))
    return dict(selected=match.split(',') if match else ['us'], layouts=layouts, revision=niri_config.revision())


def save_keyboard_layout(payload):
    current = keyboard_layouts()
    if current['revision'] != payload['revision']:
        raise ValueError('Keyboard settings changed outside this editor.')
    selected = payload.get('layouts')
    valid = {item['code'] for item in current['layouts']}
    if not isinstance(selected, list) or not selected or any(code not in valid for code in selected) or len(selected) != len(set(selected)):
        raise ValueError('Select valid, unique keyboard layouts')
    fields = {'layout': json.dumps(','.join(selected))}
    if len(selected) > 1:
        from niri_kdl import value
        existing = niri_config.effective_node('input', 'keyboard', 'xkb')
        options = next((value(c.header[0]) for c in existing[1].children if c.name == 'options' and c.header), '') if existing else ''
        if 'grp:' not in options:
            fields['options'] = json.dumps(','.join(filter(None, [options, 'grp:alt_shift_toggle'])))
    niri_config.update('keyboard', niri_config.input_fragment('xkb', fields))
    return keyboard_layouts()


def binding_sources():
    import glob
    from niri_kdl import parse, value
    sources = {}
    def visit(path, stack):
        path = path.resolve()
        if path in stack:
            raise ValueError('Recursive Niri include')
        if path in sources:
            return
        text = path.read_text()
        nodes = parse(text)
        sources[path] = (text, nodes)
        for node in nodes:
            if node.name == 'include' and node.header:
                pattern = Path(value(node.header[0])).expanduser()
                if not pattern.is_absolute():
                    pattern = path.parent / pattern
                for match in sorted(glob.glob(str(pattern))):
                    visit(Path(match), stack | {path})
    visit(CONFIG / 'niri/config.kdl', set())
    return sources


def binding_revision(sources):
    digest = hashlib.sha256()
    for path, (text, _) in sources.items():
        digest.update(str(path).encode() + b'\0' + text.encode() + b'\0')
    return digest.hexdigest()


def binding_rows(sources):
    import shlex
    from niri_kdl import value
    rows, locations = [], {}
    for path, (text, nodes) in sources.items():
        for section in nodes:
            if section.name != 'binds':
                continue
            for node in section.children:
                index = len(rows)
                command = None
                if len(node.children) == 1:
                    action = node.children[0]
                    if action.name == 'spawn-sh' and len(action.header) == 1:
                        command = value(action.header[0])
                    elif action.name == 'spawn' and all(t.text.startswith(('"', 'r"', 'r#')) for t in action.header):
                        command = shlex.join(value(t) for t in action.header)
                action = text[node.opening + 1:node.closing].strip() if node.opening is not None else ''
                rows.append(dict(line=index, key=node.name.replace('Mod+', 'SUPER+'), action=command or action,
                                 command=command, original=text[node.start:node.end]))
                locations[index] = (path, node)
    return rows, locations


def keybinds():
    sources = binding_sources()
    rows, _ = binding_rows(sources)
    return dict(rows=rows, revision=binding_revision(sources))


def save_keys(payload):
    sources = binding_sources()
    if binding_revision(sources) != payload['revision']:
        raise ValueError('Bindings changed outside this editor.')
    rows, locations = binding_rows(sources)
    known = {row['line']: row for row in rows}
    edits, seen, retained, additions = {}, set(), set(), []
    for row in payload['rows']:
        index = int(row['line'])
        chord = re.sub(r'\s+', '', row['key'])
        chord = re.sub(r'(?i)(^|\+)(SUPER|CTRL|SHIFT|ALT)(?=\+)', lambda m: m[1] + {'SUPER':'Mod','CTRL':'Ctrl','SHIFT':'Shift','ALT':'Alt'}[m[2].upper()], chord)
        if not re.fullmatch(r'[\w+.-]+', chord) or chord.lower() in seen:
            raise ValueError('Invalid or duplicate shortcut')
        seen.add(chord.lower())
        if index == -1:
            command = row.get('command')
            if not isinstance(command, str) or not command.strip() or any(ord(c) < 32 for c in command):
                raise ValueError('New shortcut needs a valid command')
            additions.append('    ' + chord + ' { spawn-sh ' + json.dumps(command, ensure_ascii=False) + '; }\n')
            continue
        if index not in known or row['original'] != known[index]['original'] or index in retained:
            raise ValueError('Binding source changed')
        retained.add(index)
        path, node = locations[index]
        text = sources[path][0]
        changes = edits.setdefault(path, [])
        changes.append((node.start, node.name_end, chord))
        if known[index]['command'] is not None:
            command = row.get('command', known[index]['command'])
            if not isinstance(command, str) or not command.strip() or any(ord(c) < 32 for c in command):
                raise ValueError('Invalid command')
            if command != known[index]['command']:
                action = node.children[0]
                changes.append((action.start, action.end, 'spawn-sh ' + json.dumps(command, ensure_ascii=False) + '; '))
    for index in known.keys() - retained:
        path, node = locations[index]
        edits.setdefault(path, []).append((node.start, node.end, ''))
    if additions:
        main = (CONFIG / 'niri/config.kdl').resolve()
        section = next((n for n in sources[main][1] if n.name == 'binds'), None)
        if section and section.closing is not None:
            edits.setdefault(main, []).append((section.closing, section.closing, '\n' + ''.join(additions)))
        else:
            end = len(sources[main][0])
            edits.setdefault(main, []).append((end, end, '\nbinds {\n' + ''.join(additions) + '}\n'))
    changes = {}
    for path, replacements in edits.items():
        text = sources[path][0]
        for start, end, replacement in sorted(replacements, reverse=True):
            text = text[:start] + replacement + text[end:]
        changes[path] = text
    niri_config.transaction(changes)
    return keybinds()
