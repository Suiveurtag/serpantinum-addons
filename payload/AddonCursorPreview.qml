import QtQuick
import "../reusables"
import "../"

AddonGlassSurface {
    id: root
    property var cursorInfo: ({preview: "", hotspot: [0, 0]})
    readonly property var point: cursorInfo.hotspot || [0, 0]
    property bool editable: false
    property bool animate: true
    signal pointSelected(real pointX, real pointY)
    surfaceColor: ThemeBackend.surface0
    radius: ThemeBackend.borderRadius
    border.color: editor.activeFocus ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface2, 0.6)
    Accessible.role: editable ? Accessible.Button : Accessible.Graphic
    Accessible.name: editable ? qsTr("Cursor click point; click or use arrow keys to move") : qsTr("Cursor preview")
    AnimatedImage {
        id: art
        anchors.fill: parent
        anchors.margins: 8
        source: root.cursorInfo.preview || ""
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        playing: root.visible && root.animate
        visible: status === Image.Ready
        Accessible.ignored: true
    }
    Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: "󰍽"
        font.family: "Iosevka Nerd Font"
        font.pixelSize: 24
        color: ThemeBackend.subtext0
        Accessible.ignored: true
    }
    Item {
        visible: root.editable && art.status === Image.Ready
        x: (root.width - art.paintedWidth) / 2 + root.point[0] * Math.max(0, art.paintedWidth - 1)
        y: (root.height - art.paintedHeight) / 2 + root.point[1] * Math.max(0, art.paintedHeight - 1)
        Rectangle { x: -7; y: -1; width: 15; height: 3; color: ThemeBackend.crust }
        Rectangle { x: -1; y: -7; width: 3; height: 15; color: ThemeBackend.crust }
        Rectangle { x: -6; width: 13; height: 1; color: ThemeBackend.mauve }
        Rectangle { y: -6; width: 1; height: 13; color: ThemeBackend.mauve }
    }
    MouseArea {
        id: editor
        anchors.fill: parent
        enabled: root.editable && art.status === Image.Ready
        activeFocusOnTab: true
        cursorShape: Qt.CrossCursor
        onClicked: mouse => {
            forceActiveFocus();
            let px = (mouse.x - (root.width - art.paintedWidth) / 2) / Math.max(1, art.paintedWidth - 1);
            let py = (mouse.y - (root.height - art.paintedHeight) / 2) / Math.max(1, art.paintedHeight - 1);
            root.pointSelected(Math.max(0, Math.min(1, px)), Math.max(0, Math.min(1, py)));
        }
        Keys.onPressed: event => {
            let dx = event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Left ? -1 : 0;
            let dy = event.key === Qt.Key_Down ? 1 : event.key === Qt.Key_Up ? -1 : 0;
            if (dx || dy) {
                root.pointSelected(Math.max(0, Math.min(1, root.point[0] + dx / Math.max(1, root.cursorInfo.width - 1))),
                                   Math.max(0, Math.min(1, root.point[1] + dy / Math.max(1, root.cursorInfo.height - 1))));
                event.accepted = true;
            }
        }
    }
}
