import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


control = load('control', ROOT/'scripts/control.py')
installer = load('installer', ROOT/'install.py')


class ChangeTests(unittest.TestCase):
    def test_color_picker_hooks_are_idempotent(self):
        for file, patch in [('Shell.qml', installer.patch_shell), ('quickactions/Floating.qml', installer.patch_floating)]:
            original = (installer.QS/file).read_text()
            result = patch(original)
            self.assertEqual(result, patch(result))
        keys = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })\n'
        patched = installer.patch_keybinds(keys)
        self.assertEqual(patched, installer.patch_keybinds(patched))
        self.assertIn('addonColorPicker toggle', patched)

    def test_guide_idempotence_and_about_order(self):
        text = (installer.QS/'guide/GuidePopup.qml').read_text()
        patched = installer.patch_guide(text)
        self.assertEqual(patched, installer.patch_guide(patched))
        model = patched[patched.index('property var tabsModel:'):patched.index('    StackView.onStatusChanged:')]
        self.assertLess(model.index('id: "Keybinds"'), model.index('id: "About"'))
        self.assertIn('id: "Addons"', model)
        if '                                Rectangle {\n                                    id: tabAbout' in patched:
            self.assertEqual(patched.count('id: tabAddonMonitors\n'), 1)
            self.assertIn('tabAddonAddons, tabAddonMonitors, tabAddonKeybinds, tabAbout', patched)

    def test_addons_options_and_weather_patch_preserve_each_other(self):
        general = (ROOT/'payload/AddonsTab.qml').read_text()
        banners = (ROOT/'payload/AddonsBannersTab.qml').read_text()
        mouse = (ROOT/'payload/AddonsMouseTab.qml').read_text()
        for option in ('addons_mullvad_dns', 'addonsV2ObfuscateWeatherCity'):
            with self.subTest(option=option):
                self.assertIn(option, general)
        for option in ('HalloweenCard', 'CapriSettings', 'ClawdSettings'):
            with self.subTest(option=option):
                self.assertIn(option, banners)
        for option in ('addons_mouse_spotlight', 'addons_mouse_acceleration', 'addons_trackpad_speed',
                       'addons_trackpad_typing', 'addons_trackpad_clicks_typing'):
            with self.subTest(option=option):
                self.assertIn(option, mouse)
        self.assertIn('addons_legacy_clock', general)
        self.assertIn('SettingsGroup {', mouse)
        self.assertIn('spacing: rootObj.s(8)', mouse)
        self.assertIn('Layout.bottomMargin: rootObj.s(6)', banners)
        self.assertIn('opacity: root.noTrackpadDetected ? 0.38 : 1.0', mouse)
        self.assertEqual(mouse.count('settingId: "addons_trackpad_'), 3)

        weather_path = installer.QS/'widgets/faces/weather/WeatherFaceFull.qml'
        weather = installer.patch_weather_face(weather_path.read_text())
        self.assertIn('reshuffleCity()', weather)
        self.assertIn('interval: 90', weather)
        self.assertEqual(weather, installer.patch_weather_face(weather))

    def test_palette_overrides_sample_chosen_point(self):
        from PIL import Image
        colors = load('colors', ROOT/'scripts/colors.py')
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory)/'wall.png'
            wall = Image.new('RGB', (200, 100), (20, 60, 220))
            wall.paste((230, 20, 20), (100, 0, 200, 100))
            wall.save(image)
            auto, points = colors.palette(image, 'vibrant')
            self.assertEqual(auto['blue'], '#143cdc')
            self.assertFalse(points['blue']['manual'])
            moved, points = colors.palette(image, 'vibrant', {'blue': [0.9, 0.5]})
            self.assertEqual(moved['blue'], '#e61414')
            self.assertEqual((points['blue']['x'], points['blue']['manual']), (0.9, True))
            state = Path(directory)
            (state/colors.OVERRIDES).write_text(json.dumps({str(image): {'blue': [0.9, 0.5], 'bogus': [0, 0]}, 'other': {}}))
            self.assertEqual(colors.read_overrides(state, str(image)), {'blue': [0.9, 0.5]})
            (state/colors.OVERRIDES).write_text('{broken')
            self.assertEqual(colors.read_overrides(state, str(image)), {})

    def test_palette_editor_hook_is_idempotent(self):
        text = installer.patch_theme_view((installer.QS/'guide/theme/ThemeTab.qml').read_text())
        self.assertEqual(text, installer.patch_theme_view(text))
        self.assertEqual(text.count('AddonPaletteEditor { tab: themeTabRoot }'), 1)

    def test_theme_uses_original_tile_delegate(self):
        theme = installer.QS/'guide/theme/ThemeTabState.qml'
        text = (theme if theme.exists() else installer.QS/'guide/theme/ThemeTab.qml').read_text()
        text = installer.patch_theme(text)
        self.assertEqual(text, installer.patch_theme(text))
        self.assertNotIn('options: ["Matugen", "Vibrant", "Vivid"]', text)
        self.assertIn('{name: "Vibrant", isMatugen: true', text)
        self.assertIn('systemPresets = sys.slice()', text)

    def test_matugen_dedupe_includes_color_mode(self):
        original = (installer.QS/'singletons/theme/Matugen.qml').read_text()
        patched = installer.patch_matugen(original)
        self.assertEqual(patched, installer.patch_matugen(patched))
        self.assertEqual(patched.count('Config.getSetting("addonsV2ColorMode", "matugen")'), 4)

    def test_settings_sidebar_resolves_addon_titles(self):
        text = (installer.QS/'guide/GuideSidebar.qml').read_text()
        patched = installer.patch_guide_sidebar(text)
        self.assertEqual(patched, installer.patch_guide_sidebar(patched))
        self.assertIn('text: popup.resolveTabTitle(', patched)
        self.assertIn('text: popup.resolveSubtabTitle(', patched)

    def test_remove_obsolete_inline_settings(self):
        for prefix in ('//', '--'):
            original = f'before\n{prefix} BEGIN serpantinum-addons-v2 inline settings\nold\n{prefix} END serpantinum-addons-v2 inline settings\nafter\n'
            cleaned = installer.remove_inline_settings(original, prefix)
            self.assertEqual(cleaned, 'before\nafter\n')
            self.assertEqual(cleaned, installer.remove_inline_settings(cleaned, prefix))

    def test_native_patches_do_not_change_on_reinstall(self):
        patches = {
            'guide/IdleTab.qml': installer.patch_idle_tab,
            'guide/theme/ThemeTabState.qml': installer.patch_theme,
            'widgets/faces/weather/WeatherFaceFull.qml': installer.patch_weather_face,
        }
        for path, patch in patches.items():
            with self.subTest(path=path):
                patched = patch((installer.QS/path).read_text())
                self.assertEqual(patched, patch(patched))

    def test_key_edits_preserve_action_flags_and_generated_bindings(self):
        old_config, old_state, old_run = control.CONFIG, control.STATE, control.run
        try:
            with tempfile.TemporaryDirectory() as directory:
                control.CONFIG = Path(directory)
                control.STATE = Path(directory)/'backups'
                control.run = lambda *args: 'ok' if args[-1] == 'configerrors' else ''
                path = control.CONFIG/'hypr/config/keybinds.lua'
                path.parent.mkdir(parents=True)
                original = 'local mainMod = "SUPER"\nhl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty"), { locked = true })\nhl.bind("SUPER + Left", hl.dsp.focus({ direction = "left" }))\nfor i = 1, 10 do\n  hl.bind(mainMod .. " + " .. key, hl.dsp.exec_cmd("workspace " .. i))\nend\n'
                path.write_text(original)
                data = control.keybinds()
                self.assertEqual(len(data['rows']), 2)
                data['rows'][0]['key'] = 'SUPER + Y'
                data['rows'][0]['command'] = 'alacritty'
                control.save_keys(data)
                result = path.read_text()
                self.assertIn('hl.dsp.exec_cmd("alacritty"), { locked = true }', result)
                self.assertIn('hl.dsp.focus({ direction = "left" })', result)
                self.assertIn('hl.bind(mainMod .. " + " .. key,', result)
                with self.assertRaises(ValueError): control.save_keys(data)
        finally:
            control.CONFIG, control.STATE, control.run = old_config, old_state, old_run


if __name__ == '__main__':
    unittest.main()
