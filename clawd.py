"""Clawd desktop pet hooks. Owns its mark so --without-capri never strips it."""
import hashlib
import importlib.util
import json
import os
import re
import shlex
from pathlib import Path

MARK = 'serpantinum-clawd-v2'
TYPES = ['singleton Clawd 1.0 clawd/Clawd.qml'] + [f'{name} 1.0 clawd/{name}.qml' for name in
         ('AddonClawd', 'ClawdOverlay', 'ClawdPet', 'ClawdWorld', 'ClawdEvents', 'ClawdSprite', 'ClawdMenu', 'ClawdBubble', 'ClawdJournal', 'ClawdThought', 'ClawdSettings', 'ClawdCard',
          'ClawdSingularity', 'ClawdBlast', 'ClawdNuke', 'ClawdRevive', 'ClawdRecharge', 'ClawdSymphony', 'ClawdSurge', 'ClawdChat', 'ClawdBrain',
          'ClawdDream', 'ClawdDreamSurf', 'ClawdNightmareGemini', 'ClawdDreamBubble')]
CHORD = 'SUPER + SHIFT + L'


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # IpcHandler "clawd" must be a direct ShellRoot child; same anchor as Capri.
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Clawd shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonClawd {{}}\n    // END {MARK} host\n' + anchor, 1)


def patch_keybind(text, shell_qml):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = f'-- BEGIN {MARK} keybind'
    if marker in text: return text
    if f'"{CHORD}"' in text: raise ValueError(f'Clawd shortcut {CHORD} already in use')
    command = 'quickshell -p ' + shlex.quote(str(shell_qml)) + ' ipc call clawd toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + f'hl.bind("{CHORD}", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n' + f'-- END {MARK} keybind\n'


def remove_blocks(text):
    text = re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)
    lua = re.compile(r'\n*^-- BEGIN ' + MARK + r' ([^\n]+)\n.*?^-- END ' + MARK + r' \1\n', re.S | re.M)
    while lua.search(text):
        text = lua.sub('\n', text, count=1)
    return text


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 clawd/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def resources(payload, qs):
    # Qt caches GPU programs by URL across hot reloads: each shader package is installed under its content hash and
    # every QML file using one is rewritten to it. A package that does not match its source stops the install.
    shaders = payload/'shaders'
    manifest = json.loads((shaders/'manifest.json').read_text())
    names = {}
    for source in sorted(shaders.glob('*.frag')):
        package = shaders/(source.name + '.qsb')
        record = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'package_sha256': hashlib.sha256(package.read_bytes()).hexdigest()}
        if manifest.get(source.stem) != record:
            raise ValueError(f'Clawd shader {source.stem} source/package mismatch; run python3 scripts/clawd/shaders.py')
        names[package.name] = f"{source.stem}.{record['package_sha256'][:12]}.frag.qsb"
    out = []
    for source in sorted(payload.rglob('*')):
        if not source.is_file():
            continue
        path, blob = qs/'clawd'/source.relative_to(payload), source.read_bytes()
        if source.parent == shaders and source.name in names:
            path = path.with_name(names[source.name])
        elif source.suffix == '.qml':
            for plain, hashed in names.items():
                blob = blob.replace(f'shaders/{plain}'.encode(), f'shaders/{hashed}'.encode())
        out.append((path, blob))
    return out


def stale_shaders(qs, everything=False):
    # Superseded hashed packages (all of them when Clawd is removed), deleted by the installer after the new ones are in place.
    shaders = qs/'clawd/shaders'
    keep = set() if everything else {path.name for path, _ in resources(Path(__file__).resolve().parent/'payload/clawd', qs) if path.parent == shaders}
    return sorted(p for p in shaders.glob('*.frag.qsb') if p.name not in keep) if shaders.is_dir() else []


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}


def uninstall_hooks():
    if os.environ.get('SERPANTINUM_ADDONS_NO_SERVICES'):
        return   # tests: never touch the real agent settings
    # Before any shell file changes: a hooks file we cannot rewrite stops the whole run.
    spec = importlib.util.spec_from_file_location('clawd_hooks', Path(__file__).resolve().parent/'scripts/clawd/hooks.py')
    hooks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hooks)
    for agent in hooks.AGENTS:
        hooks.configure(agent, install=False)
    hooks.statusline(install=False)
