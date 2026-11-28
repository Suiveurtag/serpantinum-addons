import QtQuick
import QtQuick.Window

// Renders three settings-like rows (frost at rest, growing, full) to preview.png, then quits.
// Run on the real display (the offscreen platform renders in software and skips shaders):
//   QT_QPA_PLATFORM=wayland /usr/lib/qt6/bin/qml preview.qml
Window {
    id: win
    width: 560; height: 236; visible: true; color: "#11151c"
    property bool hovered: false                 // flips after start, like a pointer entering
    Timer { interval: 100; running: true; onTriggered: win.hovered = true }
    Column {
        x: 20; y: 20; spacing: 12
        Repeater {
            model: [0, 0.45, 1]
            delegate: Rectangle {
                id: row
                required property real modelData
                width: 520; height: 56; radius: 14; color: "#1b212b"
                Text { x: 18; anchors.verticalCenter: parent.verticalCenter; color: "#e6ebf2"; font.pixelSize: 15; text: "Setting row, frost " + row.modelData }
                FrostEdge {
                    anchors.fill: parent
                    cornerRadius: row.radius
                    engaged: win.hovered && row.modelData > 0
                    growDuration: row.modelData < 1 ? 2600 : 600      // middle row is captured mid-growth
                }
            }
        }
    }
    Timer {
        interval: 1300; running: true
        onTriggered: win.contentItem.grabToImage(function (result) {
            result.saveToFile(Qt.resolvedUrl("preview.png").toString().replace("file://", ""));
            Qt.quit();
        })
    }
}
