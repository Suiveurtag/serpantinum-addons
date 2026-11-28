import QtQuick
import QtQuick.Shapes
import "../"

// Below freezing, the clock panel ices over: plates of ice crystallise from the corners (shaders/freeze.frag) and
// icicles grow down from the top.
// It grows once each time it appears, then stands still. Never takes input.
Item {
    id: freeze
    enabled: false
    property real cornerRadius: 0
    readonly property real unit: Scaler.s(1)
    property real hang: Christmas.motion ? 0 : 1     // the icicles
    property real grow: Christmas.motion ? 0 : 1     // the ice plates
    Component.onCompleted: if (Christmas.motion) setting.start()
    ParallelAnimation {
        id: setting
        NumberAnimation { target: freeze; property: "grow"; to: 1; duration: 2800; easing.type: Easing.InOutSine }
        SequentialAnimation {
            PauseAnimation { duration: 900 }
            NumberAnimation { target: freeze; property: "hang"; to: 1; duration: 2200; easing.type: Easing.OutCubic }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        readonly property real grow: freeze.grow
        readonly property real cornerRadius: freeze.cornerRadius
        readonly property real unit: freeze.unit
        readonly property size extent: Qt.size(width, height)
        fragmentShader: Qt.resolvedUrl("shaders/freeze.frag.qsb")
    }

    // Icicles of uneven length in loose clusters, as one path.
    function icicles(from: real, to: real, grown: real): string {
        let path = "";
        for (let x = from, i = 0; x < to; i++) {
            const a = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1, b = Math.abs(Math.sin(i * 78.233) * 24634.6345) % 1;
            const w = unit * (5 + 6 * a);
            const h = unit * (6 + 34 * b * b * b + (i % 7 === 3 ? 12 : 0)) * grown;
            path += "M" + x.toFixed(1) + ",0 Q" + (x + w * 0.4).toFixed(1) + "," + (h * 0.35).toFixed(1) + " "
                + (x + w * 0.5).toFixed(1) + "," + h.toFixed(1) + " Q" + (x + w * 0.6).toFixed(1) + "," + (h * 0.35).toFixed(1)
                + " " + (x + w).toFixed(1) + ",0 Z ";
            x += w + unit * (i % 5 === 4 ? 16 : 1.5);
        }
        return path;
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: freeze.hang > 0.01
        ShapePath {
            strokeColor: Qt.alpha("#ffffff", 0.55)
            strokeWidth: freeze.unit * 0.7
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: freeze.unit * 45
                GradientStop { position: 0; color: Qt.alpha("#eef8ff", 0.85) }
                GradientStop { position: 1; color: Qt.alpha("#8ecbff", 0.35) }
            }
            PathSvg {
                path: freeze.width > 0 ? freeze.icicles(Math.max(freeze.unit * 4, freeze.cornerRadius * 0.8),
                    freeze.width - Math.max(freeze.unit * 14, freeze.cornerRadius * 1.2), freeze.hang) : ""
            }
        }
    }
}
