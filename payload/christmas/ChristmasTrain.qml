import QtQuick
import "../"

// A toy train on the day stream under the clock. It rides the stream's own time scale: the engine's nose stays under
// the "now" line, so it travels from one event to the next, and each event's start is a signal post along the track
// that turns from red to green as the engine reaches it. It pulls one present for each event still ahead (six at most)
// behind a wagon carrying the tree. It steams in when the panel opens; pressing the engine blows the whistle.
// Picking another day drives it off one side and brings that day's train in from the other. Before the first event it
// waits at the station, loading its presents under a departure board; on a day without events it sleeps beside a
// snowman and a lit tree.
Item {
    id: train
    property real timelineStart: 0          // where the stream's time axis begins, and how long it is
    property real timelineWidth: width
    readonly property real unit: Scaler.s(1)
    readonly property bool linked: typeof GCal !== "undefined" && GCal.available

    // the same events and time span as the stream above (GCalDayStream.plan)
    readonly property var plan: {
        const out = { items: [], t0: 0, t1: 0 };
        if (!linked) return out;
        const d = new Date(shownKey);
        const d0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const d1 = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
        for (const e of GCal.eventsOn(d)) {
            if (e.allDay || e.rsvp === "declined") continue;
            const a = Math.max(e.start, d0);
            let b = Math.min(e.end, d1);
            if (b <= a) b = Math.min(d1, a + 15 * 60000);
            out.items.push({ a: a, b: b });
        }
        if (!out.items.length) return out;
        out.t0 = Math.min(...out.items.map(it => it.a));
        out.t1 = Math.max(...out.items.map(it => it.b));
        if (out.t1 - out.t0 < 3 * 3600000) out.t1 = out.t0 + 3 * 3600000;
        return out;
    }
    readonly property bool scheduled: plan.items.length > 0
    readonly property real now: linked ? GCal.now : DateTime.now.getTime()
    function at(time: real): real { return timelineStart + (time - plan.t0) / Math.max(1, plan.t1 - plan.t0) * timelineWidth; }
    readonly property int presents: Math.min(6, plan.items.filter(it => it.b > train.now).length)

    // The day on show lags behind the picked one while the trains change over.
    readonly property real wantedKey: {
        const d = linked ? GCal.selectedDay || GCal.today : DateTime.now;
        return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    }
    property real shownKey: 0
    property real shift: 0                  // how far the train is from its place while changing over
    property real posts: 1                  // the signal posts, 0 down .. 1 up
    property real load: 1                   // the presents settling into their wagons
    property int direction: 1
    onWantedKeyChanged: {
        if (shownKey === 0 || wantedKey === shownKey) return;
        direction = wantedKey > shownKey ? 1 : -1;
        if (!Christmas.motion) { shownKey = wantedKey; return; }
        journey.stop(); arrive = 1;
        changeover.restart();
    }
    // later days: out to the right and in from the left; earlier days: it backs out and returns from the right
    function offstage(side: int): real { return side > 0 ? width - station + length + unit * 20 : -station - unit * 60; }
    SequentialAnimation {
        id: changeover
        ParallelAnimation {
            NumberAnimation { target: train; property: "posts"; to: 0; duration: 260; easing.type: Easing.InBack }
            NumberAnimation { target: train; property: "shift"; to: train.offstage(train.direction); duration: 520; easing.type: Easing.InCubic }
        }
        ScriptAction { script: {
            train.shownKey = train.wantedKey;
            train.shift = train.offstage(-train.direction);
            train.load = train.waiting ? 0 : 1;
        } }
        ParallelAnimation {
            NumberAnimation { target: train; property: "shift"; to: 0; duration: 900; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 220 }
                NumberAnimation { target: train; property: "posts"; to: 1; duration: 700; easing.type: Easing.Linear }
            }
        }
        ScriptAction { script: train.settle() }
    }
    // arrived: presents are loaded while it waits, otherwise they give a hop
    function settle(): void {
        if (waiting) loading.restart();
        else if (presents > 0) jump.restart();
    }
    NumberAnimation { id: loading; target: train; property: "load"; from: 0; to: 1; duration: 1400 }

    readonly property bool waiting: scheduled && now < plan.t0
    readonly property bool dayOff: linked && !scheduled
    property bool awake: false
    Timer { id: doze; interval: 3500; onTriggered: train.awake = false }

    // Where the engine's nose belongs: on the stream's scale, or across the whole day when nothing is planned.
    // It never leaves the strip: before the first event it waits at the start, after the last it rests at the end.
    property real station: {
        const date = DateTime.now;
        const spot = scheduled ? at(now) : (date.getHours() * 60 + date.getMinutes()) / 1440 * width;
        // parked, the whole train is in sight
        if (waiting) return length + unit * 4;
        if (dayOff) return Math.max(length + unit * 4, width * 0.24);
        return Math.max(engine + unit * 4, Math.min(width - unit * 4, spot));
    }
    readonly property real length: engine + (presents + 1) * wagon
    Behavior on station { enabled: Christmas.motion && !changeover.running; NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }

    readonly property real wagon: unit * 34
    readonly property real engine: unit * 46
    property real arrive: Christmas.motion ? 0 : 1
    // the engine's nose
    readonly property real head: station * arrive + shift
    readonly property bool rolling: journey.running || changeover.running
    property real travelled: head           // turns the wheels
    property real hop: 0
    NumberAnimation {
        id: journey; target: train; property: "arrive"; from: 0; to: 1; duration: 3600; easing.type: Easing.OutCubic
        onFinished: train.settle()
    }
    Component.onCompleted: {
        shownKey = wantedKey;
        if (!Christmas.motion) return;
        load = waiting ? 0 : 1;
        journey.start();
    }

    function whistle(): void {
        awake = true; doze.restart();
        if (!Christmas.motion) return;
        jump.restart();
        for (let i = 0; i < 4; i++) puff(1.5);
    }
    function puff(size: real): void {
        for (let i = 0; i < steam.count; i++) {
            const cloud = steam.itemAt(i);
            if (cloud && !cloud.busy) { cloud.blow(size); return; }
        }
    }
    SequentialAnimation {
        id: jump
        NumberAnimation { target: train; property: "hop"; to: 1; duration: 700; easing.type: Easing.Linear }
        PropertyAction { target: train; property: "hop"; value: 0 }
    }
    Timer {
        interval: train.rolling ? 220 : 1300; repeat: true
        running: train.visible && Christmas.motion && (train.rolling || !train.dayOff || train.awake)
        onTriggered: train.puff(train.rolling ? 1 : 0.75)
    }

    // ── the track ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.bottom: parent.bottom; anchors.bottomMargin: train.unit * 3
        width: parent.width; height: train.unit * 1.5
        color: Qt.alpha(Christmas.gold, 0.45)
    }
    Repeater {
        model: Math.ceil(train.width / (train.unit * 14))
        Rectangle {
            required property int index
            x: index * train.unit * 14 + train.unit * 4; y: train.height - train.unit * 3
            width: train.unit * 5; height: train.unit * 2.5
            color: Qt.alpha("#8a5a36", 0.7)
        }
    }

    // ── a signal post at each event's start ──────────────────────────────────
    Repeater {
        model: train.plan.items
        Item {
            id: post
            required property var modelData
            required property int index
            readonly property real up: Math.max(0, Math.min(1, train.posts * 2 - index / Math.max(1, train.plan.items.length)))
            // ease-out-back
            scale: up <= 0 ? 0 : 1 + 2.7 * Math.pow(up - 1, 3) + 1.7 * Math.pow(up - 1, 2)
            transformOrigin: Item.Bottom
            readonly property bool reached: train.now >= modelData.a
            x: train.at(modelData.a); y: train.height - train.unit * 24
            Rectangle { x: -train.unit * 0.75; width: train.unit * 1.5; height: train.unit * 21; color: Christmas.gold }
            Rectangle {
                x: -width / 2; y: -height / 2
                width: train.unit * 7; height: width; radius: width / 2
                color: post.reached ? "#38d873" : "#ff4538"
                Behavior on color { ColorAnimation { duration: 600 } }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 2.2; height: width; radius: width / 2
                    color: Qt.alpha(parent.color, 0.25)
                }
            }
        }
    }

    component Snow: Rectangle { radius: width / 2; height: width; color: "#f4f8fb"; anchors.horizontalCenter: parent.horizontalCenter }

    component Wheel: Rectangle {
        property real size: train.unit * 8
        width: size; height: size; radius: size / 2
        y: train.height - train.unit * 4.5 - size
        color: "#20242a"
        border.width: train.unit * 1.3; border.color: Christmas.gold
        rotation: train.travelled / (Math.PI * size) * 360
        Rectangle { anchors.centerIn: parent; width: parent.width * 0.62; height: train.unit; color: Christmas.paleGold }
    }

    // ── the wagons ───────────────────────────────────────────────────────────
    Repeater {
        model: train.presents + 1
        Item {
            id: car
            required property int index
            readonly property bool tree: index === train.presents      // the last one
            readonly property color tint: Christmas.bulb(index)
            readonly property real leap: {
                const k = Math.max(0, Math.min(1, train.hop * 2 - index * 0.12));
                return Math.sin(k * Math.PI) * train.unit * 11;
            }
            x: train.head - train.engine - (index + 1) * train.wagon
            width: train.wagon; height: train.height

            Rectangle {     // coupling
                x: parent.width - train.unit * 5; y: train.height - train.unit * 13
                width: train.unit * 6; height: train.unit * 1.5; color: Christmas.gold
            }
            Item {          // the present
                visible: !car.tree
                readonly property real settled: Math.max(0, Math.min(1, train.load * (train.presents + 1) - car.index))
                x: train.unit * 6; y: train.height - train.unit * 30 - car.leap - (1 - settled * settled) * train.unit * 26
                opacity: Math.min(1, settled * 3)
                width: train.unit * 18; height: train.unit * 15
                rotation: car.leap * (car.index % 2 ? 1.2 : -1.2)
                Rectangle { anchors.fill: parent; radius: train.unit * 2; color: car.tint }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: train.unit * 3; height: parent.height; color: Christmas.cream }
                ChristmasBow {
                    width: train.unit * 13; height: width * 0.8
                    anchors.horizontalCenter: parent.horizontalCenter; y: -height * 0.62
                    ribbon: Christmas.cream; shade: Christmas.gold; shine: "white"
                }
            }
            Item {          // the tree
                visible: car.tree
                x: train.unit * 5; y: train.height - train.unit * 40
                width: train.unit * 20; height: train.unit * 25
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        readonly property real side: train.unit * (7 + index * 3.2)
                        x: parent.width / 2 - side / 2; y: train.unit * (4 + index * 6.5) - side / 4
                        width: side; height: side; rotation: 45; radius: train.unit
                        color: index % 2 ? Christmas.holly : Christmas.pine
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: -train.unit * 7
                    text: "★"; color: Christmas.gold; font.pixelSize: train.unit * 11
                }
            }
            Rectangle {     // the bed
                x: train.unit * 2; y: train.height - train.unit * 16
                width: train.wagon - train.unit * 7; height: train.unit * 8; radius: train.unit * 2
                color: car.tree ? Christmas.deepRed : Christmas.holly
                border.width: train.unit; border.color: Qt.alpha(Christmas.gold, 0.8)
            }
            Wheel { x: train.unit * 4 }
            Wheel { x: train.wagon - train.unit * 17 }
        }
    }

    // ── the engine, facing right ─────────────────────────────────────────────
    Item {
        x: train.head - train.engine
        width: train.engine; height: train.height
        Rectangle {     // cab roof, cab and its lit window
            x: 0; y: train.height - train.unit * 36
            width: train.unit * 20; height: train.unit * 4; radius: train.unit * 2
            color: Christmas.gold
        }
        Rectangle {
            x: train.unit * 2; y: train.height - train.unit * 33
            width: train.unit * 16; height: train.unit * 25
            color: Christmas.cranberry
            Rectangle { x: train.unit * 4; y: train.unit * 4; width: train.unit * 8; height: train.unit * 8; radius: train.unit * 2; color: Christmas.paleGold }
        }
        Rectangle {     // boiler
            x: train.unit * 17; y: train.height - train.unit * 23
            width: train.unit * 24; height: train.unit * 15; radius: train.unit * 5
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Christmas.holly, 1.35) }
                GradientStop { position: 1; color: Christmas.pine }
            }
            Rectangle { x: train.unit * 9; width: train.unit * 2.5; height: parent.height; color: Christmas.gold }
        }
        Rectangle {     // chimney
            x: train.unit * 30; y: train.height - train.unit * 32
            width: train.unit * 6; height: train.unit * 10; color: "#20242a"
            Rectangle { x: -train.unit * 1.5; width: parent.width + train.unit * 3; height: train.unit * 3; radius: train.unit; color: Christmas.gold }
        }
        Rectangle {     // lamp and its beam
            x: train.unit * 39; y: train.height - train.unit * 21
            width: train.unit * 6; height: width; radius: width / 2; color: Christmas.paleGold
            Rectangle {
                x: parent.width / 2; anchors.verticalCenter: parent.verticalCenter
                width: train.unit * 46; height: train.unit * 7
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(Christmas.paleGold, 0.4) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Wheel { x: train.unit * 3; size: train.unit * 12 }
        Wheel { x: train.unit * 19 }
        Wheel { x: train.unit * 31 }
        MouseArea {
            x: 0; y: train.height - train.unit * 38
            width: parent.width; height: train.unit * 38
            cursorShape: Qt.PointingHandCursor
            onClicked: train.whistle()
        }
    }

    // ── before the first event: the departure board ──────────────────────────
    Loader {
        active: train.waiting && !changeover.running
        x: Math.min(train.width - width, train.head + train.unit * 22)
        y: train.height - height - train.unit * 4
        sourceComponent: Item {
            id: board
            implicitWidth: panel.width; implicitHeight: train.unit * 38
            property real drop: Christmas.motion ? 0 : 1
            NumberAnimation on drop { running: Christmas.motion; from: 0; to: 1; duration: 700; easing.type: Easing.OutBounce }
            opacity: Math.min(1, drop * 3)
            transform: Translate { y: -train.unit * 20 * (1 - board.drop) }
            Rectangle { x: panel.width / 2 - width / 2; y: panel.height; width: train.unit * 2; height: parent.height - panel.height; color: Christmas.gold }
            Rectangle {
                id: panel
                width: words.implicitWidth + train.unit * 30; height: train.unit * 24; radius: train.unit * 5
                color: Christmas.pine
                border.width: train.unit * 1.2; border.color: Christmas.gold
                Rectangle {     // the signal lamp, blinking while the train waits
                    id: beacon
                    x: train.unit * 8; anchors.verticalCenter: parent.verticalCenter
                    width: train.unit * 7; height: width; radius: width / 2; color: "#ffbd38"
                    SequentialAnimation on opacity {
                        running: Christmas.motion && train.visible; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 700 }
                        NumberAnimation { to: 1; duration: 700 }
                    }
                }
                Text {
                    id: words
                    x: train.unit * 21; anchors.verticalCenter: parent.verticalCenter
                    text: GCal.fmtTime(train.plan.t0)
                    color: Christmas.cream
                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: train.unit * 11
                }
            }
        }
    }

    // ── a day without events: the train sleeps beside a snowman ──────────────
    Loader {
        active: train.dayOff && !changeover.running
        x: train.head + train.unit * 26
        width: train.unit * 250; height: train.height
        sourceComponent: Item {
            id: rest
            property real appear: Christmas.motion ? 0 : 1
            NumberAnimation on appear { running: Christmas.motion; from: 0; to: 1; duration: 800; easing.type: Easing.OutBack }

            Item {      // the snowman, bobbing his head; he jumps at the whistle
                x: train.unit * 8; width: train.unit * 22; height: parent.height
                transform: Translate {
                    y: train.unit * 40 * (1 - rest.appear) - Math.abs(Math.sin(train.hop * Math.PI * 2)) * train.unit * 9
                }
                Snow { width: train.unit * 20; y: parent.height - train.unit * 23 }
                Item {
                    anchors.fill: parent
                    property real nod: 0
                    rotation: nod
                    transformOrigin: Item.Center
                    SequentialAnimation on nod {
                        running: Christmas.motion && train.visible && !train.awake; loops: Animation.Infinite
                        NumberAnimation { to: 7; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -3; duration: 1600; easing.type: Easing.InOutSine }
                    }
                    Snow { id: face; width: train.unit * 14; y: parent.height - train.unit * 34 }
                    Rectangle { x: train.unit * 7; y: face.y + train.unit * 4.5; width: train.unit * 2; height: width; radius: width / 2; color: "#20242a" }
                    Rectangle { x: train.unit * 13; y: face.y + train.unit * 4.5; width: train.unit * 2; height: width; radius: width / 2; color: "#20242a" }
                    Rectangle { x: train.unit * 11; y: face.y + train.unit * 7.5; width: train.unit * 8; height: train.unit * 2.2; radius: height / 2; color: "#ff8a2b" }
                    Rectangle { x: train.unit * 3.5; y: face.y + train.unit * 12; width: train.unit * 15; height: train.unit * 3.5; radius: height / 2; color: Christmas.cranberry }
                    Rectangle { x: train.unit * 5; y: face.y - train.unit; width: train.unit * 12; height: train.unit * 2.5; color: "#20242a" }
                    Rectangle { x: train.unit * 7.5; y: face.y - train.unit * 7; width: train.unit * 7; height: train.unit * 7; color: "#20242a" }
                }
            }
            ChristmasLights {
                x: train.unit * 40; y: parent.height - train.unit * 40
                width: train.unit * 200; height: train.unit * 14
                spacing: train.unit * 15; sag: train.unit * 3; bulb: train.unit * 2.2; seed: 5
            }
        }
    }
    Repeater {      // asleep
        model: train.dayOff && !train.awake && !train.rolling ? 3 : 0
        Text {
            id: zed
            required property int index
            property real k: index / 3
            NumberAnimation on k {
                running: Christmas.motion && train.visible; loops: Animation.Infinite
                from: zed.index / 3; to: zed.index / 3 + 1; duration: 3200
            }
            readonly property real along: k % 1
            x: train.head - train.engine + train.unit * (34 + 20 * along)
            y: train.height - train.unit * (30 + 22 * along) - height / 2
            text: "z"; color: "#cfe6ff"
            opacity: Math.sin(along * Math.PI)
            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: train.unit * (8 + 7 * along)
        }
    }

    // ── steam: a few reused puffs, left behind where they were blown ─────────
    Repeater {
        id: steam
        model: 12
        Rectangle {
            id: cloud
            property real k: 0
            property real from: 0
            property real big: 1
            readonly property bool busy: rise.running
            function blow(size: real): void {
                from = train.head - train.engine + train.unit * 33;
                big = size * (0.85 + Math.random() * 0.3);
                rise.restart();
            }
            NumberAnimation { id: rise; target: cloud; property: "k"; from: 0; to: 1; duration: 1500 }
            visible: busy
            width: train.unit * (5 + 13 * k) * big; height: width; radius: width / 2
            x: from - width / 2 - train.unit * 20 * k
            y: train.height - train.unit * (34 + 26 * k * big) - height / 2
            color: "#eef4f8"
            opacity: 0.6 * (1 - k)
        }
    }
}
