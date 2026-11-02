import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import "../"
import "js/world.mjs" as World
import "js/pc.mjs" as Pc

// One watcher and one body, independent of the per-screen surfaces. Moving the body's parent
// preserves her flight, generators, and the shared util clock across a monitor boundary.
Scope {
    id: world
    required property var engine
    property var surfaces: ({})
    property var displays: []
    property var clients: []
    property string foreground: ""
    property var foregroundClient: null
    property var pointer: null
    property string cursorBuffer: ""
    property var liveClients: []     // j/clients straight from Hyprland: its toplevel model keeps closed windows
    property string clientBuffer: ""
    property int awayChecks: 0
    property string awayScreen: ""
    property var pc: null
    property string game: ""
    property string sentForeground: "-"
    property bool subscribed: false
    readonly property bool nativeAvailable: Hyprland.requestSocketPath !== ""
    readonly property bool performanceMode: Config.getSetting("general.performance", false)
    readonly property bool pcEnabled: Config.getSetting("addonsV2CapriPcReact", true)
    readonly property var here: displays.find(d => d.id === Capri.screenName) || null
    readonly property var surface: surfaces[Capri.screenName] || null
    readonly property var cursor: World.cursor(displays, here, pointer)
    signal send(var message)

    function registerSurface(name, window) {
        const next = Object.assign({}, surfaces); next[name] = window; surfaces = next;
    }
    function unregisterSurface(name) {
        const next = Object.assign({}, surfaces); delete next[name]; surfaces = next;
    }
    function refresh() {
        if (!nativeAvailable) return;
        Hyprland.refreshMonitors();
        // Snapshot once the window list has arrived (readClients).
        if (!clientSocket.connected) clientSocket.connected = true;
    }
    function snapshot() {
        const monitors = nativeAvailable ? Hyprland.monitors.values : [];
        displays = World.monitors(Quickshell.screens, monitors);
        const minimized = {};
        if (nativeAvailable) for (const t of Hyprland.toplevels.values) if (t.wayland && t.wayland.minimized) minimized["0x" + t.address.replace(/^0x/, "")] = true;
        clients = nativeAvailable ? liveClients.map(c => Object.assign({}, c, { minimized: !!minimized[c.address] })) : [];
        foreground = Hyprland.activeToplevel ? "0x" + Hyprland.activeToplevel.address.replace(/^0x/, "") : "";
        foregroundClient = clients.find(c => c.address === foreground) || null;
        if (!displays.some(d => d.id === Capri.screenName)) {
            const saved = Config.getSetting("addonsV2CapriPosition", null);
            const preferred = Capri.screenName || (saved ? saved.screen : "");
            Capri.screenName = displays.some(d => d.id === preferred) ? preferred
                : Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : displays.length ? displays[0].id : "";
        }
        sync();
        sendForeground();
    }
    function sendForeground() {
        const c = foregroundClient;
        const key = c ? c.address + ":" + c.pid + ":" + c.class : "";
        if (key === sentForeground) return;
        sentForeground = key;
        send({ t: "foreground", pid: c ? c.pid : 0, class: c ? c.class : "", title: c ? c.title : "" });
    }
    function sync() {
        if (!engine.capri || !here) return;
        engine.setView(here.w, here.h, here.floor);
        engine.capri.setWindows(World.windows(clients, displays, here, foreground));
    }
    function moveTo(name) {
        if (!surfaces[name] || !displays.some(d => d.id === name)) return Promise.resolve(null);
        Capri.screenName = name;
        sync();
        return Promise.resolve(World.cursor(displays, here, pointer));
    }
    function goToScreen(name, toPointer = false) {
        const c = engine.capri;
        if (!c || name === Capri.screenName || !surfaces[name]) return false;
        const mid = c.screenPoint(118, 232);
        const side = [-1, 1].find(side => {
            const d = World.beyond(displays, here, side, Math.max(120, mid.y - 140));
            return d && d.id === name;
        });
        if (side && !toPointer && c.free && !performanceMode) c.leapTo(side);
        else c.jumpScreen(() => moveTo(name), { toPointer });
        return true;
    }
    function attach() {
        const c = engine.capri;
        if (!c) return;
        c.canCross = (side, y) => !!World.beyond(displays, here, side, y);
        c.onCross = (side, at) => {
            const there = World.beyond(displays, here, side, at.y);
            if (!there) return Promise.resolve(null);
            const gy = here.y + at.y;
            return moveTo(there.id).then(() => ({ y: gy - there.y }));
        };
        c.onScreenOf = cursor => c.jumpScreen(() => moveTo(cursor.display), { toPointer: true });
        pc = new Pc.Pc(c, (kind, data) => Capri.pcReaction(kind, data));
        sync();
    }
    function quiet() {
        return !Config.getSetting("notifications.dnd", false) && engine.capri && engine.capri.mode !== "alert";
    }
    function samplePc() {
        if (!pc || !pcEnabled) return;
        const online = Networking.canCheckConnectivity && Networking.connectivity !== NetworkConnectivity.Unknown ? Networking.connectivity !== NetworkConnectivity.None : null;
        pc.sample({ cpu: SysData.cpu, battery: SysNotif.hasBattery ?
            { level: SysNotif.batteryPercentage / 100, charging: SysNotif.isCharging } : null, online, game }, Date.now(), quiet());
    }
    function ingest(message) {
        if (!message || !pcEnabled) return;
        if (message.t === "device" && pc) pc.device(message.plug, Date.now(), quiet());
        if (message.t === "pc") game = typeof message.game === "string" ? message.game : "";
    }
    function subscribe() {
        if (pcEnabled && !subscribed) { SysData.subscribe(); subscribed = true; }
        else if (!pcEnabled && subscribed) { SysData.unsubscribe(); subscribed = false; }
    }
    function follow() {
        if (performanceMode) { awayChecks = 0; return; }
        const c = engine.capri;
        const elsewhere = Config.getSetting("addonsV2CapriFollow", true) && cursor && !cursor.inside && cursor.display !== null;
        awayChecks = elsewhere ? (awayScreen === cursor.display ? awayChecks + 1 : 1) : 0;
        awayScreen = elsewhere ? cursor.display : "";
        if (awayChecks < 2 || !c || !c.free || c.pointing || c.mode === "sleep" || c.mode === "alert") return;
        awayChecks = 0;
        goToScreen(cursor.display);
    }
    function savePosition() {
        const c = engine.capri;
        if (!c || !here || !c.free || c.stance !== "stand") return;
        const value = { screen: Capri.screenName, x: Math.round(c.pos.x), y: Math.round(c.pos.y) };
        const previous = Config.getSetting("addonsV2CapriPosition", null);
        if (JSON.stringify(previous) !== JSON.stringify(value)) Config.setSetting("addonsV2CapriPosition", value);
    }
    onPcEnabledChanged: {
        subscribe();
        if (!pcEnabled) { if (pc && pc.game && pc.game.put && engine.capri.stowed) engine.capri.unstow(); pc = null; game = ""; }
        else { attach(); sentForeground = "-"; sendForeground(); }
    }
    onPerformanceModeChanged: { awayChecks = 0; pointer = null; }
    onHereChanged: sync()
    Component.onCompleted: { subscribe(); snapshot(); refresh(); }
    Component.onDestruction: { if (subscribed) SysData.unsubscribe(); }

    Connections {
        target: Hyprland
        function onRawEvent(event) { world.refresh(); }
        function onActiveToplevelChanged() { world.snapshot(); }
    }
    Connections { target: Quickshell; function onScreensChanged() { world.snapshot(); world.refresh(); } }
    Connections { target: engine; function onCapriChanged() { world.attach(); } }
    // faster while she rides a window, so she keeps up with it (upstream polls every 150 ms)
    Timer {
        property int ticks: 0
        interval: 60; repeat: true; running: world.nativeAvailable
        // her stance is a JS field (no QML notification): checked on each tick
        onTriggered: if (++ticks % 4 === 0 || (world.engine.capri && world.engine.capri.stance === "sit")) world.refresh()
    }
    Timer { interval: 1000; repeat: true; running: world.pcEnabled; onTriggered: world.samplePc() }
    Timer { interval: 2000; repeat: true; running: !world.performanceMode; onTriggered: world.follow() }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: world.savePosition() }

    Process {
        // Owned directly by QML: disabling Capri kills the watcher even if node is killed abruptly.
        running: world.pcEnabled
        command: ["udevadm", "monitor", "--udev", "--property", "--subsystem-match=usb", "--subsystem-match=block"]
        stdout: SplitParser { splitMarker: "\n\n"; onRead: block => {
            const plug = World.deviceBlock(block);
            if (plug && world.pc) world.pc.device(plug, Date.now(), world.quiet());
        } }
        stderr: SplitParser { onRead: line => console.warn("Capri udev:", line) }
    }

    function readClients() {
        try {
            const list = JSON.parse(clientBuffer);
            clientBuffer = "";
            clientSocket.connected = false;
            if (!Array.isArray(list)) return;
            liveClients = list;
            snapshot();
        } catch (error) {} // The JSON may be split across reads.
    }
    Socket {
        id: clientSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { world.clientBuffer += data; world.readClients(); } }
        onConnectedChanged: {
            if (connected) { world.clientBuffer = ""; write("j/clients"); flush(); }
            else if (world.clientBuffer) world.readClients();
        }
    }

    function readCursor() {
        try {
            const p = JSON.parse(cursorBuffer);
            if (Number.isFinite(p.x) && Number.isFinite(p.y)) {
                pointer = p;
                const at = cursor;
                if (at && at.inside && engine.capri) engine.capri.notice(at.x, at.y);
            }
            cursorBuffer = "";
            cursorSocket.connected = false;
        } catch (error) {} // The JSON may be split across reads.
    }

    Socket {
        id: cursorSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { world.cursorBuffer += data; world.readCursor(); } }
        onConnectedChanged: {
            if (connected) { world.cursorBuffer = ""; write("j/cursorpos"); flush(); }
            else if (world.cursorBuffer) world.readCursor();
        }
    }
    Timer {
        interval: 100; repeat: true
        running: world.nativeAvailable && !world.performanceMode && world.engine.capri !== null
        onTriggered: {
            const c = world.engine.capri;
            if (c && !c.stowed && !c.dormant && c.mode !== "sleep" && !cursorSocket.connected) cursorSocket.connected = true;
        }
    }
}
