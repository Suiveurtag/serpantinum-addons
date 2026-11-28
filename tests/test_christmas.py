import hashlib
import json
import re
import subprocess
import sys
import unittest

from test_changes import ROOT, installer

sys.path.insert(0, str(ROOT))
import christmas  # noqa: E402
import seasonal  # noqa: E402
import snowhush  # noqa: E402

PAYLOAD = ROOT/'payload/christmas'


class ChristmasPatchTests(unittest.TestCase):
    def test_every_hook_is_idempotent_and_removable(self):
        for path, transform in christmas.transformations(installer.QS).items():
            with self.subTest(file=path.name):
                original = christmas.remove(path.read_text())   # the live shell may already carry the hooks
                once = transform(original)
                self.assertNotEqual(once, original)
                self.assertEqual(transform(once), once)
                self.assertEqual(christmas.remove(once), original)
                self.assertNotIn(christmas.MARK, christmas.remove(once))

    def test_hooks_compose_with_the_seasonal_and_snow_hush_layers(self):
        layers = {**seasonal.transformations(installer.QS)}
        snow = snowhush.transformations(installer.QS)
        for path, transform in christmas.transformations(installer.QS).items():
            others = [f for f in (layers.get(path), snow.get(path)) if f]
            if not others:
                continue
            with self.subTest(file=path.name):
                def stacked(text):
                    for other in others:
                        text = other(text)
                    return transform(text)
                once = stacked(christmas.remove(path.read_text()))
                self.assertEqual(stacked(once), once)
                self.assertEqual(once.count(f'// BEGIN {christmas.MARK}'), once.count(f'// END {christmas.MARK}'))
                stripped = christmas.remove(once)
                self.assertNotIn('Christmas', stripped)
                for other in others:
                    self.assertEqual(other(stripped), stripped)

    def test_changed_anchor_fails_closed(self):
        for patch in (christmas.patch_main, christmas.patch_bar, christmas.patch_settings_row, christmas.patch_icon_button,
                      christmas.patch_notification, christmas.patch_shell, christmas.patch_launcher):
            with self.subTest(patch=patch.__name__), self.assertRaises(ValueError):
                patch('Item {\n    id: somethingElse\n}\n')

    def test_qmldir_declares_every_component(self):
        declared = {line.split()[-1] for line in christmas.TYPES}
        self.assertEqual(declared, {'christmas/' + p.name for p in PAYLOAD.glob('*.qml')})
        qmldir = christmas.remove((installer.QS/'qmldir').read_text())
        patched = christmas.patch_qmldir(qmldir)
        self.assertEqual(christmas.patch_qmldir(patched), patched)
        self.assertIn('singleton Christmas 1.0 christmas/Christmas.qml', patched)
        self.assertEqual(christmas.remove(patched), qmldir)

    def test_banner_option_is_owned_by_christmas_only(self):
        tab = (ROOT/'payload/AddonsBannersTab.qml').read_text()
        self.assertIn('ChristmasSettings { rootObj: root.rootObj', tab)
        stripped = christmas.remove(tab)
        self.assertNotIn('Christmas', stripped)
        for other in ('SnowHushCard', 'ClawdSettings', 'CapriSettings', 'HalloweenCard'):
            self.assertIn(other, stripped)
        self.assertIn('ChristmasSettings', seasonal.remove(tab))

    def test_component_property_names_do_not_shadow_final_item_properties(self):
        # Qt refuses to load a component that redeclares a FINAL property of Item ("Cannot override FINAL property").
        final = r'(top|bottom|left|right|horizontalCenter|verticalCenter|baseline|enabled|palette|state|smooth|data|layer|' \
                r'visible|opacity|scale|rotation|x|y|z|width|height|parent|children|anchors|clip|focus)'
        for source in PAYLOAD.glob('*.qml'):
            with self.subTest(file=source.name):
                text = source.read_text()
                if source.name == 'Christmas.qml':
                    self.assertRegex(text, r'\nScope \{\n')   # no Item properties to collide with
                    continue
                self.assertIsNone(re.search(r'property \w+ ' + final + r':', text))


class ChristmasResourceTests(unittest.TestCase):
    def test_shaders_match_their_packages(self):
        result = subprocess.run([sys.executable, str(ROOT/'scripts/christmas/shaders.py'), '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_resources_use_content_hashed_shaders(self):
        out = dict(christmas.resources(PAYLOAD, installer.QS))
        names = {path.name for path in out if path.parent == installer.QS/'christmas/shaders'}
        manifest = json.loads((PAYLOAD/'shaders/manifest.json').read_text())
        for stem, record in manifest.items():
            self.assertIn(f"{stem}.{record['package_sha256'][:12]}.frag.qsb", names)
        for path, blob in out.items():
            if path.suffix == '.qml':
                self.assertNotRegex(blob.decode(), r'shaders/\w+\.frag\.qsb', path.name)
        lights = out[installer.QS/'christmas/ChristmasLights.qml'].decode()
        self.assertIn(f"shaders/lights.{manifest['lights']['package_sha256'][:12]}.frag.qsb", lights)
        self.assertIn(installer.QS/'christmas/glade-jul.jpg', out)
        self.assertEqual(hashlib.sha256(out[installer.QS/'christmas/glade-jul.jpg']).hexdigest(),
                         hashlib.sha256((PAYLOAD/'glade-jul.jpg').read_bytes()).hexdigest())

    def test_fonts_ship_with_their_licence(self):
        self.assertTrue((PAYLOAD/'BerkshireSwash-Regular.ttf').is_file())
        self.assertIn('SIL Open Font License', (PAYLOAD/'BerkshireSwash-OFL.txt').read_text())

    def test_settings_and_ipc_surface(self):
        singleton = (PAYLOAD/'Christmas.qml').read_text()
        for key in ('addonsV2Christmas"', 'addonsV2ChristmasLights', 'addonsV2ChristmasTwinkle', 'addonsV2ChristmasFx.'):
            self.assertIn(key, singleton)
        handler = singleton[singleton.index('IpcHandler {'):]
        self.assertEqual(sorted(re.findall(r'function (\w+)\(', handler)), ['intro', 'setArea', 'setEnabled', 'setLights', 'status', 'toggle'])
        self.assertIn('target: "christmas"', handler)


if __name__ == '__main__':
    unittest.main()
