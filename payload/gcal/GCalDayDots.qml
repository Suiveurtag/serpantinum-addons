import QtQuick
import "../"

// Up to three event-colour dots under a day number. Each dot pops in with a staggered overshoot.
Row {
    id: root
    property var date: null
    property bool onAccent: false
    property bool dimmed: false
    property int delay: 0
    readonly property var colors: date ? GCal.dayColors(date) : []
    spacing: Scaler.s(2)

    Repeater {
        model: root.colors
        Rectangle {
            id: dot
            required property string modelData
            required property int index
            width: Scaler.s(4); height: width; radius: width / 2
            color: root.onAccent ? ThemeBackend.base : modelData
            opacity: root.dimmed ? 0.4 : 0.95
            scale: 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            SequentialAnimation {
                running: true
                PauseAnimation { duration: root.delay + dot.index * 55 }
                NumberAnimation { target: dot; property: "scale"; from: 0; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
            }
        }
    }
}
