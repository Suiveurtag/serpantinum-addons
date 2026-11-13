import sys
import tempfile
import shutil
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import install
import seasonal
import seasonal_surfaces


class SeasonalIntegrationTests(unittest.TestCase):
    def test_retired_audio_boost_is_removed_without_touching_upstream(self):
        marker = 'serpantinum-addons-v2 audio boost'
        upstream = '"dynamics": "off"\n'
        patched = (f'// BEGIN {marker} state\nfunction setBoost() {{}}\n'
                   f'// END {marker} state\n' +
                   '"dynamics": "off", "boost": 0\n        temp.boost = 0;\n')
        self.assertEqual(seasonal_surfaces.remove_audio_boost_qml(patched), upstream)
        self.assertEqual(seasonal_surfaces.remove_audio_boost_qml(upstream), upstream)
        newer_backend = '#!/usr/bin/env bash\n# Serpantinum Audio\n'
        self.assertEqual(seasonal_surfaces.remove_audio_boost_backend(newer_backend), newer_backend)

    def test_control_hook_preserves_unrelated_escape_calls(self):
        original = 'Item {\n    id: root\n    function leave() { thirdParty.escape(); }\n}\n'
        self.assertEqual(original, seasonal.remove(seasonal.patch_control(original)))

    def test_stale_shader_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)/'shaders'
            shutil.copytree(ROOT/'payload/seasonal/shaders', folder)
            name = install.shader_package_name(folder)
            self.assertTrue(name.endswith('.frag.qsb'))
            source = folder/'atmosphere.frag'
            source.write_text(source.read_text() + '\n// unrecompiled modification\n')
            with self.assertRaisesRegex(ValueError, 'source/package mismatch'):
                install.shader_package_name(folder)

    def test_damaged_shader_package_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)/'shaders'
            shutil.copytree(ROOT/'payload/seasonal/shaders', folder)
            (folder/'atmosphere.frag.qsb').write_bytes(b'damaged')
            with self.assertRaisesRegex(ValueError, 'source/package mismatch'):
                install.shader_package_name(folder)

    def test_reinstall_does_not_duplicate_or_rewrite_hooks(self):
        for path, transform in seasonal.transformations(install.QS).items():
            with self.subTest(path=path.name):
                result = transform(path.read_text())
                self.assertEqual(result, transform(result))

    def test_normal_color_assignment_is_separate_from_presentation(self):
        colors = ['base', 'mantle', 'crust', 'surface0', 'surface1', 'surface2',
                  'overlay0', 'overlay1', 'overlay2', 'text', 'subtext0', 'subtext1',
                  'blue', 'sapphire', 'peach', 'green', 'red', 'mauve', 'pink', 'yellow', 'maroon', 'teal']
        # Model the upstream storage/assignment contract, including a custom hue.
        source = '    id: root\n' + '\n'.join(f'    property color {key}: "#123456"' for key in colors)
        source += '\nif (root[propName].toString() !== nextColor.toString()) { root[propName] = nextColor; }'
        source += '\nroot[names[i]]; root[item.name]; root[slot];'
        result = seasonal.patch_palette(source)
        for key in colors:
            self.assertIn(f'property color _normal{key}: "#123456"', result)
            self.assertIn(f'Halloween.presentColor("{key}", _normal{key})', result)
        self.assertIn('root["_normal" + names[i]]', result)
        self.assertIn('root["_normal" + item.name]', result)
        self.assertIn('root["_normal" + slot]', result)
        self.assertNotIn('root[propName] =', result)
        self.assertEqual(result, seasonal.patch_palette(result))
        self.assertEqual(seasonal.remove(result), source)

    def test_changed_upstream_palette_fails_before_installation(self):
        with self.assertRaises(ValueError):
            seasonal.patch_palette('property color newPalette: "#123456"')

    def test_removal_restores_normal_color_assignment_and_all_hooks(self):
        for path, transform in seasonal.transformations(install.QS).items():
            with self.subTest(path=path.name):
                result = seasonal.remove(transform(path.read_text()))
                self.assertNotIn('Halloween.', result)
                self.assertNotIn('sourceComponent: NightPanel', result)
                self.assertNotIn('sourceComponent: BatBurst', result)
                self.assertNotIn('property color _normal', result)
                self.assertNotIn('root["_normal"', result)
                self.assertEqual(result, seasonal.remove(result))

    def test_native_clock_keeps_the_normal_orbit(self):
        source = (install.QS/'calendar/NativeCalendar.qml').read_text()
        result = seasonal.patch_calendar(source)
        self.assertEqual(result, seasonal.patch_calendar(result))
        if 'id: orbitCanvas' in source:
            self.assertEqual(result.count('id: orbitCanvas'), 1)
            self.assertEqual(result.count('sourceComponent: CelestialDial'), 1)
            self.assertIn('visible: !Halloween.activeSeason', result)
        else:
            self.assertIn('id: centralHub', result)
            self.assertNotIn('sourceComponent: CelestialDial', result)


if __name__ == '__main__':
    unittest.main()
