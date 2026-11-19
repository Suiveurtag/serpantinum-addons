import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Fourth column of the clock panel: the events of the day picked in the mini calendar (today by default),
// followed by tomorrow's when looking at today. Rows cascade in, the list slides when the day changes.
Item {
    id: root
    property color accent: ThemeBackend.mauve
    property bool active: false
    function s(v) { return Scaler.s(v); }

    readonly property var day: GCal.selectedDay || GCal.today
    readonly property bool isToday: GCal.sameDay(day, GCal.today)
    readonly property var rows: {
        const out = [];
        const first = GCal.eventsOn(root.day);
        for (const e of first) out.push({ kind: "event", ev: e });
        if (root.isToday) {
            const next = GCal.eventsOn(GCal.addDays(root.day, 1));
            if (next.length) {
                out.push({ kind: "header", label: GCal.tr("Tomorrow", "Demain") });
                for (const e of next.slice(0, 6)) out.push({ kind: "event", ev: e });
            }
        }
        return out;
    }
    readonly property bool empty: GCal.eventsOn(root.day).length === 0

    // Intro (follows the native panel's columns) and day-switch slide.
    property real intro: 0
    property real listOpacity: 1
    property real listOffset: 0
    property int slideDir: 1
    property var shownDay: day

    onActiveChanged: {
        if (active) { intro = 0; introAnim.restart(); GCal.selectedDay = null; GCal.sync(); }
        else introAnim.stop();
    }
    SequentialAnimation {
        id: introAnim
        PauseAnimation { duration: 160 }
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 520; easing.type: Easing.OutQuint }
    }

    onDayChanged: {
        if (GCal.sameDay(day, shownDay)) return;
        slideDir = day > shownDay ? 1 : -1;
        daySwap.restart();
    }
    SequentialAnimation {
        id: daySwap
        ParallelAnimation {
            NumberAnimation { target: root; property: "listOpacity"; to: 0; duration: 150; easing.type: Easing.InSine }
            NumberAnimation { target: root; property: "listOffset"; to: -root.s(22) * root.slideDir; duration: 150; easing.type: Easing.InSine }
        }
        ScriptAction { script: { root.shownDay = root.day; root.listOffset = root.s(22) * root.slideDir; } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "listOpacity"; to: 1; duration: 380; easing.type: Easing.OutQuart }
            NumberAnimation { target: root; property: "listOffset"; to: 0; duration: 380; easing.type: Easing.OutQuart }
        }
    }

    opacity: intro
    transform: Translate { x: root.s(40) * (1 - root.intro) }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.s(10)

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(8)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                GCalRollText {
                    Layout.fillWidth: true
                    text: GCal.dayTitle(root.day).toUpperCase()
                    direction: root.slideDir
                    pixelSize: root.s(14)
                    weight: Font.Black
                    color: ThemeBackend.text
                }
                GCalRollText {
                    Layout.fillWidth: true
                    text: root.day.toLocaleDateString(GCal.locale, "d MMMM")
                    direction: root.slideDir
                    pixelSize: root.s(11)
                    weight: Font.Bold
                    color: ThemeBackend.overlay1
                }
            }

            IconButton {
                Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                size: root.s(28); cornerRadius: root.s(8)
                visible: GCal.writableCalendars.length > 0
                buttonIcon: GCal.icon.plus
                iconFontSize: root.s(14)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
                onClicked: { GCal.openEventId = "new"; GCal.openAgenda("day", root.day); }
            }
            IconButton {
                Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                size: root.s(28); cornerRadius: root.s(8)
                buttonIcon: GCal.icon.expand
                iconFontSize: root.s(13)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
                onClicked: GCal.openAgenda("week", root.day)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Not configured: a gentle invitation that opens the agenda's setup screen.
            Item {
                anchors.fill: parent
                visible: !GCal.available
                opacity: visible ? 1 : 0

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - root.s(16)
                    spacing: root.s(10)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: GCal.icon.calendar
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: root.s(46)
                        color: root.accent
                        opacity: 0.85
                        transform: Translate {
                            SequentialAnimation on y {
                                running: root.active && !GCal.available
                                loops: Animation.Infinite
                                NumberAnimation { from: 0; to: -root.s(6); duration: 2200; easing.type: Easing.InOutSine }
                                NumberAnimation { from: -root.s(6); to: 0; duration: 2200; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: GCal.tr("Bring your Google Calendar or any iCal link here.", "Affiche ton Google Agenda ou n'importe quel lien iCal ici.")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(12)
                        font.weight: Font.Bold
                        color: ThemeBackend.subtext0
                    }
                    ClickButton {
                        Layout.alignment: Qt.AlignHCenter
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
            }

            // Free day.
            ColumnLayout {
                anchors.centerIn: parent
                visible: GCal.available && root.rows.length === 0
                spacing: root.s(6)
                opacity: root.listOpacity
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: GCal.icon.sun
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.s(34)
                    color: Qt.alpha(root.accent, 0.8)
                    RotationAnimation on rotation {
                        running: root.active && parent.visible
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 24000
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isToday ? GCal.tr("Nothing planned today", "Rien de prévu aujourd'hui") : GCal.tr("Nothing planned", "Rien de prévu")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(12)
                    font.weight: Font.Bold
                    color: ThemeBackend.overlay1
                }
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: GCal.available
                model: root.rows
                spacing: root.s(6)
                boundsBehavior: Flickable.StopAtBounds
                opacity: root.listOpacity
                transform: Translate { x: root.listOffset }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.kind === "header"
                    readonly property var ev: modelData.ev
                    readonly property color tone: isHeader ? root.accent : GCal.colorOf(ev)
                    readonly property bool past: !isHeader && ev.end <= GCal.now
                    readonly property bool ongoing: !isHeader && !ev.allDay && ev.start <= GCal.now && ev.end > GCal.now
                    width: ListView.view.width
                    height: isHeader ? root.s(24) : root.s(50)

                    property real enter: 0
                    Component.onCompleted: enterAnim.start()
                    SequentialAnimation {
                        id: enterAnim
                        PauseAnimation { duration: 60 + Math.min(row.index, 10) * 45 }
                        NumberAnimation { target: row; property: "enter"; from: 0; to: 1; duration: 480; easing.type: Easing.OutQuint }
                    }
                    opacity: enter * (past ? 0.5 : 1)
                    transform: Translate { x: root.s(18) * (1 - row.enter) }

                    Text {
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.s(2)
                        text: row.isHeader ? row.modelData.label.toUpperCase() : ""
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: root.s(11)
                        font.letterSpacing: root.s(0.6)
                        color: ThemeBackend.overlay1
                    }

                    Rectangle {
                        id: card
                        visible: !row.isHeader
                        anchors.fill: parent
                        radius: Math.min(ThemeBackend.borderRadius, root.s(12))
                        color: cardGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, cardHover.hovered ? 0.55 : (row.ongoing ? 0.4 : 0.22))
                        Behavior on color { ColorAnimation { duration: 180 } }
                        scale: cardTap.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                        clip: true

                        GlassFill {
                            id: cardGlass
                            anchors.fill: parent
                            radius: parent.radius
                            tintColor: ThemeBackend.surface0
                            tintAmount: 0.22
                            press: cardTap.pressed ? 0.7 : (cardHover.hovered ? 0.25 : 0)
                        }

                        // Ongoing: a soft fill showing how far into the event we are.
                        Rectangle {
                            visible: row.ongoing
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: row.ongoing ? parent.width * Math.min(1, (GCal.now - row.ev.start) / Math.max(1, row.ev.end - row.ev.start)) : 0
                            color: Qt.alpha(row.tone, 0.14)
                            Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            id: bar
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(7)
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(4)
                            height: (parent.height - root.s(16)) * row.enter
                            radius: width / 2
                            color: row.tone
                        }

                        ColumnLayout {
                            anchors.left: bar.right
                            anchors.leftMargin: root.s(9)
                            anchors.right: parent.right
                            anchors.rightMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(2)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(6)
                                Text {
                                    Layout.fillWidth: true
                                    text: row.isHeader ? "" : (row.ev.title || GCal.tr("(No title)", "(Sans titre)"))
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Black
                                    font.pixelSize: root.s(12.5)
                                    font.strikeout: !row.isHeader && row.ev.rsvp === "declined"
                                    color: ThemeBackend.text
                                }
                                Text {
                                    visible: !row.isHeader && !!row.ev.meet
                                    text: GCal.icon.video
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: root.s(13)
                                    color: row.tone
                                }
                                Text {
                                    visible: !row.isHeader && row.ev.pending
                                    text: GCal.icon.sync
                                    font.family: ThemeBackend.iconFont
                                    font.pixelSize: root.s(11)
                                    color: ThemeBackend.overlay1
                                    RotationAnimation on rotation { running: parent.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 1200 }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.isHeader ? "" : (GCal.fmtRange(row.ev) + (row.ev.location ? "  ·  " + row.ev.location : ""))
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: root.s(10.5)
                                color: row.ongoing ? Qt.tint(row.tone, Qt.alpha(ThemeBackend.text, 0.4)) : ThemeBackend.overlay1
                            }
                        }

                        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: cardTap; onTapped: GCal.openAgenda("day", new Date(row.ev.start), row.ev.id) }
                    }
                }
            }
        }

        // Sync status: offline / pending edits / error, shown only when something needs attention.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: statusText.text !== "" ? root.s(18) : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            clip: true
            Text {
                id: statusText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: GCal.status === "offline" ? GCal.icon.offline + "  " + GCal.tr("Offline · showing saved events", "Hors ligne · événements en cache")
                    : GCal.pending > 0 ? GCal.icon.sync + "  " + GCal.tr("%1 change(s) waiting to sync", "%1 modification(s) en attente").arg(GCal.pending)
                    : GCal.status === "error" ? GCal.icon.alert + "  " + GCal.error : ""
                elide: Text.ElideRight
                width: parent.width
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: root.s(10.5)
                color: GCal.status === "error" ? ThemeBackend.red : ThemeBackend.overlay1
            }
        }
    }
}
