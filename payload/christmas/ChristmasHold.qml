import QtQuick
import "../"

// Holding a button pulls a cracker. Bulbs light along both long sides with the charge, a spark runs at their head,
// and above the button a cracker is drawn apart, trembling harder the nearer it is to giving; when the hold completes
// it snaps, the halves fly off and (for buttons without their own burst) confetti showers. Letting go relaxes it all.
Item {
    id: hold
    enabled: false
    property real charge: 0             // 0..1, the button's own fill
    property bool done: false
    property bool upward: false         // the button fills from the bottom
    property bool confetti: false
    property real cornerRadius: 0
    readonly property real unit: Scaler.s(1)
    readonly property real long: upward ? height : width
    readonly property real across: upward ? width : height
    readonly property real radius: Math.min(cornerRadius, width / 2, height / 2)
    readonly property int count: Math.max(3, Math.min(18, Math.floor(long / (unit * 15))))

    property real snap: 0
    onDoneChanged: {
        if (done && Christmas.motion) { release.restart(); if (confetti) shower.play(); }
    }
    NumberAnimation { id: release; target: hold; property: "snap"; from: 0.001; to: 1; duration: 620; easing.type: Easing.OutCubic; onFinished: hold.snap = 0 }

    // how far the rounded corner pushes a side inward at a distance `at` along it
    function bend(at: real): real {
        const d = radius - Math.min(at, long - at);
        return d > 0 ? radius - Math.sqrt(Math.max(0, radius * radius - d * d)) : 0;
    }

    Repeater {
        model: hold.count * 2
        Item {
            id: lamp
            required property int index
            readonly property int step: Math.floor(index / 2)
            readonly property bool far: index % 2 === 1
            readonly property real share: (step + 0.5) / hold.count
            readonly property real along: share * hold.long
            readonly property real side: far ? hold.across - hold.bend(along) : hold.bend(along)
            readonly property bool on: hold.charge >= share
            readonly property color tint: Christmas.bulb(step)
            x: hold.upward ? side : along
            y: hold.upward ? hold.height - along : side
            visible: hold.charge > 0.001
            Rectangle {
                anchors.centerIn: parent
                width: hold.unit * 13; height: width; radius: width / 2
                color: Qt.alpha(lamp.tint, 0.3); visible: lamp.on
            }
            Rectangle {
                anchors.centerIn: parent
                width: hold.unit * 5; height: width; radius: width / 2
                scale: lamp.on ? 1 + 0.6 * Math.max(0, 1 - (hold.charge - lamp.share) * hold.count * 0.7) : 0.8
                color: lamp.on ? lamp.tint : "#3a423d"
            }
        }
    }

    // the spark at the head of the lights, one on each side
    Repeater {
        model: 2
        Text {
            required property int index
            readonly property real along: hold.charge * hold.long
            readonly property real side: index ? hold.across - hold.bend(along) : hold.bend(along)
            visible: hold.charge > 0.02 && hold.charge < 0.99 && !hold.done
            x: (hold.upward ? side : along) - width / 2
            y: (hold.upward ? hold.height - along : side) - height / 2
            text: "✦"; color: "#fff6e2"
            style: Text.Outline; styleColor: Christmas.gold
            font.pixelSize: hold.unit * (13 + 5 * Math.abs(Math.sin(hold.charge * 47 + index)))
            rotation: hold.charge * 720
        }
    }

    // ── the cracker, above the button ────────────────────────────────────────
    Item {
        id: cracker
        readonly property real pull: hold.snap > 0 ? 1 + hold.snap * 3 : hold.charge
        readonly property real shake: hold.snap > 0 ? 0 : Math.sin(hold.charge * 150) * hold.charge * hold.charge * hold.unit * 2.2
        x: hold.width / 2 + shake
        y: -hold.unit * 17 - hold.snap * hold.unit * 14
        visible: hold.snap > 0 || (hold.charge > 0.02 && !hold.done)
        opacity: hold.snap > 0 ? 1 - hold.snap : Math.min(1, hold.charge * 6)
        component Half: Item {
            property int way: 1
            x: way * (cracker.pull * hold.unit * 7)
            rotation: way * hold.snap * 55
            Item {
                scale: way
                Rectangle { x: 0; y: -hold.unit * 6; width: hold.unit * 15; height: hold.unit * 12; radius: hold.unit * 2; color: Christmas.cranberry }
                Rectangle { x: hold.unit * 10; y: -hold.unit * 6; width: hold.unit * 3; height: hold.unit * 12; color: Christmas.gold }
                Rectangle { x: hold.unit * 15; y: -hold.unit * 2.5; width: hold.unit * 3; height: hold.unit * 5; color: Christmas.deepRed }
                Rectangle { x: hold.unit * 17.5; y: -hold.unit * 5; width: hold.unit * 6; height: hold.unit * 10; radius: hold.unit; color: Christmas.holly }
            }
        }
        // the paper twist between the halves, stretching until it tears
        Rectangle {
            visible: hold.snap === 0
            x: -width / 2; y: -height / 2
            width: cracker.pull * hold.unit * 15; height: hold.unit * (6 - 4.5 * hold.charge); color: Christmas.cream
        }
        Half { way: -1 }
        Half { way: 1 }
        Text {
            visible: hold.snap > 0
            anchors.centerIn: parent
            text: "✸"; color: Christmas.paleGold
            font.pixelSize: hold.unit * 34
            scale: 0.3 + hold.snap
            rotation: hold.snap * 90
        }
    }

    Loader {
        id: shower
        readonly property real span: hold.unit * 190
        x: (hold.width - span) / 2; y: (hold.height - span) / 2
        width: span; height: span
        active: false
        function play(): void { active = false; active = true; }
        sourceComponent: ChristmasBurst {
            count: 18; confetti: true
            onFinished: shower.active = false
            Component.onCompleted: play()
        }
    }
}
