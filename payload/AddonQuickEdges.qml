import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../../"
import "../../reusables"
import "../../reusables/guide"

ColumnLayout {
    id: editor
    required property var rootObj
    property bool expanded: false
    readonly property bool reducedMotion: !!Config.getSetting("general", {}).performance
    property real reveal: expanded ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: editor.reducedMotion ? 110 : (editor.expanded ? 280 : 240); easing.type: Easing.OutCubic }
    }
    Layout.fillWidth: true
    spacing: 0

    function allowed(screen, edge) {
        const screens = Config.getSetting("addonsV2QuickEdgesByScreen", {});
        const values = screens[screen];
        return values && values[edge] !== undefined ? values[edge] !== false
            : Config.getSetting("addonsV2QuickEdge_" + edge, true) !== false;
    }
    function toggle(screen, edge) {
        const screens = Config.getSetting("addonsV2QuickEdgesByScreen", {});
        const values = screens[screen] || {};
        values[edge] = !allowed(screen, edge);
        screens[screen] = values;
        Config.setSetting("addonsV2QuickEdgesByScreen", screens);
    }

    SettingsRow {
        rootObj: editor.rootObj
        settingId: "general_quickactions_edges"
        searchKeywords: "quick actions edges screens monitor bords écran moniteur"
        icon: "󰍹"
        title: qsTr("Quick Actions edges")
        description: qsTr("Choose the active edges for each screen")
        clickable: true
        onClicked: editor.expanded = !editor.expanded
        titleBadge: Component {
            Rectangle {
                implicitWidth: addonBadgeText.implicitWidth + rootObj.s(12)
                implicitHeight: rootObj.s(18)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.mauve, 0.15)
                border.color: Qt.alpha(ThemeBackend.mauve, 0.4)
                border.width: 1
                id: addonBadge
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: addonBadgeMask }

                Rectangle {
                    id: addonBadgeMask
                    anchors.fill: parent
                    radius: addonBadge.radius
                    color: "black"
                    visible: false
                    layer.enabled: true
                }

                Text {
                    id: addonBadgeText
                    anchors.centerIn: parent
                    text: "Addon"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(10)
                    font.bold: true
                    color: ThemeBackend.mauve
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: badgeShimmerAnimation.restart()
                }

                Rectangle {
                    id: badgeShimmer
                    x: -width
                    y: -height / 4
                    width: parent.width * 0.45
                    height: parent.height * 1.5
                    rotation: 18
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.alpha(ThemeBackend.text, 0.45) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    NumberAnimation on x {
                        id: badgeShimmerAnimation
                        from: -badgeShimmer.width
                        to: badgeShimmer.parent.width + badgeShimmer.width
                        duration: 450
                        running: false
                    }
                }
            }
        }
        Text {
            text: "󰅀"
            font.family: ThemeBackend.iconFont
            font.pixelSize: editor.rootObj.s(14)
            color: editor.expanded ? ThemeBackend.text : ThemeBackend.overlay2
            rotation: editor.expanded ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }
    Item {
        Layout.fillWidth: true
        implicitHeight: (edgeContent.implicitHeight + editor.rootObj.s(16)) * editor.reveal
        visible: editor.reveal > 0.001
        clip: true
        ColumnLayout {
        id: edgeContent
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.leftMargin: editor.rootObj.s(20); anchors.rightMargin: editor.rootObj.s(20)
        opacity: Math.min(1, editor.reveal * 1.8)
        enabled: editor.expanded
        transform: Translate { y: editor.reducedMotion ? 0 : -editor.rootObj.s(8) * (1 - editor.reveal) }
        spacing: editor.rootObj.s(12)
        Text {
            Layout.fillWidth: true
            text: qsTr("Select the edges on each screen. The bar's edge remains unavailable.")
            wrapMode: Text.WordWrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: editor.rootObj.s(12)
            color: ThemeBackend.subtext0
        }
        Repeater {
            model: Quickshell.screens
            delegate: Rectangle {
                id: card
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + editor.rootObj.s(24)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface1, 0.45)
                border.color: ThemeBackend.surface2
                ColumnLayout {
                    id: content
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: editor.rootObj.s(12)
                    spacing: editor.rootObj.s(8)
                    Text {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.bold: true
                        font.pixelSize: editor.rootObj.s(13)
                        elide: Text.ElideRight
                    }
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(editor.rootObj.s(260), content.width)
                        Layout.preferredHeight: editor.rootObj.s(140)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: editor.rootObj.s(18)
                            color: ThemeBackend.base
                            radius: editor.rootObj.s(7)
                            border.color: ThemeBackend.surface2
                            Text {
                                anchors.centerIn: parent
                                text: card.modelData.width + " × " + card.modelData.height
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: editor.rootObj.s(11)
                            }
                        }
                        Repeater {
                            model: [
                                { edge: "top", label: qsTr("Top") },
                                { edge: "bottom", label: qsTr("Bottom") },
                                { edge: "left", label: qsTr("Left") },
                                { edge: "right", label: qsTr("Right") }
                            ]
                            delegate: Rectangle {
                                id: edgeButton
                                required property var modelData
                                readonly property bool horizontal: modelData.edge === "top" || modelData.edge === "bottom"
                                readonly property bool selected: { Config.rawSettings; return editor.allowed(card.modelData.name, modelData.edge); }
                                x: modelData.edge === "right" ? parent.width - width : (horizontal ? editor.rootObj.s(29) : 0)
                                y: modelData.edge === "bottom" ? parent.height - height : (horizontal ? 0 : editor.rootObj.s(29))
                                width: horizontal ? parent.width - editor.rootObj.s(58) : editor.rootObj.s(32)
                                height: horizontal ? editor.rootObj.s(32) : parent.height - editor.rootObj.s(58)
                                radius: editor.rootObj.s(8)
                                color: selected ? Qt.alpha(ThemeBackend.mauve, edgeMouse.containsMouse ? 0.42 : 0.28) : (edgeMouse.containsMouse ? ThemeBackend.surface2 : ThemeBackend.surface1)
                                scale: !editor.reducedMotion && edgeMouse.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                border.width: activeFocus ? 2 : 1
                                border.color: selected || activeFocus ? ThemeBackend.mauve : ThemeBackend.overlay0
                                activeFocusOnTab: true
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: card.modelData.name + " · " + modelData.label
                                Accessible.checked: selected
                                Keys.onSpacePressed: editor.toggle(card.modelData.name, modelData.edge)
                                Keys.onReturnPressed: editor.toggle(card.modelData.name, modelData.edge)
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: edgeButton.horizontal ? parent.width - editor.rootObj.s(18) : editor.rootObj.s(4)
                                    height: edgeButton.horizontal ? editor.rootObj.s(4) : parent.height - editor.rootObj.s(18)
                                    radius: editor.rootObj.s(2)
                                    color: edgeButton.selected ? ThemeBackend.mauve : ThemeBackend.overlay0
                                    scale: editor.reducedMotion || edgeButton.selected ? 1 : 0.72
                                    opacity: edgeButton.selected ? 1 : 0.65
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: edgeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { edgeButton.forceActiveFocus(); editor.toggle(card.modelData.name, edgeButton.modelData.edge); }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Highlighted edges are enabled · Click an edge to change it")
                        color: ThemeBackend.subtext0
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: editor.rootObj.s(11)
                        wrapMode: Text.WordWrap
                        Layout.maximumWidth: content.width
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
        Text {
            visible: Quickshell.screens.length === 0
            text: qsTr("No screens detected")
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
        }
        }
    }
}
