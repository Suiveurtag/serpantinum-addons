import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    property int subTabIndex: 0
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex && rootObj.currentSubTab === subTabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    // Platform logo for a sub-setting row: white source SVG tinted with the given theme colour, in the 32px icon slot.
    component PlatformLogo: Item {
        id: logoRoot
        required property string logo
        required property color tint
        width: root.rootObj.s(32); height: width
        Image {
            anchors.centerIn: parent
            width: root.rootObj.s(18); height: width
            source: Qt.resolvedUrl("../tokens/assets/logos/" + logoRoot.logo)
            sourceSize: Qt.size(width, height)
            smooth: true; mipmap: true
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1; colorizationColor: logoRoot.tint }
        }
    }
    Flickable {
        id: addonsViewport
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_desktop_glass"; searchTab: "addons"; searchKeywords: "liquid glass desktop windows live capture reflection bureau fenêtres"
                title: "Live desktop in Liquid Glass"; description: "Reflect windows behind the shell on Hyprland 0.57+. Uses extra graphics resources."; icon: "󰖲"
                wrapText: true
                Toggle {
                    checked: Config.getSetting("addonsV2DesktopGlass", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: {
                        Config.setSetting("addonsV2DesktopGlass", checked);
                        checked = Qt.binding(function() { return Config.getSetting("addonsV2DesktopGlass", false); });
                    }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_window_outline"; searchTab: "addons"; searchKeywords: "window outline border theme fenêtre contour bordure thème"
                title: "Themed window outline"; description: "Add a fine outline to windows using the current shell palette."; icon: "󰖯"
                Toggle {
                    checked: Config.getSetting("addonsV2WindowOutline", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: {
                        Config.setSetting("addonsV2WindowOutline", checked);
                        checked = Qt.binding(function() { return Config.getSetting("addonsV2WindowOutline", false); });
                    }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_skip_boot_intro"; searchTab: "addons"; searchKeywords: "skip boot intro startup login logo animation splash démarrage ouverture passer ignorer"
                title: "Skip intro at login"; description: "Skip the Serpantinum welcome animation whenever you log in."; icon: "󰒭"
                wrapText: true
                ClickButton {
                    buttonText: qsTr("Preview")
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: Quickshell.execDetached(["quickshell", "-p", Caching.qsDir + "/Shell.qml", "ipc", "call", "addonBootIntro", "play"])
                }
                Toggle {
                    checked: Config.getSetting("addonsV2BootIntro", true) === false
                    accentColor: ThemeBackend.mauve
                    onToggled: {
                        Config.setSetting("addonsV2BootIntro", !checked);
                        checked = Qt.binding(function() { return Config.getSetting("addonsV2BootIntro", true) === false; });
                    }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_boot_intro_sound"; searchTab: "addons"; searchKeywords: "boot intro sound audio son démarrage"
                title: "Boot intro sound"; description: "Play the welcome sounds with the boot intro."; icon: "󰕾"
                visible: Config.getSetting("addonsV2BootIntro", true) !== false
                Toggle {
                    checked: Config.getSetting("addonsV2BootIntroSound", true) !== false
                    accentColor: ThemeBackend.mauve
                    onToggled: {
                        Config.setSetting("addonsV2BootIntroSound", checked);
                        checked = Qt.binding(function() { return Config.getSetting("addonsV2BootIntroSound", true) !== false; });
                    }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_weather_city_obfuscation"; searchTab: "addons"; searchKeywords: "weather city location privacy obfuscated météo ville localisation"
                title: "Obfuscate weather location"; description: "Scramble the city name in the weather widget."; icon: "󰍑"
                Toggle {
                    checked: Config.getSetting("addonsV2ObfuscateWeatherCity", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2ObfuscateWeatherCity", checked); }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_mullvad_dns"; searchTab: "addons"; searchKeywords: "dns mullvad network privacy"
                title: "Mullvad DNS"; icon: "󰖟"
                description: dns.errorMessage || (dns.connectionName ? "DNS over TLS · " + dns.connectionName : "Connect to a network to change its DNS.")
                wrapText: true
                DnsControl { id: dns; Layout.preferredWidth: root.rootObj.s(170); pollEnabled: root.visible }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_bar_outlines"; searchTab: "addons"; searchKeywords: "bar outline panel open contour barre panneau animation effects"
                title: "Animated bar outlines"; description: "Outline the bar button (or its whole group) while its panel is open, and the AI tokens item on hover."; icon: "󱓼"
                Toggle {
                    checked: Config.getSetting("addonsV2BarOutlines", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2BarOutlines", checked); }
                }
            }
            // AI tokens counter: a header that folds the sources open and shut. Closed by default.
            ColumnLayout {
                id: tokensSources
                property bool expanded: false
                readonly property bool isOpen: expanded
                property real progress: isOpen ? 1 : 0
                // Opening: a soft decelerate. Closing: shorter, ease-in-out so it tucks away without a bounce.
                Behavior on progress { NumberAnimation { duration: tokensSources.isOpen ? 420 : 280; easing.type: tokensSources.isOpen ? Easing.OutCubic : Easing.InOutQuad } }
                // Each row starts a little after the one above it, so the list unfolds instead of sliding as one block.
                function stagger(i) { return Math.max(0, Math.min(1, (progress - Math.min(i * 0.07, 0.35)) / 0.65)); }
                Layout.fillWidth: true
                spacing: 0
                SettingsRow {
                    rootObj: root.rootObj
                    // The whole header toggles the list, like the wallpaper accents.
                    clickable: true
                    onClicked: tokensSources.expanded = !tokensSources.expanded
                    settingId: "addons_tokens_sources"; searchTab: "addons"
                    searchKeywords: "tokens counter sources codex claude opencode llama.cpp ollama lmstudio compteur jetons sources"
                    icon: "󰞷"
                    title: "AI tokens counter"
                    description: "Tools whose usage the counter adds up"
                    Text {
                        text: "󰅀"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: rootObj.s(14)
                        color: tokensSources.expanded ? ThemeBackend.text : ThemeBackend.overlay2
                        rotation: tokensSources.expanded ? 180 : 0
                        // Plain ease, no overshoot: a chevron that bounces reads as a glitch.
                        Behavior on rotation { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                    }
                }
                Item {
                    id: tokensBody
                    Layout.fillWidth: true
                    clip: true
                    visible: tokensSources.progress > 0.001
                    implicitHeight: (tokensRows.implicitHeight + rootObj.s(4)) * tokensSources.progress
                    opacity: Math.min(1.0, tokensSources.progress * 2.5)
                    RowLayout {
                        id: tokensRows
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.topMargin: rootObj.s(4)
                        spacing: rootObj.s(6)
                        Item {
                            Layout.preferredWidth: rootObj.s(20)
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.topMargin: rootObj.s(2); anchors.bottomMargin: rootObj.s(2)
                                width: Math.max(1, rootObj.s(2))
                                radius: rootObj.s(1)
                                color: Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.7)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            SettingsRow {
                                rootObj: root.rootObj; settingId: "addons_tokens_codex"; searchTab: "addons"; searchKeywords: "codex openai tokens"
                                title: "Codex"; customLeftContent: Component { PlatformLogo { logo: "codex.svg"; tint: ThemeBackend.text } }
                                description: "Codex sessions and the account total."; wrapText: true
                                opacity: tokensSources.stagger(0)
                                transform: Translate { y: rootObj.s(-8) * (1 - tokensSources.stagger(0)) }
                                Toggle {
                                    checked: Config.getSetting("addonsV2TokensCodex", true)
                                    accentColor: ThemeBackend.mauve
                                    onToggled: { Config.setSetting("addonsV2TokensCodex", checked); }
                                }
                            }
                            SettingsRow {
                                rootObj: root.rootObj; settingId: "addons_tokens_claude"; searchTab: "addons"; searchKeywords: "claude anthropic tokens"
                                title: "Claude Code"; customLeftContent: Component { PlatformLogo { logo: "claudecode.svg"; tint: ThemeBackend.peach } }
                                description: "Claude Code transcripts, subagents included."; wrapText: true
                                opacity: tokensSources.stagger(1)
                                transform: Translate { y: rootObj.s(-8) * (1 - tokensSources.stagger(1)) }
                                Toggle {
                                    checked: Config.getSetting("addonsV2TokensClaude", true)
                                    accentColor: ThemeBackend.mauve
                                    onToggled: { Config.setSetting("addonsV2TokensClaude", checked); }
                                }
                            }
                            SettingsRow {
                                rootObj: root.rootObj; settingId: "addons_tokens_opencode"; searchTab: "addons"; searchKeywords: "opencode sessions tokens"
                                title: "opencode"; customLeftContent: Component { PlatformLogo { logo: "opencode.svg"; tint: ThemeBackend.green } }
                                description: "Totals of opencode sessions, read from its local database."; wrapText: true
                                opacity: tokensSources.stagger(2)
                                transform: Translate { y: rootObj.s(-8) * (1 - tokensSources.stagger(2)) }
                                Toggle {
                                    checked: Config.getSetting("addonsV2TokensOpencode", false)
                                    accentColor: ThemeBackend.mauve
                                    onToggled: { Config.setSetting("addonsV2TokensOpencode", checked); }
                                }
                            }
                            SettingsRow {
                                id: llamaSettingsRow
                                rootObj: root.rootObj; settingId: "addons_tokens_llamacpp"; searchTab: "addons"; searchKeywords: "llama.cpp llama-server metrics tokens"
                                // The logo sits centred in the space left of the controls. The field and the dot take extra room on the right, so shift the logo back by half of it.
                                title: "llama.cpp"; customLeftContent: Component {
                                    PlatformLogo {
                                        logo: "llamacpp.svg"; tint: ThemeBackend.yellow
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.horizontalCenterOffset: (pingIndicator.width + urlField.width + 2 * llamaSettingsRow.controlSpacing) / 2
                                    }
                                }
                                wrapText: true
                                description: urlField.text.trim() === "dash" ? qsTr("Dashboard settings unlocked below.") : qsTr("Reads the /metrics of llama-server (start it with --metrics). Counts from when it is first seen.")
                                opacity: tokensSources.stagger(3)
                                transform: Translate { y: rootObj.s(-8) * (1 - tokensSources.stagger(3)) }
                                // Ping state: idle | pinging | ok | fail. The probe is a curl on the server's /metrics.
                                QtObject {
                                    id: llamaProbe
                                    property string pingState: "idle"
                                    property string target: ""
                                    function ping() {
                                        const url = urlField.text.trim();
                                        pingState = "pinging";
                                        target = url !== "" ? url : "http://127.0.0.1:8080";
                                        llamaCurl.running = false;
                                        llamaCurl.running = true;
                                    }
                                    Component.onCompleted: if (Config.getSetting("addonsV2TokensLlamaCpp", false)) ping()
                                }
                                Process {
                                    id: llamaCurl
                                    command: ["curl", "-sf", "-m", "3", "-o", "/dev/null", llamaProbe.target + "/metrics"]
                                    onExited: (exitCode, exitStatus) => {
                                        if (exitCode === 0) {
                                            llamaProbe.pingState = "ok";
                                            successRing.restart();
                                        } else {
                                            llamaProbe.pingState = "fail";
                                            urlField.triggerShake();
                                        }
                                    }
                                }
                                Item {
                                    id: pingIndicator
                                    Layout.preferredWidth: rootObj.s(16)
                                    Layout.preferredHeight: rootObj.s(16)
                                    Layout.alignment: Qt.AlignVCenter
                                    Rectangle {
                                        id: pingRing
                                        anchors.centerIn: parent
                                        width: rootObj.s(8); height: width; radius: width / 2
                                        color: "transparent"; border.width: 1; border.color: ThemeBackend.green
                                        opacity: 0
                                        visible: llamaProbe.pingState === "pinging" || successRing.running
                                    }
                                    Rectangle {
                                        id: pingDot
                                        anchors.centerIn: parent
                                        width: rootObj.s(8); height: width; radius: width / 2
                                        color: llamaProbe.pingState === "ok" ? ThemeBackend.green
                                             : llamaProbe.pingState === "fail" ? ThemeBackend.red
                                             : llamaProbe.pingState === "pinging" ? ThemeBackend.yellow : ThemeBackend.surface2
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text {
                                        id: pingCheck
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: ThemeBackend.green
                                        font.family: ThemeBackend.fontFamily; font.bold: true
                                        font.pixelSize: rootObj.s(11)
                                        opacity: llamaProbe.pingState === "ok" ? 1 : 0
                                        scale: llamaProbe.pingState === "ok" ? 1 : 0.4
                                        Behavior on opacity { NumberAnimation { duration: 300 } }
                                        Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
                                    }
                                    ParallelAnimation {
                                        running: llamaProbe.pingState === "pinging"
                                        loops: Animation.Infinite
                                        ScaleAnimator { target: pingRing; from: 1; to: 2.4; duration: 1000; easing.type: Easing.OutCubic }
                                        OpacityAnimator { target: pingRing; from: 0.9; to: 0; duration: 1000; easing.type: Easing.OutCubic }
                                    }
                                    ParallelAnimation {
                                        id: successRing
                                        ScaleAnimator { target: pingRing; from: 1; to: 3; duration: 700; easing.type: Easing.OutCubic }
                                        OpacityAnimator { target: pingRing; from: 1; to: 0; duration: 700; easing.type: Easing.OutCubic }
                                    }
                                }
                                Input {
                                    id: urlField
                                    Layout.preferredWidth: rootObj.s(170)
                                    Layout.alignment: Qt.AlignVCenter
                                    text: Config.getSetting("addonsV2TokensLlamaCppUrl", "")
                                    placeholderText: "http://127.0.0.1:8080"
                                    isBusy: llamaProbe.pingState === "pinging"
                                    hasError: llamaProbe.pingState === "fail"
                                    accentColor: llamaProbe.pingState === "ok" ? ThemeBackend.green : ThemeBackend.yellow
                                    baseColor: ThemeBackend.surface0
                                    textColor: ThemeBackend.text
                                    borderColor: ThemeBackend.surface2
                                    onAccepted: finalText => {
                                        if (finalText.trim() === "dash") return;
                                        Config.setSetting("addonsV2TokensLlamaCppUrl", finalText.trim());
                                        llamaProbe.ping();
                                    }
                                }
                                Toggle {
                                    checked: Config.getSetting("addonsV2TokensLlamaCpp", false)
                                    accentColor: ThemeBackend.mauve
                                    onToggled: { Config.setSetting("addonsV2TokensLlamaCpp", checked); }
                                }
                            }
                            Item {
                                id: dashboardReveal
                                readonly property bool unlocked: urlField.text.trim() === "dash"
                                onUnlockedChanged: if (unlocked && !dashboardPasswordWriter.running) dashboardPasswordCheck.running = true
                                property real progress: unlocked ? 1 : 0
                                Behavior on progress { NumberAnimation { duration: dashboardReveal.unlocked ? 380 : 240; easing.type: Easing.OutCubic } }
                                Layout.fillWidth: true
                                implicitHeight: dashboardContent.implicitHeight * progress
                                visible: progress > 0.001
                                clip: true

                                ColumnLayout {
                                    id: dashboardContent
                                    width: parent.width
                                    spacing: rootObj.s(6)
                                    opacity: dashboardReveal.progress
                                    transform: Translate { y: rootObj.s(-8) * (1 - dashboardReveal.progress) }

                                    SettingsRow {
                                        rootObj: root.rootObj; searchable: false
                                        icon: "󰒍"
                                        title: qsTr("Dashboard sync")
                                        description: Config.getSetting("addonsV2TokensDashboard", false)
                                            ? qsTr("Enabled · refreshes every 3 seconds") : qsTr("Use the dashboard’s synchronized total")
                                        wrapText: true
                                        Toggle {
                                            checked: Config.getSetting("addonsV2TokensDashboard", false)
                                            accentColor: ThemeBackend.mauve
                                            onToggled: Config.setSetting("addonsV2TokensDashboard", checked)
                                        }
                                    }
                                    SettingsRow {
                                        rootObj: root.rootObj; searchable: false
                                        icon: "󰖟"; title: qsTr("Dashboard URL")
                                        description: qsTr("Press Enter to save the HTTPS address.")
                                        wrapText: true
                                        Input {
                                            Layout.preferredWidth: rootObj.s(240)
                                            text: Config.getSetting("addonsV2TokensDashboardUrl", "https://dash.brighter-builds.com")
                                            accentColor: ThemeBackend.mauve
                                            onAccepted: value => Config.setSetting("addonsV2TokensDashboardUrl", value.trim())
                                        }
                                    }
                                    SettingsRow {
                                        id: passwordRow
                                        rootObj: root.rootObj; searchable: false
                                        function savePassword() {
                                            if (dashboardPasswordWriter.running) return;
                                            if (!dashboardPassword.text) {
                                                dashboardPasswordWriter.result = -2;
                                                dashboardPassword.triggerShake();
                                                return;
                                            }
                                            dashboardPasswordWriter.result = 0;
                                            dashboardPasswordWriter.running = true;
                                            dashboardPasswordWriter.write(dashboardPassword.text + "\n");
                                        }
                                        icon: "󰌾"; title: qsTr("Dashboard password")
                                        description: dashboardPasswordWriter.running ? qsTr("Saving password…")
                                            : dashboardPasswordWriter.result === 1 ? qsTr("Password saved on this device.")
                                            : dashboardPasswordWriter.result === -1 ? qsTr("Could not save. Your entry is still here; try again.")
                                            : dashboardPasswordWriter.result === -2 ? qsTr("Enter a password before saving.")
                                            : dashboardPassword.text.length > 0 ? qsTr("Not saved yet. Press Enter or Save.")
                                            : dashboardPasswordCheck.running || dashboardPasswordCheck.state === -1 ? qsTr("Checking saved password…")
                                            : dashboardPasswordCheck.state === 1 ? qsTr("Password saved on this device. Enter a new one to replace it.")
                                            : dashboardPasswordCheck.state === 2 ? qsTr("Cannot read the saved password. Check file permissions.")
                                            : qsTr("No password saved. Enter one to connect.")
                                        wrapText: true
                                        Text {
                                            readonly property bool error: dashboardPasswordWriter.result < 0 || (!dashboardPassword.text && dashboardPasswordCheck.state === 2)
                                            readonly property bool saved: dashboardPasswordWriter.result === 1 || (!dashboardPassword.text && dashboardPasswordCheck.state === 1)
                                            text: dashboardPasswordWriter.running || dashboardPasswordCheck.running ? "󰔟" : error ? "󰀪" : saved ? "󰄬" : "󰌾"
                                            font.family: ThemeBackend.iconFont; font.pixelSize: rootObj.s(16)
                                            color: error ? ThemeBackend.red : saved ? ThemeBackend.green : ThemeBackend.subtext0
                                            Accessible.ignored: true
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                        Input {
                                            id: dashboardPassword
                                            Layout.preferredWidth: rootObj.s(160)
                                            masked: true; revealTyping: false
                                            accentColor: ThemeBackend.mauve
                                            hasError: dashboardPasswordWriter.result < 0
                                            isBusy: dashboardPasswordWriter.running
                                            placeholderText: dashboardPasswordCheck.state === 1 ? qsTr("New password") : qsTr("Password")
                                            enabled: !dashboardPasswordWriter.running
                                            onTextEdited: dashboardPasswordWriter.result = 0
                                            onAccepted: value => passwordRow.savePassword()
                                        }
                                        ClickButton {
                                            buttonText: qsTr("Save")
                                            accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                                            enabled: !dashboardPasswordWriter.running
                                            onTriggered: passwordRow.savePassword()
                                        }
                                        Process {
                                            id: dashboardPasswordCheck
                                            property int state: -1
                                            command: ["sh", "-c", "p=\"${XDG_CONFIG_HOME:-$HOME/.config}/serpantinum/tokens/dashboard-password\"; if [ ! -e \"$p\" ]; then exit 1; elif [ ! -r \"$p\" ]; then exit 2; elif [ ! -s \"$p\" ]; then exit 1; fi"]
                                            onExited: code => state = code === 0 ? 1 : code === 1 ? 0 : 2
                                        }
                                        Process {
                                            id: dashboardPasswordWriter
                                            property int result: 0
                                            command: ["sh", "-c", "umask 077; d=\"${XDG_CONFIG_HOME:-$HOME/.config}/serpantinum/tokens\"; mkdir -p \"$d\" && chmod 700 \"$d\" && t=$(mktemp \"$d/.password.XXXXXX\") && head -n1 > \"$t\" && mv -f \"$t\" \"$d/dashboard-password\""]
                                            stdinEnabled: true
                                            onExited: (exitCode, exitStatus) => {
                                                result = exitCode === 0 ? 1 : -1;
                                                if (exitCode === 0) {
                                                    dashboardPassword.text = "";
                                                    dashboardPasswordCheck.state = 1;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            // Separator: the account scope is a setting about Codex, not a fifth provider.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.5)
                            }
                            SettingsRow {
                                rootObj: root.rootObj; settingId: "addons_tokens_codex_scope"; searchTab: "addons"; searchKeywords: "codex account compte total local ce pc this pc device appareil sync synchro"
                                icon: "󰓅"
                                title: "Codex account total"
                                description: Config.getSetting("addonsV2TokensCodexAccount", true)
                                    ? "On: lifetime total of your Codex account, all devices (synced)."
                                    : "Off: only the tokens run on this PC."
                                wrapText: true
                                opacity: tokensSources.stagger(4)
                                transform: Translate { y: rootObj.s(-8) * (1 - tokensSources.stagger(4)) }
                                Toggle {
                                    checked: Config.getSetting("addonsV2TokensCodexAccount", true)
                                    accentColor: ThemeBackend.mauve
                                    onToggled: { Config.setSetting("addonsV2TokensCodexAccount", checked); }
                                }
                            }
                        }
                    }
                }
            }
            // Passive addons: same fold as the tokens header, but open by default.
            ColumnLayout {
                id: passiveSection
                property bool expanded: true
                // Search and the highlight call holdOpen/releaseOpen on the owner group (same contract as SettingsGroup).
                property int openHolds: 0
                readonly property bool isOpen: expanded || openHolds > 0
                function holdOpen() { openHolds++; }
                function releaseOpen() { if (openHolds > 0) openHolds--; }
                property real progress: isOpen ? 1 : 0
                Behavior on progress { NumberAnimation { duration: passiveSection.isOpen ? 420 : 280; easing.type: passiveSection.isOpen ? Easing.OutCubic : Easing.InOutQuad } }
                function stagger(i) { return Math.max(0, Math.min(1, (progress - Math.min(i * 0.05, 0.35)) / 0.65)); }
                Layout.fillWidth: true
                spacing: 0
                SettingsRow {
                    rootObj: root.rootObj
                    clickable: true
                    onClicked: passiveSection.expanded = !passiveSection.expanded
                    settingId: "addons_passive_group"; searchable: false
                    icon: "󰐱"
                    title: "Passive addons"
                    description: "Shell tools enabled without individual switches"
                    Text {
                        text: "󰅀"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: rootObj.s(14)
                        color: passiveSection.expanded ? ThemeBackend.text : ThemeBackend.overlay2
                        rotation: passiveSection.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                    }
                }
                Item {
                    id: passiveBody
                    readonly property bool isGroupSubWrapper: true
                    readonly property var ownerGroup: passiveSection
                    Layout.fillWidth: true
                    clip: true
                    visible: passiveSection.progress > 0.001
                    implicitHeight: (passiveRows.implicitHeight + rootObj.s(4)) * passiveSection.progress
                    opacity: Math.min(1.0, passiveSection.progress * 2.5)
                    RowLayout {
                        id: passiveRows
                        layoutDirection: I18n.layoutDirection
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.topMargin: rootObj.s(4)
                        spacing: rootObj.s(6)
                        Item {
                            Layout.preferredWidth: rootObj.s(20)
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.topMargin: rootObj.s(2); anchors.bottomMargin: rootObj.s(2)
                                width: Math.max(1, rootObj.s(2))
                                radius: rootObj.s(1)
                                color: Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.7)
                            }
                        }
                        ColumnLayout {
                            id: passiveList
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Repeater {
                                model: [
                                    { id: "addons_passive_desktop_draw", title: "Desktop drawing", icon: "󰏫", keywords: "desktop draw drawing annotation pen circle rectangle dessiner entourer dessin addonDesktopDraw", detail: "Super+Shift+D · Draw, circle or box · Esc to close" },
                                    { id: "addons_passive_desktop_zoom", title: "Desktop zoom", icon: "󰍉", keywords: "desktop zoom magnifier loupe souris curseur raccourci addonDesktopZoom", detail: "Super+Shift+Z · Scroll to zoom · Esc to close" },
                                    { id: "addons_passive_color_picker", title: "Color picker", icon: "󰈊", keywords: "color picker pipette palette couleur", detail: "Super+Shift+C" },
                                    { id: "addons_passive_screenshot", title: "Screenshot tools", icon: "󰹑", keywords: "screenshot capture freeze screenshot tool capture écran image", detail: "Frozen capture fixed · Super+Shift+S" },
                                    { id: "addons_passive_tokens", title: "AI Tokens counter", icon: "󰞷", keywords: "AI tokens counter Codex Claude usage compteur jetons", detail: "Widget and bar module · Codex + Claude usage" },
    // BEGIN serpantinum-gcal-v2 row
                                    { id: "addons_passive_calendar", title: "Calendar", icon: "󰃭", keywords: "calendar agenda google ical ics events meeting calendrier événement rendez-vous rappel addonCalendar", detail: "Super+G / Super+I · Google Calendar & iCal · day stream in the clock panel (Super+S) · options in Calendar" },
    // END serpantinum-gcal-v2 row
                                    { id: "addons_passive_monitors", title: "Monitor tools", icon: "󰍹", keywords: "monitor display screen monitors écran", detail: "Display tools for connected monitors" },
                                    { id: "addons_passive_screen_switch", title: "Next screen", icon: "󰆽", keywords: "screen monitor next switch Super Tab écran moniteur", detail: "Super+Tab · Move pointer to the screen centre" },
                                    { id: "addons_passive_window_switch", title: "Next window", icon: "󰖯", keywords: "window next switch Alt Tab fenêtre", detail: "Alt+Tab · Next window on this screen and workspace" },
                                    { id: "addons_passive_keybinds", title: "Keybind editor", icon: "󰌌", keywords: "keybind shortcut keyboard raccourci clavier", detail: "Edit and record shell shortcuts" },
                                    { id: "addons_passive_beamer", title: "Beamer (KVM)", icon: Qt.resolvedUrl("../tokens/assets/logos/beamer.svg"), keywords: "beamer kvm mouse keyboard clipboard share pc souris clavier presse-papier", detail: "Crossing effects and shared clipboard between the two PCs" },
                                    { id: "addons_passive_theme_modes", title: "Vibrant and Vivid theme modes", icon: "󰏘", keywords: "theme matugen vibrant vivid color mode thème", detail: "Colour modes for the shell palette" }
                                ]
                                delegate: SettingsRow {
                                    required property var modelData
                                    required property int index
                                    rootObj: root.rootObj
                                    settingId: modelData.id; searchTab: "addons"; searchKeywords: modelData.keywords
                                    title: modelData.title; icon: modelData.icon; description: modelData.detail
                                    wrapText: true
                                    iconSize: 24; iconFontSize: 12
                                    verticalPadding: rootObj.s(6)
                                    titlePixelSize: 12; descriptionPixelSize: 10
                                    readonly property real reveal: passiveSection.stagger(index)
                                    opacity: reveal
                                    transform: Translate { y: rootObj.s(-8) * (1 - reveal) }

                                    Text {
                                        text: modelData.status || "Enabled"
                                        color: ThemeBackend.green
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SettingsGroup {
                rootObj: root.rootObj
                settingId: "addons_maintenance"; searchTab: "addons"; searchable: true
                searchKeywords: "addons version update upgrade reinstall uninstall remove changelog release mise à jour désinstaller supprimer"
                icon: "󰏗"
                title: "Addons maintenance"
                description: "Version, updates and removal"
                subSettings: [
                    AddonsReleaseCard { rootObj: root.rootObj; showUninstall: true }
                ]
            }
        }
    }
}
