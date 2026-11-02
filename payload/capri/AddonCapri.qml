import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Direct ShellRoot child: the IPC target must exist while Capri is OFF.
Scope {
    id: root
    readonly property bool sidecarRunning: loader.status === Loader.Ready && loader.item ? loader.item.sidecarRunning : false

    readonly property var world: loader.status === Loader.Ready && loader.item ? loader.item.environment : null

    IpcHandler {
        target: "capri"
        function setEnabled(value: bool): void { Config.setSetting("addonsV2Capri", value); }
        function toggle(): void { Config.setSetting("addonsV2Capri", !Capri.enabled); }
        function event(json: string): string {
            let evt = null;
            try { evt = JSON.parse(json); } catch (error) {}
            return Capri.enabled && Capri.accept(evt) ? "ok" : "rejected";
        }
        function act(name: string, arg: string): string { return Capri.enabled ? Capri.act(name, arg) : "off"; }
        function status(): string {
            return JSON.stringify({ enabled: Capri.enabled, animationEnabled: Capri.animationEnabled, instances: Capri.instances,
                sidecar: root.sidecarRunning, events: Capri.events, lastEvent: Capri.lastEvent ? Capri.lastEvent.hook_event_name : null });
        }
    }

    // OFF destroys every window, timer and the sidecar process.
    Loader {
        id: loader
        active: Capri.enabled
        sourceComponent: Scope {
            id: host
            readonly property bool sidecarRunning: sidecar.running
            readonly property alias environment: environment
            property int restarts: 0

            Process {
                id: sidecar
                running: true
                command: ["node", Capri.scripts + "/sidecar.js"]
                stdinEnabled: true
                stdout: SplitParser { onRead: line => {
                    Capri.ingest(line);
                    try { body.brain.ingest(JSON.parse(line)); } catch (error) { console.warn("Capri Brain:", error); }
                    try { environment.ingest(JSON.parse(line)); } catch (error) {}
                } }
                onRunningChanged: if (running) { environment.sentForeground = ""; environment.sendForeground(); }
                stderr: SplitParser { onRead: line => console.warn("Capri sidecar:", line) }
                onExited: code => {
                    if (host.restarts++ < 3) retry.start();
                    else Quickshell.execDetached(["notify-send", "-a", "Serpantinum", "Capri", "The Capri helper keeps stopping (exit " + code + "). Is node installed?"]);
                }
            }
            Timer { id: retry; interval: 5000; onTriggered: sidecar.running = true }

            CapriWorld { id: environment; engine: body; onSend: message => { if (sidecar.running) sidecar.write(JSON.stringify(message) + "\n"); } }
            CapriEngine {
                id: body
                world: environment
                Connections { target: body.brain; function onSend(message) { if(sidecar.running)sidecar.write(JSON.stringify(message) + "\n"); } }
                parent: environment.surface ? environment.surface.contentItem : null
                width: environment.here ? environment.here.w : 0
                height: environment.here ? environment.here.h : 0
            }
            Variants {
                model: Quickshell.screens
                delegate: CapriOverlay { required property var modelData; screen: modelData; world: environment }
            }
        }
    }
}
