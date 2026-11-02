import QtQuick
import "../"

// The cloud over his head while he dreams, drawn as pixel art on a grid of whole pixels (no smoothing, no rotation):
// a soft lavender cloud with a star and a moon (a dream), or a jagged dark cloud with glowing red eyes (a nightmare).
// A click opens it (pet.openDream): the scene plays over his sleep. It fades out on its own after 30 s.
Item {
    id: cloud
    required property var pet
    required property Item anchor
    readonly property bool nightmare: !!pet.dream && !!pet.dream.entry && pet.dream.entry.kind === "nightmare"
    readonly property bool reduced: Clawd.lowMotion
    readonly property int px: Math.max(2, Math.round(Scaler.s(2.5)))   // one art pixel, always a whole number of screen pixels
    property real now: Date.now()
    readonly property real age: (now - pet.dreamAt) / 1000
    readonly property real life: Math.min(1, age / 0.3, (30 - age) / 3)
    readonly property int phase: Math.floor(now / 90)                  // nightmare flicker steps
    // o outline, w fill, h highlight, s shade, p star and moon, E red eyes. Rows are 24 wide.
    readonly property var dreamArt: ["........................", "...........oooooo.......", "..........owwwwwwo......", ".....ooooowwwwwwwwo.....", "....owhwwwwwwwwwwwo.....", "...owhwwwwwwwwwwwwwo....", "...owwwwwwwwwwwwwwwwoo..", "...ohwwwwwwwwwwpppwwwwo.", "...oswwwwpwwwwppwwwwwwo.", "...osswwpppwwwppwwwwwwo.", "....osswwpwwwwppwwwwwso.", ".....oswwwwwwwwpppwwsso.", "......oswwwwwswwwwwsso..", "......ossssssssswssso...", ".......osssssossssso....", "........ooooo.oosoo.....", ".....oo.........o.......", "....owwo................", ".o..owso................", "owo..oo.................", ".o......................", "........................"]
    readonly property var nightArt: ["........................", "...........oo...........", "..........owwo..........", ".........owwwwo.........", "......ooowwwwwwo........", ".....owwwwwwwwwwoo......", "....owwwwwwwwwwwwwo.....", "...owwwwwwwwwwwwwwwo....", "..owwwwwwwwwwwwwwwwwo...", ".oswwwwwwwwwwwwwwwwwwo..", ".osswwwwEEEwwwwEEEwwsso.", "..osswwwEEEEwwEEEEwsso..", "...osswwwwEEwwEEwwsso...", "....ossswwwwswwwwsso....", ".....ossswwssswwsso.....", "......oosEsEoEsEso......", "........osso.osso.......", "......oo.oo...oo........", "..o..owwo...............", ".owo..oo................", "..o.....................", "........................"]
    readonly property var art: nightmare ? nightArt : dreamArt
    readonly property var pal: nightmare
        ? { o: "#8B0F16", w: "#1d080c", s: "#120508", h: "#1d080c", p: "#1d080c", E: "#FF2A2A" }
        : { o: "#B9A2F5", w: "#F7F0FF", s: "#DCCDFA", h: "#FFFFFF", p: "#9B7BEA", E: "#9B7BEA" }
    // each row as runs of one colour: [x, y, length, char]; far fewer items than one per pixel
    readonly property var runs: {
        const out = [];
        for (let y = 0; y < art.length; y++) {
            const r = art[y];
            let x = 0;
            while (x < r.length) {
                const c = r[x];
                if (c === ".") { x++; continue; }
                let n = 1;
                while (x + n < r.length && r[x + n] === c) n++;
                out.push([x, y, n, c]);
                x += n;
            }
        }
        return out;
    }
    // own x/y (not anchors): the overlay mask Region only follows its item's own geometry
    x: Math.round(Math.max(0, Math.min((parent ? parent.width : 0) - width, anchor.x + anchor.width * 0.62)))
    y: Math.round(Math.max(0, anchor.y + anchor.height * 0.35 - height))
    width: 24 * px
    height: 22 * px

    Timer { interval: 33; repeat: true; running: cloud.visible; triggeredOnStart: true; onTriggered: cloud.now = Date.now() }

    Item {
        id: body
        anchors.fill: parent
        opacity: Math.max(0, cloud.life) * (hover.containsMouse ? 1 : 0.94)
        // dream: a slow bob in whole-pixel steps; nightmare: a nervous one-pixel shake
        readonly property int bob: cloud.reduced ? 0 : cloud.nightmare ? (cloud.phase % 2 ? 1 : -1) * cloud.px
                                   : Math.round(Math.sin(cloud.now / 450)) * cloud.px
        x: cloud.nightmare ? bob : 0
        y: (cloud.nightmare ? 0 : bob) - (hover.containsMouse ? cloud.px : 0)

        Repeater {
            model: cloud.runs
            delegate: Rectangle {
                required property var modelData
                x: modelData[0] * cloud.px; y: modelData[1] * cloud.px
                width: modelData[2] * cloud.px; height: cloud.px
                antialiasing: false
                color: {
                    const c = modelData[3];
                    if (!cloud.nightmare || cloud.reduced) return cloud.pal[c];
                    if (c === "o") return (cloud.phase + modelData[0] + modelData[1]) % 5 ? cloud.pal.o : "#FF2A2A";
                    if (c === "E") return cloud.phase % 4 ? "#FF2A2A" : "#FFD0D0";
                    return cloud.pal[c];
                }
            }
        }
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cloud.pet.openDream()
    }
}
