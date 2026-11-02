import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

// Clawd at his limit, one window per screen above everything (even fullscreen windows) while pet.blast is set: the
// singularity (ClawdBlast) or the nuclear variant (ClawdNuke), blast.kind. His screen: once he froze and hid from it, its
// desktop is captured and the scene's clock starts (pet.blast.clock); the frozen screen takes clicks, Escape skips to the
// end, where his corpse falls back onto the live desktop (pet.reappear). Other screens only darken, flash and come back.
PanelWindow {
    id: win
    required property var pet
    readonly property var blast: pet.blast
    readonly property var here: pet.display(screen.name)
    readonly property bool main: !!blast && blast.screen === screen.name
    readonly property bool nuke: !!blast && blast.kind === "nuke"
    readonly property Item scene: nuke ? nukeScene : blastScene
    property bool running: false
    property bool armed: false     // capture requested
    property bool returned: false
    visible: running
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-addon-clawd-blast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: main && scene.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: scene.visible ? scene : null }

    onBlastChanged: if (!blast) { running = false; armed = false; } else if (!running) begin()
    Component.onCompleted: if (blast) begin()
    function begin() {
        armed = false;
        returned = false;
        blastScene.t = 0;   // only the running scene's clock moves: the other one stays hidden
        nukeScene.t = 0;
        running = true;
        if (blast.screen === screen.name) prelude.restart();  // not main: its binding may not have caught up with blast yet
    }
    function skip() {
        if (main && blast && blast.clock && scene.t < scene.at.back) pet.blastClock(Date.now() - scene.at.back * 1000);
    }

    // He froze; a moment later the screen does: hide him, capture without him, start the clock at the freeze.
    Timer { id: prelude; interval: win.nuke ? 250 : 900; onTriggered: { win.pet.blastHidden = true; capture.restart(); } }
    Timer { id: capture; interval: 60; onTriggered: { win.armed = true; fallback.restart(); } }
    Timer { id: fallback; interval: 1500; onTriggered: win.go() }  // no capture: the scene runs on black
    function go() {
        fallback.stop();
        if (main && blast && !blast.clock) pet.blastClock(Date.now() - scene.at.freeze * 1000);
    }
    // a fresh capture for every blast
    Loader {
        id: shot
        anchors.fill: parent
        active: win.armed
        sourceComponent: ScreencopyView {
            captureSource: win.screen
            live: false
            paintCursor: false
            onHasContentChanged: if (hasContent && win.armed) win.go()
        }
    }

    FrameAnimation {
        running: win.running
        onTriggered: {
            const clock = win.blast ? win.blast.clock : 0;
            if (clock) win.scene.t = (Date.now() - clock) / 1000;
            // his corpse comes back where he went off: the middle of the screen, or ground zero
            if (win.main && !win.returned && win.scene.t >= win.scene.at.back + 0.05) {
                win.returned = true;
                win.pet.reappear(win.here ? win.here.x + (win.nuke ? nukeScene.groundX : win.width / 2) : undefined);
            }
            if (win.scene.t >= win.scene.at.end) {
                win.running = false;
                win.armed = false;
                if (win.main) win.pet.blastDone();
            }
        }
    }

    ClawdBlast {
        id: blastScene
        anchors.fill: parent
        manifest: Clawd.manifest
        desk: shot.item
        side: !win.main
        pixel: win.blast ? win.blast.scale : Clawd.scale
        pose: !win.nuke && win.blast && win.here ? { x: win.blast.x - win.here.x, y: win.blast.y - win.here.y, animation: win.blast.animation, frame: win.blast.frame, mirrored: win.blast.mirrored } : null
        focus: !win.nuke
        Keys.onEscapePressed: win.skip()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }
    ClawdNuke {
        id: nukeScene
        anchors.fill: parent
        manifest: Clawd.manifest
        desk: shot.item
        side: !win.main
        pixel: win.blast ? win.blast.scale : Clawd.scale
        floor: win.here ? win.here.floor - win.here.y : height
        pose: win.nuke && win.blast && win.here ? { x: win.blast.x - win.here.x, y: win.blast.y - win.here.y, animation: win.blast.animation, frame: win.blast.frame, mirrored: win.blast.mirrored } : null
        focus: win.nuke
        Keys.onEscapePressed: win.skip()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }
}
