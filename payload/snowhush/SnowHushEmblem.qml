import QtQuick
import QtQuick.Shapes

// What floats in the snow globe: one sticker-like vector emblem per kind of weather, drawn in a 100 × 100 box with the
// card's riso off-register shadow. A change of kind spins the old one away and pops the new one in.
Item {
    id: emblem

    property string kind: "snow"
    property bool animate: true     // play the swap between kinds
    property bool live: false       // idle motion: turning, swaying, bobbing
    property bool mono: false       // one ink only, for the postmark
    property color paper: "#f2ebd6"
    property color ink: "#10292c"
    property color frost: "#cfe9e4"

    property string shown: "snow"
    readonly property bool spins: shown === "snow" || shown === "blossom"
    readonly property color shadow: mono ? "transparent" : Qt.alpha(ink, 0.5)
    readonly property real rim: mono ? 0 : 3.5

    onKindChanged: {
        if (animate) {
            swap.restart();
        } else {
            swap.stop();
            shown = kind; pop.scale = 1; pop.rotation = 0;
        }
    }
    Component.onCompleted: shown = kind

    // Points of an outline turned about the centre, as SVG path data: [command, x, y, x, y, …].
    function turned(outline: var, angle: real): string {
        const c = Math.cos(angle), n = Math.sin(angle);
        return outline.map(step => {
            let d = step[0];
            for (let i = 1; i + 1 < step.length; i += 2) {
                const x = step[i] - 50, y = step[i + 1] - 50;
                d += " " + (50 + x * c - y * n).toFixed(2) + " " + (50 + x * n + y * c).toFixed(2);
            }
            return d;
        }).join(" ");
    }
    function around(count: int, outline: var): string {
        let d = "";
        for (let i = 0; i < count; i++) d += turned(outline, i * Math.PI * 2 / count) + " ";
        return d;
    }
    function dot(x: real, y: real, r: real): string {
        return "M " + (x - r) + " " + y + " a " + r + " " + r + " 0 1 0 " + 2 * r + " 0 a " + r + " " + r + " 0 1 0 " + -2 * r + " 0 Z ";
    }

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: pop; property: "scale"; to: 0; duration: 170; easing.type: Easing.InBack }
            NumberAnimation { target: pop; property: "rotation"; to: -80; duration: 170; easing.type: Easing.InCubic }
        }
        ScriptAction { script: emblem.shown = emblem.kind }
        ParallelAnimation {
            NumberAnimation { target: pop; property: "scale"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
            NumberAnimation { target: pop; property: "rotation"; from: 90; to: 0; duration: 460; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: pop
        anchors.fill: parent
        Item {
            id: idle
            property real spin: 0
            property real sway: 0
            width: parent.width; height: parent.height
            rotation: emblem.spins ? spin : emblem.shown === "rain" ? 0 : sway
            y: emblem.shown === "rain" || emblem.shown === "halloween" ? Math.abs(sway) / 9 * height * 0.05 : 0
            NumberAnimation on spin { running: emblem.live && emblem.spins; from: 0; to: 360; duration: 16000; loops: Animation.Infinite }
            SequentialAnimation on sway {
                running: emblem.live && !emblem.spins
                loops: Animation.Infinite
                NumberAnimation { to: 9; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { to: -9; duration: 1900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
            Loader {
                width: 100; height: 100
                anchors.centerIn: parent
                scale: parent.width / 100
                sourceComponent: ({ autumn: leaf, rain: drop, blossom: flower, christmas: fir, halloween: pumpkin })[emblem.shown] || flake
            }
        }
    }

    // A filled outline with its paper rim.
    component Body: ShapePath {
        property alias d: svg.path
        strokeColor: emblem.paper
        strokeWidth: emblem.rim > 0 ? emblem.rim : -1
        joinStyle: ShapePath.RoundJoin
        fillRule: ShapePath.WindingFill
        PathSvg { id: svg }
    }
    // A flat patch of colour.
    component Patch: ShapePath {
        property alias d: svg.path
        strokeWidth: -1
        fillRule: ShapePath.WindingFill
        PathSvg { id: svg }
    }
    // An open line.
    component Stroke: ShapePath {
        property alias d: svg.path
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { id: svg }
    }
    component Art: Shape {
        width: 100; height: 100
        preferredRendererType: Shape.CurveRenderer
    }

    Component {
        id: flake
        Item {
            id: snowArt
            // six arms, each with two pairs of barbs
            readonly property string d: emblem.around(6, [["M", 50, 50], ["L", 50, 5], ["M", 50, 26], ["L", 38, 15], ["M", 50, 26], ["L", 62, 15],
                                                          ["M", 50, 38], ["L", 42, 31], ["M", 50, 38], ["L", 58, 31]])
            Art { x: 4; y: 4; Stroke { d: snowArt.d; strokeColor: emblem.shadow; strokeWidth: 5.5 } }
            Art { Stroke { d: snowArt.d; strokeColor: emblem.paper; strokeWidth: 5.5 } }
            Art { Patch { d: emblem.dot(50, 50, 8); fillColor: emblem.paper } }
        }
    }

    Component {
        id: leaf
        Item {
            id: leafArt
            readonly property string d: "M50 4 L59 22 L69 17 L65 39 L80 26 L83 36 L96 35 L88 52 L94 58 L72 70 L76 80 L53 75 L47 75 L24 80 L28 70 L6 58 L12 52 L4 35 L17 36 L20 26 L35 39 L31 17 L41 22 Z"
            Art { x: 5; y: 5; Patch { d: leafArt.d; fillColor: emblem.shadow } }
            Art {
                Stroke { d: "M50 72 Q49 86 56 96"; strokeColor: emblem.paper; strokeWidth: 5 }
                Body { d: leafArt.d; fillColor: emblem.mono ? emblem.paper : "#e0702a" }
                Stroke {
                    d: "M50 72 L50 22 M50 60 L77 43 M50 60 L23 43 M50 69 L68 66 M50 69 L32 66"
                    strokeColor: emblem.mono ? emblem.ink : Qt.alpha(emblem.paper, 0.85); strokeWidth: 2.6
                }
            }
        }
    }

    Component {
        id: drop
        Item {
            id: rainArt
            readonly property string d: "M50 5 C62 28 80 45 80 65 C80 82 67 95 50 95 C33 95 20 82 20 65 C20 45 38 28 50 5 Z"
            readonly property string small: "M14 14 C18 22 23 27 23 33 C23 38 19 42 14 42 C9 42 5 38 5 33 C5 27 10 22 14 14 Z "
                + "M86 22 C89 28 93 32 93 37 C93 41 90 44 86 44 C82 44 79 41 79 37 C79 32 83 28 86 22 Z"
            Art { x: 5; y: 5; Patch { d: rainArt.d; fillColor: emblem.shadow } }
            Art {
                Patch { d: rainArt.small; fillColor: Qt.alpha(emblem.paper, 0.75) }
                Body { d: rainArt.d; fillColor: emblem.mono ? emblem.paper : "#7fa9de" }
                Stroke { d: "M33 62 C32 74 38 82 47 84"; strokeColor: emblem.mono ? emblem.ink : emblem.paper; strokeWidth: 5 }
            }
        }
    }

    Component {
        id: flower
        Item {
            id: flowerArt
            readonly property string d: emblem.around(5, [["M", 50, 50], ["C", 26, 41, 21, 14, 40, 4], ["L", 50, 14], ["L", 60, 4],
                                                          ["C", 79, 14, 74, 41, 50, 50], ["Z"]])
            readonly property string stamens: emblem.around(5, [["M", 50, 50], ["L", 50, 32]])
            Art { x: 5; y: 5; Patch { d: flowerArt.d; fillColor: emblem.shadow } }
            Art {
                Body { d: flowerArt.d; fillColor: emblem.mono ? emblem.paper : "#f4a9c6" }
                Stroke { d: flowerArt.stamens; strokeColor: emblem.mono ? emblem.ink : "#b8456f"; strokeWidth: 2.6 }
                Patch {
                    d: [0, 1, 2, 3, 4].map(i => emblem.dot(50 + Math.sin(i * Math.PI * 0.4) * 19, 50 - Math.cos(i * Math.PI * 0.4) * 19, 3.4)).join("")
                    fillColor: emblem.mono ? emblem.ink : "#b8456f"
                }
                Patch { d: emblem.dot(50, 50, 9); fillColor: emblem.mono ? emblem.ink : "#ffe0a3" }
            }
        }
    }

    // New Year: the decorated fir under its star
    Component {
        id: fir
        Item {
            id: firArt
            readonly property string d: "M50 15 L70 40 L61 40 L78 61 L68 61 L88 84 L12 84 L32 61 L22 61 L39 40 L30 40 Z"
            Art { x: 5; y: 5; Patch { d: firArt.d; fillColor: emblem.shadow } }
            Art {
                Patch { d: "M43 83 L57 83 L57 97 L43 97 Z"; fillColor: emblem.mono ? emblem.paper : "#9a6a42" }
                Body { d: firArt.d; fillColor: emblem.mono ? emblem.paper : "#2f8a55" }
                Stroke { d: "M38 43 Q52 55 66 49 M28 66 Q50 82 72 69"; strokeColor: emblem.mono ? emblem.ink : emblem.frost; strokeWidth: 2.8 }
                Patch {
                    d: emblem.dot(45, 34, 4.5) + emblem.dot(57, 61, 5) + emblem.dot(30, 76, 4.5) + emblem.dot(70, 77, 4.5) + emblem.dot(40, 54, 3.8)
                    fillColor: emblem.mono ? emblem.ink : "#e2483c"
                }
                Body {
                    d: "M50 0 L54.5 10 L65 11 L57 18.5 L59.5 29 L50 23.5 L40.5 29 L43 18.5 L35 11 L45.5 10 Z"
                    fillColor: emblem.mono ? emblem.paper : "#ffd466"
                    strokeWidth: emblem.rim > 0 ? 2 : -1
                }
            }
        }
    }

    Component {
        id: pumpkin
        Item {
            id: pumpkinArt
            readonly property string d: "M50 29 C70 17 97 31 95 59 C93 83 73 95 62 90 C56 95 44 95 38 90 C27 95 7 83 5 59 C3 31 30 17 50 29 Z"
            Art { x: 5; y: 5; Patch { d: pumpkinArt.d; fillColor: emblem.shadow } }
            Art {
                Body { d: "M43 31 C43 19 48 10 60 5 L66 14 C59 17 56 23 57 31 Z"; fillColor: emblem.mono ? emblem.paper : "#7f9c4e"; strokeWidth: emblem.rim > 0 ? 2.5 : -1 }
                Body { d: pumpkinArt.d; fillColor: emblem.mono ? emblem.paper : "#ff8a2b" }
                Stroke { d: "M36 30 C20 45 20 75 37 89 M64 30 C80 45 80 75 63 89"; strokeColor: emblem.mono ? "transparent" : "#c95a12"; strokeWidth: 3 }
                Patch {
                    d: "M23 52 L33 39 L43 52 Z M57 52 L67 39 L77 52 Z M45 62 L50 54 L55 62 Z "
                        + "M22 63 L33 68 L40 63 L45 71 L55 71 L60 63 L67 68 L78 63 C73 79 62 84 55 83 L52 77 L47 83 C37 84 27 79 22 63 Z"
                    fillColor: emblem.ink
                }
            }
        }
    }
}
