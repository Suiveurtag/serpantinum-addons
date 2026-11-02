"""Beamer prerequisites are installed by install.py instead of being reported as a skipped note."""
import os
import unittest
from unittest import mock

from test_changes import ROOT, load


class BeamerDependencies(unittest.TestCase):
    def setUp(self):
        self.installer = load('installer_beamer_deps', ROOT/'install.py')
        env = mock.patch.dict(os.environ)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop(self.installer.NO_SERVICES, None)

    def test_missing_tools_are_installed_with_the_detected_manager(self):
        missing = {'flatpak', 'wl-paste', 'cc'}
        calls = []

        def which(name):
            if name == 'pacman':
                return '/usr/bin/pacman'
            if name in missing:
                return None
            return '/usr/bin/' + name

        def run(argv, **kwargs):
            calls.append(argv)
            missing.clear()
            return mock.Mock(returncode=0, stdout='')

        with mock.patch.object(self.installer.shutil, 'which', side_effect=which), \
             mock.patch.object(self.installer, '_beamer_missing', side_effect=lambda t: t in missing), \
             mock.patch.object(self.installer.subprocess, 'run', side_effect=run):
            self.installer.ensure_beamer_dependencies()
        self.assertEqual(calls[0][:4], ['sudo', 'pacman', '-S', '--needed'])
        self.assertIn('flatpak', calls[0])
        self.assertIn('wl-clipboard', calls[0])
        self.assertIn('gcc', calls[0])

    def test_unpackaged_hyprland_is_a_clear_error(self):
        with mock.patch.object(self.installer, '_beamer_missing', side_effect=lambda t: t == 'hyprctl'):
            with self.assertRaisesRegex(RuntimeError, 'Hyprland is required'):
                self.installer.ensure_beamer_dependencies()


if __name__ == '__main__':
    unittest.main()
