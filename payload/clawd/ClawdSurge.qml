import QtQuick
import QtQuick.Effects
import "../"

// The weekly limit ran out, the superpowered way: drawn by his overlay over the live desktop (click-through), a pure
// function of t (seconds since it started). Storyboard: animations/SURGE.md in the Clawd project. He jumps ("!"), stares
// at the top-left corner where light bleeds in and the screen bulges (bulge.frag on a capture of the desktop) until a
// magic orb tears through and hits him (impact frames, explosion); poker-faced in the smoke, he inhales all of it, gets
// his powers (pulse, aura), dashes right (dark, zoom, glowing wink, the overlay switches to an empty workspace meanwhile),
// strikes the floor alight in the middle of the screen and summons six helpers, one per effort level, who each start
// working with a beam of light; then he rises, light in his hands, and their streams recharge the week (ASCII bar).
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property Item desk: null       // the desktop captured at the start (ScreencopyView), or null
    property var verbs: ["Thinking"]
    property real ox: 0            // his frame's top-left on the desktop, scene px
    property real oy: 0
    property int pixel: 4
    property real floorY: height   // the floor line of his screen

    property real seed: 0          // set when it starts: which work each helper picks
    readonly property var at: ({ look: 0.75, edge: 0.9, bulge: 1.6, brace: 3.5, burst: 4.3, hit: 4.95, boom: 5.25, poker: 6.4, blink: 7.6,
        inhale: 8.3, gulp: 10.9, power: 11.1, crouch: 12.5, dash: 12.8, slow: 12.95, wink: 13.35, unwink: 14.15, fast: 14.45, swap: 14.55,
        slide: 14.7, stop: 15.9, leap: 16.15, slam: 17.1, call: 18.5, gap: 0.85, work: 24.2, wgap: 0.95, rise: 30.4, charge: 31.2,
        full: 35.6, vanish: 40.6, land: 41.4, close: 42.0, back: 42.5, open: 42.8, end: 43.6 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }
    function rel(i) { const k = t - landAt(i); return k < -1 ? -2 : k; }
    function since(a) { return t >= a ? t - a : -1; }

    readonly property real sw: width
    readonly property real sh: height
    readonly property real cx: sw / 2
    readonly property int fw: (manifest ? manifest.frame.w : 21)
    readonly property int fh: (manifest ? manifest.frame.h : 14)
    // once on the empty workspace, he and his helpers are drawn twice as big (the dash off-screen hides the change)
    readonly property int ps: t >= at.swap ? pixel * 2 : pixel
    readonly property real pw: fw * ps
    readonly property real ph: fh * ps
    readonly property point home: Qt.point(ox + fw * pixel / 2, oy + fh * pixel)     // his feet before it all
    readonly property string mono: typeof ThemeBackend !== "undefined" ? ThemeBackend.fontFamily : "monospace"

    // the helpers: low, medium, high on the left, xhigh, max, ultra on the right
    readonly property var names: ["low", "medium", "high", "xhigh", "max", "ultra"]
    readonly property var colors: ["#FFC107", "#4EBA65", "#B1B9F9", "#AF87FF", "#FFB38A", "#9BF6FF"]
    readonly property var rainbow: ["#FF9E7A", "#FFD966", "#8FE3A0", "#9BD3FF", "#C9B5FF", "#FF9CB0"]
    function colorOf(i, k) { return i === 4 ? rainbow[Math.floor(t * 6 + (k || 0)) % 6] : colors[i]; }
    function seatX(i) { return sw * [1, 2, 3, 5, 6, 7][i] / 8; }
    function arrive(i) { return at.call + i * at.gap; }
    // when each one touches down, and when it is flung away
    function landAt(i) { return arrive(i) + [0.45, 0.5, 0.6, 0.56, 0.35, 0.1][i]; }
    function leaveAt(i) { return at.vanish + i * 0.12; }
    function workAt(i) { return at.work + i * at.wgap; }
    // xhigh slides in from the right edge
    function glideX() { const k = clamp01(seg(arrive(3), arrive(3) + 0.8) / 0.7); return sw + pw + (seatX(3) - sw - pw) * (1 - Math.pow(1 - k, 3)); }

    // ── Clawd: feet position, surge.png pose ─────────────────────────────────────────────────────────
    // the dash: short on screen, slow motion in the middle, the workspace switches as he bursts off again, then a long slide
    readonly property int dir: home.x < sw * 0.68 ? 1 : -1
    readonly property real dashFit: { const room = dir > 0 ? sw - pixel * 30 - home.x : home.x - pixel * 30; return Math.max(0, Math.min(1, room / (sw * 0.2))); }
    readonly property real dashD: sw * 0.08 * dashFit
    readonly property real slideD: sw * 0.12 * dashFit
    readonly property real slideX: home.x + dir * (dashD + slideD)
    readonly property real camera: smooth(at.slow, at.slow + 0.35) * (1 - smooth(at.unwink, at.fast))   // the zoom on his wink
    readonly property real hoverY: floorY - sh * 0.24
    // world time: crawls during the slow motion
    function tw(tt) { return tt - Math.max(0, Math.min(tt, at.fast) - at.slow) * 0.92; }
    function bodyAt(tt) {
        const hx = home.x, hy = home.y, k = (a, b) => clamp01((tt - a) / (b - a));
        if (tt < at.look) { const q = k(0, 0.6); return { x: hx, y: hy - Math.sin(Math.PI * q) * fh * pixel * 0.7, pose: q > 0 && q < 1 ? 1 : 0 }; }
        if (tt < at.brace) return { x: hx + (tt > at.bulge + 1.2 ? (Math.floor(tt * 30) % 2 ? 0.5 : -0.5) * pixel * k(at.bulge + 1.2, at.brace) : 0), y: hy, pose: 2 };
        if (tt < at.boom) return { x: hx, y: hy, pose: 3 };
        if (tt < at.inhale) return { x: hx, y: hy, pose: tt >= at.blink && tt < at.blink + 0.14 ? 5 : 4 };
        if (tt < at.gulp) {
            const q = k(at.inhale, at.gulp), shiver = (Math.floor(tt * 28) % 2 ? 0.5 : -0.5) * pixel * q;
            return { x: hx + shiver, y: hy, pose: q < 0.35 ? 6 : q < 0.7 ? 7 : 8 };
        }
        if (tt < at.power) return { x: hx, y: hy - pixel * 2 * Math.sin(k(at.gulp, at.power) * Math.PI), pose: 16 };
        if (tt < at.crouch) return { x: hx, y: hy, pose: tt < at.power + 0.45 ? 10 : tt < 12.2 ? 9 : 16 };
        if (tt < at.dash) return { x: hx, y: hy, pose: 11 };
        const run = Math.floor(tw(tt) * 16) % 2 ? 13 : 12;
        if (tt < at.slow) return { x: hx + dir * dashD * 0.35 * k(at.dash, at.slow), y: hy, pose: run };
        if (tt < at.fast) return { x: hx + dir * dashD * (0.35 + 0.1 * k(at.slow, at.fast)), y: hy, pose: tt >= at.wink && tt < at.unwink ? 14 : run };
        if (tt < at.slide) { const q = k(at.fast, at.slide); return { x: hx + dir * dashD * (0.45 + 0.55 * q), y: tt < at.swap ? hy : floorY, pose: run }; }
        if (tt < at.stop) { const q = k(at.slide, at.stop); return { x: hx + dir * (dashD + slideD * (1 - Math.pow(1 - q, 2.2))), y: floorY, pose: 15 }; }
        if (tt < at.leap) return { x: slideX, y: floorY, pose: 11 };
        if (tt < at.slam) {
            const q = k(at.leap, at.slam), e = q * q * (3 - 2 * q);
            return { x: slideX + (cx - slideX) * e, y: floorY - Math.sin(Math.PI * q) * fh * pixel * 2 * 2.4, pose: q < 0.55 ? 9 : 17 };
        }
        if (tt < at.slam + 0.7) return { x: cx, y: floorY, pose: 18 };
        if (tt < at.rise) return { x: cx, y: floorY, pose: 16 };
        if (tt < at.land) {
            const up = ease(k(at.rise, at.charge)), bob = Math.sin(tt * 2.6) * pixel * 2 * up;
            const pose = tt < at.charge ? 19 : tt < at.full ? 20 : 21;
            return { x: cx, y: floorY + (hoverY - floorY) * up + bob, pose };
        }
        if (tt < at.close) { const q = ease(k(at.land, at.land + 0.5)); return { x: cx, y: hoverY + (floorY - hoverY) * q, pose: q < 1 ? 21 : 0 }; }
        return { x: cx, y: floorY, pose: 0 };
    }
    readonly property var me: bodyAt(t)
    readonly property bool flip: dir < 0 && t >= at.crouch && t < at.leap
    readonly property real meX: me.x - pw / 2       // his frame's top-left
    readonly property real meY: me.y - ph
    readonly property point mid: Qt.point(me.x, me.y - ph * 0.45)
    // impact frames: the orb hitting him, then his fists hitting the floor
    readonly property var impact: t >= at.hit && t < at.boom ? { n: Math.floor((t - at.hit) / 0.075), x: home.x - fw * pixel / 2, y: home.y - fh * pixel, pose: 3, p: Qt.point(orbC.x, orbC.y) }
        : t >= at.slam && t < at.slam + 0.26 ? { n: Math.floor((t - at.slam) / 0.065), x: cx - pw / 2, y: floorY - ph, pose: 18, p: Qt.point(cx, floorY) } : null
    readonly property real impactPhase: impact ? impact.n : -1

    // the orb: it pushes in through the left edge a bit above the middle, then bends down onto him
    readonly property point orbA: Qt.point(0, sh * 0.4)
    readonly property point orbB: Qt.point((home.x + sw * 0.05) * 0.5, sh * 0.3)
    readonly property point orbC: Qt.point(home.x, home.y - fh * pixel * 0.45)
    readonly property real orbU: t >= at.burst && t < at.hit ? Math.pow(seg(at.burst, at.hit), 1.6) : -1

    readonly property real suck: ease(seg(at.inhale, at.gulp))
    readonly property real aura: smooth(at.power, at.power + 0.5) * (1 - smooth(at.vanish + 0.4, at.land + 0.5))
    // the camera: the compositor zooms the live desktop itself (the overlay starts that, nativeZoom); else only this scene is scaled
    property bool nativeZoom: false
    readonly property real zoomFactor: 1 + 2.0 * camera
    readonly property real zoom: nativeZoom ? 1 : zoomFactor
    readonly property real dark: Math.max(0.85 * smooth(at.dash, at.slow + 0.2) * (1 - smooth(at.unwink, at.fast)),
        0.5 * smooth(at.slam, at.slam + 0.8) * (1 - smooth(at.land, at.close)),
        0.3 * smooth(at.burst - 0.3, at.burst) * (1 - smooth(at.poker, at.poker + 1.0)),
        t >= at.inhale && t < at.gulp ? 0.5 * smooth(at.gulp - 1.0, at.gulp - 0.05) : 0,
        t < at.full ? 0.55 * smooth(at.full - 1.3, at.full - 0.05) : 0)
    // which work each helper does: 6 of the 7 kinds (strip frame pairs), shuffled by the seed
    // keyboard, then the full loops of read, bash, search, edit, todo, web (clone.png: first frame, frame count, fps)
    readonly property var works: [{ s: 2, n: 2, f: 5 }, { s: 8, n: 5, f: 4 }, { s: 13, n: 5, f: 5 }, { s: 18, n: 4, f: 4 }, { s: 22, n: 8, f: 6 }, { s: 30, n: 4, f: 3.5 }, { s: 34, n: 4, f: 6 }]
    readonly property var workOf: { const o = [0, 1, 2, 3, 4, 5, 6]; o.sort((a, b) => hash(seed * 97 + a * 13.1) - hash(seed * 97 + b * 13.1)); return o; }
    // the beams: each helper's level, and how long since it struck
    function beamLevel(i) {
        const on = smooth(workAt(i), workAt(i) + 0.25);
        const flare = t >= at.full ? 2.0 * Math.exp(-(t - at.full) * 1.4) : 0;
        return on * (0.7 + 0.3 * Math.sin(t * 3 + i)) * (1 - 0.5 * smooth(at.charge, at.charge + 1)) * (1 - smooth(at.vanish, at.vanish + 0.6)) + flare * on;
    }
    readonly property real shake: {
        let s = 0;
        if (t >= at.brace - 0.6 && t < at.burst) s += pixel * 2.5 * smooth(at.brace - 0.6, at.burst) * (Math.floor(t * 45) % 2 ? 1 : -1);
        if (t >= at.burst) s += pixel * 14 * Math.exp(-(t - at.burst) * 3.2);
        if (t >= at.boom) s += pixel * 4 * Math.exp(-(t - at.boom) * 3);
        if (t >= at.inhale && t < at.gulp) s += pixel * 2 * smooth(at.inhale, at.gulp) * (Math.floor(t * 50) % 2 ? 1 : -1);
        if (t >= at.gulp) s += pixel * 16 * Math.exp(-(t - at.gulp) * 2.2);
        if (t >= at.slam) s += pixel * 8 * Math.exp(-(t - at.slam) * 3.5);
        if (t >= at.swap) s += pixel * 3 * Math.exp(-(t - at.swap) * 5);
        for (let i = 0; i < 6; i++) if (t >= workAt(i)) s += pixel * [0.4, 0.6, 0.9, 1.4, 2.2, 4][i] * Math.exp(-(t - workAt(i)) * 4);
        for (let i = 0; i < 6; i++) {
            if (t >= landAt(i)) s += pixel * (3 + i * 0.8) * Math.exp(-(t - landAt(i)) * 7);
            if (t >= leaveAt(i)) s += pixel * 3 * Math.exp(-(t - leaveAt(i)) * 7);
        }
        if (t < at.full) s += pixel * 3 * Math.pow(smooth(at.full - 1.4, at.full), 2) * (Math.floor(t * 40) % 2 ? 1 : -1);
        if (t >= at.full) s += pixel * 12 * Math.exp(-(t - at.full) * 1.8);
        return s;
    }
    readonly property real flash: {
        let f = 0;
        if (t >= at.burst) f = Math.max(f, 0.9 * Math.exp(-(t - at.burst) * 9));
        if (t >= at.boom) f = Math.max(f, 0.95 * Math.exp(-(t - at.boom) * 5));
        if (t >= at.gulp) f = Math.max(f, 0.6 * Math.exp(-(t - at.gulp) * 9));
        if (t >= at.power) f = Math.max(f, 0.8 * Math.exp(-(t - at.power) * 8));
        if (t >= at.swap) f = Math.max(f, 0.85 * Math.exp(-(t - at.swap) * 7));
        if (t >= at.slam + 0.26) f = Math.max(f, 0.6 * Math.exp(-(t - at.slam - 0.26) * 6));
        if (t >= workAt(4)) f = Math.max(f, 0.25 * Math.exp(-(t - workAt(4)) * 6));
        if (t >= workAt(5)) f = Math.max(f, 0.4 * Math.exp(-(t - workAt(5)) * 6));
        for (let i = 0; i < 6; i++) {
            if (t >= landAt(i)) f = Math.max(f, (0.18 + 0.05 * i) * Math.exp(-(t - landAt(i)) * 10));
            if (t >= leaveAt(i)) f = Math.max(f, 0.22 * Math.exp(-(t - leaveAt(i)) * 9));
        }
        if (t >= arrive(5)) f = Math.max(f, 0.4 * Math.exp(-(t - arrive(5)) * 7));
        if (t >= at.full) f = Math.max(f, 1.0 * Math.exp(-(t - at.full) * 2.2));
        return f;
    }
    // the end of his arms (surge poses 19 and 20), scene px
    readonly property var hands: me.pose === 20 ? [[2.5, 0.5], [18.5, 0.5]] : [[1.5, 3.5], [19.5, 3.5]]

    // the week coming back: an ASCII bar
    readonly property real charge: t < at.charge ? 0 : t >= at.full ? 1 : Math.floor(Math.pow(seg(at.charge, at.full), 1.35) * 100) / 100
    function bar(k) {
        const n = 30, f = Math.round(k * n), pct = String(Math.round(k * 100)).padStart(3, " ") + "%";
        const rule = "+" + "-".repeat(44) + "+";
        const status = k >= 1 ? "RESTORED" : t >= at.charge ? "recharging" + ".".repeat(1 + Math.floor(t * 3) % 3).padEnd(3, " ") : "";
        const head = ("weekly limit").padEnd(42 - status.length, " ") + status;
        return [rule, "| " + head + " |", "| [" + "#".repeat(f) + ".".repeat(n - f) + "] " + pct + " left |", rule].join("\n");
    }
    readonly property var cleanVerbs: { const v = (verbs || []).filter(s => /^[\x20-\x7e]{1,24}$/.test(s)); return v.length ? v : ["Thinking", "Pondering", "Brewing", "Conjuring"]; }

    // the darkening stays full-screen while the world zooms
    Rectangle { anchors.fill: parent; color: "#05030a"; opacity: scene.dark }

    Item {
        id: world
        anchors.fill: parent
        x: scene.shake * Math.sin(scene.t * 63)
        y: scene.shake * 0.7 * Math.cos(scene.t * 51)
        // the camera zooms on him where he is, his feet stay on the floor line
        transform: Scale { origin.x: scene.me.x; origin.y: scene.me.y; xScale: scene.zoom; yScale: scene.zoom }

        // the corner bending in, on the captured desktop
        ShaderEffect {
            anchors.fill: parent
            visible: !!scene.desk && scene.desk.hasContent && scene.t >= scene.at.bulge && scene.t < scene.at.burst + 1.6
            property var uDesk: scene.desk
            property size uSize: Qt.size(width, height)
            property real uTime: scene.t
            property point uCorner: Qt.point(-scene.sh * 0.03, scene.orbA.y)
            property real uBulge: scene.smooth(scene.at.bulge, scene.at.burst) * (0.85 + 0.15 * Math.sin(scene.t * 9))
            property real uCrack: scene.smooth(scene.at.brace - 0.8, scene.at.burst)
            property real uPop: scene.since(scene.at.burst)
            fragmentShader: "shaders/bulge.frag.qsb"
        }

        // all the light
        ShaderEffect {
            anchors.fill: parent
            property size uSize: Qt.size(width, height)
            property real uTime: scene.t
            property real uDark: 0
            property real uEdge: scene.smooth(scene.at.edge, scene.at.burst) * (1 - scene.smooth(scene.at.burst + 0.2, scene.at.burst + 1.4))
            property real uPop: scene.since(scene.at.burst)
            property point uOrbA: scene.orbA
            property point uOrbB: scene.orbB
            property point uOrbC: scene.orbC
            property real uOrbU: scene.orbU
            property real uOrbR: scene.pixel * 9
            property point uHit: scene.orbC
            property real uBoom: scene.since(scene.at.boom)
            property real uSmoke: scene.smooth(scene.at.boom, scene.at.boom + 0.4) * (1 - scene.smooth(scene.at.gulp - 0.25, scene.at.gulp))
            property real uSuck: scene.suck
            property real uPower: scene.since(scene.at.power)
            property real uAura: scene.aura
            property point uMe: scene.mid
            property real uPix: scene.ps
            property real uSlam: scene.since(scene.at.slam + 0.05)
            property real uFloorY: scene.floorY
            property real uFloor: scene.smooth(scene.at.slam, scene.at.slam + 0.3) * (1 - scene.smooth(scene.at.land, scene.at.close)) * (0.7 + 0.3 * Math.sin(scene.t * 2))
            property vector4d uBX0: Qt.vector4d(scene.seatX(0), scene.seatX(1), scene.seatX(2), scene.seatX(3))
            property vector4d uBX1: Qt.vector4d(scene.seatX(4), scene.seatX(5), 0, 0)
            property vector4d uBL0: Qt.vector4d(scene.beamLevel(0), scene.beamLevel(1), scene.beamLevel(2), scene.beamLevel(3))
            property vector4d uBL1: Qt.vector4d(scene.beamLevel(4), scene.beamLevel(5), 0, 0)
            property vector4d uBK0: Qt.vector4d(scene.since(scene.workAt(0)), scene.since(scene.workAt(1)), scene.since(scene.workAt(2)), scene.since(scene.workAt(3)))
            property vector4d uBK1: Qt.vector4d(scene.since(scene.workAt(4)), scene.since(scene.workAt(5)), -1, -1)
            property real uHead: scene.ph * 0.6
            property real uStream: scene.smooth(scene.at.charge, scene.at.charge + 1.4) * (1 - scene.smooth(scene.at.full, scene.at.vanish))
            property real uFinal: scene.since(scene.at.full)
            property vector4d uAK0: Qt.vector4d(scene.rel(0), scene.rel(1), scene.rel(2), scene.rel(3))
            property vector4d uAK1: Qt.vector4d(scene.rel(4), scene.rel(5), 0, 0)
            property vector4d uVK0: Qt.vector4d(scene.since(scene.leaveAt(0)), scene.since(scene.leaveAt(1)), scene.since(scene.leaveAt(2)), scene.since(scene.leaveAt(3)))
            property vector4d uVK1: Qt.vector4d(scene.since(scene.leaveAt(4)), scene.since(scene.leaveAt(5)), -1, -1)
            property real uBuild: scene.smooth(scene.at.full - 1.4, scene.at.full) * (scene.t < scene.at.full ? 1 : 0)
            property real uImpact: 0
            property real uZap: scene.since(scene.arrive(5))
            property point uHandL: Qt.point(scene.meX + scene.hands[0][0] * scene.ps, scene.meY + scene.hands[0][1] * scene.ps)
            property point uHandR: Qt.point(scene.meX + scene.hands[1][0] * scene.ps, scene.meY + scene.hands[1][1] * scene.ps)
            property real uWarp: scene.since(scene.at.swap)
            property real uDir: scene.dir
            property real uHands: (scene.me.pose === 19 || scene.me.pose === 20 || scene.me.pose === 21 && scene.t < scene.at.vanish) ? scene.smooth(scene.at.rise, scene.at.rise + 0.5) : 0
            fragmentShader: "shaders/surge.frag.qsb"
        }

        // the glowing wisps the explosion leaves, spiralling into him as he inhales
        Repeater {
            model: scene.wisps
            delegate: Repeater {
                id: wisp
                required property var modelData
                model: 6
                delegate: Rectangle {
                    id: dot
                    required property int index
                    readonly property real tt: scene.t - index * 0.035
                    readonly property real s: scene.ease((tt - scene.at.inhale) / (scene.at.gulp - scene.at.inhale - 0.2))
                    readonly property real life: tt - scene.at.boom - wisp.modelData.delay
                    readonly property real r: wisp.modelData.r * scene.sh * (1 - Math.exp(-Math.max(0, life) * 3)) * (1 - s)
                    readonly property real a: wisp.modelData.a + Math.max(0, life) * wisp.modelData.w + s * s * 7 * wisp.modelData.dir
                    visible: life > 0 && scene.t < scene.at.gulp && r > 1
                    width: scene.pixel * (1.6 - index * 0.2); height: width; radius: width / 2
                    x: scene.orbC.x + Math.cos(a) * r - width / 2
                    y: scene.orbC.y + Math.sin(a) * r * 0.75 - wisp.modelData.lift * Math.max(0, life) * (1 - s) - height / 2
                    color: index === 0 ? "#ffffff" : wisp.modelData.color
                    opacity: (1 - index / 6) * Math.min(1, life * 3) * (0.6 + 0.4 * Math.sin(scene.t * 7 + wisp.modelData.a * 5))
                }
            }
        }

        // the helpers (the floor clips the medium one rising out of it)
        Item {
            x: 0; y: 0; width: scene.sw; height: scene.floorY
            clip: true
            Repeater {
                model: 6
                delegate: Item {
                    id: help
                    required property int index
                    readonly property real a0: scene.arrive(index)
                    readonly property real k: scene.seg(a0, a0 + 0.8)
                    readonly property real w0: scene.workAt(index)
                    readonly property real gone: scene.seg(scene.leaveAt(index), scene.leaveAt(index) + 0.9)
                    readonly property real lk: scene.t - scene.landAt(index)
                    readonly property real sq: lk >= 0 && lk < 0.6 ? Math.exp(-lk * 7) * Math.cos(lk * 26) * 0.3 : 0
                    readonly property real seat: scene.seatX(index)
                    readonly property bool flipped: index >= 3
                    // where it is (feet), how it arrives
                    readonly property real fx: index === 3 ? scene.glideX() : seat
                    readonly property real fy: {
                        if (index === 0) { const d = scene.clamp01(k / 0.55); return scene.floorY - (1 - d * d) * (scene.floorY + scene.ph); }
                        if (index === 1) return scene.floorY + scene.ph * (1 - scene.ease(k / 0.75));
                        if (index === 4) { const h = scene.clamp01((k - 0.25) / 0.6); return scene.floorY - Math.sin(h * Math.PI) * scene.ph * 0.8; }
                        return scene.floorY;
                    }
                    readonly property real bob: scene.t >= scene.at.full ? Math.abs(Math.sin((scene.t - scene.at.full) * 7 + index)) * scene.pixel * 4
                        : scene.t >= w0 ? scene.ps * 5 * Math.sin(Math.min(1, (scene.t - w0) / 0.35) * Math.PI) + scene.ps * 0.6 * Math.abs(Math.sin(scene.t * (4 + index)))
                        : 0
                    readonly property var work: scene.works[scene.workOf[index]]
                    readonly property int frame: {
                        if (scene.t >= scene.at.full) return Math.floor(scene.t * 6 + index) % 2 ? 5 : 4;
                        if (scene.t >= w0) return work.s + Math.floor((scene.t - w0) * work.f * (1 + 0.08 * index)) % work.n;
                        if (index === 0 && k > 0.55 && k < 0.75) return 6;
                        return k < 1 ? 0 : Math.floor(scene.t * 1.5 + index) % 2 ? 0 : 7;
                    }
                    visible: scene.t >= a0 && gone < 1 && (index !== 4 || k > 0.25)
                    opacity: 1 - scene.smooth(scene.leaveAt(index) + 0.35, scene.leaveAt(index) + 0.9)
                    x: Math.round(fx - scene.pw / 2)
                    y: Math.round(fy - scene.ph - bob - scene.ease(help.gone) * scene.ease(help.gone) * scene.floorY * 1.3)
                    width: scene.pw; height: scene.ph
                    transform: [Scale { origin.x: help.width / 2; origin.y: help.height; xScale: 1 + help.sq * 0.7 - help.gone * 0.6; yScale: 1 - help.sq + help.gone * 2.2 }, Scale { origin.x: help.width / 2; xScale: help.flipped ? -1 : 1 }]
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: scene.colorOf(help.index)
                        shadowBlur: 1
                        shadowScale: 1.04
                        shadowOpacity: help.index >= 3 ? 0.9 : 0.6
                        shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                        blurMax: 32
                        autoPaddingEnabled: true
                    }
                    Item {
                        id: body
                        anchors.fill: parent
                        readonly property var clip: scene.manifest ? scene.manifest.clone : null
                        Image {
                            anchors.fill: parent
                            source: body.clip ? Qt.resolvedUrl("sprites/" + body.clip.file) : ""
                            sourceClipRect: body.clip ? Qt.rect(help.frame * body.clip.w, 0, body.clip.w, body.clip.h) : Qt.rect(0, 0, 0, 0)
                            smooth: false
                        }
                        layer.enabled: true
                        layer.smooth: false
                        layer.effect: ShaderEffect {
                            property color uColor: help.gone > 0 || help.lk >= 0 && help.lk < 0.12 ? Qt.tint(scene.colors[help.index], Qt.rgba(1, 1, 1, 0.9)) : scene.colors[help.index]
                            property real uMode: [0, 0, 0, 1, 2, 3][help.index]
                            property real uTime: scene.t + help.index
                            property real uReveal: help.index === 2 ? scene.clamp01(help.k * 1.3) : 1
                            property size uGrid: Qt.size(scene.fw, scene.fh)
                            fragmentShader: "shaders/clone.frag.qsb"
                        }
                    }
                }
            }
        }

        // how each one comes in: rings, a portal, a pillar, sparkles
        Repeater {
            model: 6
            delegate: Item {
                id: entry
                required property int index
                readonly property real a0: scene.arrive(index)
                readonly property real k: scene.seg(a0, a0 + 0.9)
                readonly property real land: index === 0 ? a0 + 0.45 : a0 + 0.1
                readonly property real kr: scene.seg(land, land + 0.7)
                readonly property real kv: scene.seg(scene.at.vanish + index * 0.12, scene.at.vanish + index * 0.12 + 0.5)
                readonly property real sx: scene.seatX(index)
                visible: scene.t >= a0 && (k < 1 || kv > 0 && kv < 1)
                // a ring on the floor where it lands (and where it vanishes)
                Rectangle {
                    readonly property real kk: entry.kv > 0 ? entry.kv : entry.kr
                    visible: false
                    width: scene.pw * (0.6 + 2.6 * kk); height: width * 0.28
                    x: entry.sx - width / 2; y: scene.floorY - height / 2 - (entry.kv > 0 ? scene.ph * 0.5 : 0)
                    radius: height / 2
                    color: "transparent"
                    border.width: Math.max(1, scene.pixel * (1 - kk)); border.color: scene.colorOf(entry.index)
                    opacity: 1 - kk
                }
                // xhigh: speed lines behind it
                Repeater {
                    model: entry.index === 3 && entry.k < 0.85 ? 4 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property real fade: 1 - entry.k / 0.85
                        x: scene.glideX() + scene.pw * 0.45 + scene.pixel * index * 3
                        y: scene.floorY - scene.ph * (0.75 - 0.15 * index)
                        width: scene.pw * (1.8 - index * 0.3) * fade; height: scene.pixel
                        color: index % 2 ? "#ffffff" : scene.colors[3]
                        opacity: (0.85 - index * 0.15) * fade
                    }
                }
                // high: a pillar it materialises in
                Rectangle {
                    visible: entry.index === 2 && entry.k < 1
                    x: entry.sx - width / 2; y: 0; width: scene.pw * (0.9 - 0.6 * entry.k); height: scene.floorY
                    gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Qt.alpha(scene.colors[2], 0.55) } }
                    opacity: Math.sin(entry.k * Math.PI)
                }
                // medium: sparkles rising from the floor
                Repeater {
                    model: entry.index === 1 ? 14 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property real kk: entry.k * 1.4 - index * 0.04
                        visible: kk > 0 && kk < 1
                        width: scene.pixel; height: scene.pixel
                        x: entry.sx + (scene.hash(index * 3.1) - 0.5) * scene.pw * 1.3
                        y: scene.floorY - kk * scene.ph * (1.2 + scene.hash(index * 1.7))
                        color: index % 3 ? scene.colors[1] : "#ffffff"
                        opacity: 1 - kk
                    }
                }
                // max: a rainbow portal, open then closing
                Rectangle {
                    visible: entry.index === 4 && entry.k < 1
                    readonly property real o: Math.sin(Math.min(1, entry.k * 1.2) * Math.PI)
                    width: scene.pw * 1.1 * o; height: scene.ph * 1.6 * o
                    x: entry.sx - width / 2; y: scene.floorY - scene.ph * 0.8 - height / 2
                    radius: width / 2
                    color: Qt.alpha("#ffffff", 0.15 * o)
                    border.width: scene.pixel * 1.5; border.color: scene.colorOf(4)
                    rotation: scene.t * 90
                }
            }
        }

        // the slide: two burning traces where his feet scrape the floor, cooling down
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                readonly property real x0: scene.home.x + scene.dir * scene.dashD
                readonly property real x1: scene.t < scene.at.stop ? scene.me.x : scene.slideX
                readonly property real cool: scene.seg(scene.at.stop, scene.at.stop + 3.0)
                visible: scene.t >= scene.at.slide && cool < 1
                x: Math.min(x0, x1)
                y: scene.floorY - height + index * scene.ps * 1.2
                width: Math.abs(x1 - x0); height: scene.ps * (index ? 0.8 : 1.6)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: scene.dir > 0 ? "#00b48cff" : "#ffffff" }
                    GradientStop { position: 0.5; color: "#c79bff" }
                    GradientStop { position: 1; color: scene.dir > 0 ? "#ffffff" : "#00b48cff" }
                }
                opacity: (1 - cool) * (index ? 0.7 : 1)
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#b48cff"; shadowBlur: 1; shadowOpacity: 1; shadowScale: 1.1; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 24; autoPaddingEnabled: true }
            }
        }
        // particles: a trail of magic behind the dash, sparks from his feet on the slide, debris from the strike
        Repeater {
            model: scene.trail
            delegate: Rectangle {
                id: bit
                required property var modelData
                readonly property var at0: scene.bodyAt(modelData.te)
                readonly property real age: scene.tw(scene.t) - scene.tw(modelData.te)
                readonly property real k: age / modelData.life
                visible: age >= 0 && k < 1
                width: scene.pixel * modelData.size * (1 - k * 0.6); height: width
                x: at0.x - width / 2 - scene.dir * modelData.vx * age + (modelData.spark ? 0 : Math.sin(age * 6 + modelData.ph) * scene.pixel * 2)
                y: at0.y - (modelData.spark ? scene.pixel : modelData.h * scene.fh * scene.pixel) - modelData.vy * age + (modelData.spark ? 600 * age * age : -age * scene.pixel * 6) - height / 2
                color: modelData.color
                opacity: (1 - k) * (0.6 + 0.4 * Math.sin(scene.t * 20 + modelData.ph))
            }
        }
        Repeater {
            model: scene.debris
            delegate: Rectangle {
                required property var modelData
                readonly property real age: scene.t - scene.at.slam - modelData.delay
                visible: age >= 0 && age < modelData.life
                width: scene.pixel * modelData.size; height: width
                x: scene.cx + modelData.vx * age - width / 2
                y: scene.floorY - modelData.vy * age + 900 * age * age * modelData.heavy - height
                color: modelData.color
                rotation: age * modelData.spin
                opacity: 1 - age / modelData.life
            }
        }
        // motes rising around each helper while it works
        Repeater {
            model: 60
            delegate: Rectangle {
                required property int index
                readonly property int i: index % 6
                readonly property real per: 1.6 + scene.hash(index * 2.3)
                readonly property real age: scene.t - scene.workAt(i) - scene.hash(index * 7.1) * per
                readonly property real k: ((age % per) + per) % per / per
                visible: age >= 0 && scene.t < scene.at.vanish
                width: scene.pixel * (1 + scene.hash(index * 4.4)); height: width
                x: scene.seatX(i) + (scene.hash(index * 3.3) - 0.5) * scene.pw * 1.6 + Math.sin(k * 6 + index) * scene.pixel * 3
                y: scene.floorY - k * scene.sh * (0.3 + 0.4 * scene.hash(index * 5.5))
                color: index % 4 ? scene.colorOf(i, index) : "#ffffff"
                opacity: Math.sin(k * Math.PI) * 0.9
            }
        }

        // Clawd
        Item {
            id: clawd
            readonly property var clip: scene.manifest ? scene.manifest.animations.surge : null
            visible: !!clip && scene.impactPhase < 0
            x: Math.round(scene.meX); y: Math.round(scene.meY)
            width: scene.pw; height: scene.ph
            layer.enabled: scene.aura > 0.01 || scene.suck > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0.82, 0.72, 1, 1)
                shadowBlur: 1
                shadowScale: 1.03 + 0.06 * scene.aura
                shadowOpacity: Math.min(1, scene.aura + scene.suck * 0.7)
                shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                blurMax: 48
                autoPaddingEnabled: true
            }
            Image {
                anchors.fill: parent
                source: clawd.clip ? Qt.resolvedUrl("sprites/" + clawd.clip.file) : ""
                sourceClipRect: clawd.clip ? Qt.rect(Math.min(scene.me.pose, clawd.clip.frames - 1) * scene.fw, 0, scene.fw, scene.fh) : Qt.rect(0, 0, 0, 0)
                smooth: false
                transform: Scale { origin.x: scene.pw / 2; xScale: scene.flip ? -1 : 1 }
            }
        }

        // "!" over his head as he jumps
        Item {
            readonly property real k: scene.seg(0.02, 0.2)
            readonly property real u: scene.pixel * 2
            visible: scene.t < 1.7
            x: Math.round(scene.me.x - u / 2); y: Math.round(scene.meY + scene.pixel * 3 - u * 5.5)
            scale: 0.3 + 0.7 * k + 0.25 * Math.sin(k * Math.PI)
            opacity: 1 - scene.smooth(1.4, 1.7)
            Rectangle { y: 0; width: parent.u; height: parent.u * 3; color: "#fff2b8" }
            Rectangle { y: parent.u * 4; width: parent.u; height: parent.u; color: "#fff2b8" }
        }

        // the glowing wink: a four-pointed star at his closed eye
        Item {
            id: star
            readonly property real k: scene.seg(scene.at.wink + 0.15, scene.at.unwink - 0.05)
            readonly property real u: scene.ps
            visible: k > 0 && k < 1
            width: u * 12; height: u * 12
            x: scene.meX + (scene.flip ? 6.5 : 14.5) * u - width / 2; y: scene.meY + 6 * u - height / 2
            rotation: k * 90
            scale: Math.sin(k * Math.PI)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#d9c8ff"; shadowBlur: 1; shadowScale: 1.6; shadowOpacity: 1; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 32; autoPaddingEnabled: true }
            Rectangle { x: star.u; y: star.u * 5.75; width: star.u * 10; height: star.u * 0.5; color: "#ffffff" }
            Rectangle { x: star.u * 5.75; y: star.u; width: star.u * 0.5; height: star.u * 10; color: "#ffffff" }
            Rectangle { x: star.u * 4.8; y: star.u * 4.8; width: star.u * 2.4; height: width; rotation: 45; color: "#ffffff" }
        }

        // their thoughts while they work, Claude Code style (ASCII only)
        Repeater {
            model: 6
            delegate: Item {
                id: pop
                required property int index
                readonly property real w0: scene.workAt(index)
                readonly property bool arriving: scene.t >= scene.arrive(index) + 0.5 && scene.t < w0
                readonly property bool working: scene.t >= w0 && scene.t < scene.at.full
                readonly property int n: Math.floor((scene.t - w0) / 2.6)
                readonly property string verb: scene.cleanVerbs[Math.floor(scene.hash(index * 7.3 + n * 1.9) * scene.cleanVerbs.length)]
                visible: arriving || working
                opacity: arriving ? scene.seg(scene.arrive(index) + 0.5, scene.arrive(index) + 0.8) : Math.min(1, (scene.t - w0) * 4) * (1 - scene.smooth(scene.at.full - 0.15, scene.at.full))
                x: Math.round(Math.max(2, Math.min(scene.sw - width - 2, scene.seatX(index) - width / 2)))
                y: Math.round(scene.floorY - scene.ph - height - scene.pixel * 3)
                width: label.implicitWidth + scene.pixel * 4; height: label.implicitHeight + scene.pixel
                Rectangle { anchors.fill: parent; radius: height / 2; color: "#16141c"; opacity: 0.7 }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: pop.working ? "|/-\\"[Math.floor(scene.t * 8 + pop.index) % 4] + " " + pop.verb + "..." : "[" + scene.names[pop.index] + "]"
                    color: scene.colorOf(pop.index)
                    font.family: scene.mono; font.pixelSize: Math.round(scene.pixel * 4); font.bold: true
                    textFormat: Text.PlainText
                }
            }
        }

        // the weekly limit, recharging
        Item {
            id: meter
            visible: opacity > 0
            opacity: scene.smooth(scene.at.charge - 0.4, scene.at.charge) * (1 - scene.smooth(scene.at.land, scene.at.close))
            x: Math.round(scene.cx - width / 2); y: Math.round(scene.sh * 0.1)
            width: gauge.implicitWidth + scene.pixel * 6; height: gauge.implicitHeight + scene.pixel * 4
            scale: 1 + 0.5 * (scene.t >= scene.at.full ? Math.exp(-(scene.t - scene.at.full) * 3) : 0) + 0.04 * scene.smooth(scene.at.full - 1.4, scene.at.full)
            Rectangle { anchors.fill: parent; color: "#0e0c14"; opacity: 0.85 }
            Text {
                id: gauge
                anchors.centerIn: parent
                text: scene.bar(scene.charge)
                color: scene.t >= scene.at.full ? scene.rainbow[Math.floor(scene.t * 8) % 6] : "#f2ecff"
                font.family: scene.mono; font.pixelSize: Math.round(scene.pixel * 4.5); font.bold: true
                textFormat: Text.PlainText
            }
        }
    }

    // flashes, the impact frames (his silhouette on top), and the blackout that hides the way back
    Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: scene.flash }
    ShaderEffect {
        anchors.fill: parent
        visible: scene.impactPhase >= 0
        property size uSize: Qt.size(width, height)
        property real uTime: scene.t
        property point uHit: scene.impact ? scene.impact.p : scene.orbC
        property real uPix: scene.impact && scene.impact.pose === 18 ? scene.ps : scene.pixel
        property real uOrbU: -1
        property real uBoom: -1
        property real uPop: -1
        property real uImpact: scene.impactPhase % 2 ? 2 : 1
        fragmentShader: "shaders/surge.frag.qsb"
    }
    Item {
        visible: scene.impactPhase >= 0 && !!clip
        readonly property var clip: scene.manifest ? scene.manifest.animations.surge : null
        readonly property int pose: scene.impact ? scene.impact.pose : 3
        readonly property int u: pose === 18 ? scene.ps : scene.pixel
        x: scene.impact ? Math.round(scene.impact.x) : 0; y: scene.impact ? Math.round(scene.impact.y) : 0
        width: scene.fw * u; height: scene.fh * u
        Image {
            anchors.fill: parent
            source: parent.clip ? Qt.resolvedUrl("sprites/" + parent.clip.file) : ""
            sourceClipRect: parent.clip ? Qt.rect(parent.pose * scene.fw, 0, scene.fw, scene.fh) : Qt.rect(0, 0, 0, 0)
            smooth: false
        }
        layer.enabled: true
        layer.smooth: false
        layer.effect: ShaderEffect {
            property color uColor: scene.impactPhase % 2 ? "#ffffff" : "#000000"
            property real uMode: 4
            property real uTime: scene.t
            property real uReveal: 1
            property size uGrid: Qt.size(scene.fw, scene.fh)
            fragmentShader: "shaders/clone.frag.qsb"
        }
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: scene.smooth(scene.at.close, scene.at.back) * (1 - scene.smooth(scene.at.open, scene.at.end)) }

    // ── particle tables: pure functions of the index ───────────────────────────────────────────────
    readonly property var trail: {
        const out = [], pal = ["#b48cff", "#8ef0ff", "#ffffff", "#d9b8ff", "#ffd6ff"];
        for (let i = 0; i < 70; i++)   // the dash, burning magic
            out.push({ te: at.dash + (at.slide - at.dash) * i / 70, life: 0.7 + 0.6 * hash(i * 1.9), size: 1 + 1.5 * hash(i * 2.7), vx: pixel * (10 + 30 * hash(i * 3.1)),
                vy: pixel * 8 * hash(i * 4.3), h: 0.1 + 0.7 * hash(i * 5.9), ph: 6 * hash(i * 6.1), spark: false, color: pal[i % pal.length] });
        for (let i = 0; i < 60; i++)   // the slide, sparks from his feet
            out.push({ te: at.slide + (at.stop - at.slide) * Math.pow(i / 60, 1.6), life: 0.35 + 0.4 * hash(i * 7.3), size: 0.8 + hash(i * 8.1), vx: -pixel * (40 + 80 * hash(i * 9.7)),
                vy: pixel * (40 + 70 * hash(i * 1.1)), h: 0, ph: 6 * hash(i * 2.2), spark: true, color: i % 3 ? "#ffe9a8" : i % 2 ? "#ffffff" : "#c79bff" });
        return out;
    }
    readonly property var debris: {
        const out = [], pal = ["#ffffff", "#FFC107", "#4EBA65", "#B1B9F9", "#AF87FF", "#FFB38A", "#9BF6FF"];
        for (let i = 0; i < 50; i++)
            out.push({ delay: 0.25 + 0.05 * hash(i), vx: (hash(i * 3.3) - 0.5) * sw * 1.4, vy: pixel * (60 + 160 * hash(i * 4.4)), heavy: 0.5 + hash(i * 5.5),
                life: 0.9 + 0.8 * hash(i * 6.6), size: 1 + 2 * hash(i * 7.7), spin: (hash(i * 8.8) - 0.5) * 900, color: pal[i % pal.length] });
        return out;
    }
    readonly property var wisps: {
        const out = [], pal = ["#b48cff", "#8ef0ff", "#ffffff", "#d9b8ff", "#7fd0ff"];
        for (let i = 0; i < 26; i++)
            out.push({ a: hash(i * 3.7) * Math.PI * 2, r: 0.06 + 0.22 * hash(i * 5.3), w: (0.4 + 0.8 * hash(i * 2.1)) * (i % 2 ? 1 : -1), dir: i % 2 ? 1 : -1,
                lift: pixel * (2 + 6 * hash(i * 9.1)), delay: 0.05 + 0.3 * hash(i * 1.3), color: pal[i % pal.length] });
        return out;
    }
}
