import QtQuick
import QtQml.Models
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../"
import "../reusables"

// The weather switch: a snow globe and the artwork as a stamp over the shell's own surfaces, then the engine's tray
// menu laid out as weather buttons, gauges and toggles once it is running.
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
    // Snow's variants stay folded into its tile until Snow falls. Kept while the options close.
    property bool snowPicked: false
    function updateTheme(): void {
        const on = i => Boolean(SnowHush.modeItems[i] && SnowHush.modeItems[i].checkState === Qt.Checked);
        card.theme = !card.ready ? "snow" : on(7) ? "halloween" : on(8) ? "christmas" : on(2) ? "snow"
            : on(5) ? "blossom" : on(3) ? "autumn" : on(4) ? "rain" : "snow";
        if (card.ready) card.snowPicked = on(2);
        const pal = card.palettes[card.theme];
        card.ink = pal.ink; card.teal = pal.accent; card.deep = pal.deep; card.frost = pal.frost; card.paper = pal.paper;
        card.tint = pal.tint;
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
        snow:      { ink: "#10292c", accent: "#4fb0b6", deep: "#2c7d83", frost: "#cfe9e4", paper: "#f2ebd6", tint: 0 },
        autumn:    { ink: "#2a170d", accent: "#e0913c", deep: "#a8541c", frost: "#f5cf98", paper: "#f7ead6", tint: 0.62 },
        rain:      { ink: "#111a27", accent: "#82a7da", deep: "#4a6fa3", frost: "#cddbee", paper: "#eef1f6", tint: 0.55 },
        blossom:   { ink: "#29141f", accent: "#e995b7", deep: "#c45d86", frost: "#f9d3e2", paper: "#fbeff2", tint: 0.6 },
        christmas: { ink: "#0e2318", accent: "#ea7066", deep: "#a3332d", frost: "#f2d48c", paper: "#f6efdf", tint: 0.5 },
        halloween: { ink: "#180f24", accent: "#ff8a2b", deep: "#8f4bd6", frost: "#ffc78c", paper: "#f2e8dc", tint: 0.6 }
    })
    property color ink: "#10292c"
    property color teal: "#4fb0b6"
    property color deep: "#2c7d83"
    property color frost: "#cfe9e4"
    property color paper: "#f2ebd6"
    property real tint: 0
    readonly property color fg: ThemeBackend.text
    readonly property color softText: ThemeBackend.subtext0
    readonly property color surface: ThemeBackend.surface0
    readonly property color hover: ThemeBackend.surface1
    readonly property color well: ThemeBackend.mantle
    readonly property real corner: s(ThemeBackend.clampedBorderRadius)
    readonly property color ember: "#ffbfa8"
    Behavior on ink { ColorAnimation { duration: 600 } }
    Behavior on teal { ColorAnimation { duration: 600 } }
    Behavior on deep { ColorAnimation { duration: 600 } }
    Behavior on frost { ColorAnimation { duration: 600 } }
    Behavior on paper { ColorAnimation { duration: 600 } }
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
    // The engine's "New Year" switch is presented as "Festive".
    function label(entry: var): string {
        if (entry && entry === SnowHush.newYear) return qsTr("Festive");
        return String(entry && entry.text || "").replace(/&/g, "");
    }
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

    FontLoader { id: titleFace; source: "Shrikhand-Regular.ttf" }

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
    Rectangle { anchors.fill: parent; color: Qt.tint(ThemeBackend.base, Qt.alpha(card.teal, 0.07 + 0.04 * card.reveal)) }

    // ── Hero: wordmark, globe, stamp ─────────────────────────────────────────
    Item {
        id: hero
        width: parent.width
        height: Math.max(card.s(card.compact ? 220 : 228), intro.y + intro.implicitHeight + card.s(14))
        clip: true

        Item {
            id: scene
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { saturation: card.reveal - 1; brightness: -0.08 * (1 - card.reveal) }

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
                    color: card.theme === "snow" || rain ? card.fg
                        : card.theme === "christmas" ? (index % 4 === 0 ? card.teal : card.fg)
                        : index % 2 === 0 ? card.teal : card.deep
                    opacity: (rain ? 0.35 : 0.3 + seed2 * 0.55) * Math.min(1, card.reveal * 1.4)
                }
            }

        }

        ColumnLayout {
            id: intro
            x: card.s(card.compact ? 22 : 32)
            y: card.s(card.compact ? 20 : 24)
            width: stamp.x - x - card.s(card.compact ? 16 : 60)
            spacing: card.s(6)

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: card.s(card.compact ? 46 : 58)
                text: "Snow <font color='" + card.teal + "'>Hush</font>"
                textFormat: Text.StyledText
                color: card.fg
                font.family: titleFace.status === FontLoader.Ready ? titleFace.font.family : ThemeBackend.fontFamily
                font.pixelSize: card.s(card.compact ? 34 : 44)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: card.s(22)
                verticalAlignment: Text.AlignVCenter
                Accessible.name: "Snow Hush"
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
                        color: card.fg
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(card.compact ? 15 : 17); font.weight: Font.Bold
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: SnowHush.available; onClicked: card.toggle() }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !card.active ? qsTr("Press the globe to start the weather") : qsTr("Press the globe again to stop it")
                        color: card.softText
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
                        color: card.troubled ? card.ember : card.teal
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
                        color: card.troubled ? card.ember : card.fg
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
                    Rectangle { id: track; anchors.fill: parent; radius: height / 2; color: card.surface; border.color: card.hover }
                    Rectangle {
                        id: fill
                        height: parent.height; radius: height / 2
                        width: Math.max(height, parent.width * (SnowHush.building ? SnowHush.buildProgress : 0))
                        visible: SnowHush.building
                        color: card.teal
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
                            GradientStop { position: 0; color: Qt.alpha(card.teal, 0) }
                            GradientStop { position: 0.5; color: Qt.alpha(card.teal, 0.8) }
                            GradientStop { position: 1; color: Qt.alpha(card.teal, 0) }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !card.troubled
                    spacing: card.s(10)
                    Text {
                        text: SnowHush.building ? card.stageText() : qsTr("Starting Snowhush and waiting for its controls")
                        color: card.fg
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: SnowHush.building ? card.stageDetail() : ""
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: SnowHush.building
                        text: Math.round(SnowHush.buildProgress * 100) + "%"
                        color: card.teal
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
                spacing: card.s(10)

                Section {
                    order: 0
                    title: card.label(SnowHush.menuItems[3]) || qsTr("Weather")
                    Flow {
                        Layout.fillWidth: true
                        spacing: card.s(8)
                        // Snow with its own variants: Halloween and New Year only ride on snow
                        SnowGroup {}
                        Repeater {
                            model: [{ index: 3, icon: 0xf032a, spin: -70 }, { index: 4, icon: 0xf0597, spin: 0 }, { index: 5, icon: 0xf024a, spin: 360 }]
                            Item {
                                required property var modelData
                                // never the child's "visible": that one includes this item's, and would latch to false
                                visible: Boolean(kind.entry)
                                width: kind.implicitWidth
                                height: kind.implicitHeight
                                Tile {
                                    id: kind
                                    entry: SnowHush.modeItems[parent.modelData.index] || null
                                    glyph: String.fromCodePoint(parent.modelData.icon)
                                    spin: parent.modelData.spin
                                }
                            }
                        }
                    }
                    // Mixed governs every kind: a plain settings row under them
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Boolean(SnowHush.mixed)
                        spacing: card.s(12)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: card.s(2)
                            Text {
                                text: card.label(SnowHush.mixed)
                                color: card.fg
                                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12); font.weight: Font.Bold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Let several kinds fall together")
                                color: card.softText
                                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                                wrapMode: Text.Wrap
                            }
                        }
                        ShellToggle {
                            name: card.label(SnowHush.mixed)
                            on: Boolean(SnowHush.mixed && SnowHush.mixed.checkState === Qt.Checked)
                            enabled: Boolean(SnowHush.mixed && SnowHush.mixed.enabled)
                            onFlipped: SnowHush.mixed.triggered()
                        }
                    }
                }

                Section {
                    order: 1
                    title: qsTr("Snowfall")
                    Gauge { entry: SnowHush.menuItems[0] || null }
                    Gauge { entry: SnowHush.menuItems[1] || null }
                }

                Section {
                    order: 2
                    title: card.label(SnowHush.menuItems[2]) || qsTr("Where it settles")
                    Checks { entry: SnowHush.menuItems[2] || null }
                    Pill {
                        visible: Boolean(card.clearEntry)
                        entry: card.clearEntry
                        prefix: "⌫  "
                    }
                }

                Section {
                    order: 3
                    title: card.label(card.groups[card.groups.length - 1]) || qsTr("Settings")
                    Toggles { entry: card.groups.length > 4 ? card.groups[card.groups.length - 1] : null }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.s(card.compact ? 20 : 30)
                    Layout.rightMargin: card.s(card.compact ? 20 : 30)
                    Layout.topMargin: card.s(6)
                    Layout.bottomMargin: card.s(16)
                    opacity: card.clamp((card.unfold - 0.5) / 0.4)
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Engine: Snowhush by Mykhailo Bezruchko")
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10)
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: Boolean(card.supportEntry)
                        text: card.label(card.supportEntry) + "  ↗"
                        color: supportArea.containsMouse ? card.fg : card.softText
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
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(9); font.weight: Font.Bold
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
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: card.fg; border.width: card.s(1.5) }
        Rectangle { anchors.fill: parent; anchors.margins: card.s(22); radius: width / 2; color: "transparent"; border.color: card.fg; border.width: card.s(1) }
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
                    color: card.fg
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(8.5); font.weight: Font.Bold
                    x: letters.width / 2 - width / 2
                    y: card.s(5)
                    transform: Rotation { origin.x: width / 2; origin.y: letters.height / 2 - card.s(5); angle: index * 360 / mark.ring.length }
                }
            }
        }
        SnowHushEmblem {
            anchors.centerIn: parent
            width: card.s(28); height: width
            kind: card.theme
            mono: true
            animate: card.motion && card.onScreen
            paper: card.fg; ink: card.ink
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
        // a new kind of weather rattles the globe while its emblem swaps
        Connections {
            target: card
            function onThemeChanged() { if (card.initialized) globeItem.shake(); }
        }
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
            // the emblem of what falls
            SnowHushEmblem {
                width: globeItem.d * 0.5; height: width
                x: globeItem.r - width / 2
                y: globeItem.d * 0.42 - height / 2
                opacity: 0.6 + 0.4 * card.reveal
                kind: card.theme
                animate: card.motion && card.onScreen
                live: card.snowing
                paper: card.paper; ink: card.ink; frost: card.frost
            }
            // flakes, drops, leaves or sparks swirling in the water
            Repeater {
                model: card.snowing ? 8 : 0
                Rectangle {
                    required property int index
                    property real a: index / 8 * Math.PI * 2
                    NumberAnimation on a { from: index / 8 * Math.PI * 2; to: index / 8 * Math.PI * 2 + Math.PI * 2; duration: 5000 + index * 600; loops: Animation.Infinite }
                    readonly property real orbit: globeItem.d * (0.24 + (index % 3) * 0.07)
                    readonly property bool rain: card.theme === "rain"
                    readonly property bool leafy: card.theme === "autumn" || card.theme === "blossom"
                    readonly property real size: card.s(2 + index % 2)
                    width: rain ? Math.max(1, card.s(1.2)) : leafy ? size * 2 : size
                    height: rain ? card.s(6) : leafy ? size * 1.2 : size
                    radius: Math.min(width, height) / 2
                    rotation: rain ? 12 : leafy ? a * 180 / Math.PI * 2 : 0
                    x: globeItem.r + Math.cos(a) * orbit - width / 2
                    y: globeItem.d * 0.42 + Math.sin(a) * orbit * 0.7 - height / 2
                    color: card.theme === "snow" || rain || index % 2 === 0 ? card.paper : card.theme === "halloween" ? card.teal : card.frost
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

    // A section of the options on its own panel; it slides in after the ones before it.
    component Section: Item {
        id: section
        property int order: 0
        property string title
        default property alias content: body.data
        readonly property real pad: card.s(card.compact ? 14 : 18)
        readonly property real shown: card.clamp((card.unfold - order * 0.13) / 0.45)
        Layout.fillWidth: true
        Layout.leftMargin: card.s(card.compact ? 10 : 14)
        Layout.rightMargin: card.s(card.compact ? 10 : 14)
        implicitHeight: body.implicitHeight + pad * 2
        opacity: shown
        transform: Translate { y: (1 - section.shown) * card.s(14) }

        Rectangle { anchors.fill: parent; radius: card.corner + card.s(4); color: card.well }
        ColumnLayout {
            id: body
            x: section.pad; y: section.pad
            width: parent.width - 2 * x
            spacing: card.s(12)
            Text {
                Layout.fillWidth: true
                text: section.title
                color: card.fg
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(14); font.weight: Font.Bold
                elide: Text.ElideRight
            }
        }
    }

    // The accent of a chosen button: it floods out from the point pressed and drains back into it.
    component Plate: Item {
        id: plate
        property bool on: false
        property real radius: card.corner
        property real pressX: width / 2
        property real pressY: height / 2
        property real level: on ? 1 : 0
        readonly property bool flooding: level > 0.001 && level < 0.999
        readonly property real reach: Math.hypot(Math.max(pressX, width - pressX), Math.max(pressY, height - pressY))
        Behavior on level {
            enabled: card.initialized && card.onScreen && card.motion
            NumberAnimation { duration: plate.on ? 460 : 300; easing.type: Easing.InOutCubic }
        }
        Rectangle { anchors.fill: parent; radius: plate.radius; color: card.teal; visible: plate.level >= 0.999 }
        Loader {
            anchors.fill: parent
            active: plate.flooding
            sourceComponent: Item {
                Rectangle { id: shape; anchors.fill: parent; radius: plate.radius; visible: false; layer.enabled: true }
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: shape; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                    Rectangle {
                        width: plate.reach * plate.level * 2; height: width; radius: width / 2
                        x: plate.pressX - width / 2; y: plate.pressY - height / 2
                        color: card.teal
                    }
                }
            }
        }
    }

    // A weather kind: a square button with its icon over its name. Picked, the accent floods it and the icon leaps.
    component Tile: AbstractButton {
        id: tile
        property var entry: null
        property string glyph
        property real spin: 0       // how far the icon turns as it lands
        readonly property bool on: Boolean(entry && entry.checkState === Qt.Checked)
        property real hop: 0
        property real turn: 0
        property real pop: 1
        property real zoom: pressed ? 0.93 : hovered || visualFocus ? 1.04 : 1
        Behavior on zoom { enabled: card.motion; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        visible: Boolean(entry)
        enabled: Boolean(entry && entry.enabled)
        padding: 0
        implicitWidth: card.s(card.compact ? 92 : 108)
        implicitHeight: card.s(card.compact ? 70 : 78)
        Accessible.role: Accessible.RadioButton
        Accessible.name: card.label(entry)
        Accessible.checked: on
        onPressedChanged: if (pressed) { plate.pressX = visualFocus ? width / 2 : pressX; plate.pressY = visualFocus ? height / 2 : pressY; }
        onClicked: if (entry && entry.enabled) entry.triggered()
        onOnChanged: if (on && card.initialized && card.onScreen && card.motion) cheer.restart()
        HoverHandler { cursorShape: tile.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        ParallelAnimation {
            id: cheer
            SequentialAnimation {
                NumberAnimation { target: tile; property: "hop"; to: -card.s(12); duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: tile; property: "hop"; to: 0; duration: 480; easing.type: Easing.OutBounce }
            }
            NumberAnimation { target: tile; property: "turn"; from: -tile.spin; to: 0; duration: 680; easing.type: Easing.OutBack }
            SequentialAnimation {
                NumberAnimation { target: tile; property: "pop"; to: 1.35; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: tile; property: "pop"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
            }
        }
        background: Item {
            scale: tile.zoom
            Rectangle {
                anchors.fill: parent
                radius: card.corner
                color: tile.hovered || tile.visualFocus ? card.hover : card.surface
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 150 } }
            }
            Plate { id: plate; anchors.fill: parent; on: tile.on }
        }
        contentItem: Item {
            scale: tile.zoom
            opacity: tile.enabled ? 1 : 0.45
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12 + tile.hop + (tile.hovered ? -card.s(2) : 0)
                Behavior on y { enabled: card.motion && !cheer.running; NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                rotation: tile.turn
                scale: tile.pop
                text: tile.glyph
                color: tile.on ? card.ink : card.teal
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 280 } }
                font.family: ThemeBackend.iconFont; font.pixelSize: card.s(card.compact ? 26 : 30)
            }
            Text {
                anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.12
                x: card.s(3); width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: card.label(tile.entry)
                color: tile.on ? card.ink : card.fg
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 280 } }
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.weight: Font.Bold
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: card.s(8)
                elide: Text.ElideRight
            }
        }
    }

    // The Snow button and its two variants. Folded, they are small seals docked in its corner; when Snow falls they
    // roll out one after the other into two stacked buttons beside it; they are drawn back in the reverse order.
    component SnowGroup: Item {
        id: group
        readonly property bool open: card.snowPicked
        property real room: 0       // width taken beside the button
        property real first: 0      // each variant's way from its dock (0) to its place (1)
        property real second: 0
        readonly property real gap: card.s(6)
        readonly property real pillWidth: Math.ceil(Math.max(halloweenSeal.fullWidth, newYearSeal.fullWidth))
        width: snowTile.width + room * (pillWidth + gap)
        height: snowTile.implicitHeight

        states: State {
            name: "open"
            when: group.open
            PropertyChanges { target: group; room: 1; first: 1; second: 1 }
        }
        transitions: [
            Transition {
                to: "open"
                enabled: card.initialized && card.onScreen && card.motion
                ParallelAnimation {
                    NumberAnimation { target: group; property: "room"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: group; property: "first"; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    SequentialAnimation {
                        PauseAnimation { duration: 80 }
                        NumberAnimation { target: group; property: "second"; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    }
                    // the tile squeezes as it lets them go
                    SequentialAnimation {
                        NumberAnimation { target: snowTile; property: "scale"; to: 0.93; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: snowTile; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                    }
                }
            },
            Transition {
                from: "open"
                enabled: card.initialized && card.onScreen && card.motion
                ParallelAnimation {
                    NumberAnimation { target: group; property: "second"; duration: 300; easing.type: Easing.InOutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 70 }
                        NumberAnimation { target: group; property: "first"; duration: 300; easing.type: Easing.InOutCubic }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 90 }
                        NumberAnimation { target: group; property: "room"; duration: 360; easing.type: Easing.InOutCubic }
                    }
                    // and swells as it takes them back
                    SequentialAnimation {
                        PauseAnimation { duration: 300 }
                        NumberAnimation { target: snowTile; property: "scale"; to: 1.07; duration: 100; easing.type: Easing.OutQuad }
                        NumberAnimation { target: snowTile; property: "scale"; to: 1; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                    }
                }
            }
        ]

        Tile {
            id: snowTile
            spin: 180
            entry: SnowHush.snow; glyph: String.fromCodePoint(0xf0717)
            // pressed again while Snow falls: drop the variants and leave plain snow
            onClicked: if (on) [SnowHush.halloween, SnowHush.newYear].forEach(e => {
                if (e && e.enabled && e.checkState === Qt.Checked) e.triggered();
            })
        }
        Variant { id: halloweenSeal; tray: group; slot: 0; t: group.first; tile: snowTile; entry: SnowHush.halloween; glyph: String.fromCodePoint(0xf0ba3) }
        Variant { id: newYearSeal; tray: group; slot: 1; t: group.second; tile: snowTile; entry: SnowHush.newYear; glyph: String.fromCodePoint(0xf0405); fallbackMode: "new-year" }
    }

    // One snow variant, morphing from a seal into a button. Folded it is inert, so a press reaches the tile underneath.
    component Variant: AbstractButton {
        id: variant
        property var tray: null
        property Item tile: null
        property var entry: null
        property string glyph
        property string fallbackMode: ""
        property int slot: 0
        property real t: 0
        readonly property real k: card.clamp(t)
        readonly property bool on: Boolean(entry && entry.checkState === Qt.Checked)
        readonly property real seal: card.s(20)
        readonly property real pillHeight: (tile.height - tray.gap) / 2
        readonly property real fullWidth: card.s(12 + 18 + 8 + 12) + caption.implicitWidth
        readonly property real dockX: tile.x + tile.width - seal - card.s(5)
        readonly property real dockY: tile.y + card.s(5) + slot * (seal + card.s(3))
        readonly property real openX: tile.x + tile.width + tray.gap
        readonly property real openY: tile.y + slot * (pillHeight + tray.gap)
        readonly property real lead: tray ? (tray.pillWidth - fullWidth) / 2 + card.s(12) : card.s(12)
        property real zoom: pressed ? 0.93 : hovered || visualFocus ? 1.04 : 1
        property real turn: 0
        Behavior on zoom { enabled: card.motion; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        onPressedChanged: if (pressed) { plate.pressX = visualFocus ? width / 2 : pressX; plate.pressY = visualFocus ? height / 2 : pressY; }
        onOnChanged: if (on && card.initialized && card.onScreen && card.motion) twirl.restart()
        NumberAnimation { id: twirl; target: variant; property: "turn"; from: -360; to: 0; duration: 620; easing.type: Easing.OutBack }
        x: dockX + (openX - dockX) * t
        y: dockY + (openY - dockY) * t
        width: seal + ((tray ? tray.pillWidth : fullWidth) - seal) * k
        height: seal + (pillHeight - seal) * k
        padding: 0
        visible: Boolean(entry)
        enabled: Boolean(tray && tray.open && entry && (entry.enabled || fallbackMode))
        opacity: tray && tray.open && !enabled ? 0.45 : 0.8 + 0.2 * k
        text: card.label(entry)
        Accessible.ignored: !(tray && tray.open)
        Accessible.role: Accessible.CheckBox
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: on
        onClicked: {
            if (entry && entry.enabled) entry.triggered();
            else if (entry && fallbackMode) SnowHush.selectMode(fallbackMode);
        }
        HoverHandler { cursorShape: variant.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Item {
            scale: variant.zoom
            Rectangle {
                id: variantBase
                anchors.fill: parent
                radius: variant.height / 2 * (1 - variant.k) + Math.min(card.corner, variant.height / 2) * variant.k
                // a shade above the tile while docked on it
                color: Qt.tint(variant.hovered || variant.visualFocus ? card.hover : card.surface, Qt.alpha(card.fg, 0.12 * (1 - variant.k)))
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 150 } }
            }
            Plate { id: plate; anchors.fill: parent; radius: variantBase.radius; on: variant.on }
        }
        contentItem: Item {
            Text {
                // centred in the seal, then rolling to the head of the button
                x: (variant.seal - width) / 2 * (1 - variant.k) + (variant.lead + (card.s(18) - width) / 2) * variant.k
                scale: variant.zoom
                anchors.verticalCenter: parent.verticalCenter
                rotation: (variant.k - 1) * 360 + variant.turn
                text: variant.glyph
                color: variant.on ? card.ink : card.teal
                font.family: ThemeBackend.iconFont; font.pixelSize: card.s(13 + 5 * variant.k)
            }
            Text {
                id: caption
                x: variant.lead + card.s(18 + 8) - (1 - variant.k) * card.s(10)
                anchors.verticalCenter: parent.verticalCenter
                opacity: card.clamp((variant.k - 0.6) / 0.4)
                visible: opacity > 0
                text: variant.text
                color: variant.on ? card.ink : card.fg
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12); font.weight: Font.Bold
            }
        }
    }

    // A radio submenu as a staircase of bars. A new pick pours into the bars one after the other (or drains them)
    // and the marker under the labels stretches across to it.
    component Gauge: RowLayout {
        id: gauge
        property var entry: null
        readonly property var listed: (opener.children.values || []).filter(item => !item.isSeparator && item.text)
        // Read as numbers ("Off" is 0); a menu listed high to low (opacity) is shown low to high, so the gauge fills up.
        readonly property bool descending: listed.length > 1 && (parseInt(card.label(listed[0])) || 0) > (parseInt(card.label(listed[listed.length - 1])) || 0)
        readonly property var steps: descending ? listed.slice().reverse() : listed
        readonly property int chosen: steps.findIndex(item => item.checkState === Qt.Checked)
        // The engine republishes its menu after a pick: the bars keep their count and the last confirmed choice
        // through the gap, so they animate instead of being rebuilt.
        property int count: 0
        property int shown: -1
        property int from: -1
        property int pointed: -1
        property bool rising: false
        function sync(): void {
            if (steps.length) count = steps.length;
            if (chosen < 0 || chosen === shown) return;
            from = shown;
            rising = chosen > shown;
            shown = chosen;
        }
        onStepsChanged: sync()
        onChosenChanged: sync()
        Component.onCompleted: sync()
        Layout.fillWidth: true
        visible: Boolean(entry) && count > 0
        spacing: card.s(14)
        QsMenuOpener { id: opener; menu: gauge.entry }

        Text {
            Layout.preferredWidth: card.s(card.compact ? 74 : 96)
            text: card.label(gauge.entry)
            color: card.softText
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
            elide: Text.ElideRight
        }
        Item {
            id: stairs
            Layout.fillWidth: true
            implicitHeight: card.s(62)
            readonly property real gap: card.s(4)
            readonly property real stepWidth: (width - gap * (gauge.count - 1)) / Math.max(1, gauge.count)
            readonly property real barArea: card.s(36)
            function peak(index: int): real { return card.s(12) + (barArea - card.s(12)) * (index + 1) / Math.max(1, gauge.count); }

            // the marker: its two edges travel at different speeds, as the shell's switch does
            Rectangle {
                id: marker
                readonly property real target: Math.max(0, gauge.shown) * (stairs.stepWidth + stairs.gap)
                property real near: target
                property real far: target + stairs.stepWidth
                Behavior on near { enabled: card.initialized && card.motion; NumberAnimation { duration: gauge.rising ? 400 : 200; easing.type: Easing.OutExpo } }
                Behavior on far { enabled: card.initialized && card.motion; NumberAnimation { duration: gauge.rising ? 200 : 400; easing.type: Easing.OutExpo } }
                visible: gauge.shown >= 0
                x: near; y: stairs.barArea + card.s(6)
                width: Math.max(0, far - near); height: card.s(20)
                radius: Math.min(card.corner, height / 2)
                color: card.teal
            }

            Repeater {
                model: gauge.count
                AbstractButton {
                    id: step
                    required property int index
                    readonly property var option: gauge.steps[index] || null
                    readonly property bool filled: index <= gauge.shown
                    readonly property bool ghosted: gauge.pointed >= 0 && index <= gauge.pointed
                    // the pour runs outward from where the choice was
                    readonly property int wait: Math.max(0, filled ? index - gauge.from - 1 : gauge.from - index) * 55
                    property real level: filled ? 1 : 0
                    Behavior on level {
                        enabled: card.initialized && card.onScreen && card.motion
                        SequentialAnimation {
                            PauseAnimation { duration: step.wait }
                            NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }
                    }
                    x: index * (stairs.stepWidth + stairs.gap)
                    width: stairs.stepWidth
                    height: stairs.height
                    padding: 0
                    enabled: Boolean(option && option.enabled)
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: card.label(gauge.entry) + " " + card.label(option)
                    Accessible.checked: index === gauge.shown
                    onClicked: if (option) option.triggered()
                    readonly property bool aimed: hovered || visualFocus
                    onAimedChanged: {
                        if (aimed) gauge.pointed = index;
                        else if (gauge.pointed === index) gauge.pointed = -1;
                    }
                    HoverHandler { cursorShape: step.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    background: Item {}
                    contentItem: Item {
                        Item {
                            width: parent.width; height: stairs.peak(step.index)
                            y: stairs.barArea - height
                            transform: Scale {
                                origin.y: stairs.peak(step.index)
                                yScale: step.pressed ? 0.78 : step.aimed ? 1.14 : 1
                                Behavior on yScale { enabled: card.motion; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                            }
                            Rectangle { anchors.fill: parent; radius: card.s(5); color: card.surface }
                            // a preview of the pour up to the bar pointed at
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: step.ghosted ? parent.height : 0
                                radius: Math.min(card.s(5), height / 2)
                                color: Qt.alpha(card.teal, 0.32)
                                Behavior on height { enabled: card.motion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: Math.max(0, parent.height * step.level)
                                radius: Math.min(card.s(5), height / 2)
                                // opacity reads as opacity: its bars thicken from faint to solid
                                color: Qt.alpha(card.teal, gauge.descending ? 0.4 + 0.6 * (step.index + 1) / gauge.count : 1)
                            }
                        }
                        Text {
                            y: stairs.barArea + card.s(6)
                            width: parent.width; height: card.s(20)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: card.label(step.option)
                            color: step.index === gauge.shown ? card.ink : step.aimed ? card.fg : card.softText
                            Behavior on color { enabled: card.motion; ColorAnimation { duration: 220 } }
                            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10)
                            font.weight: step.index === gauge.shown ? Font.Bold : Font.Normal
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
                    color: card.softText
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

    // The shell's toggle in the weather's colours. It flips itself on a press, so the engine's state is bound back:
    // the handle only stays moved once the engine confirms.
    component ShellToggle: Toggle {
        id: shellToggle
        property bool on: false
        property string name
        signal flipped()
        horizontalPadding: 0
        checked: on
        accentColor: card.teal
        baseColor: ThemeBackend.surface1
        handleColor: card.ink
        handleOffColor: ThemeBackend.text
        action_highlight: activeFocus
        Accessible.role: Accessible.CheckBox
        Accessible.name: name
        Accessible.checkable: true
        Accessible.checked: on
        Accessible.onPressAction: flipped()
        onToggled: {
            shellToggle.flipped();
            shellToggle.checked = Qt.binding(() => shellToggle.on);
        }
    }

    component SwitchRow: RowLayout {
        id: row
        property string text
        property bool on: false
        signal flipped()
        implicitHeight: card.s(34)
        spacing: card.s(10)
        Text {
            Layout.fillWidth: true
            text: row.text
            color: card.fg
            opacity: row.enabled ? 1 : 0.45
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
            elide: Text.ElideRight
        }
        ShellToggle { name: row.text; on: row.on; onFlipped: row.flipped() }
    }

    // The shell's button; given a menu entry it mirrors and triggers it, checkmark entries show their state.
    component Pill: ClickButton {
        id: pill
        property var entry: null
        property string text: entry ? card.label(entry) : ""
        property string prefix: ""
        readonly property bool isCheck: Boolean(entry && entry.buttonType !== QsMenuButtonType.None)
        readonly property bool on: Boolean(entry && entry.checkState === Qt.Checked)
        visible: entry === null ? text !== "" : Boolean(entry)
        enabled: entry === null || Boolean(entry && entry.enabled)
        opacity: enabled ? 1 : 0.45
        buttonText: prefix + text
        accentColor: on ? card.teal : card.surface
        textColor: on ? card.ink : card.fg
        cornerRadius: card.corner
        implicitHeight: card.s(32)
        horizontalPadding: card.s(14)
        textFontSize: card.s(12)
        action_highlight: activeFocus
        Accessible.role: isCheck ? Accessible.CheckBox : Accessible.Button
        Accessible.name: text
        Accessible.checkable: isCheck
        Accessible.checked: on
        Accessible.onPressAction: clicked()
        onClicked: if (entry && entry.enabled) entry.triggered()
    }
}
