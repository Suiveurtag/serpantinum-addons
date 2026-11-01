import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../"
import "../reusables"

// Claude Code's terminal: a monospace cell grid, box-drawing frames, ">" prompts and controls that invert under the pointer.
Rectangle {
    id: card
    required property var rootObj
    property bool consumerVisible: true
    property real highlight: 0
    readonly property bool animate: visible && consumerVisible && !Clawd.lowMotion && width > 0
        && Window.window !== null && Window.window.visible
    readonly property int px: Math.round(rootObj.s(12))
    readonly property real cw: cell.advanceWidth
    readonly property real lh: metrics.height
    readonly property real rowH: Math.round(lh * 1.6)
    readonly property int cols: Math.max(36, Math.floor(width / cw) - 2)
    readonly property bool compact: cols < 62
    readonly property color accent: ThemeBackend.peach
    readonly property color ink: ThemeBackend.text
    readonly property color dim: ThemeBackend.subtext0
    readonly property color faint: ThemeBackend.overlay1
    readonly property var naps: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    property bool cursorOn: true
    property bool summoned: false
    property string hookNote: ""
    property bool hookFailed: false
    property var chatSigned: null
    property int hookRuns: 0       // hooks.py runs in flight: they share ~/.claude/settings.json, one change at a time
    function setScale(value) { Config.setSetting("addonsV2ClawdScale", Math.max(2, Math.min(8, Math.round(value)))); }
    function nap(step) {
        const v = Clawd.sleepMinutes;
        const next = step > 0 ? naps.find(n => n > v) : naps.slice().reverse().find(n => n < v);
        if (next !== undefined) Config.setSetting("addonsV2ClawdSleep", next);
    }
    function summon() {
        Config.setSetting("addonsV2ClawdSummon", (Config.getSetting("addonsV2ClawdSummon", 0) | 0) + 1);
        summoned = true;
        summonedTimer.restart();
    }
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + lh * 1.5
    radius: ThemeBackend.borderRadius
    color: Qt.tint(ThemeBackend.mantle, Qt.alpha(ThemeBackend.mauve, highlight * 0.12))
    border.width: Math.max(1, Math.round(rootObj.s(1)))
    border.color: Qt.alpha(ThemeBackend.surface1, 0.6)

    TextMetrics { id: cell; text: "─"; font.family: ThemeBackend.fontFamily; font.pixelSize: card.px }
    FontMetrics { id: metrics; font.family: ThemeBackend.fontFamily; font.pixelSize: card.px }
    Timer { interval: 530; repeat: true; running: card.animate; onTriggered: card.cursorOn = !card.cursorOn }
    Timer { id: summonedTimer; interval: 2600; onTriggered: card.summoned = false }

    component T: Text {
        font.family: ThemeBackend.fontFamily
        font.pixelSize: card.px
        color: card.ink
        textFormat: Text.PlainText
    }
    // A ╭─╮ box sized in whole cells; children sit one cell in from the border.
    component Frame: Item {
        id: frame
        property int lines: 1
        property string title: ""
        default property alias content: inside.data
        readonly property int titleCells: title ? title.length + 2 : 0
        width: card.cols * card.cw
        height: (lines + 2) * card.lh
        T { color: card.accent; text: "╭───" + " ".repeat(frame.titleCells) + "─".repeat(Math.max(0, card.cols - 5 - frame.titleCells)) + "╮" }
        T { x: 5 * card.cw; text: frame.title; color: card.ink; font.bold: true }
        T { y: card.lh; color: card.accent; text: "│\n".repeat(frame.lines).trim(); lineHeightMode: Text.FixedHeight; lineHeight: card.lh }
        T { x: (card.cols - 1) * card.cw; y: card.lh; color: card.accent; text: "│\n".repeat(frame.lines).trim(); lineHeightMode: Text.FixedHeight; lineHeight: card.lh }
        T { y: (frame.lines + 1) * card.lh; color: card.accent; text: "╰" + "─".repeat(card.cols - 2) + "╯" }
        Item { id: inside; x: 2 * card.cw; y: card.lh; width: (card.cols - 4) * card.cw; height: frame.lines * card.lh }
    }
    // A run of terminal text that is a button: inverted on hover, harder inverted while pressed.
    component Key: Item {
        id: key
        property string label
        property string accessibleName: label
        property bool selected: false
        property bool checkable: false
        property bool checked: false
        property bool tabStop: true
        property color idleColor: card.ink
        readonly property bool lit: enabled && (area.containsMouse || area.pressed)
        signal activated()
        implicitWidth: keyText.implicitWidth
        implicitHeight: keyText.implicitHeight
        activeFocusOnTab: enabled && tabStop
        Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
        Accessible.name: accessibleName
        Accessible.checkable: checkable
        Accessible.checked: checked
        Accessible.onPressAction: if (enabled) activated()
        Keys.onSpacePressed: activated()
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Rectangle { anchors.fill: parent; visible: key.lit; color: area.pressed ? card.ink : card.accent }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: Math.max(1, Math.round(card.rootObj.s(1)))
            visible: key.activeFocus && !key.lit; color: card.accent
        }
        T {
            id: keyText
            text: key.label
            font.bold: key.selected
            color: key.lit ? ThemeBackend.base : !key.enabled ? card.faint : key.selected ? card.accent : key.idleColor
        }
        MouseArea {
            id: area
            anchors.fill: parent; anchors.topMargin: -card.rootObj.s(4); anchors.bottomMargin: -card.rootObj.s(4)
            enabled: key.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: key.activated()
        }
    }
    // "> label   controls…", the prompt lights up with the row under the pointer.
    component Line: Item {
        id: line
        property string label
        default property alias content: controls.data
        width: parent ? parent.width : 0
        implicitHeight: card.rowH
        HoverHandler { id: hover }
        T { anchors.verticalCenter: parent.verticalCenter; text: ">"; color: hover.hovered ? card.accent : card.faint; font.bold: hover.hovered }
        T { x: 2 * card.cw; anchors.verticalCenter: parent.verticalCenter; text: line.label }
        Row { id: controls; x: 13 * card.cw; anchors.verticalCenter: parent.verticalCenter }
    }

    Column {
        id: body
        x: Math.round((card.width - card.cols * card.cw) / 2)
        y: Math.round(card.lh * 0.75)
        width: card.cols * card.cw

        Frame {
            id: header
            readonly property int frameH: Clawd.manifest ? Clawd.manifest.frame.h : 0
            title: "Clawd v1"
            lines: 5
            Item {
                id: stage
                y: card.lh
                width: Math.ceil(sprite.width * (card.compact ? 1.5 : 2.4) / card.cw) * card.cw
                height: 3 * card.lh
                ClawdSprite {
                    id: sprite
                    // a little loop of what he does on the desktop; off, he naps in the card
                    readonly property var script: ["idle", "blink", "idle", "walk", "sit", "blink", "idle", "walk"]
                    property int beat: 0
                    readonly property string phase: !Clawd.enabled ? "sleep" : card.animate ? script[beat % script.length] : "idle"
                    anchors.bottom: parent.bottom
                    animation: phase
                    pixelScale: header.frameH > 0 ? Math.max(1, Math.min(4, Math.floor(3 * card.lh / header.frameH))) : 3
                    running: card.animate
                    onFinished: if (phase === "blink") beat++
                    onPhaseChanged: {
                        if (phase !== "walk") return stroll.stop();
                        mirrored = x > (stage.width - width) / 2;
                        stroll.to = mirrored ? 0 : stage.width - width;
                        stroll.duration = Math.max(1, Math.abs(stroll.to - x)) / ({calm: 30, normal: 60, active: 100}[Clawd.speed] || 60) * 1000 * 4 / pixelScale;
                        stroll.restart();
                    }
                    NumberAnimation { id: stroll; target: sprite; property: "x"; onFinished: sprite.beat++ }
                }
                Timer {
                    interval: 2400; repeat: true
                    running: card.animate && Clawd.enabled && !stroll.running
                    onTriggered: sprite.beat++
                }
            }
            Column {
                x: stage.width + 2 * card.cw
                y: card.lh
                width: parent.width - x
                Row {
                    height: card.lh
                    T { text: "✻ "; color: card.accent; font.bold: true }
                    T { text: "Welcome to Clawd!"; font.bold: true }
                }
                T { width: parent.width; elide: Text.ElideRight; color: card.dim; height: card.lh; text: "Claude Code's cute pal" +(card.compact ? "" : ", on your desktop") }
                T {
                    width: parent.width; elide: Text.ElideRight; height: card.lh
                    color: Clawd.enabled ? ThemeBackend.green : card.faint
                    text: Clawd.enabled ? "● awake · ×" + Clawd.scale + " · " + Clawd.speed + (card.compact ? "" : " · naps after " + Clawd.sleepMinutes + " min")
                        : "○ off · tucked away in this card"
                }
            }
        }
        Item { width: 1; height: card.lh * 0.5 }
        Line {
            label: "clawd"
            Key {
                objectName: "clawdEnable"
                label: Clawd.enabled ? "[x] on" : "[ ] off"
                accessibleName: "Clawd"
                checkable: true; checked: Clawd.enabled
                onActivated: Config.setSetting("addonsV2Clawd", !Clawd.enabled)
            }
            T { color: card.dim; text: Clawd.enabled ? "   roaming the desktop" : "   tick to let him out" }
        }
        Line {
            label: "scale"
            Key { objectName: "clawdScaleDown"; label: "◀"; accessibleName: "Smaller"; enabled: Clawd.scale > 2; onActivated: card.setScale(Clawd.scale - 1) }
            T { text: " ×" + Clawd.scale + " "; font.bold: true }
            Key { objectName: "clawdScaleUp"; label: "▶"; accessibleName: "Larger"; enabled: Clawd.scale < 8; onActivated: card.setScale(Clawd.scale + 1) }
            T { text: "   " }
            Repeater {
                model: 7
                Key {
                    required property int index
                    label: index + 2 <= Clawd.scale ? "█" : "░"
                    accessibleName: "×" + (index + 2)
                    selected: index + 2 <= Clawd.scale
                    idleColor: card.faint
                    tabStop: false
                    onActivated: card.setScale(index + 2)
                }
            }
        }
        Line {
            label: "pace"
            Repeater {
                model: ["calm", "normal", "active"]
                Row {
                    required property string modelData
                    required property int index
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Key {
                        objectName: "clawdSpeed_" + modelData
                        label: modelData
                        selected: Clawd.speed === modelData
                        onActivated: Config.setSetting("addonsV2ClawdSpeed", modelData)
                    }
                }
            }
        }
        Line {
            label: "nap after"
            Key { objectName: "clawdSleepDown"; label: "◀"; accessibleName: "Sooner"; enabled: Clawd.sleepMinutes > 1; onActivated: card.nap(-1) }
            T { text: " " + Clawd.sleepMinutes + " min "; font.bold: true }
            Key { objectName: "clawdSleepUp"; label: "▶"; accessibleName: "Later"; enabled: Clawd.sleepMinutes < 60; onActivated: card.nap(1) }
            T { visible: !card.compact; color: card.dim; text: "   of quiet, then zZ" }
        }
        Line {
            // windows: perches on them, peeks behind them, reacts to them; follow: goes to the cursor's screen
            label: "world"
            Key {
                objectName: "clawdWorld"
                label: (Clawd.world ? "[x]" : "[ ]") + " windows"
                accessibleName: "Windows"
                checkable: true; checked: Clawd.world
                onActivated: Config.setSetting("addonsV2ClawdWorld", !Clawd.world)
            }
            T { text: " · "; color: card.faint }
            Key {
                objectName: "clawdFollow"
                label: (Clawd.follow ? "[x]" : "[ ]") + " follow"
                accessibleName: "Follow the cursor"
                checkable: true; checked: Clawd.follow
                onActivated: Config.setSetting("addonsV2ClawdFollow", !Clawd.follow)
            }
            T { visible: !card.compact; color: card.dim; text: "  ⎿ perches on windows, follows your cursor" }
        }
        Line {
            // his colour (and the spinner's) follows the effort of the session at work
            label: "effort"
            Key {
                objectName: "clawdEffort"
                label: (Clawd.effortColors ? "[x]" : "[ ]") + " colours"
                accessibleName: "Effort colours"
                checkable: true; checked: Clawd.effortColors
                onActivated: Config.setSetting("addonsV2ClawdEffort", !Clawd.effortColors)
            }
            T { visible: !card.compact; color: card.dim; text: "  ⎿ tints him by the effort of the working session" }
        }
        Line {
            // which effort levels tint him, per agent; each name is drawn letter by letter, cycling its palette like a terminal
            label: "codex"
            Repeater {
                model: [
                    { key: "low", name: "Light", palette: ["#FFFFFF"] },
                    { key: "medium", name: "Medium", palette: ["#ACFFD8"] },
                    { key: "high", name: "High", palette: ["#0093FF"] },
                    { key: "xhigh", name: "Extra High", palette: ["#FF6363", "#FFFFFF"], sweep: true },
                    { key: "max", name: "Max", palette: ["#FFD34D", "#FFF2B8"] },
                    { key: "ultra", name: "Ultra", palette: ["#9B7BFF", "#6FB6FF"] }
                ]
                Row {
                    required property var modelData
                    required property int index
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Item {
                        id: opt
                        objectName: "clawdEffort_codex_" + modelData.key
                        readonly property var fx: modelData
                        readonly property bool on: Config.getSetting("addonsV2ClawdEffort_codex_" + modelData.key, true) !== false
                        readonly property bool animated: on && fx.palette.length > 1
                        property int tick: 0
                        Timer { running: opt.animated && Clawd.effortColors; interval: 140; repeat: true; onTriggered: opt.tick++ }
                        implicitWidth: word.width
                        implicitHeight: word.height
                        opacity: Clawd.effortColors ? 1 : 0.4
                        function paint() {
                            let h = "";
                            const name = opt.fx.name;
                            for (let i = 0; i < name.length; i++) {
                                let c = card.faint;
                                if (opt.on && !opt.animated) c = opt.fx.palette[0];
                                else if (opt.on && opt.fx.sweep) c = (opt.tick % (name.length + 2)) === i ? opt.fx.palette[1] : opt.fx.palette[0];
                                else if (opt.on) c = opt.fx.palette[(opt.tick + i) % opt.fx.palette.length];
                                h += '<font color="' + c + '">' + (name[i] === " " ? "&nbsp;" : name[i]) + "</font>";
                            }
                            return h;
                        }
                        T {
                            id: word
                            textFormat: Text.RichText
                            font.bold: true
                            text: opt.paint()
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Config.setSetting("addonsV2ClawdEffort_codex_" + modelData.key, !opt.on)
                        }
                    }
                }
            }
        }
        Line {
            label: "claude"
            Repeater {
                model: [
                    { key: "low", name: "Low", palette: ["#FFC107"] },
                    { key: "medium", name: "Medium", palette: ["#4EBA65"] },
                    { key: "high", name: "High", palette: ["#B1B9F9"] },
                    { key: "xhigh", name: "Xhigh", palette: ["#AF87FF", "#FFFFFF"], sweep: true },
                    { key: "max", name: "Max", palette: ["#FF9E7A", "#FFD966", "#8FE3A0", "#9BD3FF", "#C9B5FF", "#FF9CB0"] },
                    { key: "ultracode", name: "Ultracode subagent", palette: ["#EB83FF", "#FFFFFF"] },
                    { key: "ultracode_workflow", name: "Ultracode Workflow", palette: ["#9BF6FF", "#FFFFFF"] }
                ]
                Row {
                    required property var modelData
                    required property int index
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Item {
                        id: opt
                        objectName: "clawdEffort_claude_" + modelData.key
                        readonly property var fx: modelData
                        readonly property bool on: Config.getSetting("addonsV2ClawdEffort_claude_" + modelData.key, true) !== false
                        readonly property bool animated: on && fx.palette.length > 1
                        property int tick: 0
                        Timer { running: opt.animated && Clawd.effortColors; interval: 140; repeat: true; onTriggered: opt.tick++ }
                        implicitWidth: word.width
                        implicitHeight: word.height
                        opacity: Clawd.effortColors ? 1 : 0.4
                        function paint() {
                            let h = "";
                            const name = opt.fx.name;
                            for (let i = 0; i < name.length; i++) {
                                let c = card.faint;
                                if (opt.on && !opt.animated) c = opt.fx.palette[0];
                                else if (opt.on && opt.fx.sweep) c = (opt.tick % (name.length + 2)) === i ? opt.fx.palette[1] : opt.fx.palette[0];
                                else if (opt.on) c = opt.fx.palette[(opt.tick + i) % opt.fx.palette.length];
                                h += '<font color="' + c + '">' + (name[i] === " " ? "&nbsp;" : name[i]) + "</font>";
                            }
                            return h;
                        }
                        T {
                            id: word
                            textFormat: Text.RichText
                            font.bold: true
                            text: opt.paint()
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Config.setSetting("addonsV2ClawdEffort_claude_" + modelData.key, !opt.on)
                        }
                    }
                }
            }
        }
        Line {
            // how much he reacts to the shell: all, quiet (urgent, bubbles, moods), off (urgent only)
            label: "reacts"
            Repeater {
                model: ["all", "quiet", "off"]
                Row {
                    required property string modelData
                    required property int index
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Key {
                        objectName: "clawdReacts_" + modelData
                        label: modelData
                        selected: Clawd.reactions === modelData
                        onActivated: Config.setSetting("addonsV2ClawdReactions", modelData)
                    }
                }
            }
            T { visible: !card.compact; color: card.dim; text: "  ⎿ music, notifications, volume…" }
        }
        Line {
            label: "summon"
            Key {
                objectName: "clawdSummon"
                label: "[ summon on this screen ]"
                enabled: Clawd.enabled
                onActivated: card.summon()
            }
            T {
                color: card.summoned ? card.accent : card.faint
                text: card.summoned ? "  ⎿ on his way" : Clawd.enabled ? "" : "  needs clawd on"
            }
        }
        Line {
            label: "shortcut"
            T { text: "super+shift+l" }
            T { text: "  " }
            Key {
                objectName: "clawdShortcut"
                visible: typeof card.rootObj.gotoTab === "function"
                label: "[ keybinds ]"
                onActivated: card.rootObj.gotoTab("addon_keybinds")
            }
            T { visible: !card.compact; color: card.dim; text: "  search “clawd”" }
        }
        Line {
            label: "hooks"
            Repeater {
                // statusline: Claude's status line relays model, context, cost and limits ("stats")
                model: ["claude", "codex", "statusline"]
                Row {
                    id: hook
                    required property string modelData
                    required property int index
                    readonly property string name: modelData === "statusline" ? "stats" : modelData
                    readonly property string agent: modelData === "codex" ? "codex" : "claude"
                    property var info: null    // hooks.py status, or {error}
                    property bool busy: false  // Process.running only flips once the process has started
                    function run(action) { busy = true; card.hookRuns++; proc.command = ["python3", Clawd.scripts + "/hooks.py", action, modelData]; proc.running = true; }
                    Component.onCompleted: run("status")
                    Process {
                        id: proc
                        stdout: StdioCollector {
                            onStreamFinished: {
                                let r = null;
                                try { r = JSON.parse(text); } catch (error) {}
                                hook.busy = false;
                                card.hookRuns = Math.max(0, card.hookRuns - 1);
                                hook.info = r && r.ok ? r.data : { error: r && r.error || "hooks.py failed" };
                                card.hookFailed = !!hook.info.error;
                                card.hookNote = hook.info.error ? hook.name + ": " + hook.info.error : r.data.changed ? "start a new " + hook.agent + " session" : card.hookNote;
                            }
                        }
                    }
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Key {
                        objectName: "clawdHook_" + modelData
                        label: (hook.busy || !hook.info ? "[…] " : hook.info.error ? "[!] " : hook.info.installed ? "[x] " : "[ ] ") + hook.name
                        accessibleName: hook.modelData === "statusline" ? "Claude status line stats" : modelData + " hooks"
                        checkable: true; checked: !!hook.info && hook.info.installed === true
                        enabled: !hook.busy && !!hook.info && card.hookRuns === 0
                        onActivated: hook.run(checked ? "uninstall" : "install")
                    }
                }
            }
            T {
                visible: !card.compact
                color: card.hookFailed ? ThemeBackend.red : card.dim
                text: "  ⎿ " + (card.hookNote || "he reacts to your agents")
            }
        }
        // narrow card: three toggles fill the row, the note goes under them
        T {
            visible: card.compact && card.hookNote !== ""
            x: 13 * card.cw; width: parent.width - x; height: card.lh; elide: Text.ElideRight
            color: card.hookFailed ? ThemeBackend.red : card.dim
            text: "⎿ " + card.hookNote
        }
        Line {
            label: "thoughts"
            Repeater {
                model: ["full", "verbs", "off"]
                Row {
                    required property string modelData
                    required property int index
                    T { visible: index > 0; text: " · "; color: card.faint }
                    Key {
                        objectName: "clawdThoughts_" + modelData
                        label: modelData
                        selected: Clawd.thoughts === modelData
                        onActivated: Config.setSetting("addonsV2ClawdThoughts", modelData)
                    }
                }
            }
            T { visible: !card.compact; color: card.dim; text: "  ⎿ above his head while claude works" }
        }
        Line {
            label: "chat"
            Key {
                objectName: "clawdChatToggle"
                label: (Clawd.chat ? "[x]" : "[ ]") + " on"
                accessibleName: "Chat"
                checkable: true; checked: Clawd.chat
                onActivated: Config.setSetting("addonsV2ClawdChat", !Clawd.chat)
            }
            Process {
                id: chatStatus
                command: ["node", Clawd.scripts + "/brain.js", "status"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { const r = JSON.parse(text); card.chatSigned = r.ok && r.data ? r.data.signedIn === true : false; } catch (error) { card.chatSigned = false; }
                    }
                }
            }
            T { visible: !card.compact; color: card.dim; text: "  ⎿ ChatGPT via Codex · " + (card.chatSigned === null ? "checking" : card.chatSigned ? "signed in" : "run codex login") }
        }
        Item { width: 1; height: card.lh * 0.5 }
        Frame {
            T { text: ">"; color: card.accent; font.bold: true }
            Rectangle {
                x: 2 * card.cw; y: (card.lh - height) / 2
                width: card.cw; height: Math.round(card.lh * 0.9)
                color: card.ink
                visible: card.cursorOn || !card.animate
            }
            T {
                x: 4 * card.cw; width: parent.width - x; elide: Text.ElideRight
                color: card.faint; text: "try: quickshell -p <Shell.qml> ipc call clawd play sit"
            }
        }
        T { x: 2 * card.cw; width: parent.width - x; elide: Text.ElideRight; color: card.faint; text: "? drag him anywhere · right-click him for his menu" }
    }
}
