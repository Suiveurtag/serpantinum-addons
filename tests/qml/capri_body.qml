import QtQuick
import Quickshell

// Her body and moves, end to end through the IPC "act" command: every step must leave her in
// the expected state, and nothing in js/ may throw (checked by the test on the log).
ShellRoot {
    id: shell
    AddonCapri { id: addon }
    Component.onCompleted: Config.setSetting("addonsV2Capri", true)

    function state() { return JSON.parse(Capri.act("state", "")); }
    // [wait ms before, command, arg, check on the state after]
    readonly property var steps: [
        [6500, "state", "", s => !s.busy && s.stance === "stand" && !s.hidden],              // the intro is over
        [0, "victory", "", s => s.act === "victory"],
        [2600, "state", "", s => s.act === null],
        [0, "teleport", "stage", s => s.busy],
        [1600, "state", "", s => !s.busy && !s.hidden],
        [0, "gaze", "big", s => s.act === "uplink"],
        [9000, "state", "", s => s.act === null && s.fx === 0],
        [0, "throw", "2600,-900", s => s.stance === "fly"],
        [5500, "state", "", s => s.stance === "stand" && !s.busy && s.y === Quickshell.screens[0].height - 6],               // back on the floor (720 - 6)
        [0, "hurt", "", s => s.act === "flinch"],
        [700, "doze", "", s => s.busy],
        [1200, "state", "", s => s.dormant && s.hidden],
        [0, "rouse", "", s => !s.dormant],
        [1500, "state", "", s => !s.hidden && !s.busy],
        [0, "stow", "", s => true],
        [1500, "state", "", s => s.stowed && s.hidden],
        [0, "unstow", "", s => !s.stowed],
        [1500, "state", "", s => !s.hidden && s.x < 300],                                        // next to her chip, bottom left
        [0, "nonsense", "", s => true],
    ]

    Timer {
        property int i: 0
        property bool isolated: false
        interval: 50; running: true
        onTriggered: {
            // Dialogue is covered in capri_brain.qml; keep this fixture on the body and its own FX.
            if (!isolated && addon.world && addon.world.engine.capri && addon.world.engine.brain.runtime) {
                const c = addon.world.engine.capri;
                addon.world.engine.brain.runtime.panel.say = () => false;
                c.onGaze = null; c.onThrown = null; c.wander = false; c.possessWindows = false;
                c.nextMove = Infinity; c.nextGaze = Infinity; c.nextTwitch = Infinity; c.nextShed = Infinity; isolated = true;
            }
            if (!isolated) { start(); return; } // her brain comes up a moment after her body
            if (i > 0) {
                const step = shell.steps[i - 1];
                const answer = Capri.act(step[1], step[2]);
                const after = shell.state();
                if (step[1] === "nonsense" ? answer !== "unknown" : !step[3](after)) {
                    console.error("CAPRI_FAIL", i - 1, step[1], answer, JSON.stringify(after));
                    Qt.exit(1);
                    return;
                }
            }
            if (i >= shell.steps.length) { Config.setSetting("addonsV2CapriScale",0.8);
                if (addon.world.engine.capri.scale !== 0.8) { console.error("CAPRI_FAIL","live config scale");Qt.exit(1);return; }
                console.log("CAPRI_PASS"); Qt.quit(); return; }
            interval = Math.max(50, shell.steps[i][0]);
            i++;
            start();
        }
    }
}
