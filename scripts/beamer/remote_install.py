#!/usr/bin/env python3
"""Install the Beamer compatibility files on another Hyprland machine."""

import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

import remote_hyprland
import setup

FILES = (
    "launcher.py", "setup.py", "hyprland_capture.py", "hyprland_inject.py",
    "hyprland_clipboard.py", "clipboard_bridge.py", "input_bridge.py", "effect_fix.py", "effect_overlay_helper.py", "overlay_place.py",
    "clipboard_offer.c", "build-clipboard.sh",
    "REMOTE.md", "remote_install.py", "remote_hyprland.py",
)


def has_rescue_binding(binds):
    """Only accept a compositor-level release binding that works during capture."""
    return any(
        bind.get("allow_input_capture") is True
        and "release_input_capture" in str(bind.get("dispatcher", "")).lower()
        and (bind.get("key") or bind.get("keycode"))
        for bind in binds if isinstance(bind, dict)
    )


def check_rescue():
    try:
        result = subprocess.run(["hyprctl", "-j", "binds"], check=True, text=True,
                                capture_output=True, timeout=5)
        binds = json.loads(result.stdout)
        if not isinstance(binds, list):
            raise ValueError("bind list expected")
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        raise RuntimeError("Impossible de vérifier les raccourcis de la session Hyprland active") from exc
    if not has_rescue_binding(binds):
        raise RuntimeError(
            "Aucun raccourci Hyprland de secours release_input_capture avec "
            "allow_input_capture n'est actif. Consulte REMOTE.md avant de poursuivre."
        )


def cleanup_copy(dest, directory_inode, copied):
    """Remove only files created by this invocation that still match their snapshots."""
    if directory_inode is None:
        return []
    if dest.is_symlink() or not dest.is_dir() or dest.stat().st_ino != directory_inode:
        return [f"Dossier déplacé ou remplacé, conservé : {dest}"]
    warnings = []
    for path, (inode, mode, data) in reversed(list(copied.items())):
        try:
            if path.is_symlink() or (path.exists() and
                    (not path.is_file() or path.stat().st_ino != inode or
                     stat.S_IMODE(path.stat().st_mode) != mode or path.read_bytes() != data)):
                warnings.append(f"Fichier modifié, conservé : {path}")
            elif path.exists():
                path.unlink()
        except OSError as exc:
            warnings.append(f"Fichier conservé : {path} ({exc})")
    try:
        dest.rmdir()
    except FileNotFoundError:
        pass
    except OSError:
        warnings.append(f"Dossier non vide ou modifié, conservé : {dest}")
    return warnings


def copy_owned(source, dest):
    with source.open("rb") as src, dest.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    shutil.copystat(source, dest, follow_symlinks=False)


def install():
    source = Path(__file__).resolve().parent
    for name in FILES:
        if not (source / name).is_file():
            raise RuntimeError(f"Fichier du paquet absent : {name}")
    root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    dest = root / "beamer-hyprland-compat"
    if dest.is_symlink() or (dest.exists() and not dest.is_dir()):
        raise RuntimeError(f"Emplacement déjà occupé : {dest}")
    if dest.exists():
        for name in FILES:
            path = dest / name
            if path.is_symlink() or not path.is_file() or path.read_bytes() != (source / name).read_bytes():
                raise RuntimeError(f"Fichier existant différent, conservé : {path}")
    setup.check_dependencies()
    desktop, state_path, cache = setup.paths()
    state = setup.read_state(state_path)
    if (desktop.exists() or desktop.is_symlink()) and not setup.owned(desktop, state.get("desktop")):
        raise RuntimeError(f"Lanceur existant conservé : {desktop}")
    with tempfile.TemporaryDirectory(prefix="beamer-remote-check-") as tmp:
        subprocess.run([str(source / "build-clipboard.sh"), tmp], check=True)
        for name in setup.HELPERS:
            path = cache / name
            expected = state.get("helpers", {}).get(name) if state else setup.digest((Path(tmp) / name).read_bytes())
            if path.is_symlink() or (path.exists() and not setup.owned(path, expected)):
                raise RuntimeError(f"Auxiliaire existant conservé : {path}")
    receipt = remote_hyprland.install()
    if receipt is not None:
        print(f"Sauvegarde Hyprland : {receipt.backup}")
    directory_inode = None
    copied = {}
    try:
        check_rescue()
        root.mkdir(parents=True, exist_ok=True)
        if not dest.exists():
            dest.mkdir(mode=0o700)
            directory_inode = dest.stat().st_ino
            for name in FILES:
                path = dest / name
                copy_owned(source / name, path)
                info = path.stat()
                copied[path] = (info.st_ino, stat.S_IMODE(info.st_mode), path.read_bytes())
        desktop = setup.install(dest)
        return dest, desktop
    except Exception as exc:
        warnings = cleanup_copy(dest, directory_inode, copied)
        if receipt is not None:
            warnings.extend(remote_hyprland.rollback(receipt))
        detail = "; ".join(warnings) if warnings else "Modifications propres annulées."
        backup_note = f" Sauvegarde Hyprland : {receipt.backup}." if receipt is not None else ""
        raise RuntimeError(f"{exc}. {detail}{backup_note}") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Vérifier sans installer")
    args = parser.parse_args()
    try:
        if args.check:
            setup.check_dependencies()
            remote_hyprland.checked_config()
            current = remote_hyprland.binds()
            if not has_rescue_binding(current) and remote_hyprland.conflict(current):
                raise RuntimeError("Super+Maj+F12 est déjà utilisé ; configure d'abord un autre raccourci de secours")
            print("Prérequis et configuration Hyprland vérifiés ; rien n'a été installé.")
        else:
            dest, desktop = install()
            print(f"Adaptation copiée dans {dest}\nLanceur créé : {desktop}")
            print("Utiliser Beamer (Hyprland) sur les deux machines. Aucun lancement n'a été effectué.")
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f"Installation interrompue : {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
