import QtQuick
import QtQuick.Layouts
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
    Flickable {
        id: addonsViewport
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)
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
                rootObj: root.rootObj; settingId: "addons_weather_city_obfuscation"; searchTab: "addons"; searchKeywords: "weather city location privacy obfuscated météo ville localisation"
                title: "Obfuscate weather location"; description: "Scramble the city name in the weather widget."; icon: "󰖟"
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
                rootObj: root.rootObj; settingId: "addons_legacy_clock"; searchTab: "addons"; searchKeywords: "calendar clock legacy horloge calendrier"
                title: "Legacy clock design"; description: "Restore the v1 calendar and clock panel."; icon: "󰥔"
                Toggle {
                    checked: Config.getSetting("addonsV2LegacyClock", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2LegacyClock", checked); }
                }
            }
            AddonGlassSurface {
                id: passiveAddonsCard
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(18)
                radius: ThemeBackend.borderRadius
                surfaceColor: Qt.alpha(ThemeBackend.surface0, 0.72)
                border.width: rootObj.s(1)
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)
                implicitHeight: passiveContent.implicitHeight + rootObj.s(28)

                ColumnLayout {
                    id: passiveContent
                    anchors.fill: parent
                    anchors.margins: rootObj.s(14)
                    spacing: rootObj.s(8)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)
                        AddonGlassSurface {
                            Layout.preferredWidth: rootObj.s(34)
                            Layout.preferredHeight: rootObj.s(34)
                            radius: ThemeBackend.borderRadius
                            surfaceColor: ThemeBackend.surface1
                            Text {
                                anchors.centerIn: parent
                                text: "󰐱"
                                color: ThemeBackend.text
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: rootObj.s(17)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(2)
                            Text {
                                text: "Passive addons"
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Shell tools enabled without individual switches"
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(10)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    AddonGlassSurface {
                        Layout.fillWidth: true
                        Layout.topMargin: rootObj.s(2)
                        Layout.bottomMargin: rootObj.s(2)
                        height: rootObj.s(1)
                        surfaceColor: Qt.alpha(ThemeBackend.surface2, 0.65)
                    }

                    Repeater {
                        model: [
                            // BEGIN serpantinum-capri-v2 shortcut
                            { id: "addons_capri_shortcut_passive", title: "Capri shortcut", icon: "󰩃", keywords: "capri pet desktop companion compagnon Super Shift K ipc call capri toggle", detail: "Super+Shift+K · Toggle the desktop companion", status: "Shortcut" },
                            // END serpantinum-capri-v2 shortcut
                            // BEGIN serpantinum-clawd-v2 shortcut
                            { id: "addons_clawd_shortcut_passive", title: "Clawd shortcut", icon: "󰚩", keywords: "clawd claude pet desktop companion Super Shift L ipc call clawd toggle", detail: "Super+Shift+L · Toggle Clawd", status: "Shortcut" },
                            // END serpantinum-clawd-v2 shortcut
                            { id: "addons_passive_desktop_draw", title: "Desktop drawing", icon: "󰏫", keywords: "desktop draw drawing annotation pen circle rectangle dessiner entourer dessin addonDesktopDraw", detail: "Super+Shift+D · Draw, circle or box · Esc to close" },
                            { id: "addons_passive_desktop_zoom", title: "Desktop zoom", icon: "󰍉", keywords: "desktop zoom magnifier loupe souris curseur raccourci addonDesktopZoom", detail: "Super+Shift+Z · Scroll to zoom · Esc to close" },
                            { id: "addons_passive_color_picker", title: "Color picker", icon: "󰈊", keywords: "color picker pipette palette couleur", detail: "Super+Shift+C" },
                            { id: "addons_passive_screenshot", title: "Screenshot tools", icon: "󰹑", keywords: "screenshot capture freeze screenshot tool capture écran image", detail: "Frozen capture fixed · Super+Shift+S" },
                            { id: "addons_passive_monitors", title: "Monitor tools", icon: "󰍹", keywords: "monitor display screen monitors écran", detail: "" },
                            { id: "addons_passive_keybinds", title: "Keybind editor", icon: "󰌌", keywords: "keybind shortcut keyboard raccourci clavier", detail: "" },
                            { id: "addons_passive_theme_modes", title: "Vibrant and Vivid theme modes", icon: "󰏘", keywords: "theme matugen vibrant vivid color mode thème", detail: "" }
                        ]
                        delegate: SettingsRow {
                            required property var modelData
                            rootObj: root.rootObj
                            settingId: modelData.id; searchTab: "addons"; searchKeywords: modelData.keywords
                            title: modelData.title; icon: modelData.icon; description: modelData.detail
                            iconSize: 24; iconFontSize: 12
                            horizontalPadding: rootObj.s(8); verticalPadding: rootObj.s(6)
                            spacing: rootObj.s(10); innerSpacing: rootObj.s(4); textSpacing: rootObj.s(1)
                            titlePixelSize: 12; descriptionPixelSize: 10
                            baseColor: "transparent"; hoverColor: "transparent"

                            AddonGlassSurface {
                                Layout.preferredWidth: enabledLabel.implicitWidth + rootObj.s(18)
                                Layout.preferredHeight: rootObj.s(24)
                                radius: ThemeBackend.borderRadius
                                surfaceColor: Qt.alpha(ThemeBackend.green, 0.13)
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: rootObj.s(5)
                                    Rectangle {
                                        Layout.preferredWidth: rootObj.s(6)
                                        Layout.preferredHeight: rootObj.s(6)
                                        radius: width / 2
                                        color: ThemeBackend.green
                                    }
                                    Text {
                                        id: enabledLabel
                                        text: modelData.status || "Enabled"
                                        color: ThemeBackend.green
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(10)
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
