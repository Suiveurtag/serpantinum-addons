"""Material transitions keep fallback colours and unload when hidden."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
class GlassRuntimeTests(unittest.TestCase):
    def test_material_switch_and_visibility(self):
        with tempfile.TemporaryDirectory(prefix='serpantinum-glass-') as directory:
            fixture = Path(directory)
            reusables = fixture/'reusables'
            reusables.mkdir()
            shutil.copy2(ROOT/'payload/AddonGlassSurface.qml', reusables)
            (fixture/'qmldir').write_text('singleton ThemeBackend 1.0 ThemeBackend.qml\n')
            (fixture/'ThemeBackend.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool liquidGlass: false
    property bool blurBackground: false
    property real elementOpacity: 0.4
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999
    property color surface0: "#312618"
    property color text: "white"
}
''')
            # Model the native backdrop contract without a compositor or GPU shader.
            (reusables/'GlassFill.qml').write_text('''import QtQuick
import "../"
Item {
    property real radius: 0
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    property color tintColor
    property Item backdropOverride
    property real frost: 0
    property real rim: 0
    property real press: 0
    property real pulse: 0
    readonly property bool active: visible && ThemeBackend.liquidGlass && backdropOverride !== null && tintColor.a > 0.02
}
''')
            (fixture/'Shell.qml').write_text('''import QtQuick
import Quickshell
import "./"
import "reusables"
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 200; implicitHeight: 100
        Item { id: backdrop }
        AddonGlassSurface { id: material; anchors.fill: parent; surfaceColor: "#123456"; glassSource: backdrop }
        Timer {
            interval: 100; running: true; repeat: true
            property int step: 0
            function expect(ok) { if (!ok) { console.error("GLASS_FAIL", step); Qt.exit(1); } }
            onTriggered: {
                switch(step++) {
                case 0: expect(!material.glassActive && !material.blurActive && material.color === Qt.color("#123456")); ThemeBackend.blurBackground = true; break;
                case 1: expect(material.blurActive && !material.glassActive && Math.abs(material.color.a - 0.4) < 0.01); material.surfaceColor = "#80123456"; break;
                case 2: expect(Math.abs(material.color.a - 0.2) < 0.01); ThemeBackend.liquidGlass = true; break;
                case 3: expect(material.glassActive && !material.blurActive && material.color.a === 0); material.visible = false; break;
                case 4: expect(!material.glassActive && !material.blurActive); material.visible = true; material.surfaceColor = "#654321"; break;
                case 5: expect(material.glassActive); ThemeBackend.liquidGlass = false; break;
                case 6: expect(material.blurActive && Math.abs(material.color.a - 0.4) < 0.01); ThemeBackend.blurBackground = false; break;
                case 7: expect(!material.blurActive && material.color === Qt.color("#654321")); ThemeBackend.liquidGlass = true; material.glassSource = null; break;
                case 8: expect(!material.glassActive && material.color === Qt.color("#654321")); console.log("GLASS_PASS"); Qt.quit(); break;
                }
            }
        }
    }
}
''')
            runtime = fixture/'runtime'
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('GLASS_PASS', output)
            self.assertNotIn('GLASS_FAIL', output)
