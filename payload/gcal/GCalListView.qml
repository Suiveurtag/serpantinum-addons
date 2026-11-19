import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Agenda list (upcoming days from the focused date) and search results, grouped by day with sticky headers.
Item {
    id: root
    required property Item agenda
    property string query: ""
    property real reveal: 1
    function s(v) { return Scaler.s(v); }

    readonly property bool searching: query.trim().length > 0
    readonly property var rows: {
        const out = [];
        if (root.searching) {
            const words = root.query.toLowerCase().split(/\s+/).filter(w => w);
            const found = GCal.events.filter(e => {
                const hay = (e.title + " " + e.location + " " + e.description).toLowerCase();
                return words.every(w => hay.indexOf(w) !== -1);
            }).sort((a, b) => Math.abs(a.start - GCal.now) - Math.abs(b.start - GCal.now)).slice(0, 120)
              .sort((a, b) => a.start - b.start);
            let last = "";
            for (const e of found) {
                const k = GCal.key(e.start);
                if (k !== last) { out.push({ kind: "header", dayMs: GCal.startOfDay(e.start).getTime() }); last = k; }
                out.push({ kind: "event", ev: e });
            }
            return out;
        }
        const first = GCal.startOfDay(GCal.focusDate);
        for (let i = 0; i < 60; i++) {
            const d = GCal.addDays(first, i);
            const list = GCal.eventsOn(d);
            if (list.length) out.push({ kind: "header", dayMs: d.getTime() });
            for (const e of list) out.push({ kind: "event", ev: e });
        }
        return out;
    }

    property int generation: 0
    onRowsChanged: generation++

    // Empty states.
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        spacing: root.s(10)
        opacity: root.reveal
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.searching ? GCal.icon.search : GCal.icon.sun
            font.family: ThemeBackend.iconFont
            font.pixelSize: root.s(54)
            color: Qt.alpha(root.agenda.accent, 0.8)
            SequentialAnimation on scale {
                running: parent.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.08; to: 1; duration: 1800; easing.type: Easing.InOutSine }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.searching ? GCal.tr("No event matches “%1”", "Aucun événement ne correspond à « %1 »").arg(root.query) : GCal.tr("Nothing in the next two months", "Rien dans les deux prochains mois")
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(14)
            color: ThemeBackend.overlay1
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: root.s(8)
        anchors.rightMargin: root.s(8)
        model: root.rows
        spacing: root.s(6)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        opacity: root.reveal
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isHeader: modelData.kind === "header"
            readonly property var ev: isHeader ? ({ start: 0, end: 0, title: "", location: "", calendarId: "", meet: "", rsvp: "" }) : modelData.ev
            readonly property color tone: GCal.colorOf(ev)
            readonly property bool past: !isHeader && ev.end <= GCal.now
            readonly property var date: new Date(isHeader ? modelData.dayMs : 0)
            readonly property bool isToday: GCal.sameDay(date, GCal.today)
            width: ListView.view.width
            height: isHeader ? root.s(48) : root.s(58)

            RowLayout {
                visible: row.isHeader
                anchors.fill: parent
                anchors.leftMargin: root.s(6)
                anchors.topMargin: root.s(6)
                spacing: root.s(12)
                Rectangle {
                    Layout.preferredWidth: root.s(34); Layout.preferredHeight: root.s(34)
                    radius: width / 2
                    color: row.isToday ? root.agenda.accent : Qt.alpha(ThemeBackend.surface0, 0.6)
                    scale: 0.6 + 0.4 * row.enter
                    Text {
                        anchors.centerIn: parent
                        text: row.date.getDate()
                        font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(14)
                        color: row.isToday ? ThemeBackend.base : ThemeBackend.text
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.isHeader ? (GCal.dayTitle(row.date) + "  ·  " + row.date.toLocaleDateString(GCal.locale, "d MMMM yyyy")).toUpperCase() : ""
                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11.5)
                    font.letterSpacing: root.s(0.4)
                    color: row.isToday ? root.agenda.accent : ThemeBackend.subtext0
                }
            }

            property real enter: 0
            Component.onCompleted: enterAnim.start()
            SequentialAnimation {
                id: enterAnim
                PauseAnimation { duration: Math.min(row.index, 14) * 30 }
                NumberAnimation { target: row; property: "enter"; to: 1; duration: 460; easing.type: Easing.OutQuint }
            }
            opacity: enter * (past ? 0.55 : 1)
            transform: Translate { x: root.s(24) * (1 - row.enter) }

            Rectangle {
                visible: !row.isHeader
                anchors.fill: parent
                anchors.leftMargin: root.s(46)
                radius: Math.min(ThemeBackend.borderRadius, root.s(12))
                color: Qt.alpha(ThemeBackend.surface0, rowMa.containsMouse ? 0.6 : 0.25)
                Behavior on color { ColorAnimation { duration: 160 } }

                Rectangle {
                    x: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.s(4); height: (parent.height - root.s(18)) * row.enter
                    radius: width / 2
                    color: row.tone
                }
                Text {
                    id: timeLabel
                    x: root.s(24)
                    width: root.s(118)
                    anchors.verticalCenter: parent.verticalCenter
                    text: GCal.fmtRange(row.ev)
                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                    color: ThemeBackend.overlay1
                    elide: Text.ElideRight
                }
                ColumnLayout {
                    anchors.left: timeLabel.right
                    anchors.leftMargin: root.s(8)
                    anchors.right: actions.left
                    anchors.rightMargin: root.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(2)
                    Text {
                        Layout.fillWidth: true
                        text: row.ev.title || GCal.tr("(No title)", "(Sans titre)")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(13)
                        font.strikeout: row.ev.rsvp === "declined"
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: [GCal.calendarMap[row.ev.calendarId] ? GCal.calendarMap[row.ev.calendarId].name : "", row.ev.location].filter(x => x).join("  ·  ")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(10.5)
                        color: ThemeBackend.overlay1
                    }
                }
                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.rightMargin: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(6)
                    ClickButton {
                        visible: !!row.ev.meet && !row.past
                        height: root.s(28)
                        width: implicitWidth
                        buttonText: GCal.tr("Join", "Rejoindre")
                        buttonIcon: GCal.icon.video
                        textFontSize: root.s(11); iconFontSize: root.s(13)
                        cornerRadius: root.s(9)
                        accentColor: row.tone
                        textColor: GCal.readableOn(row.tone)
                        onClicked: Qt.openUrlExternally(row.ev.meet)
                    }
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    anchors.rightMargin: actions.width + root.s(16)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.agenda.showDetails(row.ev, row)
                }
            }
        }
    }
}
