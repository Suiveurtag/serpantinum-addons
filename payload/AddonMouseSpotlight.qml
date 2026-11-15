import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool niri: !!Quickshell.env("NIRI_SOCKET")
    property bool active: false
    property bool ready: false
    property real pointerX: 0
    property real pointerY: 0
    property real reveal: 0
    property real spread: 1
    readonly property int entranceDuration: Math.max(100, Config.getSetting("addonsV2SpotlightEntrance", 650))
    readonly property int exitDuration: Math.max(100, Config.getSetting("addonsV2SpotlightExit", 800))
    property real radius: Scaler.s(Config.getSetting("addonsV2SpotlightRadius", 95))
    readonly property real dimming: Config.getSetting("addonsV2SpotlightDimming", 0.65)

    Behavior on reveal {
        NumberAnimation {
            duration: root.active ? root.entranceDuration : root.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.active ? [0.22, 1, 0.36, 1, 1, 1] : [0.4, 0, 0.2, 1, 1, 1]
        }
    }
    Behavior on spread {
        enabled: root.ready
        NumberAnimation {
            duration: root.active ? root.entranceDuration : root.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
        }
    }
    Behavior on radius { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    function open() {
        if (active) return;
        active = true;
        if (niri) ready = true;
        if (ready) { spread = 0; reveal = 1; }
    }
    function close() { active = false; spread = 0.06; reveal = 0; }
    function resizeCircle(delta) {
        let current = Config.getSetting("addonsV2SpotlightRadius", 95);
        Config.setSetting("addonsV2SpotlightRadius", Math.round(Math.max(35, Math.min(350, current + delta))));
    }

    IpcHandler {
        target: "addonMouseSpotlight"
        function toggle(): void { root.active ? root.close() : root.open(); }
        function activate(): void { root.open(); }
        function deactivate(): void { root.close(); }
    }

    Process {
        id: cursor
        running: !root.niri && (root.active || root.reveal > 0)
        command: ["python3", "-u", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/mouse_spotlight.py"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let point = JSON.parse(data);
                    root.pointerX = point.x;
                    root.pointerY = point.y;
                    if (!root.ready && root.reveal === 0) root.spread = 1;
                    root.ready = true;
                    if (root.active) { root.spread = 0; root.reveal = 1; }
                } catch (e) { console.warn("Mouse spotlight: invalid cursor position", e); }
            }
        }
        onRunningChanged: if (!running) root.ready = false
        onExited: (code, status) => {
            if (root.active) {
                root.close();
                Quickshell.execDetached(["notify-send", "-a", "Serpantinum", "Mouse spotlight", "Could not track the pointer. Check the Hyprland session."]);
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: root.ready && root.reveal > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: root.active && screen === Quickshell.cursorScreen
            // Consume the dismissing click; release input immediately during fade-out.
            mask: Region { item: root.active ? input : null }
            WlrLayershell.namespace: "qs-addon-mouse-spotlight"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active && screen === Quickshell.cursorScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            readonly property var monitor: Quickshell.env("NIRI_SOCKET") ? screen : Hyprland.monitorFor(screen)
            readonly property real cx: root.pointerX - (monitor ? monitor.x : 0)
            readonly property real cy: root.pointerY - (monitor ? monitor.y : 0)
            readonly property real spotRadius: root.radius + root.spread * Math.hypot(width, height)

            Shortcut { sequence: "Escape"; enabled: root.active && overlay.screen === Quickshell.cursorScreen; onActivated: root.close() }
            MouseArea {
                id: input
                anchors.fill: parent
                enabled: root.active
                hoverEnabled: root.niri
                onPositionChanged: mouse => {
                    if (!root.niri) return;
                    root.pointerX = mouse.x + overlay.screen.x;
                    root.pointerY = mouse.y + overlay.screen.y;
                }
                onEntered: if (root.niri) {
                    root.pointerX = mouseX + overlay.screen.x;
                    root.pointerY = mouseY + overlay.screen.y;
                }
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => { mouse.accepted = true; root.close(); }
                onWheel: wheel => {
                    let delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y / 120 * 10 : wheel.pixelDelta.y / 4;
                    root.resizeCircle(delta);
                    wheel.accepted = true;
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.rgba(0, 0, 0, root.dimming * root.reveal)
                    fillRule: ShapePath.OddEvenFill
                    PathSvg {
                        // Transparent circular hole in the live desktop dimmer.
                        path: "M 0 0 H " + overlay.width + " V " + overlay.height + " H 0 Z "
                            + "M " + (overlay.cx - overlay.spotRadius) + " " + overlay.cy
                            + " a " + overlay.spotRadius + " " + overlay.spotRadius + " 0 1 0 " + (2 * overlay.spotRadius) + " 0"
                            + " a " + overlay.spotRadius + " " + overlay.spotRadius + " 0 1 0 " + (-2 * overlay.spotRadius) + " 0 Z"
                    }
                }
            }
            Rectangle {
                x: overlay.cx - overlay.spotRadius; y: overlay.cy - overlay.spotRadius
                width: overlay.spotRadius * 2; height: width; radius: width / 2
                color: "transparent"
                border.width: Scaler.s(1.5)
                border.color: Qt.rgba(1, 1, 1, 0.22 * root.reveal)
            }
        }
    }
}
