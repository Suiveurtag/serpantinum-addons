import QtQuick
import "../"

// Segmented control with a sliding selection highlight.
Item {
    id: root
    property var options: []          // [{ id, label, icon? }]
    property string current: ""
    property bool compactIcons: false
    property bool viewIcons: false
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
                        visible: !!opt.modelData.icon && !root.viewIcons
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.icon || ""
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: root.fontSize * 1.15
                        color: GCal.readableOn(pill.visible && opt.x + opt.width / 2 >= pill.x && opt.x + opt.width / 2 < pill.x + pill.width ? root.accent : ThemeBackend.surface0)
                    }
                    Canvas {
                        id: viewIcon
                        visible: root.viewIcons
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.s(16); height: root.s(16)
                        property color ink: GCal.readableOn(pill.visible && opt.x + opt.width / 2 >= pill.x && opt.x + opt.width / 2 < pill.x + pill.width ? root.accent : ThemeBackend.surface0)
                        onInkChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.scale(width / 16, height / 16);
                            ctx.strokeStyle = ink;
                            ctx.fillStyle = ink;
                            ctx.lineWidth = 1.4;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            if (opt.modelData.id === "list") {
                                for (let y = 4; y <= 12; y += 4) {
                                    ctx.beginPath(); ctx.arc(2.5, y, 0.85, 0, Math.PI * 2); ctx.fill();
                                    ctx.beginPath(); ctx.moveTo(5.5, y); ctx.lineTo(14, y); ctx.stroke();
                                }
                            } else if (opt.modelData.id === "month") {
                                ctx.beginPath(); ctx.roundedRect(1.5, 2, 13, 12, 2, 2); ctx.stroke();
                                ctx.beginPath(); ctx.moveTo(2, 5.5); ctx.lineTo(14, 5.5); ctx.stroke();
                                for (let x = 4.5; x <= 11.5; x += 3.5)
                                    for (let y = 8; y <= 11.5; y += 3.5)
                                        ctx.fillRect(x - 0.75, y - 0.75, 1.5, 1.5);
                            } else if (opt.modelData.id === "week") {
                                for (let x = 2; x <= 12; x += 5) {
                                    ctx.beginPath(); ctx.roundedRect(x, 3, 3, 10, 1, 1); ctx.stroke();
                                }
                            } else {
                                ctx.beginPath(); ctx.roundedRect(3, 1.5, 10, 13, 2, 2); ctx.stroke();
                                ctx.beginPath(); ctx.moveTo(6, 6); ctx.lineTo(8, 4.5); ctx.lineTo(8, 11.5); ctx.stroke();
                                ctx.beginPath(); ctx.moveTo(6, 11.5); ctx.lineTo(10, 11.5); ctx.stroke();
                            }
                        }
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
