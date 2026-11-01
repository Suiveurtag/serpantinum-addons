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
    // Same percentage the widget editor shows: width against the type's default width (360). opencode and llama.cpp appear from 120 % on.
    readonly property bool large: Math.round(width / Scaler.s(360) * 100) >= 120
    // Static model: a publish never rebuilds the cards (a rebuilt card would replay its spin).
    readonly property var cards: [
        { key: "codex", name: "Codex", tone: ThemeBackend.blue },
        { key: "claude", name: "Claude", tone: ThemeBackend.peach },
        { key: "opencode", name: "opencode", tone: ThemeBackend.green },
        { key: "llamacpp", name: "llama.cpp", tone: ThemeBackend.yellow }
    ]
    // What is on screen. Everything is copied here together, in flush(), so the total and the sources move in the same tick.
    property real shownTotal: Tokens.total
    property real shownCodex: Tokens.codex
    property real shownClaude: Tokens.claude
    property real shownOpencode: Tokens.opencode
    property real shownLlamacpp: Tokens.llamacpp
    property string noteCodex: Tokens.codexNote
    property string noteClaude: Tokens.claudeNote
    property string noteOpencode: Tokens.opencodeNote
    property string noteLlamacpp: Tokens.llamacppNote
    // Per source: true while its digits roll. Set in flush(), cleared about a second later.
    property bool rollCodex: false
    property bool rollClaude: false
    property bool rollOpencode: false
    property bool rollLlamacpp: false
    property string bump: ""
    property bool primed: false

    // Changes arriving in the same burst (same 140 ms window as the bar module) roll together; otherwise they roll at once.
    Timer {
        id: windowTimer
        interval: 140
        onTriggered: root.flush()
    }
    Timer {
        id: rollClear
        interval: 1100
        onTriggered: { root.rollCodex = false; root.rollClaude = false; root.rollOpencode = false; root.rollLlamacpp = false; }
    }

    function applyNow() {
        shownTotal = Tokens.total;
        shownCodex = Tokens.codex;
        shownClaude = Tokens.claude;
        shownOpencode = Tokens.opencode;
        shownLlamacpp = Tokens.llamacpp;
        noteCodex = Tokens.codexNote;
        noteClaude = Tokens.claudeNote;
        noteOpencode = Tokens.opencodeNote;
        noteLlamacpp = Tokens.llamacppNote;
    }

    function flush() {
        const gain = Tokens.total - shownTotal;
        const moved = Tokens.codex !== shownCodex || Tokens.claude !== shownClaude || Tokens.opencode !== shownOpencode || Tokens.llamacpp !== shownLlamacpp;
        if (!primed) return;
        if (gain > 0 && visible) {
            bump = "+" + Tokens.compact(gain);
            gainAnim.restart();
            flash.restart();
        }
        // Flags first, then the values: the digits see animate already on when they change.
        rollCodex = Tokens.codex !== shownCodex;
        rollClaude = Tokens.claude !== shownClaude;
        rollOpencode = Tokens.opencode !== shownOpencode;
        rollLlamacpp = Tokens.llamacpp !== shownLlamacpp;
        applyNow();
        if (moved || gain > 0) rollClear.restart();
    }

    Connections {
        target: Tokens
        function onDataChanged() {
            if (!Tokens.data) return;
            if (!root.primed) {
                // First load: show the numbers as they are, nothing rolls.
                root.applyNow();
                root.primed = true;
                return;
            }
            if (!windowTimer.running) windowTimer.start();
        }
    }
    Component.onCompleted: { applyNow(); primed = !!Tokens.data; }

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
                    value: root.shownTotal
                    pixelSize: parent.fit
                    color: ThemeBackend.text
                    animate: root.visible && root.primed
                }
            }

            // Codex and Claude; from 120 % also opencode and llama.cpp. Four side by side when wide enough, otherwise a 2 x 2 grid.
            GridLayout {
                visible: root.roomy
                Layout.fillWidth: true
                columns: root.width > Scaler.s(520) ? 4 : 2
                columnSpacing: Scaler.s(14)
                rowSpacing: Scaler.s(6)
                Repeater {
                    model: root.large ? root.cards : root.cards.slice(0, 2)
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
                            value: part.modelData.key === "codex" ? root.shownCodex
                                 : part.modelData.key === "claude" ? root.shownClaude
                                 : part.modelData.key === "opencode" ? root.shownOpencode : root.shownLlamacpp
                            pixelSize: Math.min(Scaler.s(14), root.width / 24)
                            weight: Font.Bold
                            color: ThemeBackend.text
                            // Only the source that received tokens rolls; the others stay still.
                            animate: root.visible && root.primed
                                 && (part.modelData.key === "codex" ? root.rollCodex
                                   : part.modelData.key === "claude" ? root.rollClaude
                                   : part.modelData.key === "opencode" ? root.rollOpencode : root.rollLlamacpp)
                            spinIn: false
                            duration: 700
                        }
                        Text {
                            Layout.fillWidth: true
                            text: part.modelData.key === "codex" ? root.noteCodex
                                : part.modelData.key === "claude" ? root.noteClaude
                                : part.modelData.key === "opencode" ? root.noteOpencode : root.noteLlamacpp
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
