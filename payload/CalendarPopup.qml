// BEGIN serpantinum-addons-v2 calendar wrapper
import QtQuick
import "../"
Item {
    id: root
    anchors.fill: parent
    readonly property bool legacy: Config.getSetting("addonsV2LegacyClock", false)
    function resetAndPlayIntro() { if (panel.status === Loader.Ready && panel.item && panel.item.resetAndPlayIntro) panel.item.resetAndPlayIntro(); }
    Loader {
        id: panel; anchors.fill: parent
        source: root.legacy ? "LegacyCalendar.qml" : "NativeCalendar.qml"
        onLoaded: {
            if (typeof masterWindow !== "undefined") {
                masterWindow._animW = Scaler.s(root.legacy ? 1450 : 1360);
                masterWindow._stageW = masterWindow._animW;
                masterWindow._animH = Scaler.s(510);
                masterWindow._stageH = masterWindow._animH;
            }
            root.resetAndPlayIntro();
        }
    }
    onVisibleChanged: if (visible) resetAndPlayIntro()
}
