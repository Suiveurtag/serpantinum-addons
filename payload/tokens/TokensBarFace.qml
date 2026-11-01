import QtQuick
import QtQuick.Effects
import "../reusables"
import "../"

// Bar module "tokens": odometer total; hover folds it into the Codex / Claude split.
Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isVertical: module ? module.orientation === "vertical" : false
    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null
    readonly property bool live: !module || module.moduleActive

    function s(val) {
        return barWindow && typeof barWindow.cs === "function" ? barWindow.cs(val) : Math.round(Scaler.s(val));
    }

    property bool showLayout: !barWindow
    property bool hovered: hover.containsMouse
    property real lastTotal: -1
    readonly property real pad: s(isCompact ? 10 : 12)
    readonly property real gap: s(7)
    readonly property real fontSize: s(isCompact ? 11 : 12)

    readonly property real contentLength: isVertical ? side.implicitHeight
        : icon.width + gap + (hovered ? split.implicitWidth : digits.implicitWidth)
    property real targetLength: live ? contentLength + pad * 2 : 0
    property bool isFaceVisible: showLayout && targetLength > 0

    implicitWidth: isVertical ? (parent ? parent.width : 0) : targetLength
    implicitHeight: isVertical ? targetLength : (parent ? parent.height : 0)

    Timer {
        running: root.barWindow && root.barWindow.isStartupReady
        interval: 140
        onTriggered: root.showLayout = true
    }

    Connections {
        target: Tokens
        function onTotalChanged() {
            if (root.lastTotal > 0 && Tokens.total > root.lastTotal && root.visible) glow.restart();
            root.lastTotal = Tokens.total;
        }
    }
    Component.onCompleted: lastTotal = Tokens.total

    transform: Translate {
        x: (root.isVertical || root.showLayout) ? 0 : root.s(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Token icon (assets/token.svg, white stroke), tinted with the theme's primary colour.
    component TokenIcon: Image {
        required property real side
        width: side; height: side
        source: Qt.resolvedUrl("assets/token.svg")
        sourceSize: Qt.size(side, side)
        smooth: true; mipmap: true
        layer.enabled: true
        layer.effect: MultiEffect { colorization: 1; colorizationColor: ThemeBackend.primary }
    }

    // Live indicator: steady dot, pulsing ring while tokens flow.
    component LiveDot : Item {
        id: dot
        width: root.s(8)
        height: width
        Rectangle {
            id: ring
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: ThemeBackend.green
            opacity: 0
            ParallelAnimation {
                running: Tokens.active && root.visible && root.live
                loops: Animation.Infinite
                ScaleAnimator { target: ring; from: 0.8; to: 2.2; duration: 1300; easing.type: Easing.OutCubic }
                OpacityAnimator { target: ring; from: 0.8; to: 0; duration: 1300; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: width
            radius: width / 2
            color: Tokens.stale ? ThemeBackend.red : Tokens.active ? ThemeBackend.green : Qt.alpha(ThemeBackend.subtext0, 0.5)
            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    Row {
        id: horizontal
        visible: !root.isVertical
        anchors.verticalCenter: parent.verticalCenter
        x: root.pad
        spacing: root.gap
        opacity: root.showLayout ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Item {
            id: icon
            width: root.s(19)
            height: root.s(19)
            anchors.verticalCenter: parent.verticalCenter
            TokenIcon { anchors.centerIn: parent; side: root.s(19) }
            LiveDot { x: parent.width - width * 0.7; y: -height * 0.25 }
        }

        Item {
            width: root.hovered ? split.implicitWidth : digits.implicitWidth
            height: digits.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            Behavior on width { enabled: root.showLayout; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }

            TokensDigits {
                id: digits
                anchors.verticalCenter: parent.verticalCenter
                value: Tokens.total
                pixelSize: root.fontSize
                weight: Font.Bold
                color: ThemeBackend.text
                animate: root.visible && root.showLayout && !!Tokens.data
                duration: 700
                opacity: root.hovered ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                SequentialAnimation on color {
                    id: glow
                    running: false
                    ColorAnimation { to: ThemeBackend.green; duration: 180 }
                    PauseAnimation { duration: 500 }
                    ColorAnimation { to: ThemeBackend.text; duration: 900; easing.type: Easing.OutCubic }
                }
            }

            Row {
                id: split
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(8)
                opacity: root.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Repeater {
                    model: [{ tone: ThemeBackend.blue, value: Tokens.codex }, { tone: ThemeBackend.peach, value: Tokens.claude }]
                    delegate: Row {
                        required property var modelData
                        spacing: root.s(4)
                        Rectangle { width: root.s(6); height: width; radius: width / 2; color: modelData.tone; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: Tokens.compact(modelData.value)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.fontSize
                            font.bold: true
                            color: ThemeBackend.text
                        }
                    }
                }
            }
        }
    }

    Column {
        id: side
        visible: root.isVertical
        anchors.centerIn: parent
        spacing: root.s(3)
        Item { width: root.s(17); height: root.s(17); anchors.horizontalCenter: parent.horizontalCenter
            TokenIcon { anchors.centerIn: parent; side: root.s(16) } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tokens.compact(Tokens.total)
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(10)
            font.bold: true
            color: ThemeBackend.text
        }
        LiveDot { anchors.horizontalCenter: parent.horizontalCenter }
    }
}
