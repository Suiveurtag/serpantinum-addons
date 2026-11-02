import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
spec = importlib.util.spec_from_file_location('window_outline', Path(__file__).resolve().parents[1] / 'scripts/window_outline.py')
outline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(outline)


class WindowOutlineTest(unittest.TestCase):
    def test_enable_update_disable_and_reload_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            main, lua = base / 'hyprland.lua', base / 'config/outline.lua'
            main.write_text('existing config\n')
            calls = []
            def run(*args):
                calls.append(args)
                return ''
            with patch.object(outline, 'MAIN', main), patch.object(outline, 'LUA', lua), patch.object(outline, 'run', side_effect=run):
                colors = ('#112233', '#445566', '#778899')
                outline.apply(False, *colors)
                self.assertFalse(lua.exists())
                outline.apply(True, *colors)
                self.assertIn('border_size = 2', lua.read_text())
                self.assertIn('rgba(112233e6)', lua.read_text())
                outline.apply(True, *colors)
                self.assertEqual(calls.count(('hyprctl', 'reload')), 1)
                outline.apply(True, '#abcdef', *colors[1:])
                self.assertIn('rgba(abcdefe6)', lua.read_text())
                outline.apply(False, *colors)
                self.assertIn('border_size = 0', lua.read_text())
                self.assertEqual(main.read_text().count('require("config/serpantinum_window_outline")'), 1)
                old = lua.read_text()
                with patch.object(outline, 'run', side_effect=['', 'bad config', '']):
                    with self.assertRaises(ValueError):
                        outline.apply(True, *colors)
                self.assertEqual(lua.read_text(), old)
                with self.assertRaises(ValueError):
                    outline.apply(True, 'invalid', *colors[1:])


if __name__ == '__main__':
    unittest.main()
