import QtQuick
import QtQuick.Layouts
import "../"

// Icon + text (+ secondary line) row of the event card. Optional hover/click affordance.
GCalReveal {
    id: root
    property string icon: ""
    property string text: ""
    property string sub: ""
    property color tone: ThemeBackend.blue
    property bool clickable: false
    signal activated()
    function s(v) { return Scaler.s(v); }
    implicitHeight: Math.max(s(24), col.implicitHeight)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.s(4)
        radius: root.s(8)
        color: root.clickable && hover.hovered ? Qt.alpha(ThemeBackend.surface0, 0.55) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    Rectangle {
        id: badge
        width: root.s(24); height: width
        color: "transparent"
        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: ThemeBackend.iconFont
            font.pixelSize: root.s(15)
            color: ThemeBackend.overlay1
        }
    }
    ColumnLayout {
        id: col
        anchors.left: badge.right
        anchors.leftMargin: root.s(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.s(1)
        Text {
            Layout.fillWidth: true
            text: root.text
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(12.5)
            color: ThemeBackend.text
        }
        Text {
            Layout.fillWidth: true
            visible: root.sub !== ""
            text: root.sub
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(10.5)
            color: root.clickable && hover.hovered ? root.tone : ThemeBackend.overlay1
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
    HoverHandler { id: hover; enabled: root.clickable; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: root.clickable; onTapped: root.activated() }
}
