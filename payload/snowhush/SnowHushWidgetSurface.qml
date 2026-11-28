import QtQuick
import Quickshell
import "../"

// Where snow lands on one desktop widget: what its face actually paints, not its window.
Scope {
    id: widget

    required property string name
    required property var screen
    required property bool shown
    required property var face      // the Loader holding the widget's face
    required property point center
    required property size limit

    readonly property string file: String(face.source).split("/").pop()
    // These faces draw on the bare wallpaper: snow falls through them.
    readonly property bool bare: ["TextFace", "ClockFaceDigital", "ClockFaceMinimal", "ClockFaceStretched",
        "ClockFaceLockscreen", "ClockFaceMaterial", "VisualizerFace", "VisualizerFaceContinuous",
        "MusicFaceLyricsSimple", "SnakeFace", "TimerFace", "TimerFaceTimer", "TimerFaceStopwatch",
        "TimerFacePomodoro"].indexOf(file.replace(".qml", "")) >= 0
    // The rest paint a card at the theme's element opacity, unless they are a picture or a gauge.
    readonly property bool round: Boolean(face.item && face.item.isRound) || file.endsWith("Circle.qml")
    readonly property bool solid: !bare && (round || file.startsWith("Image") || ThemeBackend.elementOpacity >= 0.05)
    // A pill lying at 45 degrees: its two round ends.
    readonly property bool pill: file === "WeatherFaceRound.qml"

    readonly property real side: Math.min(face.width, face.height)
    // What a round face paints can be smaller than its box.
    readonly property real diameter: pill ? side * 0.54
        : face.item && face.item.artRadius !== undefined ? face.item.artRadius * 2
        : file === "ClockFaceMaterialLumen.qml" ? side * 0.9 : side
    readonly property real radians: face.rotation * Math.PI / 180
    readonly property real cosine: Math.abs(Math.cos(radians))
    readonly property real sine: Math.abs(Math.sin(radians))
    readonly property real boxWidth: round ? diameter : Math.min(limit.width, cosine * face.width + sine * face.height)
    readonly property real boxHeight: round ? diameter : Math.min(limit.height, sine * face.width + cosine * face.height)
    // From the pill's middle to the centre of its upper end.
    readonly property point reach: pill ? Qt.point(side * 0.2 * Math.sin(radians + Math.PI / 4),
                                                   -side * 0.2 * Math.cos(radians + Math.PI / 4)) : Qt.point(0, 0)

    SnowHushSurface {
        name: widget.name
        kind: "widgets"
        screen: widget.screen
        shown: widget.shown && widget.solid
        bounds: Qt.rect(widget.center.x + widget.reach.x - widget.boxWidth / 2,
                        widget.center.y + widget.reach.y - widget.boxHeight / 2,
                        widget.boxWidth, widget.boxHeight)
        radius: widget.round ? widget.diameter / 2 : ThemeBackend.borderRadius
    }

    SnowHushSurface {
        name: widget.name + "/end"
        kind: "widgets"
        screen: widget.screen
        shown: widget.shown && widget.solid && widget.pill
        bounds: Qt.rect(widget.center.x - widget.reach.x - widget.boxWidth / 2,
                        widget.center.y - widget.reach.y - widget.boxHeight / 2,
                        widget.boxWidth, widget.boxHeight)
        radius: widget.diameter / 2
    }
}
