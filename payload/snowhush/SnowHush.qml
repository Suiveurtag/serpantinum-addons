pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../"

Scope {
    id: root

    readonly property bool available: Quickshell.env("WAYLAND_DISPLAY") !== ""
        && Quickshell.env("XDG_RUNTIME_DIR") !== "" && Quickshell.env("SERPANTINUM_STANDALONE") !== "1"
    readonly property bool startWithShell: Config.getSetting("addonsV2SnowHushStartWithShell", true) === true
    readonly property bool enabled: startWithShell ? Config.getSetting("addonsV2SnowHush", false) === true : session.enabled
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
    readonly property string wallpaperFile: Quickshell.env("XDG_RUNTIME_DIR") + "/serpantinum-snowhush-" + Quickshell.env("WAYLAND_DISPLAY").split("/").pop() + ".json"
    readonly property var wallpaperPaths: Wallpaper.screenWallpaperPaths
    readonly property var tray: {
        const items = SystemTray.items.values || [];
        return engine.running ? (items.find(item => item.id === "snowhush") || null) : null;
    }
    readonly property var menu: tray && verifiedPid > 0 && Number(engine.processId) === verifiedPid ? (tray.menu || null) : null
    readonly property bool starting: Boolean(enabled && (engine.running || collisionRetry.running) && !modeItems.length)
    property string error: ""
    property string modeError: ""
    property string requestedMode: ""
    property bool stopping: false
    property int collisionAttempts: 0
    property int verifiedPid: 0
    readonly property var surfaces: new Map()
    property string lastSurfaceData: ""
    property var clickedEntry: null
    property int previousCheckState: Qt.Unchecked

    // The pinned Linux release exposes its four falling modes, Mixed and
    // holiday switches in this order in its StatusNotifier Mode submenu.
    readonly property var menuItems: engineMenu.children.values || []
    readonly property var modeItems: modeMenu.children.values || []
    readonly property var mixed: modeItems[0] || null
    readonly property var snow: modeItems[2] || null
    readonly property var autumn: modeItems[3] || null
    readonly property var rain: modeItems[4] || null
    readonly property var halloween: modeItems[7] || null
    readonly property var newYear: modeItems[8] || null
    readonly property string mode: {
        if (!mixed || mixed.checkState === Qt.Checked || !snow || !autumn || !rain || !newYear)
            return "";
        if (snow.checkState === Qt.Checked) {
            if (newYear.checkState === Qt.Checked) return "new-year";
            if (halloween && halloween.checkState === Qt.Checked) return "";
            return "snow";
        }
        if (autumn.checkState === Qt.Checked) return "autumn";
        if (rain.checkState === Qt.Checked) return "rain";
        return "";
    }

    function publishWallpapers(): void {
        if (root.available && (root.enabled || engine.running))
            wallpaperData.setText(JSON.stringify(root.wallpaperPaths));
    }

    function setSurface(key: string, record: var): void {
        root.surfaces.set(key, record);
        Qt.callLater(root.publishSurfaces);
    }

    function removeSurface(key: string): void {
        if (root.surfaces.delete(key)) Qt.callLater(root.publishSurfaces);
    }

    function publishSurfaces(): void {
        if (!root.menu || !engine.running || !root.enabled) return;
        const data = JSON.stringify(Array.from(root.surfaces.values()));
        if (data === root.lastSurfaceData) return;
        root.lastSurfaceData = data;
        engine.write(data + "\n");
    }

    function start(): void {
        if (!root.available || !root.enabled || engine.running || root.stopping) return;
        root.error = "";
        root.publishWallpapers();
        engine.running = true;
    }

    function setStartWithShell(on: bool): void {
        const current = root.enabled;
        session.enabled = current;
        if (on) Config.setSetting("addonsV2SnowHush", current);
        Config.setSetting("addonsV2SnowHushStartWithShell", on);
    }

    function setEnabled(on: bool): void {
        if (!on) {
            root.requestedMode = "";
            root.error = "";
            root.modeError = "";
            modeStep.stop();
            collisionRetry.stop();
            root.clickedEntry = null;
        }
        if (!engine.running) root.collisionAttempts = 0;
        if (on !== root.enabled) {
            if (root.startWithShell) Config.setSetting("addonsV2SnowHush", on);
            else session.enabled = on;
        }
        if (on) root.start();
    }

    function selectMode(value: string): bool {
        if (!root.available || ["snow", "autumn", "rain", "new-year"].indexOf(value) < 0)
            return false;
        root.modeError = "";
        root.requestedMode = value;
        root.setEnabled(true);
        return true;
    }

    function applyMode(): void {
        if (!root.enabled || !root.requestedMode || !root.modeItems.length || modeStep.running) return;
        if (root.mode === root.requestedMode) {
            root.requestedMode = "";
            return;
        }

        let entry = root.requestedMode === "autumn" ? root.autumn : root.requestedMode === "rain" ? root.rain : root.snow;
        if (!entry || !root.mixed || !root.newYear || !root.halloween) return;
        if (root.mixed.checkState === Qt.Checked)
            entry = root.mixed;
        else if (entry.checkState === Qt.Checked)
            entry = root.requestedMode === "new-year" || root.newYear.checkState === Qt.Checked ? root.newYear : root.halloween;

        if (entry.enabled) {
            root.clickedEntry = entry;
            root.previousCheckState = entry.checkState;
            modeStep.start();
            entry.triggered();
        }
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.start();
        } else {
            collisionRetry.stop();
            if (engine.running) {
                root.stopping = true;
                engine.signal(15);
            }
        }
    }
    onWallpaperPathsChanged: publishWallpapers()
    onTrayChanged: if (root.tray) ownerCheck.running = true
    onMenuChanged: {
        root.lastSurfaceData = "";
        if (root.menu) {
            startupDeadline.stop();
            root.collisionAttempts = 0;
            root.publishSurfaces();
        }
    }
    onModeItemsChanged: Qt.callLater(root.applyMode)
    onModeChanged: Qt.callLater(root.applyMode)
    onRequestedModeChanged: Qt.callLater(root.applyMode)
    function finishModeClick(): void {
        if (modeStep.running && root.clickedEntry && root.clickedEntry.checkState !== root.previousCheckState) {
            modeStep.stop();
            root.clickedEntry = null;
            root.applyMode();
        }
    }
    Component.onCompleted: start()

    PersistentProperties {
        id: session
        property bool enabled: false
    }

    FileView {
        id: wallpaperData
        path: root.available ? root.wallpaperFile : ""
        printErrors: false
    }

    Process {
        id: engine
        command: ["python3", root.dataHome + "/serpantinum-addons-v2/scripts/snowhush/launch.py"]
        environment: ({ SERPANTINUM_SNOWHUSH_WALLPAPERS: root.wallpaperFile })
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                if (line === "SNOWHUSH_ENGINE_STARTING") startupDeadline.restart();
            }
        }
        stderr: StdioCollector { id: diagnostics }
        onExited: (code, status) => {
            root.verifiedPid = 0;
            startupDeadline.stop();
            modeStep.stop();
            root.clickedEntry = null;
            if (root.stopping) {
                root.stopping = false;
                if (root.enabled) Qt.callLater(root.start);
            } else if (root.enabled) {
                const message = diagnostics.text.trim();
                // A shell reload may start the replacement before D-Bus has
                // released the previous engine's name.
                if (message === "Snowhush is already running." && root.collisionAttempts < 3) {
                    root.collisionAttempts++;
                    collisionRetry.restart();
                } else if (code === 0 && status === 0 && !message && !root.error) {
                    root.setEnabled(false);
                } else {
                    root.error = root.error || message || qsTr("Snowhush stopped unexpectedly.");
                }
            }
        }
    }

    Process {
        id: ownerCheck
        command: ["dbus-send", "--session", "--print-reply=literal", "--reply-timeout=2000",
                  "--dest=org.freedesktop.DBus", "/org/freedesktop/DBus",
                  "org.freedesktop.DBus.GetConnectionUnixProcessID", "string:io.github.mbezruchko.Snowhush"]
        stdout: StdioCollector { id: owner }
        onExited: (code) => {
            const match = owner.text.match(/uint32\s+(\d+)/);
            if (code === 0 && match) root.verifiedPid = Number(match[1]);
        }
    }

    QsMenuOpener {
        id: engineMenu
        menu: root.menu || null
    }

    Connections {
        target: root.clickedEntry
        function onCheckStateChanged() { Qt.callLater(root.finishModeClick); }
    }

    QsMenuOpener {
        id: modeMenu
        menu: (engineMenu.children.values || [])[3] || null
    }

    Timer {
        id: collisionRetry
        interval: 450 * root.collisionAttempts
        onTriggered: root.start()
    }

    Timer {
        id: startupDeadline
        interval: 20000
        onTriggered: {
            if (engine.running && !root.modeItems.length) {
                root.error = qsTr("Snowhush did not publish its controls. Check the session and try again.");
                engine.signal(15);
            }
        }
    }

    Timer {
        id: modeStep
        interval: 2500
        onTriggered: {
            root.clickedEntry = null;
            if (root.mode !== root.requestedMode)
                root.modeError = qsTr("Snowhush did not confirm the mode change.");
            root.requestedMode = "";
        }
    }

    IpcHandler {
        target: "snowHush"

        function enable(): void { root.setEnabled(true); }
        function disable(): void { root.setEnabled(false); }
        function select(mode: string): bool { return root.selectMode(mode); }
        function status(): string {
            return JSON.stringify({ enabled: root.enabled, ready: root.modeItems.length > 0, mode: root.mode, surfaces: root.surfaces.size,
                                    pending: root.requestedMode, error: root.error || root.modeError });
        }
    }
}
