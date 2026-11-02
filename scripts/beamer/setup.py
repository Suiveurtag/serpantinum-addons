#!/usr/bin/env python3
"""Install or remove the optional Beamer launcher without touching the Flatpak."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

_launcher_spec = importlib.util.spec_from_file_location('beamer_addon_launcher', Path(__file__).with_name('launcher.py'))
_launcher = importlib.util.module_from_spec(_launcher_spec)
_launcher_spec.loader.exec_module(_launcher)
APP, VERSION = _launcher.APP, _launcher.VERSION

HELPERS = ("clipboard-offer", "wl-paste")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def desktop_quote(value):
    # Desktop Exec has its own quoting rules; percent introduces a field code.
    return '"' + value.replace('%', '%%').replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$') + '"'


def desktop_content(addon_dir):
    cmd = desktop_quote(sys.executable) + ' ' + desktop_quote(str(addon_dir / 'launcher.py'))
    return ('[Desktop Entry]\nType=Application\nName=Beamer (Hyprland)\n'
            'Comment=Share keyboard and mouse using Serpantinum addons\n'
            f'Exec={cmd}\nIcon=uk.co.kalkman.beamer\nTerminal=true\n'
            'Categories=Utility;\nStartupWMClass=uk.co.kalkman.beamer\n').encode()


def paths():
    home = Path.home()
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
    state = Path(os.environ.get('XDG_STATE_HOME', home / '.local/state'))
    cache = Path(os.environ.get('XDG_CACHE_HOME', home / '.cache'))
    return (data / 'applications/serpantinum-beamer.desktop',
            state / 'serpantinum-addons-v2/beamer-install.json',
            cache / 'serpantinum-addons-v2/beamer')


def atomic_write(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_state(path):
    if path.is_symlink():
        raise RuntimeError(f'Refusing symbolic link: {path}')
    if not path.exists():
        return {}
    try:
        state = json.loads(path.read_text())
        if not isinstance(state, dict) or not isinstance(state.get('desktop'), str) or not isinstance(state.get('helpers'), dict):
            raise ValueError('invalid state')
        return state
    except (ValueError, OSError) as exc:
        raise RuntimeError(f'Cannot read Beamer install state: {path}') from exc


def owned(path, expected):
    return not path.is_symlink() and path.is_file() and digest(path.read_bytes()) == expected


def check_dependencies():
    missing = [name for name in ('flatpak', 'hyprctl', 'wl-paste', 'wayland-scanner', 'cc', 'pkg-config')
               if not shutil.which(name)]
    try:
        import evdev  # noqa: F401
    except ImportError:
        missing.append('python-evdev')
    if not os.access('/dev/uinput', os.R_OK | os.W_OK):
        missing.append('read/write access to /dev/uinput')
    protocol = Path('/usr/share/wayland-protocols/staging/ext-data-control/ext-data-control-v1.xml')
    if not protocol.is_file():
        missing.append('wayland-protocols ext-data-control XML')
    if missing:
        raise RuntimeError('Missing Beamer dependencies: ' + ', '.join(missing))
    try:
        installed = subprocess.check_output(['flatpak', 'list', '--user', '--app', '--columns=application,version'], text=True)
        subprocess.run(['pkg-config', '--exists', 'wayland-client'], check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError('Beamer user Flatpak or Wayland client development files are unavailable') from exc
    versions = [row.split('\t', 1)[1].strip() for row in installed.splitlines() if row.startswith(APP + '\t')]
    if versions != [VERSION]:
        raise RuntimeError(f'Beamer {VERSION} is required, installed versions: {versions or "none"}')


def install(addon_dir):
    desktop, state_path, cache = paths()
    state = read_state(state_path)
    if (desktop.exists() or desktop.is_symlink()) and not owned(desktop, state.get('desktop')):
        raise RuntimeError(f'Refusing to overwrite an unowned or modified launcher: {desktop}')
    for name in HELPERS:
        path = cache / name
        if path.is_symlink() or (state and path.exists() and not owned(path, state.get('helpers', {}).get(name))):
            raise RuntimeError(f'Refusing to overwrite an unowned or modified helper: {path}')
    check_dependencies()
    addon_dir = Path(addon_dir).resolve()
    if not (addon_dir / 'launcher.py').is_file():
        raise RuntimeError('The deployed Beamer launcher is missing')
    cache.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.beamer-build-', dir=cache.parent) as temp:
        subprocess.run([str(addon_dir / 'build-clipboard.sh'), temp], check=True)
        helpers = {name: (Path(temp) / name).read_bytes() for name in HELPERS}
    for name, data in helpers.items():
        path = cache / name
        if not state and path.exists() and not owned(path, digest(data)):
            raise RuntimeError(f'Refusing to overwrite an unowned helper: {path}')
    content = desktop_content(addon_dir)
    targets = [(cache / name, data, 0o755) for name, data in helpers.items()]
    targets += [(desktop, content, 0o644), (state_path, json.dumps(
        {'desktop': digest(content), 'helpers': {k: digest(v) for k, v in helpers.items()}}, indent=2).encode() + b'\n', 0o600)]
    before = {path: (path.read_bytes(), path.stat().st_mode & 0o777) if path.exists() else None for path, _, _ in targets}
    try:
        for path, data, mode in targets:
            atomic_write(path, data, mode)
    except OSError:
        for path, previous in before.items():
            if previous is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, *previous)
        raise
    return desktop


def uninstall_plan():
    """Find only addon-owned files; this is also safe for a dry run."""
    desktop, state_path, cache = paths()
    state = read_state(state_path)
    if not state:
        return [], []
    removable = []
    preserved = []
    targets = [(desktop, state['desktop'])] + [(cache / name, state['helpers'].get(name)) for name in HELPERS]
    for path, expected in targets:
        if not path.exists() and not path.is_symlink():
            continue
        if owned(path, expected):
            removable.append(path)
        else:
            preserved.append(path)
    if not preserved:
        removable.append(state_path)
    return removable, preserved


def uninstall():
    removable, preserved = uninstall_plan()
    for path in removable:
        path.unlink()
    return preserved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'uninstall'))
    args = parser.parse_args()
    try:
        if args.action == 'install':
            print(f'Beamer launcher installed: {install(Path(__file__).resolve().parent)}')
        else:
            preserved = uninstall()
            print('Beamer launcher removed.' if not preserved else 'Modified files preserved: ' + ', '.join(map(str, preserved)))
    except (RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Beamer setup failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
