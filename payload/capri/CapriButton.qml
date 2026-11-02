import QtQuick
import QtQuick.Controls.Basic
import "../"

Button {
    id: control
    property color accent: "#36ff73"
    property bool primary: false
    implicitWidth: contentItem.implicitWidth + 24
    implicitHeight: Math.max(34, contentItem.implicitHeight + 14)
    activeFocusOnTab: true
    contentItem: Text {
        text: control.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: !control.enabled ? "#b7a4bd" : control.primary && !control.hovered ? "#120c1c" : "#fcf2f6"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        color: !control.enabled ? "#20182f" : control.down ? "#7d3af5" : control.hovered ? "#7d3af5" : control.primary ? control.accent : "#20182f"
        border.width: control.activeFocus ? 2 : 0
        border.color: "#fcf2f6"
    }
}
