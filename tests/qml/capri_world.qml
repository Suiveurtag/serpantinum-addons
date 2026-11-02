import QtQuick
import Quickshell

ShellRoot {
    id: shell
    AddonCapri { id: host }
    FloatingWindow { id: other; implicitWidth: 1000; implicitHeight: 800 }
    property var body: null
    property var flight: null
    property string home: ""
    property var win: ({ address: "seat", at: [200, 280], size: [700, 280], workspace: { id: 1 }, floating: true, focusHistoryID: 0 })
    property var lower: ({ address: "lower", at: [100, 530], size: [900, 180], workspace: { id: 1 }, floating: true, focusHistoryID: 1 })
    function expect(c, message) { if (!c) { console.error("CAPRI_FAIL", clock.step, message); Qt.exit(1); } }
    function setup() {
        const w = host.world;
        home = Capri.screenName;
        w.displays = [{ id: home, x: 0, y: 31, w: 1280, h: 720, floor: 690, workspace: 1 },
            { id: "other", x: -1000, y: 27, w: 1000, h: 800, floor: 800, workspace: 2 }];
        w.registerSurface("other", other);
        w.clients = [win, lower]; w.foreground = "seat"; w.sync();
        body = w.engine.capri;
        body.wander = false;
    }
    Component.onCompleted: Config.setSetting("addonsV2Capri", true)
    Timer {
        id: clock
        property int step: 0
        interval: 6500; running: true
        onTriggered: {
            const w = host.world;
            switch (step++) {
            case 0:
                shell.setup();
                body.onThrown = null; body.onGaze = null; // dialogue has its own Brain fixture
                w.pc = null; w.ingest({ t: "pc", game: "Startup game" });
                shell.expect(w.game === "Startup game", "foreground game survives engine initialization");
                w.attach(); w.game = "";
                shell.expect(body.view.floor === 690, "reserved bottom establishes floor");
                shell.expect(Capri.act("sit", "") === "ok", "foreground window is sittable");
                interval = 1800; break;
            case 1:
                shell.expect(body.stance === "sit" && body.perch.id === "seat", "perched on foreground");
                win.at = [240, 300]; w.clients = [win, lower]; w.sync();
                shell.expect(body.pos.x === win.at[0] + body.perch.dx && Math.abs(body.pos.y - 383.6) < 0.01, "ride window in local coordinates");
                w.clients = [lower]; w.sync();
                shell.expect(body.stance === "fall", "window closed: fall");
                interval = 1200; break;
            case 2:
                shell.expect(body.stance === "sit" && body.perch.id === "lower", "land on lower ledge");
                shell.expect(Capri.act("possess", "") === "ok", "possession starts");
                interval = 1400; break;
            case 3:
                shell.expect(body.p.alpha === 0 && w.engine.fx.items.some(i => i.type === "possess"), "possession draws on window");
                interval = 3000; break;
            case 4:
                shell.expect(!body.hidden && !body.busy && body.stance === "sit", "possession returns");
                w.clients = [Object.assign({}, lower, { fullscreen: 1 })]; w.sync();
                shell.expect(body.stance === "fall", "maximized ledge: fall");
                interval = 1300; break;
            case 5:
                shell.expect(body.stance === "stand" && body.pos.y === 684, "land above reserved bottom");
                w.clients = []; w.sync();
                body.pos = { x: 180, y: 520 };
                body.throwHer(-2600, -500); flight = body.flight;
                interval = 500; break;
            case 6:
                shell.expect(Capri.screenName === "other", "throw crosses touching edge");
                shell.expect(w.engine.capri === body && body.flight === flight, "flight and engine preserved");
                shell.expect(body.view.w === 1000 && body.view.h === 800, "new monitor view");
                interval = 6500; break;
            case 7:
                shell.expect(body.free, "throw settles on other screen");
                w.pointer = { x: 700, y: 500 }; w.follow(); w.follow();
                interval = 2200; break;
            case 8:
                shell.expect(Capri.screenName === home, "two checks: leap back to pointer screen");
                interval = 3800; break;
            case 9:
                shell.expect(body.free, "leap lands on feet");
                body.peek("top"); interval = 1000; break;
            case 10:
                shell.expect(body.stance === "peek" && body.upside, "top peek upside down");
                body.unpeek(); interval = 1700; break;
            case 11:
                shell.expect(!body.busy && !body.hidden && body.stance === "stand", "unpeek returns");
                w.displays = [w.displays[0], Object.assign({}, w.displays[1], { x: -1200 })];
                w.goToScreen("other", true); interval = 1600; break;
            case 12:
                shell.expect(Capri.screenName === "other" && w.engine.capri === body && !body.hidden, "jump across gap preserves engine");
                Config.setSetting("general.performance", true);
                w.pointer = { x: 700, y: 500 }; w.follow(); w.follow();
                interval = 300; break;
            case 13:
                shell.expect(Capri.screenName === "other", "performance disables following");
                body.setMode("alert");
                w.pc.hotSince = Date.now() - 16000; SysData.cpu = 90; w.samplePc();
                shell.expect(!w.pc.hot, "alert mode suppresses PC reactions");
                body.setMode("idle"); w.samplePc();
                shell.expect(w.pc.hot, "PC mode guard reads current body mode");
                shell.expect(SysData.subscribers === 1, "CPU subscribed once");
                Config.setSetting("addonsV2Capri", false);
                interval = 200; break;
            case 14:
                shell.expect(SysData.subscribers === 0, "OFF releases system subscription");
                console.log("CAPRI_PASS"); Qt.quit(); return;
            }
            start();
        }
    }
}
