import QtQuick
import QtQuick.Layouts
import "../reusables"
import "../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 220
    property real minHeight: 90
    property real maxWidth: 700
    property real maxHeight: 260
    property real minAspect: 1.4
    property real maxAspect: 5

    readonly property bool roomy: height > Scaler.s(120)
    property real shown: Tokens.total
    property real lastTotal: -1
    property string bump: ""
    property bool primed: false

    Connections {
        target: Tokens
        function onTotalChanged() {
            const gain = Tokens.total - root.lastTotal;
            if (root.primed && root.lastTotal > 0 && gain > 0 && root.visible) {
                root.bump = "+" + Tokens.compact(gain);
                gainAnim.restart();
                flash.restart();
            }
            root.lastTotal = Tokens.total;
        }
        function onDataChanged() { if (Tokens.data) root.primed = true; }
    }
    Component.onCompleted: { lastTotal = Tokens.total; primed = !!Tokens.data; }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        clip: true

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
        }

        // Energy sweep along the base while tokens are flowing.
        Rectangle {
            id: sweep
            visible: Tokens.active && root.visible
            y: parent.height - height
            width: parent.width * 0.35
            height: Scaler.s(2)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: ThemeBackend.primary }
                GradientStop { position: 1; color: "transparent" }
            }
            XAnimator on x {
                from: -sweep.width
                to: card.width
                duration: 1600
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
                running: sweep.visible
            }
        }

        // Soft wash that blooms from the counter when a gain arrives.
        Rectangle {
            id: wash
            anchors.fill: parent
            color: ThemeBackend.primary
            opacity: 0
            NumberAnimation on opacity {
                id: flash
                running: false
                from: 0.16; to: 0
                duration: 1400
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(16)
            spacing: Scaler.s(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    text: qsTr("LIFETIME TOKENS")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(10)
                    font.letterSpacing: Scaler.s(1.4)
                }
                Text {
                    visible: Tokens.status !== ""
                    text: "· " + Tokens.status
                    color: Tokens.stale ? ThemeBackend.red : ThemeBackend.peach
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(10)
                }
                Item { Layout.fillWidth: true }
                Text {
                    id: gain
                    text: root.bump
                    color: ThemeBackend.green
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(10)
                    opacity: 0
                    ParallelAnimation {
                        id: gainAnim
                        OpacityAnimator { target: gain; from: 1; to: 0; duration: 2200; easing.type: Easing.OutQuad }
                        ScaleAnimator { target: gain; from: 1.35; to: 1; duration: 500; easing.type: Easing.OutBack }
                    }
                }
                Item {
                    Layout.preferredWidth: Scaler.s(10)
                    Layout.preferredHeight: Scaler.s(10)
                    Rectangle {
                        id: halo
                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: ThemeBackend.green
                        opacity: 0
                        ParallelAnimation {
                            running: Tokens.active && root.visible
                            loops: Animation.Infinite
                            ScaleAnimator { target: halo; from: 0.8; to: 2.4; duration: 1300; easing.type: Easing.OutCubic }
                            OpacityAnimator { target: halo; from: 0.8; to: 0; duration: 1300; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: Scaler.s(6)
                        height: width
                        radius: width / 2
                        color: Tokens.active ? ThemeBackend.green : Qt.alpha(ThemeBackend.subtext0, 0.45)
                        Behavior on color { ColorAnimation { duration: 400 } }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The 13-character counter shrinks to the widget width instead of overflowing.
                readonly property real fit: Math.max(Scaler.s(14), Math.min(Scaler.s(44), width / 8.6, height * 0.9))
                TokensDigits {
                    id: big
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    value: Tokens.total
                    pixelSize: parent.fit
                    color: ThemeBackend.text
                    animate: root.visible && root.primed
                }
            }

            RowLayout {
                visible: root.roomy
                Layout.fillWidth: true
                spacing: Scaler.s(14)
                Repeater {
                    model: [
                        { name: "Codex", tone: ThemeBackend.blue, value: Tokens.codex, note: Tokens.codexNote },
                        { name: "Claude", tone: ThemeBackend.peach, value: Tokens.claude, note: Tokens.claudeNote }
                    ]
                    delegate: ColumnLayout {
                        id: part
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 0
                        RowLayout {
                            spacing: Scaler.s(5)
                            Rectangle { Layout.preferredWidth: Scaler.s(6); Layout.preferredHeight: Scaler.s(6); radius: width / 2; color: part.modelData.tone }
                            Text {
                                text: part.modelData.name
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: Scaler.s(10)
                            }
                        }
                        TokensDigits {
                            Layout.preferredWidth: implicitWidth
                            value: part.modelData.value
                            pixelSize: Math.min(Scaler.s(14), root.width / 24)
                            weight: Font.Bold
                            color: ThemeBackend.text
                            animate: root.visible && root.primed
                            duration: 700
                        }
                        Text {
                            Layout.fillWidth: true
                            text: part.modelData.note
                            elide: Text.ElideRight
                            color: Qt.alpha(ThemeBackend.subtext0, 0.8)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(9)
                        }
                    }
                }
            }
        }
    }
}
