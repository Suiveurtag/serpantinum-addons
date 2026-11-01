import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "addons_release.py"
spec = importlib.util.spec_from_file_location("addons_release", SCRIPT)
ar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ar)

API = f"https://api.github.com/repos/{ar.REPO}/releases/latest"
UP = f"https://raw.githubusercontent.com/{ar.UPSTREAM_REPO}/master/version.txt"


def make_fetch(release="2.1.0", rmin="2.3.2", upstream="2.3.2", calls=None, err=None):
    def fetch(url):
        if calls is not None:
            calls.append(url)
        if err:
            raise err
        if url == API:
            if release is None:
                raise urllib.error.HTTPError(url, 404, "nf", {}, io.BytesIO())
            return json.dumps({"tag_name": "v" + release, "html_url": "http://r",
                               "body": "notes"}).encode()
        if url.endswith("compat.json"):
            return json.dumps({"serpantinum": {"min": rmin}}).encode()
        if url == UP:
            return (upstream + "\n").encode()
        raise AssertionError(url)
    return fetch


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        self.saved = {k: os.environ.get(k) for k in
                      ("XDG_STATE_HOME", "XDG_DATA_HOME", "SERPANTINUM_HOME")}
        os.environ["XDG_STATE_HOME"] = str(t / "state")
        os.environ["XDG_DATA_HOME"] = str(t / "data")
        os.environ["SERPANTINUM_HOME"] = str(t / "home")
        (t / "state" / "serpantinum").mkdir(parents=True)
        self.set_shell("2.3.2", "abc")

    def tearDown(self):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def set_shell(self, v, c):
        p = Path(os.environ["XDG_STATE_HOME"]) / "serpantinum" / "version"
        p.write_text(f'SERPANTINUM_VERSION="{v}"\nSERPANTINUM_COMMIT="{c}"\nX="y"\n')

    def install(self, **kw):
        d = {"version": "2.0.0", "commit": "x", "channel": "release", "source": "s",
             "serpantinum_version": "2.3.2", "serpantinum_commit": "abc",
             "installed_at": "2026-11-01T00:00:00", "without": [],
             "manifest": {"patched": [], "created": []}}
        d.update(kw)
        ar.write_install_state(d)


class TestVersions(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(ar.parse_version("v2.0.0"), (2, 0, 0))
        self.assertEqual(ar.parse_version("2.0.0-dev+abc"), (2, 0, 0))
        self.assertEqual(ar.parse_version(""), ())
        self.assertEqual(ar.parse_version(None), ())

    def test_compare(self):
        self.assertEqual(ar.compare("2.0.0", "2.0.0"), 0)
        self.assertEqual(ar.compare("2.0.1", "2.0.0"), 1)
        self.assertEqual(ar.compare("2.0", "2.0.1"), -1)
        self.assertEqual(ar.compare("2.10.0", "2.9.0"), 1)

    def test_compat_status(self):
        c = {"serpantinum": {"min": "2.3.2", "tested": "2.3.2"}}
        self.assertEqual(ar.compat_status("2.3.2", c), "ok")
        self.assertEqual(ar.compat_status("2.3.1", c), "too_old")
        self.assertEqual(ar.compat_status("2.4.0", c), "newer_than_tested")
        self.assertEqual(ar.compat_status(None, c), "unknown")
        self.assertEqual(ar.compat_status("2.3.2", {}), "unknown")


class TestState(Base):
    def test_serpantinum_state(self):
        s = ar.serpantinum_state()
        self.assertEqual((s["version"], s["commit"]), ("2.3.2", "abc"))

    def test_fallback_version_txt(self):
        (Path(os.environ["XDG_STATE_HOME"]) / "serpantinum" / "version").unlink()
        home = Path(os.environ["SERPANTINUM_HOME"])
        home.mkdir()
        (home / "version.txt").write_text("2.2.0\n")
        s = ar.serpantinum_state()
        self.assertEqual(s["version"], "2.2.0")
        self.assertIsNone(s["commit"])

    def test_round_trip(self):
        self.assertIsNone(ar.read_install_state())
        self.install()
        self.assertEqual(ar.read_install_state()["version"], "2.0.0")
        self.assertEqual(list(ar.state_dir().glob("install.json.*")), [])

    def test_load_compat_missing(self):
        self.assertEqual(ar.load_compat(Path(self.tmp.name) / "nope.json"), {})
        self.assertIn("serpantinum", ar.load_compat())


class TestCheck(Base):
    def test_not_installed(self):
        self.assertEqual(ar.check(fetch=make_fetch())["state"], "not_installed")

    def test_reinstall_needed(self):
        self.install(serpantinum_commit="old")
        self.assertEqual(ar.check(fetch=make_fetch())["state"], "reinstall_needed")

    def test_error_with_stale_cache(self):
        self.install()
        ar.check(force=True, fetch=make_fetch())
        r = ar.check(force=True, fetch=make_fetch(err=RuntimeError("Offline")))
        self.assertEqual(r["state"], "error")
        self.assertEqual(r["error"], "Offline")
        self.assertEqual(r["remote"], "2.1.0")
        self.assertEqual(r["notes_url"], "http://r")

    def test_serpantinum_outdated(self):
        self.install()
        r = ar.check(fetch=make_fetch(upstream="2.4.0"))
        self.assertEqual(r["state"], "serpantinum_outdated")

    def test_incompatible(self):
        self.install()
        r = ar.check(fetch=make_fetch(rmin="2.5.0"))
        self.assertEqual(r["state"], "incompatible")

    def test_available(self):
        self.install()
        r = ar.check(fetch=make_fetch())
        self.assertEqual(r["state"], "available")
        self.assertEqual(r["remote"], "2.1.0")
        self.assertEqual(set(r), {"state", "local", "remote", "serpantinum", "compat",
                                  "notes_url", "checked_at", "error"})

    def test_dev(self):
        self.install(channel="dev")
        self.assertEqual(ar.check(fetch=make_fetch(release="2.0.0"))["state"], "dev")

    def test_up_to_date(self):
        self.install()
        self.assertEqual(ar.check(fetch=make_fetch(release="2.0.0"))["state"], "up_to_date")

    def test_no_release_404(self):
        self.install()
        self.assertEqual(ar.latest_release(fetch=make_fetch(release=None)), {})
        self.assertEqual(ar.check(force=True, fetch=make_fetch(release=None))["state"],
                         "up_to_date")

    def test_default_fetch_404_is_notfound_and_other_codes_keep_messages(self):
        def opener(code, headers=None):
            def urlopen(req, timeout=None):
                raise urllib.error.HTTPError(req.full_url, code, "x", headers or {}, io.BytesIO())
            return urlopen
        with mock.patch.object(ar.urllib.request, "urlopen", opener(404)):
            with self.assertRaises(ar.NotFound):
                ar._default_fetch(API)
            self.install()
            self.assertEqual(ar.latest_release(force=True), {})
        with mock.patch.object(ar.urllib.request, "urlopen", opener(403, {"X-RateLimit-Remaining": "0"})):
            with self.assertRaisesRegex(RuntimeError, "rate limit"):
                ar._default_fetch(API)
        with mock.patch.object(ar.urllib.request, "urlopen", opener(500)):
            with self.assertRaisesRegex(RuntimeError, "HTTP error 500"):
                ar._default_fetch(API)
        with mock.patch.object(ar.urllib.request, "urlopen", side_effect=urllib.error.URLError("x")):
            with self.assertRaisesRegex(RuntimeError, "Offline"):
                ar._default_fetch(API)
        self.assertEqual(ar.latest_release(force=True, fetch=make_fetch(err=ar.NotFound("404"))), {})

    def test_cache(self):
        calls = []
        ar.latest_release(fetch=make_fetch(calls=calls))
        n = len(calls)
        ar.latest_release(fetch=make_fetch(calls=calls))
        self.assertEqual(len(calls), n)
        ar.latest_release(force=True, fetch=make_fetch(calls=calls))
        self.assertGreater(len(calls), n)

    def test_upstream_failure(self):
        self.assertIsNone(ar.upstream_latest_version(fetch=make_fetch(err=OSError("x"))))
        self.assertEqual(ar.upstream_latest_version(fetch=make_fetch()), "2.3.2")


class TestCLI(Base):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True,
                              text=True, env=dict(os.environ))

    def test_check_json(self):
        r = self.run_cli("check")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(json.loads(r.stdout)["state"], "not_installed")
        self.assertEqual(len(r.stdout.strip().splitlines()), 1)

    def test_error_json(self):
        orig = ar.check
        ar.check = lambda **k: (_ for _ in ()).throw(ValueError("boom"))
        try:
            buf = io.StringIO()
            old, sys.stdout = sys.stdout, buf
            try:
                self.assertEqual(ar.main(["check"]), 0)
            finally:
                sys.stdout = old
        finally:
            ar.check = orig
        d = json.loads(buf.getvalue())
        self.assertEqual((d["state"], d["error"]), ("error", "boom"))


if __name__ == "__main__":
    unittest.main()
