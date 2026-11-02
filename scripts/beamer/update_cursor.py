#!/usr/bin/env python3
"""Replace the first experimental remote bridge with the corrected Lua dispatcher."""
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile

OLD = '6d3cc12cabce57c139e6df877afcb9e2fb3a05fd781182c601934c25b50047c6'
NEW = '3b7b691eaa2c5f06d7dcd4bee19a4220829a0e6e07c0d2145367b88888aff0c8'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def update(target, source, socket):
    if socket.exists() or socket.is_symlink():
        raise RuntimeError('Ferme Beamer (Hyprland) avant de mettre à jour le pont.')
    if target.is_symlink() or not target.is_file():
        raise RuntimeError(f'Pont introuvable ou symbolique : {target}')
    old = target.read_bytes()
    if digest(old) == NEW:
        return 'Le correctif est déjà installé.'
    if digest(old) != OLD:
        raise RuntimeError('Le pont existant a été modifié ; il est conservé.')
    new = source.read_bytes()
    if digest(new) != NEW:
        raise RuntimeError('Le fichier de mise à jour ne correspond pas au correctif attendu.')
    backup = target.with_name(target.name + '.before-cursor-fix')
    if backup.is_symlink() or (backup.exists() and backup.read_bytes() != old):
        raise RuntimeError(f'Sauvegarde existante conservée : {backup}')
    if not backup.exists():
        with backup.open('xb') as f:
            f.write(old)
        os.chmod(backup, stat.S_IMODE(target.stat().st_mode))
    fd, name = tempfile.mkstemp(prefix='.input-bridge-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(new)
        os.chmod(name, stat.S_IMODE(target.stat().st_mode))
        if target.is_symlink() or target.read_bytes() != old:
            raise RuntimeError('Le pont a changé pendant la mise à jour ; il est conservé.')
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return f'Correctif installé ; sauvegarde : {backup}'


def main():
    try:
        runtime = os.environ.get('XDG_RUNTIME_DIR')
        if not runtime:
            raise RuntimeError('XDG_RUNTIME_DIR absent : utilise un terminal de la session graphique.')
        data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
        print(update(data / 'beamer-hyprland-compat/input_bridge.py',
                     Path(__file__).with_name('input_bridge.py'),
                     Path(runtime) / 'beamer-addon/input.sock'))
    except (OSError, RuntimeError) as exc:
        print(f'Mise à jour interrompue : {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
