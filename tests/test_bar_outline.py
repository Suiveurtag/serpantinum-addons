import sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import bar_outline

QS = Path.home()/'.local/share/serpantinum/src/quickshell'


class BarOutlineTest(unittest.TestCase):
    def test_action_face_path_supports_old_and_new_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'bar/faces/left'
            folder.mkdir(parents=True)
            old = folder/'LeftFace.qml'
            new = folder/'ActionsFace.qml'
            old.touch()
            self.assertEqual(bar_outline.left_face_path(root), old)
            new.touch()
            self.assertEqual(bar_outline.left_face_path(root), new)

    def test_patches_are_idempotent_and_fail_closed(self):
        for path, transform in bar_outline.transformations(QS).items():
            if not path.is_file():
                self.skipTest(f'{path} not installed')
            once = transform(path.read_text())
            self.assertEqual(once, transform(once), path.name)
            self.assertIn(bar_outline.MARK, once)
            with self.assertRaises(ValueError):
                transform('// unrelated\n')

    def test_option_is_off_by_default(self):
        self.assertIn('Config.getSetting("addonsV2BarOutlines", false)', (ROOT/'payload/AddonsTab.qml').read_text())
        self.assertIn('requiresOption === "" ||', (ROOT/'payload/AddonButtonEffect.qml').read_text())


if __name__ == '__main__':
    unittest.main()
