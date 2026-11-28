import QtQuick
import QtQml.Models
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../"

// A winter postcard in riso print: the artwork as a perforated stamp with its postmark, a snow globe that switches the
// weather on, and the engine's tray menu laid out as weather tiles, gauges and toggles once it is running.
Item {
    id: card

    required property var rootObj
    readonly property bool active: SnowHush.enabled
    readonly property bool compact: width < s(695)
    readonly property bool motion: !(Config.getSetting("general", {}) || {}).performance
    readonly property bool onScreen: visible && width > 0 && Window.window !== null && Window.window.visible
    readonly property bool snowing: active && motion && onScreen
    readonly property bool ready: active && Boolean(SnowHush.menu) && SnowHush.modeItems.length > 0
    readonly property bool working: active && (SnowHush.building || SnowHush.starting)
    readonly property bool troubled: Boolean(SnowHush.error || SnowHush.modeError)
    // The card takes the colours of what falls: Halloween and New Year (Christmas) first, as they ride on snow.
    // Decided after the fact, not bound: reading a menu entry's state can make it refresh mid-binding.
    property string theme: "snow"
    function updateTheme(): void {
        const on = i => Boolean(SnowHush.modeItems[i] && SnowHush.modeItems[i].checkState === Qt.Checked);
        card.theme = !card.ready ? "snow" : on(7) ? "halloween" : on(8) ? "christmas" : on(2) ? "snow"
            : on(5) ? "blossom" : on(3) ? "autumn" : on(4) ? "rain" : "snow";
        const pal = card.palettes[card.theme];
        card.ink = pal.ink; card.ink2 = pal.ink2; card.heroTop = pal.top; card.teal = pal.accent; card.deep = pal.deep;
        card.frost = pal.frost; card.paper = pal.paper; card.softText = pal.soft; card.faint = pal.faint;
        card.line = pal.line; card.tint = pal.tint;
    }
    Instantiator {
        model: SnowHush.modeItems
        delegate: Connections {
            required property var modelData
            target: modelData
            function onCheckStateChanged() { Qt.callLater(card.updateTheme); }
        }
    }
    Connections {
        target: SnowHush
        function onModeItemsChanged() { Qt.callLater(card.updateTheme); }
    }
    readonly property var palettes: Object.freeze({
        snow:      { ink: "#10292c", ink2: "#183a3e", top: "#163a3e", accent: "#3d9aa0", deep: card.deep, frost: "#cfe9e4", paper: "#f2ebd6", soft: "#a9c7c3", faint: "#6f8f8c", line: card.line, tint: 0 },
        autumn:    { ink: "#2a170d", ink2: "#3a2314", top: "#40220f", accent: "#d9822b", deep: "#a8541c", frost: "#f5cf98", paper: "#f7ead6", soft: "#d6b692", faint: "#97735a", line: "#5a3a22", tint: 0.62 },
        rain:      { ink: "#111a27", ink2: "#1b2738", top: "#1b2a40", accent: "#6f95c9", deep: "#4a6fa3", frost: "#cddbee", paper: "#eef1f6", soft: "#a7b6cb", faint: "#6c7b91", line: "#33455e", tint: 0.55 },
        blossom:   { ink: "#29141f", ink2: "#3a1e2c", top: "#3e1c2d", accent: "#e58aae", deep: "#c45d86", frost: "#f9d3e2", paper: "#fbeff2", soft: "#d8adbf", faint: "#9a7083", line: "#5c3448", tint: 0.6 },
        christmas: { ink: "#0e2318", ink2: "#173323", top: "#123222", accent: "#d04a40", deep: "#a3332d", frost: "#f2d48c", paper: "#f6efdf", soft: "#b6cab4", faint: "#718e78", line: "#2d4f38", tint: 0.5 },
        halloween: { ink: "#180f24", ink2: "#251835", top: "#2a1739", accent: "#ff8a2b", deep: "#8f4bd6", frost: "#ffc78c", paper: "#f2e8dc", soft: "#b9a7cd", faint: "#7b6990", line: "#3f2a57", tint: 0.6 }
    })
    property color ink: "#10292c"
    property color ink2: "#183a3e"
    property color heroTop: "#163a3e"
    property color teal: "#3d9aa0"
    property color deep: "#2c7d83"
    property color frost: "#cfe9e4"
    property color paper: "#f2ebd6"
    property color softText: "#a9c7c3"
    property color faint: "#6f8f8c"
    property color line: "#2d5558"
    property real tint: 0
    readonly property color hover: Qt.lighter(ink2, 1.3)
    readonly property color well: Qt.darker(ink, 1.35)
    readonly property color ember: "#ffbfa8"
    Behavior on ink { ColorAnimation { duration: 600 } }
    Behavior on ink2 { ColorAnimation { duration: 600 } }
    Behavior on heroTop { ColorAnimation { duration: 600 } }
    Behavior on teal { ColorAnimation { duration: 600 } }
    Behavior on deep { ColorAnimation { duration: 600 } }
    Behavior on frost { ColorAnimation { duration: 600 } }
    Behavior on paper { ColorAnimation { duration: 600 } }
    Behavior on softText { ColorAnimation { duration: 600 } }
    Behavior on faint { ColorAnimation { duration: 600 } }
    Behavior on line { ColorAnimation { duration: 600 } }
    Behavior on tint { NumberAnimation { duration: 600 } }
    readonly property string glyph: ({ snow: "❄", autumn: "❧", rain: "☂", blossom: "✿", christmas: "✶", halloween: "☾" })[theme]
    property real reveal: active ? 1 : 0
    property real unfold: 0
    property real now: Date.now()
    property bool initialized: false
    readonly property var groups: SnowHush.menuItems.filter(item => item.hasChildren)
    readonly property var plain: SnowHush.menuItems.filter(item => !item.hasChildren && !item.isSeparator)
    // Top level, after the submenus: "Clear the snow" while something lies, "Support", "Quit".
    readonly property var clearEntry: plain.length >= 3 ? plain[plain.length - 3] : null
    readonly property var supportEntry: plain.length >= 2 ? plain[plain.length - 2] : null
    readonly property string fallingNow: {
        const kinds = [2, 3, 4, 5].map(i => SnowHush.modeItems[i]).filter(item => item && item.checkState === Qt.Checked);
        const names = kinds.map(item => card.label(item));
        if (SnowHush.newYear && SnowHush.newYear.checkState === Qt.Checked) names.push(card.label(SnowHush.newYear));
        if (SnowHush.halloween && SnowHush.halloween.checkState === Qt.Checked) names.push(card.label(SnowHush.halloween));
        return names.join(" · ");
    }

    function s(value: real): real { return card.rootObj.s(value); }
    function label(entry: var): string { return String(entry && entry.text || "").replace(/&/g, ""); }
    function clamp(value: real): real { return Math.max(0, Math.min(1, value)); }
    function toggle(): void {
        if (!SnowHush.available) return;
        globe.shake();
        SnowHush.setEnabled(!card.active);
    }
    function clock(ms: real): string {
        const total = Math.max(0, Math.floor(ms / 1000));
        const minutes = Math.floor(total / 60), seconds = total % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }
    function stageText(): string {
        switch (SnowHush.buildStage) {
        case "tools": return qsTr("Checking the build tools");
        case "fetch": return qsTr("Downloading the Snowhush source");
        case "patch": return qsTr("Fitting Serpantinum's surface bridge");
        case "crates": return qsTr("Gathering Rust crates");
        case "compile": return qsTr("Compiling the engine");
        case "link": return qsTr("Linking and optimising");
        case "install": return qsTr("Installing the engine");
        default: return qsTr("Preparing the build");
        }
    }
    function stageDetail(): string {
        const counted = SnowHush.buildTotal > 0 ? SnowHush.buildDone + " / " + SnowHush.buildTotal : "";
        switch (SnowHush.buildStage) {
        case "fetch": return counted ? counted + qsTr(" objects") : qsTr("Cloning the pinned release");
        case "compile": return qsTr("Crate ") + counted + (SnowHush.buildDetail ? "  ·  " + SnowHush.buildDetail : "");
        case "crates": return SnowHush.buildDetail || qsTr("Downloading dependencies");
        case "link": return qsTr("The last step has no counter: a minute or two, sometimes more");
        case "install": return qsTr("Almost there");
        default: return "";
        }
    }

    Layout.fillWidth: true
    implicitHeight: hero.height + statusBox.height + options.height
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: cardMask }

    Component.onCompleted: { initialized = true; if (ready) unfold = 1; Qt.callLater(updateTheme); }
    onReadyChanged: {
        Qt.callLater(updateTheme);
        if (!ready) { unfoldIn.stop(); unfold = 0; }
        else if (initialized && motion && onScreen) unfoldIn.restart();
        else unfold = 1;
    }
    Behavior on reveal {
        enabled: card.initialized && card.onScreen && card.motion
        NumberAnimation { duration: card.active ? 520 : 320; easing.type: Easing.OutCubic }
    }
    NumberAnimation { id: unfoldIn; target: card; property: "unfold"; from: 0; to: 1; duration: 950; easing.type: Easing.OutCubic }
    Timer { interval: 1000; repeat: true; running: SnowHush.building && card.onScreen; triggeredOnStart: true; onTriggered: card.now = Date.now() }

    Rectangle { id: cardMask; anchors.fill: parent; radius: card.s(20); visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; color: Qt.tint("#202324", Qt.alpha(card.ink, card.reveal)) }

    // ── Hero: wordmark, globe, stamp ─────────────────────────────────────────
    Item {
        id: hero
        width: parent.width
        height: Math.max(card.s(card.compact ? 250 : 240), intro.y + intro.implicitHeight + card.s(30))
        clip: true

        Item {
            id: scene
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { saturation: card.reveal - 1; brightness: -0.08 * (1 - card.reveal) }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: card.heroTop }
                    GradientStop { position: 1; color: card.ink }
                }
            }
            // riso grain: horizontal print lines and a scatter of paper speckle, painted once per size
            Canvas {
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    c.fillStyle = Qt.rgba(1, 1, 1, 0.035);
                    for (let y = 0; y < height; y += 3) c.fillRect(0, y, width, 1);
                    c.fillStyle = Qt.rgba(0.95, 0.92, 0.84, 0.07);
                    for (let i = 0; i < width * height / 700; i++)
                        c.fillRect((i * 7919 % 1000) / 1000 * width, (i * 104729 % 997) / 997 * height, 1.5, 1.5);
                }
            }

            Stamp {
                id: stamp
                height: card.s(card.compact ? 180 : 194)
                width: height * 0.76
                x: hero.width - width - card.s(card.compact ? 22 : 40)
                y: card.s(card.compact ? 22 : 18)
                rotation: 4
            }
            Postmark {
                visible: !card.compact || hero.width > card.s(520)
                x: stamp.x - width * 0.52
                y: stamp.y + stamp.height * 0.56
            }

            // snow falling across the whole postcard while the weather is on
            Repeater {
                model: card.snowing ? 30 : 0
                Rectangle {
                    required property int index
                    readonly property real seed: (index * 7919 % 997) / 997
                    readonly property real seed2: (index * 104729 % 991) / 991
                    readonly property real fall: t % 1
                    readonly property bool rain: card.theme === "rain"
                    readonly property bool leafy: card.theme === "autumn" || card.theme === "blossom"
                    readonly property real size: card.s(1.5 + index % 3 * 1.2)
                    property real t: seed
                    NumberAnimation on t {
                        from: seed; to: seed + 1; loops: Animation.Infinite
                        duration: (rain ? 900 + seed2 * 700 : leafy ? 9000 + seed2 * 6000 : 7000 + seed2 * 7000)
                    }
                    width: rain ? Math.max(1, card.s(1)) : leafy ? size * 2.2 : size
                    height: rain ? card.s(9 + index % 3 * 4) : leafy ? size * 1.3 : size
                    radius: rain ? 0 : leafy ? height / 2 : width / 2
                    rotation: rain ? 12 : leafy ? fall * 360 * (index % 2 ? 1 : -1) * (1 + seed2) : 0
                    x: hero.width * ((index * 0.137 + seed * 0.29) % 1) - (rain ? fall * card.s(30) : 0)
                       + (rain ? 0 : Math.sin(fall * Math.PI * 2 * (1 + seed2)) * card.s(leafy ? 22 : 9))
                    y: -card.s(14) + fall * (hero.height + card.s(28))
                    color: card.theme === "snow" || rain ? card.paper
                        : card.theme === "christmas" ? (index % 4 === 0 ? card.frost : card.paper)
                        : index % 3 === 0 ? card.frost : index % 3 === 1 ? card.teal : card.deep
                    opacity: (rain ? 0.35 : 0.3 + seed2 * 0.55) * Math.min(1, card.reveal * 1.4)
                }
            }

            // the drift along the bottom edge grows while the weather is on
            Shape {
                id: drift
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: card.s(26)
                readonly property real crest: card.s(5 + 12 * card.reveal)
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.alpha(card.paper, 0.13 + 0.12 * card.reveal)
                    startX: 0; startY: drift.height
                    PathLine { x: 0; y: drift.height - drift.crest * 0.6 }
                    PathCubic { x: drift.width * 0.34; y: drift.height - drift.crest * 0.9; control1X: drift.width * 0.1; control1Y: drift.height - drift.crest * 1.3; control2X: drift.width * 0.22; control2Y: drift.height - drift.crest * 0.3 }
                    PathCubic { x: drift.width * 0.72; y: drift.height - drift.crest * 0.7; control1X: drift.width * 0.48; control1Y: drift.height - drift.crest * 1.6; control2X: drift.width * 0.6; control2Y: drift.height - drift.crest * 0.2 }
                    PathCubic { x: drift.width; y: drift.height - drift.crest; control1X: drift.width * 0.84; control1Y: drift.height - drift.crest * 1.2; control2X: drift.width * 0.93; control2Y: drift.height - drift.crest * 0.5 }
                    PathLine { x: drift.width; y: drift.height }
                }
            }
        }

        ColumnLayout {
            id: intro
            x: card.s(card.compact ? 22 : 32)
            y: card.s(card.compact ? 20 : 24)
            width: stamp.x - x - card.s(card.compact ? 16 : 60)
            spacing: card.s(6)

            // eyebrow tag
            Rectangle {
                implicitWidth: eyebrow.implicitWidth + card.s(18)
                implicitHeight: card.s(22)
                radius: card.s(4)
                color: "transparent"
                border.color: Qt.alpha(card.paper, 0.35 + 0.3 * card.reveal)
                Text {
                    id: eyebrow
                    anchors.centerIn: parent
                    text: card.glyph + "  " + qsTr("DESKTOP WEATHER")
                    color: card.paper
                    opacity: 0.6 + 0.4 * card.reveal
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10); font.weight: Font.DemiBold
                    font.letterSpacing: card.s(2.5)
                }
            }

            // wordmark with a teal misregistered copy, like the print behind it
            Item {
                Layout.fillWidth: true
                implicitHeight: word.implicitHeight * 0.92
                Text {
                    x: card.s(3); y: card.s(3)
                    text: word.text; textFormat: Text.StyledText; font: word.font
                    color: Qt.alpha(card.teal, 0.35 + 0.5 * card.reveal)
                }
                Text {
                    id: word
                    text: "Snow <i>hush</i>"
                    textFormat: Text.StyledText
                    color: card.paper
                    font.family: "Noto Serif"
                    font.pixelSize: card.s(card.compact ? 38 : 52)
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                text: !SnowHush.available ? qsTr("Snow Hush needs a Wayland session.")
                    : card.ready && card.fallingNow ? qsTr("Now falling: ") + card.fallingNow
                    : card.active ? qsTr("Seasonal weather drifting over your desktop.")
                    : qsTr("Snow, leaves and rain that settle on your windows, dock and widgets.")
                color: card.softText
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }

            // the switch: a snow globe, with its call to action beside it
            RowLayout {
                Layout.topMargin: card.s(card.compact ? 6 : 10)
                spacing: card.s(16)

                Globe { id: globe }

                ColumnLayout {
                    spacing: card.s(2)
                    Layout.maximumWidth: intro.width - globe.width - card.s(16)
                    Text {
                        text: !card.active ? qsTr("Let it snow") : card.working ? qsTr("Shaking the globe…")
                            : ({ snow: qsTr("It's snowing"), autumn: qsTr("Leaves are falling"), rain: qsTr("It's raining"),
                                 blossom: qsTr("Petals are drifting"), christmas: qsTr("Season's greetings"),
                                 halloween: qsTr("A haunted snowfall") })[card.theme]
                        color: card.paper
                        font.family: "Noto Serif"; font.pixelSize: card.s(card.compact ? 18 : 21); font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: SnowHush.available; onClicked: card.toggle() }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !card.active ? qsTr("Press the globe to start the weather") : qsTr("Press the globe again to stop it")
                        color: card.faint
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // ── Status: first build, waking the engine, errors ───────────────────────
    Item {
        id: statusBox
        anchors.top: hero.bottom
        width: parent.width
        readonly property bool shown: card.working || card.troubled
        height: shown ? statusPanel.implicitHeight + card.s(28) : 0
        clip: true
        Behavior on height {
            enabled: card.initialized && card.onScreen && card.motion
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: statusPanel
            x: card.s(card.compact ? 16 : 24); y: card.s(14)
            width: parent.width - 2 * x
            implicitHeight: statusColumn.implicitHeight + card.s(30)
            height: implicitHeight
            radius: card.s(14)
            color: card.well
            border.color: card.troubled ? Qt.alpha(card.ember, 0.45) : Qt.alpha(card.teal, 0.45)
            opacity: statusBox.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            ColumnLayout {
                id: statusColumn
                x: card.s(18); y: card.s(15)
                width: parent.width - 2 * x
                spacing: card.s(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: card.s(10)
                    Text {
                        text: card.troubled ? "!" : card.glyph
                        color: card.troubled ? card.ember : card.frost
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(16); font.weight: Font.Bold
                        RotationAnimation on rotation {
                            running: card.working && !card.troubled && card.motion && card.onScreen
                            from: 0; to: 360; duration: 4000; loops: Animation.Infinite
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.troubled ? qsTr("Snow Hush hit a snag")
                            : SnowHush.building ? qsTr("Building the Snowhush engine") + (card.compact ? "" : qsTr("  ·  first launch only"))
                            : qsTr("Waking the engine…")
                        color: card.troubled ? card.ember : card.paper
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(14); font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: SnowHush.building && !card.troubled
                        text: card.clock(card.now - SnowHush.buildStartedAt)
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                    }
                }

                // progress: a frosted track that fills with snow
                Item {
                    id: bar
                    Layout.fillWidth: true
                    visible: !card.troubled
                    implicitHeight: card.s(12)
                    readonly property bool counted: SnowHush.building && SnowHush.buildStage !== "link" && SnowHush.buildStage !== ""
                    Rectangle { id: track; anchors.fill: parent; radius: height / 2; color: card.ink2; border.color: card.line }
                    Rectangle {
                        id: fill
                        height: parent.height; radius: height / 2
                        width: Math.max(height, parent.width * (SnowHush.building ? SnowHush.buildProgress : 0))
                        visible: SnowHush.building
                        color: card.frost
                        Behavior on width { enabled: card.motion; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                    }
                    // work with no counter (linking, waking): a glint runs along the unfilled part
                    Rectangle {
                        id: glint
                        visible: !bar.counted && card.motion && card.onScreen
                        readonly property real from: SnowHush.building ? fill.width : 0
                        property real t: 0
                        NumberAnimation on t { running: glint.visible; from: 0; to: 1; duration: 1500; loops: Animation.Infinite; easing.type: Easing.InOutSine }
                        height: parent.height; radius: height / 2
                        width: Math.min(card.s(90), Math.max(0, parent.width - from))
                        x: from + (parent.width - from - width) * t
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(card.frost, 0) }
                            GradientStop { position: 0.5; color: Qt.alpha(card.frost, 0.8) }
                            GradientStop { position: 1; color: Qt.alpha(card.frost, 0) }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !card.troubled
                    spacing: card.s(10)
                    Text {
                        text: SnowHush.building ? card.stageText() : qsTr("Starting Snowhush and waiting for its controls")
                        color: card.paper
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: SnowHush.building ? card.stageDetail() : ""
                        color: card.faint
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: SnowHush.building
                        text: Math.round(SnowHush.buildProgress * 100) + "%"
                        color: card.frost
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12); font.weight: Font.DemiBold
                    }
                }

                // CPU heads-up while the engine compiles
                RowLayout {
                    Layout.fillWidth: true
                    visible: SnowHush.building && !card.troubled
                    spacing: card.s(10)
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: cpuTag.implicitWidth + card.s(12); implicitHeight: card.s(19)
                        radius: card.s(4)
                        color: Qt.alpha(card.ember, 0.16)
                        Text {
                            id: cpuTag
                            anchors.centerIn: parent
                            text: "CPU"
                            color: card.ember
                            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10); font.weight: Font.Bold; font.letterSpacing: card.s(1)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("The engine is compiled from source on your machine: expect busy cores and some fan noise for a few minutes. It runs at low priority so you can keep working, and only happens again when the engine is updated. Press the globe to cancel.")
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                        wrapMode: Text.Wrap; lineHeight: 1.15
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.troubled
                    text: SnowHush.error || SnowHush.modeError
                    color: card.softText
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                    wrapMode: Text.Wrap
                }
                Row {
                    visible: Boolean(SnowHush.error)
                    spacing: card.s(8)
                    Pill { text: qsTr("Try again"); onClicked: SnowHush.setEnabled(true) }
                    Pill {
                        readonly property string log: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/serpantinum-addons-v2/snowhush/build.log"
                        visible: SnowHush.error.indexOf("build.log") >= 0
                        text: qsTr("Open the build log")
                        onClicked: Quickshell.execDetached(["xdg-open", log])
                    }
                }
            }
        }
    }

    // ── Options: the engine's tray menu, laid out ────────────────────────────
    Item {
        id: options
        anchors.top: statusBox.bottom
        width: parent.width
        height: card.ready && settings.item ? settings.item.implicitHeight : 0
        clip: true
        enabled: card.ready
        Behavior on height {
            enabled: card.initialized && card.onScreen && card.motion
            NumberAnimation { duration: card.ready ? 480 : 300; easing.type: Easing.OutCubic }
        }

        Loader {
            id: settings
            width: parent.width
            active: card.ready || options.height > 0
            sourceComponent: ColumnLayout {
                width: settings.width
                spacing: card.s(22)

                Item { implicitHeight: card.s(2) }

                Section {
                    order: 0
                    number: "01"
                    title: card.label(SnowHush.menuItems[3]) || qsTr("Weather")
                    hint: qsTr("what falls")
                    // Mixed governs every kind, so it sits apart, above them
                    Rectangle {
                        Layout.fillWidth: true
                        visible: Boolean(SnowHush.mixed)
                        implicitHeight: mixedRow.implicitHeight + card.s(12)
                        radius: card.s(12)
                        color: Qt.alpha(card.ink2, 0.6)
                        border.color: card.line
                        RowLayout {
                            id: mixedRow
                            anchors.fill: parent
                            anchors.margins: card.s(6)
                            anchors.rightMargin: card.s(14)
                            spacing: card.s(10)
                            SwitchRow {
                                Layout.preferredWidth: implicitWidth
                                text: "⁂  " + card.label(SnowHush.mixed)
                                on: Boolean(SnowHush.mixed && SnowHush.mixed.checkState === Qt.Checked)
                                enabled: Boolean(SnowHush.mixed && SnowHush.mixed.enabled)
                                onFlipped: SnowHush.mixed.triggered()
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("let several kinds fall together; the tiles below then combine")
                                color: card.faint
                                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.italic: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: card.s(8)
                        // Snow with its own variants: Halloween and New Year only ride on snow
                        Rectangle {
                            width: snowGroup.implicitWidth + card.s(12)
                            height: snowGroup.implicitHeight + card.s(12)
                            radius: card.s(16)
                            color: Qt.alpha(card.ink2, 0.45)
                            border.color: card.line
                            Row {
                                id: snowGroup
                                x: card.s(6); y: card.s(6)
                                spacing: card.s(8)
                                Tile { entry: SnowHush.snow; glyph: "❄" }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: card.s(6)
                                    Pill { entry: SnowHush.halloween; prefix: "☾  " }
                                    Pill { entry: SnowHush.newYear; prefix: "✶  "; fallbackMode: "new-year" }
                                }
                            }
                        }
                        Repeater {
                            model: [{ index: 3, glyph: "❧" }, { index: 4, glyph: "☂" }, { index: 5, glyph: "✿" }]
                            Item {
                                required property var modelData
                                visible: kind.visible
                                width: kind.implicitWidth
                                height: kind.implicitHeight + card.s(12)
                                Tile {
                                    id: kind
                                    y: card.s(6)
                                    entry: SnowHush.modeItems[parent.modelData.index] || null
                                    glyph: parent.modelData.glyph
                                }
                            }
                        }
                    }
                }

                Section {
                    order: 1
                    number: "02"
                    title: qsTr("Snowfall")
                    hint: qsTr("how much, how bright")
                    Gauge { entry: SnowHush.menuItems[0] || null }
                    Gauge { entry: SnowHush.menuItems[1] || null }
                }

                Section {
                    order: 2
                    number: "03"
                    title: card.label(SnowHush.menuItems[2]) || qsTr("Where it settles")
                    hint: qsTr("where it piles up")
                    Checks { entry: SnowHush.menuItems[2] || null }
                    Pill {
                        visible: Boolean(card.clearEntry)
                        entry: card.clearEntry
                        prefix: "⌫  "
                    }
                }

                Section {
                    order: 3
                    number: "04"
                    title: card.label(card.groups[card.groups.length - 1]) || qsTr("Settings")
                    hint: qsTr("how it behaves")
                    Toggles { entry: card.groups.length > 4 ? card.groups[card.groups.length - 1] : null }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.s(card.compact ? 20 : 30)
                    Layout.rightMargin: card.s(card.compact ? 20 : 30)
                    Layout.bottomMargin: card.s(18)
                    opacity: card.clamp((card.unfold - 0.5) / 0.4)
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Engine: Snowhush by Mykhailo Bezruchko")
                        color: card.faint
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10)
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: Boolean(card.supportEntry)
                        text: card.label(card.supportEntry) + "  ↗"
                        color: supportArea.containsMouse ? card.paper : card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.underline: supportArea.containsMouse
                        MouseArea {
                            id: supportArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (card.supportEntry) card.supportEntry.triggered()
                        }
                    }
                }
            }
        }
    }

    // ── Components ───────────────────────────────────────────────────────────

    // Perforated postage stamp holding the artwork.
    component Stamp: Item {
        id: stampItem
        Canvas {
            id: perforation
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.fillStyle = "#f2ebd6";
                c.fillRect(0, 0, width, height);
                c.globalCompositeOperation = "destination-out";
                const r = card.s(3.2), gap = r * 3.1;
                c.beginPath();
                for (let x = gap / 2; x < width; x += gap) { c.moveTo(x + r, 0); c.arc(x, 0, r, 0, Math.PI * 2); c.moveTo(x + r, height); c.arc(x, height, r, 0, Math.PI * 2); }
                for (let y = gap / 2; y < height; y += gap) { c.moveTo(r, y); c.arc(0, y, r, 0, Math.PI * 2); c.moveTo(width + r, y); c.arc(width, y, r, 0, Math.PI * 2); }
                c.fill();
            }
        }
        Image {
            anchors.fill: parent
            anchors.margins: card.s(9)
            anchors.bottomMargin: card.s(24)
            layer.enabled: card.tint > 0.01
            layer.effect: MultiEffect { colorization: card.tint; colorizationColor: card.deep }
            source: "winter.jpg"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            mipmap: true
            sourceSize.width: width * 2
        }
        Text {
            anchors.bottom: parent.bottom; anchors.bottomMargin: card.s(6)
            anchors.left: parent.left; anchors.leftMargin: card.s(10)
            text: "SNOW HUSH"
            color: card.ink
            font.family: "Noto Serif"; font.pixelSize: card.s(9); font.weight: Font.Bold; font.letterSpacing: card.s(1.5)
        }
        Text {
            anchors.bottom: parent.bottom; anchors.bottomMargin: card.s(4)
            anchors.right: parent.right; anchors.rightMargin: card.s(10)
            text: card.glyph
            color: card.deep
            font.pixelSize: card.s(13)
        }
    }

    // Round cancellation mark with wavy lines, stamped over the stamp's corner; it turns slowly while it snows.
    component Postmark: Item {
        id: mark
        width: card.s(96); height: width
        opacity: 0.35 + 0.4 * card.reveal
        readonly property string ring: "SNOW HUSH ✶ WINTER " + new Date().getFullYear() + " ✶ "
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: card.paper; border.width: card.s(1.5) }
        Rectangle { anchors.fill: parent; anchors.margins: card.s(22); radius: width / 2; color: "transparent"; border.color: card.paper; border.width: card.s(1) }
        Item {
            id: letters
            anchors.fill: parent
            RotationAnimation on rotation {
                running: card.snowing
                from: 0; to: 360; duration: 60000; loops: Animation.Infinite
            }
            Repeater {
                model: mark.ring.length
                Text {
                    required property int index
                    text: mark.ring[index]
                    color: card.paper
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(8.5); font.weight: Font.Bold
                    x: letters.width / 2 - width / 2
                    y: card.s(5)
                    transform: Rotation { origin.x: width / 2; origin.y: letters.height / 2 - card.s(5); angle: index * 360 / mark.ring.length }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: "❄"
            color: card.paper
            font.pixelSize: card.s(20)
        }
    }

    // The power switch: a snow globe seated in its base, shaken on every press.
    component Globe: Item {
        id: globeItem
        readonly property real d: card.s(card.compact ? 74 : 86)
        readonly property real r: d / 2
        readonly property real groundY: d * 0.68
        implicitWidth: d * 1.1
        implicitHeight: d * 1.16
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Snow Hush weather")
        Accessible.checkable: true
        Accessible.checked: card.active
        Accessible.onPressAction: card.toggle()
        Keys.onSpacePressed: card.toggle()
        Keys.onReturnPressed: card.toggle()
        Keys.onEnterPressed: card.toggle()
        opacity: SnowHush.available ? 1 : 0.45
        scale: area.pressed ? 0.94 : area.containsMouse ? 1.04 : 1
        Behavior on scale { enabled: card.motion; NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        function shake(): void { if (card.motion && card.onScreen) shaking.restart(); }
        SequentialAnimation {
            id: shaking
            RotationAnimation { target: dome; to: -9; duration: 70 }
            RotationAnimation { target: dome; to: 7; duration: 90 }
            RotationAnimation { target: dome; to: -4; duration: 90 }
            RotationAnimation { target: dome; to: 0; duration: 140; easing.type: Easing.OutBack }
        }

        // glow behind the dome while on
        Rectangle {
            x: dome.x + globeItem.r - width / 2; y: globeItem.r - height / 2
            width: globeItem.d * 1.32; height: width; radius: width / 2
            color: Qt.alpha(card.teal, 0.2 * card.reveal + (area.containsMouse ? 0.08 : 0))
        }
        Item {
            id: dome
            x: (globeItem.width - width) / 2
            width: globeItem.d; height: globeItem.d
            transformOrigin: Item.Bottom
            // water
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.tint("#4a4e4e", Qt.alpha(Qt.lighter(card.teal, 1.15), card.reveal)) }
                    GradientStop { position: 1; color: Qt.tint("#232627", Qt.alpha(card.ink, card.reveal)) }
                }
            }
            // snow lying inside: the circle's lower segment under a soft mound
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    id: groundPath
                    readonly property real half: Math.sqrt(Math.max(0, globeItem.r * globeItem.r - Math.pow(globeItem.groundY - globeItem.r, 2)))
                    strokeWidth: -1
                    fillColor: Qt.alpha(card.paper, 0.4 + 0.5 * card.reveal)
                    startX: globeItem.r - half; startY: globeItem.groundY
                    PathArc {
                        x: globeItem.r + groundPath.half; y: globeItem.groundY
                        radiusX: globeItem.r; radiusY: globeItem.r
                        direction: PathArc.Counterclockwise
                    }
                    PathQuad { x: globeItem.r - groundPath.half; y: globeItem.groundY; controlX: globeItem.r; controlY: globeItem.groundY - globeItem.d * 0.12 }
                }
            }
            // a six-armed flake, drawn so it turns about its true centre
            Item {
                id: flake
                width: globeItem.d * 0.42; height: width
                x: globeItem.r - width / 2
                y: globeItem.d * 0.4 - height / 2
                opacity: 0.6 + 0.4 * card.reveal
                RotationAnimation on rotation { running: card.snowing; from: 0; to: 360; duration: 16000; loops: Animation.Infinite }
                Repeater {
                    model: 6
                    Shape {
                        required property int index
                        anchors.fill: parent
                        rotation: index * 60
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            id: arm
                            readonly property real c: flake.width / 2
                            readonly property real len: flake.width / 2 * 0.92
                            strokeColor: card.paper
                            strokeWidth: Math.max(1.5, card.s(2))
                            capStyle: ShapePath.RoundCap
                            fillColor: "transparent"
                            startX: c; startY: c
                            PathLine { x: arm.c; y: arm.c - arm.len }
                            PathMove { x: arm.c; y: arm.c - arm.len * 0.55 }
                            PathLine { x: arm.c - arm.len * 0.26; y: arm.c - arm.len * 0.8 }
                            PathMove { x: arm.c; y: arm.c - arm.len * 0.55 }
                            PathLine { x: arm.c + arm.len * 0.26; y: arm.c - arm.len * 0.8 }
                        }
                    }
                }
            }
            // flakes swirling in the water
            Repeater {
                model: card.snowing ? 8 : 0
                Rectangle {
                    required property int index
                    property real a: index / 8 * Math.PI * 2
                    NumberAnimation on a { from: index / 8 * Math.PI * 2; to: index / 8 * Math.PI * 2 + Math.PI * 2; duration: 5000 + index * 600; loops: Animation.Infinite }
                    readonly property real orbit: globeItem.d * (0.18 + (index % 3) * 0.06)
                    width: card.s(2 + index % 2); height: width; radius: width / 2
                    x: globeItem.r + Math.cos(a) * orbit - width / 2
                    y: globeItem.d * 0.42 + Math.sin(a) * orbit * 0.7 - height / 2
                    color: card.paper
                    opacity: 0.8
                }
            }
            // glass rim and highlight
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: card.s(2)
                border.color: globeItem.activeFocus ? "white" : Qt.alpha(card.paper, 0.45 + 0.3 * card.reveal)
            }
            Rectangle {
                x: parent.width * 0.18; y: parent.height * 0.12
                width: parent.width * 0.3; height: parent.height * 0.14
                radius: height / 2
                rotation: -32
                color: Qt.alpha("white", 0.22)
            }
        }
        // the base: a flared stand that hides the bottom of the dome
        Shape {
            id: base
            anchors.horizontalCenter: parent.horizontalCenter
            y: globeItem.d * 0.84
            width: globeItem.d * 0.92; height: globeItem.height - y
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: base.height
                    GradientStop { position: 0; color: Qt.tint("#7d807f", Qt.alpha(Qt.lighter(card.deep, 1.2), card.reveal)) }
                    GradientStop { position: 1; color: Qt.tint("#4b4e4d", Qt.alpha(Qt.darker(card.deep, 1.5), card.reveal)) }
                }
                startX: base.width * 0.16; startY: 0
                PathLine { x: base.width * 0.84; y: 0 }
                PathQuad { x: base.width; y: base.height; controlX: base.width * 0.9; controlY: base.height * 0.55 }
                PathLine { x: 0; y: base.height }
                PathQuad { x: base.width * 0.16; y: 0; controlX: base.width * 0.1; controlY: base.height * 0.55 }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.7; height: Math.max(1, card.s(2)); radius: height / 2
                color: Qt.alpha(card.paper, 0.35 + 0.35 * card.reveal)
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.5
                width: parent.width * 0.36; height: Math.max(1, card.s(1.5)); radius: height / 2
                color: Qt.alpha(card.paper, 0.3)
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: SnowHush.available
            cursorShape: Qt.PointingHandCursor
            onClicked: { globeItem.forceActiveFocus(Qt.MouseFocusReason); card.toggle(); }
        }
    }

    // A numbered section of the options; it slides in after the ones before it.
    component Section: ColumnLayout {
        id: section
        property int order: 0
        property string number
        property string title
        property string hint
        readonly property real shown: card.clamp((card.unfold - order * 0.13) / 0.45)
        Layout.fillWidth: true
        Layout.leftMargin: card.s(card.compact ? 20 : 30)
        Layout.rightMargin: card.s(card.compact ? 20 : 30)
        spacing: card.s(10)
        opacity: shown
        transform: Translate { y: (1 - section.shown) * card.s(14) }

        RowLayout {
            Layout.fillWidth: true
            spacing: card.s(10)
            Text {
                text: section.number
                color: card.teal
                font.family: "Noto Serif"; font.pixelSize: card.s(13); font.italic: true; font.weight: Font.DemiBold
            }
            Text {
                text: section.title
                color: card.paper
                font.family: "Noto Serif"; font.pixelSize: card.s(17); font.weight: Font.DemiBold
            }
            Rectangle {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.max(1, card.s(1))
                color: Qt.alpha(card.teal, 0.35)
            }
            Text {
                visible: !card.compact
                text: section.hint
                color: card.faint
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.italic: true
            }
        }
    }

    // A weather kind: a big tile with its glyph, lit when it falls.
    component Tile: AbstractButton {
        id: tile
        property var entry: null
        property string glyph
        readonly property bool isNewYear: entry !== null && entry === SnowHush.newYear
        readonly property bool on: Boolean(entry && entry.checkState === Qt.Checked)
        visible: Boolean(entry)
        enabled: Boolean(entry && (entry.enabled || isNewYear))
        implicitWidth: card.s(card.compact ? 92 : 108)
        implicitHeight: card.s(card.compact ? 70 : 78)
        Accessible.role: Accessible.RadioButton
        Accessible.name: card.label(entry)
        Accessible.checked: on
        onClicked: {
            if (entry && entry.enabled) entry.triggered();
            else if (isNewYear) SnowHush.selectMode("new-year");
        }
        background: Rectangle {
            radius: card.s(12)
            color: tile.on ? card.paper : tile.hovered ? card.hover : card.ink2
            border.color: tile.visualFocus ? "white" : tile.on ? card.paper : card.line
            border.width: card.s(1)
            Behavior on color { enabled: card.motion; ColorAnimation { duration: 160 } }
        }
        contentItem: Item {
            opacity: tile.enabled ? 1 : 0.4
            Text {
                id: glyphText
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12 + (tile.on && card.snowing ? bob : 0)
                property real bob: 0
                SequentialAnimation on bob {
                    running: tile.on && card.snowing
                    loops: Animation.Infinite
                    NumberAnimation { to: card.s(3); duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
                }
                text: tile.glyph
                color: tile.on ? card.deep : card.frost
                font.pixelSize: card.s(card.compact ? 22 : 26)
            }
            Text {
                anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.label(tile.entry)
                color: tile.on ? card.ink : card.paper
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.weight: tile.on ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }
    }

    // A radio submenu as a stepped gauge: every step up to the chosen one is filled.
    component Gauge: RowLayout {
        id: gauge
        property var entry: null
        readonly property var listed: (opener.children.values || []).filter(item => !item.isSeparator && item.text)
        // Read as numbers ("Off" is 0); a menu listed high to low (opacity) is shown low to high, so the gauge fills up.
        readonly property bool descending: listed.length > 1 && (parseInt(card.label(listed[0])) || 0) > (parseInt(card.label(listed[listed.length - 1])) || 0)
        readonly property var steps: descending ? listed.slice().reverse() : listed
        readonly property int chosen: steps.findIndex(item => item.checkState === Qt.Checked)
        Layout.fillWidth: true
        visible: Boolean(entry) && steps.length > 0
        spacing: card.s(14)
        QsMenuOpener { id: opener; menu: gauge.entry }

        Text {
            Layout.preferredWidth: card.s(card.compact ? 74 : 96)
            text: card.label(gauge.entry)
            color: card.softText
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
            elide: Text.ElideRight
        }
        Row {
            id: stepRow
            Layout.fillWidth: true
            spacing: card.s(4)
            readonly property real stepWidth: (width - spacing * (gauge.steps.length - 1)) / Math.max(1, gauge.steps.length)
            Repeater {
                model: gauge.steps
                AbstractButton {
                    id: step
                    required property var modelData
                    required property int index
                    readonly property bool filled: index <= gauge.chosen && gauge.chosen >= 0
                    width: stepRow.stepWidth
                    height: card.s(36)
                    enabled: Boolean(modelData && modelData.enabled)
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: card.label(gauge.entry) + " " + card.label(modelData)
                    Accessible.checked: index === gauge.chosen
                    onClicked: modelData.triggered()
                    background: Item {}
                    contentItem: Item {
                        Rectangle {
                            width: parent.width; height: card.s(index === gauge.chosen ? 12 : 8)
                            y: card.s(12) - height
                            radius: card.s(3)
                            color: step.filled ? Qt.tint(card.frost, Qt.alpha(card.paper, (index + 1) / gauge.steps.length)) : step.hovered ? card.hover : card.ink2
                            border.color: step.visualFocus ? "white" : "transparent"
                            Behavior on color { enabled: card.motion; ColorAnimation { duration: 160 } }
                            Behavior on height { enabled: card.motion; NumberAnimation { duration: 160 } }
                        }
                        Text {
                            y: card.s(17)
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: card.label(step.modelData)
                            color: index === gauge.chosen ? card.paper : step.hovered ? card.softText : card.faint
                            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10)
                            font.weight: index === gauge.chosen ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // A checkmark submenu as a row of pills.
    component Checks: Flow {
        id: checks
        property var entry: null
        Layout.fillWidth: true
        visible: Boolean(entry)
        spacing: card.s(6)
        QsMenuOpener { id: checksOpener; menu: checks.entry }
        Repeater {
            model: (checksOpener.children.values || []).filter(item => !item.isSeparator && item.text)
            Pill { required property var modelData; entry: modelData }
        }
    }

    // The settings submenu: its disabled headers become small captions, its checkmarks switches.
    component Toggles: GridLayout {
        id: toggles
        property var entry: null
        readonly property var items: (togglesOpener.children.values || []).filter(item => !item.isSeparator && item.text)
        property var switches: ({})
        Layout.fillWidth: true
        visible: Boolean(entry)
        columns: card.compact ? 1 : 2
        columnSpacing: card.s(18)
        rowSpacing: card.s(4)
        QsMenuOpener { id: togglesOpener; menu: toggles.entry }

        Repeater {
            // Snowhush's own "open at login" (last) is replaced by starting with the shell.
            model: toggles.items.slice(0, -1)
            Item {
                id: cell
                required property var modelData
                // Captions are Snowhush's plain items. After a toggle the engine republishes its menu and an entry can
                // report no button type for a moment, so this is decided once (and rechecked shortly after), never
                // bound: a label once seen as a switch stays a switch.
                property bool header: false
                function classify(): void {
                    const name = card.label(cell.modelData);
                    if (cell.modelData.buttonType !== QsMenuButtonType.None) toggles.switches[name] = true;
                    cell.header = !toggles.switches[name];
                }
                Component.onCompleted: { classify(); recheck.start(); }
                Timer { id: recheck; interval: 600; onTriggered: cell.classify() }
                // equal tiny preferred widths: the grid shares its width evenly between the columns
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.columnSpan: header ? toggles.columns : 1
                Layout.topMargin: header ? card.s(6) : 0
                implicitHeight: header ? captionText.implicitHeight : switchRow.implicitHeight
                Text {
                    id: captionText
                    visible: cell.header
                    text: card.label(cell.modelData).toUpperCase()
                    color: card.faint
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10); font.weight: Font.DemiBold
                    font.letterSpacing: card.s(1.5)
                }
                SwitchRow {
                    id: switchRow
                    width: parent.width
                    visible: !cell.header
                    text: card.label(cell.modelData)
                    on: cell.modelData.checkState === Qt.Checked
                    enabled: Boolean(cell.modelData.enabled)
                    onFlipped: cell.modelData.triggered()
                }
            }
        }
        SwitchRow {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: qsTr("Start with Serpantinum")
            on: SnowHush.startWithShell
            onFlipped: SnowHush.setStartWithShell(!SnowHush.startWithShell)
        }
    }

    component SwitchRow: AbstractButton {
        id: row
        property bool on: false
        signal flipped()
        implicitHeight: card.s(34)
        Accessible.role: Accessible.CheckBox
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: on
        onClicked: row.flipped()
        background: Rectangle {
            radius: card.s(8)
            color: row.hovered ? card.ink2 : "transparent"
            border.color: row.visualFocus ? "white" : "transparent"
        }
        contentItem: RowLayout {
            spacing: card.s(10)
            opacity: row.enabled ? 1 : 0.45
            Rectangle {
                implicitWidth: card.s(34); implicitHeight: card.s(19)
                Layout.leftMargin: card.s(6)
                radius: height / 2
                color: row.on ? card.frost : card.ink2
                border.color: row.on ? card.frost : card.line
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 160 } }
                Rectangle {
                    width: card.s(13); height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: row.on ? parent.width - width - card.s(3) : card.s(3)
                    color: row.on ? card.ink : card.softText
                    Behavior on x { enabled: card.motion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                Layout.fillWidth: true
                text: row.text
                color: card.paper
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                elide: Text.ElideRight
            }
        }
    }

    // A small rounded button; given a menu entry it mirrors and triggers it, checkmark entries show their state.
    component Pill: AbstractButton {
        id: pill
        property var entry: null
        property string prefix: ""
        property string fallbackMode: ""
        readonly property bool isCheck: Boolean(entry && entry.buttonType !== QsMenuButtonType.None)
        readonly property bool on: Boolean(entry && entry.checkState === Qt.Checked)
        visible: entry === null ? text !== "" : Boolean(entry)
        enabled: entry === null || Boolean(entry && (entry.enabled || fallbackMode))
        text: entry ? card.label(entry) : ""
        horizontalPadding: card.s(12)
        verticalPadding: card.s(7)
        Accessible.role: isCheck ? Accessible.CheckBox : Accessible.Button
        Accessible.name: text
        Accessible.checkable: isCheck
        Accessible.checked: on
        onClicked: {
            if (entry && entry.enabled) entry.triggered();
            else if (entry && fallbackMode) SnowHush.selectMode(fallbackMode);
        }
        contentItem: Text {
            text: (pill.isCheck && pill.on ? "✓  " : pill.prefix) + pill.text
            color: !pill.enabled ? card.faint : pill.on ? card.ink : card.paper
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: height / 2
            color: !pill.enabled ? "transparent" : pill.on ? card.frost : pill.hovered ? card.hover : card.ink2
            border.color: pill.visualFocus ? "white" : !pill.enabled ? card.line : pill.on ? card.frost : card.line
            Behavior on color { enabled: card.motion; ColorAnimation { duration: 160 } }
        }
    }
}
