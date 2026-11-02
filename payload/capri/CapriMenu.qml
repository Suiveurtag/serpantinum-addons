import QtQuick
import QtQuick.Controls.Basic
import "../"
import "js/labels.mjs" as Labels

FocusScope {
    id: menu
    required property var brain
    required property var engine
    property string page: ""
    property var hooks: null   // her hooks for the assistant she watches, read when the menu opens
    readonly property var reminderUi: Labels.REMINDER_UI[brain.lang] || Labels.REMINDER_UI.en
    readonly property var t: Labels.TRAY[brain.lang] || Labels.TRAY.en
    readonly property var rows: {
        const r = brain.revision;
        return build();
    }
    visible: brain.menuOpen || brain.reminderOpen
    width: Math.min(370, engine.width - 28)
    height: Math.min(engine.height - 28, brain.reminderOpen ? 260 : list.implicitHeight + 28)
    x: Math.max(14, Math.min(engine.width - width - 14, brain.head.x - width / 2))
    y: Math.max(14, Math.min(engine.height - height - 14, brain.head.y - height))
    onVisibleChanged: if (visible) {
        page = "";
        hooks = null;
        if (brain.runtime) brain.chatController.rpc("hooksStatus", {assistant: brain.runtime.brain.assistant}).then(s => menu.hooks = s || null);
        forceActiveFocus();
        if (brain.reminderOpen)
            entry.forceActiveFocus();
    }
    Keys.onEscapePressed: {
        if (page)
            page = "";
        else {
            brain.menuOpen = false;
            brain.reminderOpen = false;
        }
    }
    function setting(key, label, fallback) {
        return {
            label: (brain.get(key, fallback) ? "✓  " : "   ") + label,
            key,
            value: !brain.get(key, fallback)
        };
    }
    // upstream: the tray's "Claude Code" is whichever assistant she watches
    function named(s) { const n = ({codex:"Codex", agy:"Antigravity"})[brain.runtime.brain.assistant]; return n ? String(s).split("Claude Code").join(n) : s; }
    function build() {
        if (!brain.runtime)
            return [];
        const r = brain.runtime, c = engine.capri, b = r.bond, assistant = r.brain.assistant;
        switch (page) {
        case "size":
            return [[.45, t.small], [.6, t.medium], [.8, t.large]].map(v => ({
                        label: v[1],
                        key: "Scale",
                        value: v[0]
                    }));
        case "ai":
            return [{label:t.aiSetup,cmd:"setup"},{label:t.chatModel + "…",act:"ai"},{label:t.apiKey,cmd:"key"},{label:t.cloudSignin,signin:true},{label:t.forget,forget:true}];
        case "sound":
            return [setting("Muted", t.mute, false),{label:t.soundsDir,cmd:"sounds"}];
        case "rest":
            return [{label:t.restCorner,key:"Rest",value:"corner"},{label:t.restTaskbar,key:"Rest",value:"taskbar"}];
        case "motion":
            return [{label:t.auto,key:"Motion",value:"auto"},{label:t.motionFull,key:"Motion",value:"full"},{label:t.motionReduced,key:"Motion",value:"reduced"}];
        case "lang":
            return [
                {
                    label: t.auto,
                    key: "Language",
                    value: "auto"
                }
            ].concat(Object.keys(Labels.TRAY).map(k => ({
                        label: Labels.TRAY[k].name,
                        key: "Language",
                        value: k
                    })));
        case "watch":
            return ["claude", "codex", "agy", "none"].map(k => ({
                        label: k === "none" ? t.watchNone : ({
                                claude: "Claude Code",
                                codex: "Codex",
                                agy: "Antigravity"
                            })[k],
                        watch: k
                    }));
        case "screen":
            return (engine.world ? engine.world.displays : []).map(d => ({
                        label: (d.id === Capri.screenName ? "✓ " : "") + d.id + " — " + d.w + "×" + d.h,
                        screen: d.id
                    })).concat([setting("Follow", t.follow, true)]);
        case "reminders":
            return r.reminders.upcoming.map(item => ({
                        label: brain.clock(item.at, brain.lang) + " · " + item.text.slice(0, 50),
                        cancel: item.id
                    })).concat([
                {
                    label: "+ " + t.reminders,
                    add: true
                }
            ]);
        default:
            return [
                {
                    label: t.online(47823),
                    disabled: true
                },
                {
                    label: t.sync(b.percent, t.stages[b.stage]),
                    disabled: true
                },
                {
                    label: t.teleport,
                    act: "teleport"
                },
                {
                    label: t.satellite,
                    act: "gaze"
                },
                {
                    label: t.demo,
                    act: "demo"
                },
                {label:t.help,cmd:"help"},
                {label:t.talk,act:"chat"},
                {label:t.lookNow,cmd:"look"},
                {label:t.chatModel,page:"ai"},
                {label:t.custom,cmd:"customize"},
                {
                    label: t.report,
                    act: "report",
                    disabled: !r.brain.watching
                },
                {
                    label: t.reminders,
                    page: "reminders"
                },
                {
                    label: c && c.stowed ? t.show : t.hide,
                    act: c && c.stowed ? "unstow" : "stow"
                },
                {
                    label: t.size,
                    page: "size"
                },
                {
                    label: t.screen,
                    page: "screen"
                },
                {label:t.sound,page:"sound"},
                setting("Wander", t.wander, true), setting("Possess", t.possess, true), setting("Jealous", t.jealous, true), setting("PcReact", t.pcReact, true),
                {label:(brain.get("WatchScreen", false) ? "✓  " : "   ") + t.lookAuto, cmd:"lookAuto", arg:brain.get("WatchScreen", false) ? "off" : "on"},
                {
                    label: t.rest, page: "rest"
                },
                {
                    label: t.motion, page: "motion"
                },
                {
                    label: t.watch,
                    page: "watch"
                }].concat(!r.brain.watching || !menu.hooks ? [] : menu.hooks.installed
                    ? [{label:named(t.hooksOn),disabled:true},{label:named(t.hooksRemove),cmd:"hooks",arg:"off"}]
                    : [{label:named(t.hooksOff),cmd:"hooks",arg:"on"}]).concat([
                {
                    label: t.lang,
                    page: "lang"
                },
                {
                    label: t.quit,
                    disable: true
                }
            ]);
        }
    }
    function choose(row) {
        if (row.page) {
            page = row.page;
            return;
        }
        if (row.key) {
            Config.setSetting("addonsV2Capri" + row.key, row.value);
            if (row.key === "Scale")
                engine.capri.setScale(row.value);
        } else if (row.watch) {
            const before = brain.runtime.brain.watching ? brain.runtime.brain.assistant : "none";
            brain.runtime.panel.hide();
            Config.setSetting("addonsV2CapriLinked", false);
            if (row.watch !== "none")
                Config.setSetting("addonsV2CapriAssistant", row.watch);
            Config.setSetting("addonsV2CapriWatching", row.watch !== "none");
            // a new one: she says hi and offers to plug herself in (upstream "assistantChanged")
            if (row.watch !== "none" && row.watch !== before) {
                Config.setSetting("addonsV2CapriWelcomed", false);
                Qt.callLater(() => brain.command("welcome", ""));
            }
        } else if (row.cmd) {
            brain.menuOpen = false;
            brain.command(row.cmd, row.arg || "");
            return;
        } else if (row.signin) brain.chatController.rpc("ollamaSignin");
        else if(row.forget) brain.chatController.forget();
        else if (row.screen)
            engine.world.goToScreen(row.screen, true);
        else if (row.cancel) {
            brain.runtime.reminders.remove(row.cancel);
            brain.revision++;
            return;
        } else if (row.add) {
            brain.reminderOpen = true;
            brain.menuOpen = false;
            entry.forceActiveFocus();
            return;
        } else if (row.disable)
            Config.setSetting("addonsV2Capri", false);
        else if (row.act)
            engine.act(row.act, "");
        brain.menuOpen = false;
    }
    CapriPlate {
        anchors.fill: parent
        fillColor: "#7d3af5"
        transform: Translate {
            x: 6
            y: 6
        }
    }
    CapriPlate {
        anchors.fill: parent
    }
    MouseArea {
        anchors.fill: parent
        onWheel: wheel => wheel.accepted = true
    }
    ScrollView {
        anchors.fill: parent
        anchors.margins: 14
        visible: !brain.reminderOpen
        contentWidth: availableWidth
        clip: true
        Column {
            id: list
            width: parent.width
            CapriButton {
                visible: !!menu.page
                width: parent.width
                text: "‹ " + menu.t.online(47823)
                onClicked: menu.page = ""
            }
            Repeater {
                model: menu.rows
                CapriButton {
                    required property var modelData
                    width: list.width
                    enabled: !modelData.disabled
                    text: modelData.label + (modelData.page ? "  ›" : "")
                    onClicked: menu.choose(modelData)
                }
            }
        }
    }
    Column {
        visible: brain.reminderOpen
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12
        Text {
            text: menu.t.reminders
            color: "#fcf2f6"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 16
            font.bold: true
        }
        TextField {
            id: entry
            width: parent.width
            maximumLength: 2000
            placeholderText: menu.reminderUi.example
            placeholderTextColor: "#d6c5d0"
            color: "#fcf2f6"
            font.family: ThemeBackend.fontFamily
            selectByMouse: true
            background: Rectangle {
                color: "#2a203b"
                border.color: entry.activeFocus ? "#36ff73" : "#7d3af5"
            }
            onAccepted: submit.clicked()
        }
        Text {
            width: parent.width
            visible: !!brain.reminderFeedback
            text: menu.reminderUi[brain.reminderFeedback] || ""
            wrapMode: Text.Wrap
            color: "#d6c5d0"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: 12
        }
        Row {
            spacing: 8
            CapriButton {
                id: submit
                text: menu.reminderUi.add
                primary: true
                onClicked: {
                    if (entry.text.trim()) {
                        brain.parse(entry.text.trim());
                        entry.clear();
                    }
                }
            }
            CapriButton {
                text: brain.labels.remind ? brain.labels.remind.cancel : ""
                onClicked: brain.reminderOpen = false
            }
        }
    }
}
