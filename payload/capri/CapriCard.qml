import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import "../"
import "../reusables"

// Capri's own flat print look (spec visuals §7–9): ink ground, a slanted anime cut-in of her face, violet misregistered copies.
Item {
    id: card
    required property var rootObj
    required property var strings
    property bool consumerVisible: true
    readonly property bool motionAllowed: !Config.getSetting("general.performance", false) && Capri.motion !== "reduced"
    readonly property bool previewActive: preview.status === Loader.Ready && preview.item !== null
    readonly property bool glitch: previewActive && preview.item.glitch
    readonly property bool compact: width < rootObj.s(560)
    readonly property string display: displayFont.status === FontLoader.Ready ? displayFont.name : ThemeBackend.fontFamily
    readonly property color ink: "#120c1c"
    readonly property color ink2: "#20182f"
    readonly property color paper: "#fcf2f6"
    readonly property color paper2: "#d6c5d0"
    readonly property color paper3: "#9c8ca0"
    readonly property color red: "#ff245d"
    readonly property color green: "#36ff73"
    readonly property color violet: "#7d3af5"
    // the band: slanted cut-in on the right; its top edge starts at bandX, its bottom edge skew further left
    readonly property real skew: height * 0.22
    readonly property real bandX: width * (compact ? 0.68 : 0.56) + skew / 2
    readonly property real faceSide: Math.max(height * 1.12, width - bandX + skew)
    readonly property real faceX: (bandX - skew / 2 + width) / 2 - faceSide / 2
    property real ignition: Capri.enabled ? 1 : 0
    property real ignitedAt: 0
    function mix(a, b, t) { return Qt.tint(a, Qt.alpha(b, t)); }
    Layout.fillWidth: true
    implicitHeight: rootObj.s(compact ? 330 : 300)
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: roundedMask }
    Behavior on ignition { enabled: card.motionAllowed; NumberAnimation { duration: Capri.enabled ? 300 : 240; easing.type: Easing.InOutCubic } }
    Connections {
        target: Capri
        function onEnabledChanged() {
            if (!Capri.enabled) return;
            card.ignitedAt = Date.now();
            if (card.motionAllowed && card.visible) flash.restart();
        }
    }
    FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/ChakraPetch-SemiBold.ttf") }
    Rectangle { id: roundedMask; anchors.fill: parent; radius: card.rootObj.s(18); color: "black"; visible: false; layer.enabled: true }
    Shape {
        id: bandShape
        anchors.fill: parent; visible: false; layer.enabled: true
        ShapePath {
            strokeWidth: -1; fillColor: "black"
            startX: card.bandX; startY: 0
            PathLine { x: card.width; y: 0 }
            PathLine { x: card.width; y: card.height }
            PathLine { x: card.bandX - card.skew; y: card.height }
            PathLine { x: card.bandX; y: 0 }
        }
    }

    Rectangle { anchors.fill: parent; color: card.ink }
    // scanlines + print speckle, painted once per size
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.fillStyle = Qt.rgba(0.49, 0.23, 0.96, 0.08);
            for (let y = 0; y < height; y += 4) c.fillRect(0, y, width, 1);
            c.fillStyle = Qt.rgba(0.99, 0.95, 0.96, 0.06);
            for (let i = 0; i < width * height / 900; i++) c.fillRect(Math.random() * card.bandX, Math.random() * height, 2, 2);
        }
    }
    // violet misregistered copy of the band, then its red edge
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1; fillColor: card.mix(card.ink2, card.violet, card.ignition)
            startX: card.bandX - card.rootObj.s(18); startY: 0
            PathLine { x: card.width; y: 0 }
            PathLine { x: card.width; y: card.height }
            PathLine { x: card.bandX - card.skew - card.rootObj.s(18); y: card.height }
            PathLine { x: card.bandX - card.rootObj.s(18); y: 0 }
        }
        ShapePath {
            strokeWidth: -1; fillColor: card.mix(card.paper3, card.red, card.ignition)
            startX: card.bandX - card.rootObj.s(6); startY: 0
            PathLine { x: card.width; y: 0 }
            PathLine { x: card.width; y: card.height }
            PathLine { x: card.bandX - card.skew - card.rootObj.s(6); y: card.height }
            PathLine { x: card.bandX - card.rootObj.s(6); y: 0 }
        }
    }
    // still face: dormant (ink/violet, desaturated) when off, full colour when on without motion
    Item {
        anchors.fill: parent
        visible: !card.previewActive
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true; maskSource: bandShape
            saturation: -1 + card.ignition
            colorization: (1 - card.ignition) * 0.5; colorizationColor: card.violet
            brightness: -0.5 * (1 - card.ignition)
        }
        Rectangle { anchors.fill: parent; color: card.ink }
        Image {
            x: card.faceX; y: (card.height - height) / 2
            width: card.faceSide; height: card.faceSide
            source: Qt.resolvedUrl("assets/capri-icon.png"); sourceSize: Qt.size(width, height)
            asynchronous: true; mipmap: true
            Accessible.ignored: true
        }
    }
    Loader {
        id: preview
        anchors.fill: parent
        enabled: false
        active: Capri.enabled && card.visible && card.consumerVisible && card.width > 0 && card.height > 0
            && card.Window.window !== null && card.Window.window.visible && card.motionAllowed
        sourceComponent: CapriCardPreview { host: card; bandMask: bandShape }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: master.toggle() }

    ColumnLayout {
        x: card.rootObj.s(28); y: card.rootObj.s(24)
        width: card.bandX - card.skew - card.rootObj.s(56)
        spacing: card.rootObj.s(4)
        // eyebrow tag
        Item {
            implicitWidth: eyebrow.implicitWidth + card.rootObj.s(30); implicitHeight: card.rootObj.s(22)
            CapriPlate { x: card.rootObj.s(3); y: card.rootObj.s(3); width: parent.width; height: parent.height; fillColor: card.violet; opacity: card.ignition }
            CapriPlate { anchors.fill: parent; fillColor: card.mix(card.ink2, card.red, card.ignition) }
            Text {
                id: eyebrow
                anchors.centerIn: parent
                text: "▸ " + card.strings.eyebrow
                font.family: card.display; font.pixelSize: card.rootObj.s(10); font.bold: true; font.letterSpacing: 2
                color: card.mix(card.paper3, card.paper, card.ignition)
            }
        }
        // wordmark: violet copy, red glitch copy, paper
        Item {
            Layout.fillWidth: true
            implicitHeight: word.implicitHeight * 0.9
            Text { text: word.text; font: word.font; x: card.rootObj.s(5); y: card.rootObj.s(5); color: card.mix(card.ink2, card.violet, card.ignition) }
            Text { text: word.text; font: word.font; x: -card.rootObj.s(6); color: card.red; visible: card.glitch }
            Text {
                id: word
                text: "CAPRICORN"
                x: card.glitch ? card.rootObj.s(3) : 0
                font.family: card.display; font.pixelSize: card.rootObj.s(card.compact ? 56 : 84); font.bold: true; font.letterSpacing: card.rootObj.s(2)
                color: card.mix(card.paper3, card.paper, card.ignition)
            }
        }
        Text {
            Layout.fillWidth: true
            text: card.strings.headline + " — " + card.strings.body
            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(12)
            color: card.paper2
        }
        RowLayout {
            Layout.topMargin: card.rootObj.s(12)
            spacing: card.rootObj.s(18)
            CapriSwitch {
                id: master
                objectName: "capriMaster"
                uiScale: card.compact ? 0.85 : 1
                motionAllowed: card.motionAllowed
                accessibleName: card.strings.toggle
                offText: card.strings.toggle; onText: card.strings.enabled
                fontFamily: card.display
            }
            Text {
                visible: !card.compact
                text: (Capri.enabled ? "● " + card.strings.enabled : "○ " + card.strings.disabled) + "\nSUPER+SHIFT+K"
                lineHeight: 1.3
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10); font.letterSpacing: 1
                color: Capri.enabled ? card.green : card.paper3
            }
        }
    }

    // ticker strip
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: card.rootObj.s(22)
        color: card.ink
        clip: true
        Rectangle { width: parent.width; height: card.rootObj.s(2); color: card.mix(card.ink2, card.red, card.ignition) }
        Row {
            id: ticker
            y: card.rootObj.s(6)
            spacing: card.rootObj.s(28)
            Repeater {
                model: 6
                Text {
                    text: "▸ " + card.strings.eyebrow + "  //  SUPER+SHIFT+K  //  " + (Capri.enabled ? card.strings.enabled : card.strings.disabled)
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.rootObj.s(10); font.letterSpacing: 2
                    color: Capri.enabled ? card.paper3 : card.ink2
                }
            }
            // one item + one gap per loop, so the seam never shows
            NumberAnimation on x {
                running: card.previewActive
                from: 0; to: -(ticker.width + ticker.spacing) / 6
                duration: 9000; loops: Animation.Infinite
            }
        }
    }

    // ignition impact: a paper frame, then red, in hard steps
    Rectangle {
        id: impact
        anchors.fill: parent
        color: card.paper; opacity: 0
        SequentialAnimation {
            id: flash
            PropertyAction { target: impact; property: "color"; value: card.paper }
            PropertyAction { target: impact; property: "opacity"; value: 0.9 }
            PauseAnimation { duration: 42 }
            PropertyAction { target: impact; property: "color"; value: card.red }
            PropertyAction { target: impact; property: "opacity"; value: 0.6 }
            PauseAnimation { duration: 42 }
            PropertyAction { target: impact; property: "opacity"; value: 0.3 }
            PauseAnimation { duration: 42 }
            PropertyAction { target: impact; property: "opacity"; value: 0 }
        }
    }
}
