// BEGIN serpantinum-addons-v2 calendar wrapper
import QtQuick
import "../"
Item {
    id: root
    implicitWidth: panel.item ? panel.item.implicitWidth : 0
    implicitHeight: panel.item ? panel.item.implicitHeight : 0
    property bool vertical: false
    readonly property real panelRadius: Math.min(ThemeBackend.borderRadius, Scaler.s(28))
    property color backgroundColor: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
    property real cornerTopLeft: panelRadius
    property real cornerTopRight: panelRadius
    property real cornerBottomLeft: panelRadius
    property real cornerBottomRight: panelRadius
    function resetAndPlayIntro() { if (panel.status === Loader.Ready && panel.item && panel.item.resetAndPlayIntro) panel.item.resetAndPlayIntro(); }
    Loader {
        id: panel; anchors.fill: parent
        source: "NativeCalendar.qml"
        onLoaded: {
            const item = panel.item;
            if (item) item.visible = Qt.binding(() => root.visible);
            if (item && item.vertical !== undefined) item.vertical = Qt.binding(() => root.vertical);
            if (item && item.backgroundColor !== undefined) item.backgroundColor = Qt.binding(() => root.backgroundColor);
            if (item && item.cornerTopLeft !== undefined) item.cornerTopLeft = Qt.binding(() => root.cornerTopLeft);
            if (item && item.cornerTopRight !== undefined) item.cornerTopRight = Qt.binding(() => root.cornerTopRight);
            if (item && item.cornerBottomLeft !== undefined) item.cornerBottomLeft = Qt.binding(() => root.cornerBottomLeft);
            if (item && item.cornerBottomRight !== undefined) item.cornerBottomRight = Qt.binding(() => root.cornerBottomRight);
            if (typeof masterWindow !== "undefined") {
                masterWindow._animW = Scaler.s(1360);
                masterWindow._stageW = masterWindow._animW;
                masterWindow._animH = Scaler.s(510);
                masterWindow._stageH = masterWindow._animH;
            }
            root.resetAndPlayIntro();
        }
    }
    onVisibleChanged: if (visible) resetAndPlayIntro()
}
