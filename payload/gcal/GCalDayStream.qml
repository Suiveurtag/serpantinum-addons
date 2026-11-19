import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Strip under the clock panel: the day's events as a horizontal stream, one block per event sized by its
// duration, overlapping events on separate lanes, a marker for "now", hover on the free time between events.
// Ported from the schedule module of the original Imperative Dots clock panel, fed by the calendar instead of a school timetable.
Item {
    id: root
    property color accent: ThemeBackend.mauve
    property bool active: false
    function s(v) { return Scaler.s(v); }

    readonly property var day: GCal.selectedDay || GCal.today
    readonly property bool isToday: GCal.sameDay(day, GCal.today)
    property var shownDay: day

    // ------------------------------------------------------------------ data

    readonly property var allDayEvents: GCal.eventsOn(shownDay).filter(e => e.allDay)
    readonly property var plan: {
        const d = root.shownDay;
        const d0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const d1 = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
        const items = [];
        for (const e of GCal.eventsOn(d)) {
            if (e.allDay || e.rsvp === "declined") continue;
            const a = Math.max(e.start, d0);
            let b = Math.min(e.end, d1);
            if (b <= a) b = Math.min(d1, a + 15 * 60000);
            items.push({ ev: e, a: a, b: b, lane: 0 });
        }
        const out = { items: items, lanes: 1, t0: 0, t1: 0, gaps: [] };
        if (!items.length) return out;
        items.sort((x, y) => (x.a - y.a) || (y.b - x.b));
        const laneEnd = [];
        for (const it of items) {
            let l = laneEnd.findIndex(v => v <= it.a);
            if (l < 0) { l = laneEnd.length; laneEnd.push(0); }
            laneEnd[l] = it.b;
            it.lane = Math.min(l, 3);
        }
        out.lanes = Math.min(laneEnd.length, 4);
        out.t0 = items[0].a;
        out.t1 = items.reduce((m, it) => Math.max(m, it.b), 0);
        if (out.t1 - out.t0 < 3 * 3600000) out.t1 = out.t0 + 3 * 3600000;
        let busy = items[0].b;
        for (let i = 1; i < items.length; i++) {
            if (items[i].a - busy >= 10 * 60000) out.gaps.push({ a: busy, b: items[i].a });
            busy = Math.max(busy, items[i].b);
        }
        return out;
    }
    readonly property bool hasItems: plan.items.length > 0
    readonly property real ppm: timeline.width / Math.max(1, plan.t1 - plan.t0)

    readonly property string summary: {
        if (GCal.status === "offline") return GCal.icon.offline + "  " + GCal.tr("Offline · showing saved events", "Hors ligne · événements en cache");
        if (GCal.pending > 0) return GCal.icon.sync + "  " + GCal.tr("%1 change(s) waiting to sync", "%1 modification(s) en attente").arg(GCal.pending);
        if (GCal.status === "error") return GCal.icon.alert + "  " + GCal.error;
        if (!GCal.available) return GCal.tr("Not connected", "Non connecté");
        const n = plan.items.length + allDayEvents.length;
        if (n === 0) return root.day.toLocaleDateString(GCal.locale, "d MMMM");
        let text = n === 1 ? GCal.tr("1 event", "1 évènement") : GCal.tr("%1 events", "%1 évènements").arg(n);
        if (root.isToday) {
            const next = plan.items.find(it => it.b > GCal.now);
            if (next) text += "  ·  " + (next.ev.title || GCal.tr("(No title)", "(Sans titre)")) + " " + GCal.relative(next.ev);
        }
        return text;
    }

    // ------------------------------------------------------------------ intro and day switch

    property real intro: 0
    property real swapOpacity: 1
    property real swapOffset: 0
    property int slideDir: 1

    onActiveChanged: {
        if (active) { intro = 0; introAnim.restart(); GCal.syncIfStale(); }
        else introAnim.stop();
    }
    SequentialAnimation {
        id: introAnim
        PauseAnimation { duration: 260 }
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
    }

    onDayChanged: {
        if (GCal.sameDay(day, shownDay)) return;
        slideDir = day > shownDay ? 1 : -1;
        daySwap.restart();
    }
    SequentialAnimation {
        id: daySwap
        ParallelAnimation {
            NumberAnimation { target: root; property: "swapOpacity"; to: 0; duration: 140; easing.type: Easing.InSine }
            NumberAnimation { target: root; property: "swapOffset"; to: -root.s(18) * root.slideDir; duration: 140; easing.type: Easing.InSine }
        }
        ScriptAction { script: { root.shownDay = root.day; root.swapOffset = root.s(18) * root.slideDir; } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "swapOpacity"; to: 1; duration: 360; easing.type: Easing.OutQuart }
            NumberAnimation { target: root; property: "swapOffset"; to: 0; duration: 360; easing.type: Easing.OutQuart }
        }
    }

    opacity: intro
    transform: Translate { y: root.s(50) * (1 - root.intro) }

    // ------------------------------------------------------------------ backdrop

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.alpha(ThemeBackend.crust, 0.45) }
        }
    }
    Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.5) }

    // Three slow sine waves drifting behind everything.
    Item {
        anchors.fill: parent
        opacity: 0.15
        clip: true

        Repeater {
            model: [
                { len: 100, amp: 30, ms: 4400, dir: 1, tone: "mauve" },
                { len: 120, amp: 40, ms: 6050, dir: -1, tone: "sapphire" },
                { len: 80, amp: 20, ms: 7700, dir: 1, tone: "peach" }
            ]
            delegate: Canvas {
                id: wave
                required property var modelData
                readonly property real wLen: root.s(modelData.len) * 2 * Math.PI
                width: parent.width + wLen
                height: parent.height
                NumberAnimation on x {
                    from: wave.modelData.dir > 0 ? 0 : -wave.wLen
                    to: wave.modelData.dir > 0 ? -wave.wLen : 0
                    duration: wave.modelData.ms
                    loops: Animation.Infinite
                    running: root.active
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const cy = height / 2, step = Math.max(2, root.s(10));
                    ctx.beginPath();
                    ctx.moveTo(0, cy);
                    for (let i = 0; i <= width + step * 2; i += step)
                        ctx.lineTo(i, cy + Math.sin(i / root.s(modelData.len)) * root.s(modelData.amp));
                    ctx.strokeStyle = String(ThemeBackend[modelData.tone]);
                    ctx.lineWidth = Math.max(1, root.s(2));
                    ctx.stroke();
                }
            }
        }
    }

    // ------------------------------------------------------------------ content

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.s(22)
        anchors.topMargin: root.s(16)
        spacing: root.s(10)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.s(38)
            spacing: root.s(12)

            Rectangle {
                Layout.preferredWidth: root.s(36); Layout.preferredHeight: root.s(36)
                radius: width / 2
                color: ThemeBackend.surface0
                Text {
                    anchors.centerIn: parent
                    text: GCal.icon.calendar
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.s(17)
                    color: root.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                GCalRollText {
                    Layout.fillWidth: true
                    text: GCal.dayTitle(root.shownDay).toUpperCase() + "  ·  " + root.shownDay.toLocaleDateString(GCal.locale, "d MMMM")
                    direction: root.slideDir
                    pixelSize: root.s(14)
                    weight: Font.Black
                    color: ThemeBackend.text
                }
                GCalRollText {
                    Layout.fillWidth: true
                    text: root.summary
                    direction: root.slideDir
                    pixelSize: root.s(11)
                    weight: Font.Bold
                    color: GCal.status === "error" ? ThemeBackend.red : ThemeBackend.overlay1
                }
            }

            // All-day events: a couple of chips, the rest counted.
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: root.s(6)
                visible: root.allDayEvents.length > 0
                opacity: root.swapOpacity
                transform: Translate { x: root.swapOffset }
                Repeater {
                    model: root.allDayEvents.slice(0, 2)
                    delegate: Rectangle {
                        required property var modelData
                        readonly property color tone: GCal.colorOf(modelData)
                        height: root.s(26)
                        width: Math.min(root.s(150), chipText.implicitWidth + root.s(20))
                        radius: root.s(8)
                        color: Qt.alpha(tone, chipHover.hovered ? 0.32 : 0.2)
                        border.width: 1
                        border.color: Qt.alpha(tone, 0.6)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: GCal.openAgenda("day", new Date(modelData.start), modelData.id) }
                        Text {
                            id: chipText
                            anchors.fill: parent
                            anchors.leftMargin: root.s(10); anchors.rightMargin: root.s(10)
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.title || GCal.tr("(No title)", "(Sans titre)")
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: root.s(11)
                            color: ThemeBackend.text
                        }
                    }
                }
                Text {
                    visible: root.allDayEvents.length > 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + (root.allDayEvents.length - 2)
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(11)
                    color: ThemeBackend.overlay1
                    TapHandler { onTapped: GCal.openAgenda("day", root.shownDay) }
                }
            }

            IconButton {
                Layout.preferredWidth: root.s(30); Layout.preferredHeight: root.s(30)
                size: root.s(30); cornerRadius: root.s(9)
                visible: GCal.writableCalendars.length > 0
                buttonIcon: GCal.icon.plus
                iconFontSize: root.s(14)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
                onClicked: { GCal.openEventId = "new"; GCal.openAgenda("day", root.day); }
            }
            IconButton {
                Layout.preferredWidth: root.s(30); Layout.preferredHeight: root.s(30)
                size: root.s(30); cornerRadius: root.s(9)
                buttonIcon: GCal.icon.expand
                iconFontSize: root.s(13)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
                onClicked: GCal.openAgenda("week", root.day)
            }
        }

        Item {
            id: timeline
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real axisH: root.s(16)
            readonly property real laneH: Math.min(root.s(84), (height - axisH) / root.plan.lanes)
            readonly property real blockTop: Math.max(0, (height - axisH - laneH * root.plan.lanes) / 2)

            // Not connected yet: an invitation that opens the agenda's setup screen.
            RowLayout {
                anchors.centerIn: parent
                visible: !GCal.available
                spacing: root.s(16)
                Text {
                    text: GCal.icon.calendar
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.s(34)
                    color: root.accent
                    opacity: 0.85
                }
                Text {
                    text: GCal.tr("Bring your Google Calendar or any iCal link here.", "Affiche ton Google Agenda ou n'importe quel lien iCal ici.")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(12)
                    font.weight: Font.Bold
                    color: ThemeBackend.subtext0
                }
                ClickButton {
                    Layout.preferredHeight: root.s(32)
                    Layout.preferredWidth: implicitWidth
                    buttonText: GCal.tr("Connect", "Connecter")
                    buttonIcon: GCal.icon.google
                    textFontSize: root.s(12); iconFontSize: root.s(14)
                    cornerRadius: root.s(10)
                    accentColor: root.accent
                    textColor: ThemeBackend.base
                    onClicked: GCal.openAgenda("week")
                }
            }

            // Free day.
            Row {
                anchors.centerIn: parent
                visible: GCal.available && !root.hasItems
                spacing: root.s(10)
                opacity: root.swapOpacity
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: GCal.icon.sun
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.s(26)
                    color: Qt.alpha(root.accent, 0.8)
                    RotationAnimation on rotation { running: root.active && parent.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 24000 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.allDayEvents.length > 0 ? GCal.tr("No timed events", "Aucun évènement horaire")
                        : root.isToday ? GCal.tr("Nothing planned today", "Rien de prévu aujourd'hui") : GCal.tr("Nothing planned", "Rien de prévu")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(13)
                    font.weight: Font.Bold
                    font.italic: true
                    color: ThemeBackend.overlay1
                }
            }

            Item {
                id: stream
                anchors.fill: parent
                visible: GCal.available && root.hasItems
                opacity: root.swapOpacity
                transform: Translate { x: root.swapOffset }

                Rectangle {
                    x: 0; width: parent.width
                    y: timeline.blockTop + timeline.laneH * root.plan.lanes / 2 - height / 2
                    height: root.s(2)
                    color: Qt.alpha(ThemeBackend.surface1, 0.4)
                }

                // Free time between events.
                Repeater {
                    model: root.plan.gaps
                    delegate: Item {
                        id: gap
                        required property var modelData
                        x: Math.round((modelData.a - root.plan.t0) * root.ppm)
                        width: Math.max(1, Math.round((modelData.b - modelData.a) * root.ppm))
                        height: timeline.height - timeline.axisH
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: timeline.blockTop + timeline.laneH * root.plan.lanes / 2 - parent.height / 2
                            width: parent.width
                            height: gapHover.hovered ? root.s(4) : root.s(2)
                            color: gapHover.hovered ? root.accent : "transparent"
                            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: timeline.blockTop + timeline.laneH * root.plan.lanes / 2 - parent.height / 2 - root.s(22)
                            width: gapLabel.implicitWidth + root.s(16)
                            height: root.s(24)
                            radius: root.s(6)
                            color: ThemeBackend.mantle
                            border.width: 1
                            border.color: ThemeBackend.surface2
                            opacity: gapHover.hovered ? 1 : 0
                            scale: gapHover.hovered ? 1 : 0.8
                            z: 20
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Text {
                                id: gapLabel
                                anchors.centerIn: parent
                                text: GCal.tr("Free", "Libre") + " · " + GCal.fmtDuration((gap.modelData.b - gap.modelData.a) / 60000)
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: root.s(12)
                                color: root.accent
                            }
                        }
                        HoverHandler { id: gapHover }
                    }
                }

                Repeater {
                    model: root.plan.items
                    delegate: Item {
                        id: node
                        required property var modelData
                        required property int index
                        readonly property var ev: modelData.ev
                        readonly property color tone: GCal.colorOf(ev)
                        readonly property bool current: GCal.now >= modelData.a && GCal.now < modelData.b
                        readonly property bool past: GCal.now >= modelData.b
                        readonly property color pastTone: Qt.darker(tone, 1.7)
                        readonly property bool compact: width < root.s(120)
                        // Lanes squeezed by a busy day: title and time share one line instead of leaving a lone centred title.
                        readonly property bool tight: !compact && height <= root.s(50)
                        readonly property string range: GCal.fmtTime(modelData.a) + "–" + GCal.fmtTime(modelData.b)
                        readonly property bool lit: current || nodeHover.hovered

                        x: Math.round((modelData.a - root.plan.t0) * root.ppm)
                        y: timeline.blockTop + modelData.lane * timeline.laneH
                        width: Math.max(root.s(4), Math.round((modelData.b - modelData.a) * root.ppm) - root.s(3))
                        height: timeline.laneH - root.s(6)
                        z: nodeHover.hovered ? 10 : 1

                        property real enter: 0
                        Component.onCompleted: enterAnim.start()
                        Connections {
                            target: root
                            function onActiveChanged() { if (root.active) { node.enter = 0; enterAnim.restart(); } }
                        }
                        SequentialAnimation {
                            id: enterAnim
                            PauseAnimation { duration: 80 + Math.min(node.index, 10) * 60 }
                            NumberAnimation { target: node; property: "enter"; from: 0; to: 1; duration: 520; easing.type: Easing.OutQuint }
                        }
                        opacity: enter * (past && !nodeHover.hovered ? 0.8 : 1)
                        transform: Translate { y: root.s(14) * (1 - node.enter) }

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.min(root.s(10), ThemeBackend.borderRadius)
                            topLeftRadius: 0
                            bottomLeftRadius: 0
                            color: Qt.alpha(node.tone, node.lit ? 0.2 : 0.09)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Rectangle {
                            id: accentLine
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: node.lit ? root.s(4) : root.s(2)
                            radius: ThemeBackend.borderRadius <= 1 ? 0 : root.s(2)
                            color: node.past ? Qt.darker(node.tone, 2.1) : node.tone
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Column {
                            anchors.left: accentLine.right
                            anchors.leftMargin: root.s(9)
                            anchors.right: parent.right
                            anchors.rightMargin: root.s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: nodeHover.hovered ? -root.s(1) : root.s(1)
                            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            spacing: root.s(4)
                            visible: node.width > root.s(36)
                            clip: true

                            Text {
                                id: titleText
                                width: parent.width
                                readonly property string label: node.ev.title || GCal.tr("(No title)", "(Sans titre)")
                                textFormat: node.tight ? Text.StyledText : Text.PlainText
                                text: node.tight
                                    ? label.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") + "  <font color=\"" + (node.current ? ThemeBackend.text : (node.past ? node.pastTone : ThemeBackend.overlay1)) + "\" size=\"2\"><b>" + node.range + "</b></font>"
                                    : label
                                elide: Text.ElideRight
                                wrapMode: node.compact && node.height > root.s(50) ? Text.WordWrap : Text.NoWrap
                                maximumLineCount: node.compact && node.height > root.s(50) ? 2 : 1
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Black
                                font.pixelSize: root.s(node.compact || node.tight ? 12 : 14)
                                color: node.current || nodeHover.hovered ? node.tone : (node.past ? node.pastTone : ThemeBackend.text)
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Row {
                                visible: node.height > root.s(50) && node.width > root.s(80)
                                spacing: root.s(4)
                                Text {
                                    id: clockIcon
                                    text: GCal.icon.clock
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: root.s(11)
                                    color: node.current ? node.tone : (node.past ? node.pastTone : ThemeBackend.overlay1)
                                }
                                Text {
                                    width: node.width - root.s(30) - clockIcon.width - root.s(4)
                                    text: node.range
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: root.s(11)
                                    color: node.current ? ThemeBackend.text : (node.past ? node.pastTone : ThemeBackend.overlay1)
                                }
                            }
                            Row {
                                visible: !!node.ev.location && node.width > root.s(80) && node.height > root.s(68) + (titleText.lineCount > 1 ? root.s(14) : 0)
                                spacing: root.s(4)
                                Text {
                                    id: placeIcon
                                    text: GCal.icon.place
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: root.s(11)
                                    color: node.past ? Qt.darker(ThemeBackend.peach, 1.9) : ThemeBackend.peach
                                }
                                Text {
                                    width: node.width - root.s(30) - placeIcon.width - root.s(4)
                                    text: node.ev.location || ""
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: root.s(11)
                                    color: ThemeBackend.subtext1
                                }
                            }
                        }

                        // Blocks too narrow for text say what they are on hover.
                        Rectangle {
                            visible: node.compact && opacity > 0.01
                            opacity: nodeHover.hovered ? 1 : 0
                            scale: nodeHover.hovered ? 1 : 0.85
                            width: tip.implicitWidth + root.s(16)
                            height: root.s(24)
                            radius: root.s(6)
                            color: ThemeBackend.mantle
                            border.width: 1
                            border.color: ThemeBackend.surface2
                            x: Math.max(-node.x, Math.min(stream.width - node.x - width, (node.width - width) / 2))
                            y: -height - root.s(4)
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Text {
                                id: tip
                                anchors.centerIn: parent
                                text: (node.ev.title || GCal.tr("(No title)", "(Sans titre)")) + " · " + GCal.fmtRange(node.ev)
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: root.s(12)
                                color: node.tone
                            }
                        }

                        HoverHandler { id: nodeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: GCal.openAgenda("day", new Date(node.ev.start), node.ev.id) }
                    }
                }

                // Now: the line draws down from the top once the blocks are in, its dot appears with it.
                Rectangle {
                    id: nowLine
                    readonly property bool inRange: root.isToday && GCal.now >= root.plan.t0 && GCal.now <= root.plan.t1
                    property real draw: 0
                    visible: inRange
                    x: Math.round((GCal.now - root.plan.t0) * root.ppm) - width / 2
                    y: 0
                    width: root.s(2)
                    height: (timeline.height - timeline.axisH) * draw
                    radius: width / 2
                    color: ThemeBackend.red
                    opacity: 0.85 * Math.min(1, draw * 3)
                    z: 30
                    Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

                    SequentialAnimation {
                        id: nowIntro
                        PauseAnimation { duration: 420 }
                        NumberAnimation { target: nowLine; property: "draw"; from: 0; to: 1; duration: 650; easing.type: Easing.OutQuint }
                    }
                    Connections {
                        target: root
                        function onActiveChanged() { if (root.active) { nowLine.draw = 0; nowIntro.restart(); } else nowIntro.stop(); }
                    }
                    Connections {
                        target: stream
                        function onVisibleChanged() { if (stream.visible) { nowLine.draw = 0; nowIntro.restart(); } }
                    }
                    Component.onCompleted: nowIntro.start()

                    Rectangle {
                        x: -width / 2 + parent.width / 2; y: -height / 2
                        width: root.s(8); height: width; radius: width / 2
                        color: ThemeBackend.red
                        scale: Math.min(1, nowLine.draw * 4)
                    }
                }

                // Axis: first start and last end.
                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: GCal.fmtTime(root.plan.t0)
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(10.5)
                    color: ThemeBackend.overlay0
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: GCal.fmtTime(root.plan.t1)
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(10.5)
                    color: ThemeBackend.overlay0
                }
            }
        }
    }
}
