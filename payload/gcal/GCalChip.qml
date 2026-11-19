import QtQuick
import "../"

// Selectable chip (calendar, repeat, reminder, ...). Selection fills it with a short bounce.
Item {
    id: root
    property string text: ""
    property string icon: ""
    property color dot: "transparent"
    property bool selected: false
    property color accent: ThemeBackend.mauve
    signal clicked()
    function s(v) { return Scaler.s(v); }

    implicitWidth: row.implicitWidth + s(22)
    implicitHeight: s(30)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: height / 2
        color: root.selected ? Qt.alpha(root.accent, 0.9) : Qt.alpha(ThemeBackend.surface0, ma.containsMouse ? 0.8 : 0.5)
        border.width: 1
        border.color: root.selected ? root.accent : Qt.alpha(ThemeBackend.surface1, 0.8)
        Behavior on color { ColorAnimation { duration: 180 } }
        scale: ma.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
    }
    SequentialAnimation {
        id: bounce
        NumberAnimation { target: bg; property: "scale"; to: 1.08; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: bg; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }
    onSelectedChanged: if (selected) bounce.restart()

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.s(6)
        Rectangle {
            visible: root.dot.a > 0
            anchors.verticalCenter: parent.verticalCenter
            width: root.s(9); height: width; radius: width / 2
            color: root.dot
            border.width: root.selected ? root.s(1.5) : 0
            border.color: GCal.readableOn(root.accent)
        }
        Text {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.family: ThemeBackend.iconFont
            font.pixelSize: root.s(13)
            color: root.selected ? GCal.readableOn(root.accent) : ThemeBackend.overlay1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Black
            font.pixelSize: root.s(11)
            color: root.selected ? GCal.readableOn(root.accent) : ThemeBackend.text
            Behavior on color { ColorAnimation { duration: 180 } }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
