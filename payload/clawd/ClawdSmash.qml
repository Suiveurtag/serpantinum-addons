import QtQuick

Canvas {
    id: fx
    property bool active: false
    property real t: 1
    property real ox: 0
    property real oy: 0
    property real angle: 0
    property color color: "#D97757"
    property bool reducedMotion: false
    readonly property int life: reducedMotion ? 200 : 1000
    visible: active && t < 1
    onTChanged: if (visible) requestPaint()
    onVisibleChanged: requestPaint()

    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function ease(v) { return 1 - Math.pow(1 - clamp(v), 3); }

    // Paint in throw-local space. The positive x axis runs from the edge back along the flight path.
    function lance(c, length, breadth, fill) {
        c.save();
        c.scale(length, breadth);
        c.fillStyle = fill;
        c.beginPath();
        c.moveTo(-0.08, -0.68);
        c.lineTo(0.20, -0.82);
        c.lineTo(0.15, -0.49);
        c.lineTo(0.52, -0.56);
        c.lineTo(0.40, -0.23);
        c.lineTo(1, -0.09);
        c.lineTo(0.56, 0.13);
        c.lineTo(0.65, 0.26);
        c.lineTo(0.26, 0.24);
        c.lineTo(0.34, 0.62);
        c.lineTo(-0.08, 0.86);
        c.closePath();
        c.fill();
        c.restore();
    }

    function glint(c, x, y, rx, ry, fill) {
        c.fillStyle = fill;
        c.beginPath();
        c.moveTo(x - rx, y);
        c.quadraticCurveTo(x, y, x, y - ry);
        c.quadraticCurveTo(x, y, x + rx, y);
        c.quadraticCurveTo(x, y, x, y + ry);
        c.quadraticCurveTo(x, y, x - rx, y);
        c.fill();
    }

    onPaint: {
        const c = getContext("2d");
        c.reset();
        if (!visible) return;
        c.translate(ox, oy);
        c.rotate(angle);
        if (reducedMotion) {
            c.globalAlpha = 1 - t;
            glint(c, 8, 0, 24, 14, color);
            return;
        }

        const reach = Math.min(width * 0.78, height * 0.78, 780);
        const size = Math.min(90, reach * 0.15);
        // Hold the contact pose for two frames before opening up the beam.
        if (t < 0.24) {
            const hit = 1 - ease((t - 0.045) / 0.195);
            c.globalAlpha = hit;
            glint(c, size * 0.23, 0, size * 0.85, size, "#351929");
            glint(c, size * 0.23, 0, size * 0.69, size * 0.78, "#fff6cb");
        }

        const beat = t - 0.035;
        if (beat <= 0) return;
        const release = 1 - ease((beat - 0.16) / 0.47);
        const length = reach * (0.18 + 0.82 * ease(beat / 0.12)) * (0.45 + 0.55 * release);
        const breadth = size * (0.35 + 0.65 * ease(beat / 0.075)) * release;
        if (breadth > 0.5) {
            c.globalAlpha = Math.min(1, release * 4);
            lance(c, length, breadth, "#451c3a");
            lance(c, length * 0.98, breadth * 0.85, "#ff365e");
            lance(c, length * 0.90, breadth * 0.64, color);
            lance(c, length * 0.84, breadth * 0.46, "#ffc653");
            lance(c, length * 0.80, breadth * 0.28, "#fffbe2");
        }

        for (let i = 0; i < 2; ++i) {
            const k = (beat - 0.064 * i) / 0.43;
            if (k <= 0 || k >= 1) continue;
            c.save();
            c.translate(size * (0.3 + (0.8 + i) * ease(k)), 0);
            c.scale(0.27, 1);
            c.globalAlpha = (1 - k) * 0.95;
            c.strokeStyle = i ? "#ffb94b" : "#fff6ce";
            c.lineWidth = 2 + 8 * (1 - k);
            c.beginPath();
            c.arc(0, 0, size * (0.24 + ease(k) * (1.2 - 0.3 * i)), -1.38, 4.44);
            c.stroke();
            c.restore();
        }

        // Stagger shards and four-point stars so the last sparks outlive the silhouette.
        for (let i = 0; i < 21; ++i) {
            const k = (beat - (i % 5) * 0.018) / (0.48 + (i % 4) * 0.13);
            if (k <= 0 || k >= 1) continue;
            const a = Math.sin(i * 2.4 + 1) * (0.12 + 0.46 * ((i * 7) % 11) / 10);
            const distance = reach * (0.06 + ease(k) * (0.21 + ((i * 13) % 19) / 27));
            c.save();
            c.rotate(a);
            c.globalAlpha = Math.min(1, (1 - k) * 2);
            const radius = (1 - k) * size;
            const star = i % 4 === 0;
            glint(c, distance, 0, radius * (star ? 0.14 : 0.42),
                  radius * (star ? 0.19 : 0.035), ["#fff7d3", "#ff5472", "#ffc653"][i % 3]);
            c.restore();
        }
    }
}
