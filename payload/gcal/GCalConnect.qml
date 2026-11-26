import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Onboarding screen of the agenda while no calendar is configured: points to Settings → Calendar,
// where accounts and preferences now live.
Item {
    id: root
    required property Item agenda
    property bool open: false
    property bool onboarding: false
    function s(v) { return Scaler.s(v); }
    readonly property color accent: agenda.accent
    readonly property bool connecting: GCal.connectProc !== null

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.s(520), parent.width - root.s(40))
        spacing: root.s(16)
        visible: root.onboarding && root.open

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.s(72); Layout.preferredHeight: root.s(72)
            Rectangle {
                anchors.fill: parent
                radius: root.s(20)
                color: Qt.alpha(root.accent, 0.18)
            }
            Text {
                anchors.centerIn: parent
                text: GCal.icon.calendar
                font.family: ThemeBackend.iconFont
                font.pixelSize: parent.width * 0.5
                color: root.accent
            }
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: GCal.tr("Your calendar, in the shell", "Ton agenda, dans le shell")
            font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(22)
            color: ThemeBackend.text
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.connecting ? GCal.tr("Connecting to Google… finish in your browser.", "Connexion à Google… termine dans ton navigateur.")
                : GCal.tr("Google Calendar is fully editable. iCal links (Outlook, iCloud, school timetables, holidays…) are shown read only. Add them in Settings → Calendar.",
                          "Google Agenda est entièrement modifiable. Les liens iCal (Outlook, iCloud, emplois du temps, jours fériés…) sont en lecture seule. Ajoute-les dans Réglages → Calendar.")
            font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(12)
            color: ThemeBackend.overlay1
            wrapMode: Text.WordWrap
        }
        ClickButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.s(38); Layout.preferredWidth: implicitWidth + root.s(16)
            buttonText: GCal.tr("Open calendar settings", "Ouvrir les réglages du calendrier")
            buttonIcon: GCal.icon.cog
            textFontSize: root.s(12.5); iconFontSize: root.s(15); cornerRadius: root.s(12)
            accentColor: root.accent; textColor: GCal.readableOn(root.accent)
            onClicked: GCal.openSettings()
        }
    }
}
