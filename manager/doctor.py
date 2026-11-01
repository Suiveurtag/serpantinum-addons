"""Read-only diagnostics and the paste-ready issue report."""
from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from . import REPO_ROOT, SERPANTINUM_URL, local_version, release
from . import deps as D

OK, WARN, FAIL = "ok", "warn", "fail"


@dataclass
class Result:
    id: str
    title: str
    status: str
    detail: str = ""
    fix: str = ""


def tilde(text) -> str:
    """Hide the user's home directory (and any /home/<user>) in shared text."""
    text = str(text)
    home = os.path.expanduser("~")
    if home and home != "/":
        text = text.replace(home, "~")
    return re.sub(r"/(?:home|Users)/[^/\s\"']+", "~", text)


def _run(argv, timeout=20):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except OSError as e:
        return 127, str(e)


def os_pretty_name(path="/etc/os-release") -> str:
    try:
        for line in Path(path).read_text().splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return platform.system() or "unknown"


def parse_json_output(text):
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        pass
    a, b = (text or "").find("{"), (text or "").rfind("}")
    if 0 <= a < b:
        try:
            return json.loads(text[a:b + 1])
        except ValueError:
            return None
    return None


def run_checks(rel=None, run=None, which=None, network=True, probe=None,
               install_py=None) -> list:
    """Return a list of Result. Everything external is injectable."""
    rel = rel or release()
    run = run or _run
    which = which or shutil.which
    probe = probe or D.Probe(which=which)
    install_py = install_py or (REPO_ROOT / "install.py")
    out = []

    # Serpantinum
    ss = rel.serpantinum_state()
    sv = ss.get("version")
    if sv:
        out.append(Result("serpantinum", "Serpantinum", OK,
                          f"{sv}" + (f" ({ss['commit']})" if ss.get("commit") else "")))
    else:
        out.append(Result("serpantinum", "Serpantinum", FAIL, "not found",
                          f"Install Serpantinum first: {SERPANTINUM_URL}"))

    # compat
    compat = rel.load_compat()
    st = rel.compat_status(sv, compat)
    tested = ((compat.get("serpantinum") or {}).get("tested")) or "?"
    mn = ((compat.get("serpantinum") or {}).get("min")) or "?"
    if st == "ok":
        out.append(Result("compat", "Compatibility", OK, f"Serpantinum {sv} is supported (tested {tested})"))
    elif st == "too_old":
        out.append(Result("compat", "Compatibility", FAIL, f"Serpantinum {sv} is older than {mn}",
                          "Update Serpantinum, then run: python3 addons.py reinstall"))
    elif st == "newer_than_tested":
        out.append(Result("compat", "Compatibility", WARN,
                          f"Serpantinum {sv} is newer than the tested {tested}",
                          "It may still work; if anchors fail below, check for an addons update"))
    else:
        out.append(Result("compat", "Compatibility", WARN, "unknown (Serpantinum version not readable)"))

    # upstream
    if network and sv:
        try:
            up = rel.upstream_latest_version()
        except Exception:
            up = None
        if up and rel.compare(up, sv) > 0:
            out.append(Result("upstream", "Serpantinum up to date", WARN,
                              f"{up} is available (you have {sv})",
                              "Update Serpantinum first, then run: python3 addons.py reinstall"))
        elif up:
            out.append(Result("upstream", "Serpantinum up to date", OK, f"latest is {up}"))
        else:
            out.append(Result("upstream", "Serpantinum up to date", WARN,
                              "could not check the latest Serpantinum version"))

    # addons install state
    inst = rel.read_install_state()
    without = []
    if not inst:
        out.append(Result("addons", "Addons", OK, f"not installed (this checkout is {local_version()})"))
    else:
        without = list(inst.get("without") or [])
        detail = f"{inst.get('version', '?')} · channel {inst.get('channel', '?')}"
        if without:
            detail += " · without " + ", ".join(without)
        out.append(Result("addons", "Addons", OK, detail))
        src = inst.get("source")
        if src:
            exists = Path(str(src)).expanduser().exists()
            out.append(Result("source", "Source checkout", OK if exists else WARN,
                              tilde(src) + ("" if exists else " (missing)"),
                              "" if exists else "Re-run the one-line install command from the README"))
        if (inst.get("serpantinum_version") != sv
                or inst.get("serpantinum_commit") != ss.get("commit")):
            out.append(Result("reinstall", "Reinstall needed", WARN,
                              f"Serpantinum changed since install ({inst.get('serpantinum_version')} → {sv})",
                              "Run: python3 addons.py reinstall"))
        else:
            out.append(Result("reinstall", "Reinstall needed", OK, "no"))

    # dependencies
    results = D.check_all(probe, compat)
    miss_req = D.missing(results, required=True)
    miss_opt = D.missing(results, required=False)
    total_req = sum(1 for r in results if r.dep.required)
    out.append(Result("deps", "Required dependencies",
                      FAIL if miss_req else OK, f"{total_req - len(miss_req)}/{total_req} present"))
    mgr = D.detect_package_manager(which)
    for r in miss_req:
        out.append(Result(f"dep:{r.dep.id}", r.dep.label, FAIL,
                          f"{r.detail or r.status}; needed for {r.dep.feature}",
                          _dep_fix(r, mgr, which)))
    for r in miss_opt:
        out.append(Result(f"dep:{r.dep.id}", r.dep.label, WARN,
                          f"optional, not found; needed for {r.dep.feature}",
                          _dep_fix(r, mgr, which)))

    # anchors
    if Path(install_py).exists():
        rc, text = run([sys.executable, str(install_py), "--check", "--json"])
        data = parse_json_output(text)
        if isinstance(data, dict) and (data.get("errors") or []):
            for e in data["errors"]:
                where = " · ".join(x for x in (e.get("file"), e.get("patch")) if x)
                out.append(Result("anchors", "Shell patch anchors", FAIL,
                                  tilde(f"{e.get('message', 'anchor not found')}"
                                        + (f" ({where})" if where else "")),
                                  e.get("hint") or "Check for an addons update, or open an issue"))
        elif isinstance(data, dict) and (data.get("ok") or rc == 0):
            out.append(Result("anchors", "Shell patch anchors", OK, "all patches apply"))
        elif rc == 3:
            out.append(Result("anchors", "Shell patch anchors", WARN, "another install is running (locked)"))
        else:
            out.append(Result("anchors", "Shell patch anchors", WARN,
                              f"could not run the check (exit {rc})",
                              "Run: python3 install.py --check"))

    # tokens service (warn only)
    if inst and "tokens" not in without and which("systemctl"):
        rc, text = run(["systemctl", "--user", "is-active", "serpantinum-tokens.service"])
        state = text.strip().splitlines()[0] if text.strip() else "unknown"
        out.append(Result("tokens", "AI Tokens service",
                          OK if rc == 0 else WARN, state,
                          "" if rc == 0 else "Run: systemctl --user enable --now serpantinum-tokens.service"))

    # quickshell running
    rc, _ = run(["pgrep", "-x", "quickshell"]) if which("pgrep") else (1, "")
    out.append(Result("running", "Quickshell running", OK if rc == 0 else WARN,
                      "yes" if rc == 0 else "no",
                      "" if rc == 0 else "Start your session, or reload with: serpantinum reload"))

    # latest addons release
    if network:
        try:
            r = rel.latest_release()
            if r:
                out.append(Result("release", "Latest addons release", OK,
                                  f"{r.get('tag')} (this checkout: {local_version()})"))
            else:
                out.append(Result("release", "Latest addons release", OK, "none published yet"))
        except Exception as e:
            out.append(Result("release", "Latest addons release", WARN,
                              str(e) or e.__class__.__name__, "Check your connection and retry"))
    return out


def _dep_fix(r, mgr, which) -> str:
    plan = D.build_plan([r], mgr, which)
    if plan.commands:
        return "Run: " + " && ".join(D.format_command(c) for c in plan.commands)
    if plan.manual:
        return plan.manual[0][1]
    return ""


def summary(results) -> tuple:
    return (sum(r.status == OK for r in results),
            sum(r.status == WARN for r in results),
            sum(r.status == FAIL for r in results))


def environment_info(rel=None, run=None, which=None) -> dict:
    rel = rel or release()
    run = run or _run
    which = which or shutil.which
    ss = rel.serpantinum_state()
    inst = rel.read_install_state() or {}
    hypr = None
    if which("hyprctl"):
        hypr = D.parse_hyprland_version(run(["hyprctl", "version"])[1])
    if not hypr and which("Hyprland"):
        hypr = D.parse_hyprland_version(run(["Hyprland", "--version"])[1])
    return {
        "addons": local_version(),
        "installed": inst.get("version") or "none",
        "channel": inst.get("channel") or "-",
        "serpantinum": ss.get("version") or "not found",
        "commit": ss.get("commit") or "-",
        "hyprland": hypr or "unknown",
        "os": os_pretty_name(),
        "python": platform.python_version(),
    }


def report_markdown(results, info=None) -> str:
    """Paste-ready block for a GitHub issue (home paths are replaced by ~)."""
    info = info or environment_info()
    mark = {OK: "ok", WARN: "warn", FAIL: "FAIL"}
    lines = [
        "<details><summary>Serpantinum Addons doctor report</summary>",
        "",
        f"- Addons checkout: {info['addons']} (installed: {info['installed']}, channel: {info['channel']})",
        f"- Serpantinum: {info['serpantinum']} ({info['commit']})",
        f"- Hyprland: {info['hyprland']}",
        f"- OS: {info['os']}",
        f"- Python: {info['python']}",
        "",
        "| Check | Status | Detail |",
        "| --- | --- | --- |",
    ]
    for r in results:
        detail = r.detail + (f" → {r.fix}" if r.fix and r.status != OK else "")
        lines.append("| {} | {} | {} |".format(
            tilde(r.title), mark.get(r.status, r.status),
            tilde(detail).replace("|", "\\|").replace("\n", " ")))
    lines += ["", "</details>"]
    return "\n".join(lines)
