import QtQuick
import QtQuick.Effects

// Independent of the desktop engine and its shared JS clock. Draws at 24 fps like fx.js, most motion on twos.
Item {
    id: art
    enabled: false
    Accessible.ignored: true
    required property Item host
    required property Item bandMask
    readonly property var faces: ["capri-icon", "face-laugh", "face-wide", "face-many", "face-smug"]
    readonly property real k: host.rootObj.s(1)
    readonly property real cx: host.faceX + host.faceSide / 2
    readonly property real cy: host.height / 2
    property int frame: 0
    property int face: 0
    property int glitchUntil: -1
    readonly property bool glitch: frame < glitchUntil
    property var shards: []
    property var wedges: []
    property var bursts: []

    function rnd(a, b) { return a + Math.random() * (b - a); }
    function pick(list) { return list[Math.floor(Math.random() * list.length)]; }
    function burst() {
        for (let i = 0; i < 26; i++) {
            const a = rnd(0, Math.PI * 2), v = rnd(220, 680) * k;
            bursts.push({x: cx, y: cy, vx: Math.cos(a) * v, vy: Math.sin(a) * v, rot: rnd(0, 6), vr: rnd(-9, 9),
                len: rnd(10, 36) * k, wid: rnd(3, 10) * k, color: pick(["#ff2152", "#ff2152", "#ff2152", "#14101c", "#36ff7a", "#fff4f6"]), born: frame, life: Math.round(rnd(6, 15))});
        }
        glitchUntil = frame + 6;
    }
    function step() {
        frame++;
        // cut to the next face every ~3.6 s with a hard glitch, a smaller twitch half-way
        if (frame % 86 === 0) { face = (face + 1) % faces.length; glitchUntil = frame + 5; }
        else if (frame % 86 === 43) glitchUntil = frame + 2;
        if (frame % 5 === 0 && shards.length < 16) {
            const a = rnd(-Math.PI * 0.85, -Math.PI * 0.35);
            shards.push({x: cx + rnd(-0.3, 0.3) * host.faceSide, y: cy - host.faceSide * 0.2, vx: Math.cos(a) * rnd(16, 34) * k * 2,
                vy: Math.sin(a) * rnd(16, 34) * k * 2 - 10 * k, len: rnd(9, 20) * k * 1.4, wid: rnd(3, 6) * k * 1.3, rot: a,
                color: pick(["#ff2152", "#ff2152", "#ff2152", "#14101c", "#fff4f6"]), born: frame, life: Math.round(rnd(46, 70))});
        }
        shards = shards.filter(s => frame - s.born < s.life);
        bursts = bursts.filter(s => frame - s.born < s.life);
        if (frame % 2 === 0) {
            const next = [], inner = host.height * 0.5;
            for (let i = 0; i < 30; i++)
                next.push({a: rnd(0, Math.PI * 2), half: rnd(0.008, 0.026), tip: inner * rnd(1, 1.6), color: pick(["#fff4f6", "#fff4f6", "#fff4f6", "#7b3dff", "#ff2152"])});
            wedges = next;
        }
        fx.requestPaint();
    }
    Timer { interval: 42; repeat: true; running: art.visible; onTriggered: art.step() }
    Component.onCompleted: if (Date.now() - host.ignitedAt < 600) burst()

    // the cut-in band: ink, face zooming slowly, red/violet misregistered copies while glitching
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: art.bandMask }
        Rectangle { anchors.fill: parent; color: "#120c1c" }
        Repeater {
            model: ["#7d3af5", "#ff245d", ""]
            Image {
                required property int index
                required property string modelData
                readonly property real zoom: 1 + 0.08 * (art.frame % 86) / 86
                readonly property real shake: art.glitch ? ((art.frame * 7) % 9 - 4) * art.k : 0
                width: art.host.faceSide * zoom; height: width
                x: art.cx - width / 2 + shake + (modelData === "" ? 0 : (index ? -8 : 8) * art.k * (art.glitch ? 1.6 : 0.5))
                y: art.cy - height / 2 + Math.round(Math.sin(Math.floor(art.frame / 2) / 6) * 3) * art.k + (index === 0 ? 4 * art.k : 0)
                source: Qt.resolvedUrl("assets/" + art.faces[art.face] + ".png"); sourceSize: Qt.size(art.host.faceSide, art.host.faceSide)
                z: modelData === "" ? 1 : 0
                smooth: true; mipmap: true
                visible: modelData === "" || art.glitch || index === 0
                opacity: modelData === "" ? 1 : art.glitch ? 0.85 : 0.5
                layer.enabled: modelData !== ""
                layer.effect: MultiEffect { colorization: 1; colorizationColor: modelData || "black" }
            }
        }
    }

    Canvas {
        id: fx
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        function band(c) {
            const h = art.host;
            c.beginPath(); c.moveTo(h.bandX, 0); c.lineTo(width, 0); c.lineTo(width, height); c.lineTo(h.bandX - h.skew, height); c.closePath();
        }
        function shard(c, s, len, dx, dy, color) {
            c.save(); c.translate(s.x + dx, s.y + dy); c.rotate(s.rot); c.fillStyle = color;
            c.beginPath(); c.moveTo(-len / 2, 0); c.lineTo(0, -s.wid / 2); c.lineTo(len / 2, s.wid * 0.15); c.lineTo(-len * 0.1, s.wid / 2); c.closePath(); c.fill();
            c.restore();
        }
        function sparkle(c, x, y, s, fill) {
            c.fillStyle = fill; c.beginPath();
            for (let i = 0; i < 8; i++) {
                const r = i % 2 ? s * 0.24 : s, a = i * Math.PI / 4 - Math.PI / 2;
                if (i) c.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); else c.moveTo(x + Math.cos(a) * r, y + Math.sin(a) * r);
            }
            c.closePath(); c.fill();
        }
        onPaint: {
            const c = getContext("2d"), k = art.k, f = art.frame;
            c.reset();
            // manga focus lines around her face, kept inside the band
            c.save(); band(c); c.clip();
            c.globalAlpha = 0.5;
            const base = height * 1.8;
            for (const w of art.wedges) {
                c.fillStyle = w.color; c.beginPath();
                c.moveTo(art.cx + Math.cos(w.a) * w.tip, art.cy + Math.sin(w.a) * w.tip);
                c.lineTo(art.cx + Math.cos(w.a - w.half) * base, art.cy + Math.sin(w.a - w.half) * base);
                c.lineTo(art.cx + Math.cos(w.a + w.half) * base, art.cy + Math.sin(w.a + w.half) * base);
                c.closePath(); c.fill();
            }
            // speed bars sliding through the cut-in
            c.globalAlpha = 0.7;
            for (let i = 0; i < 9; i++) {
                const y = (i * 37 + 11) % height, len = (30 + (i * 23) % 80) * k;
                c.fillStyle = i % 3 ? "#ff2152" : "#fff4f6";
                c.fillRect(width - ((f * (10 + i * 3) * k + i * 97) % (width - art.host.bandX + art.host.skew + len)), y, len, (1 + i % 3) * k);
            }
            c.restore();
            c.globalAlpha = 1;
            // red top bar of the cut-in
            c.fillStyle = "#ff2152";
            c.beginPath(); c.moveTo(art.host.bandX, 0); c.lineTo(width, 0); c.lineTo(width, 4 * k); c.lineTo(art.host.bandX - art.host.skew * 4 * k / height, 4 * k); c.closePath(); c.fill();
            // mane shards drift up and across the card, moved on twos
            for (const s of art.shards) {
                const t = (Math.floor((f - s.born) / 2) * 2) / s.life, age = (f - s.born) * 0.042;
                const p = {x: Math.round(s.x + s.vx * age), y: Math.round(s.y + s.vy * age), rot: s.rot, wid: s.wid * (t > 0.6 ? (1 - t) / 0.4 : 1)};
                const len = s.len * (t > 0.6 ? (1 - t) / 0.4 : 1);
                shard(c, p, len, -2 * k, 2 * k, "#7b3dff");
                shard(c, p, len, 0, 0, s.color);
            }
            // ignition burst
            for (const s of art.bursts) {
                const t = (f - s.born) / s.life, age = (f - s.born) * 0.042, drag = (1 - Math.pow(0.86, f - s.born)) / 0.14 / 24;
                const p = {x: s.x + s.vx * drag, y: s.y + s.vy * drag, rot: s.rot + s.vr * age, wid: s.wid * (t > 0.7 ? (1 - t) / 0.3 : 1)};
                const len = s.len * (t > 0.7 ? (1 - t) / 0.3 : 1);
                shard(c, p, len, -2 * k, 2 * k, "#7b3dff");
                shard(c, p, len, 0, 0, s.color);
            }
            if (art.bursts.length) {
                const step = Math.min(5, f - art.bursts[0].born) / 6, r = (40 + 230 * step) * k, lw = Math.max(1, 8 * (1 - step) * k);
                c.lineWidth = lw;
                c.strokeStyle = "#7b3dff"; c.beginPath(); c.arc(art.cx - 3 * k, art.cy + 3 * k, r, 0, Math.PI * 2); c.stroke();
                c.strokeStyle = "#ff2152"; c.beginPath(); c.arc(art.cx, art.cy, r, 0, Math.PI * 2); c.stroke();
            }
            // green sparkles twinkling on threes
            const sizes = [6, 9, 5, 10];
            [[0.18, 0.2], [0.82, 0.3], [0.5, 0.85]].forEach((p, i) => {
                const x = art.host.bandX - art.host.skew / 2 + (width - art.host.bandX + art.host.skew / 2) * p[0], y = height * p[1];
                const s = sizes[(Math.floor(f / 3) + i) % 4] * k;
                sparkle(c, x - 2 * k, y + 2 * k, s, "#7b3dff");
                sparkle(c, x, y, s, "#36ff7a");
                sparkle(c, x, y, s * 0.36, "#14101c");
            });
            // glitch slices across the whole card
            if (art.glitch) {
                c.globalAlpha = 0.9;
                for (let i = 0; i < 7; i++) {
                    c.fillStyle = art.pick(["#ff2152", "#36ff7a", "#7b3dff", "#fff4f6"]);
                    c.fillRect(art.rnd(-0.3, 0.6) * width, art.rnd(0, height), art.rnd(0.3, 1.1) * width * 0.5, art.rnd(2, 7) * k);
                }
            }
        }
    }
}
