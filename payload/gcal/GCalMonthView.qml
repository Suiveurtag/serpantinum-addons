import QtQuick
import "../"

// Month grid: cells cascade in on every month change, chips can be dragged to another day, a double click
// creates an event, the day number opens the day view.
Item {
    id: root
    required property Item agenda
    property real reveal: 1
    function s(v) { return Scaler.s(v); }

    readonly property var month: new Date(GCal.focusDate.getFullYear(), GCal.focusDate.getMonth(), 1)
    readonly property var first: GCal.weekStart(month)
    readonly property int rows: {
        const last = new Date(month.getFullYear(), month.getMonth() + 1, 0);
        return Math.ceil((Math.round((last - first) / 86400000) + 1) / 7);
    }
    readonly property real headerH: s(26)
    readonly property real cw: width / 7
    readonly property real ch: (height - headerH) / rows
    readonly property int maxChips: Math.max(1, Math.floor((ch - s(30)) / s(20)))

    // Cascade replay: bumps whenever the shown month changes.
    property int generation: 0
    onMonthChanged: generation++

    // Drag state (a floating copy of the chip follows the pointer, the target cell lights up).
    property var dragEvent: null
    property int dragFrom: -1
    property int dragOver: -1
    property point dragPos: Qt.point(0, 0)
    function cellAt(x, y) {
        if (y < headerH) return -1;
        const c = Math.floor(x / cw), r = Math.floor((y - headerH) / ch);
        if (c < 0 || c > 6 || r < 0 || r >= rows) return -1;
        return r * 7 + c;
    }

    Row {
        width: parent.width
        height: root.headerH
        Repeater {
            model: GCal.weekdayLetters()
            Text {
                required property string modelData
                required property int index
                width: root.cw
                height: root.headerH
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData.toUpperCase()
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Black
                font.pixelSize: root.s(11)
                font.letterSpacing: root.s(0.5)
                color: ThemeBackend.overlay1
                opacity: root.reveal
                transform: Translate { y: -root.s(6) * (1 - root.reveal) }
            }
        }
    }

    Repeater {
        model: root.rows * 7
        Item {
            id: cell
            required property int index
            readonly property var date: GCal.addDays(root.first, index)
            readonly property bool inMonth: date.getMonth() === root.month.getMonth()
            readonly property bool isToday: GCal.sameDay(date, GCal.today)
            readonly property bool weekend: date.getDay() === 0 || date.getDay() === 6
            readonly property var events: GCal.eventsOn(date)
            x: (index % 7) * root.cw
            y: root.headerH + Math.floor(index / 7) * root.ch
            width: root.cw
            height: root.ch

            property real enter: 0
            Connections {
                target: root
                function onGenerationChanged() { cellIn.restart(); }
            }
            Component.onCompleted: cellIn.start()
            SequentialAnimation {
                id: cellIn
                ScriptAction { script: cell.enter = 0 }
                PauseAnimation { duration: (Math.floor(cell.index / 7) + cell.index % 7) * 18 }
                NumberAnimation { target: cell; property: "enter"; to: 1; duration: 420; easing.type: Easing.OutQuint }
            }
            opacity: enter * root.reveal
            transform: Translate { y: root.s(10) * (1 - cell.enter) }

            Rectangle {
                anchors.fill: parent
                anchors.margins: root.s(2)
                radius: Math.min(ThemeBackend.borderRadius, root.s(12))
                color: root.dragOver === cell.index ? Qt.alpha(root.agenda.accent, 0.22)
                     : cellMa.containsMouse ? Qt.alpha(ThemeBackend.surface0, 0.55)
                     : Qt.alpha(ThemeBackend.surface0, cell.inMonth ? (cell.weekend ? 0.12 : 0.22) : 0.06)
                border.width: root.dragOver === cell.index || cell.isToday ? 1 : 0
                border.color: Qt.alpha(root.agenda.accent, 0.55)
                Behavior on color { ColorAnimation { duration: 160 } }
            }

            MouseArea {
                id: cellMa
                anchors.fill: parent
                hoverEnabled: true
                onDoubleClicked: {
                    const start = new Date(cell.date.getFullYear(), cell.date.getMonth(), cell.date.getDate(), 9, 0);
                    root.agenda.newEvent(start.getTime(), start.getTime() + 3600000, false);
                }
            }

            // Day number (opens the day view).
            Item {
                id: num
                x: root.s(8); y: root.s(6)
                width: root.s(24); height: root.s(24)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: cell.isToday ? root.agenda.accent : (numMa.containsMouse ? ThemeBackend.surface1 : "transparent")
                    scale: numMa.pressed ? 0.88 : (numMa.containsMouse ? 1.1 : 1)
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: cell.date.getDate()
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(11.5)
                    color: cell.isToday ? ThemeBackend.base : (cell.inMonth ? ThemeBackend.text : ThemeBackend.surface2)
                }
                MouseArea { id: numMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.agenda.goTo(cell.date, "day") }
            }

            Column {
                x: root.s(5)
                y: root.s(32)
                width: parent.width - root.s(10)
                spacing: root.s(2)
                Repeater {
                    model: cell.events.slice(0, cell.events.length > root.maxChips ? root.maxChips - 1 : root.maxChips)
                    Item {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property var ev: modelData
                        readonly property color tone: GCal.colorOf(ev)
                        readonly property bool filled: ev.allDay || ev.end - ev.start >= 86400000
                        readonly property bool past: ev.end <= GCal.now
                        width: parent.width
                        height: root.s(18)
                        opacity: (root.dragEvent && root.dragEvent.id === ev.id && root.dragFrom === cell.index ? 0.3 : 1) * (past ? 0.55 : 1)
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        property real pop: 0
                        Component.onCompleted: popIn.start()
                        SequentialAnimation {
                            id: popIn
                            PauseAnimation { duration: 120 + (Math.floor(cell.index / 7) + cell.index % 7) * 18 + chip.index * 40 }
                            NumberAnimation { target: chip; property: "pop"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                        }
                        transform: [
                            Scale { origin.x: 0; origin.y: chip.height / 2; xScale: 0.6 + 0.4 * chip.pop; yScale: xScale },
                            Translate { x: chipMa.containsMouse ? root.s(2) : 0; Behavior on x { NumberAnimation { duration: 160 } } }
                        ]

                        Rectangle {
                            anchors.fill: parent
                            radius: root.s(6)
                            color: chip.filled ? Qt.alpha(chip.tone, chipMa.containsMouse ? 0.95 : 0.8) : (chipMa.containsMouse ? Qt.alpha(chip.tone, 0.18) : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        Rectangle {
                            visible: !chip.filled
                            x: root.s(5); anchors.verticalCenter: parent.verticalCenter
                            width: root.s(6); height: width; radius: width / 2
                            color: chip.tone
                        }
                        Text {
                            x: chip.filled ? root.s(6) : root.s(15)
                            width: parent.width - x - root.s(4)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: (chip.filled ? "" : GCal.fmtTime(chip.ev.start) + "  ") + (chip.ev.title || GCal.tr("(No title)", "(Sans titre)"))
                            font.family: ThemeBackend.fontFamily
                            font.weight: chip.filled ? Font.Black : Font.Bold
                            font.pixelSize: root.s(10.5)
                            font.strikeout: chip.ev.rsvp === "declined"
                            color: chip.filled ? GCal.readableOn(chip.tone) : ThemeBackend.text
                        }

                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: chip.ev.editable ? (pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor) : Qt.PointingHandCursor
                            property point origin
                            property bool dragging: false
                            onPressed: (m) => { origin = Qt.point(m.x, m.y); dragging = false; }
                            onPositionChanged: (m) => {
                                if (!pressed || !chip.ev.editable) return;
                                if (!dragging && Math.hypot(m.x - origin.x, m.y - origin.y) > root.s(6)) {
                                    dragging = true;
                                    root.dragEvent = chip.ev;
                                    root.dragFrom = cell.index;
                                }
                                if (dragging) {
                                    const p = chipMa.mapToItem(root, m.x, m.y);
                                    root.dragPos = p;
                                    root.dragOver = root.cellAt(p.x, p.y);
                                }
                            }
                            onReleased: {
                                if (dragging) {
                                    const target = root.dragOver;
                                    if (target >= 0 && target !== root.dragFrom) {
                                        const delta = Math.round((GCal.addDays(root.first, target) - GCal.addDays(root.first, root.dragFrom)) / 86400000);
                                        const shift = (d) => GCal.addDays(new Date(d), delta).getTime();
                                        root.agenda.moveEvent(chip.ev, shift(chip.ev.start), shift(chip.ev.end));
                                    }
                                }
                                dragging = false;
                                root.dragEvent = null; root.dragFrom = -1; root.dragOver = -1;
                            }
                            onClicked: (m) => { if (!dragging) root.agenda.showDetails(chip.ev, chip); }
                        }
                    }
                }
                Text {
                    visible: cell.events.length > root.maxChips
                    x: root.s(6)
                    text: GCal.tr("+%1 more", "+%1 de plus").arg(cell.events.length - root.maxChips + 1)
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(10)
                    color: moreMa.containsMouse ? root.agenda.accent : ThemeBackend.overlay1
                    Behavior on color { ColorAnimation { duration: 140 } }
                    MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.agenda.goTo(cell.date, "day") }
                }
            }
        }
    }

    // Floating chip under the pointer while dragging.
    Rectangle {
        visible: !!root.dragEvent
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        width: Math.min(root.cw - root.s(10), root.s(180))
        height: root.s(22)
        radius: root.s(7)
        color: root.dragEvent ? GCal.colorOf(root.dragEvent) : "transparent"
        scale: visible ? 1.06 : 0.8
        rotation: -2
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        z: 20
        Text {
            anchors.fill: parent
            anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.dragEvent ? (root.dragEvent.title || "") : ""
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Black
            font.pixelSize: root.s(11)
            color: root.dragEvent ? GCal.readableOn(GCal.colorOf(root.dragEvent)) : "white"
        }
    }
}
