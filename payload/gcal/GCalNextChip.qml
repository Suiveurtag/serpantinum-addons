import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// "Next event" pill under the clock: colour dot (breathing when the event is close), title and a rolling countdown.
// An ongoing event fills the pill like a progress bar. Click opens the agenda on that event.
Item {
    id: root
    property color accent: ThemeBackend.mauve
    property real intro: 1
    property bool allowed: true

    readonly property var ev: GCal.nextEvent
    readonly property bool shown: !!ev && allowed
    readonly property color tone: ev ? GCal.colorOf(ev) : accent
    readonly property bool ongoing: !!ev && ev.start <= GCal.now
    readonly property bool imminent: !!ev && (ongoing || ev.start - GCal.now < 15 * 60000)
    readonly property real progress: ongoing ? Math.max(0, Math.min(1, (GCal.now - ev.start) / Math.max(1, ev.end - ev.start))) : 0

    function s(v) { return Scaler.s(v); }

    Layout.preferredHeight: s(30) * reveal
    Layout.preferredWidth: pill.width
    implicitWidth: pill.width
    implicitHeight: s(30)

    property real reveal: shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
    opacity: Math.min(1, reveal) * intro
    visible: opacity > 0.01

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: (1 - root.reveal) * root.s(10)
        height: root.s(30)
        width: Math.min(root.s(360), row.implicitWidth + root.s(26))
        radius: height / 2
        scale: (hover.hovered ? 1.04 : 1.0) * (tap.pressed ? 0.97 : 1.0) * (0.86 + 0.14 * Math.min(1, root.reveal))
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        color: glass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, hover.hovered ? 0.75 : 0.5)
        border.width: 1
        border.color: Qt.alpha(root.tone, hover.hovered ? 0.55 : 0.28)
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }
        clip: true

        GlassFill {
            id: glass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.surface0
            tintAmount: 0.25
            press: tap.pressed ? 0.8 : (hover.hovered ? 0.3 : 0)
        }

        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: parent.width * root.progress
            radius: parent.radius
            color: Qt.alpha(root.tone, 0.2)
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: root.s(8)

            Item {
                Layout.preferredWidth: root.s(10); Layout.preferredHeight: root.s(10)
                Rectangle {
                    id: halo
                    anchors.centerIn: parent
                    width: root.s(10); height: width; radius: width / 2
                    color: root.tone
                    opacity: 0
                    SequentialAnimation on scale {
                        running: root.imminent && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 2.4; duration: 1400; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 300 }
                    }
                    SequentialAnimation on opacity {
                        running: root.imminent && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 300 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: root.s(8); height: width; radius: width / 2
                    color: root.tone
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }

            GCalRollText {
                Layout.alignment: Qt.AlignVCenter
                text: root.ev ? (root.ev.title || GCal.tr("(No title)", "(Sans titre)")) : ""
                maxWidth: root.s(190)
                pixelSize: root.s(12.5)
                weight: Font.Black
                color: ThemeBackend.text
            }

            Text {
                text: "·"
                color: ThemeBackend.overlay1
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.s(12)
                font.weight: Font.Black
            }

            GCalRollText {
                Layout.alignment: Qt.AlignVCenter
                text: GCal.relative(root.ev)
                pixelSize: root.s(12)
                weight: Font.Bold
                color: root.imminent ? Qt.tint(root.tone, Qt.alpha(ThemeBackend.text, 0.35)) : ThemeBackend.subtext0
            }

            Text {
                visible: !!root.ev && !!root.ev.meet
                text: GCal.icon.video
                color: root.tone
                font.family: ThemeBackend.iconFont
                font.pixelSize: root.s(13)
            }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: tap
            onTapped: if (root.ev) GCal.openAgenda("day", new Date(root.ev.start), root.ev.id)
        }
    }
}
