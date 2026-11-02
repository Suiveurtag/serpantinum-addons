import QtQuick
import QtQuick.Effects
import "../"

// The weekly limit coming back: a symphony, drawn by his overlay over the live desktop (click-through), a pure function of
// t (seconds since it started). Storyboard: animations/SYMPHONY.md in the Clawd project. Red velvet curtains close over
// the desktop, open on a dark hall; Clawd, in a bow tie and white gloves, takes the stage, bows, turns his back and raises
// the baton; seven little Clawds (one per day of the week: violin, flute, cello, trumpet, harp, timpani, cymbals) come in
// one after the other, each with a light of its own, while the staves of the music write themselves across the sky and
// the tempo climbs; then the silence, the baton frozen in the air, and the final chord: a golden column, shock rings,
// confetti, roses, a deep bow and the curtains again.
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property real ox: 0            // his frame's top-left on the desktop, scene px (the curtains close over it)
    property real oy: 0
    property int pixel: 4
    property real floorY: height   // the stage floor = the floor line of his screen

    readonly property var at: ({ close: 1.1, swap: 1.5, open: 3.1, spot: 2.8, bow: 3.8, turn: 5.6, lights: 6.0, upbeat: 7.6, raise: 8.2, play: 8.8,
        enter: 0.6, fury: 12.4, caesura: 18.4, finale: 19.4, dance: 19.75, bow2: 24.0, shut: 25.4, shutEnd: 26.6, again: 27.0, out: 27.6, end: 28.3 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }

    // geometry: Clawd on the stage at twice his size, the musicians behind and above him in a shallow arc
    readonly property int pix: pixel * 3     // the conductor's sprite pixel
    readonly property int ms: pixel * 2      // the musicians'
    readonly property real sw: width
    readonly property real sh: height
    readonly property real cx: sw / 2
    readonly property real gap: pixel * 40
    readonly property real base: pixel * 18
    readonly property real rise: pixel * 22
    readonly property var dayColors: ["#ff595e", "#ff9f1c", "#ffd60a", "#52d17c", "#26c6da", "#5c7cff", "#c25bff"]
    function seatX(i) { return cx + (i - 3) * gap; }
    function seatFeet(i) { const d = i - 3; return floorY - base - rise * (1 - d * d / 9); }
    function enterAt(i) { return at.play + i * at.enter; }

    // world time: stops during the silence
    readonly property real tw: t < at.caesura ? t : t < at.finale ? at.caesura : t - (at.finale - at.caesura)
    // the tempo climbs from 1.5 to 3.4 beats a second until the silence; beats counted since the first note
    function phase(w) {
        const d = w - at.play;
        if (d <= 0) return 0;
        const D = at.caesura - at.play, f0 = 1.5, f1 = 3.4;
        return d <= D ? f0 * d + (f1 - f0) * d * d / (2 * D) : f0 * D + (f1 - f0) * D / 2 + f1 * (d - D);
    }
    readonly property real beat: phase(tw)
    readonly property real beatFrac: beat - Math.floor(beat)
    readonly property bool playing: t >= at.play && t < at.finale
    // 1 on the beat, falling to 0
    readonly property real hit: playing ? Math.pow(1 - beatFrac, 2.5) : t >= at.finale ? Math.max(0, 1 - ((t - at.finale) % 0.5) * 2.2) * Math.exp(-(t - at.finale) * 0.5) : 0
    readonly property real fury: t < at.fury ? 0 : t < at.caesura ? seg(at.fury, at.caesura) : t < at.finale ? 1 : 1 - 0.45 * smooth(at.finale, at.finale + 3)
    readonly property real freeze: smooth(at.caesura, at.caesura + 0.25) * (1 - smooth(at.finale - 0.06, at.finale))
    function level(i) {
        const presence = 0.16 * smooth(at.lights, at.lights + 1.4) * (1 - smooth(at.shut - 0.3, at.shut + 0.4));
        const on = smooth(enterAt(i), enterAt(i) + 0.35) * (t < at.bow2 ? 1 : 1 - smooth(at.bow2, at.bow2 + 1.5) * 0.9);
        return Math.max(presence, on);
    }

    // curtains: 0 drawn back, 1 closed
    readonly property real curtain: t < at.close ? ease(t / at.close) : t < at.swap ? 1 : t < at.open ? 1 - ease((t - at.swap) / (at.open - at.swap))
        : t < at.shut ? 0 : t < at.shutEnd ? ease((t - at.shut) / (at.shutEnd - at.shut)) : t < at.again ? 1 : 1 - ease((t - at.again) / 1.0)
    readonly property real hall: t >= 1.2 && t < at.shutEnd + 0.1 ? 1 : 0

    // ── Clawd: the conduct.png pose he holds at each moment ──────────────────────────────────────────
    readonly property var seq1: [7, 8, 9, 10]
    readonly property var seq2: [7, 10, 8, 11, 9, 10, 7, 11]
    function poseAt(tt) {
        const w = tt < at.caesura ? tt : tt < at.finale ? at.caesura : tt - (at.finale - at.caesura);
        if (tt < at.bow) return 0;
        if (tt < at.bow + 0.5) return 1;
        if (tt < at.bow + 1.2) return 2;
        if (tt < at.bow + 1.5) return 1;
        if (tt < at.turn) return 0;
        if (tt < at.turn + 0.3) return 3;
        if (tt < at.upbeat) return 4;
        if (tt < at.raise) return 5;
        if (tt < at.play) return 6;
        if (tt < at.caesura) {
            const b = phase(w), f = b - Math.floor(b), s = tt < 14.4 ? seq1 : seq2;
            return f > 0.78 ? 6 : s[Math.floor(b) % s.length];
        }
        if (tt < at.finale) return 12;
        if (tt < at.finale + 0.16) return 13;
        if (tt < at.dance) return 15;
        if (tt < at.bow2) return Math.floor((tt - at.dance) * 4) % 2 ? 15 : 14;
        if (tt < at.bow2 + 0.5) return 1;
        if (tt < at.bow2 + 1.3) return 2;
        if (tt < at.bow2 + 1.7) return 1;
        return 0;
    }
    readonly property int pose: poseAt(t)
    readonly property var tips: [[20, 6], [20, 8], [20, 11], [19, 6], [20, 11], [20, 4], [20, 0], [20, 13], [20, 5], [19, 3], [20, 0], [20, 0], [17, 0], [15, 1], [20, 0], [20, 1]]
    // he hops off the floor on the leaps and the spin, and dances in the finale
    readonly property real hop: {
        if (t >= at.finale && t < at.finale + 0.16) return pix * (2 + 6 * Math.sin((t - at.finale) / 0.16 * Math.PI));
        if (t >= at.dance && t < at.bow2) return pix * 1.5 * Math.abs(Math.sin((t - at.dance) * 4 * Math.PI / 2 * 1.0));
        if (pose === 11) return pix * 2.5;
        return 0;
    }
    readonly property bool onStage: t >= 2.5 && t < at.shut + 0.9
    readonly property real fw0: (manifest ? manifest.frame.w : 21) * pixel      // the pet's own frame, on the desktop
    readonly property real fh0: (manifest ? manifest.frame.h : 14) * pixel
    // the desktop Clawd: there until the curtains have covered him, back when they reopen
    readonly property real covered: Math.min(1, Math.max(0, (Math.min(ox + fw0 / 2, sw - ox - fw0 / 2) < (0.075 + 0.445 * curtain) * sw) ? 1 : 0))
    readonly property bool homeVisible: (t < at.swap || t >= at.again - 0.05) && covered < 1

    readonly property real shake: t >= at.finale && t < at.finale + 1.0 ? Math.sin(t * 70) * pix * 1.2 * Math.exp(-(t - at.finale) * 5) : 0
    readonly property real zoom: 1 + 0.06 * smooth(at.fury, at.caesura) - 0.06 * smooth(at.finale, at.finale + 0.2) * 0.0 + 0.03 * smooth(at.finale, at.finale + 0.3) * Math.exp(-(t - at.finale) * 0.6)
    readonly property real glow: t < at.upbeat ? 0.25 * smooth(at.spot, at.spot + 1) : t < at.finale ? 0.3 + 0.5 * fury : 0.9 * Math.exp(-(t - at.finale) * 0.35) + 0.25

    Item {
        id: world
        anchors.fill: parent
        scale: scene.zoom
        transformOrigin: Item.Bottom
        x: scene.shake
        y: scene.shake * 0.6

        // the hall, the light, the velvet
        ShaderEffect {
            anchors.fill: parent
            opacity: scene.smooth(0, 0.25) * (1 - scene.smooth(scene.at.out, scene.at.end))
            property size uSize: Qt.size(width, height)
            property real uTime: scene.tw
            property real uCurtain: scene.curtain
            property real uHall: scene.hall
            property real uSpot: scene.smooth(scene.at.spot, scene.at.spot + 0.8) * (1 - scene.smooth(scene.at.bow2 + 0.6, scene.at.shut))
            property point uStage: Qt.point(scene.cx, scene.floorY)
            property real uGap: scene.gap
            property real uBase: scene.base
            property real uRise: scene.rise
            property real uPix: scene.pix
            property real uBeat: scene.hit
            property real uL0: scene.level(0)
            property real uL1: scene.level(1)
            property real uL2: scene.level(2)
            property real uL3: scene.level(3)
            property real uL4: scene.level(4)
            property real uL5: scene.level(5)
            property real uL6: scene.level(6)
            property real uStaff: scene.t < scene.at.play ? 0 : scene.t < scene.at.finale ? scene.ease((scene.t - scene.at.play) / 4.6) : 1
            property real uFury: scene.fury
            property real uFreeze: scene.freeze
            property real uFinale: scene.t >= scene.at.finale ? (scene.t - scene.at.finale) * (scene.t < scene.at.bow2 ? 1 : 1) : -1
            property real uFade: 1 - scene.smooth(scene.at.shut - 0.1, scene.at.shutEnd - 0.1)
            property real uFlash: scene.t >= scene.at.finale ? 0.85 * Math.exp(-(scene.t - scene.at.finale) * 6) : 0
            fragmentShader: "shaders/symphony.frag.qsb"
        }

        // the desktop Clawd, while the curtains are open on the desktop
        Image {
            readonly property var clip: scene.manifest ? scene.manifest.animations.idle : null
            visible: scene.homeVisible && !!clip
            x: Math.round(scene.ox); y: Math.round(scene.oy); width: scene.fw0; height: scene.fh0
            source: clip ? Qt.resolvedUrl("sprites/" + clip.file) : ""
            sourceClipRect: clip ? Qt.rect(0, 0, scene.manifest.frame.w, scene.manifest.frame.h) : Qt.rect(0, 0, 0, 0)
            smooth: false
        }

        // the podium
        Item {
            visible: scene.onStage
            x: scene.cx - width / 2; y: scene.floorY - height; width: scene.pix * 15; height: scene.pix * 1.5
            opacity: scene.smooth(scene.at.spot, scene.at.spot + 0.6) * (1 - scene.smooth(scene.at.shut - 0.2, scene.at.shut + 0.4))
            Rectangle { anchors.fill: parent; color: "#2a140d" }
            Rectangle { width: parent.width; height: scene.pixel; color: "#d9a441" }
            Rectangle { y: scene.pixel; width: parent.width; height: scene.pixel; color: "#5a2f1b" }
        }

        // the seven musicians
        Repeater {
            model: 7
            delegate: Item {
                id: mus
                required property int index
                readonly property var clip: scene.manifest ? scene.manifest.orchestra : null
                readonly property real lv: scene.level(index)
                readonly property bool on: scene.t >= scene.enterAt(index) && scene.t < scene.at.bow2 + 0.6
                readonly property bool celebrate: scene.t >= scene.at.finale && scene.t < scene.at.bow2 + 0.6
                readonly property int ph: celebrate ? Math.floor(scene.t * 5 + index) % 2 : on ? (Math.floor(scene.beat * 2 + index) % 2) : 0
                readonly property real bob: celebrate ? scene.ms * 1.5 * Math.abs(Math.sin(scene.t * 7 + index * 0.9)) * Math.min(1, (scene.t - scene.at.finale) * 3)
                    : on ? scene.ms * 0.5 * (scene.hit * (0.6 + scene.fury)) : 0
                visible: !!clip && scene.t >= scene.at.lights && scene.t < scene.at.shut + 0.9 && lv > 0.01
                opacity: Math.min(1, 0.25 + lv * 1.2) * (1 - scene.smooth(scene.at.shut - 0.2, scene.at.shut + 0.4))
                width: clip ? clip.w * scene.ms : 0
                height: clip ? clip.h * scene.ms : 0
                x: Math.round(scene.seatX(index) - width / 2)
                y: Math.round(scene.seatFeet(index) - height - bob)
                Image {
                    anchors.fill: parent
                    source: mus.clip ? Qt.resolvedUrl("sprites/" + mus.clip.file) : ""
                    sourceClipRect: mus.clip ? Qt.rect((mus.index * 2 + mus.ph) * mus.clip.w, 0, mus.clip.w, mus.clip.h) : Qt.rect(0, 0, 0, 0)
                    smooth: false
                }
            }
        }

        // notes rising from the instruments
        Repeater {
            model: scene.notes
            delegate: Item {
                id: note
                required property var modelData
                readonly property real k: scene.tw - modelData.t0
                visible: k >= 0 && k < modelData.life && scene.t < scene.at.finale + 0.2 && scene.t >= scene.at.play
                readonly property real u: scene.pixel
                x: Math.round(scene.seatX(modelData.i) + modelData.dx * scene.gap * 0.3 + Math.sin(k * 2.4 + modelData.ph) * u * 3)
                y: Math.round(scene.seatFeet(modelData.i) - scene.ms * 14 - k * modelData.v)
                opacity: Math.min(1, k * 5) * (1 - Math.max(0, k - modelData.life * 0.6) / (modelData.life * 0.4))
                Rectangle { x: 0; y: 0; width: note.u * 2.5; height: note.u * 2; color: scene.dayColors[note.modelData.i]; rotation: -20 }
                Rectangle { x: note.u * 2; y: -note.u * 5; width: Math.max(1, note.u * 0.6); height: note.u * 5.4; color: scene.dayColors[note.modelData.i] }
                Rectangle { visible: note.modelData.flag; x: note.u * 2.5; y: -note.u * 5; width: note.u * 2; height: note.u; color: scene.dayColors[note.modelData.i] }
            }
        }

        // Clawd the conductor
        Item {
            id: clawd
            readonly property var clip: scene.manifest ? scene.manifest.animations.conduct : null
            visible: scene.onStage && !!clip
            width: (scene.manifest ? scene.manifest.frame.w : 21) * scene.pix
            height: (scene.manifest ? scene.manifest.frame.h : 14) * scene.pix
            x: Math.round(scene.cx - width / 2)
            y: Math.round(scene.floorY - scene.pix * 1.5 - height - scene.hop)
            opacity: scene.smooth(scene.at.swap + 0.2, scene.at.swap + 0.7) * (1 - scene.smooth(scene.at.shut - 0.2, scene.at.shut + 0.4))
            layer.enabled: scene.glow > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(1, 0.86, 0.5, 1)
                shadowBlur: 1
                shadowScale: 1.03 + 0.05 * scene.glow
                shadowOpacity: Math.min(1, scene.glow)
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 48
                autoPaddingEnabled: true
            }
            Image {
                anchors.fill: parent
                source: clawd.clip ? Qt.resolvedUrl("sprites/" + clawd.clip.file) : ""
                sourceClipRect: clawd.clip ? Qt.rect(Math.min(scene.pose, clawd.clip.frames - 1) * scene.manifest.frame.w, 0, scene.manifest.frame.w, scene.manifest.frame.h) : Qt.rect(0, 0, 0, 0)
                smooth: false
            }
        }

        // the baton leaves a comet tail
        Repeater {
            model: 7
            delegate: Rectangle {
                id: tail
                required property int index
                readonly property real tt: scene.t - index * 0.03
                readonly property var tip: scene.tips[Math.min(scene.poseAt(tt), scene.tips.length - 1)]
                visible: scene.onStage && ((scene.t >= scene.at.upbeat && scene.t < scene.at.bow2) && scene.poseAt(tt) >= 5) && !!tip
                x: Math.round(clawd.x + (tip ? tip[0] : 0) * scene.pix - width / 2 + scene.pix / 2)
                y: Math.round(clawd.y + (tip ? tip[1] : 0) * scene.pix - height / 2 + scene.pix / 2)
                width: scene.pix * (1 - index * 0.11); height: width
                radius: width / 2
                color: index === 0 ? "#ffffff" : "#ffd56b"
                opacity: (1 - index / 7) * (0.5 + 0.5 * scene.hit)
            }
        }

        // confetti, streamers and notes bursting from the final chord
        Repeater {
            model: scene.confetti
            delegate: Rectangle {
                id: bit
                required property var modelData
                readonly property real k: scene.t - scene.at.finale - modelData.delay
                visible: k >= 0 && scene.t < scene.at.shut + 0.9
                readonly property real fall: Math.max(0, k)
                x: scene.cx + modelData.vx * k * (1 - Math.exp(-k * 0.5)) * 2 + Math.sin(k * modelData.sway + modelData.ph) * scene.pixel * 4
                y: scene.floorY - scene.pix * 8 - modelData.vy * (1 - Math.exp(-k * 1.4)) + 90 * k * k * modelData.heavy + k * 40
                width: modelData.w * scene.pixel; height: modelData.h * scene.pixel
                color: modelData.color
                rotation: k * modelData.spin
                transform: Scale { origin.x: bit.width / 2; origin.y: bit.height / 2; yScale: Math.cos(bit.k * bit.modelData.flip) }
                opacity: Math.min(1, k * 8) * (1 - scene.smooth(scene.at.shut - 0.3, scene.at.shut + 0.6))
            }
        }

        // roses thrown from the audience
        Repeater {
            model: scene.roses
            delegate: Item {
                id: rose
                required property var modelData
                readonly property real k: (scene.t - modelData.t0) / modelData.dur
                visible: k >= 0 && scene.t < scene.at.shut + 0.9
                readonly property real kk: Math.min(1, Math.max(0, k))
                x: scene.cx + modelData.x0 + (modelData.x1 - modelData.x0) * kk
                y: scene.sh + 20 + ((scene.floorY - scene.pix * 0.5 + modelData.dy) - scene.sh - 20) * kk - Math.sin(kk * Math.PI) * modelData.arc
                rotation: kk < 1 ? kk * modelData.spin : modelData.spin
                opacity: 1 - scene.smooth(scene.at.shut - 0.3, scene.at.shut + 0.3)
                Rectangle { x: -scene.pixel * 1.5; y: -scene.pixel * 1.5; width: scene.pixel * 3; height: scene.pixel * 3; color: "#e5365f" }
                Rectangle { x: -scene.pixel * 0.5; y: -scene.pixel * 0.5; width: scene.pixel; height: scene.pixel; color: "#ff9db5" }
                Rectangle { x: -scene.pixel * 0.25; y: scene.pixel * 1.5; width: Math.max(1, scene.pixel * 0.6); height: scene.pixel * 3; color: "#3fa34d" }
            }
        }

        // the week, as a battery: one bar per day, lit as its musician comes in; then the verdict
        Item {
            id: hud
            readonly property real u: scene.pixel * 1.6
            visible: opacity > 0
            opacity: scene.smooth(scene.at.play - 0.4, scene.at.play + 0.2) * (1 - scene.smooth(scene.at.bow2 + 1.2, scene.at.shut))
            x: Math.round(scene.cx - width / 2)
            y: Math.round(scene.sh * 0.075 + u * 4)
            width: u * 4 + (u * 7 + u * 2) * 7 + u * 4
            height: u * 12
            Rectangle { anchors.fill: parent; color: "#16141c"; opacity: 0.85 }
            Row {
                x: hud.u * 3; y: hud.u * 2
                spacing: hud.u * 2
                Repeater {
                    model: 7
                    delegate: Column {
                        id: bar
                        required property int index
                        readonly property real lit: scene.smooth(scene.enterAt(index), scene.enterAt(index) + 0.3)
                        spacing: hud.u * 0.8
                        Rectangle {
                            width: hud.u * 7; height: hud.u * 4
                            color: Qt.alpha(scene.dayColors[bar.index], 0.18 + 0.82 * bar.lit)
                            border.width: scene.t >= scene.at.finale ? 0 : 1; border.color: Qt.alpha(scene.dayColors[bar.index], 0.7)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "MTWTFSS"[bar.index]
                            color: Qt.alpha(scene.dayColors[bar.index], 0.4 + 0.6 * bar.lit)
                            font.family: ThemeBackend.fontFamily; font.pixelSize: Math.round(hud.u * 3); font.bold: true
                            textFormat: Text.PlainText
                        }
                    }
                }
            }
        }
        Rectangle {
            visible: verdict.opacity > 0
            opacity: verdict.opacity * 0.85
            x: verdict.x - scene.pixel * 2; y: verdict.y - scene.pixel; width: verdict.width + scene.pixel * 4; height: verdict.height + scene.pixel * 2
            color: "#16141c"
        }
        Text {
            id: verdict
            opacity: scene.smooth(scene.at.finale + 0.7, scene.at.finale + 1.3) * (1 - scene.smooth(scene.at.bow2 + 1.2, scene.at.shut))
            visible: opacity > 0
            x: Math.round(scene.cx - width / 2)
            y: Math.round(hud.y + hud.height + scene.pixel * 3)
            text: "♪ 7d limit reset ♪"
            color: "#fff2b8"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Math.round(scene.pixel * 8)
            font.bold: true
            textFormat: Text.PlainText
        }
    }

    // the cymbal crash
    Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: scene.t >= scene.at.finale ? 0.7 * Math.exp(-(scene.t - scene.at.finale) * 7) : 0 }

    // ── particle tables: pure functions of the index ───────────────────────────────────────────────
    readonly property var notes: {
        const out = [];
        for (let i = 0; i < 7; i++)
            for (let n = 0; n < 22; n++)
                out.push({ i, t0: enterAt(i) + n * (0.72 - 0.3 * n / 22) + 0.3 * hash(i * 31 + n), life: 2.4 + hash(i * 7 + n * 3), v: pixel * (22 + 14 * hash(i * 5 + n)),
                    dx: (hash(i * 13 + n * 2) - 0.5) * 1.6, ph: 6 * hash(i * 3 + n), flag: hash(i * 17 + n) < 0.5 });
        return out;
    }
    readonly property var confetti: {
        const out = [], colors = ["#ff595e", "#ff9f1c", "#ffd60a", "#52d17c", "#26c6da", "#5c7cff", "#c25bff", "#ffffff", "#ffd56b"];
        for (let i = 0; i < 260; i++) {
            const streamer = hash(i * 9.7) < 0.2;
            out.push({ delay: 0.05 * hash(i * 2.9), vx: (hash(i * 3.3) - 0.5) * sw * 0.55, vy: sh * (0.3 + 0.55 * hash(i * 5.1)),
                w: streamer ? 0.7 : 1 + 1.5 * hash(i * 7.7), h: streamer ? 4 + 4 * hash(i * 4.2) : 1 + hash(i * 6.1),
                color: colors[Math.floor(hash(i * 8.8) * colors.length)], spin: (hash(i * 1.7) - 0.5) * 600, flip: 4 + 8 * hash(i * 2.2),
                sway: 1 + 3 * hash(i * 6.6), ph: 6 * hash(i * 0.9), heavy: 0.6 + 0.8 * hash(i * 3.9) });
        }
        return out;
    }
    readonly property var roses: {
        const out = [];
        for (let i = 0; i < 14; i++) {
            const side = i % 2 ? 1 : -1;
            out.push({ t0: at.finale + 2.4 + i * 0.28 + 0.1 * hash(i), dur: 1.0 + 0.4 * hash(i * 4), x0: side * sw * (0.1 + 0.3 * hash(i * 2)), x1: side * (pix * (6 + 3 * hash(i * 3)) + hash(i * 5) * pix * 8),
                arc: sh * (0.35 + 0.25 * hash(i * 6)), spin: side * (200 + 400 * hash(i * 7)), dy: -pixel * 1.5 * hash(i * 8) });
        }
        return out;
    }
}
