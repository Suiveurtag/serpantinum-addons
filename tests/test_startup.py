import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import startup
import control
sys.path.pop(0)


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        base = Path(self.directory.name)
        for name, path in [('MAIN', base / 'hyprland.lua'),
                           ('LUA', base / 'config/serpantinum_startup.lua'),
                           ('SETTINGS', base / 'config/serpantinum_startup.json')]:
            p = patch.object(startup, name, path)
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(control, 'STATE', base / 'backups')
        p.start()
        self.addCleanup(p.stop)
        p = patch.object(startup, 'run', side_effect=lambda *args: 'bad config' if args[-1] == 'configerrors' and self.config_error else 'ok')
        self.runner = p.start()
        self.addCleanup(p.stop)
        self.config_error = False
        self.original = 'require("config/autostart")\n'
        startup.MAIN.write_text(self.original)

    def test_save_generates_quoted_commands_and_is_idempotent(self):
        result = startup.save(dict(revision=startup.status()['revision'], commands=[' discord ', 'sh -c "echo \\"é\\""']))
        self.assertEqual(result['commands'], ['discord', 'sh -c "echo \\"é\\""'])
        source = startup.LUA.read_text()
        self.assertIn('hl.on("hyprland.start"', source)
        self.assertIn('  hl.exec_cmd("discord")\n', source)
        self.assertIn('hl.exec_cmd("sh -c \\"echo \\\\\\"é\\\\\\"\\"")', source)
        startup.save(result)
        self.assertEqual(startup.MAIN.read_text().count('require("config/serpantinum_startup")'), 1)
        self.assertTrue(startup.MAIN.read_text().startswith(self.original))

    def test_reload_error_restores_files(self):
        self.config_error = True
        with self.assertRaisesRegex(ValueError, 'bad config'):
            startup.save(dict(revision=startup.status()['revision'], commands=['discord']))
        self.assertEqual(startup.MAIN.read_text(), self.original)
        self.assertFalse(startup.LUA.exists())
        self.assertFalse(startup.SETTINGS.exists())

    def test_invalid_commands_and_stale_revision_do_not_write(self):
        for commands in (['a\nb'], [''], [3], 'discord'):
            with self.assertRaisesRegex(ValueError, 'single non-empty line'):
                startup.save(dict(revision=startup.status()['revision'], commands=commands))
        with self.assertRaisesRegex(ValueError, 'outside this editor'):
            startup.save(dict(revision='stale', commands=['discord']))
        self.assertFalse(startup.LUA.exists())


if __name__ == '__main__':
    unittest.main()
