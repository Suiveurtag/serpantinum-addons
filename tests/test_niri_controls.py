import copy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import niri_controls
import niri_config
import control
from niri_kdl import parse


class BindingTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.base = Path(directory.name)
        for module in (niri_controls, niri_config):
            p = patch.object(module, 'CONFIG', self.base)
            p.start(); self.addCleanup(p.stop)
        p = patch.object(control, 'STATE', self.base / 'backups')
        p.start(); self.addCleanup(p.stop)
        self.main = self.base / 'niri/config.kdl'
        self.main.parent.mkdir()
        self.main.write_text('''// keep me
input { keyboard { xkb { layout "fr"; }; }; }
include "keys.kdl"
binds {
    Mod+T hotkey-overlay-title="Terminal" {
        spawn "kitty" "--title" "a{b};c"
    }
    Mod+Left { focus-column-left; }
}
''')
        self.included = self.main.with_name('keys.kdl')
        self.included.write_text('''/* a nested /* comment */ survives */
binds {
    Mod+F { spawn-sh r#"printf 'x{y};z'"#; }
}
''')

    def test_multiline_includes_native_actions_and_additions(self):
        payload = niri_controls.keybinds()
        self.assertEqual([r['key'] for r in payload['rows']], ['SUPER+T', 'SUPER+Left', 'SUPER+F'])
        payload['rows'][0]['key'] = 'SUPER + Shift + T'
        payload['rows'][2]['command'] = 'printf "%s" "edited { value }"'
        payload['rows'].append(dict(line=-1, key='SUPER+X', command='kitty --title new'))
        saved = niri_controls.save_keys(payload)
        self.assertEqual(len(saved['rows']), 4)
        self.assertIn('hotkey-overlay-title="Terminal"', self.main.read_text())
        self.assertIn('focus-column-left;', self.main.read_text())
        self.assertIn('a{b};c', self.main.read_text())
        self.assertIn('/* a nested /* comment */ survives */', self.included.read_text())
        self.assertIn('spawn-sh', self.included.read_text())

    def test_invalid_binding_rolls_back_every_file(self):
        payload = niri_controls.keybinds()
        old = [p.read_bytes() for p in (self.main, self.included)]
        payload['rows'][0]['key'] = 'InvalidModifier+T'
        payload['rows'][2]['command'] = 'echo changed'
        with self.assertRaises(ValueError):
            niri_controls.save_keys(payload)
        self.assertEqual([p.read_bytes() for p in (self.main, self.included)], old)

    def test_external_include_edit_prevents_write(self):
        payload = niri_controls.keybinds()
        self.included.write_text(self.included.read_text() + '// external\n')
        with self.assertRaisesRegex(ValueError, 'outside'):
            niri_controls.save_keys(payload)

    def test_delete_native_action_keeps_surrounding_config(self):
        payload = niri_controls.keybinds()
        payload['rows'] = [r for r in payload['rows'] if r['key'] != 'SUPER+Left']
        niri_controls.save_keys(payload)
        self.assertNotIn('focus-column-left', self.main.read_text())
        self.assertIn('input { keyboard', self.main.read_text())

    def test_disabled_nodes_and_braces_in_strings(self):
        nodes = parse('/- binds { Mod+Q { quit; }; }\nbinds { Mod+T { spawn r#"{a} /* b */"#; }; }\n')
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0].children[0].name, 'Mod+T')

if __name__ == '__main__':
    unittest.main()
