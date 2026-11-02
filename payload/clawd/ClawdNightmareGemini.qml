import QtQuick
import "../"

// The nightmare "Gemini": her drawing (sprites/gemini.png) as a sheet of paper in the dark, made evil by evil.frag
// (glitch slices, RGB split, red eyes, flicker). A pure function of t (11.7 s), hosted by ClawdDream (black-red vignette).
// 0-1.5 cold dark, static, a tiny far sheet; 1.5-4 the slices begin, a ghost "flash" caption; 4-9 a slow zoom on a
// heartbeat, her eyes light up; 9-11 stutter cuts, black frames, invert flashes; 11.0 the jumpscare: she slams to fill the
// screen, red-white flash, the big shake (the overlay makes him jolt awake); 11.0-11.7 the flash dies, black.
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

    readonly property var at: ({ slices: 1.5, zoom: 4.0, eyes: 4.5, stutter: 9.0, jump: 11.0, slam: 11.12, black: 11.35, end: 11.7 })
    readonly property var eyeL: Qt.point(0.311, 0.298)      // her eyes in gemini.png, uv
    readonly property var eyeR: Qt.point(0.622, 0.302)
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function smooth(a, b) { return ease(seg(a, b)); }
    function hash(n) { const s = Math.sin(n * 127.1 + scene.seed * 3.1) * 43758.5453; return s - Math.floor(s); }

    readonly property real sw: width
    readonly property real sh: height
    readonly property var pic: manifest ? manifest.gemini : null
    readonly property real aspect: pic ? pic.w / pic.h : 0.537
    readonly property int frame: Math.floor(t * 24)
    // the heartbeat: a double thump every 0.9 s from the zoom on
    readonly property real beat: { if (t < at.zoom || t >= at.jump) return 0; const p = ((t - at.zoom) % 0.9) / 0.9; return Math.exp(-Math.pow((p - 0.05) / 0.04, 2)) + 0.6 * Math.exp(-Math.pow((p - 0.2) / 0.04, 2)); }
    readonly property bool cut: t >= at.stutter && t < at.jump && hash(Math.floor(t * 8)) < 0.35   // a black frame
    // the sheet's height, as a part of the screen
    readonly property real size: {
        if (t < at.slices) return 0.16;
        if (t < at.zoom) return 0.16 + 0.08 * smooth(at.slices, at.zoom);
        if (t < at.stutter) return 0.24 + 0.36 * ease(seg(at.zoom, at.stutter)) + 0.025 * beat;
        if (t < at.jump) return 0.6 + 0.25 * Math.floor(seg(at.stutter, at.jump) * 8) / 8;
        return 0.85 + 1.0 * ease(seg(at.jump, at.slam));
    }
    readonly property real shake: reduced ? 0 : t >= at.jump ? sh * 0.05 * (1 - seg(at.jump, at.end)) : t >= at.zoom ? pixel * 0.6 * seg(at.zoom, at.jump) + beat * pixel : 0
    readonly property real flash: t >= at.jump ? 1 - seg(at.jump, at.black) : 0
    readonly property real dark: smooth(0, 1.2) * 0.82

    // the cold dark room
    Rectangle { anchors.fill: parent; color: "#070002"; opacity: scene.dark }
    // static: thin grey bars jumping every frame
    Repeater {
        model: 26
        delegate: Rectangle {
            required property int index
            readonly property real h: scene.hash(index * 13 + scene.frame)
            visible: !scene.reduced && scene.t < scene.at.jump
            x: 0; width: scene.sw
            y: scene.sh * scene.hash(index * 7 + scene.frame * 3)
            height: 1 + Math.round(h * 2)
            color: h > 0.5 ? "#8a7f80" : "#3a2226"
            opacity: (0.05 + 0.12 * h) * (1 - 0.5 * scene.seg(scene.at.zoom, scene.at.stutter))
        }
    }

    Item {
        id: sheet
        readonly property real hh: scene.sh * scene.size
        visible: !!scene.pic && !scene.cut && scene.t < scene.at.black + 0.15
        width: hh * scene.aspect; height: hh
        x: (scene.sw - width) / 2 + (scene.hash(scene.frame) - 0.5) * 2 * scene.shake
        y: (scene.sh - height) / 2 + (scene.hash(scene.frame + 51) - 0.5) * 2 * scene.shake + (scene.t < scene.at.jump ? scene.sh * 0.04 : 0)
        rotation: scene.reduced ? 0 : (scene.hash(Math.floor(scene.t * 6)) - 0.5) * 6 * scene.seg(scene.at.zoom, scene.at.jump)
        opacity: scene.t < scene.at.slices ? 0.55 + 0.25 * scene.hash(scene.frame) : 1
        Image {
            id: drawing
            anchors.fill: parent
            visible: false
            source: scene.pic ? Qt.resolvedUrl("sprites/" + scene.pic.file) : ""
            smooth: true
            mipmap: true
        }
        ShaderEffect {
            anchors.fill: parent
            property variant source: drawing
            property real uTime: scene.t
            property real uIntensity: 0.25 + 0.75 * scene.seg(scene.at.slices, scene.at.stutter)
            property real uSlice: scene.t < scene.at.slices ? 0 : scene.t >= scene.at.jump ? 1 : 0.25 + 0.55 * scene.seg(scene.at.zoom, scene.at.jump)
            property real uAberr: scene.t >= scene.at.jump ? 0.04 : 0.003 + 0.022 * scene.seg(scene.at.slices, scene.at.jump)
            property real uEyes: scene.t >= scene.at.jump ? 1 : scene.smooth(scene.at.eyes, scene.at.stutter) * (0.85 + 0.15 * scene.beat)
            property point uEyeL: scene.eyeL
            property point uEyeR: scene.eyeR
            property real uFlicker: scene.reduced ? 0 : 0.3 + 0.7 * scene.seg(scene.at.slices, scene.at.stutter)
            property real uInvert: scene.t >= scene.at.jump ? (scene.t < scene.at.jump + 0.06 ? 1 : 0)
                : scene.t >= scene.at.stutter && scene.hash(Math.floor(scene.t * 8) + 99) > 0.8 ? 1 : 0
            fragmentShader: "shaders/evil.frag.qsb"
        }
    }

    // the ghost of her caption, flickering beside the sheet
    Text {
        visible: scene.t >= scene.at.slices && scene.t < scene.at.stutter && scene.hash(scene.frame + 7) > 0.45
        text: "gemini"
        x: sheet.x + sheet.width * 0.25 + (scene.hash(scene.frame + 3) - 0.5) * scene.pixel * 4
        y: sheet.y - height - scene.pixel * 2
        color: "#C0141C"
        opacity: 0.35 + 0.4 * scene.hash(scene.frame + 11)
        font.family: typeof ThemeBackend !== "undefined" ? ThemeBackend.fontFamily : "monospace"
        font.pixelSize: Math.round(sheet.height * 0.09)
        font.italic: true
    }

    // the jumpscare: red-white flash, then black
    Rectangle { anchors.fill: parent; color: scene.t < scene.at.jump + 0.05 ? "#FFF2F0" : "#E0101A"; opacity: scene.flash * (scene.reduced ? 0.6 : 0.85) }
    Rectangle { anchors.fill: parent; color: "black"; opacity: scene.smooth(scene.at.black, scene.at.end) }
}
