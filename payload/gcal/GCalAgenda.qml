import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// The calendar app that the clock panel morphs into: header, sidebar (mini month, calendars, account),
// month / week / day / list views, event card, editor, accounts sheet and toasts.
FocusScope {
    id: app
    property real reveal: 1          // 0 → 1 while the panel morphs in
    property bool shown: false       // fully open
    function s(v) { return Scaler.s(v); }
    readonly property bool compact: width < s(1140)
    readonly property bool narrow: width < s(900)
    property bool sidebarOpen: false
    function step(i) { return Math.max(0, Math.min(1, app.reveal * 1.6 - i * 0.12)); }

    readonly property color accent: {
        const h = new Date(GCal.now).getHours();
        if (h >= 5 && h < 12) return ThemeBackend.peach;
        if (h >= 12 && h < 17) return ThemeBackend.sapphire;
        if (h >= 17 && h < 21) return ThemeBackend.mauve;
        return ThemeBackend.blue;
    }

    readonly property string view: GCal.agendaView
    property string query: ""
    property var details: null
    property var editorDraft: null
    property bool editScopeAll: false
    property var scopeRequest: null      // { kind: "update" | "delete", payload, ev, title }
    property var overrides: ({})         // id → { start, end } while a drag edit is being written
    readonly property bool onboarding: !GCal.available
    readonly property bool overlayOpen: !!details || !!editorDraft || !!scopeRequest

    // ------------------------------------------------------------------ navigation

    readonly property var periodStart: view === "month" ? GCal.weekStart(new Date(GCal.focusDate.getFullYear(), GCal.focusDate.getMonth(), 1))
        : view === "week" ? GCal.weekStart(GCal.focusDate) : GCal.startOfDay(GCal.focusDate)
    readonly property var periodEnd: view === "month" ? GCal.addDays(periodStart, 42) : view === "week" ? GCal.addDays(periodStart, 7)
        : view === "day" ? GCal.addDays(periodStart, 1) : GCal.addDays(periodStart, 60)
    onPeriodStartChanged: Qt.callLater(ensurePeriod)
    onPeriodEndChanged: Qt.callLater(ensurePeriod)
    function ensurePeriod() { GCal.ensure(periodStart.getTime(), periodEnd.getTime()); }

    readonly property string title: {
        const d = GCal.focusDate;
        if (app.onboarding) return GCal.tr("Calendar", "Agenda");
        if (app.query.trim()) return GCal.tr("Search", "Recherche");
        if (app.view === "month") return GCal.monthTitle(d);
        if (app.view === "day") return GCal.dayTitle(d) + " " + d.toLocaleDateString(GCal.locale, "d MMMM");
        if (app.view === "list") return GCal.tr("Upcoming", "À venir");
        const a = app.periodStart, b = GCal.addDays(app.periodStart, 6);
        if (a.getFullYear() !== b.getFullYear())
            return a.toLocaleDateString(GCal.locale, "d MMM yyyy") + " – " + b.toLocaleDateString(GCal.locale, "d MMM yyyy");
        return a.getMonth() === b.getMonth()
            ? a.getDate() + " – " + b.toLocaleDateString(GCal.locale, "d MMMM yyyy")
            : a.toLocaleDateString(GCal.locale, "d MMM") + " – " + b.toLocaleDateString(GCal.locale, "d MMM yyyy");
    }

    property real viewOffset: 0
    NumberAnimation {
        id: settleView
        target: app
        property: "viewOffset"
        to: 0
        duration: 185
        easing.type: Easing.OutCubic
    }

    function shift(dir, animate) {
        const d = GCal.focusDate;
        const next = view === "month" ? new Date(d.getFullYear(), d.getMonth() + dir, Math.min(d.getDate(), 28))
            : view === "week" ? GCal.addDays(d, 7 * dir) : view === "day" ? GCal.addDays(d, dir) : GCal.addDays(d, 14 * dir);
        navigate(next, dir, animate);
    }
    function navigate(date, dir, animate = true) {
        if (GCal.sameDay(date, GCal.focusDate)) return;
        const direction = dir || (date > GCal.focusDate ? 1 : -1);
        GCal.focusDate = GCal.startOfDay(date);
        settleView.stop();
        if (animate && !GCal.reducedMotion) {
            viewOffset = app.s(10) * direction;
            settleView.start();
        } else viewOffset = 0;
    }
    function today(animate) { navigate(GCal.today, 0, animate); }
    function setView(v) {
        if (v === view && !query) return;
        searchInput.clear();
        query = "";
        settleView.stop();
        viewOffset = 0;
        GCal.agendaView = v;
    }
    function goTo(date, v) {
        setView(v);
        navigate(date, 0, false);
    }

    // ------------------------------------------------------------------ editing

    function effective(e) {
        const o = overrides[e.id];
        return o ? Object.assign({}, e, { start: o.start, end: o.end }) : e;
    }
    function setOverride(id, start, end) {
        const copy = Object.assign({}, overrides);
        if (start === undefined) delete copy[id]; else copy[id] = { start: start, end: end, at: Date.now() };
        overrides = copy;
    }
    Connections {
        target: GCal
        function onStateChanged() {
            // Drop overrides the backend has caught up with.
            const copy = Object.assign({}, app.overrides);
            let changed = false;
            for (const id in copy) {
                const e = GCal.find(id);
                if (!e || (e.start === copy[id].start && e.end === copy[id].end) || Date.now() - (copy[id].at || 0) > 8000) { delete copy[id]; changed = true; }
            }
            if (changed) app.overrides = copy;
        }
        function onActionFinished(command, result) {
            if (result && result.ok === false && result.error && ["create", "update", "delete", "rsvp"].indexOf(command) !== -1) app.toast(result.error, true);
            else if (result && result.queued) app.toast(GCal.tr("Saved offline · will sync when back online", "Enregistré hors ligne · synchronisé au retour du réseau"));
        }
    }

    function newEvent(start, end, allDay) {
        if (!GCal.writableCalendars.length) { toast(GCal.tr("Connect Google Calendar to create events", "Connecte Google Agenda pour créer des événements"), true); GCal.openSettings(); return; }
        closeDetails();
        editScopeAll = false;
        editorDraft = { calendarId: GCal.defaultCalendar, title: "", allDay: !!allDay, start: start, end: end, reminders: { useDefault: true, overrides: [] }, recurrence: [] };
    }
    function editEvent(ev) {
        closeDetails();
        if (ev.recurringEventId) {
            scopeRequest = { kind: "edit", ev: ev, title: GCal.tr("Edit recurring event", "Modifier un événement récurrent") };
            return;
        }
        editScopeAll = false;
        editorDraft = Object.assign({}, ev);
    }
    function duplicateEvent(ev) {
        closeDetails();
        const copy = Object.assign({}, ev);
        delete copy.id; delete copy.recurringEventId;
        copy.title = ev.title + GCal.tr(" (copy)", " (copie)");
        copy.recurrence = [];
        if (!GCal.calendarMap[copy.calendarId] || !GCal.calendarMap[copy.calendarId].writable) copy.calendarId = GCal.defaultCalendar;
        editScopeAll = false;
        editorDraft = copy;
    }
    function closeEditor() { editorDraft = null; }
    function saveDraft(payload, draft, recurrence) {
        if (!draft.id) {
            GCal.create(payload);
            editorDraft = null;
            toast(GCal.tr("Event created", "Événement créé"));
            return;
        }
        if (draft.recurringEventId) payload.scope = editScopeAll ? "all" : "this";
        GCal.update(payload);
        editorDraft = null;
        toast(GCal.tr("Changes saved", "Modifications enregistrées"));
    }
    function moveEvent(ev, start, end) {
        if (!ev.editable) return;
        setOverride(ev.id, start, end);
        const payload = { id: ev.id, calendarId: ev.calendarId, start: start, end: end, allDay: ev.allDay, recurringEventId: ev.recurringEventId || "", originalStart: ev.start };
        if (ev.recurringEventId) {
            scopeRequest = { kind: "update", ev: ev, payload: payload, title: GCal.tr("Move recurring event", "Déplacer un événement récurrent") };
            return;
        }
        GCal.update(payload);
    }
    function deleteEvent(ev) {
        closeDetails();
        editorDraft = null;
        const payload = { id: ev.id, calendarId: ev.calendarId, recurringEventId: ev.recurringEventId || "" };
        if (ev.recurringEventId) {
            scopeRequest = { kind: "delete", ev: ev, payload: payload, title: GCal.tr("Delete recurring event", "Supprimer un événement récurrent") };
            return;
        }
        GCal.remove(payload);
        const restore = Object.assign({}, ev);
        toast(GCal.tr("Event deleted", "Événement supprimé"), false, GCal.tr("Undo", "Annuler"), () => {
            GCal.create({ calendarId: restore.calendarId, title: restore.title, description: restore.description, location: restore.location,
                          allDay: restore.allDay, start: restore.start, end: restore.end, colorId: restore.colorId, reminders: restore.reminders,
                          recurrence: restore.recurrence || [], transparency: restore.transparency });
        });
    }
    function resolveScope(scope) {
        const r = scopeRequest;
        scopeRequest = null;
        if (!r || !scope) {
            if (r && r.ev) setOverride(r.ev.id);
            return;
        }
        if (r.kind === "edit") {
            editScopeAll = scope === "all";
            editorDraft = Object.assign({}, r.ev);
            return;
        }
        r.payload.scope = scope;
        if (r.kind === "update") GCal.update(r.payload);
        else { GCal.remove(r.payload); toast(GCal.tr("Event deleted", "Événement supprimé")); }
    }

    function showDetails(ev, item) {
        const a = item.mapToItem(app, 0, 0);
        detailsCard.anchorRect = Qt.rect(a.x, a.y, item.width, item.height);
        details = ev;
    }
    function eventItem(item, id) {
        if (!item || !item.visible) return null;
        if (item.ev && item.ev.id === id) return item;
        for (let i = 0; i < item.children.length; ++i) {
            const found = eventItem(item.children[i], id);
            if (found) return found;
        }
        return null;
    }
    function closeDetails() { details = null; }

    // Toast.
    property string toastText: ""
    property bool toastError: false
    property string toastAction: ""
    property var toastCallback: null
    function toast(text, isError, action, cb) {
        toastText = text; toastError = !!isError; toastAction = action || ""; toastCallback = cb || null;
        toastTimer.interval = action ? 6000 : 3200;
        toastBox.open = true;
        toastTimer.restart();
        toastBar.restart();
    }
    Timer { id: toastTimer; onTriggered: toastBox.dismiss() }

    Connections {
        target: GCal
        function onOpenEventIdChanged() { if (GCal.openEventId && app.shown) app.handlePending(); }
        function onGoogleChanged() {
            if (app.shown && GCal.google)
                app.toast(GCal.tr("Google Calendar connected", "Google Agenda connecté"), false);
        }
        function onActionFinished(verb, result) {
            if (app.shown && verb === "connect" && result.cancelled)
                app.toast(GCal.tr("Google sign-in cancelled", "Connexion à Google annulée"), false);
        }
    }

    // Arriving: honour a pending "open this event" / "new event" request.
    onShownChanged: {
        if (!shown) { closeDetails(); editorDraft = null; scopeRequest = null; sidebarOpen = false; return; }
        forceActiveFocus();
        ensurePeriod();
        handlePending();
    }
    function handlePending() {
        const want = GCal.openEventId;
        GCal.openEventId = "";
        if (want && want !== "new" && query) searchInput.clear();
        if (want === "new") {
            const d = GCal.focusDate;
            const start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), Math.max(8, Math.min(20, new Date().getHours() + 1)), 0).getTime();
            newEvent(start, start + 3600000, false);
        } else if (want) {
            Qt.callLater(() => {
                const e = GCal.find(want);
                if (!e || !app.shown) return;
                if (timeGrid.status === Loader.Ready) timeGrid.item.revealEvent(e);
                // Let the target view finish creating its delegates before resolving the event's position.
                Qt.callLater(() => { if (app.shown) showDetails(e, eventItem(viewArea, want) || toolbar); });
            });
        }
    }

    // ------------------------------------------------------------------ keyboard
    // The dashboard's Escape shortcut asks GCal first: Esc closes the topmost overlay before the panel.
    function closeTopOverlay() {
        if (scopeRequest) resolveScope(null);
        else if (editorDraft) closeEditor();
        else if (details) closeDetails();
        else if (sidebarOpen) sidebarOpen = false;
        else return false;
        return true;
    }
    onOverlayOpenChanged: if (!overlayOpen && shown) app.forceActiveFocus()
    Component.onCompleted: GCal.escapeHandler = app.closeTopOverlay
    Component.onDestruction: if (GCal.escapeHandler === app.closeTopOverlay) GCal.escapeHandler = null
    Shortcut { sequence: "Left"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.shift(-1, false) }
    Shortcut { sequence: "Right"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.shift(1, false) }
    Shortcut { sequence: "T"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.today(false) }
    Shortcut { sequence: "N"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: GCal.openEventId = "new" }
    Shortcut { sequence: "M"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.setView("month") }
    Shortcut { sequence: "W"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.setView("week") }
    Shortcut { sequence: "D"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.setView("day") }
    Shortcut { sequence: "L"; enabled: app.shown && !app.overlayOpen && !searchInput.hasFocus; onActivated: app.setView("list") }
    Shortcut { sequence: "/"; enabled: app.shown && !app.onboarding && !app.overlayOpen && !searchInput.hasFocus; onActivated: searchInput.forceInputFocus() }

    // ------------------------------------------------------------------ layout
    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: app.s(22)
        enabled: !app.overlayOpen

        Item {
            id: header
            width: parent.width
            height: toolbar.height + (compactViews.visible ? app.s(42) : 0)
            opacity: app.step(0)
            transform: Translate { y: -app.s(10) * (1 - app.step(0)) }

            RowLayout {
                id: toolbar
                width: parent.width
                height: app.s(44)
                spacing: app.s(app.narrow ? 5 : 8)

                IconButton {
                    Layout.preferredWidth: app.s(36); Layout.preferredHeight: app.s(36)
                    size: app.s(36); cornerRadius: app.s(11)
                    buttonIcon: GCal.icon.back; iconFontSize: app.s(17)
                    accentColor: ThemeBackend.surface0
                    textColor: isHoveredOrHighlighted ? app.accent : ThemeBackend.text
                    action_highlight: activeFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Back to clock", "Retour à l’horloge")
                    onClicked: GCal.closeAgenda()
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.min(implicitWidth + app.s(4),
                        Math.max(app.s(90), toolbar.width - app.s(app.compact ? 330 : 765)))
                    text: app.title
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: app.s(app.narrow ? 17 : 22)
                    font.weight: Font.Black
                    color: ThemeBackend.text
                }
                IconButton {
                    visible: !app.onboarding
                    enabled: !app.query
                    Layout.preferredWidth: app.s(32); Layout.preferredHeight: app.s(32)
                    size: app.s(32); cornerRadius: app.s(10)
                    buttonIcon: GCal.icon.left; iconFontSize: app.s(18)
                    accentColor: ThemeBackend.surface0
                    textColor: isHoveredOrHighlighted ? app.accent : ThemeBackend.text
                    action_highlight: activeFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Previous period", "Période précédente")
                    onClicked: app.shift(-1)
                }
                ClickButton {
                    visible: !app.onboarding
                    enabled: !app.query
                    Layout.preferredHeight: app.s(32); Layout.preferredWidth: implicitWidth
                    buttonText: GCal.tr("Today", "Aujourd'hui")
                    textFontSize: app.s(11.5); cornerRadius: app.s(10)
                    accentColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                    onClicked: app.today()
                }
                IconButton {
                    visible: !app.onboarding
                    enabled: !app.query
                    Layout.preferredWidth: app.s(32); Layout.preferredHeight: app.s(32)
                    size: app.s(32); cornerRadius: app.s(10)
                    buttonIcon: GCal.icon.right; iconFontSize: app.s(18)
                    accentColor: ThemeBackend.surface0
                    textColor: isHoveredOrHighlighted ? app.accent : ThemeBackend.text
                    action_highlight: activeFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Next period", "Période suivante")
                    onClicked: app.shift(1)
                }
                Item { Layout.fillWidth: true }

                LayoutItemProxy {
                    visible: !app.onboarding && !app.compact
                    target: viewSwitcher
                    Layout.preferredWidth: app.s(340)
                    Layout.preferredHeight: app.s(34)
                }

                LayoutItemProxy {
                    visible: !app.onboarding && !app.compact
                    target: searchInput
                    Layout.preferredWidth: app.s(165)
                    Layout.preferredHeight: app.s(34)
                }

                IconButton {
                    visible: !app.onboarding && app.narrow
                    size: app.s(34); cornerRadius: app.s(11)
                    buttonIcon: GCal.icon.calendar; iconFontSize: app.s(16)
                    action_highlight: app.sidebarOpen || activeFocus
                    textColor: ThemeBackend.text
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Calendars", "Agendas")
                    Accessible.checkable: true
                    Accessible.checked: app.sidebarOpen
                    onClicked: app.sidebarOpen = !app.sidebarOpen
                }

                IconButton {
                    visible: GCal.available
                    Layout.preferredWidth: app.s(34); Layout.preferredHeight: app.s(34)
                    size: app.s(34); cornerRadius: app.s(11)
                    buttonIcon: GCal.status === "offline" ? GCal.icon.offline : GCal.icon.sync
                    iconFontSize: app.s(16)
                    accentColor: ThemeBackend.surface0
                    textColor: GCal.status === "error" ? ThemeBackend.red : (isHoveredOrHighlighted ? app.accent : ThemeBackend.subtext0)
                    action_highlight: activeFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Sync calendars", "Synchroniser les agendas")
                    onClicked: GCal.run(["sync", "--force"])
                    property real spin: 0
                    NumberAnimation on spin { running: GCal.syncing && app.shown && !GCal.reducedMotion; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                    rotation: GCal.syncing && !GCal.reducedMotion ? spin : 0
                }
                IconButton {
                    visible: !app.onboarding
                    Layout.preferredWidth: app.s(34); Layout.preferredHeight: app.s(34)
                    size: app.s(34); cornerRadius: app.s(11)
                    buttonIcon: GCal.icon.cog; iconFontSize: app.s(16)
                    accentColor: ThemeBackend.surface0
                    textColor: isHoveredOrHighlighted ? app.accent : ThemeBackend.overlay1
                    action_highlight: activeFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: GCal.tr("Calendar settings", "Réglages du calendrier")
                    onClicked: GCal.openSettings()
                }
                ClickButton {
                    visible: GCal.writableCalendars.length > 0
                    Layout.preferredHeight: app.s(34); Layout.preferredWidth: implicitWidth + app.s(8)
                    buttonText: app.narrow ? "" : GCal.tr("New", "Nouveau"); buttonIcon: GCal.icon.plus
                    Accessible.name: GCal.tr("New event", "Nouvel événement")
                    textFontSize: app.s(12); iconFontSize: app.s(15); cornerRadius: app.s(11)
                    accentColor: app.accent; textColor: GCal.readableOn(app.accent)
                    onClicked: GCal.openEventId = "new"
                }
            }

            RowLayout {
                id: compactViews
                visible: app.compact && !app.onboarding
                anchors.top: toolbar.bottom
                anchors.topMargin: app.s(6)
                width: parent.width
                height: app.s(36)
                spacing: app.s(8)

                LayoutItemProxy {
                    target: viewSwitcher
                    Layout.fillWidth: true
                    Layout.minimumWidth: app.s(148)
                    Layout.preferredWidth: app.s(320)
                    Layout.maximumWidth: app.s(340)
                    Layout.fillHeight: true
                }
                LayoutItemProxy {
                    target: searchInput
                    Layout.fillWidth: true
                    Layout.preferredWidth: app.s(150)
                    Layout.fillHeight: true
                }
            }

            GCalSegmented {
                id: viewSwitcher
                compactIcons: width < app.s(280)
                accent: app.accent
                options: [
                    { id: "month", label: GCal.tr("Month", "Mois"), icon: GCal.icon.month },
                    { id: "week", label: GCal.tr("Week", "Semaine"), icon: GCal.icon.week },
                    { id: "day", label: GCal.tr("Day", "Jour"), icon: GCal.icon.day },
                    { id: "list", label: GCal.tr("List", "Liste"), icon: GCal.icon.list }
                ]
                current: app.query ? "" : app.view
                onSelected: (id) => app.setView(id)
            }

            Input {
                id: searchInput
                leadingIcon: GCal.icon.search
                placeholderText: GCal.tr("Search events", "Rechercher")
                subTextColor: ThemeBackend.subtext0
                Accessible.name: placeholderText
                showClearButton: app.query !== ""
                fontPixelSize: app.s(12)
                cornerRadius: app.s(11)
                accentColor: app.accent
                onTextEdited: (t) => app.query = t.trim()
                onCleared: app.query = ""
            }
        }

        // Body.
        Item {
            id: bodyArea
            anchors.top: header.bottom
            anchors.topMargin: app.s(16)
            anchors.bottom: parent.bottom
            width: parent.width
            visible: !app.onboarding

            // Sidebar.
            Item {
                id: sidebar
                visible: !app.narrow || app.sidebarOpen
                z: app.narrow ? 2 : 0
                width: app.s(app.compact ? 220 : 250)
                height: parent.height
                opacity: app.step(1)
                transform: Translate { x: -app.s(30) * (1 - app.step(1)) }

                Rectangle {
                    anchors.fill: parent
                    visible: app.narrow
                    radius: app.s(14)
                    color: ThemeBackend.base
                    border.color: ThemeBackend.surface1
                }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: app.narrow ? app.s(10) : 0
                    spacing: app.s(12)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: mini.implicitHeight + app.s(20)
                        radius: Math.min(ThemeBackend.borderRadius, app.s(16))
                        color: miniGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.22)
                        GlassFill { id: miniGlass; anchors.fill: parent; radius: parent.radius; tintColor: ThemeBackend.surface0; tintAmount: 0.22 }
                        GCalMiniMonth {
                            id: mini
                            x: app.s(10); y: app.s(10)
                            width: parent.width - app.s(20)
                            selected: GCal.focusDate
                            weekBand: app.view === "week"
                            accent: app.accent
                            onPicked: (d) => { app.navigate(d); app.sidebarOpen = false; }
                        }
                    }

                    Text {
                        text: GCal.tr("CALENDARS", "AGENDAS")
                        font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: app.s(11)
                        font.letterSpacing: app.s(0.6)
                        color: ThemeBackend.subtext0
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: app.s(2)
                        model: GCal.calendars
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            id: calRow
                            required property var modelData
                            required property int index
                            readonly property bool on: modelData.visible !== false
                            width: ListView.view.width
                            height: app.s(34)
                            Rectangle {
                                anchors.fill: parent
                                radius: app.s(10)
                                color: calMa.containsMouse ? Qt.alpha(ThemeBackend.surface0, 0.55) : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            // Checkbox: fills with the calendar colour, the tick pops.
                            Rectangle {
                                id: box
                                x: app.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                width: app.s(18); height: width
                                radius: app.s(6)
                                color: calRow.on ? calRow.modelData.color : "transparent"
                                border.width: app.s(2)
                                border.color: calRow.modelData.color
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: GCal.icon.check
                                    font.family: ThemeBackend.iconFont; font.pixelSize: app.s(13)
                                    color: GCal.readableOn(calRow.modelData.color)
                                    opacity: calRow.on ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                            }
                            Text {
                                anchors.left: box.right
                                anchors.leftMargin: app.s(10)
                                anchors.right: tag.left
                                anchors.rightMargin: app.s(6)
                                anchors.verticalCenter: parent.verticalCenter
                                text: calRow.modelData.name
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: app.s(12)
                                color: calRow.on ? ThemeBackend.text : ThemeBackend.overlay0
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                id: tag
                                anchors.right: parent.right
                                anchors.rightMargin: app.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: calRow.modelData.source === "ics" ? GCal.icon.rss : (calRow.modelData.writable ? "" : GCal.icon.eye)
                                font.family: ThemeBackend.iconFont; font.pixelSize: app.s(12)
                                color: ThemeBackend.overlay0
                            }
                            MouseArea { id: calMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: GCal.toggleCalendar(calRow.modelData.id) }
                        }
                    }

                    // Account / sync status.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: app.s(52)
                        radius: Math.min(ThemeBackend.borderRadius, app.s(14))
                        color: Qt.alpha(ThemeBackend.surface0, accMa.containsMouse ? 0.5 : 0.25)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: app.s(10)
                            spacing: app.s(10)
                            Rectangle {
                                Layout.preferredWidth: app.s(32); Layout.preferredHeight: app.s(32)
                                radius: width / 2
                                color: Qt.alpha(app.accent, 0.25)
                                Text {
                                    anchors.centerIn: parent
                                    text: GCal.account ? GCal.account.charAt(0).toUpperCase() : GCal.icon.rss
                                    font.family: GCal.account ? ThemeBackend.fontFamily : ThemeBackend.iconFont
                                    font.weight: Font.Black; font.pixelSize: app.s(14)
                                    color: app.accent
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.account || GCal.tr("iCal only", "iCal uniquement")
                                    elide: Text.ElideMiddle
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: app.s(11.5)
                                    color: ThemeBackend.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: GCal.syncing ? GCal.tr("Syncing…", "Synchronisation…")
                                        : GCal.status === "offline" ? GCal.tr("Offline", "Hors ligne")
                                        : GCal.status === "error" ? GCal.error
                                        : GCal.pending ? GCal.tr("%1 pending", "%1 en attente").arg(GCal.pending)
                                        : GCal.state && GCal.state.lastSync ? GCal.tr("Synced %1", "Synchronisé %1").arg(GCal.ago(GCal.state.lastSync))
                                        : ""
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: app.s(10)
                                    color: GCal.status === "error" ? ThemeBackend.red : ThemeBackend.overlay1
                                }
                            }
                        }
                        MouseArea { id: accMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: GCal.openSettings() }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: app.narrow && app.sidebarOpen
                z: 1
                color: Qt.alpha(ThemeBackend.crust, 0.45)
                MouseArea { anchors.fill: parent; onClicked: app.sidebarOpen = false }
            }

            Item {
                id: viewArea
                anchors.left: app.narrow ? parent.left : sidebar.right
                anchors.leftMargin: app.narrow ? 0 : app.s(18)
                anchors.right: parent.right
                height: parent.height
                opacity: app.step(2)
                transform: Translate { y: app.s(12) * (1 - app.step(2)) }

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(ThemeBackend.borderRadius, app.s(18))
                    color: viewGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.14)
                    GlassFill { id: viewGlass; anchors.fill: parent; radius: parent.radius; tintColor: ThemeBackend.surface0; tintAmount: 0.15 }
                }

                Loader {
                    anchors.fill: parent
                    anchors.margins: app.s(10)
                    transform: Translate { x: app.viewOffset }
                    active: !app.query && app.view === "month"
                    sourceComponent: GCalMonthView { agenda: app }
                }
                Loader {
                    id: timeGrid
                    anchors.fill: parent
                    anchors.margins: app.s(10)
                    transform: Translate { x: app.viewOffset }
                    active: !app.query && (app.view === "week" || app.view === "day")
                    sourceComponent: GCalTimeGrid { agenda: app; days: app.view === "day" ? 1 : 7 }
                }
                Loader {
                    anchors.fill: parent
                    anchors.margins: app.s(10)
                    transform: Translate { x: app.viewOffset }
                    active: !!app.query || app.view === "list"
                    sourceComponent: GCalListView { agenda: app; query: app.query }
                }
            }
        }
    }

    // ------------------------------------------------------------------ overlays

    // Clicking outside the event card closes it.
    MouseArea {
        anchors.fill: parent
        visible: !!app.details
        onClicked: app.closeDetails()
        onWheel: (w) => app.closeDetails()
    }
    GCalEventDetails { id: detailsCard; agenda: app; ev: app.details; z: 10 }

    GCalEventEditor {
        anchors.fill: parent
        agenda: app
        draft: app.editorDraft
        z: 20
    }

    GCalConnect {
        anchors.fill: parent
        anchors.topMargin: app.onboarding ? app.s(60) : 0
        agenda: app
        onboarding: app.onboarding
        open: app.onboarding && app.reveal > 0.5
        opacity: app.onboarding ? app.step(1) : 1
        z: 30
    }

    // Recurring scope question.
    Item {
        anchors.fill: parent
        z: 40
        visible: scopeCard.progress > 0.01
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(ThemeBackend.crust, Math.max(0, Math.min(1, 0.4 * scopeCard.progress)))
            MouseArea { anchors.fill: parent; onClicked: app.resolveScope(null) }
        }
        Rectangle {
            id: scopeCard
            property real progress: app.scopeRequest ? 1 : 0
            Behavior on progress { NumberAnimation { duration: app.scopeRequest ? 210 : 140; easing.type: Easing.OutCubic } }
            anchors.centerIn: parent
            width: Math.min(app.s(380), parent.width - app.s(32))
            enabled: !!app.scopeRequest
            height: scopeCol.implicitHeight + app.s(40)
            radius: Math.min(ThemeBackend.borderRadius + app.s(4), app.s(22))
            color: ThemeBackend.base
            border.width: 1
            border.color: Qt.alpha(app.accent, 0.4)
            opacity: Math.min(1, progress)
            scale: GCal.reducedMotion ? 1 : 0.97 + 0.03 * progress
            property var req: null
            Connections {
                target: app
                function onScopeRequestChanged() {
                    if (app.scopeRequest) {
                        scopeCard.req = app.scopeRequest;
                        Qt.callLater(cancelScope.forceActiveFocus);
                    }
                }
            }
            ColumnLayout {
                id: scopeCol
                anchors.centerIn: parent
                width: parent.width - app.s(40)
                spacing: app.s(10)
                Text {
                    text: scopeCard.req ? scopeCard.req.title : ""
                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: app.s(16)
                    color: ThemeBackend.text
                }
                Text {
                    Layout.fillWidth: true
                    text: scopeCard.req ? "“" + (scopeCard.req.ev.title || "") + "” · " + GCal.describeRule(scopeCard.req.ev.recurrence) : ""
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: app.s(11.5)
                    color: ThemeBackend.overlay1
                }
                ClickButton {
                    Layout.fillWidth: true; Layout.preferredHeight: app.s(38)
                    buttonText: GCal.tr("This event only", "Cet événement uniquement")
                    textFontSize: app.s(12); cornerRadius: app.s(12)
                    accentColor: app.accent; textColor: GCal.readableOn(app.accent)
                    onClicked: app.resolveScope("this")
                }
                ClickButton {
                    Layout.fillWidth: true; Layout.preferredHeight: app.s(38)
                    buttonText: GCal.tr("All events in the series", "Tous les événements de la série")
                    textFontSize: app.s(12); cornerRadius: app.s(12)
                    accentColor: scopeCard.req && scopeCard.req.kind === "delete" ? ThemeBackend.red : ThemeBackend.surface1
                    textColor: scopeCard.req && scopeCard.req.kind === "delete" ? ThemeBackend.base : ThemeBackend.text
                    onClicked: app.resolveScope("all")
                }
                ClickButton {
                    Layout.fillWidth: true; Layout.preferredHeight: app.s(34)
                    id: cancelScope
                    buttonText: GCal.tr("Cancel", "Annuler")
                    textFontSize: app.s(11.5); cornerRadius: app.s(12)
                    accentColor: ThemeBackend.surface0; textColor: ThemeBackend.overlay1
                    onClicked: app.resolveScope(null)
                }
            }
        }
    }

    // Toast.
    Rectangle {
        id: toastBox
        z: 50
        property bool open: false
        function dismiss() { open = false; toastTimer.stop(); }
        property real progress: open ? 1 : 0
        Behavior on progress { NumberAnimation { duration: toastBox.open ? 180 : 140; easing.type: Easing.OutCubic } }
        visible: progress > 0.01
        opacity: progress
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: app.s(26)
        transform: Translate { y: GCal.reducedMotion ? 0 : app.s(12) * (1 - toastBox.progress) }
        width: Math.min(toastRow.implicitWidth + app.s(32), parent.width - app.s(32))
        height: app.s(42)
        radius: height / 2
        color: Qt.alpha(ThemeBackend.crust, 0.95)
        border.width: 1
        border.color: app.toastError ? ThemeBackend.red : Qt.alpha(app.accent, 0.5)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: app.s(15)
            width: parent.width - app.s(30)
            height: app.s(2)
            radius: height / 2
            color: app.toastError ? ThemeBackend.red : app.accent
            opacity: 0.7
            transform: Scale {
                NumberAnimation on xScale {
                    id: toastBar
                    from: 1; to: 0
                    duration: toastTimer.interval
                }
            }
        }
        RowLayout {
            id: toastRow
            anchors.fill: parent
            anchors.leftMargin: app.s(16)
            anchors.rightMargin: app.s(16)
            spacing: app.s(12)
            Text {
                text: app.toastError ? GCal.icon.alert : GCal.icon.check
                font.family: ThemeBackend.iconFont; font.pixelSize: app.s(15)
                color: app.toastError ? ThemeBackend.red : app.accent
            }
            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: app.s(520)
                text: app.toastText
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: app.s(12)
                color: ThemeBackend.text
            }
            Text {
                visible: app.toastAction !== ""
                text: app.toastAction.toUpperCase()
                font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: app.s(11.5)
                color: undoMa.containsMouse ? ThemeBackend.text : app.accent
                Behavior on color { ColorAnimation { duration: 140 } }
                MouseArea {
                    id: undoMa
                    anchors.fill: parent
                    anchors.margins: -app.s(8)
                    enabled: toastBox.open
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const cb = app.toastCallback;
                        toastBox.dismiss();
                        if (cb) cb();
                    }
                }
            }
        }
    }
}
