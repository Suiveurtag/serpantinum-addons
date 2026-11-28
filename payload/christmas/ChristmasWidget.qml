import QtQuick
import QtQuick.Shapes
import "../"

// Dresses one desktop widget, following what its face paints: a card gets fairy lights along its top and maybe holly
// on a top corner, a round face an arc of bulbs inside its rim and maybe holly below, the weather pill a bow on its upper end.
// Faces drawn on the bare wallpaper stay as they are. Lies over the face, turns with it and never takes input.
Item {
    id: decor
    enabled: false
    required property var face      // the Loader holding the widget's face

    readonly property string file: String(face.source).split("/").pop().replace(".qml", "")
    readonly property bool bare: ["TextFace", "ClockFaceDigital", "ClockFaceMinimal", "ClockFaceStretched",
        "ClockFaceLockscreen", "ClockFaceMaterial", "VisualizerFace", "VisualizerFaceContinuous",
        "MusicFaceLyricsSimple", "SnakeFace", "TimerFace", "TimerFaceTimer", "TimerFaceStopwatch",
        "TimerFacePomodoro"].indexOf(file) >= 0
    readonly property bool pill: file === "WeatherFaceRound"
    readonly property bool round: !pill && (Boolean(face.item && face.item.isRound) || file.endsWith("Circle"))
    readonly property bool card: !bare && !pill && !round && (file.startsWith("Image") || ThemeBackend.elementOpacity >= 0.05)

    readonly property real unit: Scaler.s(1)
    readonly property real side: Math.min(width, height)
    // What a round face paints can be smaller than its box.
    readonly property real diameter: face.item && face.item.artRadius !== undefined ? face.item.artRadius * 2
        : file === "ClockFaceMaterialLumen" ? side * 0.9 : side
    readonly property real sprigSize: Math.max(unit * 22, Math.min(unit * 46, side * 0.27))

    // Holly is left to chance, drawn once for each widget as it appears: half of them get a sprig, on either side.
    property bool sprig: false
    property bool sprigRight: true
    Component.onCompleted: {
        sprig = Math.random() < 0.5;
        sprigRight = Math.random() < 0.5;
    }

    Loader {
        anchors.fill: parent
        active: decor.card
        sourceComponent: Item {
            ChristmasGarland {
                anchors.fill: parent
                cornerRadius: ThemeBackend.borderRadius
                seed: decor.file.length
            }
            ChristmasHolly {
                readonly property real inset: Math.max(decor.unit * 5, ThemeBackend.borderRadius * 0.35)
                visible: decor.sprig
                width: decor.sprigSize; height: width
                x: (decor.sprigRight ? parent.width - inset : inset) - width / 2
                y: inset - height / 2
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        width: decor.diameter; height: width
        active: decor.round
        sourceComponent: Item {
            id: ring
            readonly property real bulb: Math.max(decor.unit * 3.5, Math.min(decor.unit * 7, width * 0.028))
            readonly property real arc: width / 2 - bulb * 1.1
            // an odd count, so one bulb sits at the very top
            readonly property int count: 2 * Math.max(3, Math.min(8, Math.round(arc * 2.3 / (decor.unit * 44)))) + 1
            property real lit: 0
            function relight(): void {
                rise.stop();
                if (!Christmas.motion) { lit = 1; return; }
                lit = 0;
                rise.restart();
            }
            readonly property bool on: Christmas.enabled
            onOnChanged: {
                if (on) relight();
                else { rise.stop(); if (Christmas.motion) fall.restart(); else lit = 0; }
            }
            readonly property bool clocked: on && visible && Christmas.twinkle && Christmas.motion
            property bool registered: false
            function syncClock(): void {
                if (clocked === registered) return;
                registered = clocked;
                Christmas.requestClock(clocked);
            }
            onClockedChanged: syncClock()
            Component.onCompleted: { if (on) relight(); syncClock(); }
            Component.onDestruction: if (registered) Christmas.requestClock(false)
            NumberAnimation { id: rise; target: ring; property: "lit"; to: 1; duration: 1500; easing.type: Easing.InOutSine }
            NumberAnimation { id: fall; target: ring; property: "lit"; to: 0; duration: 420; easing.type: Easing.InQuad }
            Connections {
                target: Christmas
                function onLightsOnSerialChanged() { ring.relight(); }
                function onLightsChanged() { if (ring.on && !Christmas.randomLights) ring.relight(); }
                function onRandomLightsChanged() { if (ring.on) ring.relight(); }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: Math.min(1, ring.lit * 3)
                ShapePath {
                    strokeColor: Christmas.wire
                    strokeWidth: Math.max(1, decor.unit * 1.2)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.arc; radiusY: ring.arc
                        startAngle: -152; sweepAngle: 124
                    }
                }
            }
            Repeater {
                model: ring.count
                Item {
                    id: lamp
                    required property int index
                    readonly property real along: index / (ring.count - 1)
                    readonly property real angle: (-150 + 120 * along) * Math.PI / 180
                    // lights from the top outwards
                    readonly property real power: Math.max(0, Math.min(1, ring.lit * 3 - Math.abs(along - 0.5) * 4))
                    readonly property real shimmer: ring.clocked ? 0.82 + 0.18 * Math.sin(Christmas.phase * 2.4 + index * 2.1) : 1
                    readonly property color tint: Christmas.bulb(index)
                    x: ring.width / 2 + ring.arc * Math.cos(angle)
                    y: ring.height / 2 + ring.arc * Math.sin(angle)
                    opacity: Math.min(1, ring.lit * 3)
                    Rectangle {
                        anchors.centerIn: parent
                        width: ring.bulb * 2.4; height: width; radius: width / 2
                        color: Qt.alpha(lamp.tint, 0.24)
                        opacity: lamp.power * lamp.shimmer
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: ring.bulb; height: width; radius: width / 2
                        color: Qt.tint("#3a423d", Qt.alpha(lamp.tint, lamp.power * lamp.shimmer))
                    }
                }
            }
            ChristmasHolly {
                visible: decor.sprig
                width: decor.sprigSize; height: width
                x: ring.width / 2 + (decor.sprigRight ? 1 : -1) * (ring.width / 2 - width * 0.12) * 0.707 - width / 2
                y: ring.height / 2 + (ring.height / 2 - width * 0.12) * 0.707 - height / 2
            }
        }
    }

    Loader {
        active: decor.pill
        // the pill lies at 45 degrees: its upper end
        x: decor.width / 2 + decor.side * 0.2 * Math.SQRT1_2
        y: decor.height / 2 - decor.side * 0.2 * Math.SQRT1_2 - decor.side * 0.27
        sourceComponent: ChristmasBow {
            width: decor.side * 0.28; height: width * 0.8
            x: -width / 2; y: -height * 0.2
            rotation: 14
        }
    }
}
