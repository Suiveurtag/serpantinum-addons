import QtQuick
import QtQuick.Effects
import "../"

// The dream "Rainbow surf": the max-effort helper of the surge (clone.png, clone.frag mode 2: Claude Code's light colours
// flowing through him) surfs a wave of rainbow tokens. A pure function of t (24 s), hosted by ClawdDream (iris, stars, vignette).
// 0-1.5 the iris opens from his head; 1.5-4 the wave rolls in from the left; 4-6 the surfer slides in; 6-14 carving;
// 14-17 the big swell, launch, two flips, landing; 17-21 shaka under the moon, shooting stars; 21-24 calm, fade.
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

    readonly property var at: ({ wave: 1.5, waveFull: 4.0, enter: 4.0, ride: 6.0, swell: 13.2, crouch: 14.0, launch: 14.5, tuck: 14.7,
        flips: 16.1, land: 16.3, settle: 16.8, shaka: 17.3, moon: 17.0, calm: 21.0, end: 24.0 })
    // the same light colours as ClawdSurge's max helper (a test keeps them equal)
    readonly property var rainbow: ["#FF9E7A", "#FFD966", "#8FE3A0", "#9BD3FF", "#C9B5FF", "#FF9CB0"]
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function smooth(a, b) { return ease(seg(a, b)); }
    function hash(n) { const s = Math.sin(n * 127.1 + scene.seed * 7.3) * 43758.5453; return s - Math.floor(s); }
    function colorAt(i) { return rainbow[((Math.floor(t * 6) + i) % 6 + 6) % 6]; }

    readonly property real sw: width
    readonly property real sh: height
    readonly property int fw: manifest ? manifest.frame.w : 21
    readonly property int fh: manifest ? manifest.frame.h : 14
    readonly property int ps: pixel * 3                 // the dream surfer is drawn three times his size
    readonly property real pw: fw * ps
    readonly property real ph: fh * ps
    readonly property string mono: typeof ThemeBackend !== "undefined" ? ThemeBackend.fontFamily : "monospace"

    // ── the wave ──────────────────────────────────────────────────────────────────────────────────
    readonly property real base: Math.min(floorY, sh) - sh * 0.2
    readonly property real amp: sh * 0.045 * smooth(at.wave, at.waveFull) * (1 - 0.5 * smooth(at.calm, at.end))
    readonly property real swellH: sh * 0.13 * smooth(at.swell, at.launch) * (1 - smooth(at.launch + 0.3, at.settle + 0.6))
    readonly property real reach: sw * 1.15 * smooth(at.wave, at.waveFull - 0.6)   // it rolls in from the left
    function waveAt(x, tt) {
        const k1 = 2 * Math.PI / (sw * 0.45), k2 = 2 * Math.PI / (sw * 0.21), sx = swellX;
        const swell = swellH * Math.exp(-Math.pow(x - sx, 2) / (2 * Math.pow(sw * 0.09, 2)));
        return base - amp * (0.6 * Math.sin(x * k1 - tt * 1.5) + 0.32 * Math.sin(x * k2 + tt * 0.85)) - swell;
    }
    function slopeAt(x) { return (waveAt(x + 6, t) - waveAt(x - 6, t)) / 12; }

    // ── the surfer: feet x, board y, pose (clone.png index), rotation ─────────────────────────────
    readonly property real swellX: sw * 0.42
    function surferX(tt) {
        if (tt < at.enter) return -pw;
        if (tt < at.ride) { const q = ease((tt - at.enter) / (at.ride - at.enter)); return -pw + (sw * 0.28 + pw) * q; }
        if (tt < at.swell) return sw * 0.28 + sw * 0.16 * Math.sin((tt - at.ride) * 0.62) + sw * 0.04 * Math.sin((tt - at.ride) * 1.7);
        const x0 = sw * 0.28 + sw * 0.16 * Math.sin((at.swell - at.ride) * 0.62) + sw * 0.04 * Math.sin((at.swell - at.ride) * 1.7);
        if (tt < at.launch) return x0 + (swellX - sw * 0.03 - x0) * ease((tt - at.swell) / (at.launch - at.swell));
        if (tt < at.land) return swellX - sw * 0.03 + sw * 0.17 * ((tt - at.launch) / (at.land - at.launch));
        return swellX + sw * 0.14 + (sw * 0.5 - swellX - sw * 0.14) * ease((tt - at.land) / (at.calm - at.land)) + sw * 0.05 * ease((tt - at.calm) / (at.end - at.calm));
    }
    function bodyAt(tt) {
        const x = surferX(tt), surface = waveAt(x, tt);
        if (tt >= at.launch && tt < at.land) {
            const q = (tt - at.launch) / (at.land - at.launch), x0 = swellX - sw * 0.03, x1 = swellX + sw * 0.14;
            const y0 = waveAt(x0, at.launch), y1 = waveAt(x1, at.land);
            const flip = ease((tt - at.tuck) / (at.flips - at.tuck)) * 720;
            const m = ((flip % 360) + 360) % 360;
            const pose = tt < at.tuck ? 45 : tt >= at.flips ? 45 : m > 120 && m < 240 ? 47 : 46;
            return { x, y: y0 + (y1 - y0) * q - sh * 0.26 * Math.sin(Math.PI * q), pose, rot: flip };
        }
        const sl = slopeAt(x), deg = Math.max(-30, Math.min(30, Math.atan(sl) * 180 / Math.PI));
        const rot = Math.round(deg / 7.5) * 7.5;
        let pose = 38;
        if (tt < at.ride) pose = Math.floor(tt * 2) % 2 ? 42 : 43;
        else if (tt < at.swell) pose = sl < -0.12 ? 41 : sl > 0.12 ? 40 : [38, 42, 38, 43, 39][Math.floor(tt * 1.6) % 5];
        else if (tt < at.crouch) pose = 39;
        else if (tt < at.launch) pose = 44;
        else if (tt < at.settle) pose = 48;
        else if (tt < at.shaka) pose = 38;
        else if (tt < at.calm) pose = 49;
        else pose = Math.floor(tt * 1.2) % 2 ? 42 : 43;
        const bob = tt >= at.ride ? Math.sin(tt * 5.2) * pixel * 0.6 : 0;
        return { x, y: surface + bob, pose, rot };
    }
    readonly property var me: bodyAt(t)
    readonly property bool airborne: t >= at.launch && t < at.land

    // ── sky: the moon and shooting stars (the host draws the stars and the vignette) ──────────────
    Text {
        text: "☾"
        x: scene.sw * 0.78; y: scene.sh * 0.08
        opacity: scene.smooth(scene.at.moon, scene.at.moon + 1.5) * (1 - scene.smooth(scene.at.end - 1.5, scene.at.end))
        color: "#FFF4D6"
        font.pixelSize: Math.round(scene.sh * 0.12)
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#FFE9B0"; shadowBlur: 1; shadowOpacity: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 48; autoPaddingEnabled: true }
    }
    Repeater {
        model: [17.6, 18.7, 19.9, 22.0]
        delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property real k: scene.seg(modelData, modelData + 0.7)
            visible: k > 0 && k < 1
            width: scene.sw * 0.12; height: Math.max(2, scene.pixel / 2)
            radius: height / 2
            x: scene.sw * (0.25 + 0.17 * index) + scene.sw * 0.25 * k - width
            y: scene.sh * (0.06 + 0.05 * (index % 2)) + scene.sh * 0.12 * k
            rotation: 25
            opacity: Math.sin(Math.PI * k)
            gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "#FFFFFF" } }
        }
    }

    // ── the wave: columns of rainbow tokens, a few rows deep, fading downwards ─────────────────────
    Repeater {
        model: 64 * 5
        delegate: Rectangle {
            required property int index
            readonly property int col: index % 64
            readonly property int row: Math.floor(index / 64)
            readonly property real cx: (col + 0.5) * scene.sw / 64
            readonly property real chip: Math.max(4, scene.sw / 64 - 3)
            visible: cx < scene.reach && scene.amp > 0.5
            width: chip; height: chip * 0.62
            radius: height * 0.35
            x: cx - width / 2
            y: scene.waveAt(cx, scene.t) + row * height * 1.25
            color: scene.colorAt(col + row)
            opacity: (1 - row * 0.18) * (cx > scene.reach - scene.sw * 0.08 ? (scene.reach - cx) / (scene.sw * 0.08) : 1)
        }
    }
    // foam: tokens sprayed off the crest behind the board
    Repeater {
        model: 28
        delegate: Rectangle {
            required property int index
            readonly property real ph: (scene.t * 1.4 + index / 28) % 1
            readonly property real fx: scene.me.x - scene.pw * 0.3 - ph * scene.pw * (1.2 + scene.hash(index) * 0.8)
            visible: scene.t > scene.at.enter + 0.5 && scene.t < scene.at.end - 1 && !scene.airborne
            width: scene.pixel * (1 + Math.round(scene.hash(index + 3) * 1.5)); height: width
            x: fx
            y: scene.waveAt(fx, scene.t) - Math.sin(Math.PI * ph) * scene.ph * (0.25 + scene.hash(index + 9) * 0.35)
            color: index % 3 ? "#FFFFFF" : scene.colorAt(index)
            opacity: (1 - ph) * 0.9
        }
    }

    // ── the surfer (and his afterimages in the air) ───────────────────────────────────────────────
    component Surfer: Item {
        id: s
        property real tt: scene.t
        property bool glow: true
        readonly property var b: scene.bodyAt(tt)
        readonly property var clip: scene.manifest ? scene.manifest.clone : null
        width: scene.pw; height: scene.ph
        x: b.x - width / 2
        y: b.y - height
        transformOrigin: Item.Center
        rotation: b.rot
        layer.enabled: glow
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: scene.colorAt(2); shadowBlur: 1; shadowScale: 1.05; shadowOpacity: 0.85
            shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 32; autoPaddingEnabled: true
        }
        Item {
            anchors.fill: parent
            Image {
                anchors.fill: parent
                source: s.clip ? Qt.resolvedUrl("sprites/" + s.clip.file) : ""
                sourceClipRect: s.clip ? Qt.rect(Math.min(s.b.pose, s.clip.frames - 1) * s.clip.w, 0, s.clip.w, s.clip.h) : Qt.rect(0, 0, 0, 0)
                smooth: false
            }
            layer.enabled: true
            layer.smooth: false
            layer.effect: ShaderEffect {
                property color uColor: "#FFB38A"
                property real uMode: 2
                property real uTime: scene.t
                property real uReveal: 1
                property size uGrid: Qt.size(scene.fw, scene.fh)
                fragmentShader: "shaders/clone.frag.qsb"
            }
        }
    }
    Repeater {
        model: 3
        delegate: Surfer {
            required property int index
            tt: scene.t - 0.07 * (index + 1)
            glow: false
            visible: scene.airborne && !scene.reduced
            opacity: 0.32 - index * 0.09
        }
    }
    Surfer { visible: scene.t >= scene.at.enter }

    // "+4.2k tok" pops while he flies
    Repeater {
        model: [14.8, 15.3, 15.8]
        delegate: Text {
            required property var modelData
            required property int index
            readonly property real k: scene.seg(modelData, modelData + 1.1)
            visible: k > 0 && k < 1
            text: ["+4.2k tok", "+12k tok", "+∞ tok"][index]
            x: scene.me.x + (index - 1) * scene.pw * 0.7 - width / 2
            y: scene.me.y - scene.ph * 1.4 - k * scene.ph
            color: scene.colorAt(index * 2)
            opacity: 1 - k
            font.family: scene.mono; font.bold: true; font.pixelSize: Math.round(scene.pixel * 4)
        }
    }
}
