import QtQuick
import "../"

// A burst from the centre of the item: gold four-point stars, and with `confetti` paper flecks in the light colours
// that arc down as they fall. One clock drives every particle; the item asks to be unloaded through `finished`.
Item {
    id: burst
    enabled: false
    property int count: 7
    property bool confetti: false
    property real reach: Math.min(width, height) * 0.42
    property int duration: confetti ? 900 : 560
    property real seed: Math.random()
    property real t: 0
    signal finished()

    function play(): void { seed = Math.random(); clock.restart(); }
    NumberAnimation {
        id: clock; target: burst; property: "t"; from: 0; to: 1
        duration: burst.duration; easing.type: Easing.Linear
        onFinished: burst.finished()
    }

    Repeater {
        model: burst.count
        Item {
            id: bit
            required property int index
            readonly property real h1: (Math.sin((index + 1) * 12.9898 + burst.seed * 78.233) * 43758.5453) % 1
            readonly property real r1: Math.abs(h1)
            readonly property real r2: Math.abs((r1 * 91.7) % 1)
            readonly property bool star: !burst.confetti || index % 3 === 0
            readonly property real angle: (index / burst.count + r1 * 0.12) * Math.PI * 2 - Math.PI / 2
            readonly property real distance: burst.reach * (0.55 + 0.45 * r2)
            // fast out, then drifting (and with confetti, falling)
            readonly property real out: 1 - Math.pow(1 - burst.t, 3)
            readonly property real fall: burst.confetti ? burst.t * burst.t * burst.reach * 0.9 : 0
            readonly property real size: (star ? 9 : 6) * Scaler.s(1) * (0.7 + 0.6 * r2)
            x: burst.width / 2 + Math.cos(angle) * distance * out - width / 2
            y: burst.height / 2 + Math.sin(angle) * distance * out + fall - height / 2
            width: size; height: size
            opacity: burst.t < 0.55 ? 1 : 1 - (burst.t - 0.55) / 0.45
            scale: burst.t < 0.2 ? burst.t / 0.2 : 1 - 0.35 * (burst.t - 0.2)
            rotation: (r1 - 0.5) * 540 * burst.t + (star ? 0 : r2 * 180)

            Text {
                visible: bit.star
                anchors.centerIn: parent
                text: "✦"
                color: bit.index % 2 ? Christmas.paleGold : Christmas.gold
                font.pixelSize: bit.size * 1.5
            }
            Rectangle {
                visible: !bit.star
                anchors.centerIn: parent
                width: bit.size; height: bit.size * 0.55
                radius: 1
                color: Christmas.bulb(bit.index)
            }
        }
    }
}
