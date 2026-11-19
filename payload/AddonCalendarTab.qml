import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"
import "../reusables"
import "../reusables/guide"

// Settings → Calendar: Google account, iCal subscriptions and the calendar preferences.
Item {
    id: root
    required property var rootObj
    required property int tabIndex
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    function s(value) { return rootObj.s(value); }

    Flickable {
        anchors.fill: parent; anchors.margins: rootObj.s(24)
        contentWidth: width; contentHeight: settings.implicitHeight + rootObj.s(24); clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(8)

            SettingsRow {
                rootObj: root.rootObj; settingId: "addon_calendar_enabled"; searchTab: "addon_calendar"
                searchKeywords: "calendar enable disable off feature agenda clock panel agenda désactiver activer calendrier"
                title: "Enable calendar"; icon: "󰃭"; wrapText: true
                description: "Off: the clock panel goes back to the native one, Super+G and Super+I do nothing, and syncing and reminders stop."
                Toggle {
                    checked: GCal.enabled
                    accentColor: ThemeBackend.mauve
                    onToggled: {
                        GCal.setEnabled(checked);
                        checked = Qt.binding(function() { return GCal.enabled; });
                    }
                }
            }

            SettingsRow {
                visible: GCal.enabled
                rootObj: root.rootObj; settingId: "addon_calendar_preview"; searchTab: "addon_calendar"
                searchKeywords: "calendar preview clock panel timeline events agenda aperçu horloge panneau événements"
                title: "Calendar preview in clock panel"; icon: "󰃭"; wrapText: true
                description: "Show the day's events beneath the clock. The agenda remains available when this is off."
                Toggle {
                    checked: GCal.previewEnabled
                    accentColor: ThemeBackend.mauve
                    onToggled: GCal.setPreviewEnabled(checked)
                }
            }

            SettingsRow {
                visible: GCal.enabled
                rootObj: root.rootObj; settingId: "addon_calendar_google"; searchTab: "addon_calendar"
                searchKeywords: "calendar google agenda account oauth connect sync compte connexion"
                title: "Google Calendar"; icon: "󰊭"; wrapText: true
                description: GCal.google ? (GCal.account || "Connected") + " · synced every 5 minutes" : "Read and write your Google calendars (needs your own OAuth client)."
            }
            GCalGoogleSetup { visible: GCal.enabled; Layout.fillWidth: true; header: false; accent: ThemeBackend.mauve; open: root.visible }

            SettingsRow {
                visible: GCal.enabled
                rootObj: root.rootObj; settingId: "addon_calendar_ics"; searchTab: "addon_calendar"
                searchKeywords: "ical ics webcal subscription feed outlook icloud holidays abonnement lien jours fériés"
                title: "iCal subscriptions"; icon: "󰑫"; wrapText: true
                description: "Any http(s):// or webcal:// feed, shown read only."
            }
            GCalIcsSources { visible: GCal.enabled; Layout.fillWidth: true; header: false; accent: ThemeBackend.mauve }

            SettingsRow {
                rootObj: root.rootObj; settingId: "addon_calendar_reminders"; searchTab: "addon_calendar"
                searchKeywords: "calendar reminders notifications alerts rappel notification événement"
                title: "Reminder notifications"; description: "Notify before an event starts, with an Open button."; icon: "󰂚"
                visible: GCal.enabled && GCal.available
                Toggle {
                    checked: GCal.prefs.reminders !== false
                    accentColor: ThemeBackend.mauve
                    onToggled: GCal.setPrefs({ reminders: checked })
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addon_calendar_week_start"; searchTab: "addon_calendar"
                searchKeywords: "calendar week start monday sunday semaine premier jour lundi dimanche"
                title: "Week starts on"; description: "First day of the week in the agenda and the clock panel."; icon: "󰨳"
                visible: GCal.enabled && GCal.available
                GCalSegmented {
                    Layout.preferredWidth: root.s(220); Layout.preferredHeight: root.s(30)
                    accent: ThemeBackend.mauve
                    options: [{ id: "1", label: GCal.locale.dayName(1, Locale.LongFormat) }, { id: "0", label: GCal.locale.dayName(0, Locale.LongFormat) }]
                    current: String(GCal.prefs.weekStart === 0 ? 0 : 1)
                    onSelected: (id) => GCal.setPrefs({ weekStart: parseInt(id) })
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addon_calendar_default"; searchTab: "addon_calendar"
                searchKeywords: "calendar default new events calendrier par défaut nouveaux événements"
                title: "New events go to"; description: "Calendar used when you create an event."; icon: "󰐕"
                visible: GCal.enabled && GCal.writableCalendars.length > 1
                Flow {
                    Layout.preferredWidth: root.s(320)
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
