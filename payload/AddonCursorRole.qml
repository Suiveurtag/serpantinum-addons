import QtQuick
import "../reusables"
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "../"

Button {
    id: root
    property var cursorInfo: ({preview: ""})
    property string label: ""
    property bool selected: false
    property bool customized: false
    text: label
    Accessible.name: customized ? label + ", " + qsTr("customised") : label
    hoverEnabled: true
    background: AddonGlassSurface {
        radius: ThemeBackend.borderRadius
        surfaceColor: root.hovered || root.selected ? ThemeBackend.surface1 : ThemeBackend.surface0
        border.color: root.selected || root.activeFocus ? ThemeBackend.mauve : "transparent"
    }
    opacity: enabled ? 1 : 0.5
    Rectangle {
        visible: root.customized
        anchors { top: parent.top; right: parent.right; margins: 6 }
        width: 7; height: 7; radius: 3.5
        color: ThemeBackend.mauve
        z: 2
        Accessible.ignored: true
    }
    contentItem: ColumnLayout {
        spacing: 3
        AddonCursorPreview {
            Layout.fillWidth: true
            Layout.fillHeight: true
            cursorInfo: root.cursorInfo
            surfaceColor: "transparent"
            border.width: 0
            Accessible.ignored: true
        }
        Text {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(9)
            color: root.selected ? ThemeBackend.mauve : ThemeBackend.subtext0
            Accessible.ignored: true
        }
    }
}
