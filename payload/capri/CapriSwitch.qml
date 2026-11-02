import QtQuick
import "../"
import "../reusables"

// Ignition plate: a chamfered print plate with a violet hard copy that it slams into when pressed.
Item {
    id: control
    property real uiScale: 1
    property bool motionAllowed: !Config.getSetting("general.performance", false) && Capri.motion !== "reduced"
    property string accessibleName: "Capri"
    property string offText: accessibleName
    property string onText: "ON"
    property string fontFamily: ThemeBackend.fontFamily
    readonly property bool checked: Capri.enabled
    property real ignition: checked ? 1 : 0
    property int blink: 0
    readonly property real lift: mouse.pressed ? u(6) : mouse.containsMouse ? -u(2) : 0
    function u(v) { return Scaler.s(v) * uiScale; }
    function toggle() { Config.setSetting("addonsV2Capri", !checked); }
    function mix(a, b, t) { return Qt.tint(a, Qt.alpha(b, t)); }
    implicitWidth: Math.max(u(250), label.implicitWidth + u(110))
    implicitHeight: u(64)
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: toggle()
    Keys.onSpacePressed: toggle()
    Keys.onReturnPressed: toggle()
    Behavior on ignition { enabled: control.motionAllowed; NumberAnimation { duration: control.checked ? 300 : 240; easing.type: Easing.InOutCubic } }
    Timer { interval: 250; repeat: true; running: control.checked && control.motionAllowed && control.visible; onTriggered: control.blink++ }

    CapriPlate {
        x: control.u(6); y: control.u(6); width: control.width - control.u(6); height: control.height - control.u(6)
        fillColor: control.mix("#20182f", "#7d3af5", control.ignition)
    }
    Item {
        x: control.lift; y: control.lift
        width: control.width - control.u(6); height: control.height - control.u(6)
        // focus ring
        CapriPlate { x: -control.u(3); y: -control.u(3); width: parent.width + control.u(6); height: parent.height + control.u(6); fillColor: "#fcf2f6"; visible: control.activeFocus }
        CapriPlate {
            anchors.fill: parent
            fillColor: control.mix(mouse.containsMouse ? "#2a203b" : "#20182f", "#ff245d", control.ignition)
        }
        // top bar
        Rectangle { x: control.u(16); width: parent.width - control.u(48); height: control.u(3); color: control.checked ? "#36ff73" : "#9c8ca0" }
        // charge gauge: three slanted cells fill with the ignition
        Row {
            x: control.u(18); anchors.verticalCenter: parent.verticalCenter
            spacing: control.u(4)
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: control.u(7); height: control.u(22)
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.3, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                    color: control.ignition > index / 3 + 0.1 ? "#36ff73" : "#120c1c"
                    border.width: 1; border.color: control.checked ? "#120c1c" : "#9c8ca0"
                }
            }
        }
        Text {
            id: label
            x: control.u(66); anchors.verticalCenter: parent.verticalCenter
            text: (control.checked ? control.onText : control.offText).toUpperCase()
            font.family: control.fontFamily; font.pixelSize: control.u(18); font.bold: true; font.letterSpacing: control.u(2)
            color: control.checked ? "#fcf2f6" : "#d6c5d0"
        }
        // block cursor, blinking while she is awake
        Rectangle {
            anchors.left: label.right; anchors.leftMargin: control.u(6); anchors.verticalCenter: label.verticalCenter
            width: control.u(10); height: control.u(18)
            color: control.checked ? "#120c1c" : "#7d3af5"
            visible: !control.checked || control.blink % 2 === 0
        }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { control.forceActiveFocus(); control.toggle(); } }
}
