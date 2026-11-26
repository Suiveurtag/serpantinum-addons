import QtQuick
import QtQuick.Controls
import "../"

// Week / day time grid. Events can be dragged (time and day) and resized from their bottom edge with 15 min
// snapping; dragging on empty space draws a new event; a line marks the current time.
Item {
    id: root
    required property Item agenda
    property int days: 7
    function s(v) { return Scaler.s(v); }

    readonly property var start: days === 7 ? GCal.weekStart(GCal.focusDate) : GCal.startOfDay(GCal.focusDate)
    readonly property var dates: {
        const out = [];
        for (let i = 0; i < root.days; i++) out.push(GCal.addDays(root.start, i));
        return out;
    }
    readonly property double rangeStart: start.getTime()
    readonly property double rangeEnd: GCal.addDays(start, days).getTime()
    readonly property real gutter: s(58)
    readonly property real hourH: days === 1 ? s(62) : s(52)
    readonly property real colW: (width - gutter - s(6)) / days
    readonly property real headerH: s(54)
    readonly property int snap: 15

    function dayIndexOf(ms) {
        return Math.round((GCal.startOfDay(ms) - root.start) / 86400000);
    }
    function movedTime(ms, days, minutes) {
        return GCal.addDays(new Date(ms), days).getTime() + minutes * 60000;
    }
    function minutesOf(ms) { const d = new Date(ms); return d.getHours() * 60 + d.getMinutes(); }
    function yOf(min) { return min / 60 * root.hourH; }

    readonly property var visible_: GCal.events.filter(e => e.end > root.rangeStart && e.start < root.rangeEnd).map(e => root.agenda.effective(e))
    readonly property var allDayEvents: visible_.filter(e => e.allDay || e.end - e.start >= 86400000)

    // Greedy lane packing for the all-day strip.
    readonly property var allDayLanes: {
        const items = root.allDayEvents.slice().sort((a, b) => a.start - b.start || b.end - a.end);
        const laneEnds = [];
        const out = [];
        for (const e of items) {
            const a = Math.max(0, root.dayIndexOf(e.start));
            const b = Math.min(root.days - 1, root.dayIndexOf(Math.max(e.start, e.end - 1)));
            let lane = laneEnds.findIndex(end => end < a);
            if (lane === -1) { lane = laneEnds.length; laneEnds.push(b); } else laneEnds[lane] = b;
            out.push({ ev: e, a: a, b: b, lane: lane });
        }
        return { items: out, count: laneEnds.length };
    }
    readonly property real allDayH: allDayLanes.count > 0 ? Math.min(4, allDayLanes.count) * s(22) + s(8) : s(10)

    // Per-day timed segments with overlap columns.
    readonly property var columns: {
        const result = [];
        for (let d = 0; d < root.days; d++) {
            const dayStart = root.dates[d].getTime();
            const dayEnd = GCal.addDays(root.dates[d], 1).getTime();
            const segs = [];
            for (const e of root.visible_) {
                if (e.allDay || e.end - e.start >= 86400000) continue;
                const s0 = Math.max(e.start, dayStart), s1 = Math.min(Math.max(e.end, e.start + 15 * 60000), dayEnd);
                if (s1 <= s0) continue;
                segs.push({ ev: e, s: s0, e: s1, col: 0, cols: 1, cutTop: e.start < dayStart, cutBottom: e.end > dayEnd });
            }
            segs.sort((a, b) => a.s - b.s || (b.e - b.s) - (a.e - a.s));
            let cluster = [], colEnds = [], clusterEnd = 0;
            const flush = () => { for (const c of cluster) c.cols = colEnds.length; cluster = []; colEnds = []; };
            for (const seg of segs) {
                if (seg.s >= clusterEnd && cluster.length) flush();
                let col = colEnds.findIndex(end => end <= seg.s);
                if (col === -1) { col = colEnds.length; colEnds.push(seg.e); } else colEnds[col] = seg.e;
                seg.col = col;
                cluster.push(seg);
                clusterEnd = Math.max(clusterEnd, seg.e);
            }
            flush();
            result.push(segs);
        }
        return result;
    }

    function scrollToMorning() {
        body.cancelFlick();
        let first = 8 * 60;
        const cols = root.columns || [];
        for (let i = 0; i < cols.length; i++) {
            const segs = cols[i] || [];
            for (let j = 0; j < segs.length; j++) first = Math.min(first, root.minutesOf(segs[j].s));
        }
        for (let i = 0; i < root.dates.length; i++)
            if (GCal.sameDay(root.dates[i], GCal.today)) first = Math.min(first, root.minutesOf(GCal.now) - 60);
        body.contentY = Math.max(0, Math.min(body.contentHeight - body.height, root.yOf(first - 45)));
    }
    function revealEvent(event) {
        if (event.allDay || event.end - event.start >= 86400000) {
            const lane = allDayLanes.items.find(item => item.ev.id === event.id);
            if (lane)
                allDayEvents.contentY = Math.min(lane.lane * s(22), Math.max(0, allDayEvents.contentHeight - allDayEvents.height));
        } else {
            const top = yOf(minutesOf(Math.max(event.start, rangeStart)));
            if (top < body.contentY || top + s(32) > body.contentY + body.height)
                body.contentY = Math.max(0, Math.min(top - s(48), body.contentHeight - body.height));
        }
    }
    onRangeStartChanged: { allDayEvents.contentY = 0; Qt.callLater(scrollToMorning); }
    onDaysChanged: Qt.callLater(scrollToMorning)
    Component.onCompleted: Qt.callLater(scrollToMorning)

    // ------------------------------------------------------------------ header
    Item {
        id: header
        width: parent.width
        height: root.headerH
        Repeater {
            model: root.dates
            Item {
                id: head
                required property var modelData
                required property int index
                readonly property bool isToday: GCal.sameDay(modelData, GCal.today)
                x: root.gutter + index * root.colW
                width: root.colW
                height: parent.height
                Row {
                    anchors.centerIn: parent
                    spacing: root.s(root.colW < root.s(80) ? 3 : 8)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: GCal.locale.dayName(head.modelData.getDay(), root.colW < root.s(65) ? Locale.NarrowFormat : Locale.ShortFormat).replace(".", "").toUpperCase()
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: root.s(11)
                        color: head.isToday ? root.agenda.accent : ThemeBackend.overlay1
                    }
                    Item {
                        width: root.s(root.colW < root.s(80) ? 26 : 34); height: width
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: head.isToday ? root.agenda.accent : (headMa.containsMouse ? ThemeBackend.surface1 : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: head.modelData.getDate()
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: root.s(16)
                            color: head.isToday ? ThemeBackend.base : ThemeBackend.text
                        }
                        MouseArea {
                            id: headMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.days > 1
                            onClicked: root.agenda.goTo(head.modelData, "day")
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ all-day strip
    Item {
        id: allDay
        anchors.top: header.bottom
        width: parent.width
        height: root.allDayH
        clip: true

        Text {
            width: root.gutter - root.s(10)
            y: root.s(6)
            horizontalAlignment: Text.AlignRight
            text: root.allDayLanes.count > 0 ? GCal.tr("all day", "journée") : ""
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(9.5)
            color: ThemeBackend.subtext0
        }
        MouseArea {
            x: root.gutter; width: parent.width - root.gutter; height: parent.height
            onDoubleClicked: (m) => {
                const day = root.dates[Math.max(0, Math.min(root.days - 1, Math.floor(m.x / root.colW)))];
                root.agenda.newEvent(day.getTime(), GCal.addDays(day, 1).getTime(), true);
            }
        }
        Flickable {
            id: allDayEvents
            ScrollBar.vertical: ScrollBar { policy: allDayEvents.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            x: root.gutter
            width: parent.width - x
            height: parent.height
            contentHeight: root.allDayLanes.count * root.s(22) + root.s(8)
            interactive: contentHeight > height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Repeater {
                model: root.allDayLanes.items
                Item {
                    id: bar
                    required property var modelData
                    required property int index
                    readonly property var ev: modelData.ev
                    readonly property color tone: GCal.colorOf(ev)
                    x: modelData.a * root.colW + root.s(2)
                    y: root.s(4) + modelData.lane * root.s(22)
                    width: (modelData.b - modelData.a + 1) * root.colW - root.s(4)
                    height: root.s(20)
                    Rectangle {
                        width: parent.width
                        height: parent.height
                        radius: root.s(7)
                        color: Qt.tint(ThemeBackend.base, Qt.alpha(bar.tone, barMa.containsMouse ? 0.95 : 0.82))
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(6)
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: bar.ev.title || GCal.tr("(No title)", "(Sans titre)")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: root.s(10.5)
                            color: GCal.readableOn(parent.color)
                        }
                    }
                    MouseArea { id: barMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.agenda.showDetails(bar.ev, bar) }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; x: root.gutter; width: parent.width - root.gutter; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.6) }
    }

    // ------------------------------------------------------------------ hours
    Flickable {
        id: body
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        anchors.top: allDay.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: root.hourH * 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !grid.busy

        Item {
            id: grid
            width: body.width
            height: body.contentHeight
            property bool busy: false

            Repeater {
                model: 24
                Item {
                    required property int index
                    y: index * root.hourH
                    width: grid.width
                    height: root.hourH
                    Text {
                        visible: parent.index > 0
                        width: root.gutter - root.s(10)
                        y: -height / 2
                        horizontalAlignment: Text.AlignRight
                        text: GCal.fmtTime(new Date(2000, 0, 1, parent.index, 0).getTime())
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: root.s(10)
                        color: ThemeBackend.subtext0
                    }
                    Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.45) }
                    Rectangle { x: root.gutter; y: root.hourH / 2; width: parent.width - root.gutter; height: 1; color: Qt.alpha(ThemeBackend.surface1, 0.16) }
                }
            }

            Repeater {
                model: root.days
                Item {
                    id: column
                    required property int index
                    readonly property var date: root.dates[index]
                    readonly property bool isToday: GCal.sameDay(date, GCal.today)
                    x: root.gutter + index * root.colW
                    width: root.colW
                    height: grid.height

                    Rectangle {
                        anchors.fill: parent
                        color: column.isToday ? Qt.alpha(root.agenda.accent, 0.05) : "transparent"
                        Rectangle { width: 1; height: parent.height; color: Qt.alpha(ThemeBackend.surface1, 0.35) }
                    }

                    // Draw-to-create.
                    MouseArea {
                        id: drawMa
                        anchors.fill: parent
                        hoverEnabled: GCal.writableCalendars.length > 0
                        cursorShape: Qt.CrossCursor
                        property real y0: 0
                        property real y1: 0
                        property bool drawing: false
                        function snapMin(y, step) { return Math.max(0, Math.min(1440, Math.round(y / root.hourH * 60 / step) * step)); }
                        onPressed: (m) => { y0 = m.y; y1 = m.y; drawing = false; }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            y1 = m.y;
                            if (!drawing && Math.abs(y1 - y0) > root.s(8)) { drawing = true; grid.busy = true; }
                        }
                        onReleased: {
                            const base = column.date.getTime();
                            let a, b;
                            if (drawing) {
                                a = snapMin(Math.min(y0, y1), root.snap); b = snapMin(Math.max(y0, y1), root.snap);
                                if (b - a < root.snap) b = a + root.snap;
                            } else {
                                a = snapMin(y0 - root.hourH / 4, 30); b = a + 60;
                            }
                            drawing = false; grid.busy = false;
                            root.agenda.newEvent(base + a * 60000, base + b * 60000, false);
                        }
                        onCanceled: { drawing = false; grid.busy = false; }
                    }
                    Rectangle {
                        visible: drawMa.drawing
                        readonly property real topMin: drawMa.snapMin(Math.min(drawMa.y0, drawMa.y1), root.snap)
                        readonly property real bottomMin: Math.max(topMin + root.snap, drawMa.snapMin(Math.max(drawMa.y0, drawMa.y1), root.snap))
                        x: root.s(2); width: parent.width - root.s(6)
                        y: root.yOf(topMin)
                        height: root.yOf(bottomMin) - y
                        radius: root.s(8)
                        color: Qt.alpha(root.agenda.accent, 0.3)
                        border.width: 1; border.color: root.agenda.accent
                        Behavior on y { NumberAnimation { duration: 90 } }
                        Behavior on height { NumberAnimation { duration: 90 } }
                        Text {
                            x: root.s(8); y: root.s(4)
                            text: GCal.fmtTime(column.date.getTime() + parent.topMin * 60000) + " – " + GCal.fmtTime(column.date.getTime() + parent.bottomMin * 60000)
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(10.5)
                            color: ThemeBackend.text
                        }
                    }

                    Repeater {
                        model: root.columns[column.index] || []
                        Item {
                            id: block
                            required property var modelData
                            required property int index
                            readonly property var ev: modelData.ev
                            readonly property color tone: GCal.colorOf(ev)
                            readonly property bool past: ev.end <= GCal.now
                            readonly property bool declined: ev.rsvp === "declined"
                            readonly property real baseX: modelData.col * (column.width - root.s(6)) / modelData.cols + root.s(2)
                            readonly property real baseW: (column.width - root.s(6)) / modelData.cols - root.s(2) + (modelData.col < modelData.cols - 1 ? root.s(14) : 0)
                            x: baseX
                            y: root.yOf(root.minutesOf(modelData.s)) + root.s(1)
                            width: Math.min(baseW, column.width - baseX - root.s(4))
                            height: Math.max(root.s(18), root.yOf((modelData.e - modelData.s) / 60000) - root.s(2)) + resizeDy
                            z: ma.mode !== "" ? 50 : (blockHover.hovered ? 10 : modelData.col)

                            // Drag deltas (snapped), applied as a translation until the edit lands.
                            property int dDays: 0
                            property int dMin: 0
                            property real resizeDy: 0
                            property int resizeMin: 0
                            transform: Translate {
                                x: block.dDays * root.colW
                                y: root.yOf(block.dMin)
                            }

                            Rectangle {
                                id: shadow
                                anchors.fill: parent
                                transform: Translate { y: ma.mode !== "" ? root.s(5) : 0 }
                                radius: card.radius
                                color: Qt.alpha("black", ma.mode !== "" ? 0.28 : 0)
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Rectangle {
                                id: card
                                anchors.fill: parent
                                radius: Math.min(root.s(9), ThemeBackend.borderRadius)
                                topLeftRadius: block.modelData.cutTop ? root.s(2) : radius
                                topRightRadius: block.modelData.cutTop ? root.s(2) : radius
                                bottomLeftRadius: block.modelData.cutBottom ? root.s(2) : radius
                                bottomRightRadius: block.modelData.cutBottom ? root.s(2) : radius
                                color: block.declined ? "transparent" : Qt.tint(ThemeBackend.base,
                                    Qt.alpha(block.tone, blockHover.hovered || ma.mode !== "" ? 0.92 : (block.past ? 0.60 : 0.82)))
                                border.width: block.declined || block.ev.pending ? 1 : 0
                                border.color: block.tone
                                Behavior on color { ColorAnimation { duration: 140 } }
                                clip: true

                                Rectangle {
                                    width: root.s(3); height: parent.height
                                    color: Qt.darker(block.tone, 1.35)
                                    visible: !block.declined
                                }
                                // Pending edit: a light sweep across the block until Google confirms it.
                                Rectangle {
                                    visible: block.ev.pending
                                    width: parent.width * 0.4; height: parent.height
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
                                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                                    }
                                    NumberAnimation on x { running: block.ev.pending; loops: Animation.Infinite; from: -card.width * 0.4; to: card.width; duration: 1200 }
                                }

                                Column {
                                    x: root.s(8); y: root.s(4)
                                    width: parent.width - root.s(12)
                                    spacing: root.s(1)
                                    Text {
                                        width: parent.width
                                        text: block.ev.title || GCal.tr("(No title)", "(Sans titre)")
                                        elide: Text.ElideRight
                                        wrapMode: Text.Wrap
                                        maximumLineCount: Math.max(1, Math.floor((block.height - root.s(20)) / root.s(14)))
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Black
                                        font.pixelSize: root.s(11)
                                        font.strikeout: block.declined
                                        color: block.declined ? ThemeBackend.text : GCal.readableOn(card.color)
                                    }
                                    Text {
                                        visible: block.height > root.s(34)
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: {
                                            const moving = ma.mode === "move";
                                            const start = moving ? root.movedTime(block.ev.start, block.dDays, block.dMin) : block.ev.start;
                                            const end = moving ? root.movedTime(block.ev.end, block.dDays, block.dMin) : block.ev.end + block.resizeMin * 60000;
                                            return GCal.fmtTime(start) + " – " + GCal.fmtTime(end) + (block.ev.location && ma.mode === "" ? "  ·  " + block.ev.location : "");
                                        }
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Bold
                                        font.pixelSize: root.s(10)
                                        color: block.declined ? ThemeBackend.subtext0 : GCal.readableOn(card.color)
                                    }
                                }
                                Text {
                                    visible: !!block.ev.meet && block.height > root.s(22)
                                    anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: root.s(5)
                                    text: GCal.icon.video
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: root.s(12)
                                    color: block.declined ? ThemeBackend.text : GCal.readableOn(card.color)
                                }
                                // Resize grip.
                                Rectangle {
                                    visible: block.ev.editable && blockHover.hovered && block.height > root.s(26)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: root.s(3)
                                    width: root.s(18); height: root.s(3); radius: height / 2
                                    color: Qt.alpha(GCal.readableOn(card.color), 0.6)
                                }
                            }

                            HoverHandler { id: blockHover; cursorShape: block.ev.editable ? (ma.mode === "resize" || ma.nearEdge ? Qt.SizeVerCursor : Qt.PointingHandCursor) : Qt.PointingHandCursor }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                property string mode: ""
                                property point origin
                                property bool nearEdge: containsMouse && mouseY > height - root.s(8)
                                onPressed: (m) => { origin = mapToItem(grid, m.x, m.y); mode = ""; }
                                onPositionChanged: (m) => {
                                    if (!pressed || !block.ev.editable) return;
                                    const p = mapToItem(grid, m.x, m.y);
                                    const dx = p.x - origin.x, dy = p.y - origin.y;
                                    if (mode === "" && Math.hypot(dx, dy) > root.s(6)) {
                                        mode = origin.y - (block.y + column.y) > block.height - root.s(8) - block.resizeDy ? "resize" : "move";
                                        if (block.modelData.cutTop || block.modelData.cutBottom) mode = "move";
                                        grid.busy = true;
                                    }
                                    if (mode === "move") {
                                        block.dMin = Math.round(dy / root.hourH * 60 / root.snap) * root.snap;
                                        block.dDays = root.days > 1 ? Math.max(-column.index, Math.min(root.days - 1 - column.index, Math.round(dx / root.colW))) : 0;
                                    } else if (mode === "resize") {
                                        const length = (block.ev.end - block.ev.start) / 60000;
                                        block.resizeMin = Math.max(root.snap - length, Math.round(dy / root.hourH * 60 / root.snap) * root.snap);
                                        block.resizeDy = root.yOf(block.resizeMin);
                                    }
                                }
                                onReleased: {
                                    const m = mode;
                                    mode = "";
                                    grid.busy = false;
                                    if (m === "move" && (block.dMin !== 0 || block.dDays !== 0)) {
                                        root.agenda.moveEvent(block.ev, root.movedTime(block.ev.start, block.dDays, block.dMin),
                                            root.movedTime(block.ev.end, block.dDays, block.dMin));
                                    } else if (m === "resize" && block.resizeMin !== 0) {
                                        root.agenda.moveEvent(block.ev, block.ev.start, block.ev.end + block.resizeMin * 60000);
                                    } else if (m === "") {
                                        root.agenda.showDetails(block.ev, block);
                                    }
                                    block.dMin = 0; block.dDays = 0; block.resizeMin = 0; block.resizeDy = 0;
                                }
                                onCanceled: { mode = ""; grid.busy = false; block.dMin = 0; block.dDays = 0; block.resizeMin = 0; block.resizeDy = 0; }
                            }
                        }
                    }

                    // Now line.
                    Item {
                        visible: column.isToday
                        width: parent.width
                        y: root.yOf(root.minutesOf(GCal.now))
                        z: 60
                        Rectangle { width: parent.width; height: root.s(2); y: -height / 2; color: ThemeBackend.red; radius: height / 2 }
                        Rectangle {
                            x: -width / 2; y: -height / 2
                            width: root.s(10); height: width; radius: width / 2
                            color: ThemeBackend.red
                        }

                    }
                }
            }
        }
    }
}
