import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Clawd's chat sidecar (node brain.js): JSONL requests on stdin, deltas and results on stdout. Started on the first rpc.
// Lives under the AddonClawd Loader, so OFF destroys it; never instantiated in the Settings process.
Scope {
    id: brain
    property var pending: ({})   // id -> {cb, until}
    property var queue: []       // lines written once the process is up
    property int serial: 0
    property int count: 0
    property int restarts: 0
    property bool wanted: false
    signal delta(string id, string text)

    // cb({ok, ...}) gets the result's data (or a synthetic failure); returns the request id.
    function rpc(method, args, cb, timeoutMs) {
        const id = "b" + (++serial);
        pending[id] = { cb, method, until: Date.now() + (timeoutMs || (method === "send" ? 95000 : 20000)) };
        count++;
        wanted = true;
        const line = JSON.stringify({ t: "chat.request", id, method, args: args || {} }) + "\n";
        if (proc.running) proc.write(line); else { queue.push(line); proc.running = true; }
        return id;
    }
    function finish(id, data) {
        const p = pending[id];
        if (!p) return;
        delete pending[id];
        count--;
        if (p.cb) p.cb(data);
    }
    function failAll(code) { for (const id of Object.keys(pending)) finish(id, { ok: false, error: code, code }); }
    function ingest(line) {
        let m = null;
        try { m = JSON.parse(line); } catch (error) { return; }
        restarts = 0;
        if (m.t === "chat.delta") brain.delta(m.id, String(m.text || ""));
        else if (m.t === "chat.result") finish(m.id, m.data || { ok: false, code: "failed" });
    }

    Process {
        id: proc
        command: ["node", Clawd.scripts + "/brain.js"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => brain.ingest(line) }
        stderr: SplitParser { onRead: line => { if (/error|exception|cannot|not found/i.test(line)) console.warn("Clawd brain:", line); } }
        onRunningChanged: if (running) { for (const l of brain.queue) write(l); brain.queue = []; }
        onExited: {
            brain.queue = [];
            brain.failAll("failed");
            if (brain.wanted && brain.restarts++ < 3) retry.start(); else brain.wanted = false;
        }
    }
    Timer { id: retry; interval: 5000; onTriggered: if (brain.wanted) proc.running = true }
    // request timeouts
    Timer {
        interval: 1000; repeat: true; running: brain.count > 0
        onTriggered: { const now = Date.now(); for (const id of Object.keys(brain.pending)) if (brain.pending[id].until < now) {
            const send = brain.pending[id].method === "send";
            brain.finish(id, { ok: false, error: "timeout", code: "failed" });
            if (send) brain.rpc("stop", { id }, () => {});  // the sidecar must abort the CLI too
        } }
    }
}
