import QtQuick
import QtQuick.Effects

// Clawd's nuclear variant on one screen, a pure function of t (seconds since he froze): ClawdSingularity owns the window,
// the desktop capture and the clock. Storyboard: animations/NUKE.md in the Clawd project.
// Layers: world = frozen desktop (nuke.frag) + Clawd (nuke.png poses) + the mushroom (mushroom.png, frame by frame) + embers
// and ash, then lens.frag shakes, splits and flashes all of it. It fades out over the live desktop, where his corpse lands.
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property Item desk: null       // the frozen desktop, any texture provider item
    property var pose: null        // his pose when he froze: {x, y, animation, frame, mirrored}, scene px
    property int pixel: 4          // his pixel when he froze (Clawd.scale)
    property real floor: height    // his floor, scene px
    property bool side: false      // another screen: alarm, flash and the glow of the fire only

    readonly property var at: ({ freeze: 0.3, panic: 0.9, terror: 5.2, crouch: 5.6, jump: 5.85, slow: 6.15, crossed: 9.0, glint: 9.45,
        impact: 9.75, blast: 10.15, fade: 18.6, back: 19.4, end: 19.9 })
    readonly property real tau: t - at.blast   // time since the detonation

    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }

    readonly property var frame: manifest ? manifest.frame : { w: 21, h: 14 }
    readonly property real fw: frame.w * pixel
    readonly property real fh: frame.h * pixel
    // where he started (his frame's bottom centre) and the floor he panics on
    readonly property point start: pose ? Qt.point(pose.x + fw / 2, pose.y + fh) : Qt.point(width / 2, floor)

    // The panic: runs back and forth at full tilt, freezes in terror once, ends near the middle where he jumps.
    // [x from, x to, seconds, kind] scaled to fill panic..terror.
    readonly property var legs: {
        const m = fw, w = width, fit = v => Math.max(m, Math.min(w - m, v));
        const go = start.x < w / 2 ? 1 : -1;
        const xs = [start.x];
        xs.push(fit(xs[0] + go * w * 0.3));
        xs.push(fit(xs[1] - go * w * 0.45));
        xs.push(xs[2]);                               // frozen in terror
        xs.push(fit(xs[3] + go * w * 0.22));
        xs.push(fit(xs[4] - go * w * 0.3));
        xs.push(fit(w / 2 + (hash(start.x) - 0.5) * w * 0.2));
        const out = [];
        let total = 0;
        for (let i = 1; i < xs.length; i++) {
            const terror = i === 3, d = terror ? 0.4 * 950 : Math.max(90, Math.abs(xs[i] - xs[i - 1]));
            out.push({ a: xs[i - 1], b: xs[i], d, terror, hop: i === 4 });
            total += d;
        }
        const span = at.terror - at.panic;
        let t0 = at.panic;
        for (const l of out) { l.t0 = t0; l.t1 = t0 + l.d / total * span; t0 = l.t1; }
        return out;
    }
    readonly property real groundX: legs.length ? legs[legs.length - 1].b : start.x

    // his feet (bottom centre), the pose (nuke.png index) and which way he faces
    readonly property var body: {
        if (t < at.panic) {
            // startled: he leaps out of his skin, landing on the floor (from wherever he was)
            const k = seg(at.freeze, at.panic);
            return { x: start.x, y: start.y + (floor - start.y) * k - Math.sin(Math.PI * k) * fh * 0.6, pose: 0, flip: false };
        }
        if (t < at.terror) {
            const l = legs.find(g => t < g.t1) || legs[legs.length - 1];
            const k = clamp01((t - l.t0) / (l.t1 - l.t0)), e = 0.25 * k + 0.75 * k * k * (3 - 2 * k);
            if (l.terror) return { x: l.a + (Math.floor(t * 30) % 2 ? pixel * 0.5 : -pixel * 0.5), y: floor, pose: 5, flip: false };
            return { x: l.a + (l.b - l.a) * e, y: floor - (l.hop ? Math.sin(Math.PI * k) * fh * 0.5 : 0), pose: 1 + Math.floor(t * 16) % 4, flip: l.b < l.a };
        }
        const gx = groundX;
        if (t < at.crouch) return { x: gx + (Math.floor(t * 34) % 2 ? pixel * 0.5 : -pixel * 0.5), y: floor, pose: 5, flip: false };
        if (t < at.jump) return { x: gx, y: floor, pose: 6, flip: false };
        // the leap: fast off the ground, then time dilates and he hangs there, barely rising
        const k = seg(at.jump, at.slow), up = fh * 1.6 * (0.82 * (1 - Math.pow(1 - k, 2)) + 0.18 * smooth(at.slow, at.impact));
        const pose = t < at.slow ? 7 : t < at.crossed ? 8 : t < at.glint ? 9 : t < at.impact ? 10
            : Math.floor((t - at.impact) / 0.1) % 2 ? 12 : 11;
        return { x: gx, y: floor - up, pose, flip: false };
    }
    readonly property point center: Qt.point(body.x, body.y - fh * 0.4)
    readonly property int impactFrame: t >= at.impact && t < at.blast ? 1 + Math.floor((t - at.impact) / 0.1) % 2 : 0

    // the cloud: its cell size, its frame (fast while it forms, slower as it climbs), its fireball and its heat
    readonly property var cloud: manifest ? manifest.mushroom : null
    readonly property int cell: Math.max(pixel * 2, Math.floor(height * 0.82 / 96))
    readonly property int cloudFrame: cloud ? Math.min(cloud.frames - 1, Math.floor(cloud.frames * Math.pow(clamp01(tau / 8.4), 0.62))) : 0
    readonly property real rise: { const s = cloudFrame / 27; return 1 - Math.pow(1 - s, 2.4); }
    readonly property point fireC: Qt.point(groundX, floor - (5 + 57 * rise) * cell)
    readonly property real fire: tau < 0 ? 0 : tau < 0.12 ? 2.4 : 0.35 + 2.05 * Math.exp(-(tau - 0.12) * 0.45)
    readonly property real burn: tau < 0 ? 0 : smooth(at.blast, at.blast + 0.6) * (1 - smooth(16.5, at.back))
    readonly property real fadeOut: 1 - smooth(at.fade, at.back)

    visible: t >= at.freeze

    // ── another screen: the alarm, the flash, the glow of the fire ─────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: scene.side
        color: "#c41a1a"
        opacity: scene.t < scene.at.slow ? 0.12 * (0.5 + 0.5 * Math.sin(scene.t * 13)) * scene.smooth(scene.at.freeze, 1.5) : 0
    }
    Rectangle {
        anchors.fill: parent
        visible: scene.side
        color: "black"
        opacity: scene.t >= scene.at.slow && scene.t < scene.at.blast ? 0.45 * scene.smooth(scene.at.slow, 7) : 0
    }
    Rectangle {
        anchors.fill: parent
        visible: scene.side && scene.tau >= 0
        color: scene.tau < 0.5 ? "white" : "#ff7a2a"
        opacity: scene.tau < 0.5 ? 0.85 * Math.exp(-scene.tau * 4) : 0.22 * scene.burn
    }

    // ── his screen ─────────────────────────────────────────────────────────────────────────────────
    Item {
        id: world
        anchors.fill: parent
        visible: !scene.side

        ShaderEffectSource { id: deskTex; sourceItem: scene.desk; hideSource: true; visible: false }

        ShaderEffect {
            anchors.fill: parent
            property var uDesk: deskTex
            property size uSize: Qt.size(width, height)
            property point uClawd: scene.center
            property point uFireC: scene.fireC
            property point uGround: Qt.point(scene.groundX, scene.floor)
            property real uTime: scene.t
            property real uAlarm: scene.t < scene.at.slow ? scene.smooth(scene.at.freeze, 1.6) * (1 - scene.smooth(scene.at.jump, scene.at.slow)) : 0
            property real uSlow: scene.tau < 0 ? scene.smooth(scene.at.jump, scene.at.slow + 0.5) : 0
            property real uPush: scene.tau < 0 ? scene.smooth(scene.at.slow, scene.at.glint) - 0.4 * scene.smooth(scene.at.glint, scene.at.impact) : 0
            // two heartbeats in the silence, the second fainter
            property real uBeat: [7.1, 8.1].reduce((v, b, i) => Math.max(v, (1 - 0.35 * i) * Math.exp(-Math.pow((scene.t - b) / 0.09, 2)) + 0.6 * (1 - 0.35 * i) * Math.exp(-Math.pow((scene.t - b - 0.24) / 0.08, 2))), 0)
            property real uImpact: scene.impactFrame
            property real uFire: scene.fire * (scene.tau < 0 ? 0 : 1)
            property real uBurn: scene.burn
            property real uShock: scene.tau > 0 ? scene.height * 2.2 * (1 - Math.exp(-scene.tau * 0.9)) : -1
            property real uHaze: scene.tau > 0 ? scene.smooth(scene.at.blast + 0.3, scene.at.blast + 1.5) * (1 - scene.smooth(15, scene.at.fade)) : 0
            fragmentShader: "shaders/nuke.frag.qsb"
        }

        // Clawd: panicking, leaping, hanging in slow motion, crossed eyes, the glint, the impact silhouettes
        Item {
            id: clawd
            readonly property var clip: scene.manifest ? scene.manifest.animations[scene.t < scene.at.freeze + 0.05 && scene.pose ? scene.pose.animation : "nuke"] : null
            visible: !!clip && scene.tau < 0
            x: Math.round(scene.body.x - scene.fw / 2)
            y: Math.round(scene.body.y - scene.fh)
            width: scene.fw
            height: scene.fh
            layer.enabled: scene.t >= scene.at.glint && scene.t < scene.at.impact
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "white"
                shadowBlur: 1
                shadowScale: 1.1
                shadowOpacity: scene.seg(scene.at.glint, scene.at.impact)
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 32
                autoPaddingEnabled: true
            }
            Image {
                anchors.fill: parent
                source: clawd.clip ? Qt.resolvedUrl("sprites/" + clawd.clip.file) : ""
                readonly property int index: clawd.clip && clawd.clip.file === "nuke.png" ? scene.body.pose : clawd.clip && scene.pose ? Math.min(scene.pose.frame, clawd.clip.frames - 1) : 0
                sourceClipRect: clawd.clip ? Qt.rect(index * scene.frame.w, 0, scene.frame.w, scene.frame.h) : Qt.rect(0, 0, 0, 0)
                smooth: false
                mipmap: false
                transform: Scale { origin.x: clawd.width / 2; xScale: scene.body.flip || (clawd.clip && clawd.clip.file !== "nuke.png" && !!scene.pose && scene.pose.mirrored) ? -1 : 1 }
            }
        }
        // the glint: a white four-point star swelling in his chest
        Repeater {
            model: scene.t >= scene.at.glint && scene.t < scene.at.impact ? [0, 1] : []
            delegate: Rectangle {
                required property int index
                readonly property real len: scene.pixel * (2 + 16 * Math.pow(scene.seg(scene.at.glint, scene.at.impact), 2))
                color: "white"
                width: index ? scene.pixel : len * 2
                height: index ? len * 2 : scene.pixel
                x: Math.round(scene.body.x - width / 2)
                y: Math.round(scene.body.y - 5 * scene.pixel - height / 2)
            }
        }

        // the mushroom, drawn frame by frame, glowing while it is hot
        Image {
            id: mushroom
            visible: !!scene.cloud && scene.tau >= 0
            x: Math.round(scene.groundX - width / 2)
            y: Math.round(scene.floor - height + scene.cell)
            width: scene.cloud ? scene.cloud.w * scene.cell : 0
            height: scene.cloud ? scene.cloud.h * scene.cell : 0
            source: scene.cloud ? Qt.resolvedUrl("sprites/" + scene.cloud.file) : ""
            sourceClipRect: scene.cloud ? Qt.rect(scene.cloudFrame * scene.cloud.w, 0, scene.cloud.w, scene.cloud.h) : Qt.rect(0, 0, 0, 0)
            smooth: false
            mipmap: false
            layer.enabled: visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(1, 0.55 + 0.3 * Math.min(1, scene.fire / 2), 0.25, 1)
                shadowBlur: 1
                shadowScale: 1.03
                shadowOpacity: Math.min(1, scene.fire * 0.55)
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 64
                brightness: 0.25 * Math.max(0, scene.fire - 1.2)
                autoPaddingEnabled: true
            }
        }

        // embers flung out of the fireball, then ash drifting down while it fades
        Repeater {
            model: scene.side ? [] : scene.embers
            delegate: Rectangle {
                required property var modelData
                readonly property real k: Math.max(0, scene.tau - modelData.delay)
                readonly property real life: k / modelData.life
                visible: scene.tau >= modelData.delay && life < 1
                width: modelData.big ? scene.pixel * 2 : scene.pixel
                height: width
                x: Math.round(scene.groundX + modelData.vx * (1 - Math.exp(-k * 1.4)) / 1.4 - width / 2)
                y: Math.round(scene.floor - 5 * scene.cell + modelData.vy * (1 - Math.exp(-k * 1.4)) / 1.4 + 260 * k * k - height / 2)
                color: life < 0.15 ? "#fff6d8" : life < 0.4 ? "#ffcf4d" : life < 0.7 ? "#ff9028" : "#9e2c18"
            }
        }
        Repeater {
            model: scene.side ? [] : scene.ash
            delegate: Rectangle {
                required property var modelData
                readonly property real k: scene.t - modelData.t0
                visible: k >= 0
                width: modelData.big ? scene.pixel : Math.max(2, scene.pixel / 2)
                height: width
                x: Math.round(modelData.x + Math.sin(k * modelData.sway + modelData.ph) * scene.pixel * 3)
                y: Math.round(modelData.y + k * modelData.v)
                color: modelData.dark ? "#4a423e" : "#9a8f88"
                opacity: 0.85
            }
        }
    }
    readonly property var embers: {
        const out = [];
        for (let i = 0; i < 64; i++) {
            const a = -Math.PI * (0.05 + 0.9 * hash(i * 3.3)), v = height * (0.35 + 0.9 * hash(i * 7.1));
            out.push({ vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 1.2 + 2.2 * hash(i * 1.7), delay: 0.05 * hash(i * 9.9), big: hash(i * 5.5) < 0.3 });
        }
        return out;
    }
    readonly property var ash: {
        const out = [];
        for (let i = 0; i < 90; i++)
            out.push({ x: width * hash(i * 2.9), y: -20 - height * 0.5 * hash(i * 4.1), t0: 13 + 4 * hash(i * 6.3), v: height * (0.08 + 0.12 * hash(i * 8.7)),
                sway: 1 + 2 * hash(i * 1.3), ph: 6 * hash(i * 3.7), big: hash(i * 5.1) < 0.35, dark: hash(i * 7.3) < 0.5 });
        return out;
    }

    ShaderEffectSource { id: worldTex; sourceItem: world; hideSource: true; live: true; visible: false }

    ShaderEffect {
        anchors.fill: parent
        visible: !scene.side
        opacity: scene.fadeOut
        property var uWorld: worldTex
        property size uSize: Qt.size(width, height)
        property point uCenter: Qt.point(scene.groundX, scene.floor)
        property point uShake: {
            let amp = 0;
            if (scene.t >= scene.at.panic && scene.t < scene.at.terror) amp = 1.5;      // he is shaking the whole place
            if (scene.tau >= 0) amp = 34 * Math.exp(-scene.tau * 2.2) + 5 * (1 - scene.seg(scene.at.blast + 1, 16));  // the blast, then rumbling
            if (!amp) return Qt.point(0, 0);
            const n = Math.floor(scene.t * 40);
            return Qt.point((scene.hash(n) - 0.5) * 2 * amp, (scene.hash(n + 13.7) - 0.5) * 2 * amp);
        }
        property real uTime: scene.t
        property real uPixel: scene.pixel
        property real uChroma: scene.tau >= 0 ? 16 * Math.exp(-scene.tau * 1.6) : scene.t >= scene.at.glint ? 4 * scene.seg(scene.at.glint, scene.at.impact) : 0
        property real uInvert: 0
        property real uFlash: scene.tau >= 0 && scene.tau < 0.08 ? 1 : scene.tau >= 0 ? Math.exp(-(scene.tau - 0.08) * 2.6) * 0.9 : 0
        property real uRipR: scene.height * 2.2 * (1 - Math.exp(-Math.max(0, scene.tau) * 0.9))
        property real uRipA: scene.tau >= 0 ? 22 * Math.exp(-scene.tau * 0.8) : 0
        property real uHole: 0
        property real uPull: 0
        property real uSwirl: 0
        property real uAccrete: 0
        property real uStar: 0
        property real uBlack: 0
        property real uReveal: -1
        fragmentShader: "shaders/lens.frag.qsb"
    }
}
