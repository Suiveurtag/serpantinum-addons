import QtQuick
import Quickshell

// Clawd and the windows around him, without Hyprland: the world is fed through world.inject().
ShellRoot {
    id: shell
    AddonClawd { id: host }

    Timer {
        property int step: 0
        property int waits: 0
        property var p: host.pet
        property var w: host.world
        property string main: Quickshell.screens[0].name
        property real mark: 0
        property var seen: null
        interval: 100; running: true; repeat: true
        function expect(c, msg) { if (!c) { console.error("CLAWD_FAIL", step, msg, p ? JSON.stringify({ mode: p.mode, anim: p.animation, x: p.x, y: p.y, support: p.support, cover: p.cover, intent: p.intent, here: p.here }) : ""); Qt.exit(1); } }
        function wait(c, msg) { if (c) { waits = 0; return true; } if (++waits > 80) expect(false, "timeout: " + msg); step--; return false; }
        function win(id, x, y, ww, h) { return { address: id, at: [x, y], size: [ww, h], workspace: { id: 1 }, mapped: true, floating: true, focusHistoryID: 3 }; }
        function screen(name, x) { return { name, x, y: 0, width: 1280, height: 720 }; }
        function monitor(name, x) { return { name, x, y: 0, activeWorkspace: { id: 1 }, reserved: [0, 40, 0, 0] }; }
        function feed(clients) { expect(w.inject({ clients }), "inject works without Hyprland"); }
        // pick him up and let go with his centre at cx and his top at top
        function drop(cx, top) {
            p.press(Qt.LeftButton, p.x + 10, p.y + 10);
            p.move(cx - p.width / 2 + 10, top + 10);
            p.release(cx - p.width / 2 + 10, top + 10);
        }
        function hook(event) { Clawd.ingest(JSON.stringify({ agent: "claude", event, session_id: "w1", dir: "proj" })); }
        function cx() { return p.x + p.width / 2; }
        function seat() { return p.y + (Clawd.manifest.animations.perch && Clawd.manifest.animations.perch.grip ? Clawd.manifest.animations.perch.grip[1] : Clawd.manifest.frame.h) * Clawd.scale; }
        onTriggered: {
            switch (step++) {
            case 0:
                Config.setSetting("addonsV2Clawd", true);
                break;
            case 1:
                if (!wait(!!p && !!w && !!Clawd.manifest && p.mode === "idle", "spawned")) break;
                expect(Clawd.world && Clawd.follow, "world and follow on by default");
                expect(w.inject({ screens: [screen(main, 0)], monitors: [monitor(main, 0)], clients: [] }), "prime");
                expect(w.ledges.length === 1 && w.ledges[0].kind === "floor" && w.ledges[0].y === 720 && w.displays[0].top === 40, "one floor: " + JSON.stringify(w.ledges));
                break;
            case 2:
                expect(Math.abs(p.y + p.height - 720) < 1 && !p.support, "on the injected floor");
                feed([win("0xw1", 400, 300, 500, 300)]);
                expect(w.wins.length === 1 && w.ledges.some(l => l.id === "0xw1" && l.kind === "win" && l.y === 300), "floating window = ledge");
                drop(650, 100);
                expect(p.mode === "fall", "dropped above the window");
                break;
            case 3:
                if (!wait(p.mode === "perch", "lands, then perches on the window")) break;
                expect(p.support && p.support.kind === "win" && p.support.id === "0xw1" && p.riding, "support = the window: " + JSON.stringify(p.support));
                expect(Math.abs(seat() - 300) < 1 && Math.abs(cx() - 650) < 1, "seated on its top: " + p.y);
                expect(!Clawd.manifest.animations.perch || p.animation === "perch" || p.animation === "perch_look", "perch animation");
                feed([win("0xw1", 450, 320, 500, 300)]);
                break;
            case 4:
                expect(p.support && p.support.id === "0xw1" && Math.abs(seat() - 320) < 1 && Math.abs(cx() - 700) < 1, "rides the window: " + cx());
                feed([]);
                break;
            case 5:
                if (!wait(p.mode === "land" && p.animation === "oops" || p.mode === "fall", "window closed: falls")) break;
                expect(!p.support, "support lost");
                break;
            case 6:
                if (!wait(p.mode === "land" && p.animation === "oops", "oops on landing")) break;
                expect(Math.abs(p.y + p.height - 720) < 1 && !p.support, "on the floor");
                feed([win("0xw2", 300, 400, 300, 200)]);
                drop(450, 200);
                break;
            case 7: {
                if (!wait(p.mode === "perch" && p.support && p.support.id === "0xw2", "perched on the narrow window")) break;
                const lo = 300, hi = 600 - p.width;
                for (let i = 0; i < 40; i++) {
                    p.walk();
                    expect(p.target === null || p.target >= lo - 0.01 && p.target <= hi + 0.01, "walk target on the window top: " + p.target);
                    p.idle();
                }
                expect(p.mode === "perch", "still perched");
                expect(p.walkTo(hi, { kind: "edge" }), "walk to the end");
                break;
            }
            case 8:
                expect(p.x <= 600 - p.width + 0.01 && p.x >= 299.99, "never walks off the ledge: " + p.x);
                if (!wait(p.mode === "teeter", "teeters at the end")) break;
                expect(Math.abs(p.x - (600 - p.width)) < 0.01 && p.support && p.support.id === "0xw2", "at the end of the window top");
                expect(p.animation === (Clawd.manifest.animations.teeter ? "teeter" : "idle"), "teeter animation (or its fallback)");
                p.idle();
                Config.setSetting("addonsV2ClawdSummon", 1);
                break;
            case 9:
                if (!wait(p.mode === "idle" && !p.support, "respawned on the floor")) break;
                feed([win("0xw3", 700, 150, 400, 565)]);
                seen = p.peekSpot();
                expect(seen && seen.id === "0xw3" && seen.side === -1, "a window edge to peek from: " + JSON.stringify(seen));
                expect(p.peek(seen), "peek starts");
                break;
            case 10: {
                if (!wait(p.mode === "peek", "behind the window")) break;
                const o = host.overlays[0];
                expect(p.mirrored && p.cover && p.cover.x === 700 && Math.abs(p.x - (700 - p.width / 3)) < 0.01, "2/3 behind its left edge, facing out");
                expect(o.viewport.visible && o.viewport.width > 0 && o.viewport.width < o.frameBox.width - 10 && o.viewport.x === o.frameBox.x, "viewport clipped: " + o.viewport.width + " / " + o.frameBox.width);
                expect(o.hitBox.x === o.viewport.x && o.hitBox.y === o.viewport.y && o.hitBox.width === o.viewport.width && o.hitBox.height === o.viewport.height && o.hitBox.visible, "hitBox mirrors the viewport");
                feed([win("0xw3", 720, 150, 400, 565)]);
                break;
            }
            case 11: {
                const o = host.overlays[0];
                expect(!p.cover && (p.mode === "turn" || p.mode === "walk") && p.intent && p.intent.kind === "out", "window moved: steps out");
                expect(o.viewport.width === o.frameBox.width && o.hitBox.width === o.frameBox.width, "unclipped again");
                break;
            }
            case 12:
                if (!wait(p.mode === "idle", "out, then idle")) break;
                p.mind = ({ last: {}, recent: [] });
                feed([win("0xw3", 720, 150, 400, 565), win("0xw4", 100, 100, 300, 200)]);
                expect(p.mode === "react" && p.animation.startsWith("look") && p.mind.recent.length === 1, "a window opens: he looks at it");
                mark = p.mind.last.window_open;
                break;
            case 13:
                feed([win("0xw3", 720, 150, 400, 565), win("0xw4", 100, 100, 300, 200), win("0xw5", 900, 100, 200, 150)]);
                expect(p.mind.recent.length === 1 && p.mind.last.window_open === mark, "two opens within 1 s: one reaction");
                Config.setSetting("general.performance", true);
                break;
            case 14:
                if (!wait(p.mode === "idle", "reaction over")) break;
                expect(!p.explore(), "low motion: no exploring");
                for (let i = 0; i < 40; i++) {
                    p.think();
                    expect(["hop", "peek"].indexOf(p.mode) < 0 && !(p.intent && p.intent.kind === "peek"), "low motion: no hop, no peek");
                    p.idle();
                }
                Config.setSetting("general.performance", false);
                feed([win("0xw3", 720, 150, 400, 565), win("0xw6", Math.round(cx() - 150), 650, 300, 70)]);
                break;
            case 15:
                expect(w.ledges.some(l => l.id === "0xw6"), "a low window right above him");
                expect(p.explore(), "explores again");
                Config.setSetting("addonsV2ClawdWorld", false);
                break;
            case 16:
                if (!wait(w.wins.length === 0 && w.ledges.length === 1 && ["idle", "land", "fall"].indexOf(p.mode) >= 0 && !p.support, "world off: floor only")) break;
                expect(!p.explore(), "world off: no exploring");
                drop(900, 100);
                break;
            case 17:
                if (!wait(p.mode === "idle" || p.mode === "land", "plain floor behaviour: falls to the floor")) break;
                expect(!p.support && Math.abs(p.y + p.height - 720) < 1, "on the floor, not on the window under him");
                p.mind = ({ last: {}, recent: [] });
                feed([win("0xw3", 720, 150, 400, 565), win("0xw7", 100, 100, 300, 200)]);
                expect(p.mind.recent.length === 0, "world off: no window reactions");
                Config.setSetting("addonsV2ClawdWorld", true);
                break;
            case 18:
                if (!wait(w.wins.length === 2 && p.mode === "idle", "world back")) break;
                expect(p.mind.recent.length === 0, "windows already there are not news");
                // a second screen on his right, the cursor on it
                expect(w.inject({ screens: [screen(main, 0), screen("side", 1280)], monitors: [monitor(main, 0), monitor("side", 1280)], pointer: { x: 1800, y: 300 } }), "second screen");
                p.follow(); p.follow();
                expect(p.intent && p.intent.kind === "cross" && p.intent.to === "side", "cursor elsewhere twice: walks over: " + JSON.stringify(p.intent));
                break;
            case 19:
                if (!wait(Clawd.screenName === "side", "crossed to the next screen")) break;
                expect(Math.abs(p.y + p.height - 720) < 1, "walked over on the floor");
                break;
            case 20:
                if (!wait(p.mode === "idle", "arrived")) break;
                expect(p.x >= 1280 && Clawd.screenName === "side", "on the side screen");
                expect(w.inject({ screens: [screen(main, 0)], monitors: [monitor(main, 0)], pointer: null, clients: [] }), "side screen gone");
                break;
            case 21:
                if (!wait(Clawd.screenName === main && p.mode === "idle", "back on a screen that exists")) break;
                expect(w.refreshes > 10, "snapshots counted");
                // 5b: the bar's underside (no layers known: the display minus its margins), then hanging from it
                expect(w.inject({ clients: [], layers: {}, bar: { position: "top", height: 36, autohide: false } }), "bar and layers injected");
                expect(w.bars[main] && w.bars[main].y === 40 && w.bars[main].x === 4 && w.bars[main].w === 1272, "bar underside: " + JSON.stringify(w.bars));
                expect(p.hangBar(400), "hangs under the bar");
                break;
            case 22:
                expect(p.mode === "hang" && p.support && p.support.kind === "bar" && !p.grounded(), "hanging: " + p.mode);
                expect(Math.abs(p.contact().y - 40) < 0.01 && Math.abs(p.contact().x - 400) < 0.01, "hands on the bar's underside: " + JSON.stringify(p.contact()));
                expect(p.animation === "hang" && Clawd.manifest.animations.hang, "hang animation");
                feed([]);
                break;
            case 23:
                expect(p.mode === "hang" && Math.abs(p.contact().y - 40) < 0.01, "still hanging after a world update");
                // a bar popup opens (qs-master): he lets go, startled
                expect(w.inject({ layers: { [main]: { 2: [{ namespace: "qs-master", x: 0, y: 0, w: 1280, h: 720 }] } } }), "popup opens");
                expect(w.openLayers.length === 1, "open layers: " + JSON.stringify(w.openLayers));
                expect(p.mode === "drop" && p.dropStartled, "drops, startled: " + p.mode);
                break;
            case 24:
                if (!wait(p.mode === "fall" && p.animation === "startled" || p.mode === "land", "falls after the drop")) break;
                expect(!p.support, "no support while falling");
                break;
            case 25:
                if (!wait(p.mode === "land" || p.mode === "idle", "lands on the floor")) break;
                expect(Math.abs(p.y + p.height - 720) < 1, "back on the floor");
                p.idle();
                p.mind = ({ last: {}, recent: [] });
                // popup closes, then opens again while he stands: he looks up
                expect(w.inject({ layers: {} }), "popup closes");
                expect(w.inject({ layers: { [main]: { 2: [{ namespace: "qs-master", x: 0, y: 0, w: 1280, h: 720 }] } } }), "popup opens again");
                expect(p.mode === "react" && p.animation === "look_up" && p.mind.last.layer > 0, "looks up at the bar: " + p.mode + " " + p.animation);
                break;
            case 26:
                if (!wait(p.mode === "idle", "reaction over")) break;
                expect(w.inject({ layers: {} }), "popup closes");
                // 5b: a window whose bottom is near the floor has climbable sides
                feed([win("0xc1", 600, 500, 300, 200)]);
                expect(w.sides[main].length === 2 && w.sides[main][0].side === -1 && w.sides[main][0].x === 600 && w.sides[main][1].x === 900, "its sides: " + JSON.stringify(w.sides));
                seen = p.climbSpot();
                expect(seen && seen.id === "0xc1" && seen.side === -1, "the nearest side: " + JSON.stringify(seen));
                expect(p.climb(seen), "walks to the foot of it");
                break;
            case 27:
                if (!wait(p.mode === "climb" && p.support && p.support.kind === "side", "climbing")) break;
                expect(p.mirrored === false && p.animation === "climb" && Math.abs(p.contact().x - 600) < 0.01, "wall column on the edge: " + JSON.stringify(p.contact()));
                expect(!p.grounded(), "not standing");
                Config.setSetting("general.performance", true);
                break;
            case 28:
                Config.setSetting("general.performance", false);
                expect(p.mode === "climb", "keeps climbing in low motion");
                break;
            case 29:
                if (!wait(p.mode === "perch" && p.support && p.support.kind === "win" && p.support.id === "0xc1", "mantled onto the window top, perched")) break;
                expect(Math.abs(seat() - 500) < 1, "seated on its top: " + seat());
                // 5b: from the window top he jumps up to the bar (an arc, no teleport), then hangs from it
                expect(w.inject({ bar: { position: "top", height: 36, autohide: false } }) && p.hopBar(1100), "hops for the bar");
                expect(p.mode === "hop" && !p.support && p.hop && p.hop.kind === "bar", "in the air: " + p.mode);
                break;
            case 30:
                if (!wait(p.mode === "hang", "grabs the bar")) break;
                expect(p.support && p.support.kind === "bar" && Math.abs(p.contact().y - 40) < 0.01 && Math.abs(p.contact().x - 1100) < 30, "hands on the bar: " + JSON.stringify(p.contact()));
                hook("UserPromptSubmit");  // the agent gets busy while he hangs: drop -> land -> work
                expect(Clawd.activity === "work" && p.mode === "drop" && !p.dropStartled, "lets go: " + p.mode);
                break;
            case 31:
                if (!wait(p.mode === "fall" || p.mode === "land" || p.mode === "work", "drops")) break;
                expect(!p.support, "no support while falling");
                break;
            case 32:
                if (!wait(p.mode === "work", "lands, then works")) break;
                expect(Math.abs(p.y + p.height - 720) < 1 && !p.support && p.animation !== "land", "working on the floor: " + p.animation);
                hook("SessionEnd");
                break;
            case 33:
                if (!wait(Clawd.activity === "" && p.mode === "idle", "idle again")) break;
                feed([win("0xc1", 600, 500, 300, 200)]);
                seen = p.climbSpot();
                expect(seen && p.climb(seen), "climbs again");
                break;
            case 34:
                if (!wait(p.mode === "climb" && p.support && p.support.kind === "side", "climbing")) break;
                hook("UserPromptSubmit");  // busy while climbing: straight down, then work
                expect(p.mode === "fall" && !p.support, "lets go of the wall: " + p.mode);
                break;
            case 35:
                if (!wait(p.mode === "work", "lands, then works")) break;
                expect(Math.abs(p.y + p.height - 720) < 1, "on the floor");
                hook("SessionEnd");
                break;
            case 36:
                // 5d: a widget is a ledge (its layer inset by the 8 px aura); he hops onto it, the widget editor takes it away
                if (!wait(Clawd.activity === "" && p.mode === "idle", "idle again")) break;
                feed([]);
                expect(w.inject({ layers: { [main]: { 0: [{ namespace: "qs-widget-time-4", x: 500, y: 520, w: 316, h: 120 }, { namespace: "qs-widget-visualizer-1", x: 100, y: 520, w: 316, h: 120 }] } } }), "widget layers");
                expect(w.widgets.length === 1 && w.ledges.some(l => l.id === "qs-widget-time-4" && l.kind === "widget" && l.x === 508 && l.y === 528 && l.w === 300), "widget ledge: " + JSON.stringify(w.ledges));
                expect(p.widgetOn("clock") && p.widgetOn("clock").id === "qs-widget-time-4" && !p.widgetOn("music"), "the clock widget on his display");
                drop(560, 620);
                break;
            case 37:
                if (!wait(p.mode === "idle" && !p.support && Math.abs(p.y + p.height - 720) < 1, "on the floor beside it")) break;
                expect(p.visit(w.ledge("qs-widget-time-4")) && p.mode === "hop", "hops for the widget: " + p.mode);
                break;
            case 38:
                if (!wait(p.mode === "perch" && p.support && p.support.kind === "widget", "perched on the widget")) break;
                expect(Math.abs(seat() - 528) < 1, "seated on its top: " + seat());
                w.setRedact(true);
                break;
            case 39:
                expect(!w.ledges.some(l => l.kind === "widget") && !p.support, "widget editor: no widget ledge, he lost it: " + p.mode);
                break;
            case 40:
                if (!wait(p.mode === "idle" && !p.support, "back on the floor")) break;
                w.setRedact(false);
                p.mind = ({ last: {}, recent: [] });
                break;
            case 41:
                if (!wait(w.ledges.some(l => l.kind === "widget"), "ledge is back")) break;
                // the hourly chime: to the clock widget, then the chime itself (no clock widget on his display: nothing)
                expect(p.hourChime() && p.agenda && p.agenda.kind === "chime", "goes to the clock: " + JSON.stringify(p.agenda));
                break;
            case 42:
                if (!wait(p.animation === "chime" && p.support && p.support.kind === "widget", "chimes on the widget")) break;
                expect(p.agenda === null, "agenda done");
                p.idle();
                p.mind = ({ last: {}, recent: [] });
                expect(w.inject({ layers: {} }), "widgets gone");
                break;
            case 43:
                if (!wait(p.mode === "idle" && !p.support, "no widget: back on the floor")) break;
                expect(!p.hourChime() && p.mode === "idle" && !p.agenda, "no clock widget on his display: no chime");
                break;
            case 44:
                Config.setSetting("addonsV2Clawd", false);
                break;
            case 45:
                if (!wait(Clawd.instances === 0 && !host.world, "OFF unloads the world")) break;
                console.log("CLAWD_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
