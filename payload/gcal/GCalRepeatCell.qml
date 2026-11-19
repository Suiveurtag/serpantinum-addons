import QtQuick
import QtQuick.Layouts
import "../"

// Small toggle cell of the repeat editor (a weekday, a day of the month, a month). Fills its row evenly.
Item {
    id: root
    property string text: ""
    property bool on: false
    property color accent: ThemeBackend.mauve
    property real fontSize: Scaler.s(11)
    signal clicked()
    function s(v) { return Scaler.s(v); }

    Layout.fillWidth: true
    implicitWidth: root.s(30)
    implicitHeight: root.s(30)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.s(9)
        color: root.on ? Qt.alpha(root.accent, 0.92) : Qt.alpha(ThemeBackend.surface0, ma.containsMouse ? 0.85 : 0.5)
        border.width: 1
        border.color: root.on ? root.accent : Qt.alpha(ThemeBackend.surface1, 0.8)
        scale: ma.pressed ? 0.9 : 1
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
    }
    SequentialAnimation {
        id: bounce
        NumberAnimation { target: bg; property: "scale"; to: 1.1; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { target: bg; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }
    onOnChanged: if (on) bounce.restart()
    Text {
        anchors.centerIn: parent
        text: root.text
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Black
        font.pixelSize: root.fontSize
        color: root.on ? GCal.readableOn(root.accent) : ThemeBackend.text
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
