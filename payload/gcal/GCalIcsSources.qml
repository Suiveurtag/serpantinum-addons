import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// iCal subscriptions card: the list of read-only feeds and the form that adds one. Shown in Settings → Calendar.
Item {
    id: root
    property color accent: ThemeBackend.mauve
    property bool header: true
    function s(v) { return Scaler.s(v); }
    implicitHeight: icsCard.implicitHeight

    property string icsUrl: ""
    property string icsName: ""
    property bool icsBusy: false
    property string icsError: ""
    property string note: ""

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
                    visible: root.header
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
                                if (r.ok) { urlInput.clear(); root.icsUrl = ""; root.note = GCal.tr("%1 events imported", "%1 événements importés").arg(r.events || 0); }
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
