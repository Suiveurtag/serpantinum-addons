import QtQuick
import "../"

// Expanding list of times (every 15 min). Opens with a height spring, scrolls to the current value,
// the selected entry carries an accent pill. `relativeTo` adds a duration hint ("1 h 30") for end times.
Item {
    id: root
    property bool open: false
    property int minutes: 540               // selected minutes since midnight
    property int relativeTo: -1             // start minutes, for end-time duration hints
    property color accent: ThemeBackend.mauve
    signal picked(int minutes)
    function s(v) { return Scaler.s(v); }

    implicitHeight: open ? s(196) : 0
    Behavior on implicitHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    clip: true
    visible: implicitHeight > 0.5
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 240 } }

    onOpenChanged: if (open) Qt.callLater(() => list.positionViewAtIndex(Math.max(0, Math.round(root.minutes / 15) - 3), ListView.Beginning))

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.s(6)
        radius: root.s(12)
        color: Qt.alpha(ThemeBackend.surface0, 0.45)

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: root.s(4)
            clip: true
            model: 96
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: entry
                required property int index
                readonly property int value: index * 15
                readonly property bool selected: value === root.minutes
                width: ListView.view.width
                height: root.s(30)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.s(1)
                    radius: root.s(8)
                    color: entry.selected ? root.accent : (ma.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.7) : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.s(12)
                    spacing: root.s(10)
                    Text {
                        text: GCal.fmtTime(new Date(2000, 0, 1, 0, entry.value).getTime())
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: root.s(12)
                        color: entry.selected ? GCal.readableOn(root.accent) : ThemeBackend.text
                    }
                    Text {
                        visible: root.relativeTo >= 0 && entry.value > root.relativeTo
                        text: GCal.fmtDuration(entry.value - root.relativeTo)
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: root.s(11)
                        color: entry.selected ? Qt.alpha(GCal.readableOn(root.accent), 0.75) : ThemeBackend.overlay1
                    }
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(entry.value) }
            }
        }
    }
}
