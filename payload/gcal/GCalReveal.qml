import QtQuick
import QtQuick.Layouts
import "../"

// Wraps a row so it rises and fades in, staggered by `index`, each time `generation` changes.
Item {
    id: root
    property int generation: 0
    property int index: 0
    property int baseDelay: 60
    property int step: 38
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight

    property real enter: 0
    onGenerationChanged: anim.restart()
    Component.onCompleted: anim.start()
    SequentialAnimation {
        id: anim
        ScriptAction { script: root.enter = 0 }
        PauseAnimation { duration: root.baseDelay + root.index * root.step }
        NumberAnimation { target: root; property: "enter"; to: 1; duration: 460; easing.type: Easing.OutQuint }
    }
    opacity: enter
    transform: Translate { y: Scaler.s(12) * (1 - root.enter) }
}
