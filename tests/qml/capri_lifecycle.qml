import QtQuick
import Quickshell

ShellRoot {
    id: shell
    AddonCapri { id: host }

    Timer {
        property int step: 0
        interval: 200; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CAPRI_FAIL", step, msg); Qt.exit(1); } }
        onTriggered: {
            switch (step++) {
            case 0:
                expect(!Capri.enabled && Capri.instances === 0 && !host.sidecarRunning, "OFF must load nothing");
                Capri.ingest('{"t":"event","evt":{"hook_event_name":"Stop"}}');
                expect(Capri.events === 1, "sidecar event line accepted");
                Capri.ingest('not json'); Capri.ingest('{"t":"event","evt":{"hook_event_name":"rm -rf"}}'); Capri.ingest('{"t":"event","evt":[]}');
                expect(Capri.events === 1, "invalid events rejected");
                Config.setSetting("addonsV2Capri", true);
                break;
            case 1: case 2: case 3: case 4: case 5:
                if (!host.sidecarRunning || Capri.instances === 0) break;   // wait for node and the window
                step = 6;
                break;
            case 6:
                expect(Capri.instances === Quickshell.screens.length, "one pet per screen, got " + Capri.instances);
                expect(host.sidecarRunning, "sidecar running while ON");
                expect(Capri.animationEnabled, "animation on");
                Config.setSetting("general.performance", true);
                break;
            case 7:
                expect(!Capri.animationEnabled, "performance mode stops animation");
                Config.setSetting("general.performance", false);
                Config.setSetting("addonsV2Capri", false);
                break;
            case 8:
                expect(Capri.instances === 0 && !host.sidecarRunning, "OFF unloads windows and sidecar");
                Config.setSetting("addonsV2Capri", true);
                break;
            case 9:
                expect(Capri.instances === Quickshell.screens.length, "ON again reloads");
                console.log("CAPRI_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
