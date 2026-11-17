"""Exercise generated session commands through the installed SDDM wrapper."""
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


class SessionTests(unittest.TestCase):
    @unittest.skipUnless(Path('/usr/share/sddm/scripts/wayland-session').exists(), 'SDDM required')
    def test_sddm_launch_and_legacy_entry_upgrade(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            binary = home / '.local/opt/niri-serpantinum/bin/niri'
            script = home / '.local/share/serpantinum-addons-v2/scripts/niri-session.sh'
            for path in (binary, script):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('echo NIRI_SESSION_REACHED\n')
            setup = Path(__file__).resolve().parents[1] / 'scripts/setup-niri-session.py'
            with patch.object(Path, 'home', return_value=home):
                runpy.run_path(str(setup))
                entry = home / '.local/share/wayland-sessions/niri-serpantinum.desktop'
                good = entry.read_text()
                command = next(line[5:] for line in good.splitlines() if line.startswith('Exec='))
                result = subprocess.run(
                    ['/usr/share/sddm/scripts/wayland-session', command],
                    env={**os.environ, 'SHELL': '/bin/zsh'}, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('NIRI_SESSION_REACHED', result.stdout)
                entry.write_text(good.replace(command, command.replace('/usr/bin/bash ', '/usr/bin/bash "') + '"'))
                runpy.run_path(str(setup))
                self.assertEqual(entry.read_text(), good)
                entry.write_text('custom session\n')
                with self.assertRaises(SystemExit):
                    runpy.run_path(str(setup))
                self.assertEqual(entry.read_text(), 'custom session\n')
