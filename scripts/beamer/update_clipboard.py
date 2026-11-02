#!/usr/bin/env python3
"""Upgrade the initially installed Beamer adapter without overwriting user changes."""
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile

OLD_LAUNCHER = '73b997edf83fc05d69ebeb6a590e279846c880fe403fd11d4fc2a8f7a258c958'
NEW_LAUNCHER = '24473586c4478f753247c5d61d2624dd49b77fe32b8ab9a542e88597c440c945'
BRIDGE = '4e2b3c1156836599a7b4d517a923dc37e8c6132d8c638053a7d37f40c7038e23'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def replace(path, content, mode):
    fd, temp = tempfile.mkstemp(prefix='.beamer-update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def update(destination, source, runtime):
    if destination.is_symlink() or not destination.is_dir():
        raise RuntimeError(f'Dossier Beamer introuvable ou symbolique : {destination}')
    for name in ('input.sock', 'clipboard.sock'):
        path = runtime / 'beamer-addon' / name
        if path.exists() or path.is_symlink():
            raise RuntimeError('Ferme Beamer (Hyprland) avant la mise à jour.')
    launcher, bridge = destination / 'launcher.py', destination / 'clipboard_bridge.py'
    if launcher.is_symlink() or not launcher.is_file():
        raise RuntimeError('Lanceur Beamer introuvable ou symbolique.')
    old = launcher.read_bytes()
    if digest(old) not in (OLD_LAUNCHER, NEW_LAUNCHER):
        raise RuntimeError('Le lanceur existant a été modifié ; il est conservé.')
    new, bridge_data = (source / name for name in ('launcher.py', 'clipboard_bridge.py'))
    new, bridge_data = new.read_bytes(), bridge_data.read_bytes()
    if digest(new) != NEW_LAUNCHER or digest(bridge_data) != BRIDGE:
        raise RuntimeError('Le contenu de mise à jour ne correspond pas à la version attendue.')
    if bridge.is_symlink() or (bridge.exists() and (not bridge.is_file() or digest(bridge.read_bytes()) != BRIDGE)):
        raise RuntimeError('Le pont presse-papiers existant a été modifié ; il est conservé.')
    backup = launcher.with_name('launcher.py.before-clipboard-bridge')
    if digest(old) == OLD_LAUNCHER:
        if backup.is_symlink() or (backup.exists() and backup.read_bytes() != old):
            raise RuntimeError(f'Sauvegarde existante conservée : {backup}')
        if not backup.exists():
            with backup.open('xb') as f:
                f.write(old)
            os.chmod(backup, stat.S_IMODE(launcher.stat().st_mode))
    created = False
    try:
        if not bridge.exists():
            with bridge.open('xb') as f:
                f.write(bridge_data)
            created = True
        if launcher.is_symlink() or launcher.read_bytes() != old:
            raise RuntimeError('Le lanceur a changé pendant la mise à jour ; il est conservé.')
        if digest(old) != NEW_LAUNCHER:
            replace(launcher, new, stat.S_IMODE(launcher.stat().st_mode))
    except Exception:
        if created and bridge.is_file() and not bridge.is_symlink() and bridge.read_bytes() == bridge_data:
            bridge.unlink()
        raise
    return 'Correctif presse-papiers installé.'


def main():
    try:
        runtime = os.environ.get('XDG_RUNTIME_DIR')
        if not runtime:
            raise RuntimeError('XDG_RUNTIME_DIR absent : utilise un terminal de la session graphique.')
        data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
        print(update(data / 'beamer-hyprland-compat', Path(__file__).resolve().parent, Path(runtime)))
    except (OSError, RuntimeError) as exc:
        print(f'Mise à jour interrompue : {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
