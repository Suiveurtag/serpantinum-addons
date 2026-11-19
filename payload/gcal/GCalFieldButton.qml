import QtQuick
import "../"

// Field-like button (date, time). Accent underline grows when its picker is open; the mouse wheel steps it.
Item {
    id: root
    property string text: ""
    property bool active: false
    property color accent: ThemeBackend.mauve
    signal clicked()
    signal wheelStep(int dir)
    function s(v) { return Scaler.s(v); }
    implicitHeight: s(34)

    Rectangle {
        anchors.fill: parent
        radius: root.s(10)
        color: Qt.alpha(ThemeBackend.surface0, root.active ? 0.85 : (ma.containsMouse ? 0.7 : 0.45))
        border.width: 1
        border.color: root.active ? root.accent : Qt.alpha(ThemeBackend.surface1, 0.8)
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }
        scale: ma.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
    }
    GCalRollText {
        anchors.verticalCenter: parent.verticalCenter
        x: root.s(12)
        width: parent.width - root.s(24)
        text: root.text
        pixelSize: root.s(12)
        weight: Font.Black
        color: ThemeBackend.text
        duration: 320
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: root.s(2)
        radius: height / 2
        width: root.active ? parent.width - root.s(20) : 0
        color: root.accent
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onWheel: (w) => { root.wheelStep(w.angleDelta.y > 0 ? -1 : 1); }
    }
}
