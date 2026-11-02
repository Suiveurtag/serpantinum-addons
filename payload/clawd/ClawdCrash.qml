import QtQuick
import "../"

// Clawd's crash variants on one screen, a pure function of t (seconds since he froze): ClawdSingularity owns the window,
// the desktop capture and the clock. kind "bsod" is the Windows blue screen, "panic" a Linux kernel panic; both come up on
// every screen (the whole machine died), drawn by ClawdCrashScreen.
// 0.3 he freezes and the desktop freezes with him, stuttering; 1.1 the screen goes black; 1.6 the crash screen comes up
// and plays; then black again, and the live desktop fades back in over his corpse (ClawdSingularity drops it at `back`).
Item {
    id: scene
    property real t: 0
    property string kind: "bsod"
    property var manifest: null
    property Item desk: null       // the frozen desktop, any texture provider item
    property var pose: null        // unused: he is hidden while the screen is dead
    property int pixel: 4
    property real floor: height
    property bool side: false      // another screen: the same crash, no frozen desktop

    readonly property real show: 1.6
    readonly property real playing: kind === "panic" ? 14.5 : 12.0   // ClawdCrashScreen.length
    readonly property var at: ({ freeze: 0.3, cut: 1.1, show: show, back: show + playing + 0.8, end: show + playing + 1.3 })
    readonly property real groundX: width / 2

    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function seg(a, b) { return clamp01((t - a) / (b - a)); }
    function hash(n) { const s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s); }
    readonly property int frame: Math.floor(t * 24)

    visible: t >= at.freeze
    Rectangle { anchors.fill: parent; color: "black" }

    // the frozen desktop: it tears now and then, then goes
    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: scene.desk
        hideSource: true
        live: false
        visible: !!scene.desk && !scene.side && scene.t < scene.at.cut
    }
    Repeater {
        model: 5
        delegate: Rectangle {
            required property int index
            visible: !scene.side && scene.t >= scene.at.freeze + 0.25 && scene.t < scene.at.cut && scene.hash(scene.frame * 5 + index) > 0.55
            x: 0; width: scene.width
            y: scene.height * scene.hash(scene.frame + index * 17); height: 2 + 18 * scene.hash(scene.frame * 3 + index)
            color: index % 2 ? "#202020" : "#e8e8e8"
            opacity: 0.35
        }
    }

    ClawdCrashScreen {
        anchors.fill: parent
        kind: scene.kind
        t: scene.t - scene.at.show
        visible: scene.t >= scene.at.show && scene.t < scene.at.show + scene.playing
    }

    // black before the screen and after it, then the live desktop comes back
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: scene.t < scene.at.cut ? 0 : scene.t < scene.at.back ? (scene.t >= scene.at.show && scene.t < scene.at.show + scene.playing ? 0 : 1) : 1 - scene.seg(scene.at.back, scene.at.end)
    }
}
