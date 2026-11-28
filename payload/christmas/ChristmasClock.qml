import QtQuick
import QtQuick.Shapes
import "../"

// The clock panel's sun arc turned into a Christmas arch: pine grows along it from both feet, bulbs light up toward
// the top, a star settles on the apex and the sun travels it as a bauble. The countdown sits under the date. Every
// new minute sends the lights up the arch again and the star flashes; on the hour (or when the star is pressed) it
// bursts. Lives inside the SunArc and borrows its geometry.
Item {
    id: clock
    required property Item arc
    anchors.fill: parent

    readonly property real unit: Scaler.s(1)
    property real grown: Christmas.motion ? 0 : 1       // the pine
    property real lit: Christmas.motion ? 0 : 1         // the bulbs
    property real wave: -1                              // a brighter pulse running up both sides, 0 feet .. 1 apex
    property real flash: 0                              // the star

    function relight(): void { if (Christmas.motion) { entrance.restart(); } else { grown = 1; lit = 1; } }
    function chime(big: bool): void {
        if (!Christmas.motion || entrance.running) return;
        ripple.restart();
        if (big) burst.play();
    }

    readonly property bool shown: arc.revealed
    onShownChanged: if (shown) relight()
    Component.onCompleted: if (shown) relight()
    property bool clocked: false
    function syncClock(): void {
        const want = visible && Christmas.motion && Christmas.twinkle;
        if (want === clocked) return;
        clocked = want;
        Christmas.requestClock(want);
    }
    onVisibleChanged: syncClock()
    Timer { interval: 1; running: true; onTriggered: clock.syncClock() }
    Component.onDestruction: if (clocked) Christmas.requestClock(false)

    // DateTime.time may show seconds: ripple only when the minute turns.
    property int minute: new Date().getMinutes()
    Connections {
        target: DateTime
        function onTimeChanged() {
            const now = new Date().getMinutes();
            if (now === clock.minute) return;
            clock.minute = now;
            clock.chime(now === 0);
        }
    }
    Connections {
        target: Christmas
        function onLightsOnSerialChanged() { clock.relight(); }
        function onMotionChanged() { clock.syncClock(); }
        function onTwinkleChanged() { clock.syncClock(); }
    }

    SequentialAnimation {
        id: entrance
        PropertyAction { target: clock; property: "grown"; value: 0 }
        PropertyAction { target: clock; property: "lit"; value: 0 }
        NumberAnimation { target: clock; property: "grown"; to: 1; duration: 800; easing.type: Easing.OutCubic }
        NumberAnimation { target: clock; property: "lit"; to: 1; duration: 900; easing.type: Easing.InOutSine }
        ScriptAction { script: { ripple.restart(); burst.play(); } }
    }
    SequentialAnimation {
        id: ripple
        ParallelAnimation {
            NumberAnimation { target: clock; property: "wave"; from: -0.15; to: 1.15; duration: 900; easing.type: Easing.InOutSine }
            SequentialAnimation {
                PauseAnimation { duration: 620 }
                NumberAnimation { target: clock; property: "flash"; to: 1; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: clock; property: "flash"; to: 0; duration: 620; easing.type: Easing.InOutSine }
            }
        }
        PropertyAction { target: clock; property: "wave"; value: -1 }
    }

    // Tufts of needles along the arc between two angles, as one path.
    function needles(from: real, to: real, length: real, phase: real): string {
        const count = 46;
        let path = "";
        for (let i = 0; i <= count; i++) {
            const a = from + (to - from) * i / count;
            const x = arc.px(a), y = arc.py(a);
            // the tangent, pointing the way the branch grows
            const tx = (to > from ? -1 : 1) * Math.sin(a) * arc.arcW / 2, ty = (to > from ? -1 : 1) * Math.cos(a) * arc.arcRy;
            const heading = Math.atan2(ty, tx);
            for (const side of [-1, 1]) {
                const spread = heading + side * (0.75 + 0.3 * Math.sin(i * 2.3 + phase));
                const reach = length * (0.7 + 0.3 * Math.sin(i * 5.1 + phase * 2 + side));
                path += "M" + x.toFixed(1) + "," + y.toFixed(1) + " l" + (Math.cos(spread) * reach).toFixed(1)
                    + "," + (Math.sin(spread) * reach).toFixed(1) + " ";
            }
        }
        return path;
    }

    // ── the pine, grown from both feet to the apex ───────────────────────────
    component Branch: Shape {
        id: branch
        property real foot: Math.PI
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.9
        readonly property real tip: foot + (Math.PI / 2 - foot) * clock.grown
        ShapePath {
            strokeColor: Christmas.pine
            strokeWidth: clock.unit * 2.6
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg { path: clock.grown > 0.01 && clock.width > 0 ? clock.needles(branch.foot, branch.tip, clock.unit * 13, 0) : "" }
        }
        ShapePath {
            strokeColor: Christmas.holly
            strokeWidth: clock.unit * 1.2
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg { path: clock.grown > 0.01 && clock.width > 0 ? clock.needles(branch.foot, branch.tip, clock.unit * 9, 1.7) : "" }
        }
    }
    Branch { foot: Math.PI }
    Branch { foot: 0 }

    // ── bulbs ────────────────────────────────────────────────────────────────
    Repeater {
        model: 18
        Item {
            id: lamp
            required property int index
            // nine on each side, from the foot (0) to just under the star (1)
            readonly property real up: (Math.floor(index / 2) + 0.5) / 9.6
            readonly property real angle: index % 2 ? up * Math.PI / 2 : Math.PI - up * Math.PI / 2
            readonly property real offset: clock.unit * (Math.floor(index / 2) % 2 ? 7 : -7)
            readonly property real power: Math.max(0, Math.min(1, (clock.lit * 1.2 - up) * 6))
            readonly property real boost: Math.max(0, 1 - Math.abs(clock.wave - up) * 6)
            readonly property real shimmer: clock.clocked ? 0.8 + 0.2 * Math.sin(Christmas.phase * 2.4 + index * 2.1) : 1
            readonly property color tint: Christmas.bulb(index)
            x: clock.arc.px(angle) + Math.cos(angle) * offset
            y: clock.arc.py(angle) - Math.sin(angle) * offset
            visible: clock.grown > up
            Rectangle {
                anchors.centerIn: parent
                width: clock.unit * (14 + 10 * lamp.boost); height: width; radius: width / 2
                color: Qt.alpha(lamp.tint, 0.22 + 0.2 * lamp.boost)
                opacity: lamp.power * lamp.shimmer
            }
            Rectangle {
                anchors.centerIn: parent
                width: clock.unit * 6; height: width; radius: width / 2
                scale: 1 + 0.5 * lamp.boost
                color: Qt.tint("#3a423d", Qt.alpha(lamp.tint, lamp.power * lamp.shimmer))
            }
        }
    }

    // ── the sun, as a bauble hung on the arch ────────────────────────────────
    Item {
        parent: clock.arc
        z: 3
        visible: clock.arc.sunUp
        x: clock.arc.sunX; y: clock.arc.sunY
        Rectangle {
            x: -width / 2; y: -clock.unit * 14
            width: clock.unit * 8; height: clock.unit * 6; radius: clock.unit * 1.5
            color: Christmas.gold
        }
        Rectangle {
            anchors.centerIn: parent
            width: clock.unit * 21; height: width; radius: width / 2
            border.width: clock.unit; border.color: Qt.alpha(Christmas.paleGold, 0.8)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Christmas.cranberry, 1.35) }
                GradientStop { position: 1; color: Christmas.deepRed }
            }
            Rectangle {
                x: parent.width * 0.22; y: parent.height * 0.18
                width: parent.width * 0.26; height: width; radius: width / 2
                color: Qt.alpha("white", 0.75)
            }
        }
    }

    // ── the star on the apex ─────────────────────────────────────────────────
    Item {
        id: star
        width: clock.unit * 36; height: width
        x: clock.arc.px(Math.PI / 2) - width / 2
        y: clock.arc.py(Math.PI / 2) - height / 2
        readonly property real k: Math.max(0, Math.min(1, (clock.lit - 0.75) * 4))
        readonly property real shimmer: clock.clocked ? 0.85 + 0.15 * Math.sin(Christmas.phase * 1.7) : 1
        Rectangle {
            anchors.centerIn: parent
            width: clock.unit * (38 + 30 * clock.flash); height: width; radius: width / 2
            color: Qt.alpha(Christmas.gold, 0.16 + 0.2 * clock.flash)
            opacity: star.k * star.shimmer
        }
        Shape {
            id: points
            readonly property real r: clock.unit * 14
            anchors.centerIn: parent; width: 2 * r; height: 2 * r
            preferredRendererType: Shape.CurveRenderer
            scale: (0.4 + 0.6 * star.k) * (1 + 0.28 * clock.flash + (starArea.containsMouse ? 0.12 : 0))
            rotation: 72 * (1 - star.k)
            opacity: star.k
            ShapePath {
                strokeColor: Christmas.paleGold
                strokeWidth: clock.unit
                joinStyle: ShapePath.RoundJoin
                fillColor: Christmas.gold
                PathPolyline {
                    path: Array.from({ length: 11 }, (_, i) => {
                        const a = i * Math.PI / 5 - Math.PI / 2, d = points.r * (i % 2 ? 0.45 : 1);
                        return Qt.point(points.r + Math.cos(a) * d, points.r + Math.sin(a) * d);
                    })
                }
            }
        }
        MouseArea {
            id: starArea
            parent: clock.arc.parent
            z: 100
            readonly property point centre: star.mapToItem(parent, star.width / 2, star.height / 2)
            x: centre.x - width / 2
            y: Math.max(0, centre.y - height / 2)
            width: clock.unit * 44
            height: Math.min(clock.unit * 44, centre.y + clock.unit * 22) - y
            enabled: star.k > 0.5
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: clock.chime(true)
        }
        Loader {
            id: burst
            anchors.centerIn: parent
            width: clock.unit * 150; height: width
            active: false
            function play(): void { active = false; active = true; }
            sourceComponent: ChristmasBurst {
                count: 11
                onFinished: burst.active = false
                Component.onCompleted: play()
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: { DateTime.time; return "✦  " + Christmas.countdown() + "  ✦"; }
        color: Qt.tint(Christmas.gold, Qt.alpha(ThemeBackend.text, 0.25))
        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: clock.unit * 11
        opacity: clock.lit
    }
}
