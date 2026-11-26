import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Event card shown next to the clicked event. Placed from its real height, kept filled while it fades out.
Item {
    id: root
    required property Item agenda
    property var ev: null
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    readonly property bool open: !!ev
    function s(v) { return Scaler.s(v); }

    // Last opened event: keeps the card content during the close animation.
    property var shown: null
    onEvChanged: if (ev) {
        shown = ev;
        generation++;
        Qt.callLater(() => { if (root.open) closeButton.forceActiveFocus(); });
    }

    readonly property var live: shown ? (GCal.find(shown.id) || shown) : null
    readonly property color tone: live ? GCal.colorOf(live) : ThemeBackend.blue
    readonly property var cal: live ? GCal.calendarMap[live.calendarId] : null
    readonly property var me: live && live.attendees ? live.attendees.find(a => a.self) : null
    readonly property bool canRsvp: !!me && !(live && live.organizerSelf) && cal && cal.writable

    readonly property real pad: s(16)
    readonly property real gutter: s(12)
    width: Math.min(s(360), parent ? parent.width - gutter * 2 : s(360))
    implicitHeight: content.implicitHeight + pad * 2
    height: Math.min(implicitHeight, parent ? parent.height - gutter * 2 : implicitHeight)

    // Right of the event, or left when it does not fit; vertically clamped with the real height.
    x: {
        const W = parent ? parent.width : 0;
        let px = anchorRect.x + anchorRect.width + s(8);
        if (px + width > W - gutter) px = anchorRect.x - width - s(8);
        return Math.max(gutter, Math.min(W - width - gutter, px));
    }
    y: {
        const H = parent ? parent.height : 0;
        return Math.max(gutter, Math.min(H - height - gutter, anchorRect.y - s(8)));
    }
    readonly property bool onLeft: x + width <= anchorRect.x
    transformOrigin: onLeft ? Item.TopRight : Item.TopLeft

    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: root.open ? 220 : 140; easing.type: Easing.OutCubic } }
    visible: progress > 0.01
    enabled: open
    opacity: progress
    scale: GCal.reducedMotion ? 1 : 0.96 + 0.04 * progress
    onVisibleChanged: if (!visible && !open) shown = null

    property int generation: 0

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Math.min(ThemeBackend.borderRadius, root.s(18))
        color: ThemeBackend.base
        border.width: 1
        border.color: ThemeBackend.surface1
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: root.pad
            contentHeight: content.implicitHeight
            interactive: contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: content
                width: flick.width
                spacing: root.s(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(10)
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: root.s(6)
                        Layout.preferredWidth: root.s(10); Layout.preferredHeight: root.s(10)
                        radius: root.s(3)
                        color: root.tone
                    }
                    Text {
                        id: title
                        Layout.fillWidth: true
                        text: root.live ? (root.live.title || GCal.tr("(No title)", "(Sans titre)")) : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: root.s(17)
                        color: ThemeBackend.text
                    }
                    IconButton {
                        id: closeButton
                        action_highlight: activeFocus
                        Accessible.role: Accessible.Button
                        Accessible.name: GCal.tr("Close event details", "Fermer les détails de l’événement")
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.s(26); Layout.preferredHeight: root.s(26)
                        size: root.s(26); cornerRadius: root.s(8)
                        buttonIcon: GCal.icon.close; iconFontSize: root.s(13)
                        accentColor: "transparent"
                        textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay1
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
                            font.family: ThemeBackend.fontFamily; font.weight: Font.DemiBold; font.pixelSize: root.s(11)
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
                                    color: ThemeBackend.surface0
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
                            font.family: ThemeBackend.fontFamily; font.weight: Font.DemiBold; font.pixelSize: root.s(11)
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
                        color: ThemeBackend.mantle
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
