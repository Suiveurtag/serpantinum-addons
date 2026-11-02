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
    text: label
    Accessible.name: label
    hoverEnabled: true
    background: AddonGlassSurface {
        radius: ThemeBackend.borderRadius
        surfaceColor: root.hovered || root.selected ? ThemeBackend.surface1 : ThemeBackend.surface0
        border.color: root.selected || root.activeFocus ? ThemeBackend.mauve : "transparent"
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
