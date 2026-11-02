import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool active: false
    property bool ready: false
    property real pointerX: 0
    property real pointerY: 0
    property real factor: 1
    property real targetFactor: 2

    function open() {
        if (worker.running) return;
        ready = false;
        targetFactor = Math.max(1.15, Math.min(6, Config.getSetting("addonsV2ZoomFactor", 2)));
        active = true;
        worker.running = true;
    }
    function close() {
        active = false;
        if (ready) Config.setSetting("addonsV2ZoomFactor", targetFactor);
        if (ready && worker.running) worker.write(JSON.stringify({close: true}) + "\n");
        else if (worker.running) worker.running = false;
    }
    function adjust(steps) {
        if (!active || !ready) return;
        targetFactor = Math.max(1, Math.min(6, targetFactor * Math.pow(1.15, steps)));
        // Fully zoomed out: close, and reopen next time at a small level instead of ×1.
        if (targetFactor <= 1) {
            targetFactor = 1.5;
            close();
            return;
        }
        worker.write(JSON.stringify({factor: targetFactor}) + "\n");
    }
    Component.onDestruction: if (worker.running) worker.running = false

    IpcHandler {
        target: "addonDesktopZoom"
        function status(): string { return JSON.stringify({active: root.active, ready: root.ready, factor: root.factor, x: root.pointerX, y: root.pointerY}); }
        function toggle(): void { root.active ? root.close() : root.open(); }
        function activate(): void { root.open(); }
        function deactivate(): void { root.close(); }
        function zoomIn(): void { root.adjust(1); }
        function zoomOut(): void { root.adjust(-1); }
    }

    Process {
        id: worker
        command: ["python3", "-u", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/desktop_zoom.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    let state = JSON.parse(data);
                    root.factor = state.factor;
                    if (state.ready) {
                        root.pointerX = state.x;
                        root.pointerY = state.y;
                        root.ready = true;
                        worker.write(JSON.stringify(root.active ? {factor: root.targetFactor} : {close: true}) + "\n");
                    }
                } catch (e) { console.warn("Desktop zoom:", e); }
            }
        }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onExited: (code, status) => {
            root.active = false;
            root.ready = false;
            if (code !== 0) Quickshell.execDetached(["notify-send", "-a", "Serpantinum", "Desktop zoom", "Could not zoom the desktop. Check the Hyprland session."]);
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: root.ready
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            focusable: root.active && pointerScreen
            mask: Region { item: input; intersection: Intersection.Xor }
            WlrLayershell.namespace: "qs-addon-desktop-zoom"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active && pointerScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            readonly property var monitor: Hyprland.monitorFor(screen)
            readonly property bool pointerScreen: pointerX >= 0 && pointerY >= 0 && pointerX < width && pointerY < height
            readonly property real pointerX: root.pointerX - (monitor ? monitor.x : 0)
            readonly property real pointerY: root.pointerY - (monitor ? monitor.y : 0)

            Shortcut { sequence: "Escape"; enabled: root.active; onActivated: root.close() }
            Item {
                id: input
                anchors.fill: parent
            }

        }
    }
}
