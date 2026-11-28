import QtQuick
import "../"

// A closing panel is sent off as a present: paper closes over it and draws it down to a small parcel, the bow ties,
// the parcel crouches, then leaves toward the bar in a puff of gold. One clock drives it, once per close.
Item {
    id: send
    enabled: false
    property rect from: Qt.rect(0, 0, 0, 0)
    property string edge: "center"      // where the panel came from, and where the parcel goes
    property real cornerRadius: 0
    property real t: 0
    readonly property bool playing: run.running || sparkle.active

    readonly property real unit: Scaler.s(1)
    readonly property real sheer: Christmas.effectOpacity   // the same as the opening wrap
    readonly property real side: Math.min(unit * 76, Math.max(unit * 36, Math.min(from.width, from.height)))

    function play(rect: rect, towards: string, radius: real): void {
        if (!Christmas.motion || rect.width < 2 || rect.height < 2) return;
        from = rect; edge = towards; cornerRadius = radius;
        sparkle.active = false;
        run.restart();
    }
    function cancel(): void { run.stop(); sparkle.active = false; }

    NumberAnimation {
        id: run; target: send; property: "t"; from: 0; to: 1
        duration: 480; easing.type: Easing.Linear
    }
    onTChanged: if (run.running && t > 0.84 && !sparkle.active) sparkle.active = true

    function phase(a: real, b: real): real { return Math.max(0, Math.min(1, (t - a) / (b - a))); }
    function smooth(k: real): real { return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; }
    function mix(a: real, b: real, k: real): real { return a + (b - a) * k; }

    readonly property real wrapped: smooth(phase(0, 0.44))
    readonly property real crouch: Math.sin(phase(0.46, 0.64) * Math.PI)
    readonly property real flight: { const k = phase(0.62, 1); return k * k * k; }

    // the way out: the middle of the panel's side facing the bar; a centred panel's parcel rises and vanishes
    readonly property real dirX: edge === "left" ? -1 : edge === "right" ? 1 : 0
    readonly property real dirY: edge === "top" ? -1 : edge === "bottom" ? 1 : edge === "center" ? -1 : 0
    readonly property real reachX: dirX * from.width / 2
    readonly property real reachY: edge === "center" ? -side * 1.6 : dirY * from.height / 2
    readonly property real centreX: from.x + from.width / 2 + reachX * flight
    readonly property real centreY: from.y + from.height / 2 + reachY * flight

    Item {
        id: parcel
        visible: run.running
        width: send.mix(send.from.width, send.side, send.wrapped)
        height: send.mix(send.from.height, send.side, send.wrapped)
        x: send.centreX - width / 2
        y: send.centreY - height / 2
        opacity: send.phase(0, 0.16) * (1 - send.phase(0.86, 1)) * send.sheer
        layer.enabled: visible          // flattened, so ribbons and bow do not show through each other
        layer.smooth: true
        // crouches against the direction it is about to take, then stretches along it
        transform: Scale {
            origin.x: parcel.width / 2 - send.dirX * parcel.width / 2
            origin.y: parcel.height / 2 - send.dirY * parcel.height / 2
            readonly property real along: 1 - 0.16 * send.crouch + 0.22 * Math.sin(send.flight * Math.PI)
            readonly property real acrossIt: 1 + 0.12 * send.crouch - 0.14 * Math.sin(send.flight * Math.PI)
            readonly property real shrink: 1 - 0.7 * send.flight
            xScale: (send.dirX !== 0 ? along : acrossIt) * shrink
            yScale: (send.dirX !== 0 ? acrossIt : along) * shrink
        }

        readonly property real band: Math.max(send.unit * 8, Math.min(send.unit * 14, Math.min(width, height) * 0.16))

        Rectangle {
            anchors.fill: parent
            radius: send.mix(send.cornerRadius, send.unit * 12, send.wrapped)
            border.width: Math.max(1, send.unit * 1.5)
            border.color: Qt.alpha(Christmas.gold, 0.7)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Christmas.deepRed, 1.25) }
                GradientStop { position: 1; color: Qt.darker(Christmas.deepRed, 1.25) }
            }
        }
        component Band: Rectangle {
            color: Christmas.gold
            Rectangle { anchors.fill: parent; anchors.margins: Math.max(1, send.unit * 2); color: Christmas.paleGold; opacity: 0.55 }
        }
        // edge to edge from the first frame: short arms would read as a plus sign
        Band { anchors.centerIn: parent; height: parcel.band; width: parent.width }
        Band { anchors.centerIn: parent; width: parcel.band; height: parent.height }

        ChristmasBow {
            readonly property real k: send.phase(0.3, 0.5)
            width: send.side * 0.9; height: width * 0.8
            x: (parent.width - width) / 2
            y: parent.height / 2 - height * 0.4
            visible: k > 0
            // ease-out-back: ties with a little snap
            scale: 1 + 3.2 * Math.pow(k - 1, 3) + 2.2 * Math.pow(k - 1, 2)
        }
    }

    Loader {
        id: sparkle
        readonly property real span: send.unit * 130
        x: send.from.x + send.from.width / 2 + send.reachX - span / 2
        y: send.from.y + send.from.height / 2 + send.reachY - span / 2
        width: span; height: span
        active: false
        opacity: send.sheer
        sourceComponent: ChristmasBurst {
            count: 8
            onFinished: sparkle.active = false
            Component.onCompleted: play()
        }
    }
}
