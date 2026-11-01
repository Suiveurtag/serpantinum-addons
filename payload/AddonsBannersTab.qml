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
    Flickable {
        id: addonsViewport
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
            // BEGIN serpantinum-night-v2 option
            HalloweenCard { rootObj: root.rootObj; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-night-v2 option
            // BEGIN serpantinum-capri-v2 option
            CapriSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-capri-v2 option
            // BEGIN serpantinum-clawd-v2 option
            ClawdSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }
            // END serpantinum-clawd-v2 option
        }
    }
}
