import QtQuick
import Quickshell
import "../"

// Left click on Clawd: his agent sessions as a terminal box, newest first. The circle follows; the rest of a row raises its terminal.
// Second tab (pet.journalTab "dreams"): his dream collection (Clawd.dreamBook,
// the ones he never had are ???) and the last dreams he had, with their time.
Item {
    id: journal
    required property var pet
    property Item anchor: null
    property real now: Date.now()
    readonly property int cols: 42
    readonly property var rows: Clawd.sessionChoices
    readonly property color accent: ThemeBackend.primary
    readonly property bool dreams: pet.journalTab === "dreams"
    readonly property var book: Clawd.dreamBook || []
    readonly property int seen: book.filter(d => d.seen).length
    readonly property var recent: (Clawd.dreams && Clawd.dreams.log || []).slice(0, 8)
    readonly property string tab2: "☾ dreams " + seen + "/" + book.length
    function entry(id) { return book.find(d => d.id === id) || { glyph: "?", title: id, kind: "dream" }; }
    function bookLine(d) { return cell(d.seen ? d.glyph + " " + d.title : "? ???", 24) + cell(d.kind, 11) + cell(d.seen ? "x" + d.n : "—", 7); }
    function when(at) {
        const d = new Date(at), today = new Date(now);
        return Qt.formatDateTime(d, d.toDateString() === today.toDateString() ? "HH:mm" : "ddd HH:mm");
    }
    function recentLine(r) { const d = entry(r.id); return cell(when(r.at), 10) + cell(d.glyph + " " + d.title, 22) + cell(r.kind === "nightmare" ? "nightmare" : "", 10); }
    width: box.implicitWidth
    height: box.implicitHeight
    x: anchor && parent ? Math.max(8, Math.min(parent.width - width - 8, anchor.x + (anchor.width - width) / 2)) : 0
    y: anchor ? (anchor.y - height - 8 >= 8 ? anchor.y - height - 8 : anchor.y + anchor.height + 8) : 0

    function cell(text, n) { text = String(text || "—"); return text.length > n ? text.slice(0, n - 1) + "…" : text + " ".repeat(n - text.length); }
    function ago(since) {
        const s = Math.max(0, Math.round((now - since) / 1000));
        return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h";
    }
    function identity(s) {
        const id = s.isSubagent ? s.subId : s.key.slice(s.key.indexOf(":") + 1);
        return (s.agent === "claude" ? "Cl" : "Co") + (s.isSubagent ? "↳" : "-")
            + String(id || "").replace(/[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "").slice(-5);
    }
    function sessionDescription(s) { return (s.agent === "claude" ? "Claude Code" : "Codex") + (s.isSubagent ? " subagent " + s.subType : " session") + " " + identity(s); }
    function line(s) {
        return (Clawd.followedSessionKey === s.key ? "●" : "○") + " " + ({ alert: "⚠", work: "✻", idle: "✓" })[s.phase] + " "
            + cell(identity(s), 8) + " " + cell(s.dir, 7) + " " + cell(s.isSubagent ? s.subType : s.tool, 7)
            + " " + cell(ago(s.since), 3) + " " + cell(Number.isFinite(s.ctx) ? Math.round(s.ctx) + "%" : "", 5);
    }

    Timer { interval: 1000; repeat: true; running: journal.visible; triggeredOnStart: true; onTriggered: journal.now = Date.now() }
    FontMetrics { id: metrics; font.family: ThemeBackend.fontFamily; font.pixelSize: 14 }
    Rectangle {
        anchors { fill: parent; leftMargin: metrics.averageCharacterWidth / 2; rightMargin: metrics.averageCharacterWidth / 2
            topMargin: metrics.height / 2; bottomMargin: metrics.height / 2 }
        color: ThemeBackend.base
        radius: 3
    }
    Column {
        id: box
        Row {
            Text { text: "╭─ "; color: journal.accent; font: metrics.font }
            Text {
                text: "✻ sessions"
                color: !journal.dreams || tab1.containsMouse ? journal.accent : ThemeBackend.subtext0
                font: metrics.font
                MouseArea { id: tab1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: journal.pet.journalTab = "sessions" }
            }
            Text { text: " ─ "; color: journal.accent; font: metrics.font }
            Text {
                text: journal.tab2
                color: journal.dreams || tab2.containsMouse ? journal.accent : ThemeBackend.subtext0
                font: metrics.font
                MouseArea { id: tab2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: journal.pet.journalTab = "dreams" }
            }
            Text { text: " " + "─".repeat(Math.max(1, journal.cols - 14 - journal.tab2.length)) + "╮"; color: journal.accent; font: metrics.font }
        }
        // dreams: the collection, then the last ones he had
        Repeater {
            model: journal.dreams ? journal.book : []
            Text {
                required property var modelData
                text: "│ " + journal.bookLine(modelData) + " │"
                color: !modelData.seen ? Qt.alpha(ThemeBackend.subtext0, 0.6) : modelData.kind === "nightmare" ? ThemeBackend.red : ThemeBackend.mauve
                font: metrics.font
            }
        }
        Text {
            visible: journal.dreams
            text: "├" + "─".repeat(journal.cols + 2) + "┤"
            color: journal.accent
            font: metrics.font
        }
        Text {
            visible: journal.dreams && journal.recent.length === 0
            text: "│ " + journal.cell("no dreams yet: let him sleep", journal.cols) + " │"
            color: ThemeBackend.subtext0
            font: metrics.font
        }
        Repeater {
            model: journal.dreams ? journal.recent : []
            Text {
                required property var modelData
                text: "│ " + journal.recentLine(modelData) + " │"
                color: ThemeBackend.subtext0
                font: metrics.font
            }
        }
        Text {
            visible: !journal.dreams && journal.rows.length === 0
            text: "│ " + journal.cell("no sessions", journal.cols) + " │"
            color: ThemeBackend.subtext0
            font: metrics.font
        }
        Item {
            visible: !journal.dreams && (journal.rows.length > 1 || !!Clawd.followedSessionKey)
            width: metrics.averageCharacterWidth * (journal.cols + 4)
            height: visible ? metrics.height : 0
            Accessible.role: Accessible.RadioButton
            Accessible.name: "Follow automatically"
            Accessible.checkable: true
            Accessible.checked: !Clawd.followedSessionKey
            activeFocusOnTab: true
            Keys.onReturnPressed: Clawd.selectSession("")
            Text {
                anchors.fill: parent
                text: "│ " + journal.cell((Clawd.followedSessionKey ? "○" : "●") + " follow: auto", journal.cols) + " │"
                color: Clawd.followedSessionKey ? ThemeBackend.subtext0 : journal.accent
                font: metrics.font
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clawd.selectSession("")
            }
        }
        // One click target per row: the circle (column 2) selects it, the rest raises its terminal.
        Repeater {
            model: journal.dreams ? [] : journal.rows
            Item {
                id: sessionRow
                required property var modelData
                width: metrics.averageCharacterWidth * (journal.cols + 4)
                height: metrics.height
                Accessible.role: Accessible.RadioButton
                Accessible.name: journal.sessionDescription(sessionRow.modelData) + (Clawd.followedSessionKey === sessionRow.modelData.key ? ", followed" : "")
                Accessible.checkable: true
                Accessible.checked: Clawd.followedSessionKey === sessionRow.modelData.key
                activeFocusOnTab: true
                Keys.onReturnPressed: Clawd.selectSession(sessionRow.modelData.key)
                Text {
                    id: rowText
                    anchors.fill: parent
                    text: "│ " + journal.cell(journal.line(sessionRow.modelData), journal.cols) + " │"
                    color: sessionRow.modelData.phase === "alert" ? ThemeBackend.peach
                        : Clawd.followedSessionKey === sessionRow.modelData.key || hover.containsMouse ? journal.accent : ThemeBackend.subtext0
                    font: metrics.font
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.x < metrics.averageCharacterWidth * 3) Clawd.selectSession(sessionRow.modelData.key);
                        else { Clawd.focus(sessionRow.modelData.parentKey); journal.pet.journalOpen = false; }
                    }
                }
            }
        }
        Text {
            text: "╰" + "─".repeat(journal.cols + 2) + "╯"
            color: journal.accent
            font: metrics.font
        }
    }
}
