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
    // Entry: the first time it animates, every wheel spins up from zero to its digit, right to left.
    property bool spinIn: true
    property int spinDuration: 900
    property bool spun: false
    property bool spinning: false
    onAnimateChanged: if (animate && spinIn && !spun) { spun = true; spinning = true; spinEnd.restart(); }
    Timer { id: spinEnd; interval: root.spinDuration + 600; onTriggered: root.spinning = false }
    readonly property string formatted: String(Math.round(value)).replace(/\B(?=(\d{3})+(?!\d))/g, "\u202f")
    readonly property real cell: metrics.advanceWidth
    readonly property real lineHeight: metrics.height
    implicitWidth: row.width
    implicitHeight: lineHeight
    clip: true

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
                // Integer target of the wheel. Deltas pile onto it, never onto the animated `roll`: a new value arriving mid-roll would otherwise park the wheel between two digits.
                property real goal: 0
                readonly property int whole: Math.floor(roll)
                // Bounded: out-of-range values reach Qt.alpha and flood the log with setAlphaF warnings.
                readonly property real frac: Math.max(0, Math.min(1, roll - whole))
                width: isDigit ? root.cell : Math.max(sep.implicitWidth, root.cell * 0.4)
                height: root.lineHeight
                clip: isDigit

                onChChanged: {
                    if (!isDigit) return;
                    const d = Number(ch);
                    if (spinAnim.running) {
                        // Changed mid-spin: stop the spin and move on from the digit actually shown,
                        // otherwise the spin's end value overwrites the new digit and it stays stuck.
                        spinAnim.stop();
                        const shown = Math.round(roll) % 10;
                        goal = Math.round(roll) + (d - shown + 10) % 10;
                        roll = goal;
                        last = d;
                        return;
                    }
                    // A digit cannot be rolled backwards: wrapping 9 to 0 keeps rolling forward.
                    goal = last < 0 || !root.animate ? d : Math.round(goal) + (d - last + 10) % 10;
                    roll = goal;
                    last = d;
                }
                Component.onCompleted: if (isDigit) { last = Number(ch); roll = last; goal = last; }
                Behavior on roll {
                    enabled: root.animate
                    NumberAnimation { duration: root.duration; easing.type: Easing.OutExpo }
                }
                SequentialAnimation {
                    id: spinAnim
                    running: root.spinning && slot.isDigit
                    // however the spin ends, the wheel lands on a whole digit (no half-rolled fragment)
                    onStopped: { slot.roll = Math.round(slot.roll); slot.goal = slot.roll; }
                    PauseAnimation { duration: slot.index * 70 }
                    // two full turns, then settle on the digit (roll mod 10 is the digit shown)
                    NumberAnimation { target: slot; property: "roll"; from: 0; to: Number(slot.ch) + 20; duration: root.spinDuration; easing.type: Easing.OutCubic }
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
