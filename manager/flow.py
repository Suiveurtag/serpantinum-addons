"""Install / update / reinstall / uninstall / doctor flows."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import traceback
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from . import ISSUES_URL, REPO_ROOT, SERPANTINUM_INSTALL_URL, SERPANTINUM_URL, local_version, release
from . import deps as D
from . import doctor as DR
from .tui import UI

ACTIONS = ("install", "update", "reinstall", "uninstall", "doctor")
ADDONS = [
    ("clawd", "Clawd", "desktop pet with chat"),
    ("capri", "Capri", "AI assistant"),
    ("halloween", "Halloween", "seasonal effects"),
    ("tokens", "AI Tokens", "usage collector"),
    ("beamer", "Beamer", "KVM mouse/keyboard sharing"),
]
REEXEC_ENV = "ADDONS_REEXEC"
INSTALL_TIMEOUT = 900


class Cancelled(Exception):
    pass


class Fail(Exception):
    """An expected failure: shown as what / why / hint, never as a traceback."""

    def __init__(self, what, why="", hint="", code=1):
        super().__init__(what)
        self.what, self.why, self.hint, self.code = what, why, hint, code


# ---------------------------------------------------------------- paths / log
def managed_source() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "serpantinum-addons-v2" / "source"


def is_managed_source(root=None) -> bool:
    try:
        return Path(root or REPO_ROOT).resolve() == managed_source().resolve()
    except OSError:
        return False


class Log:
    def __init__(self, action, rel=None, now=None):
        rel = rel or release()
        stamp = (now or datetime.now()).strftime("%Y%m%d-%H%M%S")
        self.path = rel.state_dir() / "logs" / f"{stamp}-{action}.log"
        self._started = False

    def write(self, text: str) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(text)
            self._started = True
        except OSError:
            pass

    @property
    def shown(self) -> str:
        return DR.tilde(self.path)


def _run_proc(argv, cwd=None, timeout=INSTALL_TIMEOUT):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s"
    except OSError as e:
        return 127, str(e)


def download_script(url, dest, timeout=30):
    """Fetch a shell script to `dest`; refuse anything that is not a script (e.g. an HTML error page)."""
    req = urllib.request.Request(url, headers={"User-Agent": "serpantinum-addons-v2-installer"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    if not data.startswith(b"#!"):
        raise OSError("the downloaded file is not a shell script")
    Path(dest).write_bytes(data)


@dataclass
class Ctx:
    ui: UI
    args: object
    rel: object
    log: Log
    run: object = _run_proc
    probe: object = None
    call: object = subprocess.call      # interactive commands: they own the terminal (sudo, package manager, installers)
    fetch: object = download_script
    phase: str = "prepare"  # prepare | installing

    def step_run(self, label, argv, cwd=None):
        """Run argv under a spinner, full output goes to the log."""
        self.log.write(f"$ {D.format_command(argv)}\n")
        with self.ui.spinner(label):
            rc, out = self.run(argv, cwd)
        self.log.write(out + f"\n[exit {rc}]\n\n")
        return rc, out


# ---------------------------------------------------------------- menu logic
def menu_options(installed: bool, newer=None, focus=None, reinstall_needed=False):
    """-> (options [(key, label)], default index)."""
    if not installed:
        opts = [("install", "Install Serpantinum Addons"), ("doctor", "Diagnose problems"),
                ("exit", "Exit")]
    else:
        opts = []
        if newer:
            opts.append(("update", f"Update to v{str(newer).lstrip('v')}"))
        opts += [("reinstall", "Reinstall (re-apply the patches)"), ("uninstall", "Uninstall"),
                 ("doctor", "Diagnose problems"), ("exit", "Exit")]
    keys = [k for k, _ in opts]
    if focus in keys:
        return opts, keys.index(focus)
    if installed and reinstall_needed:
        return opts, keys.index("reinstall")
    return opts, 0


def rebuild_args(args, action) -> list:
    out = [action]
    if getattr(args, "yes", False):
        out.append("--yes")
    if getattr(args, "ref", None):
        out += ["--ref", args.ref]
    if getattr(args, "purge", False):
        out.append("--purge")
    return out


# ---------------------------------------------------------------- preflight
@dataclass
class Pre:
    ss: dict
    compat: dict
    compat_status: str
    inst: object
    deps: list = field(default_factory=list)
    release: dict = field(default_factory=dict)
    release_error: object = None
    newer: object = None
    reinstall_needed: bool = False

    @property
    def installed(self) -> bool:
        return bool(self.inst)

    @property
    def current(self):
        return (self.inst or {}).get("version")


def quick_state(ctx):
    rel = ctx.rel
    ss = rel.serpantinum_state()
    compat = rel.load_compat()
    inst = rel.read_install_state()
    return ss, compat, rel.compat_status(ss.get("version"), compat), inst


def preflight(ctx) -> Pre:
    rel = ctx.rel
    ss, compat, cstat, inst = quick_state(ctx)
    pre = Pre(ss, compat, cstat, inst)
    with ctx.ui.spinner("Checking your system"):
        pre.deps = D.check_all(ctx.probe, compat)
        try:
            pre.release = rel.latest_release() or {}
        except Exception as e:
            pre.release_error = str(e) or e.__class__.__name__
    base = pre.current or local_version()
    if pre.release and rel.compare(pre.release.get("version"), base) > 0:
        pre.newer = pre.release.get("version")
    if inst:
        pre.reinstall_needed = (inst.get("serpantinum_version") != ss.get("version")
                                or inst.get("serpantinum_commit") != ss.get("commit"))
    return pre


def show_header(ctx, pre):
    target = pre.newer or local_version()
    ctx.ui.header(pre.current, target, pre.ss.get("version"), pre.compat_status)


def show_preflight(ctx, pre):
    ui = ctx.ui
    ui.step("Preflight")
    sv = pre.ss.get("version")
    if sv:
        kind = "ok" if pre.compat_status == "ok" else "warn"
        ui.child(f"Serpantinum {sv} (compatibility: {pre.compat_status.replace('_', ' ')})",
                 None if kind == "ok" else "warn")
    else:
        ui.child("Serpantinum not found: its installer will run first", "warn")
    req = [r for r in pre.deps if r.dep.required]
    miss = D.missing(req)
    opt_miss = D.missing(pre.deps, required=False)
    line = f"Dependencies: {len(req) - len(miss)}/{len(req)} required present"
    if opt_miss:
        line += f", {len(opt_miss)} optional missing"
    ui.child(line, "warn" if miss else None)
    if pre.release_error:
        ui.child(f"Latest release: unavailable ({pre.release_error})", "warn")
    elif not pre.release:
        ui.child("Latest release: none published yet", "dim")
    elif pre.newer:
        ui.child(f"Latest release: {pre.release.get('tag')} (newer than your v{pre.current or local_version()})")
    else:
        ui.child(f"Latest release: {pre.release.get('tag')} (you are up to date)")
    if pre.reinstall_needed:
        ui.child("Serpantinum changed since the addons were installed: reinstall recommended", "warn")


# ---------------------------------------------------------------- helpers
def install_serpantinum(ctx, pre):
    """Run Serpantinum's own (interactive) installer, then refresh what preflight knew."""
    ui = ctx.ui
    ui.step("Serpantinum is not installed: running its installer")
    ui.child(SERPANTINUM_INSTALL_URL, "dim")
    if not ui.interactive:
        raise Fail("Serpantinum is not installed",
                   "Its installer is interactive and needs a terminal.",
                   f"Run it from a terminal ({SERPANTINUM_URL}), then run this again.")
    with tempfile.TemporaryDirectory(prefix="serpantinum-installer-") as tmp:
        script = Path(tmp) / "install.sh"
        ctx.log.write(f"download {SERPANTINUM_INSTALL_URL}\n")
        try:
            with ui.spinner("Downloading the Serpantinum installer"):
                ctx.fetch(SERPANTINUM_INSTALL_URL, script)
        except (OSError, ValueError) as e:  # URLError and HTTPError are OSError
            raise Fail("Could not download the Serpantinum installer", DR.tilde(e) or e.__class__.__name__,
                       f"Check your connection, or install Serpantinum yourself: {SERPANTINUM_URL}")
        ui.hint("Handing the terminal over to the Serpantinum installer")
        ui.println()
        ctx.log.write(f"$ bash {script}   (interactive)\n")
        ctx.phase = "installing"
        try:
            rc = ctx.call(["bash", str(script)])
        except OSError as e:
            rc = 127
            ctx.log.write(f"{e}\n")
        ctx.phase = "prepare"  # not reset on Ctrl-C: run() then reports an interrupted change
        ctx.log.write(f"[exit {rc}]\n\n")
    if rc != 0:
        raise Fail("The Serpantinum installer did not finish", f"It exited with {rc}.",
                   "Fix the error shown above (or run it yourself, see the Serpantinum README), then run this again.")
    pre.ss, pre.compat, pre.compat_status, _ = quick_state(ctx)
    pre.deps = D.check_all(ctx.probe, pre.compat)  # it may have installed some of our dependencies too
    if not pre.ss.get("version"):
        raise Fail("Serpantinum was not found after its installer ran",
                   "Neither ~/.local/state/serpantinum/version nor ~/.local/share/serpantinum exists.",
                   f"Install it yourself ({SERPANTINUM_URL}), then run this again.")
    ui.status("ok", f"Serpantinum {pre.ss['version']} installed")


def require_serpantinum(ctx, pre):
    if not pre.ss.get("version"):
        install_serpantinum(ctx, pre)
    sv = pre.ss.get("version")
    if pre.compat_status == "too_old":
        mn = (pre.compat.get("serpantinum") or {}).get("min")
        raise Fail(f"Serpantinum {sv} is too old", f"These addons need Serpantinum {mn} or newer.",
                   "Update Serpantinum first, then run this again.", code=2)
    if pre.compat_status == "newer_than_tested":
        tested = (pre.compat.get("serpantinum") or {}).get("tested")
        ctx.ui.status("warn", f"Serpantinum {sv} is newer than the tested {tested}; continuing")


# Dependencies only some addons use: skipped when none of those addons is selected.
DEP_ADDONS = {"node": {"clawd", "capri"}}


def ensure_deps(ctx, pre, without=()):
    """Install the missing system tools. Never fatal: a tool that stays missing only disables the feature that needs it."""
    ui = ctx.ui
    left_out = set(without)
    def relevant(results):
        return [r for r in results if not (r.dep.id in DEP_ADDONS and DEP_ADDONS[r.dep.id] <= left_out)]

    needed = relevant(pre.deps)
    miss_req = D.missing(needed, required=True)
    miss_opt = D.missing(needed, required=False)
    which = getattr(ctx.probe, "which", None)
    mgr = D.detect_package_manager(which)
    if miss_opt:
        ui.step("Optional tools not found")
        for r in miss_opt:
            ui.child(f"{r.dep.label}: needed for {r.dep.feature}", "dim")
            how = D.build_plan([r], mgr, which)
            for argv in how.commands:
                ui.child("→ " + D.format_command(argv), "dim")
            for _, text in how.manual:
                ui.child("→ " + text, "dim")
        ui.child("Installed just now? Open a new terminal if it is still reported missing.", "dim")
    if not miss_req:
        return
    ui.step("Missing required dependencies")
    for r in miss_req:
        ui.child(f"{r.dep.label} ({r.detail or r.status}): needed for {r.dep.feature}", "warn")
    if mgr is None:
        ui.status("warn", "No supported package manager (pacman, dnf, xbps-install): continuing without these")
        ui.child("Install by hand: " + ", ".join(r.dep.label for r in miss_req), "dim")
        return
    plan = D.build_plan(miss_req, mgr, which)
    for dep, how in plan.manual:
        ui.child(f"{dep.label}: {how}", "warn")
    if plan.commands:
        ui.println()
        ui.step("Installing the missing dependencies")
        ui.hint("sudo asks for your password; the package manager asks for its own confirmation.")
        for argv in plan.commands:
            ui.println("    " + ui.paint("$ " + D.format_command(argv), "accent"))
            ctx.log.write(f"$ {D.format_command(argv)}   (interactive)\n")
            ctx.phase = "installing"
            try:
                rc = ctx.call(argv)
            except OSError as e:
                rc = 127
                ctx.log.write(f"{e}\n")
            ctx.phase = "prepare"  # not reset on Ctrl-C: run() then reports an interrupted change
            ctx.log.write(f"[exit {rc}]\n\n")
            if rc != 0:
                ui.status("warn", f"{D.format_command(argv)} exited with {rc}: continuing without these")
                break
        pre.deps = D.check_all(ctx.probe, pre.compat)
        miss_req = D.missing(relevant(pre.deps), required=True)
        if not miss_req:
            ui.status("ok", "Dependencies installed")
            return
    ui.status("warn", "Continuing: the addons are installed, but some features stay off until these are installed")
    for r in miss_req:
        ui.child(f"{r.dep.label}: {r.dep.feature}", "warn")
    ui.child("Install them, then run `python3 addons.py doctor` to check.", "dim")


def choose_addons(ctx, pre) -> list:
    """Returns the list of addon ids to leave out."""
    without_saved = set((pre.inst or {}).get("without") or [])
    options = [(aid, name, aid not in without_saved, hint) for aid, name, hint in ADDONS]
    if getattr(ctx.args, "yes", False):
        chosen = [o[0] for o in options if o[2]]
    else:
        chosen = ctx.ui.multiselect("Which addons do you want?", options)
        if chosen is None:
            raise Cancelled()
    return [aid for aid, _, _ in ADDONS if aid not in chosen]


def install_py_argv(*flags) -> list:
    return [sys.executable, str(REPO_ROOT / "install.py"), *flags]


def count_changes(data) -> int:
    ch = (data or {}).get("changes")
    if isinstance(ch, (list, tuple, dict)):
        return len(ch)
    return ch if isinstance(ch, int) else 0


def last_lines(text, n=4) -> str:
    lines = [l for l in (text or "").strip().splitlines() if l.strip()]
    return "\n".join(lines[-n:])


def fail_from_install(ctx, rc, out, data, what):
    """Show install.py errors (✗ / why / → hint) and raise Fail."""
    ui = ctx.ui
    if rc == 3:
        raise Fail("Another installation is already running", "install.py holds a lock.",
                   "Wait for it to finish, then retry.", code=3)
    errors = (data or {}).get("errors") or []
    if errors:
        ui.println()
        for e in errors:
            where = " · ".join(x for x in (e.get("file"), e.get("patch")) if x)
            ui.error(e.get("message") or "Patch could not be applied", DR.tilde(where),
                     e.get("hint") or "")
        ui.println()
        raise Fail(f"{what}: {len(errors)} problem(s) found" + (", nothing was changed" if rc == 2 else ""),
                   "The Serpantinum files differ from what these addons expect.",
                   "Run `python3 addons.py doctor`; check for an addons update or report it.",
                   code=2 if rc == 2 else 1)
    raise Fail(what, DR.tilde(last_lines(out)) or f"install.py exited with {rc}.",
               "See the log for the full output, then retry.", code=2 if rc == 2 else 1)


def offer_reload(ctx):
    ui = ctx.ui
    if not shutil.which("serpantinum"):
        ui.hint("Reload the shell to apply: serpantinum reload")
        return
    if not (getattr(ctx.args, "yes", False) or ui.confirm("Reload the shell now?", True)):
        ui.hint("Reload later with: serpantinum reload")
        return
    rc, out = ctx.step_run("Reloading the shell", ["serpantinum", "reload"])
    if rc == 0:
        ui.status("ok", "Shell reloaded")
    else:
        ui.status("warn", "Reload failed; run it yourself: serpantinum reload")


# ---------------------------------------------------------------- update (source checkout)
def update_source(ctx, pre) -> bool:
    """Move the managed source to the target release. Returns False when finished early."""
    ui = ctx.ui
    if os.environ.get(REEXEC_ENV) == "1":
        return True  # already running the new code
    ref = getattr(ctx.args, "ref", None)
    if not ref:
        if pre.release_error:
            raise Fail("Could not look up the latest release", pre.release_error,
                       "Check your connection and retry, or pick a version with --ref vX.Y.Z.")
        if not pre.newer:
            ui.status("ok", f"Already up to date (v{pre.current or local_version()})")
            return False
        ref = pre.release.get("tag")
    if not is_managed_source():
        ui.status("warn", "This is a development checkout, not the managed source.")
        ui.child("Update it yourself with: git pull", "dim")
        return ui.confirm("Reinstall from this checkout now?", True) if not ctx.args.yes else True
    src = managed_source()
    rc, out = ctx.step_run("Checking the source checkout", ["git", "-C", str(src), "status", "--porcelain"])
    if rc != 0:
        raise Fail("The source checkout is not usable", DR.tilde(last_lines(out)),
                   f"Delete {DR.tilde(src)} and run the one-line install command again.")
    if out.strip():
        raise Fail("The source checkout has local changes", DR.tilde(last_lines(out)),
                   f"Keep the changes: git -C {DR.tilde(src)} stash push -u (restore later with git stash pop). Or discard them: git -C {DR.tilde(src)} reset --hard && git -C {DR.tilde(src)} clean -fd")
    rc, out = ctx.step_run("Fetching releases", ["git", "-C", str(src), "fetch", "--tags", "--prune"])
    if rc != 0:
        raise Fail("Could not fetch the releases", DR.tilde(last_lines(out)) or "git fetch failed.",
                   "Check your connection and retry.")
    target = None
    for cand in (f"refs/tags/{ref}", f"refs/tags/v{ref.lstrip('v')}", f"origin/{ref}", ref):
        rc, out = ctx.run(["git", "-C", str(src), "rev-parse", "--verify", "--quiet", cand + "^{commit}"], None)
        if rc == 0:
            target = cand
            break
    if not target:
        raise Fail(f"Unknown version {ref}", "It is neither a release tag nor a branch.",
                   "List versions with: git -C " + DR.tilde(src) + " tag")
    rc, out = ctx.step_run(f"Checking out {ref}", ["git", "-C", str(src), "checkout", "--detach", target])
    if rc != 0:
        raise Fail(f"Could not check out {ref}", DR.tilde(last_lines(out)), "See the log, then retry.")
    ui.status("ok", f"Source updated to {ref}")
    ui.hint("Restarting from the new version")
    env = dict(os.environ, **{REEXEC_ENV: "1"})
    new_main = src / "addons.py"
    ctx.log.write(f"exec {sys.executable} {new_main} {rebuild_args(ctx.args, 'update')}\n")
    try:
        os.execve(sys.executable, [sys.executable, str(new_main), *rebuild_args(ctx.args, "update")], env)
    except OSError as e:
        raise Fail("Could not restart from the new version", str(e), "Run the update again.")
    return True  # pragma: no cover


# ---------------------------------------------------------------- actions
def action_install(ctx, mode, pre):
    ui = ctx.ui
    require_serpantinum(ctx, pre)
    if mode == "update" and not pre.installed:
        ui.status("warn", "Addons are not installed yet; installing instead")
        mode = "install"
    if mode == "update":
        if not update_source(ctx, pre):
            return 0
    without = choose_addons(ctx, pre)
    ensure_deps(ctx, pre, without)
    flags = [f"--without-{a}" for a in without]
    ctx.phase = "prepare"
    rc, out = ctx.step_run("Checking the shell can be patched", install_py_argv(*flags, "--check", "--json"))
    data = DR.parse_json_output(out)
    if rc != 0 or (isinstance(data, dict) and data.get("errors")):
        fail_from_install(ctx, rc, out, data, "The shell cannot be patched")
    ui.status("ok", "All patches apply")
    ctx.phase = "installing"
    label = {"install": "Installing", "update": "Updating", "reinstall": "Reinstalling"}[mode]
    rc, out = ctx.step_run(f"{label} the addons", install_py_argv(*flags, "--json"))
    data = DR.parse_json_output(out)
    if rc != 0 or (isinstance(data, dict) and data.get("ok") is False):
        fail_from_install(ctx, rc, out, data, f"{label} failed")
    n = count_changes(data)
    done = {"install": "installed", "update": "updated", "reinstall": "reinstalled"}[mode]
    ui.println()
    ui.celebrate(f"Serpantinum Addons v{local_version()} {done}")
    ui.child(f"{n} file(s) changed" if n else "no file needed changes (already up to date)")
    if without:
        ui.child("left out: " + ", ".join(without), "dim")
    ui.child(f"log: {ctx.log.shown}", "dim")
    ctx.phase = "prepare"
    offer_reload(ctx)
    return 0


def action_uninstall(ctx, pre):
    ui = ctx.ui
    ui.step("Uninstall Serpantinum Addons")
    ui.child("Removes: the addon patches in your Serpantinum shell (originals are restored).")
    ui.child("Keeps: Serpantinum itself, backups, the source checkout and addon data.")
    purge = bool(getattr(ctx.args, "purge", False))
    if not purge and not ctx.args.yes:
        sel = ui.multiselect("Extra cleanup", [("purge", "Also delete addon data (token history, Capri/Clawd state)", False)])
        if sel is None:
            raise Cancelled()
        purge = "purge" in sel
    if not ctx.args.yes and not ui.confirm(
            "Uninstall now" + (" and delete addon data" if purge else "") + "?", False):
        raise Cancelled()
    ctx.phase = "installing"
    argv = install_py_argv("--uninstall", *(["--purge"] if purge else []), "--json")
    rc, out = ctx.step_run("Uninstalling", argv)
    data = DR.parse_json_output(out)
    if rc != 0 or (isinstance(data, dict) and data.get("ok") is False):
        fail_from_install(ctx, rc, out, data, "Uninstall failed")
    ctx.phase = "prepare"
    ui.println()
    ui.status("ok", "Serpantinum Addons uninstalled" + (" (addon data deleted)" if purge else ""))
    ui.child(f"log: {ctx.log.shown}", "dim")
    ui.child("To also remove the source checkout: rm -rf " + DR.tilde(managed_source().parent), "dim")
    offer_reload(ctx)
    return 0


def action_doctor(ctx):
    ui = ctx.ui
    if getattr(ctx.args, "report", False):
        results = DR.run_checks(ctx.rel, probe=ctx.probe)
        ui.println(DR.report_markdown(results))
        return 1 if any(r.status == DR.FAIL for r in results) else 0
    with ui.spinner("Running checks"):
        results = DR.run_checks(ctx.rel, probe=ctx.probe)
    ui.step("Doctor")
    for r in results:
        kind = {DR.OK: "ok", DR.WARN: "warn", DR.FAIL: "err"}[r.status]
        ui.status(kind, f"{r.title}: {r.detail}" if r.detail else r.title)
        if r.fix and r.status != DR.OK:
            ui.println(ui.paint("    → " + r.fix, "accent"))
    ok, warn, bad = DR.summary(results)
    ui.println()
    ui.status("err" if bad else "warn" if warn else "ok", f"{ok} ok · {warn} warning(s) · {bad} problem(s)")
    ui.hint("Paste this in an issue: python3 addons.py doctor --report")
    return 1 if bad else 0


def interactive(ctx):
    ui = ctx.ui
    pre = preflight(ctx)
    show_header(ctx, pre)
    show_preflight(ctx, pre)
    ui.println()
    opts, default = menu_options(pre.installed, pre.newer, ctx.args.focus, pre.reinstall_needed)
    choice = ui.select("What would you like to do?", opts, default)
    if choice is None or choice == "exit":
        raise Cancelled()
    return dispatch(ctx, choice, pre)


def dispatch(ctx, action, pre=None):
    if action == "doctor":
        return action_doctor(ctx)
    if pre is None:
        pre = preflight(ctx)
    if action in ("install", "update", "reinstall"):
        return action_install(ctx, action, pre)
    if action == "uninstall":
        return action_uninstall(ctx, pre)
    raise Fail(f"Unknown action {action}")


def run(args, ui=None) -> int:
    rel = release()
    ui = ui or UI()
    action = args.action
    log = Log(action or "menu", rel)
    ctx = Ctx(ui, args, rel, log)
    try:
        if action is None:
            return interactive(ctx)
        if action != "doctor" and not getattr(args, "report", False):
            pre = preflight(ctx)
            show_header(ctx, pre)
            return dispatch(ctx, action, pre)
        return dispatch(ctx, action)
    except (KeyboardInterrupt, Cancelled) as e:
        ui.println()
        if ctx.phase == "installing":
            ui.status("warn", "Interrupted while changing files")
            ui.child("Run `python3 addons.py doctor` to check the state, then reinstall if needed.", "dim")
        else:
            ui.status("warn", "Cancelled, nothing changed")
        return 130 if isinstance(e, KeyboardInterrupt) else 0
    except Fail as f:
        log.write(f"FAIL: {f.what}\n{f.why}\n{f.hint}\n")
        ui.println()
        ui.error(f.what, f.why, f.hint, log.shown, ISSUES_URL)
        return f.code
    except Exception as e:
        log.write(traceback.format_exc())
        ui.println()
        ui.error("Something unexpected happened", f"{e.__class__.__name__}: {DR.tilde(e)}",
                 "Please report it and attach the log file.", log.shown, ISSUES_URL)
        return 1
    finally:
        if ui.animated:
            ui.write("\x1b[?25h")
