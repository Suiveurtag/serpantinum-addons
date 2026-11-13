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
        self.install_missing(tty=True, prefix=['sudo', 'pacman', '-S', '--needed'])

    def test_captured_output_never_waits_for_an_invisible_sudo_password(self):
        self.install_missing(tty=False, prefix=['sudo', '-n', 'pacman', '-S'])

    def install_missing(self, tty, prefix):
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
            return mock.Mock(returncode=0, stdout=self.installer.BEAMER_APP + '\t1.5.18\n')

        with mock.patch.object(self.installer.shutil, 'which', side_effect=which), \
             mock.patch.object(self.installer, '_beamer_missing', side_effect=lambda t: t in missing), \
             mock.patch.object(self.installer.subprocess, 'run', side_effect=run), \
             mock.patch.object(self.installer.sys, 'stdout', mock.Mock(isatty=lambda: tty)):
            self.installer.ensure_beamer_dependencies()
        self.assertEqual(calls[0][:len(prefix)], prefix)
        self.assertIn('flatpak', calls[0])
        self.assertIn('wl-clipboard', calls[0])
        self.assertIn('gcc', calls[0])
        self.assertEqual(len(calls), 2)   # the package install, then the read-only Flatpak listing: no Flathub fetch

    def test_missing_flatpak_app_is_a_quiet_skip(self):
        calls = []

        def run(argv, **kwargs):
            calls.append(argv)
            return mock.Mock(returncode=0, stdout='')

        with mock.patch.object(self.installer, '_beamer_missing', side_effect=lambda t: False), \
             mock.patch.object(self.installer.shutil, 'which', return_value='/usr/bin/x'), \
             mock.patch.object(self.installer.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'not installed'):
                self.installer.ensure_beamer_dependencies()
        self.assertEqual(calls, [['flatpak', 'list', '--user', '--app', '--columns=application,version']])

    def test_unpackaged_hyprland_is_a_clear_error(self):
        with mock.patch.object(self.installer, '_beamer_missing', side_effect=lambda t: t == 'hyprctl'):
            with self.assertRaisesRegex(RuntimeError, 'Hyprland is required'):
                self.installer.ensure_beamer_dependencies()


if __name__ == '__main__':
    unittest.main()
