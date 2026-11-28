import QtQuick
import "../"

// The launcher decorates itself as you write: every character hangs a bauble under the panel (a star for a space),
// and each keystroke sets the row swinging. Erasing drops the last one, which bursts into gold. When the results
// collapse, the baubles jolt and stars spill from both corners. On a bottom launcher they hang above it instead.
// Sits in a window-sized layer and never takes input.
Item {
    id: tree
    enabled: false
    property rect panelRect
    property string query: ""
    property real resultsHeight: 0      // the height the launcher is heading to
    property bool above: false
    readonly property real unit: Scaler.s(1)
    readonly property real gap: unit * 29
    readonly property real edge: above ? panelRect.y : panelRect.y + panelRect.height
    readonly property real middle: panelRect.x + panelRect.width / 2
    readonly property int room: Math.max(1, Math.floor((panelRect.width - unit * 30) / gap))

    ListModel { id: hung }      // { space: bool }
    signal nudge(real force)

    function sync(): void {
        const wanted = Math.min(query.length, room);
        while (hung.count > wanted) {
            if (Christmas.motion) drop(hung.count - 1);
            hung.remove(hung.count - 1);
        }
        while (hung.count < wanted) hung.append({ space: query.charAt(hung.count) === " " });
        for (let i = 0; i < wanted; i++) hung.setProperty(i, "space", query.charAt(i) === " ");
        nudge(1);
    }
    onQueryChanged: sync()
    onRoomChanged: sync()
    Component.onCompleted: sync()

    function place(index: int, count: int): real { return middle + (index - (count - 1) / 2) * gap; }
    function drop(index: int): void {
        for (let i = 0; i < fallers.count; i++) {
            const ball = fallers.itemAt(i);
            if (ball && !ball.busy) { ball.fall(place(index, hung.count), index); return; }
        }
    }

    property real lastHeight: 0
    onResultsHeightChanged: {
        const shrunk = lastHeight - resultsHeight > unit * 20;
        lastHeight = resultsHeight;
        if (shrunk && Christmas.allow("collapse", 350)) {
            nudge(2.4);
            left.play(); right.play();
        }
    }

    component Ball: Item {
        id: ball
        property color tint: Christmas.cranberry
        property bool star: false
        property real size: tree.unit * 17
        Rectangle {
            visible: !ball.star
            x: -width / 2; y: -ball.size / 2 - height * 0.6
            width: ball.size * 0.4; height: ball.size * 0.3; radius: tree.unit
            color: Christmas.gold
        }
        Rectangle {
            visible: !ball.star
            x: -width / 2; y: -height / 2
            width: ball.size; height: width; radius: width / 2
            border.width: tree.unit * 0.8; border.color: Qt.alpha(Christmas.paleGold, 0.7)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(ball.tint, 1.4) }
                GradientStop { position: 1; color: Qt.darker(ball.tint, 1.7) }
            }
            Rectangle {
                x: parent.width * 0.22; y: parent.height * 0.18
                width: parent.width * 0.26; height: width; radius: width / 2
                color: Qt.alpha("white", 0.75)
            }
        }
        Text {
            visible: ball.star
            anchors.centerIn: parent
            text: "★"; color: Christmas.gold
            style: Text.Outline; styleColor: Christmas.deepRed
            font.pixelSize: ball.size * 1.25
        }
    }

    Repeater {
        model: hung
        Item {
            id: ornament
            required property int index
            required property bool space
            readonly property real drop: tree.unit * [15, 25, 19, 30][index % 4]
            property real swing: 0
            property real born: Christmas.motion ? 0 : 1
            x: tree.place(index, hung.count)
            y: tree.edge
            rotation: swing * (tree.above ? -1 : 1)
            Behavior on x { enabled: Christmas.motion; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            NumberAnimation on born { running: Christmas.motion; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            // a damped pendulum, the newest ones swinging hardest
            SequentialAnimation {
                id: pendulum
                property real reach: 10
                NumberAnimation { target: ornament; property: "swing"; to: pendulum.reach; duration: 130; easing.type: Easing.OutSine }
                NumberAnimation { target: ornament; property: "swing"; to: -pendulum.reach * 0.65; duration: 260; easing.type: Easing.InOutSine }
                NumberAnimation { target: ornament; property: "swing"; to: pendulum.reach * 0.35; duration: 260; easing.type: Easing.InOutSine }
                NumberAnimation { target: ornament; property: "swing"; to: 0; duration: 300; easing.type: Easing.InOutSine }
            }
            Connections {
                target: tree
                function onNudge(force: real) {
                    if (!Christmas.motion) return;
                    const near = Math.max(0.25, 1 - (hung.count - 1 - ornament.index) * 0.18);
                    pendulum.stop();
                    pendulum.reach = (ornament.index % 2 ? -9 : 9) * force * near;
                    pendulum.start();
                }
            }
            Component.onCompleted: if (Christmas.motion) { pendulum.reach = 16; pendulum.start(); }
            Rectangle {
                x: -width / 2; y: tree.above ? -height : 0
                width: tree.unit; height: ornament.drop * ornament.born
                color: Qt.alpha(Christmas.gold, 0.8)
            }
            Ball {
                y: (ornament.drop * ornament.born + tree.unit * 9) * (tree.above ? -1 : 1)
                scale: ornament.born
                tint: Christmas.bulb(ornament.index)
                star: ornament.space
            }
        }
    }

    // erased baubles: a few reused ones that fall, then burst
    Repeater {
        id: fallers
        model: 5
        Item {
            id: falling
            property real k: 0
            property real from: 0
            property int kind: 0
            readonly property bool busy: plunge.running || pop.active
            function fall(at: real, index: int): void { from = at; kind = index; plunge.restart(); }
            readonly property real start: tree.edge + (tree.above ? -1 : 1) * tree.unit * 32
            x: from + (kind % 2 ? 1 : -1) * k * tree.unit * 18
            y: start + k * k * tree.unit * 70
            NumberAnimation {
                id: plunge; target: falling; property: "k"; from: 0; to: 1; duration: 420
                onFinished: pop.active = true
            }
            Ball {
                visible: plunge.running
                tint: Christmas.bulb(falling.kind)
                rotation: falling.k * (falling.kind % 2 ? 200 : -200)
            }
            Loader {
                id: pop
                active: false
                x: -width / 2; y: -height / 2; width: tree.unit * 80; height: width
                sourceComponent: ChristmasBurst {
                    count: 7; confetti: true; duration: 520
                    onFinished: pop.active = false
                    Component.onCompleted: play()
                }
            }
        }
    }

    component Spill: Loader {
        id: spill
        width: tree.unit * 130; height: width
        y: tree.edge - height / 2
        active: false
        function play(): void { active = false; active = true; }
        sourceComponent: ChristmasBurst {
            count: 10
            onFinished: spill.active = false
            Component.onCompleted: play()
        }
    }
    Spill { id: left; x: tree.panelRect.x + tree.unit * 12 - width / 2 }
    Spill { id: right; x: tree.panelRect.x + tree.panelRect.width - tree.unit * 12 - width / 2 }
}
