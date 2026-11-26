import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"

// Compact month grid with month navigation, event dots, a today ring and a highlight band
// that glides to the selected range (a day or a week).
Item {
    id: root
    property var selected: GCal.today          // highlighted day
    property bool weekBand: false              // highlight the whole week of `selected`
    property color accent: ThemeBackend.mauve
    property bool showDots: true
    signal picked(var date)

    function s(v) { return Scaler.s(v); }

    property var month: new Date(selected.getFullYear(), selected.getMonth(), 1)
    onSelectedChanged: month = new Date(selected.getFullYear(), selected.getMonth(), 1)

    readonly property var cells: {
        const first = GCal.weekStart(month);
        const out = [];
        for (let i = 0; i < 42; i++) out.push(GCal.addDays(first, i));
        return out;
    }

    implicitHeight: header.height + s(4) + names.height + grid.height
    implicitWidth: s(230)

    RowLayout {
        id: header
        width: parent.width
        height: root.s(28)
        spacing: root.s(4)
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: root.s(4)
            text: GCal.monthTitle(root.month).toUpperCase()
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(12)
            font.weight: Font.Black
            color: ThemeBackend.text
        }
        IconButton {
            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24)
            size: root.s(24); cornerRadius: root.s(7)
            buttonIcon: GCal.icon.left; iconFontSize: root.s(14)
            accentColor: ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
            onClicked: root.month = GCal.addMonths(root.month, -1)
        }
        IconButton {
            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24)
            size: root.s(24); cornerRadius: root.s(7)
            buttonIcon: GCal.icon.right; iconFontSize: root.s(14)
            accentColor: ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? root.accent : ThemeBackend.overlay1
            onClicked: root.month = GCal.addMonths(root.month, 1)
        }
    }

    Row {
        id: names
        anchors.top: header.bottom
        anchors.topMargin: root.s(4)
        width: parent.width
        height: root.s(18)
        Repeater {
            model: GCal.weekdayLetters()
            Text {
                width: names.width / 7
                horizontalAlignment: Text.AlignHCenter
                text: modelData.charAt(0)
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Black
                font.pixelSize: root.s(10)
                color: ThemeBackend.overlay1
            }
        }
    }

    Item {
        id: grid
        anchors.top: names.bottom
        width: parent.width
        readonly property real cw: width / 7
        readonly property real ch: root.s(26)
        height: ch * 6

        // Selection band: a rounded pill gliding to the selected day / week.
        Rectangle {
            readonly property int at: {
                for (let i = 0; i < 42; i++) if (GCal.sameDay(root.cells[i], root.selected)) return i;
                return -1;
            }
            visible: at >= 0
            x: root.weekBand ? 0 : (at % 7) * grid.cw + root.s(1)
            y: Math.floor(Math.max(0, at) / 7) * grid.ch + root.s(1)
            width: root.weekBand ? grid.width : grid.cw - root.s(2)
            height: grid.ch - root.s(2)
            radius: root.s(8)
            color: Qt.alpha(root.accent, 0.18)
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.35)
            Behavior on x { enabled: !GCal.reducedMotion; NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !GCal.reducedMotion; NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
        }

        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property var date: root.cells[index]
                readonly property bool inMonth: date.getMonth() === root.month.getMonth()
                readonly property bool isToday: GCal.sameDay(date, GCal.today)
                x: (index % 7) * grid.cw
                y: Math.floor(index / 7) * grid.ch
                width: grid.cw
                height: grid.ch

                Rectangle {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -root.s(2)
                    width: root.s(22); height: width; radius: width / 2
                    color: cell.isToday ? root.accent : (ma.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8) : "transparent")
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -root.s(2)
                    text: cell.date.getDate()
                    font.family: ThemeBackend.fontFamily
                    font.weight: cell.isToday ? Font.Black : Font.Bold
                    font.pixelSize: root.s(11)
                    color: cell.isToday ? ThemeBackend.base : (cell.inMonth ? ThemeBackend.text : ThemeBackend.surface2)
                }
                GCalDayDots {
                    visible: root.showDots
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.s(1)
                    date: cell.date
                    dimmed: !cell.inMonth
                    delay: cell.index * 6
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(cell.date)
                }
            }
        }
    }
}
