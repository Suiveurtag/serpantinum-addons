import QtQuick
import "../"

// The nightmare "Ouroboros": a serpent biting its own tail, turning for ever. A pure function of t (13.5 s), hosted by
// ClawdDream (black-red vignette, flicker, grain). Everything is drawn in whole-pixel squares, no shader of its own.
// 0-1.5 dark, a faint ring of ember dots; 1.5-4 the serpent draws itself round the ring, head chasing tail;
// 4 it bites: the ring is closed and turns; 5.5-10 the zoom: ring inside ring inside ring, each turning against the next,
// never ending (the rings repeat at every scale); 9.5-12.8 the figure eight "∞" overlays it, the heartbeat quickens, black
// stutter frames; 12.8 the jumpscare: the head slams to fill the screen, red-white flash (the overlay makes him jolt awake);
// 12.8-13.5 the flash dies, black.
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property int pixel: 4
    property real ox: 0
    property real oy: 0
    property real floorY: height
    property real seed: 0
    property bool reduced: false

    readonly property var at: ({ dots: 0.4, draw: 1.5, bite: 4.0, spin: 4.2, zoom: 5.5, eyes: 4.0, lemn: 9.5, stutter: 10.4, jump: 12.8, slam: 12.92, black: 13.15, end: 13.5 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function smooth(a, b) { return ease(seg(a, b)); }
    function hash(n) { const s = Math.sin(n * 127.1 + scene.seed * 5.7) * 43758.5453; return s - Math.floor(s); }
    function snap(v) { return Math.round(v / pixel) * pixel; }

    readonly property real sw: width
    readonly property real sh: height
    readonly property real cx: sw / 2
    readonly property real cy: sh / 2
    readonly property int frame: Math.floor(t * 24)
    readonly property int rings: 7
    readonly property int count: 64                       // segments per ring
    readonly property real q: 0.56                        // each ring is q times the size of the one around it
    readonly property real r0: Math.min(sw, sh) * 0.34
    readonly property string mono: typeof ThemeBackend !== "undefined" ? ThemeBackend.fontFamily : "monospace"

    // the heartbeat, from the bite on: a double thump, quicker and quicker
    readonly property real beat: {
        if (t < at.bite || t >= at.jump) return 0;
        const period = 0.9 - 0.4 * smooth(at.zoom, at.jump), p = ((t - at.bite) % period) / period;
        return Math.exp(-Math.pow((p - 0.05) / 0.04, 2)) + 0.6 * Math.exp(-Math.pow((p - 0.2) / 0.04, 2));
    }
    readonly property bool cut: t >= at.stutter && t < at.jump && hash(Math.floor(t * 8)) < 0.3   // a black frame
    readonly property real drawn: smooth(at.draw, at.bite)
    readonly property real tz: Math.max(0, t - at.zoom)
    readonly property real zpos: Math.min(tz, at.jump - at.zoom) * 0.15 + 0.06 * Math.pow(Math.min(tz, at.jump - at.zoom), 2)   // rings per second grows
    readonly property int zi: Math.floor(zpos)
    readonly property real zfrac: zpos - zi
    readonly property real tspin: Math.max(0, Math.min(t, at.jump) - at.spin)
    readonly property real spinA: 0.35 * tspin + 0.06 * tspin * tspin                // radians, the turn is accelerating
    readonly property real shake: reduced ? 0 : t >= at.jump ? sh * 0.05 * (1 - seg(at.jump, at.end)) : t >= at.zoom ? pixel * 0.5 * seg(at.zoom, at.jump) + beat * pixel * 0.8 : 0
    readonly property real flash: t >= at.jump ? 1 - seg(at.jump, at.black) : 0
    readonly property real dark: smooth(0, 1.0) * 0.9

    Rectangle { anchors.fill: parent; color: "#050003"; opacity: scene.dark }

    Item {
        id: world
        anchors.fill: parent
        x: (scene.hash(scene.frame) - 0.5) * 2 * scene.shake
        y: (scene.hash(scene.frame + 51) - 0.5) * 2 * scene.shake
        visible: !scene.cut && scene.t < scene.at.black + 0.1

        // the first, faint ring: a circle of ember dots the serpent will fill
        Repeater {
            model: 48
            delegate: Rectangle {
                required property int index
                readonly property real a: index / 48 * 2 * Math.PI
                visible: scene.t >= scene.at.dots && scene.t < scene.at.bite + 0.5
                width: scene.pixel; height: scene.pixel
                x: scene.snap(scene.cx + scene.r0 * Math.cos(a)); y: scene.snap(scene.cy + scene.r0 * Math.sin(a))
                color: "#7a2418"
                opacity: (0.25 + 0.35 * scene.hash(scene.frame + index)) * scene.smooth(scene.at.dots, scene.at.draw) * (1 - scene.smooth(scene.at.draw, scene.at.bite + 0.5))
            }
        }

        // the serpents: ring k is the (k + zi)th of an endless nest; the nest slides inwards as the zoom goes
        Repeater {
            model: scene.rings
            delegate: Item {
                id: ring
                required property int index
                readonly property int j: index + scene.zi                          // the ring's own number, kept as the nest slides
                readonly property real s: Math.pow(scene.q, index - scene.zfrac)    // its size as part of the first ring
                readonly property real r: scene.r0 * s * (1 + 0.025 * scene.beat)
                readonly property real base: r * 0.13                               // the body at its thickest
                readonly property real dir: j % 2 ? -1 : 1
                readonly property real turn: dir * scene.spinA * (1 + 0.15 * (j % 5)) - Math.PI / 2
                readonly property real span: 2 * Math.PI * 0.965 * (first ? scene.drawn : 1)
                readonly property real fadeIn: scene.clamp01((s - 0.025) / 0.06) * scene.clamp01((1.9 - s) / 0.6)
                readonly property bool first: index === 0 && scene.zi === 0       // the one ring the serpent draws
                readonly property bool shown: fadeIn > 0 && (first ? scene.t >= scene.at.draw : scene.t >= scene.at.zoom - 0.8)
                readonly property real alpha: fadeIn * (first ? 1 : scene.smooth(scene.at.zoom - 0.8, scene.at.zoom + 0.4))
                readonly property real headA: turn + span
                readonly property real hs: Math.max(scene.pixel, scene.snap(base * 1.7))
                visible: shown && base >= scene.pixel * 0.5
                opacity: alpha
                anchors.fill: parent

                Repeater {
                    model: scene.count
                    delegate: Rectangle {
                        required property int index
                        readonly property real f: index / (scene.count - 1)
                        readonly property real a: ring.turn + f * ring.span
                        readonly property real w: Math.max(scene.pixel, scene.snap(ring.base * (0.3 + 0.7 * Math.pow(f, 0.7))))
                        visible: f <= (ring.span / (2 * Math.PI * 0.965)) + 0.0001
                        width: w; height: w
                        x: scene.snap(scene.cx + ring.r * Math.cos(a) - w / 2); y: scene.snap(scene.cy + ring.r * Math.sin(a) - w / 2)
                        color: index === 0 ? "#b8ad92" : (index % 6 < 3) ? "#3f5240" : "#2b3a2d"
                        Rectangle {          // a pale belly scale on the inner side of the body
                            visible: index % 3 === 0 && parent.w >= scene.pixel * 2
                            width: scene.pixel; height: scene.pixel
                            x: (parent.width - width) / 2 - Math.cos(parent.a) * parent.w * 0.28
                            y: (parent.height - height) / 2 - Math.sin(parent.a) * parent.w * 0.28
                            color: "#8d9a78"; opacity: 0.55
                        }
                    }
                }

                // the head, at the far end of the body, its jaws shut on the tail
                Item {
                    id: head
                    visible: ring.span > 0.2
                    readonly property real ca: Math.cos(ring.headA)
                    readonly property real sa: Math.sin(ring.headA)
                    x: ring.r * ca + scene.cx; y: ring.r * sa + scene.cy
                    Rectangle {
                        width: ring.hs; height: ring.hs
                        x: scene.snap(head.x - width / 2) - head.x; y: scene.snap(head.y - height / 2) - head.y
                        color: "#516650"
                    }
                    Rectangle {              // the open mouth, forward along the ring: the tail goes in
                        width: Math.max(scene.pixel, scene.snap(ring.hs * 0.55)); height: width
                        x: scene.snap(head.x - head.sa * ring.hs * 0.55 - width / 2) - head.x
                        y: scene.snap(head.y + head.ca * ring.hs * 0.55 - height / 2) - head.y
                        color: "#12000a"
                    }
                    Repeater {               // two eyes, red, on the outer and inner side of the head
                        model: 2
                        delegate: Rectangle {
                            required property int index
                            readonly property real sgn: index ? 1 : -1
                            width: Math.max(scene.pixel, scene.snap(ring.hs * 0.22)); height: width
                            x: scene.snap(head.x + head.ca * sgn * ring.hs * 0.28 - width / 2) - head.x
                            y: scene.snap(head.y + head.sa * sgn * ring.hs * 0.28 - height / 2) - head.y
                            color: "#E0101A"
                            opacity: scene.t >= scene.at.eyes ? (0.7 + 0.3 * scene.beat) * (scene.t < scene.at.jump ? scene.smooth(scene.at.eyes, scene.at.eyes + 1.0) : 1) : 0
                        }
                    }
                }
            }
        }

        // from 9.5: the figure eight, the other symbol of the endless, drawn in dots that run along it
        Repeater {
            model: 90
            delegate: Rectangle {
                required property int index
                readonly property real u: index / 90 * 2 * Math.PI + scene.t * 1.4
                readonly property real den: 1 + Math.pow(Math.sin(u), 2)
                readonly property real big: scene.r0 * 1.45
                visible: scene.t >= scene.at.lemn && scene.t < scene.at.jump
                width: scene.pixel * (index % 5 === 0 ? 3 : 2); height: width
                x: scene.snap(scene.cx + big * Math.cos(u) / den - width / 2)
                y: scene.snap(scene.cy + big * 0.8 * Math.sin(u) * Math.cos(u) / den - height / 2)
                color: index % 5 === 0 ? "#E0101A" : "#b8ad92"
                opacity: scene.smooth(scene.at.lemn, scene.at.lemn + 1.2) * (0.3 + 0.5 * scene.hash(scene.frame + index))
            }
        }
        Text {
            visible: scene.t >= scene.at.stutter && scene.t < scene.at.jump && scene.hash(scene.frame + 7) > 0.4
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: (scene.hash(scene.frame + 3) - 0.5) * scene.pixel * 6
            text: "∞"
            color: "#C0141C"
            opacity: 0.25 + 0.4 * scene.hash(scene.frame + 11)
            font.family: scene.mono
            font.pixelSize: Math.round(scene.sh * (0.5 + 0.5 * scene.seg(scene.at.stutter, scene.at.jump)))
        }
    }

    // the jumpscare: the head slams to fill the screen
    Item {
        id: slam
        visible: scene.t >= scene.at.jump && scene.t < scene.at.black + 0.15
        readonly property real k: 0.35 + 0.95 * scene.ease(scene.seg(scene.at.jump, scene.at.slam))
        readonly property real hh: scene.sh * k
        width: hh * 1.4; height: hh
        x: (scene.sw - width) / 2 + (scene.hash(scene.frame) - 0.5) * scene.shake * 2
        y: (scene.sh - height) / 2 + (scene.hash(scene.frame + 51) - 0.5) * scene.shake * 2
        Rectangle { anchors.fill: parent; color: "#516650" }
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.height * 0.12; color: "#2b3a2d" }
        Rectangle {      // the open mouth
            x: parent.width * 0.16; y: parent.height * 0.52; width: parent.width * 0.68; height: parent.height * 0.38; color: "#12000a"
        }
        Repeater {       // fangs
            model: 6
            delegate: Rectangle {
                required property int index
                width: slam.width * 0.045; height: slam.height * (index === 1 || index === 4 ? 0.2 : 0.12)
                x: slam.width * (0.22 + index * 0.1); y: slam.height * 0.52
                color: "#F2EBD8"
            }
        }
        Repeater {       // the eyes
            model: 2
            delegate: Rectangle {
                required property int index
                x: slam.width * (index ? 0.64 : 0.14); y: slam.height * 0.22; width: slam.width * 0.22; height: slam.height * 0.12
                color: "#E0101A"
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.12; height: parent.height * 1.4; color: "#050003" }
            }
        }
    }

    Rectangle { anchors.fill: parent; color: scene.t < scene.at.jump + 0.05 ? "#FFF2F0" : "#E0101A"; opacity: scene.flash * (scene.reduced ? 0.6 : 0.85) }
    Rectangle { anchors.fill: parent; color: "black"; opacity: scene.smooth(scene.at.black, scene.at.end) }
}
