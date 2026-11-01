import QtQuick
import QtQuick.Effects
import "../"
import "../reusables"

// Moon-phase switch: a flat track, a new moon when OFF that waxes to a full ember moon when the night is in.
// The crescent is the track's own colour sliding over the moon, so no tint or glow is needed.
Item {
    id: control
    property real uiScale: 1
    function u(value) { return Scaler.s(value) * uiScale; }
    implicitWidth: u(96)
    implicitHeight: u(44)
    readonly property bool checked: Halloween.activeSeason
    property real ignition: checked ? 1 : 0
    Behavior on ignition { enabled: Halloween.animationEnabled; NumberAnimation { duration: control.checked ? 700 : 360; easing.type: Easing.InOutSine } }
    Accessible.role: Accessible.CheckBox
    Accessible.name: "Halloween mode"
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: control.toggle()
    activeFocusOnTab: true
    function toggle() { Config.setSetting("addonsV2Halloween", !checked); }
    Keys.onSpacePressed: toggle()
    Keys.onReturnPressed: toggle()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Halloween.colors.crust
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Halloween.colors.text
            : Qt.alpha(Halloween.candle, (mouse.containsMouse ? 0.5 : 0.25) + control.ignition * 0.2)
    }
    Item {
        id: moon
        width: control.height - control.u(10); height: width
        anchors.verticalCenter: parent.verticalCenter
        x: control.u(5) + control.ignition * (control.width - width - control.u(10))
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: moonMask }
        Rectangle { id: moonMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        Rectangle { anchors.fill: parent; color: Qt.tint(Halloween.colors.overlay1, Qt.alpha(Halloween.ember, control.ignition * 0.6)) }
        // the track's shadow slides off as the moon waxes
        Rectangle {
            width: parent.width; height: width; radius: width / 2
            x: control.ignition * width * 1.05
            color: Halloween.colors.crust
        }
    }
    // hairline outline so the new moon stays visible against the track
    Rectangle {
        x: moon.x; y: moon.y; width: moon.width; height: moon.height; radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Halloween.colors.overlay1, 0.5 * (1 - control.ignition))
    }
    MouseArea {
        id: mouse
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { control.forceActiveFocus(); control.toggle(); }
    }
}
