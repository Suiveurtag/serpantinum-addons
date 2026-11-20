import QtQuick

// The blast KO (a fighting-game screen-out): from the point (ox, oy) where a throw sent him off the screen, a narrow
// jet of light needles shoots back in (angle, rad), white at the root and his colour further out, over a small pop and
// a shock ring at the edge; sparks ride it out, the needles thin and fade from the root. t runs 0 -> 1 over `life` ms.
Canvas {
    id: fx
    property bool active: false
    property real t: 1
    property real ox: 0
    property real oy: 0
    property real angle: 0
    property color color: "#D97757"
    readonly property int life: 1150
    property var needles: []
    property var sparks: []
    visible: active && t < 1
    onActiveChanged: if (active) seed()
    onTChanged: if (visible) requestPaint()
    onVisibleChanged: requestPaint()

    function seed() {
        const n = [], s = [];
        for (let i = 0; i < 22; i++) {
            const a = (Math.random() + Math.random() - 1) * 0.24;  // bunched toward the axis
            n.push({ a: a, l: 0.55 + 0.45 * (1 - Math.abs(a) / 0.24) * (0.7 + Math.random() * 0.3), w: 5 + Math.random() * 11, d: Math.random() * 70 });
        }
        for (let i = 0; i < 16; i++) s.push({ a: (Math.random() - 0.5) * 0.5, v: 0.5 + Math.random() * 0.7, r: 1.5 + Math.random() * 2.5, d: Math.random() * 120 });
        needles = n.sort((p, q) => q.w - p.w);  // wide ones first, the thin bright ones on top
        sparks = s;
    }
    function ease(v) { return 1 - Math.pow(1 - Math.max(0, Math.min(1, v)), 3); }
    function rgba(a) { return Qt.rgba(color.r, color.g, color.b, Math.max(0, Math.min(1, a))); }
    function white(a) { return Qt.rgba(1, 1, 1, Math.max(0, Math.min(1, a))); }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (!visible || !needles.length) return;
        const ms = t * life, reach = Math.min(width, height) * 0.48, fade = t < 0.5 ? 1 : 1 - Math.pow((t - 0.5) / 0.5, 1.5);
        const shake = t < 0.2 ? 4 * (1 - t / 0.2) : 0;
        ctx.save();
        ctx.translate(ox + (Math.random() - 0.5) * shake * 2, oy + (Math.random() - 0.5) * shake * 2);
        ctx.rotate(angle);
        ctx.globalCompositeOperation = "lighter";

        // the pop at the edge
        if (t < 0.35) {
            const r = 70 * ease(t / 0.06) * (1 - t / 0.35) + 1, g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
            g.addColorStop(0, white(0.95));
            g.addColorStop(0.4, rgba(0.7));
            g.addColorStop(1, rgba(0));
            ctx.fillStyle = g;
            ctx.fillRect(-r, -r, 2 * r, 2 * r);
        }
        // the shock ring, squashed along the jet
        if (t < 0.5) {
            const k = t / 0.5, r = 18 + 110 * ease(k);
            ctx.save();
            ctx.scale(0.4, 1);
            ctx.strokeStyle = white(0.8 * (1 - k));
            ctx.lineWidth = 6 * (1 - k) + 1;
            ctx.beginPath();
            ctx.arc(0, 0, r, 0, 2 * Math.PI);
            ctx.stroke();
            ctx.restore();
        }
        // the needles: each shoots out (90 ms), stretches a little more, thins and fades from the root outward
        for (const n of needles) {
            const grow = ease((ms - n.d) / 90);
            if (grow <= 0) continue;
            const len = reach * n.l * grow * (1 + 0.18 * t), w = n.w * (1 - 0.75 * t), root = len * Math.max(0, (t - 0.3) / 0.7) * 0.8;
            const ca = Math.cos(n.a), sa = Math.sin(n.a), px = -sa * w / 2, py = ca * w / 2;
            const g = ctx.createLinearGradient(root * ca, root * sa, len * ca, len * sa);
            g.addColorStop(0, white(0.95 * fade));
            g.addColorStop(0.25, rgba(0.9 * fade));
            g.addColorStop(1, rgba(0));
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.moveTo(root * ca + px, root * sa + py);
            ctx.lineTo(len * ca, len * sa);
            ctx.lineTo(root * ca - px, root * sa - py);
            ctx.closePath();
            ctx.fill();
        }
        // sparks riding the jet out
        for (const p of sparks) {
            const k = (ms - p.d) / (life - p.d);
            if (k <= 0) continue;
            const d = reach * (0.1 + ease(k) * p.v), x = Math.cos(p.a) * d, y = Math.sin(p.a) * d, r = p.r * (1 - k);
            ctx.fillStyle = k < 0.4 ? white(1 - k) : rgba(1 - k);
            ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
        }
        ctx.restore();
    }
}
