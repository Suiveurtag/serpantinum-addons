import QtQuick
import QtQuick.Effects

// Clawd brought back to life, drawn by his overlay over the live desktop (click-through), a pure function of t (seconds
// since it started). Storyboard: animations/NUKE.md in the Clawd project. A spotlight comes down on his corpse, holy powder
// falls on it, the corpse floats up glowing, turns white, bursts back into himself, drops down and goes ta-da.
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property real ox: 0            // his frame's top-left where he lies, scene px
    property real oy: 0
    property int pixel: 4

    readonly property var at: ({ beam: 0.4, powder: 1.2, lift: 3.4, white: 4.6, burst: 5.4, down: 6.2, land: 6.9, open: 8.3, out: 8.4, end: 9.2 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }

    readonly property var frame: manifest ? manifest.frame : { w: 21, h: 14 }
    readonly property real fw: frame.w * pixel
    readonly property real fh: frame.h * pixel
    readonly property real floor: oy + fh
    readonly property real cx: ox + fw / 2
    // how high the corpse floats: up, a slow hover, then a drop back to the floor
    readonly property real lift: {
        const top = fh * 2.6;
        if (t < at.lift) return 0;
        if (t < at.down) return top * smooth(at.lift, at.burst) + Math.sin((t - at.lift) * 2.4) * pixel * smooth(at.lift, at.lift + 1);
        if (t < at.land) { const k = seg(at.down, at.land); return (top + Math.sin((at.down - at.lift) * 2.4) * pixel) * (1 - k * k); }
        return 0;
    }
    // revive.png: 0 grey, 1 lit rim, 2 pale, 3 cream with a glowing core, 4 white, 5-9 standing again from white to orange,
    // 10 eyes open; tada.png from the landing
    readonly property var pose: {
        if (t < at.land) {
            if (t < at.powder + 0.8) return { strip: "revive", i: 0 };
            if (t < at.lift) return { strip: "revive", i: t < at.powder + 1.5 ? 1 : 2 };
            if (t < at.white) return { strip: "revive", i: 3 };
            if (t < at.burst) return { strip: "revive", i: 4 };
            return { strip: "revive", i: Math.min(9, 5 + Math.floor((t - at.burst) / 0.2)) };
        }
        const clip = manifest && manifest.animations.tada, n = clip ? clip.frames : 1;
        const i = Math.floor((t - at.land) * (clip ? clip.fps : 8));
        if (i < n) return { strip: "tada", i };
        return t < at.open ? { strip: "tada", i: n - 1 } : { strip: "revive", i: 10 };
    }
    readonly property real glow: t < at.powder ? 0 : t < at.burst ? 0.2 + 0.8 * smooth(at.powder, at.white) : t < at.land ? 1 - 0.7 * seg(at.burst, at.land) : 0.3 * (1 - seg(at.land, at.end))

    // ── light: dim, the beam, his halo, the burst, the sunburst ─────────────────────────────────────
    ShaderEffect {
        anchors.fill: parent
        property size uSize: Qt.size(width, height)
        property real uSpotX: scene.cx
        property real uFloor: scene.floor
        property real uWidth: scene.fw * 1.4
        property real uTime: scene.t
        property real uDim: scene.smooth(0, scene.at.beam + 0.4) * (1 - scene.smooth(scene.at.out, scene.at.end))
        property real uBeam: scene.smooth(scene.at.beam, scene.at.powder) * (1 - 0.6 * scene.smooth(scene.at.land, scene.at.end)) * (1 - scene.smooth(scene.at.out, scene.at.end))
        property point uGlowC: Qt.point(scene.cx, scene.floor - scene.lift - scene.fh * 0.35)
        property real uGlow: scene.glow
        property real uBurst: scene.t >= scene.at.burst && scene.t < scene.at.land ? scene.fw * 5 * (1 - Math.exp(-(scene.t - scene.at.burst) * 3)) : -1
        property real uRays: scene.t >= scene.at.land ? scene.smooth(scene.at.land, scene.at.land + 0.35) * (1 - scene.smooth(scene.at.out, scene.at.end)) : 0
        fragmentShader: "shaders/revive.frag.qsb"
    }

    // the smoke over his corpse thins out as the light reaches him
    Image {
        readonly property var strip: scene.manifest ? scene.manifest.smoke : null
        visible: !!strip && opacity > 0
        opacity: 1 - scene.smooth(scene.at.beam, scene.at.powder + 1)
        x: Math.round(scene.cx - width / 2)
        y: Math.round(scene.oy + 9 * scene.pixel - height)
        width: strip ? strip.w * scene.pixel : 0
        height: strip ? strip.h * scene.pixel : 0
        source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
        sourceClipRect: strip ? Qt.rect(Math.floor(scene.t * strip.fps) % strip.frames * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
        smooth: false
    }

    // holy powder: gold, cream and white grains falling down the beam onto him, twinkling, some of them little crosses
    Repeater {
        model: scene.grains
        delegate: Item {
            id: grain
            required property var modelData
            readonly property real k: scene.t - modelData.t0
            readonly property real landY: scene.floor - scene.lift - scene.fh * 0.45
            readonly property real gy: -20 + k * modelData.v
            visible: k >= 0 && gy < landY
            x: Math.round(scene.cx + modelData.dx * scene.fw * (0.35 + 0.65 * gy / Math.max(1, scene.floor)) + Math.sin(k * 3 + modelData.ph) * scene.pixel * 2)
            y: Math.round(gy)
            opacity: 0.55 + 0.45 * Math.abs(Math.sin(k * modelData.tw + modelData.ph))
            Rectangle { x: -width / 2; y: -height / 2; width: scene.pixel; height: width; color: grain.modelData.color }
            Rectangle { visible: grain.modelData.star; x: -width / 2; y: -height / 2; width: scene.pixel * 3; height: Math.max(1, scene.pixel / 2); color: grain.modelData.color }
            Rectangle { visible: grain.modelData.star; x: -width / 2; y: -height / 2; width: Math.max(1, scene.pixel / 2); height: scene.pixel * 3; color: grain.modelData.color }
        }
    }
    readonly property var grains: {
        const out = [], colors = ["#ffd56b", "#fff2b8", "#ffffff", "#f0eee6"];
        for (let i = 0; i < 80; i++)
            out.push({ t0: at.powder - 0.6 + 2.6 * hash(i * 3.1), v: height * (0.45 + 0.35 * hash(i * 5.7)), dx: (hash(i * 7.3) - 0.5) * 1.6,
                ph: 6 * hash(i * 2.2), tw: 4 + 8 * hash(i * 9.1), color: colors[Math.floor(hash(i * 4.4) * 4)], star: hash(i * 6.6) < 0.18 });
        return out;
    }

    // Clawd
    Item {
        id: clawd
        readonly property var clip: scene.manifest ? scene.manifest.animations[scene.pose.strip] : null
        visible: !!clip
        x: Math.round(scene.ox)
        y: Math.round(scene.oy - scene.lift)
        width: scene.fw
        height: scene.fh
        layer.enabled: scene.glow > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(1, 0.9, 0.6, 1)
            shadowBlur: 1
            shadowScale: 1.05 + 0.06 * scene.glow
            shadowOpacity: Math.min(1, scene.glow * 1.2)
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 40
            autoPaddingEnabled: true
        }
        Image {
            anchors.fill: parent
            source: clawd.clip ? Qt.resolvedUrl("sprites/" + clawd.clip.file) : ""
            sourceClipRect: clawd.clip ? Qt.rect(Math.min(scene.pose.i, clawd.clip.frames - 1) * scene.frame.w, 0, scene.frame.w, scene.frame.h) : Qt.rect(0, 0, 0, 0)
            smooth: false
            mipmap: false
        }
    }
}
