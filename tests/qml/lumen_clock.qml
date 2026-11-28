import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 32; implicitHeight: 32; visible: true
        property int first: 0
        property int stopped: 0
        property int resumed: 0
        property int hidden: 0
        property int mark: 0
        Item {
            id: root
            property bool showSeconds: true
            property int ticks: 0
            function tick() { ticks++ }
            onVisibleChanged: if (visible) tick()
            onShowSecondsChanged: tick()
            Component.onCompleted: tick()
    Timer {
        interval: root.showSeconds ? 40 : 1000
        running: root.visible
        repeat: true
        onTriggered: root.tick()
    }
        }
        Timer { interval: 800; running: true; onTriggered: { win.first = root.ticks; root.showSeconds = false; win.mark = root.ticks } }
        Timer { interval: 1200; running: true; onTriggered: { win.stopped = root.ticks - win.mark; root.showSeconds = true; win.mark = root.ticks } }
        Timer { interval: 2000; running: true; onTriggered: { win.resumed = root.ticks - win.mark; root.visible = false; win.mark = root.ticks } }
        Timer { interval: 2400; running: true; onTriggered: { win.hidden = root.ticks - win.mark; root.visible = true; win.mark = root.ticks } }
        Timer { interval: 3200; running: true; onTriggered: console.warn("LUMEN_RESULT", win.first, win.stopped, win.resumed, win.hidden, root.ticks - win.mark) }
    }
}
