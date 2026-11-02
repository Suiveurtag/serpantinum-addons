import QtQuick
import "../"

// A dream (or a nightmare) over his sleep: drawn by his overlay under him (z -1, click-through), a pure function of t
// (seconds since the cloud was clicked). Hosts the entry's scene (js/dreams.mjs registry: entry.scene) and wraps it in
// dream.frag: an iris opening from his head, a pastel violet vignette and stars (dream), or black-red flicker and grain
// (nightmare). Storyboard: animations/DREAMS.md in the Clawd project. A new dream = a registry entry + a scene file + a line in `scenes`.
Item {
    id: host
    property real t: 0
    property var entry: null
    property var manifest: null
    property int pixel: 4
    property real ox: 0             // his frame's top-left on the desktop, scene px
    property real oy: 0
    property real floorY: height
    property real seed: 0
    readonly property bool nightmare: !!entry && entry.kind === "nightmare"
    readonly property bool reduced: typeof Clawd !== "undefined" && Clawd.lowMotion
    readonly property real duration: entry ? entry.duration : 1
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    // in over 1.2 s; out over 1.2 s (a nightmare cuts to black faster, its jumpscare is near the end)
    readonly property real fade: Math.min(ease(t / 1.2), ease((duration - t) / (nightmare ? 0.35 : 1.2)))
    readonly property real open: nightmare ? 1 : ease(t / 1.5)
    // his head while he lies asleep (row ~8 of his 21x14 frame)
    readonly property point head: Qt.point(ox + 10.5 * pixel, oy + 8 * pixel)

    readonly property var scenes: ({ ClawdDreamSurf: surf, ClawdNightmareGemini: gemini })
    Component { id: surf; ClawdDreamSurf { t: host.t; manifest: host.manifest; pixel: host.pixel; ox: host.ox; oy: host.oy; floorY: host.floorY; seed: host.seed; reduced: host.reduced } }
    Component { id: gemini; ClawdNightmareGemini { t: host.t; manifest: host.manifest; pixel: host.pixel; ox: host.ox; oy: host.oy; floorY: host.floorY; seed: host.seed; reduced: host.reduced } }

    Loader {
        anchors.fill: parent
        active: host.visible && !!host.entry
        sourceComponent: host.entry ? host.scenes[host.entry.scene] || null : null
    }

    layer.enabled: visible
    layer.effect: ShaderEffect {
        property real uTime: host.t
        property real uFade: host.fade
        property real uMood: host.nightmare ? 1 : 0
        property real uWobble: host.reduced ? 0 : 1
        property point uCenter: Qt.point(host.head.x / Math.max(1, host.width), host.head.y / Math.max(1, host.height))
        property real uOpen: host.open
        property real uAspect: host.width / Math.max(1, host.height)
        fragmentShader: "shaders/dream.frag.qsb"
    }
}
