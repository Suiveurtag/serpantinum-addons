import QtQuick
import Quickshell

ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property real carryFrom: 0
        property int waits: 0
        property real startX: 0
        property var p: host.pet
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({mode: p.mode, anim: p.animation, x: p.x, y: p.y, h: p.height, here: p.here}) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function floorY() { return p.here.floor - p.height; }
        function fam(a) { return String(a).replace(/_\d+$/, ""); }
        function raw(line) { Clawd.ingest(line); }
        function hook(agent, event, session, extra) { Clawd.ingest(JSON.stringify(Object.assign({ agent, event, session_id: session, dir: "proj" }, extra || {}))); }
        onTriggered: {
            switch (step++) {
            case 0:
                // the test runner sends one real hook through node + clawd.sock while Clawd is OFF
                if (!wait(!!Clawd.sessions["claude:e2e"], "hook line through the socket while OFF")) break;
                expect(Clawd.activity === "work" && Clawd.sessions["claude:e2e"].dir === "e2e-dir", "socket session tracked: " + JSON.stringify(Clawd.sessions));
                hook("claude", "SessionEnd", "e2e");
                expect(Clawd.activity === "" && Object.keys(Clawd.sessions).length === 0, "SessionEnd forgets");
                expect(Clawd.instances === 0 && !host.pet, "OFF loads nothing");
                expect(Clawd.play("walk") === "off", "play while OFF");
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(Clawd.instances === Quickshell.screens.length && Clawd.manifest && host.pet, "one overlay per screen")) break;
                expect(!!Clawd.manifest.animations.explode && Object.keys(Clawd.manifest.animations).length === 155 && Clawd.manifest.frame.w === 21, "manifest loaded");
                expect(p.mode === "spawn" && Clawd.screenName === Quickshell.screens[0].name, "spawns on a screen");
                expect(Math.abs(p.y - floorY()) < 1 && p.height === Clawd.manifest.frame.h * 4, "spawn on the floor at x4");
                break;
            case 2:
                if (!wait(p.mode === "idle", "spawn finishes")) break;
                expect(Clawd.play("nope") === "unknown", "unknown animation");
                expect(Clawd.play("walk") === "ok", "play ok");
                expect(p.mode === "play" && p.animation === "walk", "plays walk");
                break;
            case 3:
                if (!wait(p.mode === "idle", "loop play ends after ~3 s")) break;
                Clawd.play("land");
                expect(p.mode === "play" && p.animation === "land", "one-shot play");
                break;
            case 4:
                if (!wait(p.mode === "idle", "one-shot play ends")) break;
                p.press(Qt.MiddleButton, p.x + 5, p.y + 5);
                expect(p.mode === "play" && p.animation === "petpet" && !p.grab, "middle click pets");
                p.press(Qt.MiddleButton, p.x + 5, p.y + 5);
                expect(p.animation === "petpetheart", "petting again gets hearts");
                p.idle();
                p.press(Qt.LeftButton, p.x + 10, p.y + 10);
                p.move(p.x + 12, p.y + 10);
                expect(p.mode !== "drag", "tiny move is not a drag");
                p.move(p.x + 110, p.y - 290);
                expect(p.mode === "drag" && p.animation === "drag" && p.y < floorY() - 200, "drag lifts");
                p.release(p.x + 10, p.y + 10);
                expect(p.mode === "fall", "release falls");
                break;
            case 5:
                if (!wait(p.mode === "land" || p.mode === "idle", "falls to the floor")) break;
                expect(Math.abs(p.y - floorY()) < 1, "landed on the floor");
                break;
            case 6:
                if (!wait(p.mode === "idle", "land, then idle")) break;
                p.singleClick();  // the click itself is 250 ms late (a double-click cancels it): its timer's effect
                expect(p.mode === "land", "click reacts");
                p.walk();
                break;
            case 7:
                if (!wait(p.mode === "walk", "walk starts after turn")) break;
                startX = p.x; expect(p.mirrored === (p.target < p.x), "faces the walk");
                break;
            case 8:
                if (!wait(p.mode === "idle" && !p.mirrored, "walk ends facing front")) break;
                expect(Math.abs(p.x - startX) >= 8 && Math.abs(p.y - floorY()) < 1, "walked along the floor");
                Clawd.dice = 0.9;   // the classic sleep (< 0.5: under a blanket)
                p.sleepAfter = 300; p.touch();
                break;
            case 9:
                if (!wait(p.mode === "sleep" && p.animation === "sleep", "falls asleep")) break;
                p.singleClick();
                expect(p.mode === "idle", "click wakes");
                Clawd.dice = null;
                p.sleepAfter = 600000; p.touch();
                break;
            case 10:
                p.sleep();
                expect(p.mode === "sleep", "sleeps on demand");
                expect(Clawd.play("sit") === "ok" && p.mode === "play", "play wakes");
                p.x += 50;
                Config.setSetting("addonsV2ClawdSummon", 1);
                expect(p.mode === "spawn" && Math.abs(p.x - (p.here.x + (p.here.w - p.width) / 2)) <= 1, "summon respawns centred");
                break;
            case 11:
                if (!wait(p.mode === "idle", "summon spawn ends")) break;
                Config.setSetting("addonsV2ClawdSleep", 7);
                expect(p.mode === "idle" && p.sleepAfter === 600000, "unrelated setting does not respawn");
                expect(p.pause() < 20000, "normal idle pace");
                Config.setSetting("general.performance", true);
                break;
            case 12:
                expect(Clawd.lowMotion && p.pause() >= 20000, "performance mode: far fewer idle actions");
                for (let i = 0; i < 40; i++) { p.think(); expect(p.animation.indexOf("look_") !== 0, "no looks in performance mode"); p.idle(); }
                Config.setSetting("general.performance", false);
                p.press(Qt.RightButton, p.x + 5, p.y + 5);
                expect(p.menuOpen, "right click opens the menu");
                Config.setSetting("addonsV2ClawdScale", 6);
                break;
            case 13:
                expect(p.height === Clawd.manifest.frame.h * 6 && Math.abs(p.y - floorY()) < 1, "rescale stays grounded");
                p.menuOpen = false;
                for (const bad of ["", "nope", "[]", "null", '{"agent":"x","event":"Stop"}', '{"agent":"claude","event":"Rm"}', '{"agent":"claude","event":7}'])
                    Clawd.ingest(bad);
                expect(Object.keys(Clawd.sessions).length === 0 && !Clawd.bubble, "bad lines ignored");
                hook("claude", "PreToolUse", "s0");  // a turn already running when the shell started
                expect(Clawd.activity === "work" && p.mode === "work" && fam(p.animation) === "work", "unknown session at work");
                hook("claude", "SessionEnd", "s0");
                expect(p.mode === "idle", "back to normal life");
                hook("claude", "UserPromptSubmit", "s1");
                expect(Clawd.activity === "work" && p.mode === "play" && fam(p.animation) === "think", "prompt: think");
                break;
            case 14:
                if (!wait(p.mode === "work" && fam(p.animation) === "work", "think, then work")) break;
                p.walk(); p.idle();
                expect(p.mode === "work", "no wandering while busy");
                hook("claude", "PostToolUseFailure", "s1");
                expect(p.animation === "oops", "failure: oops");
                break;
            case 15:
                if (!wait(p.mode === "work" && fam(p.animation) === "work", "oops, then work")) break;
                for (const [tool, anim] of [["Read", "read"], ["Grep", "search"], ["exec_command", "bash"], ["WebSearch", "web"], ["Task", "task"],
                                            ["update_plan", "todo"], ["mcp__x__y", "work"], ["Edit", "edit"], ["apply_patch", "edit"], ["Bash", "bash"]]) {
                    hook("claude", "PreToolUse", "s1", { tool_name: tool });
                    expect(Clawd.workAnim === anim && fam(p.animation) === anim && !!Clawd.manifest.animations[p.animation], "tool " + tool + " -> " + anim + ": " + p.animation);
                }
                expect(Clawd.busyCount === 1, "one busy session");
                hook("codex", "PreToolUse", "c9", { tool_name: "web_search", pids: [99999, "x", 1, 3.5] });
                expect(Clawd.busyCount === 2 && fam(p.animation) === "web" && Clawd.lead.key === "codex:c9", "newest session leads: " + Clawd.busyCount);
                expect(JSON.stringify(Clawd.sessions["codex:c9"].pids) === "[99999]", "pids sanitized");
                Clawd.focus("codex:c9");  // no window owns 99999: nothing happens
                hook("codex", "SessionEnd", "c9");
                expect(Clawd.busyCount === 1 && fam(p.animation) === "bash", "back to the other session's tool");
                p.singleClick();
                expect(p.journalOpen && p.mode === "work", "click opens the journal without leaving work");
                p.openMenu();
                expect(!p.journalOpen, "menu closes the journal");
                p.menuOpen = false;
                hook("claude", "PreCompact", "s1");
                expect(p.animation === "compact", "compaction squash");
                break;
            case 16:
                if (!wait(p.mode === "work" && fam(p.animation) === "bash", "compact, then work")) break;
                p.petpet();
                expect(p.animation === "startled", "petted at work: startled");
                hook("claude", "PreToolUse", "s1", { tool_name: "Edit" });
                break;
            case 17:
                if (!wait(p.mode === "work" && fam(p.animation) === "edit", "startled, then edit")) break;
                hook("claude", "Notification", "s1", { notification_type: "permission_prompt" });
                expect(Clawd.activity === "alert" && p.animation === "alert" && Clawd.bubble.kind === "permission" && Clawd.bubble.text === "⚠ permission · proj", "permission alert");
                hook("codex", "Notification", "c1", { notification_type: "agent_needs_input" });
                expect(Clawd.bubble.kind === "permission", "waiting never hides a permission");
                hook("claude", "PreToolUse", "s1");
                expect(!Clawd.bubble && Clawd.activity === "work" && fam(p.animation) === "edit", "approved: back to work");
                hook("claude", "Stop", "s1");
                expect(Clawd.activity === "" && fam(p.animation) === "happy" && Clawd.bubble.text === "✓ done · proj", "stop: happy + bubble");
                hook("claude", "PostToolUse", "s1");
                expect(Clawd.activity === "", "a late async hook does not revive a stopped session");
                break;
            case 18:
                if (!wait(p.mode === "idle", "happy, then idle")) break;
                hook("codex", "UserPromptSubmit", "c2");
                hook("codex", "Notification", "c3", { notification_type: "permission_prompt" });
                hook("codex", "Interrupt", "c3");
                expect(Clawd.activity === "work" && !Clawd.bubble, "interrupt drops its alert");
                hook("codex", "Notification", "c3", { notification_type: "permission_prompt" });
                Clawd.staleMs = 400;
                break;
            case 19:
                if (!wait(!Clawd.sessions["codex:c2"], "stale session purged")) break;
                expect(Clawd.sessions["codex:c3"].phase === "alert" && Clawd.activity === "alert", "pending permission never purged");
                Clawd.staleMs = 120000;
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 20:
                expect(Clawd.instances === 0 && !host.pet, "OFF unloads");
                expect(Clawd.play("walk") === "off", "play OFF again");
                expect(Clawd.activity === "alert", "OFF keeps tracking");
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 21:
                if (!wait(!!host.pet && host.pet.mode === "work" && host.pet.animation === "alert", "comes back showing the alert")) break;
                hook("codex", "SessionEnd", "c3");
                hook("codex", "SessionEnd", "c1");
                expect(Clawd.activity === "" && !Clawd.bubble && Object.keys(Clawd.sessions).length === 0, "all sessions gone");
                break;
            case 22: {
                if (!wait(Clawd.verbs.length > 1 && host.pet.mode === "idle", "verbs.py loaded")) break;
                expect(Clawd.verbs.every(v => typeof v === "string" && v.length > 0 && v.length <= 40), "verbs are short strings");
                // Status: stats only, an unknown session starts idle, never revives a phase
                hook("claude", "Status", "st", { model: "Opus 5.5", effort: "high", ctx: 42, cost: 4.9, five_hour: 50, seven_day: 20 });
                let st = Clawd.sessions["claude:st"];
                expect(st && st.phase === "idle" && Clawd.activity === "" && p.mode === "idle", "status creates an idle session");
                expect(st.model === "Opus 5.5" && st.effort === "high" && st.ctx === 42 && st.cost === 4.9 && st.five_hour === 50 && st.seven_day === 20, "stats stored");
                raw('{"agent":"claude","event":"Status","session_id":"st","ctx":1e999,"cost":"9","five_hour":null,"model":7}');
                st = Clawd.sessions["claude:st"];
                expect(st.ctx === 42 && st.cost === 4.9 && st.five_hour === 50 && st.model === "Opus 5.5", "non-finite / wrong types ignored");
                hook("claude", "UserPromptSubmit", "st");
                hook("claude", "Stop", "st");
                hook("claude", "Status", "st", { ctx: 50 });
                expect(Clawd.sessions["claude:st"].phase === "idle" && Clawd.activity === "" && Clawd.sessions["claude:st"].ctx === 50, "status never revives a stopped session");
                Clawd.dismiss();
                hook("claude", "Status", "st", { cost: 5.1 });
                expect(p.animation === "coin", "crossing $5: coin");
                p.idle();
                hook("claude", "Status", "st", { cost: 6 });
                expect(p.animation === "idle", "same $5 band: nothing new");
                hook("claude", "Status", "st", { five_hour: 100 });
                expect(p.blasting && p.mode === "explode" && ["singularity", "nuke", "bsod", "panic"].indexOf(p.blast.kind) >= 0, "5h limit reached: one of the limit scenes");
                p.blastDone();
                expect(p.dead && p.mode === "corpse" && Config.getSetting("addonsV2ClawdDead", 0) > 0 && p.y < p.here.y, "dead: his corpse falls from the top");
                break;
            }
            case 23: {
                if (!wait(p.mode === "dead" && p.animation === "dead", "his corpse lands and lies there")) break;
                expect(Math.abs(p.y - floorY()) < 1, "on the floor");
                p.perform("wave"); p.idle(); p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.release(); p.press(Qt.MiddleButton, p.x + 5, p.y + 5);
                p.busy(); p.sleep(); p.perform("limit");
                expect(p.mode === "dead" && p.animation === "dead" && !p.grab && !p.journalOpen && !p.blast && Math.abs(p.y - floorY()) < 1, "dead: he reacts to nothing");
                // ...but his corpse can be carried: lifted, then it falls back to the floor where it was dropped
                carryFrom = p.x;
                p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.move(p.x + 105, p.y - 195);
                expect(p.mode === "carried" && p.dead && p.animation === "dead" && p.x > carryFrom + 50 && p.y < floorY() - 100, "his corpse is carried");
                p.release();
                expect(p.mode === "corpse" && p.dead && !p.grab, "dropped: his corpse falls");
                break;
            }
            case 24: {
                if (!wait(p.mode === "dead", "his corpse lands where it was dropped")) break;
                expect(p.dead && p.x > carryFrom + 50 && Math.abs(p.y - floorY()) < 1, "back on the floor, further along");
                const ov = host.overlays.find(o => o.screen.name === Clawd.screenName);
                p.openMenu();
                expect(p.menuOpen && ov.menu.rows[0] === "revive", "his menu offers revive");
                p.menuOpen = false;
                hook("claude", "SessionStart", "rv");
                expect(p.mode === "revive" && p.dead && p.reviveAt > 0, "a new session starts his revival");
                hook("claude", "SessionEnd", "rv");
                break;
            }
            case 25: {
                const ov = host.overlays.find(o => o.screen.name === Clawd.screenName);
                if (!wait(ov.revival.visible && ov.revival.t > 1, "his overlay plays the revival")) break;
                p.revived();
                expect(p.mode === "idle" && !p.dead, "back to life");
                break;
            }
            case 26:
                expect(Number(Config.getSetting("addonsV2ClawdDead", 0)) === 0, "alive again");
                p.idle();
                const known = Clawd.sessions;
                hook("claude", "Status", "st", { five_hour: 100 });
                expect(p.animation === "idle" && Clawd.sessions === known, "already at the limit: no new reaction, no churn");
                hook("claude", "Status", "st", { dir: "a\u202eb\u0007c" });
                expect(Clawd.sessions["claude:st"].dir === "abc", "dir: control and bidi characters stripped");
                hook("claude", "UserPromptSubmit", "sf");
                hook("claude", "StopFailure", "sf");
                expect(Clawd.sessions["claude:sf"].phase === "idle" && Clawd.activity === "" && p.animation === "sad", "StopFailure: sad");
                expect(Clawd.bubble && Clawd.bubble.kind === "error" && Clawd.bubble.text === "✗ error · proj", "error bubble");
                hook("claude", "SessionStart", "w1");
                expect(p.animation === "wave" && !Clawd.sessions["claude:w1"], "session start: wave");
                hook("claude", "UserPromptSubmit", "cp"); hook("claude", "PreCompact", "cp"); hook("claude", "SessionStart", "cp");
                expect(p.animation === "compact" && !Clawd.sessions["claude:cp"].compacting, "restart after a compaction: no wave");
                hook("claude", "SessionStart", "cp");
                expect(p.animation === "wave", "a later start waves again");
                hook("claude", "SessionEnd", "cp");
                hook("claude", "UserPromptSubmit", "lt");
                { const n = Object.assign({}, Clawd.sessions); n["claude:lt"] = Object.assign({}, n["claude:lt"], { since: Date.now() - 200000 }); Clawd.sessions = n; }
                hook("claude", "Stop", "lt");
                expect(p.animation === "celebrate", "long turn: celebrate");
                hook("claude", "UserPromptSubmit", "sh");
                hook("claude", "Stop", "sh");
                expect(fam(p.animation) === "happy", "short turn: happy");
                for (const k of ["st", "sf", "lt", "sh"]) hook("claude", "SessionEnd", k);
                break;
            case 27:
                if (!wait(p.mode === "idle", "happy ends")) break;
                Clawd.dismiss();
                Clawd.dice = 0.9;  // Clawd.pick: the last of a list (0.1: the first); < 1/3: sweat
                hook("claude", "UserPromptSubmit", "v");
                expect(p.animation === "think_3" && Clawd.sessions["claude:v"].verb === Clawd.pick(Clawd.verbs), "think variant, verb rolled: " + p.animation);
                break;
            case 28: {
                if (!wait(p.mode === "work", "think, then work")) break;
                expect(p.animation === "work_6", "work variant: " + p.animation);
                Clawd.dice = 0.1;
                hook("claude", "PreToolUse", "v", { tool_name: "Edit", target: "main.py" });
                expect(p.animation === "edit" && Clawd.lead.target === "main.py", "edit family, target stored");
                Clawd.dice = 0.9;
                hook("claude", "PreToolUse", "v", { tool_name: "Read", target: "notes.md\u0007x" });
                expect(p.animation === "read_4" && Clawd.lead.target === "notes.mdx", "read variant, control chars stripped: " + p.animation);
                hook("claude", "PostToolUse", "v", { tool_name: "Read" });
                expect(Clawd.lead.target === "notes.mdx", "post keeps the target");
                p.shuffle(); expect(p.animation === "read_3", "shuffle: another variant, never the one playing: " + p.animation);
                p.shuffle(); expect(p.animation === "read_4", "shuffle back: " + p.animation);
                expect(!Clawd.strained && p.speed === 1, "not strained, medium speed");
                hook("claude", "Status", "v", { ctx: 85, effort: "max" });
                expect(Clawd.sessions["claude:v"].phase === "work" && Clawd.strained && p.speed === 1.5, "strained, max effort types faster: " + p.speed);
                p.shuffle(); expect(p.animation === "read_3", "strained, roll 0.9: no sweat: " + p.animation);
                Clawd.dice = 0.1;
                p.shuffle(); expect(p.animation === "sweat" && p.speed === 1, "strained, roll 0.1: sweat at normal speed");
                p.shuffle(); expect(p.animation === "read", "never two sweats in a row: " + p.animation);
                expect(Clawd.effortStyle && Clawd.effortStyle.mode === 2, "max effort: rainbow body");
                hook("claude", "Status", "v", { effort: "low" });
                expect(p.speed === 0.75, "low effort slower");
                expect(Clawd.effortStyle && Clawd.effortStyle.color === "#FFC107" && Clawd.effortColor(3) === "#FFC107", "low effort: yellow body and spinner");
                hook("claude", "Status", "v", { effort: "constructor" });
                expect(p.speed === 1 && Clawd.effortRate("toString") === 1, "unknown effort: 1");
                // thoughts: pure pieces
                const lead = Clawd.lead, t0 = lead.since;
                expect(Clawd.thinking && Clawd.thoughts === "full", "thinking while working");
                expect(Clawd.elapsed(12000) === "12s" && Clawd.elapsed(65000) === "1m 05s" && Clawd.elapsed(3725000) === "1h 02m", "elapsed format");
                let t = Clawd.thought("full", lead, t0 + 65000, null);
                expect(t.text === lead.verb + "…" && t.suffix === " 1m 05s" && !t.warn, "verb line: " + JSON.stringify(t));
                t = Clawd.thought("full", lead, t0, { text: "x".repeat(60), warn: true });
                expect(t.text.length === 40 && t.text.endsWith("…") && t.warn && t.suffix === "", "override clipped to 40");
                expect(Clawd.thought("verbs", lead, t0, { text: "Edit x" }).suffix === " 0s", "verbs mode ignores flashes and infos");
                expect(Clawd.thought("off", lead, t0, null) === null && Clawd.thought("full", null, t0, null) === null, "off / no lead: nothing");
                expect(Clawd.actionText(lead) === "Read notes.mdx" && Clawd.actionText({ tool: "Bash", target: "" }) === "Bash", "action text");
                const infos = Clawd.infos(Object.assign({}, lead, { ctx: 42, five_hour: 63, seven_day: 20, cost: 1.237, model: "Opus 5.5" }));
                expect(JSON.stringify(infos.map(i => i.text)) === JSON.stringify(["Opus 5.5 · constructor", "ctx 42%", "$1.24", "5h 63% · 7d 20%"]) && !infos.some(i => i.warn), "info list: " + JSON.stringify(infos));
                expect(Clawd.nextInfo(lead, 0).text === "ctx 85%" && Clawd.nextInfo(lead, 1).warn, "warnings preferred");
                expect(Clawd.nextInfo({ since: 0 }, 0) === null, "no stats: no info");
                // sub-agents: counted, a background one wakes an idle session, the lead thread keeps its tool while busy
                hook("claude", "SubagentStart", "sa", { agent_id: "a1", agent_type: "Explore" });
                hook("claude", "SubagentStart", "sa", { agent_id: "a2" });
                expect(Clawd.sessions["claude:sa"].phase === "idle" && Clawd.subList(Clawd.sessions["claude:sa"]).length === 2, "two sub-agents counted, session idle");
                hook("claude", "PreToolUse", "sa", { tool_name: "Grep", target: "x", agent_id: "a1", sub_model: "claude-haiku-5-5", sub_tokens: 20000 });
                expect(Clawd.sessions["claude:sa"].phase === "work" && Clawd.sessions["claude:sa"].subOnly && Clawd.sessions["claude:sa"].tool === "Grep", "a background sub-agent wakes the session");
                hook("claude", "PreToolUse", "sa", { tool_name: "Bash", target: "npm" });
                hook("claude", "PreToolUse", "sa", { tool_name: "Read", target: "z", agent_id: "a2" });
                expect(Clawd.sessions["claude:sa"].tool === "Bash" && !Clawd.sessions["claude:sa"].subOnly, "lead thread busy: its tool stays");
                Clawd.sessions = Object.assign({}, Clawd.sessions, { "claude:sa": Object.assign({}, Clawd.sessions["claude:sa"], { mainAt: Date.now() - 6000 }) });
                hook("claude", "PreToolUse", "sa", { tool_name: "Read", target: "z", agent_id: "a2" });
                expect(Clawd.sessions["claude:sa"].tool === "Read" && Clawd.sessions["claude:sa"].target === "z" && Clawd.toolAnim("Read") === "read", "lead thread quiet: the sub-agent's tool takes over");
                expect(Clawd.infos(Clawd.sessions["claude:sa"]).map(i => i.text).indexOf("2 sub-agents · Haiku 5.5") >= 0, "info: count and sub-agent model: " + JSON.stringify(Clawd.infos(Clawd.sessions["claude:sa"])));
                hook("claude", "SubagentStop", "sa", { agent_id: "a1" });
                hook("claude", "PostToolUse", "sa", { tool_name: "Grep", agent_id: "a1" });  // a late hook
                expect(Clawd.subList(Clawd.sessions["claude:sa"]).length === 1, "a stopped sub-agent stays stopped");
                hook("claude", "SessionEnd", "sa");
                hook("claude", "SubagentStart", "sb", { agent_id: "b1" });
                hook("claude", "PostToolUse", "sb", { tool_name: "Read", agent_id: "b1" });
                expect(Clawd.sessions["claude:sb"].phase === "work", "sb woken by its sub-agent");
                hook("claude", "SubagentStop", "sb", { agent_id: "b1" });
                expect(Clawd.sessions["claude:sb"].phase === "idle", "its last sub-agent stops: back to sleep");
                hook("claude", "SessionEnd", "sb");
                break;
            }
            case 29:
                if (!wait(host.overlays[0].thought.visible, "thought shown")) break;
                host.overlays[0].thought.extra = null;  // the Edit/Read flashes above
                break;
            case 30: {
                const th = host.overlays[0].thought;
                if (!wait(th.shown && th.shown.text === Clawd.lead.verb + "…" && th.line.suffix.length > 1, "verb line on screen")) break;
                expect(th.glyph !== "" && th.width > 0 && th.y + th.height <= p.y - p.here.y + 1, "above his head");
                th.flashAt = 0;
                hook("claude", "PreToolUse", "v", { tool_name: "Grep", target: "TODO" });
                expect(th.extra && th.extra.text === "Grep TODO" && th.line.text === "Grep TODO" && th.line.suffix === "", "action flash");
                hook("claude", "PreToolUse", "v", { tool_name: "Bash", target: "npm" });
                expect(th.extra.text === "Grep TODO", "flashes throttled");
                th.extra = null; th.infoIndex = 0;
                th.cycle();
                expect(th.line.text === "ctx 85%" && th.line.warn, "info cycle shows the warning");
                Config.setSetting("addonsV2ClawdThoughts", "verbs");
                expect(th.visible && th.line.suffix !== "" && th.line.text === Clawd.lead.verb + "…", "verbs mode: verb only");
                th.extra = null; th.flashAt = 0; th.cycle(); th.flash();
                expect(th.extra === null, "verbs mode: no flash, no info");
                Config.setSetting("addonsV2ClawdThoughts", "off");
                expect(!Clawd.thinking && !th.visible, "off: hidden");
                Config.setSetting("addonsV2ClawdThoughts", "full");
                expect(th.visible, "full again");
                hook("codex", "Notification", "x1", { notification_type: "agent_needs_input" });
                expect(!th.visible, "a bubble hides the thought");
                Clawd.dismiss();
                expect(th.visible, "back after the bubble");
                p.openMenu();
                expect(!th.visible, "the menu hides the thought");
                p.menuOpen = false;
                hook("claude", "Stop", "v");
                expect(!th.visible && !Clawd.thinking, "turn over: no thought");
                Clawd.dice = null;
                for (const k of ["v", "x1"]) { hook("claude", "SessionEnd", k); hook("codex", "SessionEnd", k); }
                expect(Object.keys(Clawd.sessions).length === 0, "clean");
                Clawd.dismiss();
                Clawd.quotas = ({}); p.quotaQueue = [];
                // Quotas trigger the matching scene once per window.
                hook("claude", "Status", "q", { five_hour: 99, five_hour_resets: 1793000000 });
                expect(!p.blasting, "below the limit");
                Clawd.dice = 0.1;   // the 5 h limit is the nuke or a crash screen, 50/50: below 0.5 the nuke
                hook("claude", "Status", "q", { five_hour: 100, five_hour_resets: 1793000000 });
                expect(p.blasting && p.blast.kind === "nuke" && p.mode === "explode" && p.blast.screen === Clawd.screenName && p.blast.clock === 0, "limit reached: he freezes");
                const frozen = p.frame;
                p.perform("wave"); p.idle();
                expect(p.mode === "explode" && p.frame === frozen && !p.clockRunning(), "nothing moves him while he is frozen");
                break;
            }
            case 31: {
                // his screen's window hides him, then starts the clock (no capture offscreen: after the fallback)
                if (!wait(p.blastHidden && p.blast && p.blast.clock > 0, "the singularity window takes over")) break;
                const w = host.blasts.find(b => b.screen.name === p.blast.screen);
                expect(w && w.running && w.main && host.blasts.every(b => b.running), "every screen's window runs");
                w.skip();
                expect(Date.now() - p.blast.clock >= w.scene.at.back * 1000, "Escape skips to the end");
                p.blastDone();
                expect(!p.blast && !p.blasting && !p.blastHidden && p.mode === "corpse" && p.dead && host.blasts.every(b => !b.running), "his corpse after it");
                p.revive(); p.revived();
                expect(!p.dead && p.mode !== "revive", "revived");
                hook("claude", "Status", "q", { five_hour: 100, five_hour_resets: 1793000000 });
                expect(!p.blasting, "same window: once");
                const deadline = Date.now() / 1000 + 86400;
                hook("codex", "Status", "rate-limits", { seven_day: 100, seven_day_resets: deadline });
                expect(!p.blasting, "first observation at 100 does not replay a limit");
                const freshQuotas = Object.assign({}, Clawd.quotas); delete freshQuotas["codex:seven_day"];
                Clawd.quotas = freshQuotas; Clawd.observed = ({});
                hook("codex", "Status", "rate-limits", { seven_day: 99, seven_day_resets: deadline });
                Clawd.dice = 0.1;   // < 0.5: the singularity, else the surge
                hook("codex", "Status", "rate-limits", { seven_day: 100, seven_day_resets: deadline });
                expect(p.blasting && p.blast.kind === "singularity", "weekly transition starts explode");
                Clawd.dice = null;
                expect(Config.getSetting("addonsV2ClawdQuotas", {})["codex:seven_day"].fired, "limit is persisted");
                p.blastDone();
                p.revive(); p.revived(); p.idle();
                Clawd.quotas = Config.getSetting("addonsV2ClawdQuotas", {}); Clawd.observed = ({});
                hook("codex", "Status", "restarted", { seven_day: 99, seven_day_resets: deadline });
                hook("codex", "Status", "restarted", { seven_day: 100, seven_day_resets: deadline });
                expect(!p.blasting && p.quotaQueue.length === 0, "restart and stale sample do not replay a fired limit");
                p.perform("nuke");
                expect(p.blasting && p.blast.kind === "nuke", "the nuclear variant on demand");
                break;
            }
            case 32: {
                if (!wait(p.blastHidden && p.blast && p.blast.clock > 0, "the nuke window takes over")) break;
                const w = host.blasts.find(b => b.screen.name === p.blast.screen);
                expect(w.nuke && w.scene.legs.length === 6 && w.scene.groundX > 0, "its scene runs");
                w.skip();
                break;
            }
            case 33: {
                if (!wait(!p.blast && p.dead, "his corpse after the nuke")) break;
                // dead for more than 3 h: the next start revives him
                Config.setSetting("addonsV2ClawdDead", Date.now() - 4 * 3600000);
                hook("claude", "SessionEnd", "q"); hook("codex", "SessionEnd", "rate-limits");
                Config.setSetting("addonsV2Clawd", false);
                break;
            }
            case 34:
                if (!wait(Clawd.instances === 0, "OFF again: " + Clawd.instances + " " + Clawd.enabled + " " + !!host.pet)) break;
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 35:
                if (!wait(host.pet && host.pet.mode === "revive", "3 h later, a shell start revives him")) break;
                host.pet.revived();
                break;
            case 36:
                // the 5 h window that had run out is back below 100: the dawn scene, once
                if (!wait(!p.dead && p.mode === "idle" && p.grounded(), "alive and standing again")) break;
                hook("claude", "Status", "q", { five_hour: 10, five_hour_resets: 1793018000 });
                expect(p.mode === "recharge" && p.rechargeAt > 0 && p.animation === "idle", "the 5 h reset starts the recharge");
                break;
            case 37: {
                const ov = host.overlays.find(o => o.screen.name === Clawd.screenName);
                if (!wait(ov.recharge.visible && ov.recharge.t > 2.8, "his overlay plays the recharge")) break;
                expect(ov.recharging && ov.recharge.level >= 1 && ov.recharge.pose.strip === "recharge" && !ov.recharge.manifest === false, "charging up");
                p.openMenu(); p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.perform("wave");
                expect(p.mode === "recharge" && !p.menuOpen && !p.grab, "nothing interrupts it");
                p.rechargeAt = Date.now() - 11000;
                break;
            }
            case 38:
                if (!wait(p.mode !== "recharge", "the recharge ends")) break;
                expect(p.mode === "idle" && !p.dead, "back to his life");
                hook("claude", "Status", "q", { five_hour: 12, five_hour_resets: 1793018000 });
                expect(p.mode !== "recharge", "once per reset");
                // The weekly reset is silent; the symphony remains available for manual playback.
                Clawd.quotas = ({}); p.quotaQueue = [];
                hook("codex", "Status", "w", { seven_day: 100, seven_day_resets: Date.now() / 1000 - 1 });
                hook("codex", "Status", "w", { seven_day: 4, seven_day_resets: Date.now() / 1000 + 604800 });
                expect(p.mode !== "weekly" && p.quotaQueue.length === 0, "the weekly reset is silent");
                // A banked Codex reset spent early (used % falls) and the announced resets play one recharge each.
                const banked = Date.now() / 1000 + 604800;
                hook("codex", "Status", "b", { seven_day: 60, seven_day_resets: banked });
                hook("codex", "Status", "b", { seven_day: 5, seven_day_resets: banked });
                expect(p.mode === "recharge" || p.quotaQueue.length === 1, "banked reset spent: recharge");
                if (p.mode === "recharge") p.recharged();
                p.quotaQueue = []; Clawd.lastResetAt = 0;
                Clawd.codexResets = { seen: "a", done: [] };
                Clawd.ingestCodexResets(JSON.stringify({ data: { latest_reset: { id: "b", reset_type: "banked" }, scheduled_reset: null } }));
                expect(p.mode !== "recharge" && p.quotaQueue.length === 0, "a banked announcement is silent");
                Clawd.ingestCodexResets(JSON.stringify({ data: { latest_reset: { id: "c", reset_type: "regular" }, scheduled_reset: null } }));
                expect(p.mode === "recharge" || p.quotaQueue.length === 1, "an announced reset plays");
                if (p.mode === "recharge") p.recharged();
                p.quotaQueue = []; Clawd.lastResetAt = 0;
                Clawd.ingestCodexResets(JSON.stringify({ data: { latest_reset: { id: "c", reset_type: "regular" }, scheduled_reset: { id: "s", scheduled_for: new Date(Date.now() - 1000).toISOString() } } }));
                Clawd.checkCodexSchedule();
                expect(p.mode === "recharge" || p.quotaQueue.length === 1, "a scheduled reset plays at its time");
                if (p.mode === "recharge") p.recharged();
                p.quotaQueue = [];
                p.perform("weekly");
                expect(p.mode === "weekly" && p.weeklyAt > 0, "manual symphony starts");
                p.weeklyAt = Date.now() - 10000;   // skip to the orchestra playing
                break;
            case 39: {
                const ov = host.overlays.find(o => o.screen.name === Clawd.screenName);
                if (!wait(ov.symphony.visible && ov.symphony.t > 9.5, "his overlay plays the symphony")) break;
                expect(ov.symphonic && ov.symphony.level(0) > 0.9 && ov.symphony.pose >= 5 && !ov.symphony.homeVisible, "the orchestra plays under his baton");
                p.openMenu(); p.press(Qt.LeftButton, p.x + 5, p.y + 5); p.perform("wave"); p.perform("recharge");
                expect(p.mode === "weekly" && !p.menuOpen && !p.grab, "nothing interrupts it");
                p.weeklyAt = Date.now() - 30000;
                break;
            }
            case 40:
                if (!wait(p.mode !== "weekly", "the symphony ends")) break;
                expect(p.mode === "idle" && !p.dead, "back to his life");
                // the superpowered weekly variant: nothing interrupts it, it ends in the middle of his screen
                p.perform("surge");
                expect(p.mode === "surge" && p.surgeAt > 0 && !p.blast, "the surge starts");
                p.openMenu(); p.perform("wave");
                expect(p.mode === "surge" && !p.menuOpen, "nothing interrupts the surge");
                p.surged(p.here.x + p.here.w / 2);
                expect(p.mode === "idle" && Math.abs(p.x + p.width / 2 - (p.here.x + p.here.w / 2)) <= 1, "the surge ends in the middle");
                Clawd.quotas = { "claude:five_hour": { used: 100, resets: Date.now() / 1000 - 1, watched: true, consumed: false, fired: true } };
                p.die();
                Clawd.checkQuotaResets();
                expect(p.mode === "revive" && p.quotaQueue.length === 1, "deadline queues reset while dead");
                Clawd.checkQuotaResets();
                expect(p.quotaQueue.length === 1, "deadline fires once");
                p.revived(); p.runQuota();
                expect(p.mode === "recharge" && p.quotaQueue.length === 0, "reset scene follows revival");
                p.recharged();
                hook("claude", "Status", "q", { five_hour: 1, five_hour_resets: Date.now() / 1000 + 18000 });
                expect(p.mode !== "recharge", "new snapshot does not repeat a consumed deadline");
                const nextDeadline = Date.now() / 1000 + 18000;
                Clawd.quotas = { "claude:five_hour": { used: 99, resets: nextDeadline, fired: false, watched: true, consumed: false } };
                Clawd.observed = ({});
                hook("claude", "Status", "after-restart", { five_hour: 100, five_hour_resets: nextDeadline });
                expect(!p.blasting && p.quotaQueue.length === 0, "first observation after restart cannot replay an unseen crossing");
                // the idle specials: own canvas size, grip on the floor, sequence ends back at idle, walkers move, menu cancels
                p.idle();
                expect(Clawd.play("book") === "ok" && p.mode === "act" && p.animation === "book_idle" && p.width === Math.round(24 * Clawd.unit(Clawd.manifest.animations.book_idle)) && p.height === Math.round(16 * Clawd.unit(Clawd.manifest.animations.book_idle)), "special by name: its own canvas");
                expect(Math.abs(p.contact().y - p.here.floor) < 1, "special grip stands on the floor");
                p.actNext();
                expect(p.animation === "book_blink" && Math.abs(p.contact().y - p.here.floor) < 1, "next step of the sequence");
                for (let i = 0; i < 60 && p.mode === "act"; i++) p.actNext();
                expect(p.mode === "idle" && p.width === 21 * Clawd.scale && Math.abs(p.y - floorY()) < 1, "sequence ends back at idle, normal size");
                expect(Clawd.play("bike") === "ok" && p.mode === "act" && p.animation === "bike_ride" && p.act.to !== undefined && p.mirrored === (p.act.to < p.x), "biker walks toward its target, mirrored going left");
                const bikeX = p.x;
                p.step();
                p.last -= 40;
                p.step();
                expect(Math.abs(p.x - bikeX) > 0, "biker moves");
                p.openMenu();
                expect(p.mode === "idle" && p.act === null, "menu ends a special");
                p.menuOpen = false;
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 41:
                if (!wait(Clawd.instances === 0, "OFF again: " + Clawd.instances + " " + Clawd.enabled + " " + !!host.pet)) break;
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
