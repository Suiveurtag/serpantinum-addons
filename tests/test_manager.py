"""Offline tests for the terminal manager (no installs, no network)."""
from __future__ import annotations

import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import addons  # noqa: E402
from manager import deps as D  # noqa: E402
from manager import doctor as DR  # noqa: E402
from manager import flow as F  # noqa: E402
from manager import tui  # noqa: E402


def make_ui(columns=80, tty=False, environ=None, stdin=""):
    out = io.StringIO()
    ui = tui.UI(out=out, inp=io.StringIO(stdin), environ=environ if environ is not None else {},
                isatty=tty, columns=columns)
    return ui, out


class ArgParsing(unittest.TestCase):
    def test_actions(self):
        for a in addons.ACTIONS:
            self.assertEqual(addons.parse_args([a]).action, a)
        self.assertIsNone(addons.parse_args([]).action)

    def test_flags(self):
        a = addons.parse_args(["update", "--yes", "--ref", "v2.0.0"])
        self.assertTrue(a.yes)
        self.assertEqual(a.ref, "v2.0.0")
        self.assertEqual(addons.parse_args(["--focus", "uninstall"]).focus, "uninstall")

    def test_report_implies_doctor(self):
        self.assertEqual(addons.parse_args(["--report"]).action, "doctor")

    def test_invalid(self):
        for argv in (["bogus"], ["--yes"], ["install", "--purge"], ["install", "--report"]):
            with self.assertRaises(SystemExit), unittest.mock.patch("sys.stderr", io.StringIO()):
                addons.parse_args(argv)


class MenuOptions(unittest.TestCase):
    def keys(self, *a, **k):
        opts, default = F.menu_options(*a, **k)
        return [k for k, _ in opts], default, dict(opts)

    def test_not_installed(self):
        keys, default, _ = self.keys(False, "2.1.0")
        self.assertEqual(keys, ["install", "doctor", "exit"])
        self.assertEqual(default, 0)

    def test_installed_with_update(self):
        keys, _, labels = self.keys(True, "2.1.0")
        self.assertEqual(keys, ["update", "reinstall", "uninstall", "doctor", "exit"])
        self.assertEqual(labels["update"], "Update to v2.1.0")

    def test_installed_without_update(self):
        keys, _, _ = self.keys(True, None)
        self.assertNotIn("update", keys)
        self.assertEqual(keys[0], "reinstall")

    def test_focus_preselects(self):
        keys, default, _ = self.keys(True, None, focus="uninstall")
        self.assertEqual(keys[default], "uninstall")

    def test_focus_ignored_when_unavailable(self):
        keys, default, _ = self.keys(False, None, focus="uninstall")
        self.assertEqual(default, 0)

    def test_reinstall_needed_defaults_to_reinstall(self):
        keys, default, _ = self.keys(True, "2.1.0", reinstall_needed=True)
        self.assertEqual(keys[default], "reinstall")

    def test_rebuild_args(self):
        a = addons.parse_args(["update", "--yes", "--ref", "main"])
        self.assertEqual(F.rebuild_args(a, "update"), ["update", "--yes", "--ref", "main"])


class ColorMode(unittest.TestCase):
    def test_no_color(self):
        self.assertEqual(tui.detect_color_mode({"NO_COLOR": "1", "COLORTERM": "truecolor"}, True), "none")

    def test_not_a_tty(self):
        self.assertEqual(tui.detect_color_mode({"COLORTERM": "truecolor"}, False), "none")

    def test_truecolor(self):
        for v in ("truecolor", "24bit"):
            self.assertEqual(tui.detect_color_mode({"COLORTERM": v}, True), "truecolor")

    def test_256(self):
        self.assertEqual(tui.detect_color_mode({"TERM": "xterm-256color"}, True), "256")

    def test_dumb(self):
        self.assertEqual(tui.detect_color_mode({"TERM": "dumb"}, True), "none")

    def test_paint_codes(self):
        ui, _ = make_ui(tty=True, environ={"COLORTERM": "truecolor"})
        self.assertIn("38;2;250;179;135", ui.paint("x", "accent"))
        ui, _ = make_ui(tty=True, environ={"TERM": "xterm"})
        self.assertIn("38;5;216", ui.paint("x", "accent"))
        ui, _ = make_ui(tty=False)
        self.assertEqual(ui.paint("x", "accent", bold=True), "x")


class Header(unittest.TestCase):
    def render(self, columns):
        ui, out = make_ui(columns=columns, tty=True, environ={"COLORTERM": "truecolor"})
        ui.header("2.0.0", "2.1.0", "2.3.2", "ok")
        return [tui.strip_ansi(l) for l in out.getvalue().splitlines() if l.strip()]

    def test_wide(self):
        lines = self.render(200)
        self.assertTrue(lines[0].startswith("╭") and lines[0].endswith("╮"))
        self.assertTrue(lines[-1].startswith("╰") and lines[-1].endswith("╯"))
        self.assertTrue(any("serpantinum addons" in l for l in lines))
        self.assertTrue(any("2.0.0 → 2.1.0" in l for l in lines))
        self.assertEqual(len({len(l) for l in lines}), 1)
        self.assertLessEqual(len(lines[0]), tui.MAX_BOX)

    def test_narrow(self):
        for cols in (40, 24, 16):
            lines = self.render(cols)
            self.assertEqual(len({len(l) for l in lines}), 1, cols)
            self.assertLessEqual(len(lines[0]), max(cols, tui.MIN_BOX))

    def test_not_installed_label(self):
        ui, out = make_ui(columns=80)
        ui.header(None, "2.0.0", "2.3.2", "ok")
        self.assertIn("not installed → 2.0.0", out.getvalue())
        self.assertNotIn("\x1b", out.getvalue())


class Steps(unittest.TestCase):
    def test_step_child_status(self):
        ui, out = make_ui()
        ui.step("Title")
        ui.child("detail")
        ui.status("ok", "good")
        ui.status("warn", "hmm")
        ui.status("err", "bad")
        self.assertEqual(out.getvalue().splitlines(),
                         ["◆ Title", "  ›  detail", "✓ good", "! hmm", "✗ bad"])

    def test_spinner_static_without_tty(self):
        ui, out = make_ui()
        with ui.spinner("Working") as sp:
            sp.done("ok", "done")
        self.assertEqual(out.getvalue().splitlines(), ["◆ Working…", "✓ done"])

    def test_decode_keys(self):
        self.assertEqual(tui.decode_key(b"\x1b[A"), "up")
        self.assertEqual(tui.decode_key(b"\x1b[B"), "down")
        self.assertEqual(tui.decode_key(b"\x1b"), "esc")
        self.assertEqual(tui.decode_key(b"\r"), "enter")
        self.assertEqual(tui.decode_key(b" "), "space")
        self.assertEqual(tui.decode_key(b"j"), "j")
        with self.assertRaises(KeyboardInterrupt):
            tui.decode_key(b"\x03")


class NumberedFallback(unittest.TestCase):
    OPTS = [("a", "Alpha"), ("b", "Beta"), ("c", "Gamma")]

    def test_select_default_and_choice(self):
        ui, _ = make_ui(stdin="\n")
        self.assertEqual(ui.select("t", self.OPTS, 1), "b")
        ui, _ = make_ui(stdin="9\n3\n")
        self.assertEqual(ui.select("t", self.OPTS), "c")

    def test_select_quit_and_eof(self):
        ui, _ = make_ui(stdin="q\n")
        self.assertIsNone(ui.select("t", self.OPTS))
        ui, _ = make_ui(stdin="")
        self.assertIsNone(ui.select("t", self.OPTS))

    def test_multiselect(self):
        opts = [("a", "A", True), ("b", "B", False), ("c", "C", True)]
        ui, _ = make_ui(stdin="\n")
        self.assertEqual(ui.multiselect("t", opts), ["a", "c"])
        ui, _ = make_ui(stdin="2\n")
        self.assertEqual(ui.multiselect("t", opts), ["b"])
        ui, _ = make_ui(stdin="none\n")
        self.assertEqual(ui.multiselect("t", opts), [])

    def test_confirm(self):
        for text, default, want in (("\n", True, True), ("\n", False, False), ("y\n", False, True),
                                    ("n\n", True, False), ("", True, True)):
            ui, _ = make_ui(stdin=text)
            self.assertEqual(ui.confirm("ok?", default), want, (text, default))


class FakeSystem:
    def __init__(self, present=(), outputs=None, rc=None, modules=("PIL",)):
        self.present = set(present)
        self.outputs = outputs or {}
        self.rc = rc or {}
        self.modules = set(modules)

    def probe(self):
        def which(n):
            return f"/usr/bin/{n}" if n in self.present else None

        def run(argv, timeout=8):
            key = " ".join(argv)
            return self.rc.get(key, 0), self.outputs.get(key, "")

        return D.Probe(which=which, run=run, has_module=lambda m: m in self.modules)


ALL_CMDS = ["python3", "jq", "matugen", "node", "grim", "wl-copy", "udevadm", "systemctl",
            "nmcli", "resolvectl", "hyprctl", "quickshell", "codex", "ollama"]
HYPR_057 = "Hyprland 0.57.0 built from branch v0.57.0 at commit abc clean\nTag: v0.57.0"


def healthy():
    return FakeSystem(
        ALL_CMDS,
        {"hyprctl version": HYPR_057, "python3 --version": "Python 3.12.1",
         "quickshell --version": "Quickshell 0.3.0, revision x"})


class Deps(unittest.TestCase):
    def results(self, system, compat=None):
        return {r.dep.id: r for r in D.check_all(system.probe(), compat)}

    def test_all_present(self):
        res = self.results(healthy())
        self.assertEqual([i for i, r in res.items() if not r.ok], [])

    def test_missing_detected(self):
        s = healthy()
        s.present -= {"jq", "ollama"}
        s.modules = set()
        res = self.results(s)
        self.assertEqual(res["jq"].status, "missing")
        self.assertEqual(res["pillow"].status, "missing")
        miss_req = {r.dep.id for r in D.missing(res.values(), required=True)}
        miss_opt = {r.dep.id for r in D.missing(res.values(), required=False)}
        self.assertEqual(miss_req, {"jq", "pillow"})
        self.assertEqual(miss_opt, {"ollama"})

    def test_hyprland_version_parse(self):
        self.assertEqual(D.parse_hyprland_version(HYPR_057), "0.57.0")
        self.assertEqual(D.parse_hyprland_version("Hyprland 0.55.1 built from branch"), "0.55.1")
        self.assertEqual(D.parse_hyprland_version("Tag: v0.54.2, commits: 1"), "0.54.2")
        self.assertIsNone(D.parse_hyprland_version("nothing here"))

    def test_hyprland_too_old(self):
        s = healthy()
        s.outputs["hyprctl version"] = "Hyprland 0.54.0 built from branch"
        r = self.results(s)["hyprland"]
        self.assertEqual((r.status, r.version), ("old", "0.54.0"))

    def test_hyprland_falls_back_to_binary(self):
        s = healthy()
        s.present.add("Hyprland")
        s.rc["hyprctl version"] = 1
        s.outputs["hyprctl version"] = "Couldn't connect"
        s.outputs["Hyprland --version"] = "Hyprland 0.56.0 built"
        r = self.results(s)["hyprland"]
        self.assertEqual((r.status, r.version), ("ok", "0.56.0"))

    def test_hyprland_min_from_compat(self):
        r = self.results(healthy(), {"hyprland_min": "0.60"})["hyprland"]
        self.assertEqual(r.status, "old")

    def test_quickshell_old(self):
        s = healthy()
        s.outputs["quickshell --version"] = "Quickshell 0.2.1"
        self.assertEqual(self.results(s)["quickshell"].status, "old")

    def test_systemd_user_session(self):
        s = healthy()
        s.rc["systemctl --user show-environment"] = 1
        self.assertEqual(self.results(s)["systemd-user"].status, "missing")

    def test_python_too_old(self):
        s = healthy()
        s.outputs["python3 --version"] = "Python 3.9.2"
        self.assertEqual(self.results(s)["python3"].status, "old")

    def test_detect_package_manager(self):
        for avail, want in ((["pacman", "dnf"], "pacman"), (["dnf"], "dnf"),
                            (["xbps-install"], "xbps"), ([], None)):
            self.assertEqual(D.detect_package_manager(lambda n, a=avail: n if n in a else None), want)

    def test_install_command_per_manager(self):
        miss = ["jq", "grim"]
        self.assertEqual(D.install_command(miss, "pacman"), ["sudo", "pacman", "-S", "--needed", "jq", "grim"])
        self.assertEqual(D.install_command(miss, "dnf"), ["sudo", "dnf", "install", "jq", "grim"])
        self.assertEqual(D.install_command(miss, "xbps"), ["sudo", "xbps-install", "-S", "jq", "grim"])
        self.assertEqual(D.install_command([], "pacman"), [])

    def test_no_noconfirm_anywhere(self):
        plan_all = []
        for m in D.MANAGERS:
            p = D.build_plan(D.DEPS, m, which=lambda n: None)
            plan_all += [a for c in p.commands for a in c]
        self.assertFalse([a for a in plan_all if "noconfirm" in a or a in ("-y", "--yes")])

    def test_packages_deduplicated(self):
        argv = D.install_command(["udevadm", "systemd-user", "resolved"], "pacman")
        self.assertEqual(argv.count("systemd"), 1)

    def test_aur_helper_and_manual(self):
        dep = D.Dep("x", "X", "cmd", "x", False, "f", {"pacman": "aur:x-bin"})
        plan = D.build_plan([dep], "pacman", which=lambda n: "/usr/bin/yay" if n == "yay" else None)
        self.assertEqual(plan.commands, [["yay", "-S", "--needed", "x-bin"]])
        plan = D.build_plan([dep], "pacman", which=lambda n: None)
        self.assertEqual(plan.commands, [])
        self.assertIn("AUR", plan.manual[0][1])
        self.assertEqual(D.install_command([dep], "pacman"), [])

    def test_copr_enabled_before_install(self):
        plan = D.build_plan(["matugen"], "dnf", which=lambda n: None)
        self.assertEqual(plan.commands[0], ["sudo", "dnf", "copr", "enable", "mecattaf/duoRPM"])
        self.assertEqual(plan.commands[1], ["sudo", "dnf", "install", "matugen"])

    def test_unpackaged_goes_manual(self):
        plan = D.build_plan(["codex"], "pacman", which=lambda n: None)
        self.assertEqual(plan.commands, [])
        self.assertIn("npm install -g @openai/codex", plan.manual[0][1])


class FakeRelease:
    """Stand-in for scripts/addons_release.py."""

    def __init__(self, sv="2.3.2", inst=None, up="2.3.2", latest=None, err=None):
        self.sv, self.inst, self.up, self.latest, self.err = sv, inst, up, latest or {}, err
        self._real = None

    def _r(self):
        from manager import release
        return release()

    def serpantinum_state(self):
        return {"version": self.sv, "commit": "68b0222", "home": "/x"}

    def load_compat(self):
        return {"serpantinum": {"min": "2.3.2", "tested": "2.3.2"}, "hyprland_min": "0.55"}

    def compat_status(self, v, c):
        return self._r().compat_status(v, c)

    def compare(self, a, b):
        return self._r().compare(a, b)

    def read_install_state(self):
        return self.inst

    def upstream_latest_version(self):
        return self.up

    def latest_release(self, force=False):
        if self.err:
            raise RuntimeError(self.err)
        return self.latest

    def state_dir(self):
        return Path(tempfile.gettempdir()) / "addons-test-state"


class Doctor(unittest.TestCase):
    def run_checks(self, rel=None, **kw):
        sys_ = healthy()
        rel = rel or FakeRelease()

        def run(argv, timeout=20):
            if "--check" in argv:
                return 0, '{"ok": true, "changes": [], "errors": []}'
            return 0, ""

        return DR.run_checks(rel, run=run, which=sys_.probe().which, probe=sys_.probe(), **kw)

    def by_id(self, results):
        return {r.id: r for r in results}

    def test_healthy(self):
        res = self.by_id(self.run_checks(FakeRelease(latest={"tag": "v2.0.0", "version": "2.0.0"})))
        self.assertEqual(res["serpantinum"].status, DR.OK)
        self.assertEqual(res["compat"].status, DR.OK)
        self.assertEqual(res["deps"].status, DR.OK)
        self.assertEqual(res["anchors"].status, DR.OK)

    def test_serpantinum_missing_and_outdated(self):
        res = self.by_id(self.run_checks(FakeRelease(sv=None)))
        self.assertEqual(res["serpantinum"].status, DR.FAIL)
        res = self.by_id(self.run_checks(FakeRelease(up="2.4.0")))
        self.assertEqual(res["upstream"].status, DR.WARN)
        self.assertIn("update serpantinum first", res["upstream"].fix.lower())

    def test_reinstall_needed(self):
        inst = {"version": "2.0.0", "channel": "release", "serpantinum_version": "2.3.1",
                "serpantinum_commit": "old", "without": []}
        res = self.by_id(self.run_checks(FakeRelease(inst=inst)))
        self.assertEqual(res["reinstall"].status, DR.WARN)

    def test_anchor_errors_have_hints(self):
        sys_ = healthy()
        payload = '{"ok": false, "errors": [{"file": "Bar.qml", "patch": "p1", "message": "anchor lost", "hint": "update addons"}]}'
        res = DR.run_checks(FakeRelease(), run=lambda a, timeout=20: (2, payload) if "--check" in a else (0, ""),
                            which=sys_.probe().which, probe=sys_.probe())
        anchors = [r for r in res if r.id == "anchors"]
        self.assertEqual(anchors[0].status, DR.FAIL)
        self.assertEqual(anchors[0].fix, "update addons")

    def test_offline_release_is_a_warning(self):
        res = self.by_id(self.run_checks(FakeRelease(err="Offline or GitHub unreachable")))
        self.assertEqual(res["release"].status, DR.WARN)

    def test_report_has_no_home_path(self):
        home = os.path.expanduser("~")
        results = [DR.Result("a", f"Source {home}/x", DR.WARN, f"{home}/.local/share/foo missing",
                             f"cd {home}/proj"),
                   DR.Result("b", "Other", DR.FAIL, "/home/someoneelse/file | pipe")]
        info = {"addons": "2.0.0", "installed": "2.0.0", "channel": "release", "serpantinum": "2.3.2",
                "commit": "abc", "hyprland": "0.57.0", "os": "Arch", "python": "3.12"}
        md = DR.report_markdown(results, info)
        self.assertNotIn(home, md)
        self.assertNotIn("/home/someoneelse", md)
        self.assertIn("~/.local/share/foo", md)
        self.assertIn("Hyprland: 0.57.0", md)
        self.assertIn("\\|", md)

    def test_real_report_has_no_home_path(self):
        results = DR.run_checks(FakeRelease(), run=lambda a, timeout=20: (0, ""),
                                which=healthy().probe().which, probe=healthy().probe(),
                                install_py=Path("/nonexistent/install.py"))
        md = DR.report_markdown(results, DR.environment_info(
            FakeRelease(), run=lambda a: (0, HYPR_057), which=healthy().probe().which))
        self.assertNotIn(os.path.expanduser("~"), md)


class NullLog:
    shown = "~/log"

    def write(self, text):
        pass


def make_ctx(system=None, rel=None, argv=("install",), tty=True, call=None, fetch=None):
    """A flow context whose system, terminal, downloads and interactive commands are all fake."""
    ui, out = make_ui(tty=tty, environ={"TERM": "dumb"})
    ctx = F.Ctx(ui, addons.parse_args(list(argv)), rel or FakeRelease(), NullLog(),
                probe=(system or healthy()).probe(), call=call or (lambda cmd: 0),
                fetch=fetch or (lambda url, dest: Path(dest).write_text("#!/bin/sh\n")))
    return ctx, out


def make_pre(ctx):
    ss, compat, status, inst = F.quick_state(ctx)
    return F.Pre(ss, compat, status, inst, deps=D.check_all(ctx.probe, compat))


class FakeResponse:
    def __init__(self, data):
        self.data = data

    def read(self):
        return self.data

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class InstallsSerpantinum(unittest.TestCase):
    def test_runs_its_installer_when_missing(self):
        rel = FakeRelease(sv=None)
        calls = []

        def call(cmd):
            calls.append(cmd)
            self.assertTrue(Path(cmd[1]).read_text().startswith("#!"))  # downloaded script is still there
            rel.sv = "2.3.2"  # what the real installer does: write the version file
            return 0

        ctx, out = make_ctx(rel=rel, call=call)
        pre = make_pre(ctx)
        self.assertIsNone(pre.ss["version"])
        F.require_serpantinum(ctx, pre)
        self.assertEqual([c[0] for c in calls], ["bash"])
        self.assertEqual((pre.ss["version"], pre.compat_status), ("2.3.2", "ok"))
        self.assertIn("Serpantinum 2.3.2 installed", out.getvalue())
        self.assertEqual(ctx.phase, "prepare")

    def test_leaves_an_existing_install_alone(self):
        calls = []
        ctx, _ = make_ctx(call=lambda cmd: calls.append(cmd) or 0)
        F.require_serpantinum(ctx, make_pre(ctx))
        self.assertEqual(calls, [])

    def test_needs_a_terminal(self):
        calls = []
        ctx, _ = make_ctx(rel=FakeRelease(sv=None), tty=False, call=lambda cmd: calls.append(cmd) or 0)
        with self.assertRaises(F.Fail) as cm:
            F.require_serpantinum(ctx, make_pre(ctx))
        self.assertIn("terminal", cm.exception.why)
        self.assertEqual(calls, [])

    def test_download_failure_stops_before_running_anything(self):
        calls = []

        def fetch(url, dest):
            raise OSError("offline")

        ctx, _ = make_ctx(rel=FakeRelease(sv=None), fetch=fetch, call=lambda cmd: calls.append(cmd) or 0)
        with self.assertRaises(F.Fail) as cm:
            F.require_serpantinum(ctx, make_pre(ctx))
        self.assertIn("download", cm.exception.what)
        self.assertEqual(calls, [])

    def test_installer_failure(self):
        ctx, _ = make_ctx(rel=FakeRelease(sv=None), call=lambda cmd: 3)
        with self.assertRaises(F.Fail) as cm:
            F.require_serpantinum(ctx, make_pre(ctx))
        self.assertIn("did not finish", cm.exception.what)
        self.assertIn("3", cm.exception.why)

    def test_still_missing_after_a_clean_exit(self):
        ctx, _ = make_ctx(rel=FakeRelease(sv=None), call=lambda cmd: 0)
        with self.assertRaises(F.Fail) as cm:
            F.require_serpantinum(ctx, make_pre(ctx))
        self.assertIn("not found after", cm.exception.what)

    def test_ctrl_c_is_reported_as_an_interrupted_change(self):
        def call(cmd):
            raise KeyboardInterrupt

        ctx, _ = make_ctx(rel=FakeRelease(sv=None), call=call)
        with self.assertRaises(KeyboardInterrupt):
            F.require_serpantinum(ctx, make_pre(ctx))
        self.assertEqual(ctx.phase, "installing")

    def test_download_script_refuses_non_scripts(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "install.sh"
            with unittest.mock.patch("urllib.request.urlopen", return_value=FakeResponse(b"<html>404</html>")):
                with self.assertRaises(OSError):
                    F.download_script("https://example.invalid/install.sh", dest)
            self.assertFalse(dest.exists())
            with unittest.mock.patch("urllib.request.urlopen", return_value=FakeResponse(b"#!/usr/bin/env bash\n:\n")):
                F.download_script("https://example.invalid/install.sh", dest)
            self.assertTrue(dest.read_text().startswith("#!"))

    def test_serpantinum_comes_before_dependencies(self):
        order = []
        ctx, _ = make_ctx()
        pre = make_pre(ctx)
        with unittest.mock.patch.object(F, "require_serpantinum", lambda c, p: order.append("serpantinum")), \
                unittest.mock.patch.object(F, "ensure_deps", lambda c, p: order.append("deps")), \
                unittest.mock.patch.object(F, "choose_addons", lambda c, p: (_ for _ in ()).throw(F.Cancelled())):
            with self.assertRaises(F.Cancelled):
                F.action_install(ctx, "install", pre)
        self.assertEqual(order, ["serpantinum", "deps"])


class InstallsDependencies(unittest.TestCase):
    def system(self, missing=("jq",), manager="pacman"):
        s = healthy()
        s.present |= {manager}
        s.present -= set(missing)
        return s

    def test_missing_dependencies_are_installed_without_asking(self):
        for flags in ((), ("--yes",)):  # --yes used to refuse; it must install too
            s = self.system()
            calls = []

            def call(cmd):
                calls.append(cmd)
                s.present.add("jq")  # what the package manager does
                return 0

            ctx, out = make_ctx(system=s, argv=("install", *flags), call=call)
            pre = make_pre(ctx)
            F.ensure_deps(ctx, pre)
            self.assertEqual(calls, [["sudo", "pacman", "-S", "--needed", "jq"]], flags)
            self.assertNotIn("[Y/n]", out.getvalue())
            self.assertEqual(D.missing(pre.deps, required=True), [])
            self.assertIn("Dependencies installed", out.getvalue())

    def test_uses_the_detected_package_manager(self):
        s = self.system(manager="dnf")
        calls = []
        ctx, _ = make_ctx(system=s, call=lambda cmd: calls.append(cmd) or s.present.add("jq") or 0)
        F.ensure_deps(ctx, make_pre(ctx))
        self.assertEqual(calls, [["sudo", "dnf", "install", "jq"]])

    def test_nothing_to_do_when_everything_is_present(self):
        calls = []
        ctx, _ = make_ctx(call=lambda cmd: calls.append(cmd) or 0)
        F.ensure_deps(ctx, make_pre(ctx))
        self.assertEqual(calls, [])

    def test_optional_tools_are_never_installed(self):
        calls = []
        ctx, out = make_ctx(system=self.system(missing=("ollama", "codex")), call=lambda cmd: calls.append(cmd) or 0)
        F.ensure_deps(ctx, make_pre(ctx))
        self.assertEqual(calls, [])
        self.assertIn("Optional tools not found", out.getvalue())

    def test_failing_install_command(self):
        ctx, _ = make_ctx(system=self.system(), call=lambda cmd: 1)
        with self.assertRaises(F.Fail) as cm:
            F.ensure_deps(ctx, make_pre(ctx))
        self.assertIn("Installing the dependencies failed", cm.exception.what)

    def test_dependency_still_missing_afterwards(self):
        ctx, _ = make_ctx(system=self.system(), call=lambda cmd: 0)
        with self.assertRaises(F.Fail) as cm:
            F.ensure_deps(ctx, make_pre(ctx))
        self.assertIn("still missing", cm.exception.what)

    def test_no_supported_package_manager(self):
        ctx, _ = make_ctx(system=self.system(manager="pacman"))
        ctx.probe = self.system(manager="nothing").probe()
        with self.assertRaises(F.Fail) as cm:
            F.ensure_deps(ctx, make_pre(ctx))
        self.assertIn("no supported package manager", cm.exception.what)

    def test_ctrl_c_is_reported_as_an_interrupted_change(self):
        def call(cmd):
            raise KeyboardInterrupt

        ctx, _ = make_ctx(system=self.system(), call=call)
        with self.assertRaises(KeyboardInterrupt):
            F.ensure_deps(ctx, make_pre(ctx))
        self.assertEqual(ctx.phase, "installing")


class ErrorFormat(unittest.TestCase):
    def test_full(self):
        lines = tui.format_error("It broke", "because x", "do y", "~/log.txt", "https://i")
        self.assertEqual(lines, ["✗ It broke", "  because x", "  → do y", "  log: ~/log.txt",
                                 "  issues: https://i"])

    def test_minimal(self):
        self.assertEqual(tui.format_error("only"), ["✗ only"])

    def test_multiline_hint(self):
        lines = tui.format_error("w", "", "a\nb")
        self.assertEqual(lines, ["✗ w", "  → a", "    b"])

    def test_ui_error_plain(self):
        ui, out = make_ui()
        ui.error("w", "y", "h", "l", "u")
        self.assertNotIn("\x1b", out.getvalue())
        self.assertIn("  → h", out.getvalue())

    def test_run_wraps_unexpected_exceptions(self):
        ui, out = make_ui()
        args = addons.parse_args(["uninstall", "--yes"])
        old = F.preflight
        F.preflight = lambda ctx: (_ for _ in ()).throw(ValueError("boom"))
        try:
            with tempfile.TemporaryDirectory() as td:
                os.environ["XDG_STATE_HOME"] = td
                try:
                    rc = F.run(args, ui)
                finally:
                    os.environ.pop("XDG_STATE_HOME", None)
        finally:
            F.preflight = old
        text = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("Something unexpected happened", text)
        self.assertNotIn("Traceback", text)
        self.assertIn("issues", text)

    def test_ctrl_c_before_install(self):
        ui, out = make_ui()
        args = addons.parse_args(["reinstall", "--yes"])
        old = F.preflight
        F.preflight = lambda ctx: (_ for _ in ()).throw(KeyboardInterrupt())
        try:
            with tempfile.TemporaryDirectory() as td:
                os.environ["XDG_STATE_HOME"] = td
                try:
                    rc = F.run(args, ui)
                finally:
                    os.environ.pop("XDG_STATE_HOME", None)
        finally:
            F.preflight = old
        self.assertEqual(rc, 130)
        self.assertIn("Cancelled, nothing changed", out.getvalue())


class ManagedSource(unittest.TestCase):
    def test_xdg_data_home(self):
        old = os.environ.get("XDG_DATA_HOME")
        os.environ["XDG_DATA_HOME"] = "/tmp/xdg-test"
        try:
            self.assertEqual(F.managed_source(), Path("/tmp/xdg-test/serpantinum-addons-v2/source"))
            self.assertFalse(F.is_managed_source(ROOT))
        finally:
            if old is None:
                os.environ.pop("XDG_DATA_HOME")
            else:
                os.environ["XDG_DATA_HOME"] = old


class Bootstrap(unittest.TestCase):
    SCRIPT = ROOT / "install" / "install.sh"

    def test_syntax(self):
        subprocess.run(["bash", "-n", str(self.SCRIPT)], check=True)

    def test_strict_mode_and_guards(self):
        text = self.SCRIPT.read_text()
        self.assertIn("set -euo pipefail", text)
        self.assertIn("exec </dev/tty", text)
        self.assertIn("exec python3", text)
        self.assertIn("pacman -S --needed", text)

    @unittest.skipUnless(shutil.which("shellcheck"), "shellcheck not installed")
    def test_shellcheck(self):
        r = subprocess.run(["shellcheck", "-S", "warning", str(self.SCRIPT)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_refuses_root_message_present(self):
        self.assertIn("Do not run this as root", self.SCRIPT.read_text())

    def run_script(self, manager=None):
        """Run install.sh with a PATH holding only a few real tools plus a fake sudo and package manager.

        The fake package manager logs its arguments and "installs" git and curl as stubs that fail,
        so the script stops at the clone step, after the parts under test.
        """
        if os.geteuid() == 0:
            self.skipTest("install.sh refuses to run as root")
        bash, py3 = shutil.which("bash"), shutil.which("python3")
        if not (bash and py3 and sys.version_info >= (3, 10)):
            self.skipTest("needs bash and python3 >= 3.10 on PATH")
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            bindir, log = td / "bin", td / "pm.log"
            bindir.mkdir()
            for tool in ("id", "dirname", "mkdir", "ls", "chmod", "tput"):
                real = shutil.which(tool)
                if real:
                    (bindir / tool).symlink_to(real)
            (bindir / "python3").symlink_to(py3)
            (bindir / "sudo").write_text(f'#!{bash}\nexec "$@"\n')
            stub = f"#!{bash}\\nexit 1\\n"
            if manager:
                (bindir / manager).write_text(
                    f'#!{bash}\necho "$0 $*" | sed "s|.*/||" >> "{log}"\n'
                    f'printf \'{stub}\' > "{bindir}/git"\nprintf \'{stub}\' > "{bindir}/curl"\n'
                    f'chmod +x "{bindir}/git" "{bindir}/curl"\n')
                (bindir / "sed").symlink_to(shutil.which("sed"))
            for f in bindir.iterdir():
                f.chmod(0o755) if not f.is_symlink() else None
            env = {"PATH": str(bindir), "HOME": str(td / "home"), "NO_COLOR": "1"}
            r = subprocess.run([bash, str(self.SCRIPT)], capture_output=True, text=True, env=env,
                               stdin=subprocess.DEVNULL, timeout=60)
            return r, (log.read_text() if log.exists() else "")

    def test_installs_missing_tools_itself(self):
        for manager, expected in (("pacman", "pacman -S --needed git curl"),
                                  ("dnf", "dnf install git curl"),
                                  ("xbps-install", "xbps-install -S git curl")):
            r, log = self.run_script(manager)
            self.assertEqual(log.strip(), expected, manager)
            self.assertIn("git, curl and python3 ready", r.stderr, manager)

    def test_missing_serpantinum_does_not_stop_the_script(self):
        r, _ = self.run_script("pacman")
        self.assertIn("Serpantinum is not installed", r.stderr)
        self.assertIn("Fetching Serpantinum Addons", r.stderr)  # went on to the next step

    def test_no_package_manager_is_a_clear_failure(self):
        r, log = self.run_script(None)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(log, "")
        self.assertIn("No supported package manager", r.stderr)


class Cli(unittest.TestCase):
    def test_help_without_color(self):
        env = dict(os.environ, NO_COLOR="1")
        r = subprocess.run([sys.executable, str(ROOT / "addons.py"), "--help"], capture_output=True,
                           text=True, env=env)
        self.assertEqual(r.returncode, 0)
        self.assertNotIn("\x1b", r.stdout)
        self.assertIn("uninstall", r.stdout)



if __name__ == "__main__":
    unittest.main()
