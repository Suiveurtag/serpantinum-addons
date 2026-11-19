import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Accounts & preferences sheet. Doubles as the onboarding screen when no calendar is configured yet.
Item {
    id: root
    required property Item agenda
    property bool open: false
    property bool onboarding: false
    function s(v) { return Scaler.s(v); }

    property string clientId: ""
    property string clientSecret: ""
    property string icsUrl: ""
    property string icsName: ""
    property bool icsBusy: false
    property string icsError: ""
    property bool confirmDisconnect: false
    property int generation: 0
    property string credentialError: ""
    onOpenChanged: if (open) { generation++; confirmDisconnect = false; icsError = ""; }

    readonly property bool connecting: GCal.connectProc !== null
    readonly property bool cancelling: connecting && GCal.connectProc.cancelRequested
    readonly property color accent: agenda.accent

    function connectGoogle() {
        if (connecting) return;
        const id = clientId.trim();
        const secret = clientSecret.trim();
        if (!id.endsWith(".apps.googleusercontent.com")) {
            credentialError = GCal.tr("Enter the client ID ending in .apps.googleusercontent.com.", "Saisis l’ID client qui se termine par .apps.googleusercontent.com.");
            return;
        }
        if (!secret) {
            credentialError = GCal.tr("Enter the client secret.", "Saisis le secret client.");
            return;
        }
        credentialError = "";
        formScroll.contentY = 0;
        GCal.connect(id, secret);
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.onboarding && card.progress > 0.01
        color: Qt.alpha(ThemeBackend.crust, Math.max(0, Math.min(1, 0.4 * card.progress)))
        MouseArea { anchors.fill: parent; enabled: root.open; onClicked: root.agenda.settingsOpen = false }
    }

    Rectangle {
        id: card
        property real progress: root.open ? 1 : 0
        Behavior on progress { NumberAnimation { duration: root.open ? 520 : 220; easing.type: root.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.05 } }
        visible: progress > 0.01
        opacity: Math.min(1, progress)
        scale: 0.92 + 0.08 * progress
        anchors.centerIn: parent
        width: Math.min(root.s(660), parent.width - root.s(40))
        height: Math.min(body.implicitHeight + root.s(48), parent.height - root.s(24))
        radius: Math.min(ThemeBackend.borderRadius + root.s(6), root.s(26))
        color: root.onboarding ? "transparent" : ThemeBackend.base
        border.width: root.onboarding ? 0 : 1
        border.color: Qt.alpha(root.accent, 0.35)
        clip: true
        MouseArea { anchors.fill: parent }

        Flickable {
            id: formScroll
            anchors.fill: parent
            anchors.margins: root.s(24)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: root.s(16)

                // Hero.
                GCalReveal { generation: root.generation; index: 0
                    implicitHeight: hero.implicitHeight
                    RowLayout {
                        id: hero
                        width: parent.width
                        spacing: root.s(14)
                        Item {
                            Layout.preferredWidth: root.s(root.onboarding ? 64 : 44); Layout.preferredHeight: Layout.preferredWidth
                            Rectangle {
                                anchors.fill: parent
                                radius: root.s(16)
                                color: Qt.alpha(root.accent, 0.18)
                                SequentialAnimation on rotation {
                                    running: root.open
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -6; to: 6; duration: 2600; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 6; to: -6; duration: 2600; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: GCal.icon.calendar
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: parent.width * 0.5
                                color: root.accent
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(2)
                            Text {
                                Layout.fillWidth: true
                                text: root.onboarding ? GCal.tr("Your calendar, in the shell", "Ton agenda, dans le shell") : GCal.tr("Calendars & preferences", "Agendas et préférences")
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Black
                                font.pixelSize: root.s(root.onboarding ? 22 : 17)
                                color: ThemeBackend.text
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: GCal.tr("Google Calendar is fully editable. iCal links (Outlook, iCloud, school timetables, holidays…) are shown read only.",
                                              "Google Agenda est entièrement modifiable. Les liens iCal (Outlook, iCloud, emplois du temps, jours fériés…) sont en lecture seule.")
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11.5)
                                color: ThemeBackend.overlay1
                                wrapMode: Text.WordWrap
                            }
                        }
                        IconButton {
                            visible: !root.onboarding
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: root.s(30); Layout.preferredHeight: root.s(30)
                            size: root.s(30); cornerRadius: root.s(9)
                            buttonIcon: GCal.icon.close; iconFontSize: root.s(14)
                            accentColor: ThemeBackend.surface0
                            textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                            onClicked: root.agenda.settingsOpen = false
                        }
                    }
                }

                // ---------------------------------------------------------- Google
                GCalReveal { generation: root.generation; index: 1
                    implicitHeight: googleCard.implicitHeight
                    Rectangle {
                        id: googleCard
                        width: parent.width
                        implicitHeight: googleCol.implicitHeight + root.s(28)
                        Behavior on implicitHeight { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                        radius: root.s(16)
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)
                        clip: true

                        ColumnLayout {
                            id: googleCol
                            x: root.s(14); y: root.s(14)
                            width: parent.width - root.s(28)
                            spacing: root.s(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(10)
                                Text {
                                    text: GCal.icon.google
                                    font.family: ThemeBackend.iconFont; font.pixelSize: root.s(20)
                                    color: ThemeBackend.blue
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Google Calendar"
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(14)
                                    color: ThemeBackend.text
                                }
                                Rectangle {
                                    visible: GCal.google
                                    Layout.preferredWidth: root.s(8); Layout.preferredHeight: root.s(8)
                                    radius: width / 2
                                    color: GCal.status === "error" ? ThemeBackend.red : GCal.status === "offline" ? ThemeBackend.yellow : ThemeBackend.green
                                    SequentialAnimation on opacity {
                                        running: GCal.google && root.open
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.35; duration: 1200; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.35; to: 1; duration: 1200; easing.type: Easing.InOutSine }
                                    }
                                }
                                Text {
                                    visible: GCal.google
                                    text: GCal.account || GCal.tr("Connected", "Connecté")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11.5)
                                    color: ThemeBackend.subtext0
                                }
                            }

                            Text {
                                id: errorText
                                visible: text !== "" && !root.connecting
                                Layout.fillWidth: true
                                text: GCal.connectError || (GCal.status === "error" || GCal.lastError ? GCal.error : "")
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                color: ThemeBackend.red
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                onTextChanged: if (errorText.text) errShake.restart()
                                transform: Translate { id: errT }
                                SequentialAnimation {
                                    id: errShake
                                    NumberAnimation { target: errT; property: "x"; to: -root.s(8); duration: 60 }
                                    NumberAnimation { target: errT; property: "x"; to: root.s(6); duration: 80 }
                                    NumberAnimation { target: errT; property: "x"; to: 0; duration: 140; easing.type: Easing.OutBack }
                                }
                            }

                            // Connected.
                            RowLayout {
                                visible: GCal.google && !root.connecting
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.tr("%1 calendars synced every 5 minutes.", "%1 agendas synchronisés toutes les 5 minutes.").arg(GCal.calendars.filter(c => c.source === "google").length)
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11.5)
                                    color: ThemeBackend.overlay1
                                    wrapMode: Text.WordWrap
                                }
                                ClickButton {
                                    Layout.preferredHeight: root.s(32); Layout.preferredWidth: implicitWidth
                                    buttonText: root.confirmDisconnect ? GCal.tr("Click again to disconnect", "Clique encore pour déconnecter") : GCal.tr("Disconnect", "Déconnecter")
                                    textFontSize: root.s(11.5); cornerRadius: root.s(10)
                                    accentColor: root.confirmDisconnect ? ThemeBackend.red : ThemeBackend.surface1
                                    textColor: root.confirmDisconnect ? ThemeBackend.base : ThemeBackend.text
                                    onClicked: {
                                        if (!root.confirmDisconnect) { root.confirmDisconnect = true; confirmTimer.restart(); return; }
                                        root.confirmDisconnect = false;
                                        GCal.disconnect();
                                    }
                                    Timer { id: confirmTimer; interval: 3500; onTriggered: root.confirmDisconnect = false }
                                }
                            }

                            // Waiting for the browser.
                            RowLayout {
                                visible: root.connecting
                                Layout.fillWidth: true
                                spacing: root.s(12)
                                Item {
                                    Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            required property int index
                                            anchors.centerIn: parent
                                            width: root.s(28); height: width; radius: width / 2
                                            color: "transparent"
                                            border.width: root.s(2)
                                            border.color: root.accent
                                            opacity: 0
                                            SequentialAnimation on scale {
                                                running: root.connecting
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: index * 500 }
                                                NumberAnimation { from: 0.2; to: 1; duration: 1500; easing.type: Easing.OutCubic }
                                            }
                                            SequentialAnimation on opacity {
                                                running: root.connecting
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: index * 500 }
                                                NumberAnimation { from: 0.9; to: 0; duration: 1500; easing.type: Easing.OutCubic }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (root.cancelling) return GCal.tr("Cancelling…", "Annulation…");
                                        if (GCal.google) return GCal.tr("Syncing your calendars…", "Synchronisation de tes agendas…");
                                        if (GCal.browserOpenFailed) return GCal.tr("The default browser did not open. Use Open browser to try again.", "Le navigateur par défaut n’a pas pu s’ouvrir. Clique sur « Ouvrir le navigateur » pour réessayer.");
                                        if (GCal.authUrl) return GCal.tr("Allow access in your browser. If Google blocks sign-in, check the reason on that page.", "Autorise l’accès dans ton navigateur. Si Google bloque la connexion, le motif s’affiche sur sa page.");
                                        return GCal.tr("Preparing Google sign-in…", "Préparation de la connexion à Google…");
                                    }
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(12)
                                    color: ThemeBackend.text
                                    wrapMode: Text.WordWrap
                                }
                                ClickButton {
                                    Layout.preferredHeight: root.s(32); Layout.preferredWidth: implicitWidth
                                    visible: !!GCal.authUrl && !root.cancelling
                                    buttonText: GCal.tr("Open browser", "Ouvrir le navigateur"); buttonIcon: GCal.icon.open
                                    textFontSize: root.s(11.5); iconFontSize: root.s(13); cornerRadius: root.s(10)
                                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                                    onClicked: GCal.openAuthBrowser()
                                }
                                ClickButton {
                                    visible: !!GCal.authUrl && !root.cancelling
                                    Layout.preferredHeight: root.s(32); Layout.preferredWidth: implicitWidth
                                    buttonText: GCal.tr("Cancel", "Annuler")
                                    textFontSize: root.s(11.5); cornerRadius: root.s(10)
                                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                                    onClicked: GCal.cancelConnect()
                                }
                            }

                            // Setup steps.
                            ColumnLayout {
                                visible: !GCal.google && !root.connecting
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.tr("Google needs your own OAuth client (free, 3 minutes, done once):", "Google demande ton propre client OAuth (gratuit, 3 minutes, une seule fois) :")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11.5)
                                    color: ThemeBackend.subtext0
                                    wrapMode: Text.WordWrap
                                }
                                Repeater {
                                    model: [
                                        { t: GCal.tr("Create a project", "Crée un projet"), d: GCal.tr("Any name works.", "N'importe quel nom."), url: "https://console.cloud.google.com/projectcreate" },
                                        { t: GCal.tr("Enable the Google Calendar API", "Active l'API Google Calendar"), d: GCal.tr("Press “Enable”.", "Clique sur « Activer »."), url: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com" },
                                        { t: GCal.tr("Set up the consent screen", "Configure l'écran de consentement"), d: GCal.tr("Audience “External”, then “Publish app” so access never expires after 7 days.", "Audience « Externe », puis « Publier l'application » pour que l'accès n'expire pas au bout de 7 jours."), url: "https://console.cloud.google.com/auth/overview" },
                                        { t: GCal.tr("Create an OAuth client “Desktop app”", "Crée un client OAuth « Application de bureau »"), d: GCal.tr("Copy its client ID and secret below.", "Copie son ID client et son secret ci-dessous."), url: "https://console.cloud.google.com/auth/clients/create" }
                                    ]
                                    Rectangle {
                                        id: step
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: stepRow.implicitHeight + root.s(14)
                                        radius: root.s(12)
                                        color: Qt.alpha(ThemeBackend.surface0, stepMa.containsMouse ? 0.7 : 0.4)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        RowLayout {
                                            id: stepRow
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: root.s(10); width: parent.width - root.s(20)
                                            spacing: root.s(10)
                                            Rectangle {
                                                Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24)
                                                radius: width / 2
                                                color: root.accent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: step.index + 1
                                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11)
                                                    color: GCal.readableOn(root.accent)
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: step.modelData.t
                                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                                                    color: ThemeBackend.text
                                                    wrapMode: Text.WordWrap
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: step.modelData.d
                                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(10.5)
                                                    color: ThemeBackend.overlay1
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                            Text {
                                                text: GCal.icon.open
                                                font.family: ThemeBackend.iconFont; font.pixelSize: root.s(15)
                                                color: stepMa.containsMouse ? root.accent : ThemeBackend.overlay1
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                transform: Translate { x: stepMa.containsMouse ? root.s(2) : 0; Behavior on x { NumberAnimation { duration: 160 } } }
                                            }
                                        }
                                        MouseArea { id: stepMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(step.modelData.url) }
                                    }
                                }
                                Input {
                                    id: idInput
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(36)
                                    placeholderText: GCal.tr("Client ID (….apps.googleusercontent.com)", "ID client (….apps.googleusercontent.com)")
                                    fontPixelSize: root.s(12)
                                    cornerRadius: root.s(11)
                                    accentColor: root.accent
                                    onTextEdited: (t) => { root.clientId = t; root.credentialError = ""; }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Input {
                                        id: secretInput
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(36)
                                        placeholderText: GCal.tr("Client secret", "Secret client")
                                        masked: true
                                        fontPixelSize: root.s(12)
                                        cornerRadius: root.s(11)
                                        accentColor: root.accent
                                        onTextEdited: (t) => { root.clientSecret = t; root.credentialError = ""; }
                                        onAccepted: root.connectGoogle()
                                    }
                                    ClickButton {
                                        Layout.preferredHeight: root.s(36); Layout.preferredWidth: implicitWidth + root.s(10)
                                        enabled: !root.connecting
                                        buttonText: GCal.tr("Connect Google", "Connecter Google"); buttonIcon: GCal.icon.google
                                        textFontSize: root.s(12); iconFontSize: root.s(14); cornerRadius: root.s(11)
                                        accentColor: root.accent; textColor: GCal.readableOn(root.accent)
                                        onClicked: root.connectGoogle()
                                    }
                                }
                                Text {
                                    visible: text !== ""
                                    Layout.fillWidth: true
                                    text: root.credentialError
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: root.s(11)
                                    color: ThemeBackend.red
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------- iCal
                GCalReveal { generation: root.generation; index: 2
                    implicitHeight: icsCard.implicitHeight
                    Rectangle {
                        id: icsCard
                        width: parent.width
                        implicitHeight: icsCol.implicitHeight + root.s(28)
                        Behavior on implicitHeight { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                        radius: root.s(16)
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)
                        clip: true
                        ColumnLayout {
                            id: icsCol
                            x: root.s(14); y: root.s(14)
                            width: parent.width - root.s(28)
                            spacing: root.s(10)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(10)
                                Text { text: GCal.icon.rss; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(19); color: ThemeBackend.peach }
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.tr("iCal subscriptions", "Abonnements iCal")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(14)
                                    color: ThemeBackend.text
                                }
                            }
                            Repeater {
                                model: GCal.icsSources
                                Rectangle {
                                    id: src
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: root.s(40)
                                    radius: root.s(11)
                                    color: Qt.alpha(ThemeBackend.surface0, 0.5)
                                    property real enter: 0
                                    Component.onCompleted: srcIn.start()
                                    NumberAnimation { id: srcIn; target: src; property: "enter"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack }
                                    opacity: enter
                                    scale: 0.9 + 0.1 * enter
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(12); anchors.rightMargin: root.s(6)
                                        spacing: root.s(10)
                                        Rectangle { Layout.preferredWidth: root.s(10); Layout.preferredHeight: root.s(10); radius: width / 2; color: src.modelData.color || root.accent }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { Layout.fillWidth: true; text: src.modelData.name; elide: Text.ElideRight; font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(11.5); color: ThemeBackend.text }
                                            Text { Layout.fillWidth: true; text: src.modelData.url; elide: Text.ElideMiddle; font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(9.5); color: ThemeBackend.overlay0 }
                                        }
                                        IconButton {
                                            Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                                            size: root.s(28); cornerRadius: root.s(8)
                                            buttonIcon: GCal.icon.trash; iconFontSize: root.s(13)
                                            accentColor: ThemeBackend.surface0
                                            textColor: isHoveredOrHighlighted ? ThemeBackend.red : ThemeBackend.overlay1
                                            onClicked: GCal.removeIcs(src.modelData.id)
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Input {
                                    id: urlInput
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(36)
                                    leadingIcon: GCal.icon.link
                                    placeholderText: "https://… .ics  /  webcal://…"
                                    fontPixelSize: root.s(12)
                                    cornerRadius: root.s(11)
                                    accentColor: ThemeBackend.peach
                                    isBusy: root.icsBusy
                                    hasError: root.icsError !== ""
                                    onTextEdited: (t) => { root.icsUrl = t; root.icsError = ""; }
                                    onAccepted: addBtn.clicked()
                                }
                                Input {
                                    Layout.preferredWidth: root.s(130)
                                    Layout.preferredHeight: root.s(36)
                                    placeholderText: GCal.tr("Name (optional)", "Nom (optionnel)")
                                    fontPixelSize: root.s(12)
                                    cornerRadius: root.s(11)
                                    accentColor: ThemeBackend.peach
                                    onTextEdited: (t) => root.icsName = t
                                }
                                ClickButton {
                                    id: addBtn
                                    Layout.preferredHeight: root.s(36); Layout.preferredWidth: implicitWidth + root.s(8)
                                    enabled: !root.icsBusy && /^(https?|webcal):\/\//i.test(root.icsUrl.trim())
                                    opacity: enabled ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    buttonText: root.icsBusy ? GCal.tr("Reading…", "Lecture…") : GCal.tr("Add", "Ajouter")
                                    buttonIcon: GCal.icon.plus
                                    textFontSize: root.s(12); iconFontSize: root.s(14); cornerRadius: root.s(11)
                                    accentColor: ThemeBackend.peach; textColor: GCal.readableOn(ThemeBackend.peach)
                                    onClicked: {
                                        root.icsBusy = true;
                                        GCal.addIcs(root.icsUrl.trim(), root.icsName.trim(), (r) => {
                                            root.icsBusy = false;
                                            if (r.ok) { urlInput.clear(); root.icsUrl = ""; root.agenda.toast(GCal.tr("%1 events imported", "%1 événements importés").arg(r.events || 0)); }
                                            else { root.icsError = r.error || "error"; urlInput.triggerShake(); }
                                        });
                                    }
                                }
                            }
                            Text {
                                visible: root.icsError !== ""
                                Layout.fillWidth: true
                                text: root.icsError
                                wrapMode: Text.WordWrap
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                color: ThemeBackend.red
                            }
                        }
                    }
                }

                // ---------------------------------------------------------- preferences
                GCalReveal { generation: root.generation; index: 3
                    visible: GCal.available
                    implicitHeight: prefCol.implicitHeight + root.s(28)
                    Rectangle {
                        anchors.fill: parent
                        radius: root.s(16)
                        color: Qt.alpha(ThemeBackend.surface0, 0.35)
                        ColumnLayout {
                            id: prefCol
                            x: root.s(14); y: root.s(14)
                            width: parent.width - root.s(28)
                            spacing: root.s(12)
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.icon.bell + "  " + GCal.tr("Reminder notifications", "Notifications de rappel")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                                    color: ThemeBackend.text
                                }
                                Toggle {
                                    checked: GCal.prefs.reminders !== false
                                    accentColor: root.accent
                                    trackWidth: root.s(38); trackHeight: root.s(20)
                                    onToggled: (c) => GCal.setPrefs({ reminders: c })
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(10)
                                Text {
                                    Layout.fillWidth: true
                                    text: GCal.icon.week + "  " + GCal.tr("Week starts on", "La semaine commence le")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                                    color: ThemeBackend.text
                                }
                                GCalSegmented {
                                    Layout.preferredWidth: root.s(220); Layout.preferredHeight: root.s(30)
                                    accent: root.accent
                                    options: [{ id: "1", label: GCal.locale.dayName(1, Locale.LongFormat) }, { id: "0", label: GCal.locale.dayName(0, Locale.LongFormat) }]
                                    current: String(GCal.prefs.weekStart === 0 ? 0 : 1)
                                    onSelected: (id) => GCal.setPrefs({ weekStart: parseInt(id) })
                                }
                            }
                            ColumnLayout {
                                visible: GCal.writableCalendars.length > 1
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    text: GCal.icon.plus + "  " + GCal.tr("New events go to", "Les nouveaux événements vont dans")
                                    font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(12)
                                    color: ThemeBackend.text
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: root.s(6)
                                    Repeater {
                                        model: GCal.writableCalendars
                                        GCalChip {
                                            required property var modelData
                                            text: modelData.name; dot: modelData.color; accent: modelData.color
                                            selected: GCal.defaultCalendar === modelData.id
                                            onClicked: GCal.setPrefs({ defaultCalendar: modelData.id })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
