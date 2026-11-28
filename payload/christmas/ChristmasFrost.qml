import QtQuick

// Hover frost: crystals grow in from one edge while `engaged` and melt back on
// leave. Self-contained: one shader, no clock, nothing loaded while idle.
Item {
    id: edge
    enabled: false                     // never takes input from the row under it
    property bool engaged: false
    property bool active: true         // gate for the owning feature's switch
    property real direction: 1         // 1 left, -1 right, 2 bottom, 0 every edge
    property real intensity: 0.45
    property real cornerRadius: 0
    property color tint: "#dcefff"
    property int growDuration: 900
    property int meltDuration: 440
    readonly property bool frosting: engaged && active
    property real growth: frosting ? 1 : 0
    Behavior on growth {
        enabled: edge.active
        NumberAnimation {
            duration: edge.frosting ? edge.growDuration : edge.meltDuration
            easing.type: edge.frosting ? Easing.OutCubic : Easing.InCubic
        }
    }
    Loader {
        enabled: false
        anchors.fill: parent
        active: edge.active && edge.visible && edge.growth > 0.001 && edge.width > 0 && edge.height > 0
        sourceComponent: ShaderEffect {
            enabled: false
            readonly property real intensity: edge.intensity * Math.min(1, edge.growth * 3)
            readonly property real energy: edge.growth
            readonly property real direction: edge.direction
            readonly property real cornerRadius: edge.cornerRadius
            readonly property size extent: Qt.size(width, height)
            readonly property color tint: edge.tint
            fragmentShader: Qt.resolvedUrl("shaders/frost.frag.qsb")
        }
    }
}
