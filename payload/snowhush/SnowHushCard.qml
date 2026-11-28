import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../"

Item {
    id: card

    required property var rootObj
    readonly property bool active: SnowHush.enabled
    readonly property bool compact: width < s(695)
    readonly property bool motion: !Config.getSetting("general", {}).performance
    readonly property color ink: "#10292c"
    readonly property color paper: "#f2ebd6"
    readonly property color softText: "#b3cfcb"
    property real reveal: active ? 1 : 0
    property real shimmer: 0
    property bool initialized: false
    property real expandedHeight: 0
    readonly property var groups: SnowHush.menuItems.filter(item => item.hasChildren)

    function s(value: real): real { return card.rootObj.s(value); }

    Layout.fillWidth: true
    implicitHeight: hero.height + detail.height

    Component.onCompleted: initialized = true
    onActiveChanged: {
        if (active && initialized && visible && motion) frostSweep.restart();
        else frostSweep.stop();
    }
    Behavior on reveal {
        enabled: card.initialized && card.visible && card.motion
        NumberAnimation { duration: card.active ? 420 : 300; easing.type: Easing.OutCubic }
    }

    NumberAnimation {
        id: frostSweep
        target: card
        property: "shimmer"
        from: 0
        to: 1
        duration: 850
        easing.type: Easing.OutCubic
    }

    Rectangle {
        anchors.fill: parent
        radius: card.s(19)
        color: Qt.tint("#232526", Qt.alpha(card.ink, card.reveal))
        border.color: Qt.tint("#474949", Qt.alpha("#426e6b", card.reveal))
    }

    Item {
        id: hero
        width: parent.width
        height: card.s(card.compact ? 158 : 184)
        clip: true
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: heroMask
            saturation: card.reveal - 1
        }

        Rectangle { anchors.fill: parent; color: "#17363a" }

        Image {
            anchors.right: parent.right
            width: parent.width * (card.compact ? 0.56 : 0.64)
            height: parent.height
            source: "winter.jpg"
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignVCenter
            asynchronous: true
            mipmap: true
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#153337" }
                GradientStop { position: 0.36; color: "#153337" }
                GradientStop { position: 0.66; color: "#20153337" }
                GradientStop { position: 1; color: "#00153337" }
            }
        }

        Rectangle {
            width: hero.width * 0.28
            height: hero.height * 1.35
            x: -width + (hero.width + 2 * width) * card.shimmer
            y: -height * 0.15
            rotation: 15
            opacity: frostSweep.running ? Math.sin(Math.PI * card.shimmer) * 0.42 : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#00f8ffef" }
                GradientStop { position: 0.52; color: "#acf8ffef" }
                GradientStop { position: 1; color: "#00f8ffef" }
            }
        }

        Repeater {
            model: frostSweep.running ? 21 : 0
            Rectangle {
                required property int index
                readonly property real progress: card.shimmer
                x: hero.width * (0.28 + ((index * 37) % 61) / 100) + progress * card.s(index % 2 ? 33 : -38)
                y: hero.height * (0.11 + ((index * 23) % 72) / 100) - progress * card.s(34 + index % 5 * 7)
                width: card.s(2 + index % 3)
                height: width
                radius: width / 2
                color: "#ffffea"
                opacity: Math.sin(Math.PI * progress) * (0.25 + (index % 4) * 0.13)
            }
        }

        Rectangle {
            id: heroMask
            anchors.fill: parent
            radius: card.s(19)
            visible: false
            layer.enabled: true
        }
    }

    Column {
        anchors.left: hero.left
        anchors.leftMargin: card.s(card.compact ? 19 : 27)
        anchors.right: power.left
        anchors.rightMargin: card.s(12)
        anchors.verticalCenter: hero.verticalCenter
        spacing: card.s(8)

        Text {
            width: parent.width
            text: "Snow Hush"
            color: card.paper
            font.family: "Noto Serif"
            font.pixelSize: card.s(card.compact ? 33 : 47)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: SnowHush.error || SnowHush.modeError || (!SnowHush.available ? qsTr("Available in a Wayland session")
                : SnowHush.starting ? qsTr("Starting Snow Hush…") : card.active ? qsTr("Seasonal effects for your desktop") : qsTr("Effects paused"))
            color: SnowHush.error || SnowHush.modeError ? "#ffcabd" : card.active ? card.softText : "#dddddd"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: card.s(13)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Choice {
            visible: Boolean(SnowHush.error)
            text: qsTr("Retry")
            onClicked: SnowHush.setEnabled(true)
        }
    }

    Switch {
        id: power
        anchors.right: hero.right
        anchors.rightMargin: card.s(20)
        anchors.top: hero.top
        anchors.topMargin: card.s(20)
        checked: card.active
        enabled: SnowHush.available
        Accessible.name: qsTr("Snow Hush effects")
        padding: card.s(8)
        onToggled: {
            SnowHush.setEnabled(checked);
            checked = Qt.binding(() => card.active);
        }
        indicator: Rectangle {
            implicitWidth: card.s(47)
            implicitHeight: card.s(25)
            x: power.leftPadding
            y: (power.height - height) / 2
            radius: height / 2
            color: power.checked ? "#e8ecd4" : "#383b3b"
            border.color: power.visualFocus ? "white" : power.checked ? "#f8ffdc" : "#c6cbca"
            Rectangle {
                width: card.s(17)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: power.checked ? parent.width - width - card.s(4) : card.s(4)
                color: power.checked ? "#285c59" : "#e1e4de"
                Behavior on x {
                    enabled: card.motion
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    Item {
        id: detail
        anchors.top: hero.bottom
        width: parent.width
        height: card.active ? card.expandedHeight : 0
        Behavior on height {
            enabled: card.initialized && card.visible && card.motion
            NumberAnimation { duration: card.active ? 360 : 300; easing.type: Easing.OutCubic }
        }
        clip: true
        opacity: Math.min(1, card.reveal * 1.5)
        enabled: card.active && card.reveal > 0.5

        Loader {
            id: settings
            width: parent.width
            active: card.active || card.reveal > 0
            sourceComponent: ColumnLayout {
                width: settings.width
                spacing: card.s(12)
                onImplicitHeightChanged: if (card.active) card.expandedHeight = implicitHeight
                Component.onCompleted: if (card.active) card.expandedHeight = implicitHeight

                GridLayout {
                    Layout.fillWidth: true
                    Layout.margins: card.s(17)
                    visible: Boolean(SnowHush.menu)
                    columns: card.compact ? 1 : 2
                    columnSpacing: card.s(14)
                    rowSpacing: card.s(14)
                    uniformCellWidths: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: card.s(12)
                        Section { entry: SnowHush.menuItems[3] || null }
                        Section { entry: SnowHush.menuItems[0] || null }
                        Section { entry: SnowHush.menuItems[1] || null }
                        Section { entry: card.groups.length > 5 ? card.groups[4] : null }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: card.s(12)
                        Section { entry: SnowHush.menuItems[2] || null }
                        Section {
                            entry: card.groups[card.groups.length - 1] || null
                            shellStartup: true
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.s(17)
                    Layout.rightMargin: card.s(17)
                    Layout.bottomMargin: card.s(16)
                    visible: Boolean(SnowHush.menu)
                    spacing: card.s(7)

                    Repeater {
                        model: SnowHush.menuItems.filter(item => !item.hasChildren && !item.isSeparator).slice(0, -1)
                        Option {}
                    }
                }
            }
        }
    }

    component Section: ColumnLayout {
        id: section
        required property var entry
        property bool shellStartup: false
    
        Layout.fillWidth: true
        visible: Boolean(entry)
        spacing: card.s(7)

        QsMenuOpener { id: submenu; menu: section.entry || null }

        Label {
            text: String(section.entry && section.entry.text || "").replace(/&/g, "")
            color: card.paper
            font.family: ThemeBackend.fontFamily
            font.pixelSize: card.s(14)
            font.weight: Font.DemiBold
        }

        Flow {
            Layout.fillWidth: true
            spacing: card.s(6)
            Repeater {
                model: {
                    const choices = (submenu.children.values || []).filter(item => !item.isSeparator && item.text);
                    return section.shellStartup ? choices.slice(0, -1) : choices;
                }
                Option {
                    width: !checkable && !enabled ? parent.width : Math.min(parent.width, implicitWidth)
                }
            }

            Choice {
                visible: section.shellStartup && Boolean(section.entry)
                text: qsTr("Start with Serpantinum")
                checkable: true
                highlighted: SnowHush.startWithShell
                checked: highlighted
                onClicked: {
                    SnowHush.setStartWithShell(checked);
                    checked = Qt.binding(() => SnowHush.startWithShell);
                }
            }
        }
    }

    component Option: Choice {
        id: option
        required property var modelData
        readonly property var actionEntry: option.modelData
        text: String(actionEntry && actionEntry.text || "").replace(/&/g, "")
        enabled: Boolean(actionEntry && (actionEntry.enabled || actionEntry === SnowHush.newYear))
        highlighted: Boolean(actionEntry && actionEntry.checkState === Qt.Checked)
        checkable: Boolean(actionEntry && actionEntry.buttonType !== QsMenuButtonType.None)
        checked: highlighted
        onClicked: {
            if (actionEntry && actionEntry.enabled)
                actionEntry.triggered();
            else if (actionEntry && actionEntry === SnowHush.newYear)
                SnowHush.selectMode("new-year");
            checked = Qt.binding(() => option.highlighted);
        }
    }

    component Choice: Button {
        id: button
        horizontalPadding: card.s(11)
        verticalPadding: card.s(8)
        font.family: ThemeBackend.fontFamily
        font.pixelSize: card.s(12)
        contentItem: Text {
            text: button.checkable ? (button.highlighted ? "✓  " : "○  ") + button.text : button.text
            color: !button.enabled ? card.softText : button.highlighted ? "#173234" : card.paper
            font: button.font
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
        background: Rectangle {
            radius: card.s(7)
            color: !button.enabled ? "transparent" : button.highlighted ? "#d6e6cb" : button.hovered ? "#315d5d" : "#203e40"
            border.color: button.visualFocus ? "#f7f4dd" : !button.enabled ? "transparent" : button.highlighted ? "#d6e6cb" : "#42615f"
        }
    }
}
