import QtQuick
import "../"

// The nightmares "Blue screen" and "Kernel panic": the crashed machine of his limit scene (ClawdCrashScreen, kind "bsod" or
// "panic") with the words of a bad dream: the % stops at 99, the kernel tries to kill init. A pure function of t (12.5 s),
// hosted by ClawdDream. 0-0.7 dark static; 0.7 the screen comes up and plays; 9.5-11.6 it flickers, black frames, shaking
// harder; 11.6 the jumpscare: red-white flash and the screen slams (the overlay makes him jolt awake); then black.
Item {
    id: scene
    property real t: 0
    property string kind: "bsod"
    property var manifest: null
    property int pixel: 4
    property real ox: 0
    property real oy: 0
    property real floorY: height
    property real seed: 0
    property bool reduced: false

    readonly property var at: ({ screen: 0.7, flicker: 9.5, jump: 11.6, slam: 11.72, black: 11.95, end: 12.5 })
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function ease(k) { k = clamp01(k); return k * k * (3 - 2 * k); }
    function smooth(a, b) { return ease(seg(a, b)); }
    function hash(n) { const s = Math.sin(n * 127.1 + scene.seed * 3.1) * 43758.5453; return s - Math.floor(s); }

    readonly property int frame: Math.floor(t * 24)
    readonly property bool cut: t >= at.flicker && t < at.jump && hash(Math.floor(t * 9)) < 0.3 * seg(at.flicker, at.jump)
    readonly property real shake: reduced ? 0 : t >= at.jump ? height * 0.04 * (1 - seg(at.jump, at.end)) : height * 0.006 * seg(at.flicker, at.jump)
    readonly property real flash: t >= at.jump ? 1 - seg(at.jump, at.black) : 0

    Rectangle { anchors.fill: parent; color: "#050003" }
    Item {
        id: world
        width: parent.width; height: parent.height
        x: (scene.hash(scene.frame) - 0.5) * 2 * scene.shake
        y: (scene.hash(scene.frame + 51) - 0.5) * 2 * scene.shake
        scale: scene.t >= scene.at.jump ? 1 + 0.5 * scene.ease(scene.seg(scene.at.jump, scene.at.slam)) : 1
        visible: scene.t >= scene.at.screen && !scene.cut && scene.t < scene.at.black + 0.1
        ClawdCrashScreen {
            anchors.fill: parent
            kind: scene.kind
            nightmare: true
            seed: scene.seed
            reduced: scene.reduced
            t: scene.t - scene.at.screen
        }
    }
    // the red tear lines when it flickers
    Repeater {
        model: 6
        delegate: Rectangle {
            required property int index
            visible: !scene.reduced && scene.t >= scene.at.flicker && scene.t < scene.at.jump && scene.hash(scene.frame * 7 + index) > 0.6
            x: 0; width: scene.width
            y: scene.height * scene.hash(scene.frame + index * 11); height: 2 + 14 * scene.hash(scene.frame * 3 + index)
            color: "#E0101A"; opacity: 0.4
        }
    }
    Rectangle { anchors.fill: parent; color: scene.t < scene.at.jump + 0.05 ? "#FFF2F0" : "#E0101A"; opacity: scene.flash * (scene.reduced ? 0.6 : 0.85) }
    Rectangle { anchors.fill: parent; color: "black"; opacity: scene.smooth(scene.at.black, scene.at.end) }
}
