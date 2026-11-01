import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Version, compatibility and update card shared by About and Addons > General.
Rectangle {
    id: card
    required property var rootObj
    // Adds the red "Uninstall addons" hold-to-confirm button below the card content.
    property bool showUninstall: false

    readonly property string st: AddonsUpdater.state
    readonly property bool canInstall: st === "available" || st === "reinstall_needed"
    readonly property bool blocked: st === "incompatible" || st === "serpantinum_outdated"
    property real panelProgress: (canInstall || blocked) ? 1.0 : 0.0
    Behavior on panelProgress {
        NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
    }

    function s(v) { return rootObj ? rootObj.s(v) : v; }

    function bareVersion(v) { return String(v || "").replace(/^v/i, ""); }

    function checkedSuffix() {
        if (AddonsUpdater.checkedAt === "") return "";
        let d = new Date(AddonsUpdater.checkedAt);
        return isNaN(d.getTime()) ? "" : " · checked " + Qt.formatTime(d, "HH:mm");
    }

    function compatText() {
        switch (AddonsUpdater.compat) {
        case "ok": return "compatible";
        case "newer_than_tested": return "newer than tested";
        case "too_old": return "older than supported";
        default: return "compatibility unknown";
        }
    }

    function compatColor() {
        switch (AddonsUpdater.compat) {
        case "ok": return ThemeBackend.green;
        case "newer_than_tested": return ThemeBackend.yellow;
        case "too_old": return ThemeBackend.red;
        default: return ThemeBackend.subtext0;
        }
    }

    function statusText() {
        if (AddonsUpdater.checking) return "checking…";
        switch (st) {
        case "up_to_date": return "up to date" + checkedSuffix();
        case "available": return "update available" + checkedSuffix();
        case "reinstall_needed": return "reinstall needed" + checkedSuffix();
        case "error": return "offline: " + (AddonsUpdater.error !== "" ? AddonsUpdater.error : "unknown error");
        case "dev": return "dev build";
        case "not_installed": return "not installed with the addons updater";
        case "incompatible": return "incompatible with this Serpantinum";
        case "serpantinum_outdated": return "Serpantinum is too old for this release";
        default: return "not checked yet";
        }
    }

    function launchAndClose(args) {
        if (AddonsUpdater.launch(args) && rootObj && typeof rootObj.dismissHost === "function") {
            rootObj.dismissHost();
        }
    }

    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + card.s(24)
    radius: ThemeBackend.borderRadius
    color: cardGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.4)

    GlassFill {
        id: cardGlass
        anchors.fill: parent
        radius: parent.radius
        tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
        tintAmount: 0.25
    }

    ColumnLayout {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.s(14)
        anchors.rightMargin: card.s(14)
        anchors.topMargin: card.s(12)
        spacing: card.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: card.s(12)

            IconButton {
                enabled: false
                size: card.s(32)
                Layout.preferredWidth: card.s(32)
                Layout.preferredHeight: card.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: ThemeBackend.borderRadius
                buttonIcon: "󰏗"
                iconFontSize: card.s(16)
                accentColor: ThemeBackend.peach
                textColor: ThemeBackend.crust
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: card.s(2)

                Text {
                    text: "Serpantinum Addons"
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: card.s(15)
                    color: ThemeBackend.text
                }

                Text {
                    text: AddonsUpdater.localVersion !== "" ? "v" + card.bareVersion(AddonsUpdater.localVersion) : "version unknown"
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: card.s(13)
                    color: ThemeBackend.peach
                }
            }

            ClickButton {
                Layout.preferredHeight: card.s(30)
                Layout.alignment: Qt.AlignVCenter
                enabled: !AddonsUpdater.checking
                opacity: enabled ? 1.0 : 0.5
                horizontalPadding: card.s(12)
                cornerRadius: ThemeBackend.borderRadius
                buttonText: "Check now"
                textFontSize: card.s(12)
                buttonIcon: "󰑓"
                iconFontSize: card.s(14)
                accentColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                onTriggered: AddonsUpdater.check(true)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: card.s(6)

            Text {
                text: "Serpantinum" + (AddonsUpdater.serpantinumVersion !== "" ? " " + card.bareVersion(AddonsUpdater.serpantinumVersion) : "") + " ·"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(12)
                color: ThemeBackend.subtext0
            }

            Text {
                text: card.compatText()
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(12)
                color: card.compatColor()
            }
        }

        Text {
            Layout.fillWidth: true
            text: card.statusText()
            wrapMode: Text.WordWrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: card.s(12)
            color: AddonsUpdater.state === "error" ? ThemeBackend.red : ThemeBackend.subtext0
        }

        Item {
            id: updatePanel
            Layout.fillWidth: true
            Layout.preferredHeight: updateCol.implicitHeight * card.panelProgress
            visible: card.panelProgress > 0.001
            opacity: card.panelProgress
            clip: true
            transform: Translate { x: card.s(16) * (1.0 - card.panelProgress) }

            ColumnLayout {
                id: updateCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: card.s(10)

                Text {
                    Layout.topMargin: card.s(4)
                    text: card.st === "reinstall_needed" ? "Addons need reinstalling"
                        : "Addons update" + (AddonsUpdater.remoteVersion !== "" ? " v" + card.bareVersion(AddonsUpdater.remoteVersion) : "")
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: card.s(16)
                    color: ThemeBackend.peach
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.blocked
                    text: "Requires a newer Serpantinum — update Serpantinum first"
                    wrapMode: Text.WordWrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: card.s(12)
                    color: ThemeBackend.subtext0
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: card.s(10)

                    ClickButton {
                        visible: /^https:\/\//.test(AddonsUpdater.notesUrl)
                        Layout.preferredHeight: card.s(38)
                        Layout.preferredWidth: card.s(140)
                        horizontalPadding: card.s(14)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: "Changelog"
                        textFontSize: card.s(12)
                        buttonIcon: "󰈙"
                        iconFontSize: card.s(16)
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.text
                        onTriggered: Qt.openUrlExternally(AddonsUpdater.notesUrl)
                    }

                    FillButton {
                        visible: card.canInstall
                        Layout.fillWidth: true
                        Layout.preferredHeight: card.s(38)
                        buttonText: card.st === "reinstall_needed" ? "Reinstall addons" : "Update addons"
                        buttonIcon: "󰏗"
                        accentColor: ThemeBackend.peach
                        baseColor: ThemeBackend.surface0
                        hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                        textColor: ThemeBackend.peach
                        filledTextColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        textFontSize: card.s(12)
                        iconFontSize: card.s(16)
                        fillDuration: 1200
                        onTriggered: card.launchAndClose(card.st === "reinstall_needed" ? "reinstall" : "update")
                    }
                }
            }
        }

        FillButton {
            visible: card.showUninstall
            Layout.fillWidth: true
            Layout.preferredHeight: card.s(38)
            Layout.topMargin: card.s(4)
            buttonText: "Uninstall addons"
            buttonIcon: "󰆴"
            accentColor: ThemeBackend.red
            baseColor: ThemeBackend.surface0
            hoverColor: Qt.alpha(ThemeBackend.red, 0.15)
            textColor: ThemeBackend.red
            filledTextColor: ThemeBackend.crust
            cornerRadius: ThemeBackend.borderRadius
            textFontSize: card.s(12)
            iconFontSize: card.s(16)
            fillDuration: 1500
            onTriggered: card.launchAndClose("--focus uninstall")
        }
    }
}
