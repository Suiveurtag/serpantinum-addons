import QtQuick
import QtQuick.Shapes
import "../"

// Santa flies over the full calendar: three reindeer and the sleigh cross it in a long swoop, leaving stardust and
// dropping presents on the days. Once when the agenda opens, then each time another period is shown, flying the way
// time went. Never takes input, and nothing runs between two flights.
Item {
    id: sky
    enabled: false
    readonly property real unit: Scaler.s(1) * 1.25
    readonly property real team: unit * 190
    property real t: 0
    property int direction: 1       // 1 toward later dates (left to right)
    property real height0: 0.34     // where this flight crosses, as a share of the height
    readonly property bool flying: flight.running

    function fly(way: int): void {
        if (!Christmas.motion || flight.running) return;
        direction = way;
        height0 = 0.3 + Math.random() * 0.25;
        flight.restart();
    }
    // The path: x runs across, y dips in a swoop and climbs away.
    function px(k: real): real {
        const along = -team + (width + 2 * team) * k;
        return direction > 0 ? along : width - along;
    }
    function py(k: real): real { return height * height0 + Math.sin(k * Math.PI * 1.6 - 0.3) * height * 0.13; }

    NumberAnimation { id: flight; target: sky; property: "t"; from: 0; to: 1.45; duration: 4200 }
    Timer { interval: 350; running: true; onTriggered: sky.fly(1) }

    property real shown: 0
    Component.onCompleted: if (typeof GCal !== "undefined") shown = GCal.focusDate.getTime()
    Connections {
        target: typeof GCal !== "undefined" ? GCal : null
        function onFocusDateChanged() {
            const next = GCal.focusDate.getTime();
            if (next !== sky.shown) sky.fly(next > sky.shown ? 1 : -1);
            sky.shown = next;
        }
    }

    // ── stardust left along the path ─────────────────────────────────────────
    Repeater {
        model: sky.flying ? 56 : 0
        Text {
            required property int index
            readonly property real born: index / 56
            readonly property real age: (sky.t - born - 0.04) / 0.38
            readonly property real r: Math.abs(Math.sin(index * 91.17) * 437.5) % 1
            visible: age > 0 && age < 1
            x: sky.px(born) - sky.direction * sky.unit * 60 - width / 2 + (r - 0.5) * sky.unit * 14
            y: sky.py(born) - height / 2 + (r - 0.5) * sky.unit * 34 + age * age * sky.unit * 46
            text: "✦"
            color: index % 5 === 0 ? Christmas.bulb(index) : index % 2 ? Christmas.paleGold : Christmas.gold
            font.pixelSize: sky.unit * (6 + 12 * r)
            opacity: (1 - age) * Christmas.effectOpacity
            rotation: age * 180 * (r - 0.5)
            scale: 1 - 0.5 * age
        }
    }

    // ── presents dropped on the way ──────────────────────────────────────────
    Repeater {
        model: sky.flying ? 5 : 0
        Item {
            id: gift
            required property int index
            readonly property real born: 0.18 + index * 0.15
            readonly property real age: (sky.t - born) / 0.55
            visible: age > 0 && age < 1
            x: sky.px(born) - sky.direction * (sky.unit * 40 - age * sky.unit * 24) + Math.sin(age * 7 + index) * sky.unit * 8
            y: sky.py(born) + age * age * sky.height * 0.5
            rotation: Math.sin(age * 6 + index * 2) * 18
            opacity: age < 0.65 ? 1 : (1 - age) / 0.35
            Rectangle {
                x: -width / 2; y: 0; width: sky.unit * 15; height: sky.unit * 13; radius: sky.unit * 2
                color: Christmas.bulb(gift.index)
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: sky.unit * 2.5; height: parent.height; color: Christmas.cream }
            }
            ChristmasBow {
                x: -width / 2; y: -height * 0.65; width: sky.unit * 12; height: width * 0.8
                ribbon: Christmas.cream; shade: Christmas.gold; shine: "white"
            }
        }
    }

    // ── the team, drawn facing right on a 190 × 60 grid ──────────────────────
    Item {
        id: sled
        visible: sky.flying && sky.t < 1
        width: 190; height: 60
        x: sky.px(sky.t) - width / 2
        y: sky.py(sky.t) - height / 2
        readonly property real climb: Math.atan2(sky.py(sky.t + 0.01) - sky.py(sky.t), Math.abs(sky.px(sky.t + 0.01) - sky.px(sky.t))) * 180 / Math.PI
        transform: [
            Scale { origin.x: 95; origin.y: 30; xScale: sky.unit * sky.direction; yScale: sky.unit },
            Rotation { origin.x: 95; origin.y: 30; angle: sled.climb * 0.7 * sky.direction }
        ]

        Shape {     // reins
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Christmas.gold; strokeWidth: 1.2; fillColor: "transparent"
                PathSvg { path: "M40,34 Q62,44 82,32 Q104,42 124,32 Q146,42 164,30" }
            }
        }
        Repeater {
            model: 3
            Item {
                id: deer
                required property int index
                readonly property real gait: Math.sin(sky.t * 62 + index * 2.1)
                x: 66 + index * 42; y: 14 + gait * 3
                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {     // legs
                        strokeColor: "#8a5a36"; strokeWidth: 2.4; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                        PathSvg {
                            path: "M8,22 l" + (-7 * deer.gait - 3) + ",11 M12,23 l" + (-4 * deer.gait) + ",12 "
                                + "M24,22 l" + (7 * deer.gait + 3) + ",10 M28,21 l" + (4 * deer.gait + 5) + ",10"
                        }
                    }
                    ShapePath {     // body, neck and head
                        strokeColor: Christmas.paleGold; strokeWidth: 0.8; fillColor: "#a9724a"
                        PathSvg { path: "M3,17 Q4,10 14,12 L24,12 L29,3 Q33,-1 37,3 L42,7 Q41,11 35,10 L32,19 Q28,26 17,25 Q4,26 3,17 Z" }
                    }
                    ShapePath {     // antlers
                        strokeColor: Christmas.cream; strokeWidth: 1.4; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                        PathSvg { path: "M31,2 Q27,-6 20,-8 M27,-3 L27,-10 M34,1 Q34,-7 39,-11 M35,-5 L41,-5" }
                    }
                }
                Rectangle {     // the leader's nose glows
                    visible: deer.index === 2
                    x: 39; y: 4; width: 6; height: 6; radius: 3; color: "#ff4538"
                    Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: Qt.alpha("#ff4538", 0.35) }
                }
            }
        }
        // Santa and his sack, sitting in the sleigh
        Rectangle { x: 4; y: 12; width: 20; height: 22; radius: 10; color: Christmas.holly }
        Rectangle { x: 24; y: 17; width: 15; height: 18; radius: 5; color: Christmas.cranberry }
        Rectangle { x: 27; y: 8; width: 11; height: 11; radius: 5.5; color: "#f2c7a5" }
        Rectangle { x: 28; y: 15; width: 11; height: 9; radius: 4.5; color: "white" }
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {     // hat
                strokeWidth: -1; fillColor: Christmas.cranberry
                PathSvg { path: "M26,11 Q28,1 36,4 Q28,4 20,13 Z" }
            }
            ShapePath {     // the sleigh
                strokeColor: Christmas.gold; strokeWidth: 1.6; fillColor: Christmas.deepRed
                PathSvg { path: "M2,24 Q4,42 18,43 L38,43 Q50,42 51,28 Q52,22 46,24 Q43,34 30,31 Q14,28 2,24 Z" }
            }
            ShapePath {     // runner
                strokeColor: Christmas.paleGold; strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathSvg { path: "M4,50 L44,50 Q56,49 55,40 M15,43 L13,50 M37,43 L39,50" }
            }
        }
        Rectangle { x: 18; y: 9; width: 5; height: 5; radius: 2.5; color: "white" }
    }
}
