"""Add an independently reversible Hyprland rescue bind and Beamer overlay rule."""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime
from dataclasses import dataclass

BEGIN = "-- BEGIN beamer-hyprland-compat include"
END = "-- END beamer-hyprland-compat include"
RULE = ('hl.window_rule({ name = "beamer-hyprland-compat-overlay", '
        'match = { class = "^(effect_overlay_x11|effect_overlay_helper)[.]py$", xwayland = true }, '
        'no_blur = true, pin = true, move = "0 0" })\n')
BIND = ('hl.bind("SUPER + SHIFT + F12", hl.dsp.release_input_capture(), '
        '{ allow_input_capture = true, dont_inhibit = true, submap_universal = true })\n')


@dataclass(frozen=True)
class Receipt:
    config: Path
    backup: Path
    original: bytes
    updated: bytes
    mode: int
    included: Path
    contents: bytes
    created: bool


def rescue(binds):
    return any(b.get("allow_input_capture") is True
               and "release_input_capture" in str(b.get("dispatcher", "")).lower()
               and (b.get("key") or b.get("keycode")) for b in binds if isinstance(b, dict))


def conflict(binds):
    return any(b.get("modmask") == 65 and (str(b.get("key", "")).lower() == "f12"
               or b.get("keycode") == 96) for b in binds if isinstance(b, dict))


def call(*args):
    return subprocess.run(["hyprctl", *args], check=True, text=True,
                          capture_output=True, timeout=10).stdout


def binds():
    value = json.loads(call("-j", "binds"))
    if not isinstance(value, list):
        raise RuntimeError("Liste de raccourcis Hyprland invalide")
    return value


def checked_config():
    version = call("version")
    found = re.search(r"Hyprland (\d+)\.(\d+)\.(\d+)", version)
    if not found or tuple(map(int, found.groups())) < (0, 57, 0):
        raise RuntimeError("Hyprland 0.57 ou plus récent est nécessaire pour cette installation Lua")
    if "configProvider: lua" not in call("systeminfo"):
        raise RuntimeError("Cette installation automatique requiert une configuration Hyprland Lua")
    if call("configerrors").strip():
        raise RuntimeError("La configuration Hyprland présente déjà une erreur ; elle n'a pas été modifiée")
    instances = json.loads(call("-j", "instances"))
    current = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    active = [item for item in instances if item.get("instance") == current]
    if len(active) != 1:
        raise RuntimeError("Impossible d'identifier la session Hyprland active")
    process = Path(f"/proc/{int(active[0]['pid'])}")
    args = (process / "cmdline").read_bytes().split(b"\0")
    if any(arg in (b"--config", b"-c") or arg.startswith(b"--config=") for arg in args):
        raise RuntimeError("Une configuration Hyprland personnalisée est active ; installation automatique refusée")
    process_env = dict(item.split(b"=", 1) for item in (process / "environ").read_bytes().split(b"\0") if b"=" in item)
    process_config = Path(os.fsdecode(process_env.get(b"XDG_CONFIG_HOME", os.fsencode(Path.home() / ".config"))))
    terminal_config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    if process_config != terminal_config:
        raise RuntimeError("Le répertoire XDG_CONFIG_HOME du terminal diffère de celui de Hyprland")
    config = process_config / "hypr/hyprland.lua"
    if config.is_symlink() or not config.is_file():
        raise RuntimeError(f"Configuration Lua standard absente ou symbolique : {config}")
    return config


def atomic_replace(path, data, mode):
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def rollback(receipt):
    """Undo only unchanged files from this transaction; return warnings for anything retained."""
    problems = []
    config = receipt.config
    try:
        if config.is_symlink() or not config.is_file():
            return [f"Configuration déplacée ou remplacée, conservée : {config}"]
        current = config.read_bytes()
        current_mode = stat.S_IMODE(config.stat().st_mode)
        if current == receipt.updated and current_mode == receipt.mode:
            atomic_replace(config, receipt.original, receipt.mode)
            try:
                call("reload", "config-only")
                if call("configerrors").strip():
                    problems.append("La configuration restaurée signale une erreur au rechargement")
            except (OSError, subprocess.SubprocessError):
                problems.append("Configuration restaurée sur disque ; rechargement Hyprland à vérifier")
        elif current != receipt.original or current_mode != receipt.mode:
            return [f"Configuration modifiée entre-temps, conservée : {config}",
                    f"Inclusion conservée car elle peut encore être utilisée : {receipt.included}"]
    except OSError as exc:
        return [f"Impossible de restaurer {config} : {exc}",
                f"Inclusion conservée : {receipt.included}"]
    if receipt.created:
        try:
            included = receipt.included
            if included.is_symlink() or (included.exists() and
                                        (not included.is_file() or included.read_bytes() != receipt.contents)):
                problems.append(f"Inclusion modifiée entre-temps, conservée : {included}")
            elif included.exists():
                included.unlink()
        except OSError as exc:
            problems.append(f"Inclusion conservée : {receipt.included} ({exc})")
    return problems


def install():
    config = checked_config()
    old = config.read_bytes()
    mode = stat.S_IMODE(config.stat().st_mode)
    included = config.parent / "config/serpantinum_beamer_remote.lua"
    if included.is_symlink():
        raise RuntimeError(f"Lien symbolique refusé : {included}")
    current = binds()
    include = (f"{BEGIN}\ndofile({json.dumps(str(included), ensure_ascii=False)})\n{END}\n").encode()
    if BEGIN.encode() in old or END.encode() in old:
        if include not in old:
            raise RuntimeError("Un marqueur d'inclusion Beamer modifié existe déjà ; il est conservé")
        expected = (("-- Beamer : secours InputCapture et absence de flou sur son animation\n" + RULE).encode(),
                    ("-- Beamer : secours InputCapture et absence de flou sur son animation\n" + BIND + RULE).encode())
        if not included.is_file() or included.read_bytes() not in expected or not rescue(current):
            raise RuntimeError("Le fichier inclus ou le raccourci Beamer a changé ; intervention manuelle nécessaire")
        return None
    existing_rescue = rescue(current)
    if not existing_rescue and conflict(current):
        raise RuntimeError("Super+Maj+F12 est déjà utilisé ; configure d'abord un autre raccourci de secours")
    contents = ("-- Beamer : secours InputCapture et absence de flou sur son animation\n"
                + ("" if existing_rescue else BIND) + RULE).encode()
    if included.exists() and included.read_bytes() != contents:
        raise RuntimeError(f"Fichier de configuration existant conservé : {included}")
    included.parent.mkdir(parents=True, exist_ok=True)
    created = not included.exists()
    if created:
        with included.open("xb") as stream:
            stream.write(contents)
    backup = config.with_name(config.name + ".before-beamer-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    updated = old + (b"\n" if old.endswith(b"\n") else b"\n\n") + include
    receipt = Receipt(config, backup, old, updated, mode, included, contents, created)
    try:
        shutil.copy2(config, backup)
        if config.read_bytes() != old:
            raise RuntimeError("La configuration a changé pendant l'installation ; aucune inclusion ajoutée")
        atomic_replace(config, updated, mode)
        call("reload", "config-only")
        if call("configerrors").strip() or not rescue(binds()):
            raise RuntimeError("Le raccourci de secours n'a pas pu être activé")
    except Exception as exc:
        problems = rollback(receipt)
        if problems:
            raise RuntimeError(f"{exc}. " + "; ".join(problems) + f". Sauvegarde : {backup}") from exc
        raise
    return receipt
