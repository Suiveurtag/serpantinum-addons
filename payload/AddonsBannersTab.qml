import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    property int subTabIndex: 2
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex && rootObj.currentSubTab === subTabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    // Section divider: a small tracked label with a hairline running to the edge.
    component BannerDivider: RowLayout {
        id: divider
        required property string label
        Layout.fillWidth: true
        Layout.topMargin: root.rootObj.s(20)
        Layout.bottomMargin: root.rootObj.s(6)
        spacing: root.rootObj.s(14)
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: root.rootObj.s(2); Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: ThemeBackend.mauve; opacity: 0.55
        }
        Text {
            text: divider.label
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(14); font.weight: Font.DemiBold; font.italic: true
            font.letterSpacing: root.rootObj.s(4)
            Layout.alignment: Qt.AlignVCenter
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: root.rootObj.s(2); Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: ThemeBackend.mauve; opacity: 0.55
        }
    }
    Flickable {
        id: addonsViewport
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
            BannerDivider { label: "ACTIVE" }
            // BEGIN serpantinum-clawd-v2 option
            ClawdSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-clawd-v2 option
            // BEGIN serpantinum-capri-v2 option
            CapriSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-capri-v2 option
            // BEGIN serpantinum-night-v2 option
            BannerDivider { label: "ARCHIVE" }
            HalloweenCard { rootObj: root.rootObj; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-night-v2 option
        }
    }
}
