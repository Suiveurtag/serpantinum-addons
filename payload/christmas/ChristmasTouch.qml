import QtQuick
import QtQuick.Effects
import "../"

// What a button does for Christmas. Hovered, a glint of candlelight runs across it once, like light over a bauble;
// pressed, gold stars burst from under the pointer, and an icon button rings once like a bell. A hold-to-confirm
// button pulls a cracker instead: stars and paper confetti. Nothing is loaded between two of these moments.
Item {
    id: touch
    enabled: false
    property real cornerRadius: 0
    property bool hovered: false
    property Item bell: null            // an icon button: it swings once on a press
    property bool cracker: false        // a hold-to-confirm button

    readonly property bool live: Christmas.enabled && Christmas.buttons && Christmas.motion && width > 0 && height > 0

    onHoveredChanged: if (hovered && live && Christmas.allow("glint", 90)) { glint.active = true; glintRun.restart(); }

    function press(x: real, y: real): void {
        if (!live) return;
        burstLoader.originX = isNaN(x) ? width / 2 : x;
        burstLoader.originY = isNaN(y) ? height / 2 : y;
        burstLoader.active = false;
        burstLoader.active = true;
        if (bell) ring.restart();
    }

    // the bell: a swing that dies away
    SequentialAnimation {
        id: ring
        NumberAnimation { target: touch.bell; property: "rotation"; to: -11; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: touch.bell; property: "rotation"; to: 8; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: touch.bell; property: "rotation"; to: -4; duration: 130; easing.type: Easing.InOutSine }
        NumberAnimation { target: touch.bell; property: "rotation"; to: 0; duration: 160; easing.type: Easing.OutSine }
    }

    // the glint, clipped to the button's rounded shape while it runs
    property real sweep: 0
    NumberAnimation {
        id: glintRun; target: touch; property: "sweep"; from: 0; to: 1; duration: 720; easing.type: Easing.InOutSine
        onFinished: glint.active = false
    }
    Loader {
        id: glint
        anchors.fill: parent
        active: false
        sourceComponent: Item {
            Rectangle { id: shape; anchors.fill: parent; radius: touch.cornerRadius; visible: false; layer.enabled: true }
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: shape; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                Rectangle {
                    readonly property real band: Math.max(Scaler.s(18), Math.min(touch.width, touch.height) * 0.8)
                    width: band; height: (touch.width + touch.height) * 1.5
                    rotation: 24
                    x: -band * 2 + (touch.width + band * 3) * touch.sweep
                    y: (touch.height - height) / 2
                    opacity: Math.sin(touch.sweep * Math.PI)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(Christmas.paleGold, 0) }
                        GradientStop { position: 0.42; color: Qt.alpha(Christmas.paleGold, 0.16) }
                        GradientStop { position: 0.5; color: Qt.alpha("#fff6e2", 0.38) }
                        GradientStop { position: 0.58; color: Qt.alpha(Christmas.paleGold, 0.16) }
                        GradientStop { position: 1; color: Qt.alpha(Christmas.paleGold, 0) }
                    }
                }
            }
        }
    }

    // the burst is wider than the button and never clipped by it
    Loader {
        id: burstLoader
        property real originX: 0
        property real originY: 0
        readonly property real span: touch.cracker ? Math.max(Scaler.s(200), touch.width * 1.3) : Scaler.s(84)
        x: originX - span / 2; y: originY - span / 2
        width: span; height: span
        z: 30
        active: false
        sourceComponent: ChristmasBurst {
            count: touch.cracker ? 16 : 7
            confetti: touch.cracker
            onFinished: burstLoader.active = false
            Component.onCompleted: play()
        }
    }
}
