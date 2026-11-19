import sys
import unittest
from pathlib import Path

from test_changes import ROOT

sys.path.insert(0, str(ROOT))
import agenda  # noqa: E402

DAY_CELL = '''                            ClickButton {
                                Layout.fillWidth: true
                                enabled: false
                                buttonText: dayNum
                                textFontSize: window.s(11.5)
                            }
'''
CLOCK = '''                    ColumnLayout {
                        id: clockBlock
                    }

                    Item {
                        id: hourStrip
                        readonly property real pad: window.s(4)
                    }
'''
WRAPPER = (ROOT/'payload/CalendarPopup.qml').read_text()
DASHBOARD = '''    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: dashboardWindow.isOpen
        onActivated: dashboardWindow.closeDashboard()
    }
'''
SHELL = 'ShellRoot {\n    function ensureScreenshotOverlay() {\n    }\n}\n'


class AgendaPatchTest(unittest.TestCase):
    def roundtrip(self, patch, text):
        patched = patch(text)
        self.assertIn('BEGIN ' + agenda.MARK, patched)
        self.assertEqual(patch(patched), patched, 'patch must be idempotent')
        self.assertEqual(agenda.remove(patched), text, 'remove must restore the upstream text')
        return patched

    def test_native_day_cells_and_next_chip(self):
        patched = self.roundtrip(agenda.patch_native, DAY_CELL + CLOCK)
        self.assertNotIn('enabled: false', patched)
        self.assertIn('enabled: GCal.available', patched)
        self.assertIn('GCalDayDots', patched)
        self.assertLess(patched.index('GCalNextChip'), patched.index('id: hourStrip'))

    def test_wrapper_hosts_layer(self):
        patched = self.roundtrip(agenda.patch_wrapper, WRAPPER)
        self.assertTrue(patched.rstrip().endswith('}'))
        self.assertIn('GCalLayer { host: root }', patched)

    def test_dashboard_escape_asks_calendar_first(self):
        patched = self.roundtrip(agenda.patch_dashboard, DASHBOARD)
        self.assertIn('GCal.handleEscape()', patched)
        self.assertEqual(patched.count('onActivated'), 1)

    def test_shell_and_qmldir(self):
        self.roundtrip(agenda.patch_shell, SHELL)
        qmldir = agenda.patch_qmldir('singleton DateTime 1.0 singletons/system/DateTime.qml\n')
        self.assertIn('singleton GCal 1.0 gcal/GCal.qml', qmldir)
        registered = {line.split()[0] for line in qmldir.splitlines() if 'gcal/' in line and not line.startswith('singleton')}
        on_disk = {p.stem for p in (ROOT/'payload/gcal').glob('*.qml')} - {'GCal'}
        self.assertEqual(registered, on_disk)
        self.assertEqual(agenda.patch_qmldir(qmldir), qmldir)
        self.assertEqual(agenda.remove(qmldir), 'singleton DateTime 1.0 singletons/system/DateTime.qml\n')

    def test_changed_upstream_skips_optional_hooks(self):
        self.assertEqual(agenda.patch_native('Item {}\n'), 'Item {}\n')
        self.assertEqual(agenda.patch_dashboard('Shortcut {}\n'), 'Shortcut {}\n')
        only_cells = agenda.patch_native(DAY_CELL)
        self.assertIn('GCalDayDots', only_cells)
        self.assertEqual(agenda.remove(only_cells), DAY_CELL)
        with self.assertRaises(ValueError):
            agenda.patch_wrapper('Item {}\n')

    def test_keybind_block(self):
        text = agenda.patch_keybind('hl.bind("SUPER + S", hl.dsp.exec_cmd("x"))\n', Path('/qs/Shell.qml'))
        self.assertIn('hl.bind("SUPER + G"', text)
        self.assertIn('ipc call addonCalendar toggle', text)
        self.assertIn('hl.bind("SUPER + I"', text)
        self.assertIn('ipc call addonCalendar toggle', text)
        self.assertEqual(agenda.patch_keybind(text, Path('/qs/Shell.qml')), text)
        self.assertEqual(agenda.remove(text).strip(), 'hl.bind("SUPER + S", hl.dsp.exec_cmd("x"))')
        with self.assertRaises(ValueError):
            agenda.patch_keybind('hl.bind("SUPER + G", hl.dsp.exec_cmd("y"))\n', Path('/qs/Shell.qml'))

    def test_resources_cover_every_qml(self):
        files = agenda.resources(ROOT/'payload/gcal', Path('/qs'))
        self.assertTrue(all(str(path).startswith('/qs/gcal/') for path, _ in files))
        self.assertIn(Path('/qs/gcal/GCalAgenda.qml'), [path for path, _ in files])

    def test_unit_runs_daemon(self):
        self.assertIn('gcal.py daemon', agenda.unit(Path('/d/scripts/gcal/gcal.py')))


if __name__ == '__main__':
    unittest.main()
