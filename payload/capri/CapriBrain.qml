import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "js/brain-runtime.mjs" as Logic
import "js/util.mjs" as Util
import "js/demo.mjs" as Demo

Item {
    id: root
    z: 100
    required property var engine
    anchors.fill: parent
    readonly property alias chatController: chatController
    property var runtime: null
    property var pendingEvents: []
    property var message: null
    property var ticker: null
    property var head: ({
            x: 0,
            y: 0,
            top: 0
        })
    property bool suspended: false
    property bool menuOpen: false
    property bool reminderOpen: false
    property string reminderPrompt: ""
    property string reminderFeedback: ""
    property int revision: 0
    readonly property bool dnd: Config.getSetting("notifications.dnd", false)
    readonly property string langSetting: Config.getSetting("addonsV2CapriLanguage", "auto")
    readonly property string lang: ["fr", "en", "es", "pt", "ru"].indexOf(langSetting === "auto" ? I18n.currentLang : langSetting) >= 0 ? (langSetting === "auto" ? I18n.currentLang : langSetting) : "en"
    readonly property var labels: {
        const r = revision;
        return runtime ? runtime.brain.t : ({});
    }
    readonly property alias bubble: bubble
    readonly property alias menu: menu
    readonly property alias chatSettings: chatSettings
    readonly property bool wantsFocus: chatController.settingsOpen || !!(message && message.chat) || menuOpen || reminderOpen || !!(message && message.actions && message.actions.length)
    property var copyResolve: null
    property bool demoRunning: false
    signal send(var message)

    function get(key, fallback) {
        return Config.getSetting("addonsV2Capri" + key, fallback);
    }
    function clock(at, language) {
        const d = new Date(at);
        return d.toLocaleString(Qt.locale(language), d.toDateString() === new Date().toDateString() ? "HH:mm" : "ddd HH:mm");
    }
    function start() {
        if (runtime || !engine.capri)
            return;
        runtime = new Logic.Runtime(engine.capri, {
            get: (key, fallback) => root.get(key, fallback),
            lang: () => root.lang,
            setConfig: patch => {
                // upstream names: "claude" is whether she watches it; "visible" is her stow state, kept by the body
                for (const key of Object.keys(patch)) {
                    if (key === "visible") continue;
                    Config.setSetting("addonsV2Capri" + (key === "claude" ? "Watching" : key[0].toUpperCase() + key.slice(1)), patch[key]);
                }
            },
            voice: engine.voice,
            quiet: () => root.dnd,
            changed: panel => {
                root.message = panel.visible ? Object.assign({}, panel.current) : null;
                root.ticker = panel.tickerAction;
                root.revision++;
            },
            cursor: () => Promise.resolve(engine.world ? engine.world.cursor : null),
            clock: (at, language) => root.clock(at, language),
            date: (at, language) => new Date(at).toLocaleDateString(Qt.locale(language), "ddd d MMM"),
            menu: () => root.openMenu(),
            askWhen: () => {
                root.reminderFeedback = "when";
                root.reminderOpen = true;
            },
            parseError: () => {
                root.reminderFeedback = "invalid";
                root.reminderOpen = true;
            },
            reminderSaved: () => {
                root.reminderFeedback = "";
                root.reminderOpen = false;
            },
            snapshot: fn => fn({
                    x: bubble.x,
                    y: bubble.y,
                    width: bubble.width + 6,
                    height: bubble.height + 6
                }),
            copyImage: rect => root.copyImage(rect)
        });
        engine.capri.onMove = anchor => {
            root.head = anchor;
        };
        engine.capri.onTeleport = phase => {
            root.suspended = phase === "start";
        };
        head = engine.capri.head();
        revision++;
        chatController.start();
        chatController.rpc("sounds").then(list => engine.voice.loadCustom(list));
        windows();
        const queued = pendingEvents; pendingEvents = [];
        queued.forEach(evt => root.handle(evt));
    }
    function openMenu() {
        if (!runtime)
            return;
        menuOpen = !menuOpen;
        if (menuOpen)
            menu.forceActiveFocus();
    }
    function dismiss() {
        if (runtime)
            runtime.panel.hide();
        menuOpen = false;
        reminderOpen = false;
        chatController.settingsOpen = false;
    }
    function ingest(msg) {
        chatController.ingest(msg);
        if (runtime && msg.t === "reminder.parsed")
            runtime.parsed(msg);
    }
    function parse(text) {
        send({
            t: "reminder.parse",
            text: text,
            id: Date.now().toString()
        });
    }
    function copyImage(rect) {
        if (copyProcess.running || !engine.world || !engine.world.here)
            return Promise.resolve(false);
        const d = engine.world.here;
        const geo = Math.floor(d.x + rect.x) + "," + Math.floor(d.y + rect.y) + " " + Math.ceil(rect.width) + "x" + Math.ceil(rect.height);
        return new Promise(resolve => {
            copyResolve = resolve;
            copyProcess.command = ["bash", "-o", "pipefail", "-c", 'grim -g "$1" - | wl-copy -t image/png', "capri-report", geo];
            copyProcess.running = true;
        });
    }
    function command(name, arg) {
        if (!runtime)
            return "not ready";
        switch (name) {
        case "chat": chatController.open(); return "ok";
        case "send": chatController.submit(arg); return "ok";
        case "ai": chatController.showSettings(); chatSettings.personal = false; return "ok";
        case "personal": chatController.showSettings(); chatSettings.personal = true; return "ok";
        case "reminders": menuOpen = true; reminderOpen = false; menu.page = "reminders"; return "ok";
        case "forget": chatController.forget(); return "ok";
        case "help": case "welcome": case "guide": case "look": case "lookAuto": case "setup": case "key": case "free": case "customize": case "answer":
            return chatController.command(name, arg);
        case "stowToggle":
            if (engine.capri.stowed) engine.capri.unstow(); else engine.capri.stow();
            return "ok";
        case "sounds":
            chatController.rpc("openSounds");
            return "ok";
        case "hooks":
            chatController.rpc(arg === "off" ? "uninstallHooks" : "installHooks", {assistant: runtime.brain.assistant}).then(res => {
                const t = runtime.brain.t;
                runtime.panel.say(res && res.ok ? {kind:"done", line: arg === "off" ? t.hooksRemoved : t.hooksOk, hold:6000, asked:true}
                    : {kind:"error", line: Util.fmt(t.hooksFail, {error: res && res.error || "…"}), hold:7000, asked:true});
                if (res && res.ok && arg !== "off") engine.voice.play("hello");
            });
            return "ok";
        case "brain":
            return JSON.stringify({
                lang,
                assistant: runtime.brain.assistant,
                watching: runtime.brain.watching,
                linked: runtime.brain.linked,
                sessions: Array.from(runtime.brain.sessions.values()).map(s => ({
                            id: s.id,
                            count: s.count,
                            files: Array.from(s.files),
                            working: s.working,
                            waiting: s.waiting
                        })),
                message: message ? {
                    kind: message.kind,
                    line: message.line,
                    quote: message.quote,
                    reply: message.reply,
                    report: message.report,
                    progress: message.progress
                } : null,
                ticker,
                mission: runtime.mission.day,
                bond: runtime.bond.data,
                feeling: runtime.bond.feeling,
                reminders: runtime.reminders.list,
                chat: chatController.chat ? {open:chatController.chat.open,turn:chatController.chat.turn,history:chatController.chat.history.length,busy:!!(message && message.chatBusy)} : null,
                menu: menuOpen
            });
        case "demo":
            if (demoRunning)
                return "running";
            demoRunning = true;
            Util.co((function* () {
                    for (const step of Demo.demoSequence(root.lang)) {
                        yield Util.sleep(step[0]);
                        root.runtime.brain.handle(step[1]);
                    }
                    root.demoRunning = false;
                })());
            return "ok";
        case "status":
            runtime.brain.status();
            return "ok";
        case "report":
            runtime.brain.report();
            return "ok";
        case "menu":
            openMenu();
            return "ok";
        case "dismiss":
            dismiss();
            return "ok";
        case "action":
            runtime.panel.action(arg);
            return "ok";
        case "remind":
            parse(arg);
            return "ok";
        }
        return "unknown";
    }
    Component.onCompleted: start()
    Component.onDestruction: if (runtime)
        Capri.saveFinal(runtime.bond.data, runtime.mission.day)
    onDndChanged: if (dnd && runtime) {
        if (!message || !message.chat) runtime.panel.hide();
        menuOpen = false;
        reminderOpen = false;
        chatController.settingsOpen = false;
    }
    onLangChanged: if (runtime) {
        runtime.configure();
        revision++;
    }
    Connections {
        target: engine
        function onCapriChanged() {
            Qt.callLater(root.start);
        }
    }
    Connections {
        target: Config
        function onRawSettingsChanged() {
            if (root.runtime) {
                root.runtime.configure();
                chatController.configureLook();
                root.revision++;
            }
        }
    }
    Connections {
        target: Capri
        function onHookEvent(evt) {
            root.handle(evt);
        }
        function onPcReaction(kind, data) {
            if (root.runtime)
                root.runtime.pc(kind, data);
        }
    }
    Connections {
        target: engine.world
        function onForegroundChanged() {
            root.windows();
        }
        function onForegroundClientChanged() {
            root.windows();
        }
        function onPointerChanged() {
            if (root.runtime)
                root.runtime.moved(engine.world.pointer);
        }
    }
    function handle(evt) {
        if (!runtime) { if (pendingEvents.length < 128) pendingEvents.push(evt); return; }
        const result = runtime.brain.handle(evt);
        if (result && typeof result.catch === "function") result.catch(error => console.warn("Capri hook:", error));
    }
    function windows() {
        if (!runtime || !engine.world)
            return;
        const w = engine.world, c = w.foregroundClient;
        runtime.windows({
            fg: w.foreground,
            ai: Logic.rivalKeys(c ? c.title : "", c ? c.class : "")
        });
    }
    Process {
        id: copyProcess
        onExited: code => {
            if (root.copyResolve)
                root.copyResolve(code === 0);
            root.copyResolve = null;
        }
    }
    CapriChat { id: chatController; brain: root; onSend: message => root.send(message) }
    CapriChatSettings { id: chatSettings; brain: root; controller: chatController; engine: root.engine }
    CapriPanel {
        id: bubble
        brain: root
        engine: root.engine
    }
    CapriTicker {
        brain: root
        engine: root.engine
    }
    CapriMenu {
        id: menu
        brain: root
        engine: root.engine
    }
}
