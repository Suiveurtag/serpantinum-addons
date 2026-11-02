pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import "../reusables/guide"

SettingsRow {
    id: root
    settingId: "addons_cursor_test"; searchTab: "addons"
    title: qsTr("Try your cursors"); icon: "󰙨"
    description: qsTr("After applying, hover these areas to test different cursor roles.")
    wrapText: true
    bottomContent: [
        RowLayout {
            Layout.fillWidth: true
            spacing: root.rootObj.s(8)
            Repeater {
                model: [
                    {label: qsTr("Normal"), shape: Qt.ArrowCursor},
                    {label: qsTr("Link"), shape: Qt.PointingHandCursor},
                    {label: qsTr("Busy"), shape: Qt.WaitCursor},
                    {label: qsTr("Resize"), shape: Qt.SizeHorCursor},
                    {label: qsTr("Unavailable"), shape: Qt.ForbiddenCursor}
                ]
                delegate: AddonGlassSurface {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.rootObj.s(40)
                    radius: ThemeBackend.borderRadius
                    surfaceColor: hover.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.label
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11)
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        cursorShape: parent.modelData.shape
                    }
                }
            }
        },
        Input {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rootObj.s(40)
            text: qsTr("Select this text to try the text cursor")
            placeholderText: qsTr("Type here to try the text cursor")
            showClearButton: true
            baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text
            accentColor: ThemeBackend.mauve; borderColor: ThemeBackend.surface2
        },
        Input {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rootObj.s(72)
            multiLine: true
            placeholderText: qsTr("Multi-line text area")
            baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text
            accentColor: ThemeBackend.mauve; borderColor: ThemeBackend.surface2
        }
    ]
}
