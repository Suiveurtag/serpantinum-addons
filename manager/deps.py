"""Dependency table, detection and install planning (stdlib only)."""
from __future__ import annotations

import importlib.util
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

MANAGERS = ("pacman", "dnf", "xbps")
DEFAULT_HYPRLAND_MIN = "0.55"
DEFAULT_QUICKSHELL_MIN = "0.3.0"
PYTHON_MIN = "3.10"

# Package spec per manager: "name" (official repo), "aur:name", "copr:owner/project:name",
# or absent/None when the manager has no package (see Dep.manual).


@dataclass(frozen=True)
class Dep:
    id: str
    label: str
    kind: str  # cmd | module | python | hyprland | quickshell | systemd_user
    target: object  # command name (or tuple of alternatives) / module name
    required: bool
    feature: str
    packages: dict = field(default_factory=dict)
    manual: str = ""


DEPS = [
    Dep("python3", "Python 3.10+", "python", "python3", True,
        "the installer itself cannot run",
        {"pacman": "python", "dnf": "python3", "xbps": "python3"}),
    Dep("pillow", "Pillow (python-pillow)", "module", "PIL", True,
        "colours, custom cursors and wallpapers",
        {"pacman": "python-pillow", "dnf": "python3-pillow", "xbps": "python3-Pillow"}),
    Dep("jq", "jq", "cmd", "jq", True,
        "colour generation and shell scripts",
        {"pacman": "jq", "dnf": "jq", "xbps": "jq"}),
    Dep("matugen", "matugen", "cmd", "matugen", True,
        "colour generation from the wallpaper",
        {"pacman": "matugen", "dnf": "copr:mecattaf/duoRPM:matugen", "xbps": "matugen"},
        "cargo install matugen"),
    Dep("node", "Node.js", "cmd", "node", True,
        "Capri and Clawd hooks and chat",
        {"pacman": "nodejs", "dnf": "nodejs", "xbps": "nodejs"}),
    Dep("grim", "grim", "cmd", "grim", True,
        "colour picker and frozen capture",
        {"pacman": "grim", "dnf": "grim", "xbps": "grim"}),
    Dep("wl-copy", "wl-clipboard (wl-copy)", "cmd", "wl-copy", True,
        "colour picker clipboard",
        {"pacman": "wl-clipboard", "dnf": "wl-clipboard", "xbps": "wl-clipboard"}),
    Dep("udevadm", "udevadm", "cmd", "udevadm", True,
        "trackpad detection",
        {"pacman": "systemd", "dnf": "systemd-udev", "xbps": "eudev"}),
    Dep("systemd-user", "systemd user session", "systemd_user", "systemctl", True,
        "AI Tokens collector and Wallpaper Engine service",
        {"pacman": "systemd", "dnf": "systemd"},
        "this shell needs a systemd user session (log in through your display manager)"),
    Dep("networkmanager", "NetworkManager (nmcli)", "cmd", "nmcli", True,
        "Mullvad DNS and network settings",
        {"pacman": "networkmanager", "dnf": "NetworkManager", "xbps": "NetworkManager"}),
    Dep("resolved", "systemd-resolved (resolvectl)", "cmd", "resolvectl", True,
        "Mullvad DNS",
        {"pacman": "systemd", "dnf": "systemd-resolved"},
        "install and enable systemd-resolved"),
    Dep("hyprland", "Hyprland 0.55+", "hyprland", ("hyprctl", "Hyprland"), True,
        "shortcuts, cursors, trackpad, zoom, outline and the click guard",
        {"pacman": "hyprland", "dnf": "copr:mineiro/hyprland:hyprland"},
        "see https://wiki.hypr.land/Getting-Started/Installation/"),
    Dep("quickshell", "Quickshell", "quickshell", "quickshell", True,
        "the shell itself",
        {"pacman": "quickshell", "dnf": "copr:errornointernet/quickshell:quickshell",
         "xbps": "quickshell"},
        "on Arch you can also use the AUR package quickshell-git"),
    # optional
    Dep("codex", "Codex CLI", "cmd", "codex", False,
        "Clawd chat and Capri's ChatGPT provider (then run: codex login)",
        {}, "npm install -g @openai/codex"),
    Dep("ollama", "Ollama", "cmd", "ollama", False,
        "Capri running locally",
        {"pacman": "ollama", "xbps": "ollama"}, "see https://ollama.com/download"),
    Dep("cmake", "CMake", "cmd", "cmake", False,
        "building Wallpaper Engine backgrounds",
        {"pacman": "cmake", "dnf": "cmake", "xbps": "cmake"}),
    Dep("qt6-dev", "Qt 6 development files", "cmd", ("qmake6", "qmake-qt6"), False,
        "building Wallpaper Engine backgrounds",
        {"pacman": "qt6-base", "dnf": "qt6-qtbase-devel", "xbps": "qt6-base-devel"}),
]
BY_ID = {d.id: d for d in DEPS}


# ---------------------------------------------------------------- probing
def _default_run(argv, timeout=8):
    """Return (returncode, combined output); never raises."""
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except (OSError, subprocess.SubprocessError) as e:
        return 127, str(e)


def _default_has_module(name):
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


class Probe:
    """Injectable system access: which(cmd), run(argv)->(rc, out), has_module(name)."""

    def __init__(self, which=None, run=None, has_module=None):
        self.which = which or shutil.which
        self.run = run or _default_run
        self.has_module = has_module or _default_has_module


def _vt(s):
    return tuple(int(x) for x in re.findall(r"\d+", s or "")[:4])


def version_at_least(have: str, need: str) -> bool:
    a, b = _vt(have), _vt(need)
    n = max(len(a), len(b))
    return a + (0,) * (n - len(a)) >= b + (0,) * (n - len(b))


def parse_hyprland_version(text: str):
    """Extract 'X.Y.Z' from `hyprctl version` / `Hyprland --version` output."""
    for pat in (r"Hyprland\s+v?(\d+\.\d+(?:\.\d+)?)", r"Tag:\s*v?(\d+\.\d+(?:\.\d+)?)",
                r"\bv(\d+\.\d+\.\d+)\b"):
        m = re.search(pat, text or "")
        if m:
            return m.group(1)
    return None


def parse_quickshell_version(text: str):
    m = re.search(r"Quickshell\s+v?(\d+(?:\.\d+)+)", text or "", re.I)
    return m.group(1) if m else None


@dataclass
class DepResult:
    dep: Dep
    status: str  # ok | missing | old
    version: str = ""
    detail: str = ""

    @property
    def ok(self) -> bool:
        return self.status == "ok"


def _first(probe, names):
    for n in (names if isinstance(names, tuple) else (names,)):
        if probe.which(n):
            return n
    return None


def check_dep(dep: Dep, probe=None, compat=None) -> DepResult:
    probe = probe or Probe()
    compat = compat or {}
    if dep.kind == "module":
        ok = probe.has_module(dep.target)
        return DepResult(dep, "ok" if ok else "missing", "", "" if ok else "python module not found")
    if dep.kind == "python":
        if not probe.which(dep.target):
            return DepResult(dep, "missing", "", "python3 not on PATH")
        rc, out = probe.run([dep.target, "--version"])
        m = re.search(r"(\d+\.\d+(?:\.\d+)?)", out)
        ver = m.group(1) if m else ""
        if ver and not version_at_least(ver, PYTHON_MIN):
            return DepResult(dep, "old", ver, f"{ver} found, {PYTHON_MIN} or newer needed")
        return DepResult(dep, "ok", ver)
    if dep.kind == "systemd_user":
        if not probe.which(dep.target):
            return DepResult(dep, "missing", "", "systemctl not found")
        rc, _ = probe.run([dep.target, "--user", "show-environment"])
        if rc != 0:
            return DepResult(dep, "missing", "", "no systemd user session reachable")
        return DepResult(dep, "ok")
    if dep.kind == "hyprland":
        need = compat.get("hyprland_min") or DEFAULT_HYPRLAND_MIN
        ver = None
        found = False
        for exe, args in (("hyprctl", ["version"]), ("Hyprland", ["--version"])):
            if not probe.which(exe):
                continue
            found = True
            rc, out = probe.run([exe] + args)
            ver = parse_hyprland_version(out)
            if ver:
                break
        if not found:
            return DepResult(dep, "missing", "", "hyprctl / Hyprland not found")
        if not ver:
            return DepResult(dep, "ok", "", "version could not be read")
        if not version_at_least(ver, need):
            return DepResult(dep, "old", ver, f"{ver} found, {need} or newer needed")
        return DepResult(dep, "ok", ver)
    if dep.kind == "quickshell":
        if not probe.which(dep.target):
            return DepResult(dep, "missing", "", "quickshell not found")
        need = compat.get("quickshell_min") or DEFAULT_QUICKSHELL_MIN
        rc, out = probe.run([dep.target, "--version"])
        ver = parse_quickshell_version(out)
        if ver and not version_at_least(ver, need):
            return DepResult(dep, "old", ver, f"{ver} found, {need} or newer needed")
        return DepResult(dep, "ok", ver or "")
    name = _first(probe, dep.target)
    if name:
        return DepResult(dep, "ok", "", name)
    return DepResult(dep, "missing", "", "command not found")


def check_all(probe=None, compat=None, deps=None) -> list:
    probe = probe or Probe()
    return [check_dep(d, probe, compat) for d in (deps or DEPS)]


def missing(results, required=None) -> list:
    """Results that are not ok, optionally filtered by required True/False."""
    return [r for r in results if not r.ok and (required is None or r.dep.required == required)]


# ---------------------------------------------------------------- packaging
def detect_package_manager(which=None):
    which = which or shutil.which
    if which("pacman"):
        return "pacman"
    if which("dnf"):
        return "dnf"
    if which("xbps-install"):
        return "xbps"
    return None


def parse_pkg(spec):
    """-> (source, name, extra): source repo | aur | copr."""
    if not spec:
        return None
    if spec.startswith("aur:"):
        return "aur", spec[4:], ""
    if spec.startswith("copr:"):
        _, repo, name = spec.split(":", 2)
        return "copr", name, repo
    return "repo", spec, ""


def _as_dep(x) -> Dep:
    if isinstance(x, DepResult):
        return x.dep
    if isinstance(x, str):
        return BY_ID[x]
    return x


@dataclass
class Plan:
    manager: str
    commands: list = field(default_factory=list)  # argv lists, run in order
    manual: list = field(default_factory=list)    # [(Dep, instruction)]


def _dedupe(seq):
    return list(dict.fromkeys(seq))


def repo_install_argv(manager, packages):
    if not packages:
        return []
    if manager == "pacman":
        return ["sudo", "pacman", "-S", "--needed", *packages]
    if manager == "dnf":
        return ["sudo", "dnf", "install", *packages]
    if manager == "xbps":
        return ["sudo", "xbps-install", "-S", *packages]
    return []


def build_plan(missing_items, manager, which=None) -> Plan:
    """Commands needed to install `missing_items` (Dep / DepResult / id). Nothing --noconfirm."""
    which = which or shutil.which
    plan = Plan(manager or "")
    repo_pkgs, aur_pkgs, copr_repos = [], [], []
    for item in missing_items:
        dep = _as_dep(item)
        parsed = parse_pkg(dep.packages.get(manager)) if manager else None
        if not parsed:
            plan.manual.append((dep, dep.manual or f"install {dep.label} with your package manager"))
            continue
        source, name, extra = parsed
        if source == "aur":
            helper = next((h for h in ("yay", "paru") if which(h)), None)
            if helper:
                aur_pkgs.append((helper, name))
            else:
                plan.manual.append((dep, f"{name} is AUR-only: install yay or paru "
                                         f"(https://aur.archlinux.org/packages/{name}), then "
                                         f"run: yay -S --needed {name}"))
        elif source == "copr":
            copr_repos.append(extra)
            repo_pkgs.append(name)
        else:
            repo_pkgs.append(name)
    for repo in _dedupe(copr_repos):
        plan.commands.append(["sudo", "dnf", "copr", "enable", repo])
    argv = repo_install_argv(manager, _dedupe(repo_pkgs))
    if argv:
        plan.commands.append(argv)
    for helper in _dedupe(h for h, _ in aur_pkgs):
        plan.commands.append([helper, "-S", "--needed", *_dedupe(n for h, n in aur_pkgs if h == helper)])
    return plan


def install_command(missing_items, manager) -> list:
    """argv installing the repo-available packages (no --noconfirm: the manager asks)."""
    pkgs = []
    for item in missing_items:
        parsed = parse_pkg(_as_dep(item).packages.get(manager))
        if parsed and parsed[0] != "aur":
            pkgs.append(parsed[1])
    return repo_install_argv(manager, _dedupe(pkgs))


def format_command(argv) -> str:
    return " ".join(shlex.quote(a) for a in argv)


def python_ok() -> bool:
    return sys.version_info >= tuple(int(x) for x in PYTHON_MIN.split("."))
