pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"
import "js/mind.mjs" as Mind
import "js/acts.mjs" as Acts
import "js/dreams.mjs" as Dreams
import "js/effort.mjs" as Effort

// Exists separately in the shell and the Settings process; share state only through Config.
QtObject {
    id: clawd
    readonly property bool enabled: Config.getSetting("addonsV2Clawd", false) === true
    readonly property int scale: Math.max(2, Math.min(8, Math.round(Number(Config.getSetting("addonsV2ClawdScale", 4))) || 4))
    // The specials were drawn on a finer grid (his body is 16 cells wide there, 13 in the pet's own strips): a smaller (fractional) pixel evens his size out.
    function unit(clip) { return clip && clip.file && clip.w && clip.h ? scale * 0.65 : scale; }
    readonly property string speed: ["calm", "normal", "active"].indexOf(Config.getSetting("addonsV2ClawdSpeed", "normal")) >= 0 ? Config.getSetting("addonsV2ClawdSpeed", "normal") : "normal"
    readonly property int sleepMinutes: Math.max(1, Math.min(60, Math.round(Number(Config.getSetting("addonsV2ClawdSleep", 5))) || 5))
    readonly property bool lowMotion: Config.getSetting("general.performance", false) === true
    // Thought line above his head while an agent works: full (verb + actions + stats), verbs, off.
    readonly property string thoughts: ["full", "verbs", "off"].indexOf(Config.getSetting("addonsV2ClawdThoughts", "full")) >= 0 ? Config.getSetting("addonsV2ClawdThoughts", "full") : "full"
    // The windows around him (perching, peeking, exploring, window reactions); following the cursor to another screen.
    readonly property bool world: Config.getSetting("addonsV2ClawdWorld", true) !== false
    // Talk to him in a terminal panel (node sidecar, ChatGPT through Codex).
    readonly property bool chat: Config.getSetting("addonsV2ClawdChat", true) !== false
    readonly property bool follow: Config.getSetting("addonsV2ClawdFollow", true) !== false
    // His body and the spinner line take the lead session's effort colour while it works (js/effort.mjs, shaders/tint.frag).
    readonly property bool effortColors: Config.getSetting("addonsV2ClawdEffort", true) !== false
    // How much he reacts to the shell (music, notifications, volume...): all | quiet (urgent, bubbles, moods) | off (urgent only).
    readonly property string reactions: ["all", "quiet", "off"].indexOf(Config.getSetting("addonsV2ClawdReactions", "all")) >= 0 ? Config.getSetting("addonsV2ClawdReactions", "all") : "all"
    readonly property bool dnd: Config.getSetting("notifications.dnd", false) === true
    property string screenName: ""
    property int instances: 0
    property var manifest: null
    readonly property string scripts: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/serpantinum-addons-v2/scripts/clawd"
    // Claude Code / Codex sessions from the hook socket (shell process only):
    // "agent:session_id" -> {agent, dir, phase, last, tool, target, pids, since, verb, verbAt, model, effort, ctx, cost, five_hour, seven_day};
    // tool/target = last tool used this turn and its short target, pids = the hook's ancestors, stats from the status line relay.
    // phase: work | alert | idle. Kept while Clawd is OFF so he shows the right state when he comes back.
    property var sessions: ({})
    // Quota windows are tracked per provider and window, independently of sessions.
    property var quotas: Config.getSetting("addonsV2ClawdQuotas", {})
    property var dreams: Config.getSetting("addonsV2ClawdDreams", { seen: {}, log: [] })  // what he dreamed: {seen: {id: {n, first, last}}, log: [{id, kind, at}]}
    readonly property var dreamBook: Dreams.book(dreams)
    property var observed: ({})
    property var codexResets: Config.getSetting("addonsV2ClawdCodexResets", {})  // {seen: id of the last announcement handled, done: [scheduled ids played]}
    property var codexSchedule: null  // {id, at}: a reset announced for a later time (codex-resets.com)
    property real lastResetAt: 0      // seconds of the last reset scene queued, whatever its source
    property var bubble: null      // {key, kind: permission | done | waiting | error, text}
    property int staleMs: 120000
    property var verbs: ["Thinking"]   // Claude Code's spinner verbs (verbs.py), until loaded
    property real verbsAt: 0
    property var dice: null        // test hook: a fixed roll in [0, 1) instead of Math.random()
    readonly property string activity: {
        const phases = Object.values(sessions).map(s => s.phase);
        return phases.indexOf("alert") >= 0 ? "alert" : phases.indexOf("work") >= 0 ? "work" : "";
    }
    // The lead: the working session that moved last; he plays its tool and thinks its thoughts.
    readonly property var lead: {
        let best = null;
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "work" && (!best || s.last >= best.last)) best = Object.assign({ key }, s);
        return best;
    }
    readonly property string workAnim: toolAnim(lead ? lead.tool : "")
    readonly property bool strained: !!lead && (lead.ctx >= 80 || lead.five_hour >= 90)
    readonly property real effortSpeed: lead ? effortRate(lead.effort) : 1
    // {mode, color} while the lead session works (more than one sub-agent running makes Claude "fake ultracode"), else null.
    readonly property var effortStyle: effortColors && activity === "work" && lead ? Effort.style(lead.agent, lead.effort, subList(lead).length) : null
    function effortColor(step) { return Effort.textColor(effortStyle, step); }
    function effortSparks() { return Effort.sparks(effortStyle); }
    readonly property bool thinking: thoughts !== "off" && activity === "work" && !!lead
    readonly property int busyCount: Object.values(sessions).filter(s => s.phase !== "idle").length

    // Claude Code and Codex tool names -> his working loop; anything else (MCP...) types.
    function toolAnim(tool) {
        const t = String(tool || "");
        if (["Read", "NotebookRead", "view_image"].indexOf(t) >= 0) return "read";
        if (["Bash", "BashOutput", "KillShell", "exec_command", "write_stdin", "shell", "local_shell"].indexOf(t) >= 0) return "bash";
        if (["Grep", "Glob", "LS", "ToolSearch"].indexOf(t) >= 0) return "search";
        if (["WebFetch", "WebSearch", "web_search"].indexOf(t) >= 0) return "web";
        if (["Task", "Agent", "spawn_agent"].indexOf(t) >= 0) return "task";
        if (["TodoWrite", "update_plan"].indexOf(t) >= 0) return "todo";
        if (["Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch"].indexOf(t) >= 0) return "edit";
        return "work";
    }
    function effortRate(effort) {
        const v = ({ low: 0.75, medium: 1, high: 1.25, xhigh: 1.5, max: 1.5 })[effort];
        return typeof v === "number" ? v : 1;
    }
    function roll() { return typeof dice === "number" ? dice : Math.random(); }
    function pick(list) { return list[Math.min(list.length - 1, Math.floor(roll() * list.length))]; }
    // name or its "_2" variant when the manifest has one, at random.
    function variant(name) { return manifest && manifest.animations[name + "_2"] && roll() < 0.5 ? name + "_2" : name; }

    // Thought line pieces, pure so they can be checked without waiting.
    function clip(text, n) { text = String(text); return text.length > n ? text.slice(0, Math.max(0, n - 1)) + "…" : text; }
    function elapsed(ms) {
        const s = Math.max(0, Math.floor(ms / 1000)), pad = n => (n < 10 ? "0" : "") + n;
        return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m " + pad(s % 60) + "s" : Math.floor(s / 3600) + "h " + pad(Math.floor(s / 60) % 60) + "m";
    }
    function actionText(s) { return s && s.tool ? clip(s.target ? s.tool + " " + s.target : s.tool, 40) : ""; }
    // "claude-sonnet-5-5" -> "Sonnet 5.5"; other ids as they are.
    function modelName(id) {
        const m = /^claude-(opus|sonnet|haiku)-(\d+)-(\d+)(?:-\d{8})?$/.exec(String(id || ""));
        return m ? m[1][0].toUpperCase() + m[1].slice(1) + " " + m[2] + "." + m[3] : String(id || "");
    }
    // The running sub-agents of session s (SubagentStop leaves a short tombstone that only blocks late hooks).
    function subList(s) { return Object.values((s && s.subs) || {}).filter(v => !v.ended); }
    // The sub-agent of session s that moved last (its stats known, not stale), or null.
    function activeSub(s) {
        let best = null;
        for (const sub of subList(s)) if ((sub.model || Number.isFinite(sub.tokens)) && (!best || sub.last >= best.last)) best = sub;
        // a sub-agent in one long reply fires no hooks for a while: kept until its SubagentStop (or 10 min, as pruned in ingest)
        return best && Date.now() - best.last < 600000 ? best : null;
    }
    // What the info cycle can show for a session, strained values flagged. With sub-agents running, one more entry gives
    // their count with the model and context (last reply's input tokens over the window) of the one that moved last.
    function infos(s) {
        if (!s) return [];
        const out = [], pct = v => Math.round(v) + "%", sub = activeSub(s), count = subList(s).length;
        if (s.model) out.push({ text: s.model + (s.effort ? " · " + s.effort : ""), warn: false });
        if (Number.isFinite(s.ctx)) out.push({ text: "ctx " + pct(s.ctx), warn: s.ctx >= 80 });
        if (count > 0) {
            const subCtx = sub && Number.isFinite(sub.tokens) && s.ctx_size > 0 ? sub.tokens / s.ctx_size * 100 : undefined;
            out.push({ text: count + " sub-agent" + (count > 1 ? "s" : "") + (sub && sub.model ? " · " + modelName(sub.model) : "") + (Number.isFinite(subCtx) ? " · ctx " + pct(subCtx) : ""),
                       warn: Number.isFinite(subCtx) && subCtx >= 80 });
        }
        if (Number.isFinite(s.cost)) out.push({ text: "$" + s.cost.toFixed(2), warn: false });
        if (Number.isFinite(s.five_hour)) out.push({ text: "5h " + pct(s.five_hour) + (Number.isFinite(s.seven_day) ? " · 7d " + pct(s.seven_day) : ""), warn: s.five_hour >= 90 });
        return out;
    }
    // The i-th info to show; warnings win over everything else.
    function nextInfo(s, i) {
        const all = infos(s), warn = all.filter(x => x.warn), pool = warn.length ? warn : all;
        return pool.length ? pool[i % pool.length] : null;
    }
    // {text, warn, suffix} for mode, lead session s, clock now and a flash/info override; null = nothing to show.
    function thought(mode, s, now, extra) {
        if (!s || mode === "off") return null;
        if (extra && mode === "full") return { text: clip(extra.text, 40), warn: !!extra.warn, suffix: "" };
        const suffix = " " + elapsed(now - s.since);
        return { text: clip((s.verb || verbs[0] || "Thinking") + "…", 40 - suffix.length), warn: false, suffix };
    }
    signal command(string name, string arg)
    signal sessionStarted()   // a new agent session (not a compaction restart): revives a dead Clawd

    function mounted() { instances++; }
    function unmounted() { instances = Math.max(0, instances - 1); }

    // One hook line. The socket is a trust boundary: parse defensively, whitelist, cap, never execute.
    function ingest(line) {
        let e;
        try { e = JSON.parse(line); } catch (error) { return; }
        if (!e || typeof e !== "object" || ["claude", "codex"].indexOf(e.agent) < 0 || typeof e.event !== "string") return;
        const key = e.agent + ":" + (typeof e.session_id === "string" && e.session_id ? e.session_id.slice(0, 80) : "default");
        const next = Object.assign({}, sessions);
        const was = next[key];
        // control characters and bidi overrides out of everything shown
        const str = (v, n) => typeof v === "string" ? v.replace(/[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "").slice(0, n) : "";
        const dir = str(e.dir, 40) || (was ? was.dir : "");
        const where = dir || e.agent;
        const pids = Array.isArray(e.pids) ? e.pids.filter(p => Number.isInteger(p) && p > 1).slice(0, 16) : [];
        const now = Date.now();
        const model = str(e.model, 40);
        const effort = str(e.effort, 16);   // Codex hooks read it from the rollout; Claude's comes with the Status line
        const sid = typeof e.agent_id === "string" ? e.agent_id.replace(/[^\w-]/g, "").slice(0, 80) : "";  // set when the hook fired inside a sub-agent
        // stats, verb and target carry over; extra overrides
        const set = (phase, tool, fresh, extra) => {
            next[key] = Object.assign({ target: "" }, was, { agent: e.agent, dir, phase, last: now, tool: tool !== undefined ? tool : was ? was.tool : "",
                pids: pids.length ? pids : was ? was.pids : [], since: !fresh && was ? was.since : now }, model ? { model } : {}, effort ? { effort } : {}, extra || {});
        };
        let react = "", fresh = false;
        switch (e.event) {
        case "SessionStart":
            // Claude starts the session again after each compaction (source "compact"): no greeting then
            react = was && was.compacting ? "" : "wave";
            fresh = react === "wave";
            if (was && (model || was.compacting)) set(was.phase, undefined, false, { compacting: false });
            loadVerbs();
            break;
        case "UserPromptSubmit": set("work", "", true, { target: "", verb: pick(verbs), verbAt: now }); react = variant("think"); dismiss(key); break;
        case "PreCompact": set(was ? was.phase : "work", undefined, false, { compacting: true }); react = "compact"; break;
        case "PreToolUse":
        case "PostToolUse":
        case "PostToolUseFailure": {
            // Claude's async hooks may land after Stop: only a new prompt revives an idle session,
            // or a sub-agent still running in the background (it wakes him until its SubagentStop).
            const running = sid && was && was.subs && was.subs[sid] && !was.subs[sid].ended;
            if (was && was.phase === "idle" && !running) { set("idle"); break; }
            const wake = !!was && was.phase === "idle";
            // The lead thread plays its own tool; a sub-agent's takes over once the lead thread has been quiet for 5 s.
            const takes = !sid || wake || Date.now() - (was && was.mainAt || 0) >= 5000;
            set("work", takes && typeof e.tool_name === "string" ? e.tool_name.slice(0, 40) : undefined, wake,
                Object.assign(sid ? (wake ? { subOnly: true } : {}) : { mainAt: now, subOnly: false }, takes && e.event === "PreToolUse" ? { target: str(e.target, 24) } : {}));
            dismiss(key, "permission");
            if (e.event === "PostToolUseFailure") react = "oops";
            break;
        }
        case "Notification":
            if (e.notification_type === "permission_prompt") { set("alert"); say(key, "permission", "⚠ permission · " + where); }
            else if (["idle_prompt", "agent_needs_input"].indexOf(e.notification_type) >= 0) {
                if (was) set(was.phase);
                if (!bubble || bubble.kind !== "permission") say(key, "waiting", "… waiting · " + where);
            } else return;
            break;
        case "Stop":
            react = was && was.phase !== "idle" && now - was.since >= 180000 ? "celebrate" : variant("happy");  // long turns get confetti
            set("idle"); say(key, "done", "✓ done · " + where);
            break;
        case "StopFailure": set("idle"); react = "sad"; say(key, "error", "✗ error · " + where); break;
        case "Status": {
            // the status line relay: stats only, never a phase change (an unknown session starts idle)
            const s = Object.assign({ agent: e.agent, phase: "idle", last: now, tool: "", target: "", pids, since: now }, was, { dir });
            if (pids.length) s.pids = pids;
            if (model) s.model = model;
            if (str(e.effort, 16)) s.effort = str(e.effort, 16);
            for (const k of ["ctx", "ctx_size", "cost", "five_hour", "seven_day", "five_hour_resets", "seven_day_resets"]) if (typeof e[k] === "number" && Number.isFinite(e[k])) s[k] = e[k];
            if (was && Number.isFinite(was.cost) && Number.isFinite(s.cost) && Math.floor(s.cost / 5) > Math.floor(was.cost / 5)) react = "coin";
            updateQuotas(e.agent, e);
            // status refreshes are frequent: no churn when nothing moved
            if (!react && was && Object.keys(s).length === Object.keys(was).length && Object.keys(s).every(k => JSON.stringify(s[k]) === JSON.stringify(was[k]))) return;
            next[key] = s;
            break;
        }
        case "SubagentStart":
        case "SubagentStop": {
            // the sub-agent's own entry is written below; an untracked session starts idle, as with a status line.
            // The last sub-agent of a session that only it kept awake puts him back to sleep.
            const others = Object.entries((was && was.subs) || {}).filter(([k, v]) => k !== sid && !v.ended);
            if (was && e.event === "SubagentStop" && was.subOnly && !others.length) set("idle");
            else if (was) set(was.phase);
            break;
        }
        case "Interrupt": set("idle"); dismiss(key); break;
        case "SessionEnd": delete next[key]; dismiss(key); break;
        default: return;
        }
        // sub-agents of the session (hooks fired inside one carry its id): the model and tokens of its last reply, a tombstone at its stop
        if (sid) {
            const base = next[key] || { agent: e.agent, dir, phase: "idle", last: now, tool: "", target: "", pids, since: now };
            const subs = Object.assign({}, base.subs), old = subs[sid];
            if (e.event === "SubagentStop") subs[sid] = Object.assign({}, old, { last: now, ended: now });
            else if (!(old && old.ended && e.event !== "SubagentStart")) {  // a late hook never brings a stopped one back
                subs[sid] = Object.assign({}, old, { type: str(e.agent_type, 40), last: now },
                    str(e.sub_model, 40) ? { model: str(e.sub_model, 40) } : {}, Number.isFinite(e.sub_tokens) ? { tokens: e.sub_tokens } : {});
                delete subs[sid].ended;
            }
            const live = Object.entries(subs).filter(([, v]) => v.ended ? now - v.ended < 30000 : now - v.last < 600000).sort((a, b) => b[1].last - a[1].last).slice(0, 12);
            next[key] = Object.assign({}, base, { subs: live.reduce((o, [k, v]) => Object.assign(o, { [k]: v }), {}) });  // no Object.fromEntries in QML's engine
        }
        sessions = next;
        if (react) command("react", react);
        if (fresh) sessionStarted();
    }
    function recordDream(id, kind) {
        dreams = Dreams.record(dreams, id, kind, Date.now());
        Config.setSetting("addonsV2ClawdDreams", dreams);
    }
    function saveQuotas(next) {
        if (JSON.stringify(next) === JSON.stringify(quotas)) return;
        quotas = next;
        Config.setSetting("addonsV2ClawdQuotas", next);
    }
    function updateQuotas(agent, e) {
        const next = Object.assign({}, quotas), seen = Object.assign({}, observed), events = [], now = Date.now() / 1000;
        for (const w of ["five_hour", "seven_day"]) {
            const used = e[w], key = agent + ":" + w, was = next[key];
            if (!Number.isFinite(used)) continue;
            const resets = Number.isFinite(e[w + "_resets"]) ? e[w + "_resets"] : (was ? was.resets : 0);
            if (was && resets && was.resets && resets < was.resets) continue;
            if (was && was.consumed && resets === was.resets) continue;
            const changed = !!(was && resets && was.resets && resets > was.resets && was.resets <= now);
            if (changed && !was.consumed && w === "five_hour") events.push("recharge");
            // a Codex banked reset spent early: the used % falls well below what the window had reached
            const early = agent === "codex" && !!(was && !changed && !was.consumed && was.used - used >= 10);
            if (early) events.push("recharge");
            const fired = was && !changed && !early && was.fired;
            const crossed = !!(seen[key] && was && !changed && was.used < 100 && used >= 100 && !fired);
            if (crossed) events.push(w === "five_hour" ? "nuke" : "limit7");  // limit7: the singularity or the surge
            next[key] = { used: was && !changed && !early ? Math.max(was.used, used) : used, resets, fired: !!fired || crossed,
                          watched: resets > now || !!(was && !changed && was.watched), consumed: false };
            seen[key] = true;
        }
        observed = seen;
        saveQuotas(next);
        resetScene(events);
    }
    // At most one reset scene per reset: a banked or announced reset can show up in several sources at once.
    function resetScene(events) {
        let reset = false;
        for (const event of events) {
            if (event === "recharge") { if (!reset) command("quota", event); reset = true; }
            else command("quota", event);
        }
        if (reset) lastResetAt = Date.now() / 1000;
    }
    function ingestCodexResets(text) {
        let data = null;
        try { data = JSON.parse(text).data; } catch (error) { return; }
        if (!data) return;
        const done = (codexResets.done || []).slice(-20), now = Date.now() / 1000, latest = data.latest_reset, sched = data.scheduled_reset;
        let seen = codexResets.seen, play = false;
        if (latest && latest.id !== seen) {
            // the first poll only establishes the state; a banked announcement only adds a reset to the bank
            if (seen && latest.reset_type !== "banked") play = true;
            seen = latest.id;
        }
        const at = sched && sched.scheduled_for ? Date.parse(sched.scheduled_for) / 1000 : 0;
        codexSchedule = sched && at && done.indexOf(sched.id) < 0 ? { id: sched.id, at } : null;
        if (play && now - lastResetAt > 1800) resetScene(["recharge"]);
        if (seen !== codexResets.seen) {
            codexResets = { seen, done };
            Config.setSetting("addonsV2ClawdCodexResets", codexResets);
        }
    }
    function checkCodexSchedule() {
        const sched = codexSchedule, now = Date.now() / 1000;
        if (!sched || sched.at > now) return;
        codexSchedule = null;
        codexResets = { seen: codexResets.seen, done: (codexResets.done || []).concat([sched.id]).slice(-20) };
        Config.setSetting("addonsV2ClawdCodexResets", codexResets);
        if (now - sched.at < 3600 && now - lastResetAt > 1800) resetScene(["recharge"]);  // a long-gone announcement is not replayed
    }
    function checkQuotaResets() {
        const next = Object.assign({}, quotas), events = [], now = Date.now() / 1000;
        for (const key of Object.keys(next)) {
            const q = next[key];
            if (!q.watched || q.consumed || q.resets > now) continue;
            next[key] = Object.assign({}, q, { used: 0, consumed: true });
            if (key.endsWith(":five_hour")) events.push("recharge");
        }
        saveQuotas(next);
        resetScene(events);
    }
    readonly property QtObject quotaTimer: Timer {
        interval: 1000; repeat: true; running: clawd.enabled
        onTriggered: { clawd.checkQuotaResets(); clawd.checkCodexSchedule(); }
    }
    // Announced and banked Codex resets (codex-resets.com, free, no key): the scheduled time and new announcements.
    readonly property QtObject codexResetsTimer: Timer {
        interval: 60000; repeat: true; running: clawd.enabled
        triggeredOnStart: true; onTriggered: if (!codexResetsProc.running) codexResetsProc.running = true
    }
    readonly property QtObject codexResetsProc: Process {
        command: ["curl", "-fsS", "-m", "10", "https://codex-resets.com/api/v1/status"]
        stdout: StdioCollector { onStreamFinished: if (text) clawd.ingestCodexResets(text) }
    }
    readonly property QtObject codexTimer: Timer {
        interval: 30000; repeat: true; running: clawd.enabled
        triggeredOnStart: true; onTriggered: if (!codexProc.running) codexProc.running = true
    }
    readonly property QtObject codexProc: Process {
        command: ["python3", clawd.scripts + "/codex_limits.py"]
        stdout: StdioCollector { onStreamFinished: if (text) clawd.ingest(text) }
    }
    // Raise the terminal window running that session: the first of its hook's ancestors that owns a Hyprland window.
    function focus(key) {
        const s = sessions[key];
        if (!s || !s.pids || !s.pids.length || focusProc.running) return;
        focusProc.pids = s.pids;
        focusProc.running = true;
    }
    readonly property QtObject focusProc: Process {
        property var pids: []
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = [];
                try { clients = JSON.parse(text); } catch (error) { return; }
                const owners = new Set(clients.map(c => c.pid));
                const pid = clawd.focusProc.pids.find(p => owners.has(p));
                if (pid) Hyprland.dispatch("focuswindow pid:" + pid);
            }
        }
    }
    // A new verb every ~30 s for each working session.
    function reroll() {
        const now = Date.now();
        let next = null;
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "work" && now - (s.verbAt || 0) >= 30000) {
            next = next || Object.assign({}, sessions);
            next[key] = Object.assign({}, s, { verb: pick(verbs), verbAt: now });
        }
        if (next) sessions = next;
    }
    readonly property QtObject verbTimer: Timer { interval: 5000; repeat: true; running: clawd.enabled && clawd.thinking; onTriggered: clawd.reroll() }
    // Spinner verbs from the installed Claude Code (cached by verbs.py); again on session starts, at most every 30 s.
    function loadVerbs() {
        if (verbsProc.busy || Date.now() - verbsAt < 30000) return;
        verbsAt = Date.now();
        verbsProc.busy = true;
        verbsProc.running = true;
    }
    function takeVerbs(text) {
        let r = null;
        try { r = JSON.parse(text); } catch (error) { return; }
        const list = r && r.ok && r.data && Array.isArray(r.data.verbs) ? r.data.verbs.filter(v => typeof v === "string" && v && v.length <= 40) : [];
        if (list.length) verbs = list;
    }
    readonly property QtObject verbsProc: Process {
        property bool busy: false  // Process.running only flips once the process has started
        command: ["python3", clawd.scripts + "/verbs.py"]
        stdout: StdioCollector { onStreamFinished: { clawd.verbsProc.busy = false; clawd.takeVerbs(text); } }
        onExited: busy = false
    }
    Component.onCompleted: loadVerbs()
    // A lower rank never replaces a higher one, unless the same key (that session moved on); shell bubbles (key "shell:...") fade sooner.
    function say(key, kind, text) {
        if (bubble && bubble.key !== key && !Mind.outranks(kind, bubble.kind)) return;
        bubble = { key, kind, text };
    }
    function dismiss(key, kind) {
        if (bubble && (key === undefined || bubble.key === key) && (kind === undefined || bubble.kind === kind)) bubble = null;
    }
    // A pending permission never times out: the agent really is waiting for the user.
    function purge() {
        const now = Date.now(), next = {};
        for (const [key, s] of Object.entries(sessions)) if (s.phase === "alert" || now - s.last < staleMs) next[key] = s;
        if (Object.keys(next).length !== Object.keys(sessions).length) sessions = next;
    }
    readonly property QtObject purgeTimer: Timer {
        interval: Math.min(10000, clawd.staleMs / 4); repeat: true
        running: Object.keys(clawd.sessions).length > 0
        onTriggered: clawd.purge()
    }
    readonly property QtObject bubbleTimer: Timer { onTriggered: clawd.bubble = null }
    onBubbleChanged: {
        if (!bubble || bubble.kind === "permission") return bubbleTimer.stop();
        bubbleTimer.interval = String(bubble.key).startsWith("shell:") ? 4000 : 8000;
        bubbleTimer.restart();
    }

    function play(name) {
        if (!enabled) return "off";
        // the limit scenes (limit = either at random) and the revival are scenes, not strips
        if (!manifest || ["limit", "nuke", "revive", "recharge", "weekly", "surge", "limit7"].indexOf(name) < 0 && Acts.NAMES.indexOf(name) < 0 && Dreams.NAMES.indexOf(name) < 0 && !Object.prototype.hasOwnProperty.call(manifest.animations, name)) return "unknown";
        command("play", name);
        return "ok";
    }

    function load(text) {
        try {
            const m = JSON.parse(text);
            if (m && m.frame && m.frame.w > 0 && m.frame.h > 0 && m.animations && typeof m.animations === "object") manifest = m;
            else console.warn("Clawd: invalid sprites/clawd.json");
        } catch (error) { console.warn("Clawd: bad sprites/clawd.json", error); }
    }

    readonly property QtObject manifestFile: FileView {
        path: decodeURIComponent(Qt.resolvedUrl("sprites/clawd.json").toString().replace("file://", ""))
        onLoaded: clawd.load(text())
        onLoadFailed: error => console.warn("Clawd: sprites/clawd.json not loaded", error)
    }
}
