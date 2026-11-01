import QtQuick
import "../"

// One line above his head while the lead session works, like Claude Code's spinner: "✻ Pondering… 12s".
// Mode full also flashes the current action ("Edit main.py") and cycles the session's stats. Takes no input (not in the mask).
// say: a line he mumbles in his sleep (pet.mumble), shown instead, with a "z".
Item {
    id: thought
    required property Item anchor
    readonly property var glyphs: ["·", "✢", "✳", "✶", "✻", "✽"]
    property int tick: 0
    property real now: Date.now()
    property var extra: null       // {text, warn}: an action flash or an info, over the verb line
    property real flashAt: 0
    property int infoIndex: 0
    property var shown: null       // the line on screen; swapped behind a short fade
    property string say: ""
    readonly property var line: say ? { text: say, warn: false, suffix: "" } : Clawd.thought(Clawd.thoughts, Clawd.lead, now, extra)
    readonly property string lineKey: line ? (line.suffix ? "v" : "x") + (line.warn ? "!" : " ") + line.text : ""
    readonly property string actionKey: Clawd.lead ? Clawd.lead.key + "\n" + Clawd.lead.tool + "\n" + Clawd.lead.target : ""
    readonly property string glyph: say ? "z" : Clawd.lowMotion ? "✻" : glyphs[tick % 10 < 6 ? tick % 10 : 10 - tick % 10]
    // own x/y: centered over the sprite, kept on screen
    x: Math.round(Math.max(0, Math.min((parent ? parent.width : 0) - width, anchor.x + (anchor.width - width) / 2)))
    y: Math.round(Math.max(0, anchor.y - height - Scaler.s(2)))
    width: row.implicitWidth + Scaler.s(12)
    height: row.implicitHeight + Scaler.s(2)

    component T: Text { font.family: ThemeBackend.fontFamily; font.pixelSize: Math.round(Scaler.s(12)); textFormat: Text.PlainText }

    // The lead's tool or target changed: "<Tool> <target>" for 2.5 s, at most every 5 s.
    function flash() {
        if (!visible || say || Clawd.thoughts !== "full") return;
        const text = Clawd.actionText(Clawd.lead);
        if (!text || Date.now() - flashAt < 5000) return;
        flashAt = Date.now();
        show({ text, warn: false }, 2500);
    }
    function cycle() {
        if (Clawd.thoughts !== "full" || extra || say) return;
        const info = Clawd.nextInfo(Clawd.lead, infoIndex);
        if (!info) return;
        infoIndex++;
        show(info, 4000);
    }
    function show(item, ms) { extra = item; hold.interval = ms; hold.restart(); }
    onActionKeyChanged: flash()
    onLineKeyChanged: if (Clawd.lowMotion || !visible || !shown) { swap.stop(); content.opacity = 1; shown = line; } else swap.restart()
    onVisibleChanged: { swap.stop(); content.opacity = 1; shown = line; now = Date.now(); if (!visible) { extra = null; hold.stop(); } }

    Timer { id: hold; onTriggered: thought.extra = null }
    Timer { interval: 14000; repeat: true; running: thought.visible && Clawd.thoughts === "full"; onTriggered: thought.cycle() }
    Timer { interval: 1000; repeat: true; running: thought.visible; onTriggered: thought.now = Date.now() }
    Timer { interval: 120; repeat: true; running: thought.visible && !Clawd.lowMotion; onTriggered: thought.tick = (thought.tick + 1) % 10 }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 75 }
        ScriptAction { script: thought.shown = thought.line }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 75 }
    }

    // a faint pill, just enough to read over a busy wallpaper
    Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.alpha(ThemeBackend.mantle, 0.35) }
    Item {
        id: content
        anchors.fill: parent
        Row {
            id: row
            anchors.centerIn: parent
            T { text: thought.glyph + " "; color: "#D97757" }
            T { objectName: "thoughtText"; text: thought.shown ? thought.shown.text : ""; color: thought.shown && thought.shown.warn ? ThemeBackend.peach : ThemeBackend.subtext0 }
            // the live clock, only behind the verb
            T { text: thought.shown && thought.shown.suffix && thought.line ? thought.line.suffix : ""; color: Qt.alpha(ThemeBackend.subtext0, 0.55) }
        }
    }
}
