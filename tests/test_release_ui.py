import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

from test_changes import ROOT

sys.path.insert(0, str(ROOT))
import release_ui  # noqa: E402

PRISTINE = Path.home()/'.cache/serpantinum-installer/src/quickshell'
INSTALLED = Path.home()/'.local/share/serpantinum/src/quickshell'
QS = Path('/qs')  # transformation keys are only inspected, never read
FILES = ['qmldir', 'guide/qmldir', 'guide/GuideSidebar.qml', 'guide/AboutTab.qml', 'guide/GuidePopup.qml']
QML = ['AddonsUpdater', 'AddonsUpdateButton', 'AddonsReleaseCard']


def payload(name):
    return (ROOT/'payload'/f'{name}.qml').read_text()


class ReleaseUiTests(unittest.TestCase):
    def test_api(self):
        self.assertTrue(release_ui.MARK)
        self.assertNotEqual(release_ui.MARK, 'serpantinum-addons-v2')
        for source, dest in release_ui.payloads().items():
            self.assertTrue((ROOT/source).is_file(), source)
            self.assertTrue(dest.endswith('.qml'))
        self.assertEqual(sorted(Path(s).stem for s in release_ui.payloads()), sorted(QML))
        self.assertEqual({str(path.relative_to(QS)) for path in release_ui.transformations(QS)}, set(FILES))
        for lines in release_ui.qmldir_entries().values():
            for line in lines:
                self.assertTrue(line.startswith(('singleton ', 'Addons')), line)
        singleton = [l for l in release_ui.qmldir_entries()['qmldir'] if l.startswith('singleton AddonsUpdater ')]
        self.assertEqual(len(singleton), 1)
        dest = singleton[0].split()[-1]
        self.assertEqual(dest, release_ui.payloads()['payload/AddonsUpdater.qml'])

    def check_tree(self, root, strip):
        if not root.is_dir():
            self.skipTest(f'{root} not available')
        for path, patch in release_ui.transformations(root).items():
            text = path.read_text()
            if strip:
                text = release_ui.remove(text)
            patched = patch(text)
            self.assertNotEqual(patched, text, path)
            self.assertIn(release_ui.MARK, patched) if path.suffix == '.qml' else None
            self.assertEqual(patch(patched), patched, f'{path} not idempotent')
            self.assertEqual(release_ui.remove(patched), text, f'{path} not restored')

    def test_pristine_upstream(self):
        self.check_tree(PRISTINE, False)

    def test_installed(self):
        self.check_tree(INSTALLED, True)

    def test_blocks_balanced_and_single(self):
        if not PRISTINE.is_dir():
            self.skipTest('pristine QS not available')
        for path, patch in release_ui.transformations(PRISTINE).items():
            if path.suffix != '.qml':
                continue
            patched = patch(path.read_text())
            begins = re.findall(r'// BEGIN ' + release_ui.MARK + r' (.+)', patched)
            ends = re.findall(r'// END ' + release_ui.MARK + r' (.+)', patched)
            self.assertEqual(begins, ends)
            self.assertEqual(len(begins), len(set(begins)))

    def test_missing_anchors_fail_closed(self):
        for path, patch in release_ui.transformations(QS).items():
            if path.suffix == '.qml':
                with self.assertRaises(ValueError):
                    patch('Item {}\n')

    def test_duplicate_anchor_fails_closed(self):
        if not PRISTINE.is_dir():
            self.skipTest('pristine QS not available')
        popup = (PRISTINE/'guide/GuidePopup.qml').read_text()
        with self.assertRaises(ValueError):
            release_ui.patch_popup(popup + '\n' + popup)

    def test_qmldir_without_trailing_newline(self):
        patch = release_ui._qmldir_patch('guide/qmldir')
        patched = patch('GuideTab 1.0 GuideTab.qml')
        self.assertTrue(patched.endswith('\n'))
        self.assertEqual(release_ui.remove(patched), 'GuideTab 1.0 GuideTab.qml\n')

    def test_updater_contract(self):
        text = payload('AddonsUpdater')
        self.assertTrue(text.startswith('pragma Singleton'))
        for token in ['if (proc.running) return', 'JSON.parse', 'catch (e)', 'interval: 60 * 60 * 1000', 'function check(force)',
                      'updateAvailable', 'needsReinstall', 'attention', 'kitty --hold', '${TERM:-xterm} -hold -e',
                      'curl -fsSL', 'https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/', 'installerRef', '"/install/install.sh"', r'/^[0-9]+(\.[0-9]+)*$/', '"main"',
                      'source/install/install.sh', '"--force"', 'addons_release.py']:
            self.assertIn(token, text)
        match = re.search(r'allowedArgs: (\[[^\]]*\])', text)
        self.assertEqual(re.findall(r'"([^"]+)"', match.group(1)), ['update', 'reinstall', '--focus uninstall'])
        for state in ['not_installed', 'reinstall_needed', 'error', 'serpantinum_outdated', 'incompatible', 'available', 'dev', 'up_to_date']:
            self.assertIn(f'"{state}"', text)

    def test_every_launch_call_uses_a_whitelisted_argument(self):
        allowed = {'update', 'reinstall', '--focus uninstall'}
        texts = [payload('AddonsReleaseCard')]
        if PRISTINE.is_dir():
            texts.append(release_ui.patch_about((PRISTINE/'guide/AboutTab.qml').read_text()))
        seen = set()
        for text in texts:
            for line in re.findall(r'^.*\blaunch(?:AndClose)?\(.*$', text, flags=re.M):
                if 'function ' in line:
                    continue
                seen.update(set(re.findall(r'"([^"]+)"', line)) - {'reinstall_needed', 'function'})
        self.assertEqual(seen, allowed)

    def test_card_contract(self):
        text = payload('AddonsReleaseCard')
        for token in ['ThemeBackend.peach', 'ThemeBackend.red', 'fillDuration: 1200', 'fillDuration: 1500', 'Easing.OutQuint', 'duration: 400',
                      'Serpantinum Addons', 'Update addons', 'Reinstall addons', 'Uninstall addons', 'Changelog', 'Check now',
                      'Qt.openUrlExternally(AddonsUpdater.notesUrl)', 'AddonsUpdater.check(true)', 'dismissHost', 'showUninstall',
                      'newer than tested', 'older than supported', 'compatible', 'checking…', 'up to date', 'offline: ', 'dev build',
                      'Requires a newer Serpantinum', 'required property var rootObj']:
            self.assertIn(token, text)

    def test_button_contract(self):
        text = payload('AddonsUpdateButton')
        for token in ['ThemeBackend.peach', 'ThemeBackend.crust', '󰏗', 'Addons update', 'Reinstall addons', 'popup.compact',
                      'AddonsUpdater.attention', 'popup.gotoTab("about")']:
            self.assertIn(token, text)

    def test_addons_tab_has_maintenance_group(self):
        text = payload('AddonsTab')
        self.assertIn('title: "Addons maintenance"', text)
        self.assertIn('description: "Version, updates and removal"', text)
        self.assertIn('icon: "󰏗"', text)
        self.assertIn('AddonsReleaseCard { rootObj: root.rootObj; showUninstall: true }', text)
        self.assertGreater(text.index('addons_maintenance'), text.index('title: "Passive addons"'))
        self.assertEqual(text.count('SettingsGroup {'), 2)

    def test_qmllint_syntax(self):
        linter = next((p for p in (shutil.which('qmllint'), shutil.which('qmllint6'), '/usr/lib/qt6/bin/qmllint') if p and Path(p).exists()), None)
        if not linter:
            self.skipTest('qmllint not available')
        files = [ROOT/'payload'/f'{n}.qml' for n in QML] + [ROOT/'payload/AddonsTab.qml']
        for file in files:
            result = subprocess.run([linter, str(file)], capture_output=True, text=True)
            output = result.stdout + result.stderr
            self.assertNotRegex(output, r'(?i)syntax error|unexpected token|expected .* but', f'{file.name}: {output}')


if __name__ == '__main__':
    unittest.main()
