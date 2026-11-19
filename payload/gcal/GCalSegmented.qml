import QtQuick
import "../"

// Segmented control: the highlight pill springs between options and stretches while it travels.
Item {
    id: root
    property var options: []          // [{ id, label, icon? }]
    property string current: ""
    property color accent: ThemeBackend.mauve
    property real fontSize: Scaler.s(11.5)
    signal selected(string id)
    function s(v) { return Scaler.s(v); }

    readonly property int at: options.findIndex(o => o.id === current)
    readonly property real cell: width / Math.max(1, options.length)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(ThemeBackend.surface0, 0.55)
    }
    Rectangle {
        id: pill
        visible: root.at >= 0
        property real target: Math.max(0, root.at) * root.cell
        property real lead: target
        property real tail: target
        Behavior on lead { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on tail { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        x: Math.min(lead, tail) + root.s(3)
        width: Math.abs(lead - tail) + root.cell - root.s(6)
        y: root.s(3)
        height: parent.height - root.s(6)
        radius: height / 2
        color: root.accent
        Behavior on color { ColorAnimation { duration: 250 } }
    }
    Row {
        anchors.fill: parent
        Repeater {
            model: root.options
            Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool active: index === root.at
                width: root.cell
                height: root.height
                Row {
                    anchors.centerIn: parent
                    spacing: root.s(6)
                    scale: ma.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    Text {
                        visible: !!opt.modelData.icon
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.icon || ""
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: root.fontSize * 1.15
                        color: opt.active ? GCal.readableOn(root.accent) : (ma.containsMouse ? ThemeBackend.text : ThemeBackend.overlay1)
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.label
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: root.fontSize
                        color: opt.active ? GCal.readableOn(root.accent) : (ma.containsMouse ? ThemeBackend.text : ThemeBackend.overlay1)
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(opt.modelData.id)
                }
            }
        }
    }
}
