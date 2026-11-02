import QtQuick
import QtQuick.Effects
import "../"

// The 5 h limit coming back, drawn by his overlay over the live desktop (click-through), a pure function of t (seconds
// since it started). Storyboard: animations/RECHARGE.md in the Clawd project. He slumps, drained and dark; a pixel sun
// rises behind him; gold motes swirl up from the bottom of the screen into him and fill him from the feet up while a
// terminal battery counts 5 levels; flash, shock rings, sunburst, ta-da, "5h limit reset".
Item {
    id: scene
    property real t: 0
    property var manifest: null
    property real ox: 0            // his frame's top-left, scene px
    property real oy: 0
    property int pixel: 4

    readonly property var at: ({ dawn: 0.6, charge: 1.8, full: 5.6, flare: 5.85, tada: 6.4, text: 6.7, out: 9.3, end: 10.1 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function smooth(a, b) { const k = seg(a, b); return k * k * (3 - 2 * k); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }

    readonly property var frame: manifest ? manifest.frame : { w: 21, h: 14 }
    readonly property real fw: frame.w * pixel
    readonly property real fh: frame.h * pixel
    readonly property real floor: oy + fh
    readonly property real cx: ox + fw / 2
    readonly property real cy: oy + fh * 0.55                 // the middle of his body
    readonly property real fade: 1 - smooth(at.out, at.end)   // everything but him fades out with this
    readonly property real progress: seg(at.charge, at.full)
    readonly property int level: t < at.charge ? 0 : t >= at.full ? 5 : Math.min(5, 1 + Math.floor(progress * 5))
    readonly property real levelAt: at.charge + (level - 1) / 5 * (at.full - at.charge)
    // a little hop each time a level fills
    readonly property real bump: level >= 2 && t < at.full ? pixel * 3 * Math.max(0, 1 - (t - levelAt) * 7) : 0
    readonly property real shake: t >= at.full && t < at.full + 0.35 ? Math.sin(t * 90) * pixel * (1 - seg(at.full, at.full + 0.35)) : 0

    // recharge.png: 0 drained, 1-5 filled from the feet up, 6 white, 7 cream; then tada.png; then idle's first frame
    readonly property var pose: {
        if (t < at.charge) return { strip: "recharge", i: 0 };
        if (t < at.full) return { strip: "recharge", i: level };
        if (t < at.flare) return { strip: "recharge", i: 6 };
        if (t < at.tada) return { strip: "recharge", i: 7 };
        const clip = manifest && manifest.animations.tada, n = clip ? clip.frames : 1;
        const i = Math.floor((t - at.tada) * (clip ? clip.fps : 8));
        if (t < at.out) return { strip: "tada", i: Math.min(i, n - 1) };
        return { strip: "idle", i: 0 };
    }
    readonly property real glow: t < at.charge ? 0 : t < at.full ? 0.15 + 0.45 * progress : t < at.out ? 1 - 0.7 * seg(at.full, at.out) : 0.3 * (1 - seg(at.out, at.end))

    // ── the sky: a little dim, the dawn glow climbing from the bottom edge ──────────────────────────
    Rectangle { anchors.fill: parent; color: "#10080a"; opacity: 0.3 * scene.smooth(0, scene.at.dawn + 0.6) * scene.fade }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height * 0.65 * scene.smooth(scene.at.dawn, scene.at.charge + 1.5)
        opacity: scene.fade * (0.55 + 0.45 * scene.smooth(scene.at.charge, scene.at.full))
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00ffb347" }
            GradientStop { position: 0.55; color: "#3dffb347" }
            GradientStop { position: 1.0; color: "#b0ffd56b" }
        }
    }

    // ── the pixel sun rising behind him, out of the floor line; its rays turn once he is full ───────
    Item {
        id: sky
        x: 0
        y: 0
        width: parent.width
        height: scene.floor
        clip: true
        readonly property real radius: scene.fh * 1.45
        readonly property real block: scene.pixel * 2
        readonly property real rise: scene.smooth(scene.at.dawn, scene.at.charge + 1.6)
        readonly property real sunY: scene.floor + radius - rise * radius * 1.95   // centre
        opacity: scene.fade
        Repeater {
            model: Math.ceil(2 * sky.radius / sky.block)
            delegate: Item {
                id: row
                required property int index
                readonly property real dy: (index + 0.5) * sky.block - sky.radius
                readonly property real half: Math.sqrt(Math.max(0, sky.radius * sky.radius - dy * dy))
                readonly property real inner: Math.sqrt(Math.max(0, sky.radius * sky.radius * 0.5 - dy * dy))
                y: Math.round(sky.sunY - sky.radius + index * sky.block)
                Rectangle {
                    readonly property real w: Math.max(0, Math.round(row.half / sky.block) * 2 * sky.block)
                    x: Math.round(scene.cx - w / 2); width: w; height: sky.block; color: "#ffd98a"
                }
                Rectangle {
                    readonly property real w: Math.max(0, Math.round(row.inner / sky.block) * 2 * sky.block)
                    x: Math.round(scene.cx - w / 2); width: w; height: sky.block; color: "#fff1c4"
                }
            }
        }
        Repeater {
            model: 14
            delegate: Item {
                id: ray
                required property int index
                x: scene.cx
                y: sky.sunY
                rotation: index * (360 / 14) + scene.t * 7
                opacity: scene.smooth(scene.at.full, scene.at.full + 0.45) * (index % 2 ? 0.55 : 0.9)
                Rectangle { x: sky.radius * 1.12; y: -height / 2; width: sky.radius * (index % 2 ? 0.7 : 1.3); height: scene.pixel * (index % 2 ? 1 : 2); color: "#fff2b8" }
            }
        }
    }

    // ── energy: gold motes swirl up from the bottom of the screen into him ──────────────────────────
    Repeater {
        model: scene.motes
        delegate: Rectangle {
            id: mote
            required property var modelData
            readonly property real p: scene.clamp01((scene.t - modelData.t0) / modelData.d)
            readonly property real e: p * p * (3 - 2 * p)
            visible: p > 0 && p < 1
            x: Math.round(modelData.sx + (scene.cx - modelData.sx) * e + Math.sin(p * Math.PI) * modelData.swirl)
            y: Math.round(scene.height + 8 + (scene.cy - scene.height - 8) * e - Math.sin(p * Math.PI) * modelData.arc)
            width: scene.pixel * modelData.size
            height: width
            color: modelData.color
            opacity: scene.fade * Math.min(1, p * 6) * (1 - Math.max(0, p - 0.85) / 0.15)
        }
    }
    readonly property var motes: {
        const out = [], colors = ["#ffd56b", "#fff2b8", "#ffb347", "#ffffff", "#D97757"];
        for (let i = 0; i < 90; i++)
            out.push({ t0: at.charge - 1.4 + 3.6 * hash(i * 3.1), d: 1.0 + 0.7 * hash(i * 5.7), sx: width * hash(i * 7.3),
                swirl: (hash(i * 2.2) - 0.5) * width * 0.25, arc: height * (0.05 + 0.2 * hash(i * 9.1)),
                size: hash(i * 6.6) < 0.2 ? 2 : 1, color: colors[Math.floor(hash(i * 4.4) * 5)] });
        return out;
    }

    // ── the flash and the shock rings once he is full ───────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: scene.t >= scene.at.full ? 0.8 * (1 - scene.seg(scene.at.full, scene.at.full + 0.5)) : 0 }
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            readonly property real k: scene.seg(scene.at.full + index * 0.18, scene.at.full + index * 0.18 + 1.1)
            visible: k > 0 && k < 1
            width: scene.fw * 7 * (1 - Math.pow(1 - k, 3))
            height: width
            radius: width / 2
            x: scene.cx - width / 2
            y: scene.cy - height / 2
            color: "transparent"
            border.width: scene.pixel * 2
            border.color: index === 0 ? "#fff2b8" : "#ffd56b"
            opacity: (1 - k) * scene.fade
        }
    }

    // ── a terminal battery above his head, then the verdict ─────────────────────────────────────────
    Rectangle {
        visible: label.opacity > 0
        opacity: label.opacity * 0.85
        x: label.x - scene.pixel * 2
        y: label.y - scene.pixel
        width: label.width + scene.pixel * 4
        height: label.height + scene.pixel * 2
        color: "#16141c"
    }
    Text {
        id: label
        readonly property bool done: scene.t >= scene.at.text
        visible: opacity > 0
        opacity: scene.fade * (scene.smooth(scene.at.charge - 0.4, scene.at.charge + 0.2))
        x: Math.round(scene.cx - width / 2)
        y: Math.round(scene.oy - scene.pixel * 5 - height - scene.bump)
        text: done ? "✻ 5h limit reset" : "5h [" + "█".repeat(scene.level) + "░".repeat(5 - scene.level) + "] " + scene.level * 20 + "%"
        color: done || scene.level >= 5 ? "#fff2b8" : "#ffd56b"
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Math.round(scene.pixel * 4.5)
        font.bold: true
        textFormat: Text.PlainText
    }

    // Clawd
    Item {
        id: clawd
        readonly property var clip: scene.manifest ? scene.manifest.animations[scene.pose.strip] : null
        visible: !!clip
        x: Math.round(scene.ox + scene.shake)
        y: Math.round(scene.oy - scene.bump)
        width: scene.fw
        height: scene.fh
        layer.enabled: scene.glow > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(1, 0.85, 0.45, 1)
            shadowBlur: 1
            shadowScale: 1.04 + 0.06 * scene.glow
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
