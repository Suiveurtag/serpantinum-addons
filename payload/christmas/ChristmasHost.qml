import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../"

// Christmas outside the shell's own surfaces: the lights strung around a window when it takes the focus, and the
// garland that drops over every screen when the season is switched on. One transparent, click-through layer per
// screen, mapped only while something plays.
Scope {
    id: host
    readonly property bool hyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property var target: null           // { x, y, w, h } in the global layout, and a serial per play
    property int windowSerial: 0

    Connections {
        target: Hyprland
        enabled: host.hyprland && Christmas.windows && Christmas.enabled
        function onActiveToplevelChanged() {
            if (!Hyprland.activeToplevel || !Christmas.allow("window", 420)) return;
            if (!query.running) query.running = true;
        }
    }
    Process {
        id: query
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    if (!w || !w.at || !w.size || w.fullscreen > 0 || w.size[0] < 80 || w.size[1] < 60) return;
                    host.target = { x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1] };
                    host.windowSerial++;
                } catch (e) {}
            }
        }
    }

    Variants {
        model: Christmas.present ? Quickshell.screens : []
        PanelWindow {
            id: layer
            required property var modelData
            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            mask: Region {}
            WlrLayershell.namespace: "qs-addon-christmas"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            visible: lightsOn.playing || wrap.playing
            readonly property var monitor: host.hyprland ? Hyprland.monitorFor(screen) : null
            readonly property real originX: monitor ? monitor.x : screen.x
            readonly property real originY: monitor ? monitor.y : screen.y

            ChristmasIntro { id: lightsOn; anchors.fill: parent }
            ChristmasWindowLights {
                id: wrap
                anchors.fill: parent
                Connections {
                    target: host
                    function onWindowSerialChanged() {
                        const t = host.target;
                        if (!t) return;
                        const x = t.x - layer.originX, y = t.y - layer.originY;
                        // only the screen holding the window's centre plays it
                        if (x + t.w / 2 < 0 || y + t.h / 2 < 0 || x + t.w / 2 > layer.width || y + t.h / 2 > layer.height) return;
                        wrap.play(Qt.rect(x, y, t.w, t.h));
                    }
                }
            }
        }
    }
}
