import QtQuick
import QtQuick.Shapes
import "../"

// A satin gift bow: two loops, a knot and two tails with cut ends. Drawn on a 100 × 80 grid scaled to the item.
Item {
    id: bow
    enabled: false
    property color ribbon: Christmas.cranberry
    property color shade: Christmas.deepRed
    property color shine: Qt.lighter(Christmas.cranberry, 1.35)
    property color piping: Christmas.gold
    implicitWidth: 100; implicitHeight: 80

    readonly property real kx: width / 100
    readonly property real ky: height / 80
    function p(x: real, y: real): string { return (x * kx).toFixed(2) + "," + (y * ky).toFixed(2); }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // tails behind the loops
        ShapePath {
            strokeWidth: -1
            fillColor: bow.shade
            PathSvg { path: "M" + bow.p(46, 31) + " L" + bow.p(27, 74) + " L" + bow.p(35, 67) + " L" + bow.p(40, 78) + " L" + bow.p(55, 35) + " Z" }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: bow.ribbon
            PathSvg { path: "M" + bow.p(54, 31) + " L" + bow.p(73, 74) + " L" + bow.p(65, 67) + " L" + bow.p(60, 78) + " L" + bow.p(45, 35) + " Z" }
        }
        // loops
        ShapePath {
            strokeColor: Qt.alpha(bow.piping, 0.55)
            strokeWidth: Math.max(0.6, 1.2 * bow.kx)
            fillColor: bow.ribbon
            PathSvg { path: "M" + bow.p(50, 30) + " C" + bow.p(36, 6) + " " + bow.p(4, 3) + " " + bow.p(6, 23)
                          + " C" + bow.p(8, 41) + " " + bow.p(35, 41) + " " + bow.p(50, 30) + " Z" }
        }
        ShapePath {
            strokeColor: Qt.alpha(bow.piping, 0.55)
            strokeWidth: Math.max(0.6, 1.2 * bow.kx)
            fillColor: bow.ribbon
            PathSvg { path: "M" + bow.p(50, 30) + " C" + bow.p(64, 6) + " " + bow.p(96, 3) + " " + bow.p(94, 23)
                          + " C" + bow.p(92, 41) + " " + bow.p(65, 41) + " " + bow.p(50, 30) + " Z" }
        }
        // the hollow of each loop
        ShapePath {
            strokeWidth: -1
            fillColor: bow.shade
            PathSvg { path: "M" + bow.p(49, 29) + " C" + bow.p(38, 17) + " " + bow.p(17, 14) + " " + bow.p(17, 23)
                          + " C" + bow.p(18, 31) + " " + bow.p(37, 33) + " " + bow.p(49, 29) + " Z" }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: bow.shade
            PathSvg { path: "M" + bow.p(51, 29) + " C" + bow.p(62, 17) + " " + bow.p(83, 14) + " " + bow.p(83, 23)
                          + " C" + bow.p(82, 31) + " " + bow.p(63, 33) + " " + bow.p(51, 29) + " Z" }
        }
        // satin sheen along the top of each loop
        ShapePath {
            strokeColor: Qt.alpha(bow.shine, 0.85)
            strokeWidth: Math.max(0.8, 2 * bow.kx)
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg { path: "M" + bow.p(40, 17) + " C" + bow.p(30, 9) + " " + bow.p(15, 8) + " " + bow.p(11, 15) }
        }
        ShapePath {
            strokeColor: Qt.alpha(bow.shine, 0.85)
            strokeWidth: Math.max(0.8, 2 * bow.kx)
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathSvg { path: "M" + bow.p(60, 17) + " C" + bow.p(70, 9) + " " + bow.p(85, 8) + " " + bow.p(89, 15) }
        }
    }
    // the knot
    Rectangle {
        x: 43 * bow.kx; y: 22 * bow.ky
        width: 14 * bow.kx; height: 17 * bow.ky
        radius: Math.min(width, height) * 0.35
        gradient: Gradient {
            GradientStop { position: 0; color: bow.shine }
            GradientStop { position: 0.45; color: bow.ribbon }
            GradientStop { position: 1; color: bow.shade }
        }
        border.width: Math.max(0.6, 1 * bow.kx)
        border.color: Qt.alpha(bow.piping, 0.6)
    }
}
