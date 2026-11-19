import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Side sheet to create or edit an event. Slides in from the right, fields cascade in, pickers expand inline.
Item {
    id: root
    required property Item agenda
    property var draft: null                  // set by the agenda; null = closed
    readonly property bool open: !!draft
    readonly property bool isNew: !!draft && !draft.id
    function s(v) { return Scaler.s(v); }

    // Working copy.
    property string title: ""
    property string location: ""
    property string description: ""
    property string calendarId: ""
    property bool allDay: false
    property double start: 0
    property double end: 0
    property string colorId: ""
    property var recurrence: []
    property bool remindDefault: true
    property var reminders: []
    property bool addMeet: false
    property string transparency: "opaque"
    property string picker: ""                // startDate | startTime | endDate | endTime | ""
    property int generation: 0
    property bool shaking: false

    readonly property color tone: colorId && GCal.colors[colorId] ? GCal.colors[colorId] : (GCal.calendarMap[calendarId] ? GCal.calendarMap[calendarId].color : agenda.accent)
    readonly property var cal: GCal.calendarMap[calendarId] || null

    onDraftChanged: if (draft) load()
    property bool loading: false
    function load() {
        loading = true;
        const d = root.draft;
        title = d.title || "";
        location = d.location || "";
        description = d.description || "";
        calendarId = d.calendarId || GCal.defaultCalendar;
        allDay = !!d.allDay;
        start = d.start;
        end = d.end;
        colorId = d.colorId || "";
        recurrence = (d.recurrence || []).slice();
        const r = d.reminders || { useDefault: true, overrides: [] };
        remindDefault = r.useDefault !== false;
        reminders = (r.overrides || []).slice();
        addMeet = false;
        transparency = d.transparency || "opaque";
        picker = "";
        loading = false;
        allDayToggle.checked = allDay;
        meetToggle.checked = false;
        titleInput.text = title;
        locationInput.text = location;
        descInput.text = description;
        generation++;
        Qt.callLater(() => titleInput.forceInputFocus());
    }

    function dayOf(ms) { return GCal.startOfDay(ms); }
    function minutesOf(ms) { const d = new Date(ms); return d.getHours() * 60 + d.getMinutes(); }
    function setStart(ms) { const length = end - start; start = ms; end = ms + Math.max(allDay ? 86400000 : 15 * 60000, length); }
    function setEnd(ms) { end = Math.max(ms, start + (allDay ? 86400000 : 15 * 60000)); }
    function combine(day, minutes) { const d = new Date(day); return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, minutes).getTime(); }
    onAllDayChanged: {
        if (!open || loading) return;
        if (allDay) { start = dayOf(start).getTime(); end = Math.max(GCal.addDays(dayOf(end - 1), 1).getTime(), start + 86400000); }
        else { start = combine(start, 9 * 60); end = start + 3600000; }
    }

    function payload() {
        const p = {
            calendarId: root.isNew ? root.calendarId : root.draft.calendarId,
            title: root.title.trim(), location: root.location, description: root.description,
            allDay: root.allDay, start: root.start, end: root.end, colorId: root.colorId,
            reminders: { useDefault: root.remindDefault, overrides: root.reminders },
            transparency: root.transparency
        };
        if (!root.draft.recurringEventId || root.isNew) p.recurrence = root.recurrence;
        if (root.addMeet) p.addMeet = true;
        if (!root.isNew) {
            p.id = root.draft.id;
            p.recurringEventId = root.draft.recurringEventId || "";
            p.originalStart = root.draft.start;
            if (root.calendarId !== root.draft.calendarId) p.moveTo = root.calendarId;
        }
        return p;
    }
    function save() {
        if (!root.calendarId) { shake.restart(); return; }
        root.agenda.saveDraft(root.payload(), root.draft, root.recurrence);
    }

    // Backdrop.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.crust, Math.max(0, Math.min(1, 0.35 * sheet.progress)))
        visible: sheet.progress > 0.01
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.agenda.closeEditor() }
    }

    Rectangle {
        id: sheet
        property real progress: root.open ? 1 : 0
        Behavior on progress { NumberAnimation { duration: root.open ? 560 : 300; easing.type: root.open ? Easing.OutExpo : Easing.InCubic } }
        visible: progress > 0.01
        width: Math.min(root.s(460), parent.width - root.s(40))
        height: parent.height - root.s(16)
        y: root.s(8)
        x: parent.width - (width + root.s(8)) * progress
        radius: Math.min(ThemeBackend.borderRadius + root.s(4), root.s(22))
        color: ThemeBackend.base
        border.width: 1
        border.color: Qt.alpha(root.tone, 0.4)
        Behavior on border.color { ColorAnimation { duration: 300 } }
        clip: true
        MouseArea { anchors.fill: parent }   // swallow clicks

        transform: Translate {
            id: shakeT
            x: 0
        }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeT; property: "x"; to: -root.s(10); duration: 60 }
            NumberAnimation { target: shakeT; property: "x"; to: root.s(8); duration: 80 }
            NumberAnimation { target: shakeT; property: "x"; to: -root.s(4); duration: 80 }
            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 120; easing.type: Easing.OutBack }
        }

        Rectangle {
            width: parent.width; height: root.s(120)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.tone, 0.14) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // Header.
        RowLayout {
            id: head
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.s(20)
            spacing: root.s(10)
            Rectangle {
                Layout.preferredWidth: root.s(12); Layout.preferredHeight: root.s(12)
                radius: width / 2
                color: root.tone
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            Text {
                Layout.fillWidth: true
                text: (root.isNew ? GCal.tr("New event", "Nouvel événement") : GCal.tr("Edit event", "Modifier l'événement")).toUpperCase()
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Black
                font.pixelSize: root.s(13)
                font.letterSpacing: root.s(0.6)
                color: ThemeBackend.subtext0
            }
            IconButton {
                Layout.preferredWidth: root.s(30); Layout.preferredHeight: root.s(30)
                size: root.s(30); cornerRadius: root.s(9)
                buttonIcon: GCal.icon.close; iconFontSize: root.s(14)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                onClicked: root.agenda.closeEditor()
            }
        }

        Flickable {
            id: scroller
            anchors.top: head.bottom
            anchors.topMargin: root.s(14)
            anchors.bottom: footer.top
            anchors.bottomMargin: root.s(10)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.s(20)
            anchors.rightMargin: root.s(20)
            contentHeight: form.implicitHeight + root.s(10)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: form
                width: scroller.width
                spacing: root.s(14)

                GCalReveal { generation: root.generation; index: 0
                    implicitHeight: root.s(46)
                    Input {
                        id: titleInput
                        anchors.fill: parent
                        placeholderText: GCal.tr("Add a title", "Ajouter un titre")
                        fontPixelSize: root.s(17)
                        cornerRadius: root.s(12)
                        accentColor: root.tone
                        onTextEdited: (t) => root.title = t
                        onAccepted: root.save()
                    }
                }

                // Calendar.
                GCalReveal { generation: root.generation; index: 1
                    visible: GCal.writableCalendars.length > 1
                    implicitHeight: calFlow.implicitHeight
                    Flow {
                        id: calFlow
                        width: parent.width
                        spacing: root.s(6)
                        Repeater {
                            model: GCal.writableCalendars
                            GCalChip {
                                required property var modelData
                                text: modelData.name
                                dot: modelData.color
                                selected: root.calendarId === modelData.id
                                accent: modelData.color
                                onClicked: root.calendarId = modelData.id
                            }
                        }
                    }
                }

                // When.
                GCalReveal { generation: root.generation; index: 2
                    implicitHeight: whenCol.implicitHeight
                    ColumnLayout {
                        id: whenCol
                        width: parent.width
                        spacing: root.s(8)
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: GCal.icon.clock + "  " + GCal.tr("When", "Quand")
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                                color: ThemeBackend.subtext0
                            }
                            Toggle {
                                id: allDayToggle
                                buttonText: GCal.tr("All day", "Journée entière")
                                checked: root.allDay
                                accentColor: root.tone
                                textFontSize: root.s(11.5)
                                trackWidth: root.s(38); trackHeight: root.s(20)
                                onToggled: (c) => root.allDay = c
                            }
                        }
                        Repeater {
                            model: ["start", "end"]
                            ColumnLayout {
                                id: whenRow
                                required property string modelData
                                readonly property bool isStart: modelData === "start"
                                readonly property double value: isStart ? root.start : (root.allDay ? root.end - 86400000 : root.end)
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(6)
                                    Text {
                                        Layout.preferredWidth: root.s(46)
                                        text: whenRow.isStart ? GCal.tr("From", "Du") : GCal.tr("To", "Au")
                                        font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11.5)
                                        color: ThemeBackend.overlay1
                                    }
                                    GCalFieldButton {
                                        Layout.fillWidth: true
                                        text: new Date(whenRow.value).toLocaleDateString(GCal.locale, "ddd d MMMM yyyy")
                                        active: root.picker === whenRow.modelData + "Date"
                                        accent: root.tone
                                        onClicked: root.picker = active ? "" : whenRow.modelData + "Date"
                                    }
                                    GCalFieldButton {
                                        visible: !root.allDay
                                        Layout.preferredWidth: root.s(96)
                                        text: GCal.fmtTime(whenRow.value)
                                        active: root.picker === whenRow.modelData + "Time"
                                        accent: root.tone
                                        onClicked: root.picker = active ? "" : whenRow.modelData + "Time"
                                        onWheelStep: (dir) => {
                                            const step = dir * 15 * 60000;
                                            if (whenRow.isStart) root.setStart(root.start + step); else root.setEnd(root.end + step);
                                        }
                                    }
                                }
                                // Inline date picker.
                                Item {
                                    Layout.fillWidth: true
                                    readonly property bool open: root.picker === whenRow.modelData + "Date"
                                    Layout.preferredHeight: open ? mini.implicitHeight + root.s(10) : 0
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                                    clip: true
                                    opacity: open ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 240 } }
                                    GCalMiniMonth {
                                        id: mini
                                        y: root.s(8)
                                        x: root.s(52)
                                        width: Math.min(parent.width - root.s(52), root.s(260))
                                        selected: GCal.startOfDay(whenRow.value)
                                        accent: root.tone
                                        showDots: false
                                        onPicked: (d) => {
                                            const minutes = root.minutesOf(whenRow.value);
                                            if (whenRow.isStart) root.setStart(root.allDay ? d.getTime() : root.combine(d, minutes));
                                            else root.setEnd(root.allDay ? GCal.addDays(d, 1).getTime() : root.combine(d, minutes));
                                            root.picker = "";
                                        }
                                    }
                                }
                                GCalTimeList {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: root.s(52)
                                    Layout.preferredHeight: implicitHeight
                                    open: root.picker === whenRow.modelData + "Time"
                                    minutes: Math.round(root.minutesOf(whenRow.value) / 15) * 15
                                    relativeTo: whenRow.isStart || !GCal.sameDay(new Date(root.start), new Date(root.end)) ? -1 : root.minutesOf(root.start)
                                    accent: root.tone
                                    onPicked: (m) => {
                                        if (whenRow.isStart) root.setStart(root.combine(root.start, m)); else root.setEnd(root.combine(root.end, m));
                                        root.picker = "";
                                    }
                                }
                            }
                        }
                    }
                }

                // Repeat.
                GCalReveal { generation: root.generation; index: 3
                    visible: root.isNew || !root.draft || !root.draft.recurringEventId || root.agenda.editScopeAll
                    implicitHeight: repeatCol.implicitHeight
                    ColumnLayout {
                        id: repeatCol
                        width: parent.width
                        spacing: root.s(8)
                        Text {
                            text: GCal.icon.repeat + "  " + GCal.tr("Repeat", "Répétition")
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                            color: ThemeBackend.subtext0
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: root.s(6)
                            Repeater {
                                model: GCal.repeatPresets
                                GCalChip {
                                    required property var modelData
                                    text: modelData.label
                                    accent: root.tone
                                    selected: GCal.presetOf(root.recurrence) === modelData.id
                                    onClicked: root.recurrence = modelData.rule ? [modelData.rule] : []
                                }
                            }
                            GCalChip {
                                visible: GCal.presetOf(root.recurrence) === "custom"
                                text: GCal.describeRule(root.recurrence)
                                accent: root.tone
                                selected: true
                            }
                        }
                    }
                }

                // Reminders.
                GCalReveal { generation: root.generation; index: 4
                    implicitHeight: remCol.implicitHeight
                    ColumnLayout {
                        id: remCol
                        width: parent.width
                        spacing: root.s(8)
                        Text {
                            text: GCal.icon.bell + "  " + GCal.tr("Reminders", "Rappels")
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                            color: ThemeBackend.subtext0
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: root.s(6)
                            GCalChip {
                                text: GCal.tr("Calendar default", "Par défaut") + (root.cal && root.cal.defaultReminders && root.cal.defaultReminders.length ? " (" + root.cal.defaultReminders.map(m => GCal.reminderLabel(m)).join(", ") + ")" : "")
                                accent: root.tone
                                selected: root.remindDefault
                                onClicked: { root.remindDefault = true; root.reminders = []; }
                            }
                            Repeater {
                                model: [0, 5, 10, 15, 30, 60, 120, 1440]
                                GCalChip {
                                    required property int modelData
                                    text: GCal.reminderLabel(modelData)
                                    accent: root.tone
                                    selected: !root.remindDefault && root.reminders.indexOf(modelData) !== -1
                                    onClicked: {
                                        const list = root.remindDefault ? [] : root.reminders.slice();
                                        const at = list.indexOf(modelData);
                                        if (at === -1) { if (list.length < 5) list.push(modelData); } else list.splice(at, 1);
                                        root.remindDefault = false;
                                        root.reminders = list.sort((a, b) => a - b);
                                    }
                                }
                            }
                        }
                    }
                }

                // Where.
                GCalReveal { generation: root.generation; index: 5
                    implicitHeight: root.s(36)
                    Input {
                        id: locationInput
                        anchors.fill: parent
                        leadingIcon: GCal.icon.place
                        placeholderText: GCal.tr("Add a location", "Ajouter un lieu")
                        fontPixelSize: root.s(12.5)
                        cornerRadius: root.s(11)
                        accentColor: root.tone
                        onTextEdited: (t) => root.location = t
                    }
                }

                // Video call.
                GCalReveal { generation: root.generation; index: 6
                    visible: !root.draft || !root.draft.meet
                    implicitHeight: root.s(32)
                    Toggle {
                        id: meetToggle
                        anchors.left: parent.left
                        buttonText: GCal.tr("Add a Google Meet link", "Ajouter un lien Google Meet")
                        buttonIcon: GCal.icon.video
                        checked: root.addMeet
                        accentColor: root.tone
                        textFontSize: root.s(11.5)
                        trackWidth: root.s(38); trackHeight: root.s(20)
                        onToggled: (c) => root.addMeet = c
                    }
                }

                // Colour.
                GCalReveal { generation: root.generation; index: 7
                    implicitHeight: colorCol.implicitHeight
                    ColumnLayout {
                        id: colorCol
                        width: parent.width
                        spacing: root.s(8)
                        Text {
                            text: GCal.icon.palette + "  " + GCal.tr("Colour", "Couleur")
                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                            color: ThemeBackend.subtext0
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: root.s(8)
                            Repeater {
                                model: [""].concat(Object.keys(GCal.colors).sort((a, b) => a - b))
                                Item {
                                    id: swatch
                                    required property string modelData
                                    readonly property color c: modelData === "" ? (root.cal ? root.cal.color : root.agenda.accent) : GCal.colors[modelData]
                                    readonly property bool chosen: root.colorId === modelData
                                    width: root.s(26); height: width
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width; height: width; radius: width / 2
                                        color: "transparent"
                                        border.width: root.s(2)
                                        border.color: swatch.c
                                        scale: swatch.chosen ? 1.15 : 0.6
                                        opacity: swatch.chosen ? 1 : 0
                                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: root.s(18); height: width; radius: width / 2
                                        color: swatch.c
                                        scale: swMa.pressed ? 0.8 : (swMa.containsMouse ? 1.12 : 1)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: swatch.modelData === ""
                                            text: "A"
                                            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(9)
                                            color: GCal.readableOn(swatch.c)
                                        }
                                    }
                                    MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.colorId = swatch.modelData }
                                }
                            }
                        }
                    }
                }

                // Busy / free.
                GCalReveal { generation: root.generation; index: 8
                    implicitHeight: root.s(32)
                    GCalSegmented {
                        anchors.fill: parent
                        accent: root.tone
                        options: [{ id: "opaque", label: GCal.tr("Busy", "Occupé") }, { id: "transparent", label: GCal.tr("Free", "Disponible") }]
                        current: root.transparency
                        onSelected: (id) => root.transparency = id
                    }
                }

                // Notes.
                GCalReveal { generation: root.generation; index: 9
                    implicitHeight: root.s(120)
                    Input {
                        id: descInput
                        anchors.fill: parent
                        multiLine: true
                        placeholderText: GCal.tr("Description, notes, links…", "Description, notes, liens…")
                        fontPixelSize: root.s(12)
                        cornerRadius: root.s(12)
                        accentColor: root.tone
                        onTextEdited: (t) => root.description = t
                    }
                }
            }
        }

        RowLayout {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.s(18)
            height: root.s(38)
            spacing: root.s(8)
            IconButton {
                visible: !root.isNew
                Layout.preferredWidth: root.s(38); Layout.preferredHeight: root.s(38)
                size: root.s(38); cornerRadius: root.s(12)
                buttonIcon: GCal.icon.trash; iconFontSize: root.s(15)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                onClicked: root.agenda.deleteEvent(root.draft)
            }
            Item { Layout.fillWidth: true }
            ClickButton {
                Layout.preferredHeight: root.s(38)
                Layout.preferredWidth: implicitWidth + root.s(8)
                buttonText: GCal.tr("Cancel", "Annuler")
                textFontSize: root.s(12); cornerRadius: root.s(12)
                accentColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                onClicked: root.agenda.closeEditor()
            }
            ClickButton {
                Layout.preferredHeight: root.s(38)
                Layout.preferredWidth: implicitWidth + root.s(16)
                buttonText: root.isNew ? GCal.tr("Create", "Créer") : GCal.tr("Save", "Enregistrer")
                buttonIcon: GCal.icon.check
                textFontSize: root.s(12); iconFontSize: root.s(14); cornerRadius: root.s(12)
                accentColor: root.tone; textColor: GCal.readableOn(root.tone)
                onClicked: root.save()
            }
        }
    }
}
