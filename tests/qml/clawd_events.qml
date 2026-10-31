import QtQuick
import Quickshell

// Clawd and the shell's singletons, all stubs written by the harness (clawd_runtime.qml stays stub-free): music + Cava consumer + beat, notifications, OSD, battery, menus.
ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property int mark: 0
        property var p: host.pet
        property string main: Quickshell.screens[0].name
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({ mode: p.mode, anim: p.animation, mood: p.mood, beat: p.beat, bubble: Clawd.bubble, regs: Cava.regs, unregs: Cava.unregs }) : ""); Qt.exit(1); } }
        function wait(c, msg, n) { if (c) { waits = 0; return true; } if (++waits > (n || 80)) expect(false, "timeout: " + msg); step--; return false; }
        function resting() { return !!p && ["idle", "sit", "perch"].indexOf(p.mode) >= 0 && p.mood === ""; }
        function fresh() { p.mind = ({ last: {}, recent: [] }); Clawd.dismiss(); }
        function notify(app, urgency) { NotificationManager.popupAdded(1, { appName: app, urgency, summary: "SECRET-SUMMARY", body: "SECRET-BODY" }); }
        onTriggered: {
            switch (step++) {
            case 0:
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(!!p && !!host.events && !!Clawd.manifest && resting(), "spawned and resting")) break;
                expect(Cava.regs === 0 && Cava.unregs === 0 && !host.events.registered, "no Cava consumer while silent");
                expect(Clawd.reactions === "all" && !Clawd.dnd, "defaults");
                // a new track: the bubble shows the title, 28 chars at most, the lowest rank; the pace is only known from the beat
                MprisController.trackTitle = "An extremely long track title that does not fit a bubble";
                MprisController.isPlaying = true;
                break;
            case 2:
                expect(Clawd.bubble && Clawd.bubble.key === "shell:track" && Clawd.bubble.kind === "music" && Clawd.bubble.text.startsWith("♪ ") && Clawd.bubble.text.length <= 28, "track bubble: " + JSON.stringify(Clawd.bubble));
                expect(Clawd.bubbleTimer.interval === 4000, "shell bubbles last 4 s");
                if (!wait(Cava.regs === 1 && host.events.registered, "Cava consumer registered once")) break;
                expect(Cava.unregs === 0, "not released while he plays");
                break;
            case 3:
                if (!wait(p.mode === "dance" && (p.animation === "dance" || p.animation === "dance_2"), "dances", 200)) break;
                expect(Math.abs(p.beat - 1) < 0.01 || host.events.bpm > 0, "pace 1 until a beat is known");
                break;
            case 4:
                if (!wait(host.events.bpm >= 145 && host.events.bpm <= 155 && p.mode === "dance", "150 BPM beat found", 200)) break;
                expect(Math.abs(p.beat - 1.25) < 0.08, "dance pace follows the beat: " + p.beat);
                MprisController.isPlaying = false;
                break;
            case 5:
                if (!wait(Cava.unregs === 1 && p.mode !== "dance", "music stop releases Cava and ends the dance")) break;
                expect(Cava.regs === 1 && Math.abs(p.beat - 1) < 0.01 && host.events.bpm === 0, "paired and reset");
                MprisController.isPlaying = true;
                break;
            case 6:
                if (!wait(Cava.regs === 2 && host.events.registered, "plays again: registered again")) break;
                Config.setSetting("general.performance", true);
                break;
            case 7:
                if (!wait(Cava.unregs === 2 && p.mode !== "dance" && !host.events.registered, "low motion: no Cava, no dance")) break;
                Config.setSetting("general.performance", false);
                break;
            case 8:
                if (!wait(Cava.regs === 3, "low motion off: registered")) break;
                Config.setSetting("addonsV2ClawdReactions", "quiet");
                break;
            case 9:
                if (!wait(Cava.unregs === 3 && p.mode !== "dance", "quiet: no Cava, no dance")) break;
                Config.setSetting("addonsV2ClawdReactions", "all");
                MprisController.isPlaying = false;
                break;
            case 10:
                if (!wait(Cava.regs === Cava.unregs && Cava.regs >= 3 && !host.events.registered, "paired after stop")) break;
                break;
            case 11:
                // notifications: the app name only
                if (!wait(resting(), "resting")) break;
                fresh();
                notify("Firefox", 1);
                expect(Clawd.bubble && Clawd.bubble.text === "✉ Firefox" && Clawd.bubble.text.indexOf("SECRET") < 0, "app name only: " + JSON.stringify(Clawd.bubble));
                expect(p.mode === "react" && p.animation === "look_up", "looks up: " + p.animation);
                break;
            case 12:
                if (!wait(p.animation === "read", "then reads", 60)) break;
                fresh();
                p.enter("idle", "idle");
                notify("Mail", 2);
                expect(Clawd.bubble && Clawd.bubble.text === "! Mail" && p.animation === "alert", "critical alerts: " + p.animation);
                break;
            case 13:
                fresh();
                p.enter("idle", "idle");
                notify("quickactions.timer.notification.app_name", 1);
                expect(Clawd.bubble && Clawd.bubble.text === "⏰ timer" && p.animation === "alert", "timer ring");
                break;
            case 14:
                // ranks: a pending permission is never replaced by a shell bubble
                fresh();
                p.enter("idle", "idle");
                Clawd.say("claude:r", "permission", "⚠ permission · proj");
                notify("Mail", 2);
                expect(Clawd.bubble.kind === "permission", "permission outranks a notification");
                Clawd.say("claude:r", "done", "✓ done · proj");
                expect(Clawd.bubble.kind === "done", "the same session moves on");
                Clawd.say("shell:x", "notif", "✉ X");
                expect(Clawd.bubble.kind === "done", "notification below done");
                Clawd.say("claude:y", "error", "✗ error · y");
                expect(Clawd.bubble.kind === "error", "error replaces done");
                Clawd.dismiss();
                // do not disturb: normal notifications muted, critical ones not
                Config.setSetting("notifications.dnd", true);
                fresh();
                p.enter("idle", "idle");
                notify("Firefox", 1);
                expect(!Clawd.bubble && p.mode === "idle", "dnd mutes");
                notify("Mail", 2);
                expect(Clawd.bubble && p.animation === "alert", "critical passes dnd");
                Config.setSetting("notifications.dnd", false);
                break;
            case 15:
                // dead or in a scene: nothing happens
                fresh();
                p.enter("idle", "idle");
                p.dead = true;
                notify("Mail", 2);
                OsdController.sysVolume = 40;
                OsdController.sysVolume = 96;
                LauncherController.isVisible = true;
                expect(!Clawd.bubble && p.mode === "idle" && p.animation === "idle", "dead: no reaction, no bubble: " + p.animation);
                p.dead = false;
                LauncherController.isVisible = false;
                break;
            case 16:
                // volume and mute
                fresh();
                p.enter("idle", "idle");
                OsdController.sysVolume = 30;
                OsdController.sysVolume = 96;
                expect(p.animation === "cover_ears", "loud volume covers his ears: " + p.animation);
                break;
            case 17:
                fresh();
                p.enter("idle", "idle");
                OsdController.sysMuted = true;
                expect(p.animation === "shush", "mute shushes: " + p.animation);
                OsdController.sysMuted = false;
                break;
            case 18:
                // launcher and clipboard
                fresh();
                p.enter("idle", "idle");
                LauncherController.isVisible = true;
                expect(p.animation === "look_up", "launcher: " + p.animation);
                LauncherController.isVisible = false;
                break;
            case 19:
                fresh();
                p.enter("idle", "idle");
                ClipboardController.isVisible = true;
                expect(p.mode === "react" && p.animation.startsWith("look_"), "clipboard glance: " + p.animation);
                ClipboardController.isVisible = false;
                break;
            case 20:
                // moods follow the state
                fresh();
                p.enter("idle", "idle");
                OsdController.sysBrightness = 10;
                break;
            case 21:
                if (!wait(p.mood === "drowsy", "dim screen: drowsy")) break;
                expect(p.sleepAfter === Clawd.sleepMinutes * 30000, "drowsy halves the nap delay");
                OsdController.sysBrightness = 60;
                break;
            case 22:
                if (!wait(p.mood === "", "bright again: awake")) break;
                fresh();
                SysNotif.hasBattery = true;
                SysNotif.batteryPercentage = 12;
                break;
            case 23:
                if (!wait(p.mood === "exhausted", "low battery: exhausted")) break;
                SysNotif.isCharging = true;
                break;
            case 24:
                if (!wait(p.mood === "", "charging clears it")) break;
                SysNotif.isCharging = false;
                SysNotif.batteryPercentage = 3;
                fresh();
                break;
            case 25:
                if (!wait(p.mood === "exhausted", "critical battery")) break;
                SysNotif.isCharging = true;
                break;
            case 26:
                if (!wait(p.mood === "", "charging again")) break;
                // reactions off: only urgent events
                Config.setSetting("addonsV2ClawdReactions", "off");
                fresh();
                p.enter("idle", "idle");
                notify("Firefox", 1);
                expect(!Clawd.bubble && p.mode === "idle", "off: a normal notification is ignored");
                notify("Mail", 2);
                expect(!!Clawd.bubble && p.animation === "alert", "off: a critical one still counts");
                Config.setSetting("addonsV2ClawdReactions", "all");
                MprisController.isPlaying = false;
                break;
            case 27:
                // 5d: rain makes him wet (a mood), snow cold, a clear sky clears it; storms count as rain
                if (!wait(resting(), "resting, music off")) break;
                fresh();
                Weather.currentIcon = String.fromCodePoint(0xf0597);
                break;
            case 28:
                if (!wait(p.mood === "rain", "rain: mood rain")) break;
                expect(["sit", "umbrella"].indexOf(p.moodSit()) >= 0, "sits or opens his umbrella: " + p.moodSit());
                Weather.currentIcon = String.fromCodePoint(0xf185);
                break;
            case 29:
                if (!wait(p.mood === "", "sun: dry again")) break;
                fresh();
                Weather.currentIcon = String.fromCodePoint(0xf2dc);
                break;
            case 30:
                if (!wait(p.mood === "snow", "snow: mood snow")) break;
                expect(["sit", "shiver"].indexOf(p.moodSit()) >= 0, "sits or shivers: " + p.moodSit());
                Weather.currentIcon = "";
                break;
            case 31:
                if (!wait(p.mood === "", "no weather: clear")) break;
                fresh();
                Weather.currentIcon = String.fromCodePoint(0xf0e7);
                break;
            case 32:
                if (!wait(p.mood === "rain", "storm counts as rain")) break;
                Weather.currentIcon = "";
                break;
            case 33:
                if (!wait(p.mood === "", "storm over")) break;
                // widgets moved or added in the shell: the layers are fetched again 450 ms later; the widget editor hides the ledges
                mark = host.world.resyncs;
                WidgetSync.widgetAdded();
                WidgetSync.redactModeChanged(main, true);
                expect(host.world.redact, "widget editor on: no widget ledges");
                break;
            case 34:
                if (!wait(host.world.resyncs > mark, "layers fetched again after a WidgetSync signal")) break;
                WidgetSync.redactModeChanged(main, false);
                expect(!host.world.redact, "widget editor off");
                // the hour: ms until the next :00, and nothing without a clock widget on his display
                expect(host.events.untilHour(new Date(2026, 0, 1, 10, 59, 30, 0)) === 30000 && host.events.untilHour(new Date(2026, 0, 1, 10, 0, 0, 0)) === 3600000, "aligned to :00");
                expect(host.events.untilHour(new Date(2026, 0, 1, 10, 59, 59, 500)) === 3600500, "never under 2 s");
                fresh();
                p.enter("idle", "idle");
                expect(!p.hourChime() && p.animation === "idle", "no clock widget: no chime");
                // a running timer: a glance up toward the bar
                TimerState.entries = [{ id: 1 }];
                expect(host.events.timerOn, "timer running");
                host.events.timerGlance();
                expect(p.mode === "react" && p.animation === "look_up", "glances up: " + p.animation);
                TimerState.entries = [];
                MprisController.isPlaying = true;
                break;
            case 35:
                // OFF while he dances: the consumer is released with the component
                if (!wait(host.events && host.events.registered, "registered before OFF")) break;
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 36:
                if (!wait(!host.events && Cava.regs === Cava.unregs, "OFF destroyed the events and released Cava", 120)) break;
                console.log("CLAWD_PASS");
                Qt.exit(0);
                break;
            }
        }
    }
}
