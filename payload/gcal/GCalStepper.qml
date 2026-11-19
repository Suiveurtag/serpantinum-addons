import QtQuick
import "../"

// Number field with − / + buttons; the mouse wheel steps it too.
Item {
    id: root
    property int value: 1
    property int from: 1
    property int to: 99
    property color accent: ThemeBackend.mauve
    signal moved(int value)
    function s(v) { return Scaler.s(v); }
    function step(n) {
        const v = Math.max(root.from, Math.min(root.to, root.value + n));
        if (v === root.value) return;
        rolling.direction = n > 0 ? 1 : -1;
        root.moved(v);
    }

    implicitWidth: root.s(104)
    implicitHeight: root.s(34)

    Rectangle {
        anchors.fill: parent
        radius: root.s(10)
        color: Qt.alpha(ThemeBackend.surface0, 0.45)
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.surface1, 0.8)
    }
    Repeater {
        model: [-1, 1]
        Item {
            id: btn
            required property int modelData
            readonly property bool enabledStep: modelData < 0 ? root.value > root.from : root.value < root.to
            x: modelData < 0 ? 0 : parent.width - width
            width: root.s(32); height: parent.height
            Text {
                anchors.centerIn: parent
                text: btn.modelData < 0 ? "−" : "+"
                font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(16)
                color: !btn.enabledStep ? ThemeBackend.surface2 : (ma.containsMouse ? root.accent : ThemeBackend.text)
                scale: ma.pressed ? 0.8 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: btn.enabledStep ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.step(btn.modelData)
            }
        }
    }
    GCalRollText {
        id: rolling
        anchors.centerIn: parent
        width: parent.width - root.s(64)
        text: String(root.value)
        pixelSize: root.s(13)
        weight: Font.Black
        color: ThemeBackend.text
        horizontalAlignment: Text.AlignHCenter
        duration: 260
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (w) => root.step(w.angleDelta.y > 0 ? 1 : -1)
    }
}
