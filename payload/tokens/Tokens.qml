pragma Singleton
import QtQuick
import Quickshell.Io
import "../"

// Reads the collector's state.json. Exists only once a tokens widget references it; idle cost is one inotify watch and a 30 s timer.
QtObject {
    id: root

    property var data: null
    property double now: Date.now() / 1000
    readonly property bool stale: !data || now - (data.updated || 0) > 150
    readonly property real codex: data && data.codex.total !== null ? data.codex.total : 0
    readonly property real claude: data ? data.claude.total : 0
    readonly property real opencode: data && data.sources && data.sources.opencode ? data.sources.opencode.total : 0
    readonly property real llamacpp: data && data.sources && data.sources.llamacpp ? data.sources.llamacpp.total : 0
    readonly property real total: data ? data.combined.total : 0
    readonly property bool active: !stale && !!data && data.active
    readonly property bool complete: !stale && !!data && data.combined.complete

    function compact(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(2) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k";
        return String(Math.round(n));
    }
    function ago(epoch) {
        const m = Math.max(0, Math.round((now - epoch) / 60));
        return m < 1 ? qsTr("just now") : m < 60 ? qsTr("%1 min ago").arg(m) : qsTr("%1 h ago").arg(Math.round(m / 60));
    }
    readonly property string codexNote: {
        if (!data) return qsTr("collector not running");
        const c = data.codex;
        if (c.status === "no-baseline") return qsTr("no account total");
        if (c.status === "partial") return qsTr("offline, synced %1").arg(ago(c.synced));
        return qsTr("synced %1").arg(ago(c.synced));
    }
    readonly property string claudeNote: !data ? "" : data.claude.since ? qsTr("local since %1").arg(data.claude.since) : qsTr("no transcripts found")
    readonly property string opencodeNote: {
        if (!data) return qsTr("collector not running");
        const s = data.sources ? data.sources.opencode : null;
        if (!s) return qsTr("off");
        if (s.status === "error") return qsTr("unreadable");
        return qsTr("%1 sessions").arg(s.sessions);
    }
    readonly property string llamacppNote: {
        if (!data) return qsTr("collector not running");
        const s = data.sources ? data.sources.llamacpp : null;
        if (!s) return qsTr("off");
        if (s.status === "error") return qsTr("not running");
        return qsTr("live");
    }
    readonly property string status: stale ? qsTr("collector stopped") : !data.combined.complete ? qsTr("partial") : data.importing ? qsTr("importing") : ""

    property FileView file: FileView {
        path: Caching.stateDir + "/tokens/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.data = JSON.parse(text()); } catch (e) { /* half-written or missing: keep the last good state */ }
            root.now = Date.now() / 1000;
        }
    }
    property Timer clock: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
}
