import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../"

// Full-screen transparent surface; input reaches only Clawd and his menu, the rest of the desktop stays clickable.
PanelWindow {
    id: overlay
    required property var pet
    property var brain: null
    readonly property var here: pet.display(screen.name)
    readonly property bool menuHere: pet.menuOpen && Clawd.screenName === screen.name
    readonly property bool chatHere: pet.chatOpen && Clawd.chat && Clawd.screenName === screen.name
    readonly property bool journalHere: pet.journalOpen && Clawd.screenName === screen.name && !menuHere && !chatHere
    readonly property bool petHere: !!here && pet.width > 0 && pet.x < here.x + here.w && pet.x + pet.width > here.x
        && pet.y < here.y + here.h && pet.y + pet.height > here.y
    readonly property bool exploding: pet.blasting && petHere   // ClawdSingularity draws him meanwhile
    readonly property bool reviving: pet.mode === "revive" && Clawd.screenName === screen.name
    readonly property bool recharging: pet.mode === "recharge" && Clawd.screenName === screen.name
    readonly property bool symphonic: pet.mode === "weekly" && Clawd.screenName === screen.name
    readonly property bool surging: pet.mode === "surge" && Clawd.screenName === screen.name
    readonly property bool dreaming: (pet.mode === "dream" || pet.mode === "nightmare") && Clawd.screenName === screen.name
    readonly property alias thought: thought
    readonly property alias frameBox: frameBox
    readonly property alias viewport: viewport
    readonly property alias hitBox: hitBox
    readonly property alias revival: revival
    readonly property alias recharge: recharge
    readonly property alias symphony: symphony
    readonly property alias surge: surge
    readonly property alias dreamScene: dreamScene
    readonly property alias dreamBubble: dreamBubble
    readonly property alias menu: menu
    readonly property alias chat: chat
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: menuHere || chatHere
    WlrLayershell.namespace: "qs-addon-clawd"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (menuHere || chatHere) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        Region { item: hitBox.visible ? hitBox : null }
        Region { item: menu.visible ? menu : null }
        Region { item: bubble.visible ? bubble : null }
        Region { item: dreamBubble.visible ? dreamBubble : null }
        Region { item: journal.visible ? journal : null }
        Region { item: chat.visible ? chat : null }
    }

    // frameBox = his whole frame, the anchor of everything around him; viewport = the part of it you see: minus what
    // pet.cover hides while he peeks from behind a window (a fake z-order: his layer is above every window).
    Item {
        id: frameBox
        // the press keeps its surface (Wayland implicit grab): stay mapped here while dragged onto another screen
        visible: (overlay.petHere || hit.pressed) && !overlay.pet.blastHidden
        x: overlay.here ? Math.round(overlay.pet.x - overlay.here.x) : 0
        y: overlay.here ? Math.round(overlay.pet.y - overlay.here.y) : 0
        width: body.implicitWidth
        height: body.implicitHeight
    }
    Item {
        id: viewport
        readonly property int hideL: Math.round(Math.max(0, Math.min(frameBox.width, overlay.pet.cut.l)))
        readonly property int hideR: Math.round(Math.max(0, Math.min(frameBox.width - hideL, overlay.pet.cut.r)))
        visible: frameBox.visible && width > 0
        x: frameBox.x + hideL
        y: frameBox.y
        width: frameBox.width - hideL - hideR
        height: frameBox.height
        clip: hideL > 0 || hideR > 0

        ClawdSprite {
            id: body
            x: -viewport.hideL
            width: implicitWidth
            height: implicitHeight
            visible: !overlay.reviving && !overlay.recharging && !overlay.symphonic && !overlay.surging   // the scenes draw him meanwhile
            animation: overlay.pet.animation
            mirrored: overlay.pet.mirrored
            reverse: overlay.pet.reverse
            running: false
            frame: overlay.pet.frame
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            preventStealing: true
            cursorShape: overlay.pet.dead && !pressed ? Qt.ArrowCursor : pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            function at(mouse) {
                const p = mapToItem(overlay.contentItem, mouse.x, mouse.y);
                return Qt.point(p.x + overlay.here.x, p.y + overlay.here.y);
            }
            onPressed: mouse => { const p = at(mouse); overlay.pet.press(mouse.button, p.x, p.y); }
            onPositionChanged: mouse => { const p = at(mouse); overlay.pet.move(p.x, p.y); }
            onReleased: mouse => { if (mouse.button === Qt.LeftButton) { const p = at(mouse); overlay.pet.release(p.x, p.y); } }
            onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) overlay.pet.doubleClick(); }
            onCanceled: overlay.pet.release()
        }
    }

    // The petpet hand: a photo strip over Clawd, frame-locked to his petpet strips (same frame count, sprites.py).
    Image {
        readonly property var strip: Clawd.manifest && Clawd.manifest.hand || null
        visible: !!strip && viewport.visible && overlay.pet.animation.startsWith("petpet")
        x: frameBox.x - 3 * Clawd.scale
        y: frameBox.y - 6 * Clawd.scale
        width: 16 * Clawd.scale
        height: strip ? Math.round(width * strip.h / strip.w) : 0
        source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
        sourceClipRect: strip ? Qt.rect(overlay.pet.frame % strip.frames * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
    }

    // Smoke rising from his corpse, drawn above it on his pixel grid.
    Image {
        id: smoke
        readonly property var strip: Clawd.manifest && Clawd.manifest.smoke || null
        property int frame: 0
        visible: !!strip && viewport.visible && overlay.pet.mode === "dead"
        x: frameBox.x + Math.round((frameBox.width - width) / 2)
        y: frameBox.y + 9 * Clawd.scale - height
        width: strip ? strip.w * Clawd.scale : 0
        height: strip ? strip.h * Clawd.scale : 0
        source: strip ? Qt.resolvedUrl("sprites/" + strip.file) : ""
        sourceClipRect: strip ? Qt.rect(frame % strip.frames * strip.w, 0, strip.w, strip.h) : Qt.rect(0, 0, 0, 0)
        smooth: false
        Timer { interval: smoke.strip ? 1000 / smoke.strip.fps : 166; repeat: true; running: smoke.visible; onTriggered: smoke.frame++ }
    }

    // His dream (or nightmare) over his sleep, under him: click-through (not in the mask). The registry entry says how long it
    // lasts and when a nightmare's jumpscare makes him jolt awake; its end puts him back to sleep, or wakes him sweating.
    ClawdDream {
        id: dreamScene
        property bool jolted: false
        z: -1
        anchors.fill: parent
        visible: overlay.dreaming && !!overlay.here
        entry: overlay.pet.dream ? overlay.pet.dream.entry : null
        seed: overlay.pet.dream ? overlay.pet.dream.seed : 0
        manifest: Clawd.manifest
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        floorY: overlay.here ? overlay.here.floor - overlay.here.y : height
        onVisibleChanged: jolted = false
        FrameAnimation {
            running: dreamScene.visible
            onTriggered: {
                const e = dreamScene.entry;
                if (!e) return;
                dreamScene.t = (Date.now() - overlay.pet.dreamAt) / 1000;
                if (e.jump !== undefined && !dreamScene.jolted && dreamScene.t >= e.jump) { dreamScene.jolted = true; overlay.pet.jolt(); }
                if (dreamScene.t >= e.duration) overlay.pet.dreamed();
            }
        }
    }

    // His revival over the live desktop: click-through (not in the mask); its end brings him back.
    ClawdRevive {
        id: revival
        anchors.fill: parent
        visible: overlay.reviving && !!overlay.here
        manifest: Clawd.manifest
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        FrameAnimation {
            running: revival.visible
            onTriggered: {
                revival.t = (Date.now() - overlay.pet.reviveAt) / 1000;
                if (revival.t >= revival.at.end) overlay.pet.revived();
            }
        }
    }

    // The 5 h limit coming back: same idea, he stands where he is; its end gives him back to his life.
    ClawdRecharge {
        id: recharge
        anchors.fill: parent
        visible: overlay.recharging && !!overlay.here
        manifest: Clawd.manifest
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        FrameAnimation {
            running: recharge.visible
            onTriggered: {
                recharge.t = (Date.now() - overlay.pet.rechargeAt) / 1000;
                if (recharge.t >= recharge.at.end) overlay.pet.recharged();
            }
        }
    }

    // The weekly reset: a whole concert over the desktop, the curtains first; its end gives him back to his life.
    ClawdSymphony {
        id: symphony
        anchors.fill: parent
        visible: overlay.symphonic && !!overlay.here
        manifest: Clawd.manifest
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        floorY: overlay.here ? overlay.here.floor - overlay.here.y : height
        FrameAnimation {
            running: symphony.visible
            onTriggered: {
                symphony.t = (Date.now() - overlay.pet.weeklyAt) / 1000;
                if (symphony.t >= symphony.at.end) overlay.pet.weeklied();
            }
        }
    }

    // The weekly limit, superpowered: a capture of the desktop for the bulging corner, the workspace switch during his dash;
    // its end leaves him in the middle of his screen, back on the workspace he left.
    Loader {
        id: surgeShot
        active: overlay.surging && surge.t < surge.at.burst + 1.5
        sourceComponent: ScreencopyView { x: -overlay.width * 2; width: overlay.width; height: overlay.height; captureSource: overlay.screen; live: false; paintCursor: false }
    }
    // The dash zoom: the compositor's own live zoom, parked on him (scripts/clawd/surge_zoom.py restores everything).
    Process {
        id: surgeZoom
        command: ["python3", "-u", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/clawd/surge_zoom.py"]
        running: overlay.surging && surge.t >= surge.at.dash - 0.5 && surge.t < surge.at.fast + 0.3
        stdinEnabled: true
        property bool ready: false
        stdout: SplitParser { onRead: data => { if (data.indexOf("ready") >= 0) { surgeZoom.ready = true; surge.nativeZoom = true; } } }
        onRunningChanged: if (!running) { ready = false; surge.nativeZoom = false; }
    }
    ClawdSurge {
        id: surge
        property bool away: false
        anchors.fill: parent
        visible: overlay.surging && !!overlay.here
        manifest: Clawd.manifest
        desk: surgeShot.item
        verbs: Clawd.verbs
        pixel: Clawd.scale
        ox: frameBox.x
        oy: frameBox.y
        floorY: overlay.here ? overlay.here.floor - overlay.here.y : height
        onVisibleChanged: { away = false; if (visible) seed = Math.random(); }
        FrameAnimation {
            running: surge.visible
            onTriggered: {
                surge.t = (Date.now() - overlay.pet.surgeAt) / 1000;
                if (surgeZoom.ready && overlay.here)
                    surgeZoom.write(JSON.stringify({ f: surge.zoomFactor, x: overlay.here.x + surge.me.x, y: overlay.here.y + surge.me.y }) + "\n");
                if (!surge.away && surge.t >= surge.at.swap && surge.t < surge.at.back) { surge.away = true; overlay.pet.surgeWorkspace(true); }
                if (surge.away && surge.t >= surge.at.back) { surge.away = false; overlay.pet.surgeWorkspace(false); }
                if (surge.t >= surge.at.end) overlay.pet.surged(overlay.here.x + overlay.width / 2);
            }
        }
    }

    // Region tracks only its item's own geometry, never a moving parent's, so mirror the viewport here.
    Item { id: hitBox; x: viewport.x; y: viewport.y; width: viewport.width; height: viewport.height; visible: viewport.visible }

    ClawdBubble {
        id: bubble
        anchor: frameBox
        visible: !!Clawd.bubble && overlay.petHere && !overlay.menuHere && !overlay.journalHere && !overlay.exploding && !overlay.surging
    }

    // The cloud of a dream waiting for a click (in the mask: the click opens it).
    ClawdDreamBubble {
        id: dreamBubble
        pet: overlay.pet
        anchor: frameBox
        visible: overlay.pet.mode === "sleep" && overlay.pet.dreamPhase === "bubble" && !!overlay.pet.dream && overlay.petHere && !overlay.menuHere && !overlay.journalHere && !overlay.chatHere
    }

    // Above his head while an agent works, or what he mumbles in his sleep; deliberately not in the mask: clicks go through it.
    ClawdThought {
        id: thought
        anchor: frameBox
        say: overlay.pet.mumble
        visible: (Clawd.thinking || !!overlay.pet.mumble && Clawd.thoughts !== "off") && !dreamBubble.visible && overlay.petHere && !bubble.visible && !overlay.menuHere && !overlay.journalHere && !overlay.exploding && !overlay.pet.dead && !overlay.recharging && !overlay.symphonic && !overlay.surging
    }

    ClawdJournal {
        id: journal
        pet: overlay.pet
        anchor: frameBox
        visible: overlay.journalHere && !overlay.exploding
    }

    // Several agents busy at once: how many, beside his head.
    Text {
        visible: frameBox.visible && Clawd.busyCount >= 2 && !overlay.exploding && !overlay.pet.dead && !overlay.surging
        x: frameBox.x + frameBox.width - width
        y: frameBox.y + 2 * Clawd.scale - height / 2
        text: "[" + Clawd.busyCount + "]"
        color: ThemeBackend.peach
        font.family: ThemeBackend.fontFamily; font.pixelSize: Math.round(Scaler.s(12)); font.bold: true
    }

    ClawdChat {
        id: chat
        pet: overlay.pet
        brain: overlay.brain
        anchor: frameBox
        visible: overlay.chatHere && !overlay.exploding
    }

    ClawdMenu {
        id: menu
        pet: overlay.pet
        anchor: frameBox
        visible: overlay.menuHere
    }

    HyprlandFocusGrab { windows: [overlay]; active: overlay.menuHere || overlay.chatHere; onCleared: { overlay.pet.menuOpen = false; overlay.pet.chatOpen = false; } }
    Component.onCompleted: Clawd.mounted()
    Component.onDestruction: Clawd.unmounted()
}
