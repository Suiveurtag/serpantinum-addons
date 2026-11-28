pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Christmas: switch, light style, the shell areas it decorates and the one twinkle clock every string of lights
// reads. Nothing here draws; every effect loads only while the season is on (and its area is).
Scope {
    id: xmas

    readonly property bool enabled: Config.getSetting("addonsV2Christmas", false)
    readonly property bool motion: enabled && !Config.getSetting("general.performance", false)
    readonly property string lights: {
        const value = Config.getSetting("addonsV2ChristmasLights", "classic");
        return styles.indexOf(value) >= 0 ? value : "classic";
    }
    readonly property int lightsIndex: styles.indexOf(lights)
    readonly property bool twinkle: Config.getSetting("addonsV2ChristmasTwinkle", true) !== false
    readonly property bool randomLights: Config.getSetting("addonsV2ChristmasRandomLights", false) === true
    readonly property var styles: ["classic", "warm", "candy", "nordic"]
    readonly property var areas: ["bar", "system", "network", "launcher", "calendar", "widgets", "panels", "settings", "buttons", "windows", "notifications"]

    // The weather now is below freezing, in whatever unit it is reported.
    property bool freezePreview: false      // IPC: see the ice without waiting for the cold
    readonly property bool freezing: {
        if (freezePreview) return true;
        const data = Weather.data;
        if (!data || data.offline || data.current_temp === undefined || data.current_temp === null) return false;
        const point = Weather.unit === "imperial" ? 32 : Weather.unit === "standard" ? 273.15 : 0;
        return Number(data.current_temp) < point;
    }

    // Areas default to on; each can be switched off from the banner. An area stays loaded a moment after the switch
    // goes off (`present`), so its lights can go out instead of vanishing; effects that start something check `enabled`.
    function area(name: string): bool { return Config.getSetting("addonsV2ChristmasFx." + name, true) !== false; }
    function setArea(name: string, value: bool): void { Config.setSetting("addonsV2ChristmasFx." + name, value); }
    readonly property bool bar: present && area("bar")
    readonly property bool system: present && area("system")
    readonly property bool network: present && area("network")
    readonly property bool launcher: present && area("launcher")
    readonly property bool calendar: present && area("calendar")
    readonly property bool widgets: present && area("widgets")
    readonly property bool panels: present && area("panels")
    readonly property bool settings: present && area("settings")
    readonly property bool buttons: present && area("buttons")
    readonly property bool windows: present && area("windows")
    readonly property bool notifications: present && area("notifications")

    // One opacity, 0.1 .. 1, for the large effects: panel wrapping, window lights, notification wrap, switch-on garland.
    readonly property real effectOpacity: {
        const value = Number(Config.getSetting("addonsV2ChristmasOpacity", 0.7));
        return isNaN(value) ? 0.7 : Math.max(0.1, Math.min(1, value));
    }
    function setEffectOpacity(value: real): void { Config.setSetting("addonsV2ChristmasOpacity", Math.max(0.1, Math.min(1, value))); }

    readonly property bool present: enabled || outro.running
    Timer { id: outro; interval: 900 }
    onEnabledChanged: {
        if (!enabled) outro.restart();
        else if (armed) { switchedOnAt = Date.now(); introSerial++; lightsOnSerial++; }
    }
    // The intro's windows are created by the same switch, after the serial moved: they check this on creation.
    property double switchedOnAt: 0
    // The intro plays when the season is switched on, not at every shell start.
    property bool armed: false
    property int introSerial: 0
    property int lightsOnSerial: 0
    Timer { interval: 2500; running: true; onTriggered: xmas.armed = true }

    // A panel's gift layer reports its close and reopening; the host's layer plays the send-off, which outlives the panel.
    signal panelClosed(string screen, rect frame, string edge, real radius)
    signal panelOpened(string screen)

    // Palette shared by the effects and the banner.
    readonly property color gold: "#f2c46d"
    readonly property color paleGold: "#ffe3a6"
    readonly property color cranberry: "#c8344a"
    readonly property color deepRed: "#7d1828"
    readonly property color pine: "#1d4634"
    readonly property color holly: "#2f7c50"
    readonly property color cream: "#f7eedc"
    readonly property color wire: "#16261c"
    readonly property var bulbs: ({
        classic: ["#ff4538", "#ffbd38", "#38d873", "#459eff"],
        warm: ["#ffc773", "#ffd99a", "#ffe8bd"],
        candy: ["#ff3347", "#fff1ec"],
        nordic: ["#99d9ff", "#eaf4ff", "#ffe5ad"]
    })
    readonly property var palette: bulbs[lights]
    function bulb(index: int): color { return palette[((index % palette.length) + palette.length) % palette.length]; }

    // Twinkle clock: one Timer at ~12 Hz for every string on every screen, running only while a string is shown.
    property real phase: 0
    property int clockUsers: 0
    function requestClock(on: bool): void { clockUsers = Math.max(0, clockUsers + (on ? 1 : -1)); }
    Timer {
        interval: 80; repeat: true
        running: xmas.motion && xmas.twinkle && xmas.clockUsers > 0
        onTriggered: xmas.phase = (xmas.phase + 0.08) % 3600
    }

    // Shared rate limit, so a burst of clicks or focus changes never stacks effects.
    property var lastPlayed: ({})
    function allow(kind: string, gap: int): bool {
        if (!motion) return false;
        const now = Date.now();
        if (now - (lastPlayed[kind] || 0) < gap) return false;
        lastPlayed[kind] = now;
        return true;
    }

    // Countdown shown on the banner.
    function countdown(): string {
        const now = new Date();
        const year = now.getMonth() === 0 && now.getDate() <= 6 ? now.getFullYear() - 1 : now.getFullYear();
        const eve = new Date(year, 11, 24), day = new Date(year, 11, 25);
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const nights = Math.round((day - today) / 86400000);
        if (today.getTime() === eve.getTime()) return qsTr("Christmas Eve tonight");
        if (today.getTime() === day.getTime()) return qsTr("Merry Christmas");
        if (nights < 0) return qsTr("Happy holidays");
        if (nights === 1) return qsTr("One more sleep until Christmas");
        return nights + qsTr(" sleeps until Christmas");
    }

    IpcHandler {
        target: "christmas"
        function setEnabled(value: bool): void { Config.setSetting("addonsV2Christmas", value); }
        function toggle(): void { Config.setSetting("addonsV2Christmas", !xmas.enabled); }
        function setLights(value: string): void { if (xmas.styles.indexOf(value) >= 0) Config.setSetting("addonsV2ChristmasLights", value); }
        function setArea(name: string, value: bool): void { if (xmas.areas.indexOf(name) >= 0) xmas.setArea(name, value); }
        function setOpacity(percent: int): void { xmas.setEffectOpacity(percent / 100); }
        function intro(): void { if (xmas.enabled) { xmas.introSerial++; xmas.lightsOnSerial++; } }
        function previewFreeze(value: bool): void { xmas.freezePreview = value; }
        function status(): string {
            return JSON.stringify({ enabled: xmas.enabled, motion: xmas.motion, lights: xmas.lights, twinkle: xmas.twinkle, freezing: xmas.freezing,
                areas: xmas.areas.reduce((all, name) => { all[name] = xmas[name]; return all; }, {}),
                clockUsers: xmas.clockUsers, introSerial: xmas.introSerial });
        }
    }
}
