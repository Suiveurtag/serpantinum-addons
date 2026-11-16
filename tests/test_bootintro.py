import sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import bootintro

SHELL = '''ShellRoot {
    Main {}
    function ensureScreenshotOverlay() {
    }
}
'''


class BootIntroTest(unittest.TestCase):
    def test_shell_patch_is_idempotent_and_fail_closed(self):
        once = bootintro.patch_shell(SHELL)
        self.assertEqual(once, bootintro.patch_shell(once))
        self.assertEqual(once.count('AddonBootIntro {}'), 1)
        self.assertLess(once.index('AddonBootIntro {}'), once.index('function ensureScreenshotOverlay()'))
        with self.assertRaises(ValueError):
            bootintro.patch_shell('ShellRoot {}\n')
        self.assertEqual(bootintro.remove(once), SHELL)

    def test_qmldir_declares_and_removes_types(self):
        text = bootintro.patch_qmldir('Main 1.0 Main.qml\n')
        self.assertEqual(text, bootintro.patch_qmldir(text))
        for declaration in bootintro.TYPES:
            self.assertIn(declaration, text)
        self.assertEqual(bootintro.remove(text), 'Main 1.0 Main.qml\n')

    def test_resources_are_the_qml_scene_and_old_shaders_are_swept(self):
        with tempfile.TemporaryDirectory() as tmp:
            qs = Path(tmp)
            names = sorted(p.name for p, _ in bootintro.resources(qs))
            self.assertEqual(names, ['AddonBootIntro.qml', 'BootIntroScreen.qml'])
            screen = (ROOT/'payload/bootintro/BootIntroScreen.qml').read_text()
            for upstream in ('shaders/effects/screen_wipe.frag.qsb', 'shaders/fluid/logo_water_wave.frag.qsb', 'shaders/effects/vignette.frag.qsb', '"logo.svg"'):
                self.assertIn(upstream, screen)
            (qs/'bootintro/shaders').mkdir(parents=True)
            (qs/'bootintro/shaders/vortex.000000000000.frag.qsb').write_bytes(b'old')
            self.assertEqual([p.name for p in bootintro.stale_shaders(qs)], ['vortex.000000000000.frag.qsb'])

    def test_option_is_on_by_default(self):
        tab = (ROOT/'payload/AddonsTab.qml').read_text()
        self.assertIn('Config.getSetting("addonsV2BootIntro", true) !== false', tab)
        host = (ROOT/'payload/bootintro/AddonBootIntro.qml').read_text()
        self.assertIn('Config.getSetting("addonsV2BootIntro", true) !== false', host)
        self.assertIn('target: "addonBootIntro"', host)


if __name__ == '__main__':
    unittest.main()
