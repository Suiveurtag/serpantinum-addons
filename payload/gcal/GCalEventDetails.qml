import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Event card shown next to the clicked event: grows out of it (scale from the event side), rows cascade in.
Item {
    id: root
    required property Item agenda
    property var ev: null
    readonly property bool open: !!ev
    function s(v) { return Scaler.s(v); }

    readonly property var live: ev ? (GCal.find(ev.id) || ev) : null
    readonly property color tone: live ? GCal.colorOf(live) : ThemeBackend.blue
    readonly property var cal: live ? GCal.calendarMap[live.calendarId] : null
    readonly property var me: live && live.attendees ? live.attendees.find(a => a.self) : null
    readonly property bool canRsvp: !!me && !(live && live.organizerSelf) && cal && cal.writable

    width: s(380)
    implicitHeight: content.implicitHeight + s(36)
    height: Math.min(implicitHeight, parent ? parent.height - s(24) : implicitHeight)

    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: root.open ? 440 : 200; easing.type: root.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.15 } }
    visible: progress > 0.01
    opacity: Math.min(1, progress)
    scale: 0.88 + 0.12 * progress
    property real originX: 0
    property real originY: 0
    transformOrigin: Item.Center
    transform: Translate { x: root.originX * (1 - root.progress) * 0.25; y: root.originY * (1 - root.progress) * 0.25 }

    // Row cascade, replayed on each opened event.
    property int generation: 0
    onEvChanged: if (ev) generation++
    function stagger(i) { return i; }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Math.min(ThemeBackend.borderRadius + root.s(4), root.s(22))
        color: ThemeBackend.base
        border.width: 1
        border.color: Qt.alpha(root.tone, 0.45)
        clip: true

        Rectangle {
            width: parent.width
            height: root.s(6)
            color: root.tone
            Behavior on color { ColorAnimation { duration: 300 } }
        }
        // Soft tinted glow at the top.
        Rectangle {
            width: parent.width; height: root.s(110)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.tone, 0.16) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: root.s(18)
            anchors.topMargin: root.s(22)
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: content
                width: parent.width
                spacing: root.s(12)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(8)
                    GCalReveal { generation: root.generation; index: 0
                        Layout.fillWidth: true
                        implicitHeight: title.implicitHeight
                        Text {
                            id: title
                            width: parent.width
                            text: root.live ? (root.live.title || GCal.tr("(No title)", "(Sans titre)")) : ""
                            wrapMode: Text.WordWrap
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: root.s(19)
                            color: ThemeBackend.text
                        }
                    }
                    IconButton {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                        size: root.s(28); cornerRadius: root.s(9)
                        buttonIcon: GCal.icon.close; iconFontSize: root.s(14)
                        accentColor: ThemeBackend.surface0
                        textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                        onClicked: root.agenda.closeDetails()
                    }
                }

                GCalInfoRow { generation: root.generation; index: 1
                    icon: GCal.icon.clock; tone: root.tone
                    text: root.live ? (root.live.allDay ? new Date(root.live.start).toLocaleDateString(GCal.locale, "dddd d MMMM yyyy") : new Date(root.live.start).toLocaleDateString(GCal.locale, "dddd d MMMM")) : ""
                    sub: root.live ? GCal.fmtRange(root.live) + (root.live.allDay ? "" : "  ·  " + GCal.fmtDuration((root.live.end - root.live.start) / 60000)) : ""
                }
                GCalInfoRow { generation: root.generation; index: 2
                    visible: !!root.live && (root.live.recurrence || []).length > 0 || (!!root.live && !!root.live.recurringEventId)
                    icon: GCal.icon.repeat; tone: root.tone
                    text: root.live ? (GCal.describeRule(root.live.recurrence) || GCal.tr("Recurring event", "Événement récurrent")) : ""
                }
                GCalInfoRow { generation: root.generation; index: 3
                    visible: !!root.live && !!root.live.location
                    icon: GCal.icon.place; tone: root.tone
                    text: root.live ? root.live.location : ""
                    sub: GCal.tr("Open in maps", "Ouvrir dans Maps")
                    clickable: true
                    onActivated: Qt.openUrlExternally("https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(root.live.location))
                }
                GCalReveal { generation: root.generation; index: 4
                    visible: !!root.live && !!root.live.meet
                    Layout.fillWidth: true
                    implicitHeight: root.s(38)
                    ClickButton {
                        anchors.fill: parent
                        buttonText: root.live && root.live.meet.indexOf("zoom") !== -1 ? GCal.tr("Join Zoom", "Rejoindre Zoom")
                                  : root.live && root.live.meet.indexOf("teams") !== -1 ? GCal.tr("Join Teams", "Rejoindre Teams")
                                  : GCal.tr("Join video call", "Rejoindre la visio")
                        buttonIcon: GCal.icon.video
                        textFontSize: root.s(12.5); iconFontSize: root.s(16)
                        cornerRadius: root.s(12)
                        accentColor: root.tone
                        textColor: GCal.readableOn(root.tone)
                        onClicked: Qt.openUrlExternally(root.live.meet)
                    }
                }
                GCalInfoRow { generation: root.generation; index: 5
                    icon: GCal.icon.calendar; tone: root.cal ? root.cal.color : root.tone
                    text: root.cal ? root.cal.name : ""
                    sub: root.live && root.live.organizer && !root.live.organizerSelf ? GCal.tr("Organised by %1", "Organisé par %1").arg(root.live.organizer) : ""
                }
                GCalInfoRow { generation: root.generation; index: 6
                    visible: !!root.live && root.live.source === "google"
                    icon: GCal.icon.bell; tone: root.tone
                    text: {
                        if (!root.live) return "";
                        const r = root.live.reminders || {};
                        const list = r.useDefault ? (root.cal ? root.cal.defaultReminders || [] : []) : (r.overrides || []);
                        return list.length ? list.map(m => GCal.reminderLabel(m)).join(", ") + GCal.tr(" before", " avant") : GCal.tr("No reminder", "Aucun rappel");
                    }
                }

                // Guests.
                GCalReveal { generation: root.generation; index: 7
                    visible: !!root.live && (root.live.attendees || []).length > 0
                    Layout.fillWidth: true
                    implicitHeight: guests.implicitHeight
                    ColumnLayout {
                        id: guests
                        width: parent.width
                        spacing: root.s(4)
                        Text {
                            text: GCal.icon.people + "  " + GCal.tr("%1 guests", "%1 invités").arg(root.live ? (root.live.attendees || []).length : 0)
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11.5)
                            color: ThemeBackend.subtext0
                        }
                        Repeater {
                            model: root.live ? (root.live.attendees || []).slice(0, 8) : []
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Rectangle {
                                    Layout.preferredWidth: root.s(22); Layout.preferredHeight: root.s(22)
                                    radius: width / 2
                                    color: Qt.alpha(root.tone, 0.25)
                                    Text {
                                        anchors.centerIn: parent
                                        text: (modelData.name || modelData.email || "?").charAt(0).toUpperCase()
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(10)
                                        color: ThemeBackend.text
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.bottom: parent.bottom
                                        width: root.s(9); height: width; radius: width / 2
                                        border.width: root.s(1.5); border.color: ThemeBackend.base
                                        color: modelData.status === "accepted" ? ThemeBackend.green : modelData.status === "declined" ? ThemeBackend.red : modelData.status === "tentative" ? ThemeBackend.yellow : ThemeBackend.overlay0
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: (modelData.name || modelData.email) + (modelData.organizer ? GCal.tr("  · organiser", "  · organisateur") : "") + (modelData.self ? GCal.tr("  · you", "  · toi") : "")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                    color: ThemeBackend.text
                                }
                            }
                        }
                    }
                }

                // RSVP: a segmented control whose highlight slides to the current answer.
                GCalReveal { generation: root.generation; index: 8
                    visible: root.canRsvp
                    Layout.fillWidth: true
                    implicitHeight: root.s(64)
                    ColumnLayout {
                        width: parent.width
                        spacing: root.s(6)
                        Text {
                            text: GCal.tr("Going?", "Tu participes ?")
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11.5)
                            color: ThemeBackend.subtext0
                        }
                        GCalSegmented {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(32)
                            accent: root.me && root.me.status === "declined" ? ThemeBackend.red : root.me && root.me.status === "tentative" ? ThemeBackend.yellow : ThemeBackend.green
                            options: [{ id: "accepted", label: GCal.tr("Yes", "Oui") }, { id: "tentative", label: GCal.tr("Maybe", "Peut-être") }, { id: "declined", label: GCal.tr("No", "Non") }]
                            current: root.me ? root.me.status : ""
                            onSelected: (id) => GCal.rsvp(root.live, id)
                        }
                    }
                }

                GCalReveal { generation: root.generation; index: 9
                    visible: !!root.live && !!root.live.description
                    Layout.fillWidth: true
                    implicitHeight: desc.implicitHeight + root.s(20)
                    Rectangle {
                        anchors.fill: parent
                        radius: root.s(12)
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)
                        Text {
                            id: desc
                            anchors.fill: parent
                            anchors.margins: root.s(10)
                            text: root.live ? GCal.richText(root.live.description) : ""
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            linkColor: root.tone
                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11.5)
                            color: ThemeBackend.subtext1
                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                            HoverHandler { cursorShape: desc.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }
                    }
                }

                GCalReveal { generation: root.generation; index: 10
                    visible: !!root.live && (root.live.editable || GCal.writableCalendars.length > 0 || !!root.live.htmlLink)
                    Layout.fillWidth: true
                    implicitHeight: root.s(34)
                    RowLayout {
                        anchors.fill: parent
                        spacing: root.s(6)
                        ClickButton {
                            visible: !!root.live && root.live.editable
                            Layout.fillWidth: true; Layout.fillHeight: true
                            buttonText: GCal.tr("Edit", "Modifier"); buttonIcon: GCal.icon.edit
                            textFontSize: root.s(11.5); iconFontSize: root.s(13); cornerRadius: root.s(10)
                            accentColor: root.agenda.accent; textColor: ThemeBackend.base
                            onClicked: root.agenda.editEvent(root.live)
                        }
                        ClickButton {
                            visible: GCal.writableCalendars.length > 0
                            Layout.fillWidth: true; Layout.fillHeight: true
                            buttonText: GCal.tr("Duplicate", "Dupliquer"); buttonIcon: GCal.icon.copy
                            textFontSize: root.s(11.5); iconFontSize: root.s(13); cornerRadius: root.s(10)
                            accentColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                            onClicked: root.agenda.duplicateEvent(root.live)
                        }
                        IconButton {
                            visible: !!root.live && !!root.live.htmlLink
                            Layout.preferredWidth: root.s(34); Layout.preferredHeight: root.s(34)
                            size: root.s(34); cornerRadius: root.s(10)
                            buttonIcon: GCal.icon.open; iconFontSize: root.s(14)
                            accentColor: ThemeBackend.surface0
                            textColor: isHoveredOrHighlighted ? root.agenda.accent : ThemeBackend.overlay1
                            onClicked: Qt.openUrlExternally(root.live.htmlLink)
                        }
                        IconButton {
                            visible: !!root.live && root.live.editable
                            Layout.preferredWidth: root.s(34); Layout.preferredHeight: root.s(34)
                            size: root.s(34); cornerRadius: root.s(10)
                            buttonIcon: GCal.icon.trash; iconFontSize: root.s(14)
                            accentColor: ThemeBackend.surface0
                            textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                            onClicked: root.agenda.deleteEvent(root.live)
                        }
                    }
                }
            }
        }
    }
}
