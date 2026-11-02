import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"
import "js/world.mjs" as World

// What Clawd knows of the desktop, in global logical px; the only owner of his Hyprland sockets (windows, cursor).
// Windows come from the raw socket (j/clients): Hyprland.toplevels keeps closed windows. Polled every 240 ms (60 ms
// while he rides a window), plus filtered raw events; low motion: events + a 3 s heartbeat; asleep: events only.
// Without Hyprland (fixtures) inject({clients, monitors, screens, pointer}) feeds the same path.
Scope {
    id: world
    property var pet: null
    readonly property bool hypr: Hyprland.requestSocketPath !== ""
    readonly property bool live: Clawd.world
    readonly property bool asleep: !!pet && pet.asleep
    property var fake: null            // injected {clients, monitors, screens}
    property var clients: []           // last j/clients
    property bool fed: false           // clients arrived at least once since the world was turned on
    property var wins: []              // World.windows: on screen, front first
    property var ledges: []            // World.ledges: window tops + one floor per display
    property var pointer: null         // global cursor
    property int refreshes: 0          // snapshots taken (IPC state, debugging)
    property var shown: ({})           // id -> rect of the windows on screen at the last snapshot
    property var mapped: ({})          // id -> rect of every mapped window (open/close, whatever the workspace)
    property string focused: ""
    property var spaces: ({})          // display -> active workspace
    property bool primed: false        // first snapshot taken: later differences are events
    property var layerRects: []        // World.layers rects (global px): the shell's layer surfaces
    property var widgets: []           // the widgets among them (5d)
    property bool redact: false        // the shell's widget editor is on: widgets are not ledges
    property int resyncs: 0            // WidgetSync-driven layer refetches (IPC state, tests)
    property var openLayers: []        // "monitor|namespace" of the layers that have a kind (bar popups, launcher...)
    property bool layersPrimed: false  // j/layers answered once: later differences are events
    property var bars: ({})            // display -> {x, y, w}: the bar's underside, where he can hang
    property var sides: ({})           // display -> World.sides: window edges he can climb
    property var fullscreen: ({})      // display -> true while a fullscreen window covers it
    property string clientBuffer: ""
    property string layerBuffer: ""
    property string cursorBuffer: ""
    // events that never move a window (the Claude Code spinner rewrites the kitty title all the time)
    readonly property var ignored: ["windowtitle", "windowtitlev2", "activelayout", "submap", "bell", "screencast", "screencastv2"]
    readonly property var displays: {
        const native = fake && fake.monitors ? fake.monitors : hypr ? Hyprland.monitors.values.map(m => ({ name: m.name, x: m.x, y: m.y,
            activeWorkspace: m.activeWorkspace ? { id: m.activeWorkspace.id } : null, lastIpcObject: m.lastIpcObject })) : [];
        const screens = fake && fake.screens ? fake.screens : Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height }));
        return World.monitors(screens, native);
    }
    signal windowOpened(string id, var rect)
    signal windowClosed(string id, var rect)
    signal focusMoved(string id)
    signal workspaceSwitched(string monitor)
    signal layerOpened(string ns, string monitor)
    signal layerClosed(string ns, string monitor)
    signal updated()
    readonly property var rawBar: fake && fake.bar !== undefined ? fake.bar : Config.rawSettings && Config.rawSettings.bar || null

    function win(id) { return wins.find(w => w.id === id) || null; }
    function ledge(id) { return ledges.find(l => l.id === id) || null; }
    function setRedact(on) { if (redact === !!on) return; redact = !!on; Qt.callLater(snapshot); }
    function sideOf(id, side) { for (const k of Object.keys(sides)) { const s = sides[k].find(s => s.id === id && s.side === side); if (s) return s; } return null; }

    // One j/clients request at a time; readClients() takes the snapshot.
    function fetch() { if (hypr && live && !clientSocket.connected) { clientSocket.connected = true; fetchGuard.restart(); } }
    function kick() { if (live && !debounce.running) debounce.start(); }

    function snapshot() {
        refreshes++;
        const ds = displays;
        let next = [];
        if (live) {
            const minimized = {};
            if (hypr) for (const t of Hyprland.toplevels.values) if (t && t.address && t.wayland && t.wayland.minimized) minimized["0x" + t.address.replace(/^0x/, "")] = true;
            next = World.windows(clients, ds, minimized);
        }
        const byId = {}, all = {};
        for (const w of next) byId[w.id] = { x: w.x, y: w.y, w: w.w, h: w.h, display: w.display };
        if (live) for (const c of clients) if (c && c.address && c.at && c.size && c.mapped !== false) all[c.address] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] };
        const front = live ? clients.find(c => c && c.focusHistoryID === 0) : null;
        const focus = front ? front.address : "";
        const ws = {};
        for (const d of ds) ws[d.id] = d.workspace;
        if (JSON.stringify(next) !== JSON.stringify(wins)) wins = next;
        const flat = World.ledges({ wins: next, widgets: redact ? [] : widgets, displays: ds, petW: pet ? pet.width : 0, petH: pet ? pet.height : 0 });
        if (JSON.stringify(flat) !== JSON.stringify(ledges)) ledges = flat;
        const fs = {}, bs = {}, sd = {};
        if (live) for (const c of clients) if (c && c.fullscreen && byId[c.address]) fs[byId[c.address].display] = true;
        for (const d of ds) {
            const b = live ? World.bar(d, rawBar, { rects: layerRects }, !!fs[d.id]) : null;
            if (b) bs[d.id] = b;
            sd[d.id] = live ? World.sides(next, d, pet ? pet.height : 0) : [];
        }
        if (JSON.stringify(fs) !== JSON.stringify(fullscreen)) fullscreen = fs;
        if (JSON.stringify(bs) !== JSON.stringify(bars)) bars = bs;
        if (JSON.stringify(sd) !== JSON.stringify(sides)) sides = sd;
        const was = { shown, mapped, focused, spaces, primed };
        shown = byId; mapped = all; focused = focus; spaces = ws;
        primed = live && fed;
        if (was.primed && primed) {
            // a window really opened or closed (not just another workspace showing up), and only the visible ones
            const change = World.diff(was.mapped, all);
            for (const id of change.opened) if (byId[id]) windowOpened(id, byId[id]);
            for (const c of change.closed) if (was.shown[c.id]) windowClosed(c.id, was.shown[c.id]);
            if (focus && focus !== was.focused && byId[focus]) focusMoved(focus);
            for (const d of ds) if (was.spaces[d.id] !== undefined && was.spaces[d.id] !== d.workspace) workspaceSwitched(d.id);
        }
        updated();
    }

    // Fixtures only: plays Hyprland. Returns false when the real one is there.
    function inject(data) {
        if (hypr || !data) return false;
        const next = Object.assign({}, fake || {});
        for (const k of ["monitors", "screens", "bar"]) if (data[k] !== undefined) next[k] = data[k];
        fake = next;
        if (data.pointer !== undefined) pointer = data.pointer;
        if (Array.isArray(data.clients)) { clients = data.clients; fed = true; }
        if (data.layers !== undefined) applyLayers(data.layers);
        snapshot();
        return true;
    }

    onLiveChanged: {
        primed = false;
        fed = !hypr && clients.length > 0;
        layersPrimed = false;
        if (!live) { layerRects = []; widgets = []; openLayers = []; }
        Qt.callLater(snapshot);
        fetch();
        fetchLayers();
    }
    onDisplaysChanged: Qt.callLater(snapshot)
    Component.onCompleted: { snapshot(); fetch(); }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event || world.ignored.indexOf(event.name) >= 0) return;
            world.kick();
            if (/^(openlayer|closelayer|monitor)/.test(event.name) && world.live && !layerDebounce.running) layerDebounce.start();
        }
    }
    // Widgets moved, added, removed or restyled: j/layers again once their windows have settled (450 ms); the widget editor hides the ledges.
    Connections {
        target: typeof WidgetSync !== "undefined" ? WidgetSync : null
        ignoreUnknownSignals: true
        function onGeometryChanged() { widgetSync.restart(); }
        function onPositionChanged() { widgetSync.restart(); }
        function onVariantChanged() { widgetSync.restart(); }
        function onWidgetAdded() { widgetSync.restart(); }
        function onWidgetRemoved() { widgetSync.restart(); }
        function onWidgetsByTypeRemoved() { widgetSync.restart(); }
        function onWidgetsCleared() { widgetSync.restart(); }
        function onPresetApplied() { widgetSync.restart(); }
        function onRedactModeChanged(monitor, active) { world.setRedact(active); widgetSync.restart(); }
    }
    Timer { id: widgetSync; interval: 450; onTriggered: { world.resyncs++; world.fetchLayers(); } }
    Connections {
        target: world.pet
        function onHeightChanged() { Qt.callLater(world.snapshot); }
    }
    // Hyprland never answered: drop the socket so the next fetch can start
    Timer { id: fetchGuard; interval: 2000; onTriggered: { clientSocket.connected = false; world.clientBuffer = ""; } }
    // a burst of events -> one fetch
    Timer { id: debounce; interval: 40; onTriggered: world.fetch() }
    Timer {
        interval: world.pet && world.pet.riding ? 60 : 240; repeat: true
        running: world.hypr && world.live && !!world.pet && !Clawd.lowMotion && !world.asleep
        onTriggered: world.fetch()
    }
    // the shell's layers (bar popups, launcher...): on layer and monitor events and every 2 s
    Timer { id: layerGuard; interval: 2000; onTriggered: { layerSocket.connected = false; world.layerBuffer = ""; } }
    Timer { id: layerDebounce; interval: 40; onTriggered: world.fetchLayers() }
    Timer { interval: 2000; repeat: true; running: world.hypr && world.live && !!world.pet; onTriggered: world.fetchLayers() }
    // low motion; or asleep on a window, so he still falls if it is dragged away
    Timer {
        interval: 3000; repeat: true
        running: world.hypr && world.live && !!world.pet && (Clawd.lowMotion || world.asleep && !!world.pet.support)
        onTriggered: world.fetch()
    }

    function readClients() {
        try {
            const list = JSON.parse(clientBuffer);
            clientBuffer = "";
            clientSocket.connected = false;
            fetchGuard.stop();
            if (!Array.isArray(list)) return;
            clients = list;
            fed = true;
            snapshot();
        } catch (error) { if (clientBuffer.length > 8388608) { clientBuffer = ""; clientSocket.connected = false; } } // The JSON may be split across reads.
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

    function fetchLayers() { if (hypr && live && !layerSocket.connected) { layerSocket.connected = true; layerGuard.restart(); } }
    // A j/layers answer (or an injected one): rects, widgets, and what opened or closed since the last one.
    function applyLayers(json) {
        const l = World.layers(json, displays);
        const keys = [...new Set(l.rects.filter(r => World.layerKind(r.ns)).map(r => r.display + "|" + r.ns))];
        const was = openLayers, first = !layersPrimed, moved = JSON.stringify(l.rects) !== JSON.stringify(layerRects);
        layersPrimed = true;
        if (JSON.stringify(l.widgets) !== JSON.stringify(widgets)) widgets = l.widgets;
        if (JSON.stringify(keys) !== JSON.stringify(was)) openLayers = keys;
        if (moved) { layerRects = l.rects; Qt.callLater(snapshot); }
        if (first) return;
        const split = k => [k.slice(k.indexOf("|") + 1), k.slice(0, k.indexOf("|"))];
        for (const k of keys) if (was.indexOf(k) < 0) layerOpened(split(k)[0], split(k)[1]);
        for (const k of was) if (keys.indexOf(k) < 0) layerClosed(split(k)[0], split(k)[1]);
    }
    function readLayers() {
        try {
            const json = JSON.parse(layerBuffer);
            layerBuffer = "";
            layerSocket.connected = false;
            layerGuard.stop();
            applyLayers(json);
        } catch (error) { if (layerBuffer.length > 8388608) { layerBuffer = ""; layerSocket.connected = false; } } // The JSON may be split across reads.
    }
    Socket {
        id: layerSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { world.layerBuffer += data; world.readLayers(); } }
        onConnectedChanged: {
            if (connected) { world.layerBuffer = ""; write("j/layers"); flush(); }
            else if (world.layerBuffer) world.readLayers();
        }
    }

    function readCursor() {
        try {
            const p = JSON.parse(cursorBuffer);
            if (Number.isFinite(p.x) && Number.isFinite(p.y)) pointer = { x: p.x, y: p.y };
            cursorBuffer = "";
            cursorSocket.connected = false;
        } catch (error) { if (cursorBuffer.length > 4096) cursorBuffer = ""; } // The JSON may be split across reads.
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
        interval: 200; repeat: true
        running: world.hypr && world.live && !Clawd.lowMotion && !!world.pet && !world.asleep
        onTriggered: if (!cursorSocket.connected) cursorSocket.connected = true
    }
}
