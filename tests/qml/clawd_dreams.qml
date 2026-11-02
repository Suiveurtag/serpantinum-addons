import QtQuick
import Quickshell

// Lot 7: his sleep life. Blanket or classic (Clawd.dice), turning over, a dream (the cloud, the click, the scene, the
// collection), a nightmare (the jolt, awake and sweating), the groggy wake-up, sleepwalking, sleep talk, interruptions, IPC.
ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property bool m0: false
        property real x0: 0
        property real slept: 0
        property var p: host.pet
        readonly property var ov: host.overlays.find(o => o.screen.name === Clawd.screenName) || null
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({mode: p.mode, anim: p.animation, kind: p.sleepKind, phase: p.dreamPhase, x: p.x, mirrored: p.mirrored}) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function hook(event, session) { Clawd.ingest(JSON.stringify({ agent: "claude", event, session_id: session, dir: "proj" })); }
        onTriggered: {
            switch (step++) {
            case 0:
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(Clawd.instances === Quickshell.screens.length && Clawd.manifest && host.pet, "one overlay per screen")) break;
                expect(!!Clawd.manifest.animations.sleep_blanket && Clawd.manifest.clone.frames === 50 && !!Clawd.manifest.gemini, "lot 7 sprites in the manifest");
                break;
            case 2:
                if (!wait(p.mode === "idle", "spawn finishes")) break;
                p.sleepAfter = 600000; p.touch();
                Clawd.dice = 0.1;   // < 0.5: under a blanket
                p.sleep();
                expect(p.mode === "sleep" && p.asleep && p.sleepKind === "blanket" && p.animation === "sleep_blanket_in", "pulls a blanket over him");
                break;
            case 3:
                if (!wait(p.animation === "sleep_blanket", "the intro ends in the blanket loop")) break;
                m0 = p.mirrored;
                p.roll();
                expect(p.mode === "sleep" && p.animation === "sleep_blanket_roll", "turns over under the blanket");
                break;
            case 4:
                if (!wait(p.animation === "sleep_blanket" && p.mirrored !== m0, "the roll ends turned the other way")) break;
                p.wake();
                Clawd.dice = 0.9;   // classic
                p.sleep();
                expect(p.sleepKind === "classic" && p.animation === "sleep", "the classic sleep");
                p.roll();
                expect(p.animation === "sleep_roll", "turns over");
                break;
            case 5:
                if (!wait(p.animation === "sleep" && p.mode === "sleep", "back to the loop")) break;
                expect(p.startDream("surf") && p.dreamPhase === "bubble" && p.dream.entry.id === "surf", "a dream cloud");
                break;
            case 6:
                if (!wait(ov && ov.dreamBubble.visible, "the cloud is shown")) break;
                expect(!ov.dreamBubble.nightmare, "a dream's cloud");
                p.openDream();
                expect(p.mode === "dream" && p.dreamPhase === "view" && p.asleep, "the click opens the dream");
                expect(Clawd.dreams.seen.surf.n === 1 && Clawd.dreams.log.length === 1 && Clawd.dreams.log[0].id === "surf", "it joins his collection");
                expect(Clawd.dreamBook.filter(d => d.seen).length === 1 && Clawd.dreamBook.length === 2, "the book: 1/2");
                break;
            case 7:
                if (!wait(ov.dreamScene.visible && ov.dreamScene.t > 0, "the overlay plays the dream")) break;
                expect(!ov.dreamBubble.visible, "no cloud while it plays");
                p.dreamAt = Date.now() - 23900;
                break;
            case 8:
                if (!wait(p.mode === "sleep" && p.dreamPhase === "" && !p.dream, "the dream ends: still asleep")) break;
                expect(p.startDream("gemini") && ov && p.dream.entry.kind === "nightmare", "a nightmare cloud");
                break;
            case 9:
                if (!wait(ov.dreamBubble.visible && ov.dreamBubble.nightmare, "the dark cloud")) break;
                p.openDream();
                expect(p.mode === "nightmare" && Clawd.dreams.seen.gemini.n === 1, "the nightmare plays, recorded");
                p.dreamAt = Date.now() - 10950;
                break;
            case 10:
                if (!wait(p.animation === "sleep_jolt" && p.mode === "nightmare", "the jumpscare: he jolts")) break;
                break;
            case 11:
                if (!wait(p.mode === "react" && p.animation === "sweat" && !p.asleep && !p.dream, "the nightmare ends: awake and sweating")) break;
                Clawd.dice = 0.1;
                p.sleep();
                p.sleepAt = Date.now() - 20 * 60000;
                p.wake();
                expect(p.mode === "idle" && p.animation === "sleep_blanket_out" && !p.asleep, "throws the blanket off");
                break;
            case 12:
                if (!wait(p.animation === "wake_groggy", "a long night: the groggy stretch")) break;
                break;
            case 13:
                if (!wait(p.animation !== "wake_groggy" && p.mode === "idle", "then his day")) break;
                Clawd.dice = 0.9;
                p.sleep();
                p.wake();
                expect(p.animation === "blink" && !p.asleep, "a short nap: just a blink");
                p.sleep();
                slept = p.sleepAt; x0 = p.x;
                expect(p.sleepwalk() && p.mode === "sleepwalk" && p.asleep && p.animation === "sleep_walk", "sleepwalks");
                break;
            case 14:
                if (!wait(p.mode === "sleep" && Math.abs(p.x - x0) >= 30, "a few steps, then asleep again")) break;
                expect(p.sleepAt === slept && Math.abs(p.y - (p.here.floor - p.height)) < 1, "the same night, on the floor");
                p.mumbleNow();
                expect(p.mumble !== "", "mumbles");
                break;
            case 15:
                if (!wait(ov.thought.visible && ov.thought.say === p.mumble, "his sleep talk above his head")) break;
                break;
            case 16:
                if (!wait(p.mumble === "" && !ov.thought.visible, "it fades")) break;
                p.startDream("surf"); p.openDream();
                p.singleClick();
                expect(!p.asleep && !p.dream && p.dreamPhase === "", "a click wakes him: the dream is gone");
                p.sleep(); p.startDream("surf");
                hook("UserPromptSubmit", "d1");
                expect(!p.asleep && !p.dream && p.dreamPhase === "", "work wakes him: the cloud is gone");
                hook("SessionEnd", "d1");
                break;
            case 17:
                if (!wait(p.mode === "idle", "back to idle")) break;
                expect(Clawd.play("dream_surf") === "ok" && p.mode === "sleep" && p.dreamPhase === "bubble" && p.dream.entry.id === "surf", "IPC dream_surf");
                expect(Clawd.play("dream_nope") === "unknown", "unknown dream");
                expect(Clawd.play("blanket") === "ok" && p.sleepKind === "blanket", "IPC blanket");
                expect(Clawd.play("sleep_roll") === "ok", "a new clip plays by name");
                expect(ov.menu.rows.indexOf("dreams") > 0, "the menu has dreams");
                Clawd.dice = null;
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
