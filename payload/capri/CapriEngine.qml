import QtQuick
import "../"
import "js/util.mjs" as Util
import "js/acting.mjs" as Acting
import "js/fx.mjs" as Fx
import "js/chip.mjs" as Forms
import "js/capri.mjs" as Body

// Capri on one screen: her body, the full-screen fx layer, her mask and biochip, all driven by
// js/capri.mjs (the upstream behaviour, ported). The same engine travels between screens.
Item {
    id: engine
    // what takes the pointer (CapriOverlay's input region): her body, and her mask or biochip when shown
    readonly property alias hitbox: hitbox
    readonly property alias maskBox: maskCanvas
    readonly property alias chipBox: chipCanvas
    readonly property alias brain: brain
    readonly property alias voice: voice
    readonly property var cutins: ["grin", "laugh", "eyes", "many", "look"]
    readonly property var cels: ["grab", "mouth1", "mouth2", "mouth3", "wave1", "wave2", "wave3", "smear", "happy"]
    readonly property var images: cutins.map(k => asset("cutin-" + k + ".png"))
        .concat(cels.map(k => asset("intro-" + k + ".webp")))
        .concat(["paper", "ink", "violet"].map(k => asset("intro-flat-" + k + ".png")))
        .concat(["r", "g", "b"].map(k => asset("intro-channel-" + k + ".webp")))
    readonly property real configuredScale: Config.getSetting("addonsV2CapriScale", 0.6)
    onConfiguredScaleChanged: if (capri) capri.setScale(configuredScale)
    property var world: null
    property var capri: null
    property var fx: null
    property var mask: null
    property var chip: null

    function asset(name) { return Qt.resolvedUrl("assets/" + name).toString(); }

    // The IPC "act" command: one of her moves, else an act from acting.mjs ("gaze" and "fall" are both: the move wins).
    function act(name, arg) {
        if (!capri) return "not ready";
        switch (name) {
        case "screen": return world && world.goToScreen(arg, true) ? "ok" : "unavailable";
        case "world": return JSON.stringify({ screen: Capri.screenName, displays: world ? world.displays : [],
            windows: capri.windows, cursor: world ? world.cursor : null, game: world ? world.game : "" });
        case "sit": { const seat = capri.pickSeat(); if (!seat) return "no seat"; capri.sitOn(seat); return "ok"; }
        case "possess": return capri.canPossess() ? (capri.possess({ say: arg || "" }), "ok") : "unavailable";
        case "teleport": capri.teleport(capri.spot(arg || "random")); return "ok";
        case "intro": capri.intro(capri.spot("post"), arg === "still" ? { still: true } : {}); return "ok";
        case "gaze": capri.gaze({ big: arg === "big" }); return "ok";
        case "mode": capri.setMode(arg || "idle"); return "ok";
        case "throw": { const v = String(arg).split(","); capri.throwHer(+v[0] || 0, +v[1] || 0); return "ok"; }
        case "state": return JSON.stringify({ stance: capri.stance, mode: capri.mode, busy: capri.busy, hidden: capri.hidden,
            stowed: capri.stowed, dormant: capri.dormant, act: capri.act ? capri.act.player.name : null, fx: fx.items.length,
            screen: Capri.screenName, perch: capri.perch, x: Math.round(capri.pos.x), y: Math.round(capri.pos.y) });
        case "celebrate": case "hurt": case "doze": case "rouse": case "stow": case "unstow": case "peek": case "fall":
        case "wanderStep": case "flourish": case "shed": case "twitch": case "spark": case "materialize": case "goHome": case "goToWork": case "unpeek": case "drop": case "drain": case "recharge":
            capri[name](name === "materialize" ? capri.spot("post") : undefined); return "ok";
        }
        const answer = brain.command(name, arg);
        if (answer !== "unknown") return answer;
        if (!Acting.ACTS[name]) return "unknown";
        capri.perform(name, capri.towardCenter());
        return "ok";
    }

    function start() {
        if (capri || !fxCanvas.available || !maskCanvas.available || !chipCanvas.available) return;
        for (const url of images) if (!fxCanvas.isImageLoaded(url)) return;
        Util.reducedMotion.matches = !Capri.animationEnabled;
        Util.storage.getItem = key => Config.getSetting("addonsV2CapriState." + key, null);
        Util.storage.setItem = (key, value) => Config.setSetting("addonsV2CapriState." + key, value);
        const intro = {};
        cels.forEach(k => intro[k] = asset("intro-" + k + ".webp"));
        const shots = {};
        cutins.forEach(k => shots[k] = asset("cutin-" + k + ".png"));
        fx = new Fx.FxLayer(fxCanvas, { cutins: shots, intro });
        fx.resize(width, height);
        mask = new Forms.Mask(maskCanvas);
        chip = new Forms.Chip(chipCanvas);
        chip.place(width, height);
        capri = new Body.Capri({ fx, voice: { play: (cue, opts) => voice.play(cue, opts) }, host: {
            width, height,
            draw: p => pet.draw(p),
            resize: scale => pet.scale = scale,
            setHidden: hidden => pet.visible = !hidden,
            place: t => {
                pet.place(t);
                hitbox.x = t.box.x; hitbox.y = t.box.y; hitbox.width = t.box.w; hitbox.height = t.box.h;
            },
        } });
        setView(width, height, world && world.here ? world.here.floor : height);
        capri.setScale(Config.getSetting("addonsV2CapriScale", 0.6));
        capri.chipAt = () => chip.center();
        capri.onStow = () => { chip.setMode(capri.mode); chip.show(); Config.setSetting("addonsV2CapriStowed", true); };
        capri.onUnstow = () => { chip.hide(); Config.setSetting("addonsV2CapriStowed", false); };
        capri.onMode = mode => chip.setMode(mode);
        capri.onDoze = (phase, face) => {
            if (phase === "start") { mask.place(face.x, face.y, capri.scale * 1.1); mask.show(); }
            else if (phase === "waking") mask.wake();
            else mask.hide();
        };
        if (Config.getSetting("addonsV2CapriStowed", false)) capri.stowNow();
        else {
            const saved = Config.getSetting("addonsV2CapriPosition", null);
            const to = saved && saved.screen === Capri.screenName ? {
                x: Util.clamp(saved.x, 60, width - 60), y: Util.clamp(saved.y, 440 * capri.scale, capri.floor)
            } : capri.spot("post");
            capri.intro(to);
        }
    }

    function setView(w, h, floor) {
        if (!capri || (capri.view.w === w && capri.view.h === h && capri.view.floor === floor)) return;
        fx.resize(w, h);
        chip.place(w, floor);
        capri.setView(w, h, floor);
    }

    Component.onCompleted: images.forEach(url => fxCanvas.loadImage(url))
    Component.onDestruction: Util.reset()

    Connections {
        target: Capri
        function onAnimationEnabledChanged() { Util.reducedMotion.matches = !Capri.animationEnabled; }
        function onCommand(name, arg) { Capri.reply = engine.act(name, arg); }
    }

    // The clock for everything in js/: timeouts, tweens, her drawings, the fx frames.
    Timer {
        interval: 16
        repeat: true
        running: engine.capri !== null
        onTriggered: Util.pump()
    }

    CapriVoice { id: voice }
    CapriBrain { id: brain; engine: engine }

    CapriPet {
        id: pet
        dpr: Screen.devicePixelRatio
    }

    Canvas {
        id: fxCanvas
        anchors.fill: parent
        onAvailableChanged: engine.start()
        onImageLoaded: engine.start()
    }

    Canvas {
        id: maskCanvas
        visible: false
        width: 140; height: 170
        onAvailableChanged: engine.start()
        // her mask, asleep: the pointer over it stirs her, and a moment of that wakes her up
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => { if (engine.mask) engine.mask.pointer = { x: maskCanvas.x + mouse.x, y: maskCanvas.y + mouse.y }; }
            onEntered: wake.restart()
            onExited: { wake.stop(); if (engine.mask) engine.mask.pointer = null; }
            Timer { id: wake; interval: 400; onTriggered: if (engine.capri && engine.capri.dormant) engine.capri.wake() }
        }
    }

    Canvas {
        id: chipCanvas
        visible: false
        width: 140; height: 170
        onAvailableChanged: engine.start()
        // her biochip: her eyes twitch under the pointer, a click brings her back out
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: mouse => { if (engine.chip) engine.chip.pointer = { x: chipCanvas.x + mouse.x, y: chipCanvas.y + mouse.y }; }
            onExited: if (engine.chip) engine.chip.pointer = null
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => { if (mouse.button === Qt.RightButton) brain.openMenu(); else if (engine.capri) engine.capri.unstow(); }
        }
    }

    // Her bounding box (the input region is rectangles): the alpha test happens in pointerDown.
    MouseArea {
        id: hitbox
        visible: pet.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        function at(mouse) { return mapToItem(engine, mouse.x, mouse.y); }
        onPressed: mouse => {
            const p = at(mouse);
            if (!engine.capri) return;
            if (mouse.button === Qt.RightButton) engine.capri.contextMenu(p.x, p.y);
            else mouse.accepted = engine.capri.pointerDown(p.x, p.y);
        }
        onPositionChanged: mouse => { const p = at(mouse); if (engine.capri) engine.capri.pointerMove(p.x, p.y); }
        onReleased: if (engine.capri) engine.capri.pointerUp()
        onCanceled: if (engine.capri) engine.capri.pointerUp()
    }
}
