import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 32; implicitHeight: 32; visible: true
        property int firstChanges: 0
        property real stoppedAt: 0
        Item {
            id: panel
            property real enteredAt: 0
            property real counter: 0
            property int changes: 0
            onCounterChanged: changes++
            /* COUNTER_ANIMATION */
            Component.onCompleted: { enteredAt = Date.now(); counts.restart(); }
        }
        Timer { interval: 800; running: true; onTriggered: { win.firstChanges = panel.changes; counts.stop(); win.stoppedAt = panel.counter; } }
        Timer { interval: 1100; running: true; onTriggered: {
            const unchanged = Math.abs(panel.counter - win.stoppedAt) < 0.0001;
            panel.counter = 0; panel.enteredAt = Date.now(); counts.restart();
            console.warn("CAPRI_MID", win.firstChanges, unchanged);
        } }
        Timer { interval: 2300; running: true; onTriggered: console.warn("CAPRI_END", panel.counter) }
    }
}
