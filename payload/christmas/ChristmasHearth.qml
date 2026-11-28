import QtQuick
import QtQuick.Shapes
import "../"

// The system panel's battery box as a fireplace: flames burn along its foot as hard as the power profile asks
// (embers on power saver, a steady fire when balanced, a blaze on performance), sparks fly up while charging, and a
// garland with lights lines the mantelpiece. Flickers on the shared clock and never takes input.
Item {
    id: hearth
    enabled: false
    property string profile: "balanced"
    property bool charging: false
    property real cornerRadius: 0
    readonly property real unit: Scaler.s(1)
    property real heat: profile === "performance" ? 1 : profile === "power-saver" ? 0.22 : 0.55
    Behavior on heat { enabled: Christmas.motion; NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
    property bool clocked: false
    function syncClock(): void {
        const want = visible && Christmas.motion;
        if (want === clocked) return;
        clocked = want;
        Christmas.requestClock(want);
    }
    onVisibleChanged: syncClock()
    Component.onCompleted: syncClock()
    Component.onDestruction: if (clocked) Christmas.requestClock(false)
    Connections { target: Christmas; function onMotionChanged() { hearth.syncClock(); } }

    // the glow of the fire
    Rectangle {
        anchors.fill: parent
        radius: hearth.cornerRadius
        gradient: Gradient {
            GradientStop { position: 0.72; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha("#ff7a1f", 0.08 + 0.18 * hearth.heat) }
        }
    }
    Repeater {
        model: Math.max(0, Math.floor((hearth.width - 2 * hearth.cornerRadius) / (hearth.unit * 11)))
        Shape {
            id: flame
            required property int index
            readonly property real r: Math.abs(Math.sin(index * 57.31) * 43758.5453) % 1
            readonly property real flicker: 0.8 + 0.2 * Math.sin(Christmas.phase * (7 + r * 5) + index * 2.7)
            readonly property real tall: hearth.unit * (3 + 11 * hearth.heat) * (0.55 + 0.45 * r) * flicker
            readonly property real lean: Math.sin(Christmas.phase * 4 + index) * hearth.unit * 3
            readonly property real half: hearth.unit * 5
            x: hearth.cornerRadius + index * hearth.unit * 11 + hearth.unit * 5
            y: hearth.height
            preferredRendererType: Shape.CurveRenderer
            opacity: 0.55
            ShapePath {
                strokeWidth: -1; fillColor: "#ff6a1a"
                startX: -flame.half; startY: 0
                PathQuad { x: flame.lean; y: -flame.tall; controlX: -flame.half; controlY: -flame.tall * 0.45 }
                PathQuad { x: flame.half; y: 0; controlX: flame.half; controlY: -flame.tall * 0.45 }
            }
            ShapePath {
                strokeWidth: -1; fillColor: "#ffd35a"
                startX: -flame.half * 0.5; startY: 0
                PathQuad { x: flame.lean * 0.6; y: -flame.tall * 0.55; controlX: -flame.half * 0.5; controlY: -flame.tall * 0.25 }
                PathQuad { x: flame.half * 0.5; y: 0; controlX: flame.half * 0.5; controlY: -flame.tall * 0.25 }
            }
        }
    }
    // sparks, while charging
    Repeater {
        model: hearth.charging && Christmas.motion ? 12 : 0
        Rectangle {
            required property int index
            readonly property real r: Math.abs(Math.sin(index * 91.17) * 437.5) % 1
            readonly property real k: (Christmas.phase * (0.5 + r * 0.6) + index / 12) % 1
            width: hearth.unit * (2 + 2 * r); height: width; radius: width / 2
            x: hearth.width * ((index + r) / 12) + Math.sin(k * 9 + index) * hearth.unit * 5
            y: hearth.height - k * hearth.height * 0.4
            color: Christmas.paleGold
            opacity: Math.sin(k * Math.PI)
        }
    }
    ChristmasGarland { anchors.fill: parent; cornerRadius: hearth.cornerRadius; seed: 21 }
}
