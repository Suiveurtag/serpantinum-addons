import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property bool enabledOutline: Config.dataReady && Config.getSetting("addonsV2WindowOutline", false)
    readonly property string accent: String(ThemeBackend.blue)
    readonly property string secondary: String(ThemeBackend.mauve)
    readonly property string muted: String(ThemeBackend.overlay0)
    property bool dirty: false

    function schedule() {
        if (!Config.dataReady) return;
        dirty = true;
        debounce.restart();
    }
    onEnabledOutlineChanged: schedule()
    onAccentChanged: if (enabledOutline) schedule()
    onSecondaryChanged: if (enabledOutline) schedule()
    onMutedChanged: if (enabledOutline) schedule()
    Connections {
        target: Config
        function onDataReadyChanged() { if (Config.dataReady) root.schedule(); }
    }
    Timer {
        id: debounce
        interval: 500
        onTriggered: {
            if (apply.running) return;
            root.dirty = false;
            apply.command = ["python3", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/window_outline.py",
                             root.enabledOutline ? "on" : "off", root.accent, root.secondary, root.muted];
            apply.running = true;
        }
    }
    Process {
        id: apply
        stderr: StdioCollector { onStreamFinished: { if (text) console.warn("Window outline: " + text); } }
        onExited: (code, status) => {
            if (code !== 0) console.warn("Window outline could not be applied (exit " + code + ")");
            if (root.dirty) debounce.restart();
        }
    }
    Component.onCompleted: schedule()
}
