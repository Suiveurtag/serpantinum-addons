import QtQuick
import QtQuick.Effects
import "../"

// A notification arrives wrapped: a satin sash slides across its lower corner and a small bow pops onto it.
// Urgent ones are tied in gold. Lies under the card's content and is static once it has arrived.
Item {
    id: tag
    enabled: false
    property real cornerRadius: 0
    property bool urgent: false
    readonly property real unit: Scaler.s(1)
    readonly property real band: unit * 11
    readonly property color ribbon: urgent ? Christmas.gold : Christmas.cranberry
    readonly property color shade: urgent ? "#a77a2c" : Christmas.deepRed
    property real arrive: Christmas.motion ? 0 : 1
    opacity: Christmas.effectOpacity
    layer.enabled: opacity < 1          // flattened, so the bow's parts do not show through each other
    Component.onCompleted: if (arrive < 1) entrance.start()
    SequentialAnimation {
        id: entrance
        PauseAnimation { duration: 140 }
        NumberAnimation { target: tag; property: "arrive"; to: 1; duration: 620; easing.type: Easing.OutCubic }
    }

    Rectangle { id: shape; anchors.fill: parent; radius: tag.cornerRadius; visible: false; layer.enabled: true }
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: shape; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        opacity: 0.92
        // the sash crosses the corner diagonally, sliding in from outside it
        Rectangle {
            readonly property real reach: Math.min(tag.width, tag.height) * 0.62 + tag.unit * 24
            width: reach * 2; height: tag.band
            x: tag.width - reach * 0.72 - width / 2 + (1 - tag.arrive) * reach * 0.7
            y: tag.height - reach * 0.72 - height / 2 + (1 - tag.arrive) * reach * 0.7
            rotation: -45
            gradient: Gradient {
                GradientStop { position: 0; color: tag.shade }
                GradientStop { position: 0.16; color: Qt.alpha(Christmas.paleGold, 0.85) }
                GradientStop { position: 0.26; color: tag.ribbon }
                GradientStop { position: 0.5; color: Qt.lighter(tag.ribbon, 1.25) }
                GradientStop { position: 0.74; color: tag.ribbon }
                GradientStop { position: 0.84; color: Qt.alpha(Christmas.paleGold, 0.85) }
                GradientStop { position: 1; color: tag.shade }
            }
        }
    }
    ChristmasBow {
        readonly property real size: tag.unit * 30
        readonly property real k: Math.max(0, Math.min(1, (tag.arrive - 0.55) / 0.45))
        width: size; height: size * 0.8
        x: tag.width - (Math.min(tag.width, tag.height) * 0.62 + tag.unit * 24) * 0.72 - width / 2
        y: tag.height - (Math.min(tag.width, tag.height) * 0.62 + tag.unit * 24) * 0.72 - height * 0.4
        rotation: -45 + 45 * k
        scale: k <= 0 ? 0 : 1 + 3.2 * Math.pow(k - 1, 3) + 2.2 * Math.pow(k - 1, 2)
        ribbon: tag.ribbon; shade: tag.shade
        shine: Qt.lighter(tag.ribbon, 1.4)
        visible: k > 0
    }
}
