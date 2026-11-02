import QtQuick
import QtQuick.Effects

// Clawd's singularity on one screen, a pure function of t (seconds since he froze): ClawdSingularity owns the window,
// the desktop capture and the clock. Storyboard: animations/SINGULARITY.md in the Clawd project.
// Layers: world = frozen desktop (desk.frag) + light (fx.frag) + Clawd (explode.png poses) + antimatter core + his debris,
// then lens.frag bends all of it (shake, negatives, black hole, star, blackout, return pulse).
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property Item desk: null       // the frozen desktop, any texture provider item
    property var pose: null        // his pose when he froze: {x, y, animation, frame, mirrored}, scene px
    property int pixel: 4          // his pixel when he froze (Clawd.scale)
    property bool side: false      // another screen: it only darkens, flashes and comes back

    readonly property var at: ({ freeze: 1.0, glide: 3.5, landed: 7.0, charge: 8.0, white: 15.5, dark: 15.8, still: 16.0, crossed: 17.9,
        crack: 18.7, blast: 19.0, hole: 22.6, fall: 23.4, star: 29.4, gone: 31.0, back: 36.0, end: 36.8 })
    readonly property real tau: t - at.blast   // time since the annihilation

    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }

    readonly property var frame: manifest ? manifest.frame : { w: 21, h: 14 }
    // his pixel grows to twice its size while he glides in: integer steps keep him crisp
    readonly property int pz: Math.round(pixel * (1 + smooth(at.glide, at.landed)))
    // body centre (frame cell 10.5, 9): from where he froze to the middle of the screen, on a slight arc, then hovering
    readonly property point start: pose ? Qt.point(pose.x + 10.5 * pixel, pose.y + 9 * pixel) : Qt.point(width / 2, height / 2)
    readonly property real glideK: { const k = seg(at.glide, at.landed); return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2; }
    readonly property real bob: t >= at.glide && t < at.still ? Math.sin((t - at.glide) * 2.1) * pixel * 0.75 * smooth(at.glide, at.glide + 1) : 0
    readonly property real cx: start.x + (width / 2 - start.x) * glideK
    readonly property real cy: start.y + (height / 2 - start.y) * glideK - Math.sin(Math.PI * glideK) * height * 0.06 + bob

    // tremble: harder and faster while he charges, dead still in the silence, one last convulsion as he cracks
    readonly property point shake: {
        let amp = 0, rate = 12;
        if (t >= 9 && t < at.still) { const k = smooth(9, at.dark); amp = pixel * (0.3 + 1.6 * k); rate = 14 + 34 * k; }
        else if (t >= at.crack && t < at.blast) { amp = pixel * 2; rate = 50; }
        if (!amp) return Qt.point(0, 0);
        const n = Math.floor(t * rate);
        return Qt.point(Math.round((hash(n) - 0.5) * 2 * amp), Math.round((hash(n + 71.3) - 0.5) * 2 * amp));
    }
    // explode.png: 0 hovering, 1-6 charging, 7 pure light, 8 crossed eyes, 9-11 cracking open; -1 = still the frozen pose
    readonly property int poseIndex: t < at.glide ? -1 : t < at.charge ? 0 : t < at.white ? 1 + Math.min(5, Math.floor((t - at.charge) / (at.white - at.charge) * 6))
        : t < at.crossed ? 7 : t < at.crack ? 8 : Math.min(11, 9 + Math.floor((t - at.crack) / (at.blast - at.crack) * 3))
    readonly property real glow: {
        if (t < 7.5 || t >= at.blast) return 0;
        if (t < at.still) return Math.pow(smooth(7.5, at.dark), 1.2);
        if (t < 18.5) return 0.88 + 0.12 * Math.sin((t - at.still) * 3.5);
        if (t < at.crack) return 1 - 0.55 * smooth(18.5, at.crack);  // he breathes in
        return 1.25;
    }
    readonly property real suck: t < 7.2 || t >= 15.95 ? 0 : smooth(7.2, 9.6) * (1 - smooth(15.5, 15.95))
    readonly property real flow: { const d = Math.max(0, t - 7.2), x = d / 8.6; return 0.06 * d + 0.5 * 8.6 * x * x * x / 3; }

    // the hole: grows with a slight overshoot, everything falls in, it collapses into a star that blinks out
    readonly property real holeR: {
        if (t < at.hole + 0.4 || t >= at.star + 0.6) return 0;
        const k = seg(at.hole + 0.4, at.hole + 2.0), back = 1 + 2.2 * Math.pow(k - 1, 3) + 1.2 * Math.pow(k - 1, 2);
        return height * 0.11 * back * (1 - smooth(at.star, at.star + 0.6));
    }
    readonly property real pull: Math.pow(seg(at.fall, at.star), 2.2)
    readonly property real star: {
        if (t < at.star + 0.1 || t >= at.gone) return 0;
        if (t < at.star + 0.5) return smooth(at.star + 0.1, at.star + 0.5);
        if (t < at.gone - 0.25) return 0.9 + 0.1 * Math.sin(t * 31);
        if (t < at.gone - 0.17) return 1.4;  // a last glint
        return 1.4 * (1 - smooth(at.gone - 0.17, at.gone));
    }

    visible: t >= at.freeze

    // ── another screen: darkness, the flash, the pulse ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: scene.side
        color: "black"
        opacity: scene.t < scene.at.back ? Math.max(scene.smooth(7.0, 15.8), scene.t >= scene.at.blast ? 1 : 0) : 1 - scene.smooth(scene.at.back + 0.05, scene.at.back + 0.3)
    }
    Rectangle {
        anchors.fill: parent
        visible: scene.side
        color: "white"
        opacity: scene.t >= scene.at.blast && scene.t < scene.at.blast + 1 ? 0.75 * Math.exp(-scene.tau * 5) : scene.t >= scene.at.back ? 0.5 * Math.exp(-(scene.t - scene.at.back - 0.05) * 7) * scene.seg(scene.at.back, scene.at.back + 0.05) : 0
    }

    // ── Clawd's screen ──────────────────────────────────────────────────────────────────────────────
    Item {
        id: world
        anchors.fill: parent
        visible: !scene.side

        ShaderEffectSource { id: deskTex; sourceItem: scene.desk; hideSource: true; visible: false }  // live: a new capture per blast

        ShaderEffect {
            anchors.fill: parent
            property var uDesk: deskTex
            property size uSize: Qt.size(width, height)
            property point uCenter: Qt.point(scene.cx, scene.cy)
            property real uTime: scene.t
            property real uFreeze: 1 - scene.seg(scene.at.freeze, scene.at.freeze + 0.25)
            property real uDrain: Math.pow(scene.smooth(7.0, scene.at.dark), 1.3)
            property real uPull: scene.t < scene.at.blast ? Math.pow(scene.smooth(8, 15.5), 1.5) : 0
            property real uLit: scene.t >= scene.at.blast ? 0.8 * scene.smooth(scene.at.blast + 0.03, scene.at.blast + 0.5) : 0
            property real uNeg: scene.tau < 0.05 ? 1 : Math.exp(-(scene.tau - 0.05) * 1.6)
            property real uFront: scene.height * 1.9 * (1 - Math.exp(-Math.max(0, scene.tau) * 1.5))
            fragmentShader: "shaders/desk.frag.qsb"
        }

        ShaderEffect {
            anchors.fill: parent
            visible: scene.suck > 0 || scene.glow > 0 || scene.tau >= 0
            property var uDesk: deskTex
            property size uSize: Qt.size(width, height)
            property point uCenter: Qt.point(scene.cx, scene.cy)
            property size uBody: Qt.size(8.5 * scene.pz, 5 * scene.pz)
            property real uPixel: scene.pixel
            property real uTime: scene.t
            property real uFlow: scene.flow
            property real uSuck: scene.suck
            property real uGlow: scene.glow
            property real uBlast: scene.tau >= 0 ? scene.tau : -1
            property real uStill: scene.t >= scene.at.still && scene.t < scene.at.blast ? 1 : 0
            fragmentShader: "shaders/fx.frag.qsb"
        }

        // Clawd: his frozen pose, then the singularity poses; a bloom of his own light around him
        Item {
            id: clawd
            readonly property var clip: scene.manifest && scene.pose ? scene.manifest.animations[scene.poseIndex < 0 ? scene.pose.animation : "explode"] : null
            visible: !!clip && scene.t < scene.at.blast
            x: Math.round(scene.cx - 10.5 * scene.pz) + scene.shake.x
            y: Math.round(scene.cy - 9 * scene.pz) + scene.shake.y
            width: scene.frame.w * scene.pz
            height: scene.frame.h * scene.pz
            layer.enabled: scene.glow > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(1, 0.93, 0.86, 1)
                shadowBlur: 1
                shadowScale: 1.04 + 0.08 * scene.glow
                shadowOpacity: Math.min(1, scene.glow * 1.1)
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 48
                brightness: 0.15 * Math.max(0, scene.glow - 1)
                autoPaddingEnabled: true
            }
            Image {
                anchors.fill: parent
                source: clawd.clip ? Qt.resolvedUrl("sprites/" + clawd.clip.file) : ""
                readonly property int index: scene.poseIndex >= 0 ? scene.poseIndex : clawd.clip ? Math.min(scene.pose.frame, clawd.clip.frames - 1) : 0
                sourceClipRect: clawd.clip ? Qt.rect(index * scene.frame.w, 0, scene.frame.w, scene.frame.h) : Qt.rect(0, 0, 0, 0)
                smooth: false
                mipmap: false
                transform: Scale { origin.x: clawd.width / 2; xScale: scene.poseIndex < 0 && scene.pose && scene.pose.mirrored ? -1 : 1 }
            }
        }

        // the annihilation core, drawn frame by frame (antimatter.png, 12 fps)
        Image {
            readonly property var strip: scene.manifest ? scene.manifest.antimatter : null
            readonly property int cell: Math.max(scene.pixel * 2, Math.floor(scene.height * 0.5 / 49))
            readonly property int drawing: Math.floor(scene.tau * 12)
            visible: !!strip && scene.tau >= 0 && drawing < strip.frames
            x: Math.round(scene.cx - width / 2)
            y: Math.round(scene.cy - height / 2)
            width: strip ? strip.w * cell : 0
            height: strip ? strip.h * cell : 0
            source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
            sourceClipRect: strip ? Qt.rect(Math.max(0, drawing) * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
            smooth: false
            mipmap: false
        }

        // his body, pixel by pixel: white-hot, cooling to his orange, a few violet; drifting until the hole takes them
        Repeater {
            model: scene.side ? [] : scene.debris
            delegate: Rectangle {
                required property var modelData
                readonly property real k: Math.max(0, scene.tau)
                readonly property real dist: modelData.speed * (1 - Math.exp(-modelData.drag * k)) / modelData.drag + k * 12
                visible: scene.tau >= 0.04
                width: modelData.big ? scene.pz : Math.max(2, scene.pz / 2)
                height: width
                x: Math.round(scene.cx + (modelData.cx + modelData.dx * dist) - width / 2)
                y: Math.round(scene.cy + (modelData.cy + modelData.dy * dist) - height / 2)
                color: modelData.violet ? "#8b5cff" : scene.tau < 0.18 ? "#ffffff" : scene.tau < 0.7 ? "#fcddc2" : "#d97757"
            }
        }
    }
    // his cells (frame cells, rows 4-13) flung from his centre, in px from it at his landed size
    readonly property var debris: {
        const out = [];
        const cells = [];
        for (let r = 4; r <= 11; r++) for (let c = 4; c <= 16; c++) cells.push([r, c]);
        for (const r of [8, 9]) for (const c of [2, 3, 17, 18]) cells.push([r, c]);
        for (const r of [12, 13]) for (const c of [4, 6, 14, 16]) cells.push([r, c]);
        const size = Math.round(pixel * 2);
        for (let i = 0; i < cells.length; i++) {
            const [r, c] = cells[i];
            const ox = (c + 0.5 - 10.5) * size, oy = (r + 0.5 - 9) * size;
            const a = Math.atan2(oy, ox) + (hash(i * 3.1) - 0.5) * 1.2;
            out.push({ cx: ox, cy: oy, dx: Math.cos(a), dy: Math.sin(a), speed: height * (0.5 + 1.6 * hash(i * 7.7)), drag: 1.1 + 1.6 * hash(i * 1.9),
                big: hash(i * 5.3) < 0.6, violet: hash(i * 9.1) < 0.14 });
        }
        return out;
    }

    ShaderEffectSource { id: worldTex; sourceItem: world; hideSource: true; live: true; visible: false }

    ShaderEffect {
        anchors.fill: parent
        visible: !scene.side
        property var uWorld: worldTex
        property size uSize: Qt.size(width, height)
        property point uCenter: Qt.point(scene.width / 2, scene.height / 2)
        property point uShake: {
            if (scene.tau < 0 || scene.tau > 4) return Qt.point(0, 0);
            const amp = 26 * Math.exp(-scene.tau * 2.4) + 3 * (1 - scene.seg(scene.at.blast + 1, scene.at.blast + 4)), n = Math.floor(scene.t * 40);
            return Qt.point((scene.hash(n) - 0.5) * 2 * amp, (scene.hash(n + 13.7) - 0.5) * 2 * amp);
        }
        property real uTime: scene.t
        property real uPixel: scene.pixel
        property real uChroma: scene.tau >= 0 ? 14 * Math.exp(-scene.tau * 1.8) : 0
        // impact frames: the world flips to its negative three times
        property real uInvert: [[0.04, 0.10], [0.16, 0.22], [0.30, 0.34]].some(w => scene.tau >= w[0] && scene.tau < w[1]) ? 1 : 0
        property real uFlash: scene.tau >= 0 && scene.tau < 0.04 ? 1 : scene.t >= scene.at.back + 0.04 ? 0.3 * Math.exp(-(scene.t - scene.at.back - 0.04) * 6) : 0
        property real uRipR: scene.height * 1.9 * (1 - Math.exp(-Math.max(0, scene.tau) * 1.5))
        property real uRipA: scene.tau >= 0 ? 18 * Math.exp(-scene.tau * 1.2) : 0
        property real uHole: scene.holeR
        property real uPull: scene.pull
        property real uSwirl: 0.5 * scene.smooth(scene.at.hole, scene.at.fall) + 9 * Math.pow(scene.seg(scene.at.fall, scene.at.star + 0.6), 1.6)
        property real uAccrete: scene.smooth(scene.at.hole + 0.5, scene.at.hole + 2) * (0.6 + 0.8 * scene.smooth(25, scene.at.star)) * (1 - scene.smooth(scene.at.star, scene.at.star + 0.6))
        property real uStar: scene.star
        property real uBlack: scene.t >= scene.at.gone ? 1 : 0
        property real uReveal: scene.t >= scene.at.back ? Math.hypot(scene.width, scene.height) * 0.55 * (1 - Math.pow(1 - scene.seg(scene.at.back, scene.at.back + 0.28), 3)) * 1.05 : -1
        fragmentShader: "shaders/lens.frag.qsb"
    }
}
