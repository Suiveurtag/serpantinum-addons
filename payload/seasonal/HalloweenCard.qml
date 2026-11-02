import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../"
import "../reusables"

// A title card: the moon artwork is the scene, cold and grey until the night comes in and it fills with blood.
Item {
    id: card
    required property var rootObj
    readonly property bool compact: width < rootObj.s(560)
    readonly property bool animate: Halloween.animationEnabled && visible && width > 0 && height > 0
        && Window.window !== null && Window.window.visible
    property real dawn: Halloween.activeSeason ? 1 : 0
    property real ignitedAt: 0
    Layout.fillWidth: true
    implicitHeight: rootObj.s(compact ? 320 : 300)
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: roundedMask }
    Behavior on dawn { enabled: Halloween.animationEnabled; NumberAnimation { duration: Halloween.activeSeason ? 1600 : 500; easing.type: Easing.InOutSine } }
    Connections {
        target: Halloween
        function onActiveSeasonChanged() { if (Halloween.activeSeason) card.ignitedAt = Date.now(); }
    }
    Rectangle { id: roundedMask; anchors.fill: parent; radius: card.rootObj.s(18); visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; color: Halloween.colors.crust }
    Image {
        id: art
        width: card.compact ? card.width * 1.1 : card.width * 0.66; height: width
        x: card.compact ? (card.width - width) / 2 : card.width - width
        y: card.height * (card.compact ? 0.3 : 0.44) - height * 0.37
        source: Halloween.artwork; sourceSize: Qt.size(width, height)
        asynchronous: true; mipmap: true
        layer.enabled: true
        layer.effect: MultiEffect {
            saturation: -1 + card.dawn
            colorization: (1 - card.dawn) * 0.45; colorizationColor: Halloween.moonlight
            brightness: -0.1 * (1 - card.dawn)
        }
    }
    // melts the artwork's left edge into the ground
    Rectangle {
        x: art.x - 1; width: art.width * 0.42; height: card.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Halloween.colors.crust }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    // keeps the type legible where it sits on the trees
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.6
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Halloween.colors.crust, 0.85) }
        }
    }
    Loader {
        anchors.fill: parent
        enabled: false
        active: Halloween.activeSeason && card.animate
        sourceComponent: Item {
            FogLayer { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: parent.height * 0.45; intensity: 0.32; speed: 0.5 }
            DistantBats { x: art.x + art.width * 0.2; y: 0; width: art.width * 0.8; height: card.height * 0.6; altitude: 0.35; depth: 0.4 }
            BatBurst { id: burst; anchors.fill: parent; originX: art.x + art.width * 0.59; originY: art.y + art.height * 0.37; density: 8 }
            Component.onCompleted: if (Date.now() - card.ignitedAt < 800) Qt.callLater(burst.play)
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.setSetting("addonsV2Halloween", !Halloween.activeSeason) }

    Text {
        x: card.rootObj.s(32); y: card.rootObj.s(28)
        text: "SEASONAL EFFECTS"
        font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10); font.letterSpacing: card.rootObj.s(3)
        color: Qt.alpha(Halloween.colors.text, 0.55)
    }
    ColumnLayout {
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.leftMargin: card.rootObj.s(32); anchors.bottomMargin: card.rootObj.s(28)
        width: Math.min(card.width - card.rootObj.s(64), card.rootObj.s(440))
        spacing: 0
        Text {
            text: "Halloween"
            font.family: "Noto Serif"; font.weight: Font.Light; font.italic: true
            font.pixelSize: card.rootObj.s(card.compact ? 50 : 64)
            color: Halloween.colors.text
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: card.rootObj.s(2)
            text: "Living mist, spectral light and wings in the shadows."
            wrapMode: Text.WordWrap
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(12)
            color: Halloween.colors.subtext1
        }
        RowLayout {
            Layout.topMargin: card.rootObj.s(20)
            spacing: card.rootObj.s(16)
            NightSwitch { id: master; uiScale: card.compact ? 0.9 : 1 }
            Text {
                text: Halloween.activeSeason ? "The night is in" : "Let the night in"
                font.family: "Noto Serif"; font.italic: true; font.pixelSize: card.rootObj.s(15)
                color: Halloween.activeSeason ? Halloween.candle : Halloween.colors.subtext0
            }
        }
    }
}
