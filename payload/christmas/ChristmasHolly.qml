import QtQuick
import QtQuick.Shapes
import "../"

// Three holly leaves around a cluster of berries. `grown` (0..1) unfurls the leaves and pops the berries one by one.
Item {
    id: sprig
    enabled: false
    property real grown: 1
    property color leaf: Christmas.holly
    property color leafDark: "#1b4d31"
    property color vein: "#7cc596"
    property color berry: "#d42a3e"
    implicitWidth: 64; implicitHeight: 64
    readonly property real unit: Math.min(width, height) / 64

    function stage(from: real, span: real): real { return Math.max(0, Math.min(1, (grown - from) / span)); }

    component Leaf: Item {
        id: leafItem
        property real angle: 0
        property real start: 0
        readonly property real k: sprig.stage(start, 0.55)
        x: sprig.width / 2; y: sprig.height / 2
        rotation: angle - 30 * (1 - k)
        scale: 0.3 + 0.7 * k
        opacity: Math.min(1, k * 2)
        transformOrigin: Item.TopLeft
        Shape {
            preferredRendererType: Shape.CurveRenderer
            scale: sprig.unit
            transformOrigin: Item.TopLeft
            // a leaf from the stem (0,0) to its tip (30,0), with three spines on each side
            ShapePath {
                strokeColor: sprig.leafDark
                strokeWidth: 0.8
                fillGradient: LinearGradient {
                    x1: 0; y1: -6; x2: 0; y2: 6
                    GradientStop { position: 0; color: Qt.lighter(sprig.leaf, 1.25) }
                    GradientStop { position: 1; color: sprig.leaf }
                }
                PathSvg { path: "M0,0 Q1,-4 5,-5.5 Q9,-2.5 12.5,-6.5 Q15.5,-3 19.5,-6 Q22,-2.5 26,-4 Q27.5,-1.5 31,0"
                              + " Q27.5,1.5 26,4 Q22,2.5 19.5,6 Q15.5,3 12.5,6.5 Q9,2.5 5,5.5 Q1,4 0,0 Z" }
            }
            ShapePath {
                strokeColor: Qt.alpha(sprig.vein, 0.7)
                strokeWidth: 0.7
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M1,0 Q15,-0.8 28,0" }
            }
        }
    }
    component Berry: Rectangle {
        property real cx: 0
        property real cy: 0
        property real start: 0
        readonly property real k: sprig.stage(start, 0.3)
        width: 9 * sprig.unit; height: width; radius: width / 2
        x: sprig.width / 2 + cx * sprig.unit - width / 2
        y: sprig.height / 2 + cy * sprig.unit - height / 2
        // ease-out-back: overshoots a little, then settles
        scale: k <= 0 ? 0 : 1 + 3.55 * Math.pow(k - 1, 3) + 2.55 * Math.pow(k - 1, 2)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(sprig.berry, 1.3) }
            GradientStop { position: 1; color: Qt.darker(sprig.berry, 1.35) }
        }
        Rectangle {
            x: parent.width * 0.22; y: parent.height * 0.18
            width: parent.width * 0.3; height: width; radius: width / 2
            color: Qt.alpha("white", 0.7)
        }
    }

    Leaf { angle: -150; start: 0 }
    Leaf { angle: -32; start: 0.12 }
    Leaf { angle: 88; start: 0.24 }
    Berry { cx: -3.5; cy: -2; start: 0.45 }
    Berry { cx: 4; cy: -3; start: 0.55 }
    Berry { cx: 0.5; cy: 4.5; start: 0.65 }
}
