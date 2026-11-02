import QtQuick
import "../"
import "./"

Rectangle {
    id: root
    property color surfaceColor: ThemeBackend.surface0
    property color glassTint: surfaceColor
    property real glassPress: 0
    property real glassPulse: 0
    property Item glassSource: null
    readonly property bool glassActive: glass.active
    readonly property bool blurActive: root.visible && ThemeBackend.glassActive && !ThemeBackend.liquidGlass
    property real glint: hover.hovered ? 1 : 0
    color: glass.active ? "transparent" : (blurActive ? Qt.alpha(surfaceColor, surfaceColor.a * ThemeBackend.elementOpacity) : surfaceColor)
    Behavior on glint { SmoothedAnimation { velocity: 4 } }

    GlassFill {
        id: glass
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        tintColor: root.glassTint
        backdropOverride: root.glassSource
        frost: 1.8 - root.glint * 0.8
        rim: 0.45 + root.glint * 0.2
        press: root.glassPress
        pulse: root.glassPulse + root.glint * 0.12
    }
    Rectangle {
        anchors.fill: parent
        visible: root.blurActive
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.text, 0.06 + root.glint * 0.12 + root.glassPulse * 0.12)
        Accessible.ignored: true
    }
    HoverHandler { id: hover; enabled: root.visible && ThemeBackend.glassActive }
}
