import QtQuick
import "../"

// Segmented control with a sliding selection highlight.
Item {
    id: root
    property var options: []          // [{ id, label, icon? }]
    property string current: ""
    property bool compactIcons: false
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
        x: Math.max(0, root.at) * root.cell + root.s(3)
        width: Math.max(0, root.cell - root.s(6))
        Behavior on x { enabled: !GCal.reducedMotion; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        y: root.s(3)
        height: parent.height - root.s(6)
        radius: height / 2
        color: root.accent
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
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checkable: true
                Accessible.checked: active
                Accessible.onPressAction: root.selected(modelData.id)
                Keys.onSpacePressed: root.selected(modelData.id)
                Keys.onReturnPressed: root.selected(modelData.id)
                width: root.cell
                height: root.height
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.s(2)
                    radius: height / 2
                    color: "transparent"
                    border.color: ThemeBackend.text
                    visible: opt.activeFocus
                }
                Row {
                    anchors.centerIn: parent
                    spacing: root.s(6)
                    scale: ma.pressed && !GCal.reducedMotion ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: ma.pressed ? 70 : 135; easing.type: Easing.OutCubic } }
                    Text {
                        visible: !!opt.modelData.icon
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.icon || ""
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: root.fontSize * 1.15
                        color: GCal.readableOn(pill.visible && opt.x + opt.width / 2 >= pill.x && opt.x + opt.width / 2 < pill.x + pill.width ? root.accent : ThemeBackend.surface0)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.compactIcons || !opt.modelData.icon
                        text: opt.modelData.label
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Black
                        font.pixelSize: root.fontSize
                        color: GCal.readableOn(pill.visible && opt.x + opt.width / 2 >= pill.x && opt.x + opt.width / 2 < pill.x + pill.width ? root.accent : ThemeBackend.surface0)
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
