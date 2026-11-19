// BEGIN serpantinum-addons-v2 calendar wrapper
import QtQuick
import "../"
Item {
    id: root
    // Addons extend the clock panel through these: addonWidth adds a column on the right of the native panel,
    // morphWidth/morphHeight (>= 0) take over the panel size (the Dashboard follows implicit size live), and
    // nativeOpacity/nativeScale/nativeActive fade the native clock out under an addon layer.
    property real addonWidth: 0
    property real morphWidth: -1
    property real morphHeight: -1
    property real nativeOpacity: 1
    property real nativeScale: 1
    property bool nativeActive: true
    readonly property Item nativeFrame: frame
    readonly property real baseWidth: (panel.item ? panel.item.implicitWidth : 0) + addonWidth
    readonly property real baseHeight: panel.item ? panel.item.implicitHeight : 0
    implicitWidth: morphWidth >= 0 ? morphWidth : baseWidth
    implicitHeight: morphHeight >= 0 ? morphHeight : baseHeight
    property bool vertical: false
    readonly property real panelRadius: Math.min(ThemeBackend.borderRadius, Scaler.s(28))
    property color backgroundColor: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
    property real cornerTopLeft: panelRadius
    property real cornerTopRight: panelRadius
    property real cornerBottomLeft: panelRadius
    property real cornerBottomRight: panelRadius
    function resetAndPlayIntro() { if (panel.status === Loader.Ready && panel.item && panel.item.resetAndPlayIntro) panel.item.resetAndPlayIntro(); }
    Item {
        id: frame
        width: root.baseWidth
        height: root.baseHeight
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        opacity: root.nativeOpacity
        scale: root.nativeScale
        visible: opacity > 0.001
        Loader {
            id: panel
            width: parent.width - root.addonWidth
            height: parent.height
            source: "NativeCalendar.qml"
            onLoaded: {
                const item = panel.item;
                if (item) item.visible = Qt.binding(() => root.visible && root.nativeActive);
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
    }
    onVisibleChanged: if (visible) resetAndPlayIntro()
}
