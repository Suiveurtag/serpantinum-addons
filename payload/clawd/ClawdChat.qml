import QtQuick
import Quickshell
import "../"

// Terminal chat with Clawd (opened by pet.chatOpen): last lines of the talk, a prompt, [look] and [clear].
// The answers come from the node sidecar through ClawdBrain.
FocusScope {
    id: chat
    required property var pet
    property var brain: null
    property Item anchor: null
    property var history: []       // [{role: "user" | "clawd", text}]
    property string draft: ""      // the answer streaming in
    property string note: ""       // an error line
    property bool pending: false
    property bool slow: false      // pending for a while: "thinking"
    property string reqId: ""
    readonly property int cols: 40
    readonly property int rowsShown: 8
    readonly property color accent: ThemeBackend.primary
    readonly property real cw: metrics.advanceWidth("m")
    readonly property var lines: {
        const out = [];
        const add = (prefix, text, color) => wrap(text, cols - 2).forEach((l, i) => out.push({ text: (i ? "  " : prefix) + l, color }));
        for (const h of history) add(h.role === "user" ? "> " : "✻ ", h.text, h.role === "user" ? ThemeBackend.subtext0 : ThemeBackend.text);
        if (draft) add("✻ ", draft, ThemeBackend.text);
        if (note) out.push({ text: note, color: ThemeBackend.peach });
        else if (pending && slow && !draft) out.push({ text: "… thinking", color: ThemeBackend.subtext0 });
        return out.slice(-rowsShown);
    }
    width: top.implicitWidth
    height: box.implicitHeight
    x: anchor && parent ? Math.max(8, Math.min(parent.width - width - 8, anchor.x + (anchor.width - width) / 2)) : 0
    y: anchor ? (anchor.y - height - 8 >= 8 ? anchor.y - height - 8 : anchor.y + anchor.height + 8) : 0

    function wrap(text, n) {
        const out = [];
        for (const para of String(text).split("\n")) {
            let cur = "";
            for (let w of para.split(/\s+/)) {
                while (w.length > n) { if (cur) { out.push(cur); cur = ""; } out.push(w.slice(0, n)); w = w.slice(n); }
                if (!w) continue;
                if (cur && cur.length + 1 + w.length > n) { out.push(cur); cur = w; } else cur = cur ? cur + " " + w : w;
            }
            out.push(cur);
        }
        return out;
    }
    function pad(text) { text = String(text); return text.length >= cols ? text.slice(0, cols) : text + " ".repeat(cols - text.length); }
    function clip(text, n) { text = String(text || ""); return text.length > n ? text.slice(0, n - 1) + "…" : text; }

    // What Clawd knows right now, for the model: no commands, no paths (targets are already short).
    function context() {
        const parts = ["time " + new Date().toLocaleTimeString(Qt.locale(), "HH:mm"), "mode " + pet.mode + (pet.mood ? " mood " + pet.mood : "")];
        const entries = Object.values(Clawd.sessions).sort((a, b) => b.last - a.last).slice(0, 8);
        if (!entries.length) parts.push("no agent sessions");
        for (const s of entries) {
            const q = [];
            if (Number.isFinite(s.ctx)) q.push("ctx " + Math.round(s.ctx) + "%");
            if (Number.isFinite(s.five_hour)) q.push("5h " + Math.round(s.five_hour) + "%");
            if (Number.isFinite(s.seven_day)) q.push("7d " + Math.round(s.seven_day) + "%");
            parts.push(clip(s.agent, 12) + " " + (s.phase === "work" ? "busy" : s.phase) + (s.tool ? " " + clip(Clawd.toolAnim(s.tool), 12) + " " + clip(s.tool, 24) : "")
                + (s.target ? " " + clip(s.target, 40) : "") + (q.length ? " (" + q.join(", ") + ")" : ""));
        }
        return parts.join("\n").slice(0, 4000);
    }
    function load() {
        if (!brain) return;
        brain.rpc("history", {}, d => { if (d && d.ok && Array.isArray(d.history)) history = d.history.map(h => ({ role: h.role === "user" ? "user" : "clawd", text: String(h.text || "") })); });
    }
    function say(raw, look) {
        let text = String(raw).trim();
        if (/^\/look(\s|$)/.test(text)) { look = true; text = text.slice(5).trim(); }
        if (look && !text) text = "What do you see on my screen?";
        if (!text || pending || !brain) return;
        input.text = "";
        note = ""; draft = ""; slow = false; pending = true;
        pet.chatPhase = "wait";
        history = history.concat([{ role: "user", text }]);
        reqId = brain.rpc("send", { text, context: context(), look: !!look, output: Clawd.screenName, provider: Clawd.chatProvider, model: Clawd.chatModel, url: Clawd.chatUrl }, d => answer(d));
        slowTimer.restart();
    }
    function answer(d) {
        pending = false; slowTimer.stop(); draft = ""; reqId = "";
        if (d && d.ok) {
            history = history.concat([{ role: "clawd", text: String(d.text || "") }]);
            if (visible) { pet.chatPhase = "talk"; talkTimer.restart(); } else pet.chatPhase = "";
        } else {
            pet.chatPhase = "";
            const code = d && d.code;
            note = code === "signin" ? (Clawd.chatProvider === "codex" ? "✗ sign in: codex login" : "✗ check api key") : code === "busy" ? "… busy, try later" : code === "stopped" ? "" : code === "running" ? "… still thinking" : "✗ failed";
        }
        if (visible) input.forceActiveFocus();
    }
    function forget() {
        if (!brain) return;
        brain.rpc("forget", {}, () => {});
        history = []; draft = ""; note = "";
    }

    Connections {
        target: chat.brain
        function onDelta(id, text) { if (id === chat.reqId) { chat.draft += text; } }
    }
    Timer { id: slowTimer; interval: 1800; onTriggered: chat.slow = true }
    Timer { id: talkTimer; interval: 2500; onTriggered: if (chat.pet.chatPhase === "talk") chat.pet.chatPhase = "" }
    onVisibleChanged: {
        if (visible) { note = ""; load(); input.forceActiveFocus(); }
        else if (pet.chatPhase !== "talk") pet.chatPhase = "";
    }
    Keys.onEscapePressed: pet.chatOpen = false

    FontMetrics { id: metrics; font.family: ThemeBackend.fontFamily; font.pixelSize: 14 }
    Rectangle {
        anchors { fill: parent; leftMargin: metrics.averageCharacterWidth / 2; rightMargin: metrics.averageCharacterWidth / 2
            topMargin: metrics.height / 2; bottomMargin: metrics.height / 2 }
        color: ThemeBackend.base
        radius: 3
    }
    Column {
        id: box
        Text {
            id: top
            text: "╭─ ✻ clawd " + "─".repeat(chat.cols - 8) + "╮"
            color: chat.accent
            font: metrics.font
        }
        Repeater {
            model: chat.rowsShown
            Text {
                required property int index
                readonly property var row: chat.lines[index - (chat.rowsShown - chat.lines.length)] || null
                text: "│ " + chat.pad(row ? row.text : "") + " │"
                color: row ? row.color : ThemeBackend.subtext0
                font: metrics.font
            }
        }
        Item {
            width: top.implicitWidth; height: metrics.height
            Text { text: "│"; color: chat.accent; font: metrics.font }
            Text { x: 2 * chat.cw; text: ">"; color: chat.accent; font: metrics.font }
            TextInput {
                id: input
                objectName: "clawdChatInput"
                x: 4 * chat.cw; width: (chat.cols - 2) * chat.cw; height: parent.height
                font: metrics.font
                color: ThemeBackend.text
                selectionColor: chat.accent
                selectedTextColor: ThemeBackend.base
                maximumLength: 2000
                clip: true
                readOnly: chat.pending
                onAccepted: if (!chat.pending) chat.say(text, false)
                Keys.onEscapePressed: chat.pet.chatOpen = false
            }
            Text { x: (chat.cols + 3) * chat.cw; text: "│"; color: chat.accent; font: metrics.font }
        }
        Item {
            width: top.implicitWidth; height: metrics.height
            Text { text: "│"; color: chat.accent; font: metrics.font }
            Text {
                id: look
                objectName: "clawdChatLook"
                x: 2 * chat.cw; text: "[look]"; font: metrics.font
                color: lookArea.containsMouse ? chat.accent : ThemeBackend.subtext0
                MouseArea { id: lookArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chat.say(input.text, true) }
            }
            Text {
                id: clear
                objectName: "clawdChatClear"
                x: 9 * chat.cw; text: "[clear]"; font: metrics.font
                color: clearArea.containsMouse ? chat.accent : ThemeBackend.subtext0
                MouseArea { id: clearArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chat.forget() }
            }
            Text { x: (chat.cols - 8) * chat.cw; text: "esc close"; color: ThemeBackend.surface2; font: metrics.font }
            Text { x: (chat.cols + 3) * chat.cw; text: "│"; color: chat.accent; font: metrics.font }
        }
        Text {
            text: "╰" + "─".repeat(chat.cols + 2) + "╯"
            color: chat.accent
            font: metrics.font
        }
    }
}
