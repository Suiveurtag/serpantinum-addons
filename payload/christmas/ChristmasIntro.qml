import QtQuick
import "../"

// Switching Christmas on: a long garland swings down over the top of every screen, its bulbs light from the middle
// outward while a warm glow spills down, then it is drawn back up. About three seconds, once per switch-on.
Item {
    id: intro
    enabled: false
    readonly property real unit: Scaler.s(1)
    readonly property bool playing: show.running
    property real drop: 0               // 0 above the screen .. 1 hanging in place
    property real warmth: 0

    Connections {
        target: Christmas
        function onIntroSerialChanged() { if (Christmas.motion) show.restart(); }
    }
    Component.onCompleted: if (Christmas.motion && Date.now() - Christmas.switchedOnAt < 1000) show.restart()

    SequentialAnimation {
        id: show
        PropertyAction { target: intro; property: "drop"; value: 0 }
        ScriptAction { script: { garland.lit = 0; } }
        ParallelAnimation {
            NumberAnimation { target: intro; property: "drop"; to: 1; duration: 760; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { target: intro; property: "warmth"; to: 1; duration: 900; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 280 }
                NumberAnimation { target: garland; property: "lit"; to: 1; duration: 1300; easing.type: Easing.InOutSine }
            }
        }
        PauseAnimation { duration: 1100 }
        ParallelAnimation {
            NumberAnimation { target: intro; property: "drop"; to: 0; duration: 640; easing.type: Easing.InBack; easing.overshoot: 1.2 }
            NumberAnimation { target: intro; property: "warmth"; to: 0; duration: 640; easing.type: Easing.InQuad }
        }
    }

    // candlelight falling from the top of the screen
    Rectangle {
        width: parent.width; height: parent.height * 0.32
        visible: intro.playing
        opacity: intro.warmth * 0.9 * Christmas.effectOpacity
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Christmas.gold, 0.16) }
            GradientStop { position: 0.45; color: Qt.alpha(Christmas.gold, 0.05) }
            GradientStop { position: 1; color: Qt.alpha(Christmas.gold, 0) }
        }
    }
    ChristmasLights {
        id: garland
        on: false
        live: true
        visible: intro.playing
        opacity: Christmas.effectOpacity
        readonly property real margin: intro.unit * 30
        x: -margin
        width: intro.width + margin * 2
        height: intro.unit * 120
        y: -height + intro.drop * height
        spacing: intro.unit * 50
        swag: Math.max(spacing * 2, width / Math.max(3, Math.round(width / (intro.unit * 420))))
        sag: intro.unit * 38
        wireY: intro.unit * 10
        bulb: intro.unit * 7
        glow: 0.8
        origin: 0.5
        seed: 5
    }
}
