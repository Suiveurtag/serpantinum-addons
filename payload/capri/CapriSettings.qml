import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"
import "js/settings.mjs" as Copy

ColumnLayout {
    id: root
    required property var rootObj
    property var viewport: null
    property bool expanded: false
    readonly property alias card: card
    readonly property string language: Config.getSetting("addonsV2CapriLanguage", "auto")
    readonly property string effectiveLanguage: language === "auto" ? I18n.currentLang : language
    readonly property var t: Copy.STRINGS[effectiveLanguage] || Copy.STRINGS.en
    property var hooks: ({claude:null, codex:null, agy:null})
    property string busy: ""
    property string feedback: ""
    Layout.fillWidth: true
    spacing: rootObj.s(8)

    function get(key, fallback) { return Config.getSetting("addonsV2Capri" + key, fallback); }
    function set(key, value) { Config.setSetting("addonsV2Capri" + key, value); }
    function watch(value) {
        set("Linked", false);
        if (value !== "none") set("Assistant", value);
        set("Watching", value !== "none");
    }
    function act(name, arg) {
        if (!Capri.enabled || liveProcess.running) return;
        feedback = "";
        liveProcess.command = ["quickshell", "-p", Caching.mainQml, "ipc", "call", "capri", "act", name, arg || ""];
        liveProcess.running = true;
    }
    function run(action, target) {
        if (busy) return;
        busy = target;
        hookProcess.action = action; hookProcess.target = target; hookProcess.output = "";
        hookProcess.command = ["node", Capri.scripts + "/hooks.js", action, target];
        hookProcess.running = true;
    }
    function refresh() { if (visible && preferences.isOpen && !busy) run("status", "claude"); }
    onVisibleChanged: if (visible) refresh()
    onExpandedChanged: refresh()
    Process {
        id: liveProcess
        property string output: ""
        property int pending: 0
        onStarted: { output = ""; pending = 2; }
        onExited: finish()
        stdout: StdioCollector { onStreamFinished: { liveProcess.output = text.trim(); liveProcess.finish(); } }
        function finish() {
            if (--pending > 0) return;
            root.feedback = output === "ok" ? root.t.opened : root.t.failed;
        }
    }
    Process {
        id: hookProcess
        property string action: ""
        property string target: ""
        property string output: ""
        property int pending: 0
        onStarted: pending = 2
        onExited: finish()
        stdout: StdioCollector { onStreamFinished: { hookProcess.output = text; hookProcess.finish(); } }
        function finish() {
            if (--pending > 0) return;
            let result;
            try { result = JSON.parse(output); } catch (error) { result = {ok:false,error:root.t.failed}; }
            root.busy = "";
            if (action !== "status" && result.ok) return root.run("status", target);
            const next = Object.assign({}, root.hooks); next[target] = result; root.hooks = next;
            if (target === "claude" && next.codex === null) root.run("status", "codex");
            else if (target === "codex" && next.agy === null) root.run("status", "agy");
        }
    }
    CapriCard {
        id: card
        rootObj: root.rootObj; strings: root.t
        consumerVisible: !root.viewport || (root.viewport.width > 0 && root.viewport.height > 0 && root.y + y + height > root.viewport.contentY && root.y + y < root.viewport.contentY + root.viewport.height)
    }
    SettingsGroup {
        id: preferences
        expanded: root.expanded
        onIsOpenChanged: if (isOpen) root.refresh()
        rootObj: root.rootObj; settingId: "addons_capri"; searchTab: "addons"
        searchKeywords: "capri companion pet mascotte compagnon options hooks provider fournisseur model modèle"
        title: root.t.options; description: root.t.details; icon: "󰒓"; wrapText: true
        ClickButton { buttonText: root.expanded ? root.t.collapse : root.t.expand; onClicked: root.expanded = !root.expanded }
        subSettings: ColumnLayout {
        Layout.fillWidth: true
        spacing: root.rootObj.s(8)
        Repeater {
            model: [
                {key:"Scale",label:"size",detail:"sizeDetail",fallback:0.6,values:[0.45,0.6,0.8],labels:[root.t.small,root.t.medium,root.t.large]},
                {key:"Motion",label:"motion",detail:"motionDetail",fallback:"auto",values:["auto","full","reduced"],labels:[root.t.auto,root.t.full,root.t.reduced]},
                {key:"Language",label:"language",detail:"languageDetail",fallback:"auto",values:["auto","en","fr","es","pt","ru"],labels:[root.t.auto,"English","Français","Español","Português","Русский"]},
                {key:"Rest",label:"rest",detail:"restDetail",fallback:"corner",values:["corner","taskbar"],labels:[root.t.corner,root.t.taskbar]}
            ]
            SettingsRow {
                required property var modelData
                rootObj: root.rootObj; settingId: "addons_capri_" + modelData.key.toLowerCase(); searchTab: "addons"
                searchKeywords: "capri " + modelData.key + " " + title; title: root.t[modelData.label]; description: root.t[modelData.detail]; wrapText: true
                Dropdown {
                    objectName: "capri" + modelData.key
                    Layout.preferredWidth: root.rootObj.s(180)
                    options: modelData.labels
                    currentIndex: Math.max(0, modelData.values.indexOf(root.get(modelData.key, modelData.fallback)))
                    Accessible.role: Accessible.ComboBox
                Accessible.name: root.t[modelData.label]
                    onSelected: {
                        root.set(modelData.key, modelData.values[currentIndex]);
                        currentIndex = Qt.binding(() => Math.max(0, modelData.values.indexOf(root.get(modelData.key, modelData.fallback))));
                    }
                }
            }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_screen"; searchTab: "addons"; searchKeywords: "capri screen monitor écran moniteur"
            title: root.t.screen; description: root.t.screenDetail; wrapText: true
            Dropdown {
                objectName: "capriScreen"
                Layout.preferredWidth: root.rootObj.s(180)
                options: Quickshell.screens.map(s => s.name)
                currentIndex: Math.max(0, options.indexOf((root.get("Position",{}) || {}).screen || ""))
                enabled: Capri.enabled && !liveProcess.running
                Accessible.role: Accessible.ComboBox
                Accessible.name: root.t.screen
                onSelected: {
                    root.act("screen", currentValue);
                    currentIndex = Qt.binding(() => Math.max(0, options.indexOf((root.get("Position",{}) || {}).screen || "")));
                }
            }
        }
        Repeater {
            model: [{key:"Follow",label:"follow",detail:"followDetail"},{key:"Wander",label:"wander",detail:"wanderDetail"},{key:"Possess",label:"possess",detail:"possessDetail"},{key:"Jealous",label:"jealous",detail:"jealousDetail"},{key:"PcReact",label:"pc",detail:"pcDetail"}]
            SettingsRow {
                required property var modelData
                rootObj: root.rootObj; settingId: "addons_capri_" + modelData.key.toLowerCase(); searchTab: "addons"
                searchKeywords: "capri " + modelData.key + " " + title; title: root.t[modelData.label]; description: root.t[modelData.detail]; wrapText: true
                Toggle {
                    objectName: "capri" + modelData.key
                    checked: root.get(modelData.key, true); accentColor: ThemeBackend.mauve
                    onToggled: { root.set(modelData.key, checked); checked = Qt.binding(() => root.get(modelData.key, true)); }
                }
            }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_watch"; searchTab: "addons"; searchKeywords: "capri watch assistant surveiller claude codex antigravity"
            title: root.t.watch; description: root.t.watchDetail; wrapText: true
            Dropdown {
                objectName: "capriWatch"
                readonly property var values: ["codex","claude","agy","none"]
                Layout.preferredWidth: root.rootObj.s(180)
                options: ["Codex","Claude Code","Antigravity",root.t.none]
                currentIndex: root.get("Watching",true) ? Math.max(0,values.indexOf(root.get("Assistant","codex"))) : 3
                Accessible.role: Accessible.ComboBox
                Accessible.name: root.t.watch
                onSelected: {
                    root.watch(values[currentIndex]);
                    currentIndex = Qt.binding(() => root.get("Watching",true) ? Math.max(0,values.indexOf(root.get("Assistant","codex"))) : 3);
                }
            }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_hooks"; searchTab: "addons"; searchKeywords: "capri hooks connect connexion backup sauvegarde"
            title: root.t.hooks; description: root.t.hooksDetail; wrapText: true
            ClickButton { buttonText: root.t.retry; enabled: !root.busy; onClicked: { root.hooks = ({claude:null,codex:null,agy:null}); root.refresh(); } }
        }
        Repeater {
            model: [{id:"claude",title:"Claude Code",after:root.t.claudeAfter},{id:"codex",title:"Codex",after:root.t.codexAfter},{id:"agy",title:"Antigravity",after:root.t.agyAfter}]
            SettingsRow {
                required property var modelData
                readonly property var hook: root.hooks[modelData.id]
                readonly property bool installed: !!(hook && hook.ok && hook.data && hook.data.installed && !hook.data.error)
                readonly property string error: hook && (!hook.ok ? hook.error : hook.data.error) || ""
                rootObj: root.rootObj; settingId: "addons_capri_hooks_" + modelData.id; searchTab: "addons"; searchKeywords: "capri hooks " + modelData.id
                title: modelData.title; wrapText: true
                description: !hook ? root.t.checking : error || ((installed ? root.t.connected : root.t.notConnected) + " · " + hook.data.file + "\n" + modelData.after)
                ClickButton {
                    objectName: "capriHook_" + modelData.id
                    enabled: !root.busy && !!hook && !error
                    buttonText: root.busy === modelData.id ? root.t.busy : (installed ? root.t.disconnect : root.t.connect)
                    accentColor: installed ? ThemeBackend.surface1 : ThemeBackend.mauve
                    textColor: installed ? ThemeBackend.text : ThemeBackend.crust
                    onClicked: root.run(installed ? "uninstall" : "install", modelData.id)
                }
            }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_ai"; searchTab: "addons"; searchKeywords: "capri AI provider model fournisseur modèle chatgpt subscription abonnement codex ollama key clé serveur"
            title: root.t.ai; description: root.t.aiDetail; wrapText: true
            ClickButton { objectName:"capriAI"; buttonText: root.t.configure; enabled: Capri.enabled && !liveProcess.running; onClicked: root.act("ai") }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_personal"; searchTab: "addons"; searchKeywords: "capri persona personality name memories facts custom nom personnalité souvenirs"
            title: root.t.personal; description: root.t.personalDetail; wrapText: true
            ClickButton { buttonText: root.t.edit; enabled: Capri.enabled && !liveProcess.running; onClicked: root.act("personal") }
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_try"; searchTab: "addons"; searchKeywords: "capri try demo talk chat reminders rappel essayer"
            title: root.t.actions; description: root.t.actionsDetail; wrapText: true
            bottomContent: Flow {
                Layout.fillWidth: true
                spacing: root.rootObj.s(8)
                enabled: Capri.enabled && !liveProcess.running
                ClickButton { buttonText: root.t.demo; onClicked: root.act("demo") }
                ClickButton { buttonText: root.t.summon; onClicked: root.act("teleport","post") }
                ClickButton { buttonText: root.t.talk; onClicked: root.act("chat") }
                ClickButton { buttonText: root.t.reminders; onClicked: root.act("reminders") }
                ClickButton { buttonText: root.t.report; onClicked: root.act("report") }
                ClickButton { buttonText: root.t.hide; onClicked: root.act("stow") }
                ClickButton { buttonText: root.t.show; onClicked: root.act("unstow") }
            }
        }
        Text {
            Layout.fillWidth: true; visible: !!text
            text: Capri.enabled ? root.feedback : root.t.off; textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11)
        }
        SettingsRow {
            rootObj: root.rootObj; settingId: "addons_capri_shortcut"; searchTab: "addons"; searchKeywords: "capri shortcut keybind raccourci Super Shift K ipc call capri toggle"
            title: root.t.shortcut; description: root.t.shortcutDetail; wrapText: true
        }
    }
    }
}
