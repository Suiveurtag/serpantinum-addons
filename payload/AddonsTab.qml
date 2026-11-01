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
            SettingsGroup {
                rootObj: root.rootObj
                icon: "󰐱"
                title: "Passive addons"
                description: "Shell tools enabled without individual switches"
                subSettings: [
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)
                        Repeater {
                            model: [
                                { id: "addons_passive_desktop_draw", title: "Desktop drawing", icon: "󰏫", keywords: "desktop draw drawing annotation pen circle rectangle dessiner entourer dessin addonDesktopDraw", detail: "Super+Shift+D · Draw, circle or box · Esc to close" },
                                { id: "addons_passive_desktop_zoom", title: "Desktop zoom", icon: "󰍉", keywords: "desktop zoom magnifier loupe souris curseur raccourci addonDesktopZoom", detail: "Super+Shift+Z · Scroll to zoom · Esc to close" },
                                { id: "addons_passive_color_picker", title: "Color picker", icon: "󰈊", keywords: "color picker pipette palette couleur", detail: "Super+Shift+C" },
                                { id: "addons_passive_screenshot", title: "Screenshot tools", icon: "󰹑", keywords: "screenshot capture freeze screenshot tool capture écran image", detail: "Frozen capture fixed · Super+Shift+S" },
                                { id: "addons_passive_tokens", title: "AI Tokens counter", icon: "󰞷", keywords: "AI tokens counter Codex Claude usage compteur jetons", detail: "Widget and bar module · Codex + Claude usage" },
                                { id: "addons_passive_monitors", title: "Monitor tools", icon: "󰍹", keywords: "monitor display screen monitors écran", detail: "Display tools for connected monitors" },
                                { id: "addons_passive_screen_switch", title: "Next screen", icon: "󰍹", keywords: "screen monitor next switch Super Tab écran moniteur", detail: "Super+Tab · Move pointer to the screen centre" },
                                { id: "addons_passive_window_switch", title: "Next window", icon: "󰖯", keywords: "window next switch Alt Tab fenêtre", detail: "Alt+Tab · Next window on this screen and workspace" },
                                { id: "addons_passive_keybinds", title: "Keybind editor", icon: "󰌌", keywords: "keybind shortcut keyboard raccourci clavier", detail: "Edit and record shell shortcuts" },
                                { id: "addons_passive_theme_modes", title: "Vibrant and Vivid theme modes", icon: "󰏘", keywords: "theme matugen vibrant vivid color mode thème", detail: "Colour modes for the shell palette" }
                            ]
                            delegate: SettingsRow {
                                required property var modelData
                                rootObj: root.rootObj
                                settingId: modelData.id; searchTab: "addons"; searchKeywords: modelData.keywords
                                title: modelData.title; icon: modelData.icon; description: modelData.detail
                                wrapText: true
                                iconSize: 24; iconFontSize: 12
                                verticalPadding: rootObj.s(6)
                                titlePixelSize: 12; descriptionPixelSize: 10

                                Text {
                                    text: modelData.status || "Enabled"
                                    color: ThemeBackend.green
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                }
                            }
                        }
                    }
                ]
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
