"""Validated addon fragments for Niri; preserve the user's main configuration."""
import os
from pathlib import Path
import shutil
import subprocess
from control import CONFIG, write


def active():
    return bool(os.environ.get('NIRI_SOCKET'))


def executable():
    local = Path.home() / '.local/opt/niri-serpantinum/bin/niri'
    return str(local) if local.exists() else shutil.which('niri') or str(Path.home() / '.local/opt/niri/usr/bin/niri')


def update(name, content, verify=None, extra=None):
    main = CONFIG / 'niri/config.kdl'
    fragment = CONFIG / 'niri' / ('serpantinum-' + name + '.kdl')
    include = 'include "' + fragment.name + '"'
    text = main.read_text() if main.exists() else ''
    if include not in text.splitlines():
        text = text.rstrip() + '\n' + include + '\n'
    transaction({main: text, fragment: content, **(extra or {})}, verify=verify)


def transaction(changes, verify=None):
    main = CONFIG / 'niri/config.kdl'
    old = {p: p.read_text() if p.exists() else None for p in changes}
    try:
        for path, content in changes.items():
            if content != old[path]:
                write(path, content)
        result = subprocess.run([executable(), 'validate', '-c', str(main)], capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError(result.stderr)
        if verify is not None:
            import time
            deadline = time.monotonic() + 3
            while not verify():
                if time.monotonic() >= deadline:
                    raise ValueError('Niri did not apply the requested settings; restored the previous configuration')
                time.sleep(.04)
    except Exception:
        for path, content in old.items():
            if content is None:
                path.unlink(missing_ok=True)
            elif not path.exists() or path.read_text() != content:
                write(path, content)
        raise


def revision():
    from niri_controls import binding_sources, binding_revision
    return binding_revision(binding_sources())


def effective_node(*names):
    """Return the last matching node in actual include order, along with its source."""
    import glob
    from niri_kdl import value
    from niri_controls import binding_sources
    sources = binding_sources()
    found = None
    def visit(path):
        nonlocal found
        text, nodes = sources[path]
        for node in nodes:
            if node.name == 'include' and node.header:
                pattern = Path(value(node.header[0])).expanduser()
                if not pattern.is_absolute(): pattern = path.parent / pattern
                for match in sorted(glob.glob(str(pattern))): visit(Path(match).resolve())
                continue
            candidates = [node]
            for name in names:
                item = next((n for n in candidates if n.name == name), None)
                if item is None: break
                candidates = item.children
            else:
                found = (text, item)
    visit((CONFIG / 'niri/config.kdl').resolve())
    return found


def input_fragment(kind, fields):
    """Preserve all existing device/XKB fields when Niri replaces a whole sub-block."""
    names = ('input', 'keyboard', 'xkb') if kind == 'xkb' else ('input', kind)
    existing = effective_node(*names)
    if existing:
        text, node = existing
        body = text[node.start:node.end]
        edits = []
        for name, value in fields.items():
            children = [c for c in node.children if c.name == name]
            replacement = '' if value is None else name + (' ' + value if value else '') + '; '
            if children:
                for child in children:
                    edits.append((child.start-node.start, child.end-node.start, replacement))
            elif value is not None:
                edits.append((node.closing-node.start, node.closing-node.start, '\n    ' + replacement + '\n'))
        for start, end, replacement in sorted(edits, reverse=True):
            body = body[:start] + replacement + body[end:]
    else:
        body = kind + ' {\n' + ''.join('    ' + k + (' '+v if v else '') + ';\n' for k,v in fields.items() if v is not None) + '}\n'
    if kind == 'xkb': body = 'keyboard {\n' + body + '\n}\n'
    return 'input {\n' + body + '\n}\n'
