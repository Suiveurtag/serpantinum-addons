import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Direct ShellRoot child: the IPC target must exist while Clawd is OFF.
Scope {
    readonly property var pet: loader.item ? loader.item.pet : null
    readonly property var overlays: loader.item ? loader.item.overlays : []
    readonly property var world: loader.item ? loader.item.world : null
    readonly property var blasts: loader.item ? loader.item.blasts : []
    readonly property var events: loader.item ? loader.item.events : null

    IpcHandler {
        target: "clawd"
        function toggle(): void { Config.setSetting("addonsV2Clawd", !Clawd.enabled); }
        function appear(): void { Config.setSetting("addonsV2Clawd", true); }
        function hide(): void { Config.setSetting("addonsV2Clawd", false); }
        function play(name: string): string { return Clawd.play(name); }
        // Debug: what Clawd knows about the agent sessions and the windows around him right now.
        function state(): string {
            return JSON.stringify({ activity: Clawd.activity, mode: pet ? pet.mode : "off", animation: pet ? pet.animation : "", support: pet ? pet.support : null, cover: pet ? pet.cover : null,
                world: world ? { wins: world.wins.length, ledges: world.ledges.map(l => ({ id: l.id, kind: l.kind, x: Math.round(l.x), y: Math.round(l.y), w: Math.round(l.w) })), refreshes: world.refreshes } : null,
                sessions: Clawd.sessions, bubble: Clawd.bubble });
        }
    }

    // Hook ingress stays outside the Loader: Clawd OFF still tracks sessions. One JSON object per line.
    SocketServer {
        id: ingress
        active: false
        path: Caching.runDir + "/clawd.sock"
        handler: Socket { parser: SplitParser { onRead: line => Clawd.ingest(line) } }
    }
    // On reload the old shell generation unlinks clawd.sock when it closes, after the new one bound it:
    // listen only once the old generation is gone.
    Timer { interval: 1500; running: !!Caching.runDir; onTriggered: ingress.active = true }

    // OFF destroys every window, timer and Hyprland socket.
    Loader {
        id: loader
        active: Clawd.enabled
        sourceComponent: Scope {
            readonly property alias pet: body
            readonly property alias overlays: views.instances
            readonly property alias world: around
            readonly property alias blasts: singular.instances
            readonly property alias events: shell
            ClawdBrain { id: brainHost }
            ClawdWorld { id: around; pet: body }
            ClawdPet { id: body; world: around }
            ClawdEvents { id: shell; pet: body }
            Variants {
                id: views
                model: Quickshell.screens
                delegate: ClawdOverlay { required property var modelData; screen: modelData; pet: body; brain: brainHost }
            }
            // above everything only while he goes singular
            Variants {
                id: singular
                model: Quickshell.screens
                delegate: ClawdSingularity { required property var modelData; screen: modelData; pet: body }
            }
        }
    }
}
