import QtQuick
import "../"

// Odometer: every digit is a wheel that only rolls forward; separators stay still. Aligned on the right so
// the low digits never move when the number grows a character.
Item {
    id: root
    property real value: 0
    property real pixelSize: 24
    property color color: ThemeBackend.text
    property int weight: Font.Black
    property bool animate: false
    property int duration: 900
    readonly property string formatted: Math.round(value).toLocaleString(Qt.locale(), "f", 0)
    readonly property real cell: metrics.advanceWidth
    readonly property real lineHeight: metrics.height
    implicitWidth: row.width
    implicitHeight: lineHeight

    TextMetrics {
        id: metrics
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        text: "8"
    }

    Row {
        id: row
        layoutDirection: Qt.RightToLeft
        anchors.right: parent.right
        Repeater {
            model: root.formatted.length
            delegate: Item {
                id: slot
                required property int index
                readonly property string ch: root.formatted.charAt(root.formatted.length - 1 - index)
                readonly property bool isDigit: ch >= "0" && ch <= "9"
                property real roll: 0
                property int last: -1
                readonly property int whole: Math.floor(roll)
                // Bounded: out-of-range values reach Qt.alpha and flood the log with setAlphaF warnings.
                readonly property real frac: Math.max(0, Math.min(1, roll - whole))
                width: isDigit ? root.cell : sep.implicitWidth
                height: root.lineHeight
                clip: isDigit

                onChChanged: {
                    if (!isDigit) return;
                    const d = Number(ch);
                    // A digit cannot be rolled backwards: wrapping 9 to 0 keeps rolling forward.
                    roll = last < 0 || !root.animate ? d : roll + (d - last + 10) % 10;
                    last = d;
                }
                Component.onCompleted: if (isDigit) { last = Number(ch); roll = last; }
                Behavior on roll {
                    enabled: root.animate
                    NumberAnimation { duration: root.duration; easing.type: Easing.OutExpo }
                }

                Text {
                    visible: !slot.isDigit
                    id: sep
                    text: slot.ch
                    color: Qt.alpha(root.color, 0.55)
                    font: metrics.font
                }
                Text {
                    visible: slot.isDigit
                    y: -slot.frac * slot.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: slot.whole % 10
                    color: Qt.alpha(root.color, 1 - slot.frac)
                    font: metrics.font
                }
                Text {
                    visible: slot.isDigit && slot.frac > 0.001
                    y: (1 - slot.frac) * slot.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (slot.whole + 1) % 10
                    color: Qt.alpha(root.color, slot.frac)
                    font: metrics.font
                }
            }
        }
    }
}
