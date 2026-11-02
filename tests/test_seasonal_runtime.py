"""Actual Qt animation/lifetime regression test, without opening desktop windows."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
class SeasonalRuntimeTests(unittest.TestCase):
    def test_animation_lifetimes_and_retriggering(self):
        self.run_fixture("seasonal_lifecycle.qml")

    def test_new_surface_effect_lifetimes(self):
        self.run_fixture("seasonal_surfaces.qml")

    def test_directional_arrivals_bar_and_intro(self):
        self.run_fixture("seasonal_arrivals.qml")

    def test_settings_atmosphere_follows_content_and_unloads(self):
        import seasonal_surfaces
        self.run_fixture("settings_window.qml", seasonal_surfaces.guide)

    def run_fixture(self, filename, transform=lambda source: source):
        with tempfile.TemporaryDirectory(prefix='serpantinum-motion-test-') as directory:
            fixture = Path(directory)
            shutil.copytree(ROOT/'payload/seasonal', fixture/'seasonal')
            (fixture/'Shell.qml').write_text(transform((ROOT/'tests/qml'/filename).read_text()))
            import seasonal
            (fixture/'qmldir').write_text(seasonal.patch_qmldir('singleton Config 1.0 Config.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\n'))
            (fixture/'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    id: config
    property bool season: true
    property bool performance: false
    function getSetting(key, fallback) { return key === "addonsV2Halloween" ? season : (key === "general.performance" ? performance : fallback); }
    function setSetting(key, value) { if (key === "addonsV2Halloween") season = value; else if (key === "general.performance") performance = value; }
}
''')
            (fixture/'ThemeBackend.qml').write_text('''pragma Singleton
import QtQuick
import "./"
QtObject {
    property color _normalbase: "#232128"
    property color base: Halloween.presentColor("base", _normalbase)
}
''')
            runtime = fixture/'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SEASONAL_PASS', output)
            self.assertNotIn('SEASONAL_FAIL', output)


if __name__ == '__main__':
    unittest.main()
