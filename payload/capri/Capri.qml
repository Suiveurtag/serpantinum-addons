pragma Singleton
import QtQuick
import Quickshell
import "../"

// Exists separately in the shell and the Settings process; share state only through Config.
QtObject {
    id: capri
    readonly property bool enabled: Config.getSetting("addonsV2Capri", false)
    readonly property string motion: Config.getSetting("addonsV2CapriMotion", "auto")
    readonly property bool animationEnabled: enabled && (motion === "full" || (motion !== "reduced" && !Config.getSetting("general.performance", false)))
    readonly property string scripts: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/capri"
    readonly property var hookEvents: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "PreCompact", "SessionEnd", "Interrupt", "CapriShowcase"]
    property string screenName: ""
    property int instances: 0
    property int events: 0
    property var lastEvent: null
    property string reply: ""
    signal hookEvent(var evt)
    signal pcReaction(string kind, var data)
    signal command(string name, string arg)

    // An act or a move for her (IPC "act"), answered by the CapriEngine on her screen.
    function act(name, arg) {
        reply = "not on screen";
        command(name, arg);
        return reply;
    }

    // The Loader is being destroyed inside the enabled binding. Write its final state on the
    // singleton's next turn, after that binding has settled (also covers the Settings process).
    function saveFinal(bond, mission) {
        const b = JSON.parse(JSON.stringify(bond)), m = JSON.stringify(mission);
        Qt.callLater(() => {
            Config.setSetting("addonsV2CapriBond", b);
            Config.setSetting("addonsV2CapriState.capri.mission", m);
        });
    }

    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }

    // Trust boundary: anything on 127.0.0.1 or the IPC socket can reach this.
    function accept(evt) {
        if (!evt || typeof evt !== "object" || Array.isArray(evt) || hookEvents.indexOf(evt.hook_event_name) < 0) return false;
        for (const key of ["session_id", "cwd", "source", "tool_name", "notification_type", "message", "prompt", "last_assistant_message", "session_title", "agent_type"]) {
            if (evt[key] !== undefined && typeof evt[key] !== "string") return false;
        }
        if (evt.tool_input !== undefined && (!evt.tool_input || typeof evt.tool_input !== "object" || Array.isArray(evt.tool_input))) return false;
        events++;
        lastEvent = evt;
        hookEvent(evt);
        return true;
    }

    // One JSON line from the sidecar: {"t":"event","evt":{...}}.
    function ingest(line) {
        let message;
        try { message = JSON.parse(line); } catch (error) { console.warn("Capri: bad sidecar line", line.slice(0, 120)); return; }
        if (message && message.t === "event") accept(message.evt);
    }
}
