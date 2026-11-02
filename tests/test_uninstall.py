"""install -> idempotence -> check -> uninstall round trip against a throw-away copy of Serpantinum 2.3.2.

Nothing here touches the real ~/.local/share/serpantinum, ~/.config or ~/.local/state: HOME and every XDG_* /
SERPANTINUM_* variable points into a temporary directory, and SERPANTINUM_ADDONS_NO_SERVICES keeps systemctl
and agent hooks out of the picture. The pristine upstream clone is only read.
"""
import contextlib
import fcntl
import io
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from test_changes import ROOT, load

CACHE = Path(os.environ.get('SERPANTINUM_UPSTREAM_CACHE') or Path.home()/'.cache/serpantinum-installer')
COMMIT = '68b0222'
SCREENSHOT_BIND = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })\n'


def git(*args):
    return subprocess.run(['git', '-C', str(CACHE), *args], capture_output=True, check=True).stdout


def has_pristine():
    try:
        return (CACHE/'.git').exists() and subprocess.run(['git', '-C', str(CACHE), 'cat-file', '-e', COMMIT + '^{commit}'], capture_output=True).returncode == 0
    except OSError:
        return False


def snapshot(folder):
    return {str(p.relative_to(folder)): p.read_bytes() for p in sorted(folder.rglob('*')) if p.is_file()}


@unittest.skipUnless(has_pristine(), 'pristine Serpantinum clone (~/.cache/serpantinum-installer at 68b0222) is missing')
class RoundTripTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = Path(tempfile.mkdtemp(prefix='addons-pristine-'))
        archive = subprocess.run(['git', '-C', str(CACHE), 'archive', COMMIT, 'src/quickshell', 'src/scripts'], capture_output=True, check=True).stdout
        cls.pristine = cls.base/'pristine'
        cls.pristine.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(cls.pristine, filter='data')
        cls.keybinds = git('show', COMMIT + ':compositors/hyprland/config/keybinds.lua').decode() + '\n' + SCREENSHOT_BIND

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.base, ignore_errors=True)

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='addons-world-'))
        self.addCleanup(shutil.rmtree, self.root, True)
        home = self.root/'home'
        self.data, self.state, self.config = home/'.local/share', home/'.local/state', home/'.config'
        self.shell = self.data/'serpantinum'
        shutil.copytree(self.pristine/'src', self.shell/'src')
        (self.state/'serpantinum').mkdir(parents=True)
        (self.state/'serpantinum/version').write_text('SERPANTINUM_VERSION="2.3.2"\nSERPANTINUM_COMMIT="%s"\n' % COMMIT)
        self.keybind_file = self.config/'hypr/config/keybinds.lua'
        self.keybind_file.parent.mkdir(parents=True)
        self.keybind_file.write_text(self.keybinds)
        self.before = snapshot(self.shell/'src')
        env = {'HOME': str(home), 'XDG_DATA_HOME': str(self.data), 'XDG_STATE_HOME': str(self.state), 'XDG_CONFIG_HOME': str(self.config), 'XDG_CACHE_HOME': str(home/'.cache'),
               'SERPANTINUM_HOME': str(self.shell), 'SERPANTINUM_UPSTREAM_CACHE': str(CACHE), 'SERPANTINUM_ADDONS_NO_SERVICES': '1'}
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        for stray in ('TOKENS_STATE_DIR', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME'):
            os.environ.pop(stray, None)
        self.installer = load('installer_roundtrip', ROOT/'install.py')   # own module: other tests keep the real paths
        self.assertEqual(Path.home(), home)
        self.assertTrue(str(self.installer.QS).startswith(str(self.root)))

    def run_cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = self.installer.main(list(args))
        return code, out.getvalue(), err.getvalue()

    def run_json(self, *args):
        code, out, err = self.run_cli(*args, '--json')
        return code, json.loads(out), err

    def test_round_trip_restores_pristine_shell(self):
        code, report, _ = self.run_json()
        self.assertEqual((code, report['ok'], report['errors']), (0, True, []))
        self.assertGreater(report['changes'], 0)
        installed = snapshot(self.shell/'src')
        self.assertNotEqual(installed, self.before)
        self.assertIn('-- BEGIN serpantinum-addons-v2 color picker', self.keybind_file.read_text())
        self.assertIn(str(self.data/'serpantinum-addons-v2/scripts/mouse-next-monitor-center.sh'), self.keybind_file.read_text())

        state = json.loads((self.state/'serpantinum-addons-v2/install.json').read_text())
        self.assertEqual(state['serpantinum_commit'], COMMIT)
        self.assertEqual(state['channel'], 'dev')
        self.assertEqual(state['without'], [])
        self.assertEqual(state['version'], (ROOT/'VERSION').read_text().strip())
        manifest = state['manifest']
        self.assertEqual(manifest['keybinds'], str(self.keybind_file))
        self.assertIn('Shell.qml', manifest['patched'])
        self.assertIn('qmldir', manifest['patched'])
        self.assertIn('../scripts/screenshot.sh', manifest['patched'])
        self.assertIn('guide/AddonsBannersTab.qml', manifest['created'])
        for name in ('singletons/system/AddonsUpdater.qml', 'guide/AddonsUpdateButton.qml', 'guide/AddonsReleaseCard.qml'):
            self.assertIn(name, manifest['created'])
            self.assertTrue((self.shell/'src/quickshell'/name).is_file(), name)
        for name in ('guide/GuideSidebar.qml', 'guide/AboutTab.qml', 'guide/GuidePopup.qml'):
            self.assertIn('serpantinum-addons-release-v2', (self.shell/'src/quickshell'/name).read_text(), name)
            self.assertIn(name, manifest['patched'])
        self.assertTrue(any(re.fullmatch(r'seasonal/shaders/atmosphere\.[a-f0-9]{12}\.frag\.qsb', name) for name in manifest['created']))
        for name in manifest['created']:
            self.assertTrue((self.shell/'src/quickshell'/name).is_file(), name)
        self.assertTrue((self.state/'serpantinum-addons-v2/compat.json').is_file())
        self.assertTrue((self.state/'serpantinum-addons-v2/VERSION').is_file())
        self.assertTrue((self.data/'serpantinum-addons-v2/scripts/mouse-next-monitor-center.sh').stat().st_mode & 0o111)
        self.assertFalse(list((self.data/'serpantinum-addons-v2/scripts').rglob('__pycache__')))

        # second install is a no-op, --check agrees
        code, again, _ = self.run_json()
        self.assertEqual((code, again['changes'], again['ok']), (0, 0, True))
        self.assertEqual(snapshot(self.shell/'src'), installed)
        code, checked, _ = self.run_json('--check')
        self.assertEqual((code, checked['ok'], checked['changes']), (0, True, 0))

        # uninstall restores every byte and leaves no created file or folder
        code, removed, _ = self.run_json('--uninstall')
        self.assertEqual((code, removed['ok'], removed['errors']), (0, True, []))
        self.assertEqual(snapshot(self.shell/'src'), self.before)
        self.assertEqual(sorted(str(p.relative_to(self.shell/'src')) for p in (self.shell/'src').rglob('*') if p.is_dir()),
                         sorted(str(p.relative_to(self.pristine/'src')) for p in (self.pristine/'src').rglob('*') if p.is_dir()))
        text = self.keybind_file.read_text()
        self.assertIsNone(re.search(r'serpantinum-[\w-]*v2', text))
        self.assertEqual(text.rstrip(), self.keybinds.rstrip())
        self.assertFalse((self.data/'serpantinum-addons-v2/scripts').exists())
        self.assertFalse((self.state/'serpantinum-addons-v2/install.json').exists())
        self.assertTrue(list((self.data/'serpantinum-addons-v2/backups').glob('*-uninstall')))
        # a second uninstall finds nothing left to do
        code, empty, _ = self.run_json('--uninstall')
        self.assertEqual((code, empty['changes']), (0, 0))

    def test_uninstall_without_install_json_and_purge(self):
        self.assertEqual(self.run_cli()[0], 0)
        (self.state/'serpantinum-addons-v2/install.json').unlink()
        capri_state = self.state/'serpantinum/capri'
        capri_state.mkdir(parents=True)
        (capri_state/'chat.json').write_text('{}')
        (self.state/'serpantinum-addons-v2/hyprland.lua.keep').write_text('x')
        code, report, _ = self.run_json('--uninstall', '--purge')
        self.assertEqual((code, report['ok']), (0, True))
        self.assertEqual(snapshot(self.shell/'src'), self.before)
        self.assertFalse(capri_state.exists())
        self.assertFalse((self.state/'serpantinum-addons-v2').exists())
        self.assertTrue((self.data/'serpantinum-addons-v2/backups').is_dir())

    def test_uninstall_keeps_foreign_state_without_purge(self):
        self.assertEqual(self.run_cli()[0], 0)
        capri_state = self.state/'serpantinum/capri'
        capri_state.mkdir(parents=True)
        (self.state/'serpantinum-addons-v2/hyprland.lua.keep').write_text('x')
        self.assertEqual(self.run_cli('--uninstall')[0], 0)
        self.assertTrue(capri_state.is_dir())
        self.assertTrue((self.state/'serpantinum-addons-v2/hyprland.lua.keep').is_file())

    def test_uninstall_removes_only_owned_beamer_files_after_read_only_check(self):
        self.assertEqual(self.run_cli()[0], 0)
        beamer = self.installer._load('test_beamer_setup', ROOT/'scripts/beamer/setup.py')
        desktop, state, cache = beamer.paths()
        desktop.parent.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        state.parent.mkdir(parents=True, exist_ok=True)
        desktop.write_bytes(b'addon desktop')
        for name in beamer.HELPERS:
            (cache/name).write_bytes(name.encode())
        state.write_text(json.dumps({'desktop': beamer.digest(desktop.read_bytes()),
                                     'helpers': {name: beamer.digest((cache/name).read_bytes()) for name in beamer.HELPERS}}))
        before = (desktop.read_bytes(), state.read_bytes(), *( (cache/name).read_bytes() for name in beamer.HELPERS))
        code, checked, _ = self.run_json('--uninstall', '--check')
        self.assertEqual(code, 0)
        self.assertIn(str(desktop), checked['changed_files'])
        self.assertEqual(before, (desktop.read_bytes(), state.read_bytes(), *( (cache/name).read_bytes() for name in beamer.HELPERS)))
        code, report, _ = self.run_json('--uninstall')
        self.assertEqual(code, 0)
        self.assertIn(str(desktop), report['removed'])
        self.assertFalse(desktop.exists())
        self.assertFalse(state.exists())
        self.assertTrue(all(not (cache/name).exists() for name in beamer.HELPERS))

    def test_uninstall_keeps_modified_beamer_launcher_and_ownership_state(self):
        self.assertEqual(self.run_cli()[0], 0)
        beamer = self.installer._load('test_beamer_setup_modified', ROOT/'scripts/beamer/setup.py')
        desktop, state, cache = beamer.paths()
        desktop.parent.mkdir(parents=True, exist_ok=True)
        state.parent.mkdir(parents=True, exist_ok=True)
        desktop.write_bytes(b'customized desktop')
        state.write_text(json.dumps({'desktop': beamer.digest(b'original desktop'), 'helpers': {}}))
        code, report, _ = self.run_json('--uninstall')
        self.assertEqual(code, 0)
        self.assertEqual(desktop.read_bytes(), b'customized desktop')
        self.assertTrue(state.exists())
        self.assertTrue(any(str(desktop) in entry for entry in report['kept']))

    def test_uninstall_aborts_when_a_file_cannot_be_resolved(self):
        self.assertEqual(self.run_cli()[0], 0)
        installed = snapshot(self.shell/'src')
        keybinds = self.keybind_file.read_text()
        with mock.patch.dict(os.environ, {'SERPANTINUM_UPSTREAM_CACHE': str(self.root/'missing')}), \
                mock.patch.object(self.installer.urllib.request, 'urlopen', side_effect=OSError('offline')):
            code, report, err = self.run_json('--uninstall')
        self.assertEqual((code, report['ok']), (2, False))
        self.assertTrue(report['errors'][0]['hint'])
        self.assertEqual(snapshot(self.shell/'src'), installed)
        self.assertEqual(self.keybind_file.read_text(), keybinds)

    def test_old_managed_window_block_is_upgraded_in_place(self):
        self.assertEqual(self.run_cli()[0], 0)
        new = json.dumps(str(self.data/'serpantinum-addons-v2/scripts/mouse-next-monitor-center.sh'))
        old = json.dumps(str(self.config/'hypr/scripts/mouse-next-monitor-center.sh'))
        text = self.keybind_file.read_text()
        self.assertIn(new, text)
        self.keybind_file.write_text(text.replace(new, old, 1).replace('-- Alt+Tab', '-- my own Alt+Tab note'))
        code, report, _ = self.run_json('--check')
        self.assertEqual((code, report['changes']), (0, 1))
        self.assertEqual(self.run_cli()[0], 0)
        upgraded = self.keybind_file.read_text()
        self.assertIn(new, upgraded)
        self.assertNotIn(old, upgraded)
        self.assertIn('-- my own Alt+Tab note', upgraded)

    def test_without_flags_strip_the_banners_tab(self):
        self.assertEqual(self.run_cli('--without-capri', '--without-clawd', '--without-halloween')[0], 0)
        banners = (self.shell/'src/quickshell/guide/AddonsBannersTab.qml').read_text()
        for name in ('CapriSettings', 'ClawdSettings', 'HalloweenCard'):
            self.assertNotIn(name, banners)
        state = json.loads((self.state/'serpantinum-addons-v2/install.json').read_text())
        self.assertEqual(sorted(state['without']), ['capri', 'clawd', 'halloween'])
        self.assertEqual(self.run_cli('--uninstall')[0], 0)
        self.assertEqual(snapshot(self.shell/'src'), self.before)

    def test_too_old_serpantinum_is_refused_and_nothing_is_written(self):
        (self.state/'serpantinum/version').write_text('SERPANTINUM_VERSION="2.0.0"\nSERPANTINUM_COMMIT="%s"\n' % COMMIT)
        code, report, err = self.run_json()
        self.assertEqual((code, report['ok'], report['compat']), (2, False, 'too_old'))
        self.assertEqual(report['errors'][0]['message'].count('2.0.0'), 1)
        self.assertEqual(snapshot(self.shell/'src'), self.before)
        self.assertEqual(self.keybind_file.read_text(), self.keybinds)
        self.assertFalse((self.data/'serpantinum-addons-v2').exists())
        self.assertFalse((self.state/'serpantinum-addons-v2').exists())
        code, out, err = self.run_cli()
        self.assertEqual(code, 2)
        self.assertIn('✗', err)
        self.assertIn('→', err)
        self.assertNotIn('Traceback', err)

    def test_newer_than_tested_only_warns(self):
        (self.state/'serpantinum/version').write_text('SERPANTINUM_VERSION="9.9.9"\nSERPANTINUM_COMMIT="%s"\n' % COMMIT)
        code, report, _ = self.run_json('--check')
        self.assertEqual((code, report['ok'], report['compat']), (0, True, 'newer_than_tested'))
        self.assertTrue(report['warnings'])

    def test_anchor_failure_is_an_install_error_and_writes_nothing(self):
        guide = self.shell/'src/quickshell/guide/IdleTab.qml'
        guide.write_text(guide.read_text().replace('property bool lockOnSleep', 'property bool lockOnSleepRenamed'))
        broken = snapshot(self.shell/'src')
        code, report, _ = self.run_json()
        self.assertEqual((code, report['ok']), (2, False))
        error = report['errors'][0]
        self.assertEqual(error['file'], 'guide/IdleTab.qml')
        self.assertEqual(error['patch'], 'patch_idle_tab')
        self.assertIn('doctor --report', error['hint'])
        self.assertEqual(snapshot(self.shell/'src'), broken)
        self.assertFalse((self.data/'serpantinum-addons-v2').exists())

    def test_lock_held_by_another_install_exits_3(self):
        lock = self.state/'serpantinum-addons-v2/install.lock'
        lock.parent.mkdir(parents=True)
        with open(lock, 'a+') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            code, report, _ = self.run_json()
            self.assertEqual((code, report['ok']), (3, False))
            self.assertEqual(self.run_json('--uninstall')[0], 3)
            self.assertEqual(self.run_json('--check')[0], 0)   # --check never takes the lock
        self.assertEqual(snapshot(self.shell/'src'), self.before)

    def test_check_json_schema_and_writes_nothing(self):
        code, report, _ = self.run_json('--check')
        self.assertEqual(code, 0)
        self.assertTrue({'ok', 'changes', 'serpantinum', 'compat', 'errors'} <= set(report))
        self.assertIs(report['ok'], True)
        self.assertIsInstance(report['changes'], int)
        self.assertGreater(report['changes'], 0)
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['compat'], 'ok')
        self.assertEqual({k: report['serpantinum'][k] for k in ('version', 'commit')}, {'version': '2.3.2', 'commit': COMMIT})
        self.assertEqual(snapshot(self.shell/'src'), self.before)
        self.assertEqual(self.keybind_file.read_text(), self.keybinds)
        self.assertFalse((self.data/'serpantinum-addons-v2').exists())
        self.assertFalse((self.state/'serpantinum-addons-v2').exists())

    def test_purge_requires_uninstall(self):
        with self.assertRaises(SystemExit) as caught, contextlib.redirect_stderr(io.StringIO()):
            self.installer.main(['--purge'])
        self.assertEqual(caught.exception.code, 2)

    def test_scripts_deployment_mirrors_source(self):
        deploy = self.data/'serpantinum-addons-v2'
        (deploy/'scripts/stale').mkdir(parents=True)
        (deploy/'scripts/stale/old.py').write_text('x')
        (deploy/'scripts/obsolete.py').write_text('x')
        (deploy/'install.py').write_text('old')
        (deploy/'payload').mkdir()
        (deploy/'payload/old.qml').write_text('x')
        (deploy/'backups/keep').mkdir(parents=True)
        (deploy/'backups/keep/file').write_text('x')
        self.assertEqual(self.run_cli()[0], 0)
        source = {str(p.relative_to(ROOT/'scripts')) for p in (ROOT/'scripts').rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc'}
        copied = {str(p.relative_to(deploy/'scripts')) for p in (deploy/'scripts').rglob('*') if p.is_file()}
        self.assertEqual(copied, source)
        self.assertFalse((deploy/'scripts/stale').exists())
        self.assertFalse((deploy/'install.py').exists())
        self.assertFalse((deploy/'payload').exists())
        self.assertTrue((deploy/'backups/keep/file').is_file())


class SafetyGuardTests(unittest.TestCase):
    def test_purge_skips_state_dirs_outside_addon_data(self):
        installer = load('installer_purge', ROOT/'install.py')
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            outside = tmp/'precious'
            outside.mkdir()
            (outside/'f').write_text('x')
            inside = tmp/'state/serpantinum/capri'
            inside.mkdir(parents=True)
            with mock.patch.dict(os.environ, {'XDG_STATE_HOME': str(tmp/'state'), 'TOKENS_STATE_DIR': str(outside)}):
                with mock.patch.object(installer, 'HOME', tmp/'home'):
                    self.assertFalse(installer.within_addon_data(outside))
                    self.assertTrue(installer.within_addon_data(inside))
                    self.assertFalse(installer.within_addon_data(tmp/'state/serpantinum/../../precious'))
                    self.assertIn(outside, installer.addon_state_dirs())

    def test_uninstall_never_deletes_checkout_living_at_deploy(self):
        installer = load('installer_deploy', ROOT/'install.py')
        with tempfile.TemporaryDirectory() as tmp:
            deploy = Path(tmp).resolve()
            for name in ('scripts', 'payload'):
                (deploy/name).mkdir()
                (deploy/name/'f').write_text('x')
            (deploy/'install.py').write_text('x')
            with mock.patch.object(installer, 'DEPLOY', deploy), mock.patch.object(installer, 'SOURCE', deploy):
                self.assertTrue(installer.SOURCE == installer.DEPLOY.resolve())
                src = Path(installer.__file__).read_text()
                self.assertIn("if SOURCE == DEPLOY.resolve(): break", src)
            self.assertTrue((deploy/'scripts/f').exists())


class KeybindBlockTests(unittest.TestCase):
    def test_strip_keeps_user_lines_and_every_mark(self):
        installer = load('installer_blocks', ROOT/'install.py')
        text = ('-- mine\nhl.bind("X", hl.dsp.exec_cmd("a"))\n\n-- BEGIN serpantinum-addons-v2 desktop zoom\nzoom\n-- END serpantinum-addons-v2 desktop zoom\n\n'
                '-- BEGIN serpantinum-addons-v2 desktop zoom scroll\nscroll\n-- END serpantinum-addons-v2 desktop zoom scroll\n'
                '\n-- BEGIN serpantinum-capri-v2 keybind\nc\n-- END serpantinum-capri-v2 keybind\n'
                '\n-- BEGIN serpantinum-clawd-v2 keybind\nd\n-- END serpantinum-clawd-v2 keybind\n-- tail\n')
        self.assertEqual(installer.strip_keybind_blocks(text), '-- mine\nhl.bind("X", hl.dsp.exec_cmd("a"))\n-- tail\n')


if __name__ == '__main__':
    unittest.main()
