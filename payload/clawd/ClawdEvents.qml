import QtQuick
import Quickshell
import "../"
import "js/beat.mjs" as Beat
import "js/world.mjs" as World

// What the shell tells Clawd (5c): music (a track bubble, dancing to Cava's beat: Spotify only, its own volume near 100 %), notifications, mute / brightness, the battery,
// the launcher, clipboard and menus; 5d: the weather (rain, snow), the hourly chime at a clock widget, a running timer. Shell process only; the Loader scope of AddonClawd owns it, so Clawd OFF destroys it and releases Cava.
// Every singleton is guarded (fixtures and the Settings process lack them); each event goes pet.shell(kind) -> Mind -> a reaction, a mood or a bubble.
// Bubbles show the app name or the track title, never a notification's summary or body.
Scope {
    id: events
    property var pet: null
    readonly property var mpris: typeof MprisController !== "undefined" ? MprisController : null
    readonly property var cava: typeof Cava !== "undefined" ? Cava : null
    readonly property var osd: typeof OsdController !== "undefined" ? OsdController : null
    readonly property var sys: typeof SysNotif !== "undefined" ? SysNotif : null
    readonly property var notifs: typeof NotificationManager !== "undefined" ? NotificationManager : null
    readonly property var launcher: typeof LauncherController !== "undefined" ? LauncherController : null
    readonly property var clipboard: typeof ClipboardController !== "undefined" ? ClipboardController : null
    readonly property var menu: typeof DesktopMenuController !== "undefined" ? DesktopMenuController : null
    readonly property var weather: typeof Weather !== "undefined" ? Weather : null
    readonly property var timers: typeof TimerState !== "undefined" ? TimerState : null
    readonly property string sky: weather ? World.weatherKind(weather.currentIcon) : "other"
    readonly property bool timerOn: !!timers && timers.isActive === true
    readonly property bool playing: !!mpris && mpris.isPlaying === true
    readonly property string title: mpris ? String(mpris.trackTitle || "") : ""
    // he dances to Spotify only (not a video), and only when it plays loud: its own volume near 100 % (background music at 60 % is not his)
    readonly property var player: mpris && mpris.activePlayer ? mpris.activePlayer : null
    readonly property bool spotify: !!player && /spotify/i.test([player.identity, player.desktopEntry, player.busName].map(v => String(v || "")).join(" "))
    readonly property real appVolume: { if (!player || player.volumeSupported === false) return 1; const v = Number(player.volume); return isFinite(v) ? v : 1; }
    readonly property bool loud: appVolume >= 0.9
    readonly property bool launcherOpen: !!launcher && launcher.isVisible === true
    readonly property bool clipboardOpen: !!clipboard && clipboard.isVisible === true
    readonly property bool menuOpen: !!menu && menu.isVisible === true
    readonly property bool muted: !!osd && osd.sysMuted === true
    readonly property real brightness: osd ? Number(osd.sysBrightness) || 0 : 0
    readonly property bool charging: !!sys && sys.isCharging === true
    readonly property real battery: sys && sys.hasBattery === true ? Number(sys.batteryPercentage) || 0 : -1
    // dancing needs Spotify loud, motion allowed, his full reactions, a living pet that is not at work
    readonly property bool grooving: playing && spotify && loud && !!pet && !pet.dead && !Clawd.lowMotion && Clawd.reactions === "all" && !Clawd.activity
    readonly property bool wantCava: grooving && !!cava
    property bool registered: false
    property var tempo: Beat.create()
    property int bpm: 0
    property string lastTitle: ""

    function clean(text, n) { return Clawd.clip(String(text || "").replace(/[\x00-\x1f\x7f-\x9f‎‏‪-‮⁦-⁩]/g, "").trim(), n); }
    // The event through Mind; a bubble when it was not refused.
    function tell(kind, info, text, bubble) {
        if (!pet) return "none";
        const act = pet.shell(kind, info);
        if (act !== "none" && text) Clawd.say("shell:" + kind, bubble || "notif", text);
        return act;
    }

    function notified(n) {
        if (!n) return;
        const full = clean(n.appName, 80), app = Clawd.clip(full, 24), urgency = Number(n.urgency);
        const timerApp = typeof I18n !== "undefined" ? I18n.t("quickactions.timer.notification.app_name") : "";
        if (full && full === timerApp) tell("timer_ring", {}, "⏰ timer");
        else if (urgency >= 2) tell("notif_critical", {}, "! " + (app || "notification"));
        else if (urgency === 1 || isNaN(urgency)) {
            if (pet && pet.notifWalk()) Clawd.say("shell:notif", "notif", "✉ " + (app || "notification"));
            else tell("notif", { chain: "read" }, "✉ " + (app || "notification"));
        }
        else tell("notif", {}, "");
    }
    Connections {
        target: events.notifs
        ignoreUnknownSignals: true
        function onPopupAdded(uid, n) { events.notified(n); }
    }

    onMutedChanged: if (muted) tell("mute", {}, "")
    onLauncherOpenChanged: if (launcherOpen) tell("layer", {}, "")
    onClipboardOpenChanged: if (clipboardOpen) tell("shell_menu", {}, "")
    onMenuOpenChanged: if (menuOpen) tell("shell_menu", {}, "")
    onChargingChanged: if (pet && charging && battery >= 0) { pet.clearMood("exhausted"); tell("charging", {}, ""); }
    onTitleChanged: {
        if (!title || title === lastTitle) return;
        lastTitle = title;
        tell("track", {}, "♪ " + clean(title, 26), "music");
    }

    // Moods follow the state (dim screen, low battery) and clear with it; Mind may refuse one now, so this is retried every 2 s.
    function refresh() {
        if (!pet) return;
        if (Clawd.reactions === "off") pet.clearMood(pet.mood);
        const dim = brightness > 0 && brightness <= 15, low = battery > 0 && !charging && battery <= 15;
        if (!dim) pet.clearMood("drowsy");
        if (!low) pet.clearMood("exhausted");
        if (low && pet.mood !== "exhausted") tell("battery_low", {}, "");
        else if (dim && pet.mood === "") tell("brightness_low", {}, "");
        if (low && battery <= 5 && tell("battery_critical", {}, "") !== "none") pet.setMood("exhausted");
        // the weather: a lasting mood (storms count as rain), cleared when the sky is
        const wet = sky === "rain" || sky === "storm", snowing = sky === "snow";
        if (!wet) pet.clearMood("rain");
        if (!snowing) pet.clearMood("snow");
        if ((wet || snowing) && pet.mood === "") tell("rain", { mood: snowing ? "snow" : "rain" }, "");
        if (grooving && !pet.dead) pet.groove(bpm);
        else if (!grooving) pet.stopDance();
    }
    onGroovingChanged: refresh()
    Timer { interval: 2000; repeat: true; running: !!events.pet; triggeredOnStart: true; onTriggered: events.refresh() }

    // The hour: ms until the next :00 (never under 2 s: a timer that fires a hair early waits for the following hour).
    function untilHour(now) {
        const n = now || new Date(), ms = 3600000 - (n.getMinutes() * 60 + n.getSeconds()) * 1000 - n.getMilliseconds();
        return ms < 2000 ? ms + 3600000 : ms;
    }
    // At :00 (a woken-up laptop may fire late: only within a minute of the hour) with a clock widget on his display, the pet goes to chime.
    function chime() {
        const m = new Date().getMinutes();
        if (pet && m === 0) pet.hourChime();
    }
    Timer {
        id: hourly
        interval: events.untilHour(); running: !!events.pet
        onTriggered: { events.chime(); interval = events.untilHour(); restart(); }
    }
    // A running timer: now and then he glances up toward the bar.
    function timerGlance() {
        if (pet && timerOn) tell("layer", { look: [pet.x + pet.width / 2, pet.here ? pet.here.top : pet.y - 200] }, "");
    }
    Timer {
        interval: 60000; repeat: true; running: !!events.pet && events.timerOn
        onTriggered: { interval = 60000 + Math.random() * 90000; if (Math.random() < 0.5) events.timerGlance(); }
    }

    // Cava is shared: registered exactly while he can dance, released on stop, OFF, low motion, quiet reactions and destruction.
    readonly property bool cavaApi: !!cava && typeof cava.registerConsumer === "function" && typeof cava.unregisterConsumer === "function"
    function syncCava() {
        if (wantCava && cavaApi && !registered) { cava.registerConsumer(); registered = true; }
        else if ((!wantCava || !cavaApi) && registered) {
            registered = false;
            tempo = Beat.create();
            bpm = 0;
            if (cavaApi) cava.unregisterConsumer();
        }
    }
    onWantCavaChanged: syncCava()
    Component.onCompleted: { lastTitle = title; syncCava(); }
    Component.onDestruction: if (registered && cavaApi) cava.unregisterConsumer()
    // the low bars carry the kick: their mean every 50 ms
    Timer {
        interval: 50; repeat: true; running: events.registered
        onTriggered: {
            const lv = events.cava && typeof events.cava === "object" ? events.cava.barLevels : null;
            if (!lv || !lv.length) return;
            let sum = 0;
            const n = Math.min(8, lv.length);
            for (let i = 0; i < n; i++) sum += Number(lv[i]) || 0;
            events.tempo = Beat.push(events.tempo, sum / n, Date.now());
            if (events.tempo.bpm !== events.bpm) { events.bpm = events.tempo.bpm; if (events.pet) events.pet.groove(events.bpm); }
        }
    }
}
