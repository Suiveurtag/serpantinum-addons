import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import niri_config


class ConfigTests(unittest.TestCase):
    def test_real_validation_and_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            previous = niri_config.CONFIG
            niri_config.CONFIG = Path(directory)
            try:
                main = Path(directory) / 'niri/config.kdl'
                main.parent.mkdir()
                main.write_text('input { keyboard { xkb { layout "fr"; }; }; }\n')
                niri_config.update('mouse', 'input { mouse { accel-profile "flat"; }; }\n')
                good = main.read_bytes()
                fragment = main.with_name('serpantinum-mouse.kdl')
                content = fragment.read_bytes()
                with self.assertRaises(ValueError):
                    niri_config.update('mouse', 'input { invalid-setting 2; }\n')
                self.assertEqual(main.read_bytes(), good)
                self.assertEqual(fragment.read_bytes(), content)
                niri_config.update('mouse', content.decode())
                self.assertEqual(main.read_bytes(), good)
            finally:
                niri_config.CONFIG = previous

if __name__ == '__main__':
    unittest.main()
