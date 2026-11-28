import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import "../"
import "../reusables"

// The Christmas banner. A string of lights runs across its top, a glass bauble is the switch, and the last door of
// an Advent calendar swings open on Viggo Johansen's "Glade jul" (1891) when the lights come on. Once on, the
// light styles and the shell areas it decorates unfold below.
Item {
    id: card

    required property var rootObj
    property real highlight: 0
    readonly property bool active: Christmas.enabled
    readonly property bool compact: width < s(695)
    readonly property bool motion: !Config.getSetting("general.performance", false)
    readonly property bool onScreen: visible && width > 0 && Window.window !== null && Window.window.visible
    readonly property bool lively: active && motion && onScreen

    readonly property color fg: ThemeBackend.text
    readonly property color softText: ThemeBackend.subtext0
    readonly property color surface: ThemeBackend.surface0
    readonly property color hover: ThemeBackend.surface1
    readonly property color well: ThemeBackend.mantle
    readonly property real corner: s(ThemeBackend.clampedBorderRadius)
    readonly property color gold: Christmas.gold
    readonly property color ink: "#2a1b0b"
    readonly property color berry: Christmas.cranberry

    property real reveal: active ? 1 : 0
    property real door: active ? 1 : 0
    property real unfold: 0
    property bool initialized: false

    function s(value: real): real { return card.rootObj.s(value); }
    function clamp(value: real): real { return Math.max(0, Math.min(1, value)); }
    function toggle(): void {
        bauble.swing();
        Config.setSetting("addonsV2Christmas", !card.active);
    }

    Layout.fillWidth: true
    implicitHeight: hero.height + options.height
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: cardMask }

    FontLoader { id: titleFace; source: "BerkshireSwash-Regular.ttf" }

    Component.onCompleted: { initialized = true; if (active) unfold = 1; syncClock(); }
    onActiveChanged: {
        if (!active) { unfoldIn.stop(); unfold = 0; }
        else if (initialized && motion && onScreen) unfoldIn.restart();
        else unfold = 1;
    }
    Behavior on reveal {
        enabled: card.initialized && card.onScreen && card.motion
        NumberAnimation { duration: card.active ? 700 : 380; easing.type: Easing.OutCubic }
    }
    // the door opens after the first bulbs are lit, and shuts at once
    Behavior on door {
        enabled: card.initialized && card.onScreen && card.motion
        SequentialAnimation {
            PauseAnimation { duration: card.active ? 420 : 0 }
            NumberAnimation { duration: card.active ? 1100 : 460; easing.type: card.active ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.9 }
        }
    }
    SequentialAnimation {
        id: unfoldIn
        PauseAnimation { duration: 260 }
        NumberAnimation { target: card; property: "unfold"; from: 0; to: 1; duration: 950; easing.type: Easing.OutCubic }
    }

    // the candles in the painting flicker on the lights' clock
    property bool clocked: lively
    property bool registered: false
    onClockedChanged: syncClock()
    function syncClock(): void { if (clocked !== registered) { registered = clocked; Christmas.requestClock(clocked); } }
    Component.onDestruction: if (registered) Christmas.requestClock(false)

    Rectangle { id: cardMask; anchors.fill: parent; radius: card.s(20); visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; color: Qt.tint(ThemeBackend.base, Qt.alpha(Christmas.pine, 0.1 + 0.1 * card.reveal)) }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: card.s(20)
        border.width: card.s(2)
        border.color: Qt.alpha(ThemeBackend.mauve, card.highlight * 0.6)
        visible: card.highlight > 0.01
    }

    // ── Hero ─────────────────────────────────────────────────────────────────
    Item {
        id: hero
        width: parent.width
        height: Math.max(card.s(card.compact ? 250 : 262), intro.y + intro.implicitHeight + card.s(18))
        clip: true

        // warm light from the window, growing with the lights
        Glow {
            x: frame.x + frame.width / 2 - width / 2; y: frame.y + frame.height / 2 - height / 2
            width: frame.width * 2.6; height: frame.height * 1.9
            tint: card.gold; strength: 0.22
            opacity: card.reveal
        }

        AdventWindow {
            id: frame
            height: card.s(card.compact ? 178 : 196)
            width: Math.round(height * 0.78)
            x: hero.width - width - card.s(card.compact ? 26 : 46)
            y: card.s(card.compact ? 44 : 42)
            rotation: 2.5
        }

        // the string of lights across the top, dark until the bauble is pressed; it lights from above the bauble
        ChristmasLights {
            id: garland
            x: -card.s(12)
            width: hero.width + card.s(24)
            height: card.s(70)
            y: -card.s(2)
            on: card.active
            keepDark: true
            spacing: card.s(card.compact ? 34 : 38)
            swag: spacing * 3
            sag: card.s(12)
            wireY: card.s(4)
            bulb: card.s(4.6)
            glow: 0.7
            seed: 3
            cascade: 1300
            origin: (intro.x + bauble.x + bauble.width / 2 + card.s(12)) / width
        }

        ColumnLayout {
            id: intro
            x: card.s(card.compact ? 22 : 34)
            y: card.s(card.compact ? 44 : 46)
            width: frame.x - x - card.s(card.compact ? 18 : 54)
            spacing: card.s(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(8)
                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: card.s(card.compact ? 48 : 58)
                    text: "Christmas"
                    color: card.fg
                    font.family: titleFace.status === FontLoader.Ready ? titleFace.font.family : ThemeBackend.fontFamily
                    font.pixelSize: card.s(card.compact ? 38 : 48)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: card.s(24)
                    verticalAlignment: Text.AlignVCenter
                    Accessible.name: "Christmas"
                    // a star over the last letter, lit with the rest
                    Text {
                        x: Math.min(parent.width, parent.contentWidth) - width * 0.35
                        y: parent.height * 0.5 - parent.contentHeight * 0.5 - height * 0.15
                        text: "✶"
                        color: Qt.tint(card.softText, Qt.alpha(card.gold, card.reveal))
                        font.pixelSize: card.s(card.compact ? 16 : 20)
                        scale: 1 + 0.12 * card.reveal * Math.sin(Christmas.phase * 1.7)
                        rotation: card.reveal * 20
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Christmas.countdown()
                color: Qt.tint(card.softText, Qt.alpha(card.gold, card.reveal))
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(13); font.weight: Font.DemiBold
                font.letterSpacing: card.s(0.4)
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: card.active ? qsTr("Lights on the bar, gift-wrapped panels, frosted settings and a sparkle on every button.")
                                  : qsTr("Fairy lights, ribbons and holly across the whole shell. No snow, just warmth.")
                color: card.softText
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12)
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }

            // the switch: a glass bauble on a ribbon, with its call to action beside it
            RowLayout {
                Layout.topMargin: card.s(card.compact ? 10 : 14)
                spacing: card.s(16)
                Bauble { id: bauble }
                ColumnLayout {
                    spacing: card.s(2)
                    Layout.maximumWidth: intro.width - bauble.width - card.s(16)
                    Text {
                        text: card.active ? qsTr("The lights are on") : qsTr("Light up the shell")
                        color: card.fg
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(card.compact ? 15 : 17); font.weight: Font.Bold
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.toggle() }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.active ? qsTr("Press the bauble to put them out") : qsTr("Press the bauble to switch the lights on")
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // ── Options ──────────────────────────────────────────────────────────────
    Item {
        id: options
        anchors.top: hero.bottom
        width: parent.width
        height: card.active && settings.item ? settings.item.implicitHeight : 0
        clip: true
        enabled: card.active
        Behavior on height {
            enabled: card.initialized && card.onScreen && card.motion
            NumberAnimation { duration: card.active ? 560 : 320; easing.type: Easing.OutCubic }
        }

        Loader {
            id: settings
            width: parent.width
            active: card.active || options.height > 0
            sourceComponent: ColumnLayout {
                width: settings.width
                spacing: card.s(10)

                Section {
                    order: 0
                    title: qsTr("Lights")
                    hint: qsTr("The bulbs on the bar, the windows and this banner")
                    Flow {
                        Layout.fillWidth: true
                        spacing: card.s(8)
                        Repeater {
                            model: [
                                { key: "classic", name: qsTr("Classic") },
                                { key: "warm", name: qsTr("Warm white") },
                                { key: "candy", name: qsTr("Candy cane") },
                                { key: "nordic", name: qsTr("Nordic") }
                            ]
                            LightTile {
                                required property var modelData
                                required property int index
                                key: modelData.key; name: modelData.name; styleIndex: index
                            }
                        }
                    }
                    SwitchRow {
                        Layout.fillWidth: true
                        text: qsTr("Twinkle")
                        detail: qsTr("Bulbs breathe and now and then one sparkles; off keeps them steady")
                        on: Christmas.twinkle
                        onFlipped: Config.setSetting("addonsV2ChristmasTwinkle", !Christmas.twinkle)
                    }
                }

                Section {
                    order: 1
                    title: qsTr("Decorations")
                    hint: qsTr("Where Christmas shows in the shell")
                    SwitchRow {
                        Layout.fillWidth: true
                        text: qsTr("Frosted settings")
                        detail: qsTr("Frost appears on small settings when hovered")
                        on: Christmas.area("settings")
                        onFlipped: Christmas.setArea("settings", !Christmas.area("settings"))
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: card.compact ? 1 : 2
                        columnSpacing: card.s(18)
                        rowSpacing: card.s(6)
                        Repeater {
                            model: [
                                { key: "bar", name: qsTr("Bar garland"), detail: qsTr("Fairy lights hang in every bar section") },
                                { key: "panels", name: qsTr("Gift-wrapped panels"), detail: qsTr("Panels open like presents, with holly on a corner") },
                                { key: "buttons", name: qsTr("Sparkling buttons"), detail: qsTr("A glint on hover, gold stars on a press") },
                                { key: "windows", name: qsTr("Lit windows"), detail: qsTr("Lights run around a window as it takes the focus") },
                                { key: "notifications", name: qsTr("Wrapped notifications"), detail: qsTr("A satin sash and a bow on each one") }
                            ]
                            SwitchRow {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: modelData.name
                                detail: modelData.detail
                                on: Christmas.area(modelData.key)
                                onFlipped: Christmas.setArea(modelData.key, !Christmas.area(modelData.key))
                            }
                        }
                    }
                    OpacityRow { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.s(card.compact ? 20 : 30)
                    Layout.rightMargin: card.s(card.compact ? 20 : 30)
                    Layout.topMargin: card.s(4)
                    Layout.bottomMargin: card.s(16)
                    spacing: card.s(12)
                    opacity: card.clamp((card.unfold - 0.5) / 0.4)
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Painting: Viggo Johansen, Glade jul (1891), public domain  ·  Title set in Berkshire Swash")
                        color: card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10)
                        elide: Text.ElideRight
                    }
                    Text {
                        text: qsTr("Replay the lights") + "  ↺"
                        color: replayArea.containsMouse ? card.fg : card.softText
                        font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.underline: replayArea.containsMouse
                        MouseArea {
                            id: replayArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { Christmas.introSerial++; Christmas.lightsOnSerial++; garland.relight(); }
                        }
                    }
                }
            }
        }
    }

    // ── Components ───────────────────────────────────────────────────────────

    // A soft round light that fades to nothing at its edge.
    component Glow: Shape {
        id: glow
        property color tint: card.gold
        property real strength: 0.2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: glow.width / 2; centerY: glow.height / 2; focalX: centerX; focalY: centerY
                centerRadius: Math.max(glow.width, glow.height) / 2
                GradientStop { position: 0; color: Qt.alpha(glow.tint, glow.strength) }
                GradientStop { position: 0.45; color: Qt.alpha(glow.tint, glow.strength * 0.4) }
                GradientStop { position: 1; color: Qt.alpha(glow.tint, 0) }
            }
            PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height; radius: Math.min(glow.width, glow.height) / 2 }
        }
    }

    // The last door of an Advent calendar, hinged on its left, over the painting.
    component AdventWindow: Item {
        id: win
        // the painting, its candles breathing a little while the lights are on
        Rectangle {
            id: mount
            anchors.fill: parent
            radius: card.s(6)
            color: "#120d08"
            border.width: card.s(3)
            border.color: Qt.tint("#6b5a3e", Qt.alpha(card.gold, card.reveal * 0.8))
            Image {
                id: painting
                anchors.fill: parent
                anchors.margins: card.s(7)
                source: "glade-jul.jpg"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                mipmap: true
                sourceSize.width: width * 2
                layer.enabled: true
                layer.effect: MultiEffect {
                    brightness: (card.reveal - 1) * 0.25 + card.reveal * (0.07 + 0.035 * Math.sin(Christmas.phase * 6.3) * Math.sin(Christmas.phase * 2.1))
                    contrast: 0.12 * card.reveal
                    saturation: (card.reveal - 1) * 0.6 + 0.1 * card.reveal
                }
            }
            // a gilt bead inside the frame
            Rectangle {
                anchors.fill: painting
                anchors.margins: -card.s(2)
                color: "transparent"
                radius: card.s(3)
                border.width: card.s(1)
                border.color: Qt.alpha(card.gold, 0.35 + 0.4 * card.reveal)
            }
        }
        // the door itself
        Item {
            id: hinge
            anchors.fill: parent
            anchors.margins: card.s(5)
            readonly property real angle: -108 * card.door
            readonly property bool front: angle > -90
            visible: card.door < 0.999
            transform: Rotation {
                origin.x: 0; origin.y: hinge.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: hinge.angle
            }
            // front: printed card with the number
            Rectangle {
                anchors.fill: parent
                visible: hinge.front
                radius: card.s(4)
                gradient: Gradient {
                    GradientStop { position: 0; color: "#f4ead3" }
                    GradientStop { position: 1; color: "#e6d5b3" }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: card.s(6)
                    radius: card.s(3)
                    color: "transparent"
                    border.width: card.s(1.5); border.color: Qt.alpha(Christmas.deepRed, 0.6)
                    Rectangle {
                        anchors.fill: parent; anchors.margins: card.s(3)
                        radius: card.s(2)
                        color: "transparent"
                        border.width: card.s(1); border.color: Qt.alpha("#a7832f", 0.6)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -card.s(6)
                    text: "24"
                    color: Christmas.deepRed
                    font.family: titleFace.status === FontLoader.Ready ? titleFace.font.family : ThemeBackend.fontFamily
                    font.pixelSize: parent.height * 0.36
                }
                ChristmasHolly {
                    width: parent.width * 0.42; height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: card.s(10)
                    rotation: 90
                }
                // the tab to pull it open
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right; anchors.rightMargin: card.s(5)
                    width: card.s(5); height: card.s(22); radius: width / 2
                    color: Qt.alpha(Christmas.deepRed, 0.5)
                }
                // a shadow falls on the card as the door turns away from the light
                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    color: "#000000"
                    opacity: card.door * 0.45
                }
            }
            // back: plain board
            Rectangle {
                anchors.fill: parent
                visible: !hinge.front
                radius: card.s(4)
                color: "#b49c74"
                Rectangle { anchors.fill: parent; radius: parent.radius; color: "#000000"; opacity: 0.25 }
            }
        }
        // a museum label
        Text {
            anchors.top: parent.bottom; anchors.topMargin: card.s(6)
            anchors.right: parent.right
            text: "Viggo Johansen · Glade jul, 1891"
            color: card.softText
            opacity: 0.55 + 0.4 * card.reveal
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(9); font.italic: true
        }
    }

    // The switch: a glass bauble hanging from a bow. It swings on every press; lit, it glows and mirrors the lights.
    component Bauble: Item {
        id: ball
        readonly property real d: card.s(card.compact ? 58 : 66)
        implicitWidth: d * 1.25
        implicitHeight: d * 1.55
        property real sway: 0
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Christmas lights")
        Accessible.checkable: true
        Accessible.checked: card.active
        Accessible.onPressAction: card.toggle()
        Keys.onSpacePressed: card.toggle()
        Keys.onReturnPressed: card.toggle()
        Keys.onEnterPressed: card.toggle()

        function swing(): void { if (card.motion && card.onScreen) swinging.restart(); }
        SequentialAnimation {
            id: swinging
            NumberAnimation { target: ball; property: "sway"; to: 18; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: ball; property: "sway"; to: -12; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { target: ball; property: "sway"; to: 7; duration: 300; easing.type: Easing.InOutSine }
            NumberAnimation { target: ball; property: "sway"; to: -3; duration: 270; easing.type: Easing.InOutSine }
            NumberAnimation { target: ball; property: "sway"; to: 0; duration: 260; easing.type: Easing.OutSine }
        }

        Item {
            id: pendulum
            width: ball.width; height: ball.height
            transformOrigin: Item.Top
            rotation: ball.sway
            scale: area.pressed ? 0.95 : area.containsMouse ? 1.03 : 1
            Behavior on scale { enabled: card.motion; NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            // ribbon from the bow down to the cap
            Rectangle {
                x: ball.width / 2 - width / 2; y: card.s(8)
                width: card.s(3); height: ball.d * 0.36
                color: Qt.tint("#6d5b5d", Qt.alpha(card.berry, card.reveal))
            }
            ChristmasBow {
                width: card.s(30); height: card.s(24)
                x: ball.width / 2 - width / 2; y: 0
                ribbon: Qt.tint("#7a6a6c", Qt.alpha(Christmas.cranberry, card.reveal))
                shade: Qt.tint("#463a3c", Qt.alpha(Christmas.deepRed, card.reveal))
                shine: Qt.tint("#a3999a", Qt.alpha(Qt.lighter(Christmas.cranberry, 1.35), card.reveal))
                piping: Qt.tint("#8a8072", Qt.alpha(card.gold, card.reveal))
            }
            // halo while lit
            Glow {
                x: globe.x + globe.width / 2 - width / 2; y: globe.y + globe.height / 2 - height / 2
                width: ball.d * 1.9; height: width
                tint: Qt.lighter(Christmas.cranberry, 1.3); strength: 0.34 + (area.containsMouse ? 0.12 : 0)
                opacity: card.reveal
            }
            // the cap
            Rectangle {
                x: ball.width / 2 - width / 2; y: ball.d * 0.4
                width: ball.d * 0.26; height: ball.d * 0.15; radius: card.s(2)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#7c6a43" }
                    GradientStop { position: 0.45; color: Qt.tint("#cfc6b1", Qt.alpha("#ffe9b0", card.reveal)) }
                    GradientStop { position: 1; color: "#6a5a38" }
                }
            }
            // the glass
            Item {
                id: globe
                x: (ball.width - ball.d) / 2; y: ball.d * 0.5
                width: ball.d; height: ball.d
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.tint("#7a8285", Qt.alpha("#ef5a6c", card.reveal)) }
                        GradientStop { position: 0.55; color: Qt.tint("#3c4346", Qt.alpha(Christmas.cranberry, card.reveal)) }
                        GradientStop { position: 1; color: Qt.tint("#1c2022", Qt.alpha("#4c0c18", card.reveal)) }
                    }
                }
                // a gold band round the middle, with dots
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.tint("#9b917e", Qt.alpha(card.gold, card.reveal))
                        strokeWidth: card.s(2.2)
                        fillColor: "transparent"
                        startX: globe.width * 0.04; startY: globe.height * 0.52
                        PathQuad { x: globe.width * 0.96; y: globe.height * 0.52; controlX: globe.width * 0.5; controlY: globe.height * 0.68 }
                    }
                    ShapePath {
                        strokeColor: Qt.tint("#9b917e", Qt.alpha(card.gold, card.reveal))
                        strokeWidth: card.s(1)
                        fillColor: "transparent"
                        startX: globe.width * 0.06; startY: globe.height * 0.62
                        PathQuad { x: globe.width * 0.94; y: globe.height * 0.62; controlX: globe.width * 0.5; controlY: globe.height * 0.78 }
                    }
                }
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        readonly property real u: 0.2 + index * 0.15
                        width: card.s(3); height: width; radius: width / 2
                        x: globe.width * u - width / 2
                        y: globe.height * (0.57 + 0.32 * u * (1 - u)) - height / 2
                        color: Qt.tint("#c9c1b0", Qt.alpha("#fff0c4", card.reveal))
                    }
                }
                // the lights reflected in the glass, twinkling
                Repeater {
                    model: card.reveal > 0.05 ? 4 : 0
                    Rectangle {
                        required property int index
                        width: card.s(3.4); height: width; radius: width / 2
                        x: globe.width * (0.22 + index * 0.17) - width / 2
                        y: globe.height * (0.3 - 0.06 * Math.sin((index + 0.5) / 4 * Math.PI)) - height / 2
                        color: Christmas.bulb(index)
                        opacity: card.reveal * (0.55 + 0.45 * Math.sin(Christmas.phase * (1.3 + index * 0.4) + index))
                    }
                }
                // glass highlights
                Rectangle {
                    x: parent.width * 0.2; y: parent.height * 0.12
                    width: parent.width * 0.3; height: parent.height * 0.17
                    radius: height / 2
                    rotation: -35
                    color: Qt.alpha("white", 0.32)
                }
                Rectangle {
                    x: parent.width * 0.66; y: parent.height * 0.7
                    width: parent.width * 0.1; height: width; radius: width / 2
                    color: Qt.alpha("white", 0.14)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: ball.activeFocus ? card.s(2) : card.s(1)
                    border.color: ball.activeFocus ? "white" : Qt.alpha("white", 0.12)
                }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { ball.forceActiveFocus(Qt.MouseFocusReason); card.toggle(); }
        }
    }

    // A section of options on its own panel; it slides in after the ones before it.
    component Section: Item {
        id: section
        property int order: 0
        property string title
        property string hint
        default property alias content: body.data
        readonly property real pad: card.s(card.compact ? 14 : 18)
        readonly property real shown: card.clamp((card.unfold - order * 0.15) / 0.45)
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
            RowLayout {
                Layout.fillWidth: true
                spacing: card.s(10)
                Text {
                    text: section.title
                    color: card.fg
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(14); font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    text: section.hint
                    color: card.softText
                    font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                    elide: Text.ElideRight
                }
            }
        }
    }

    // The gold of a chosen tile floods out from the point pressed and drains back into it.
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
        Rectangle { anchors.fill: parent; radius: plate.radius; color: card.gold; visible: plate.level >= 0.999 }
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
                        color: card.gold
                    }
                }
            }
        }
    }

    // A light style: a short string of its bulbs over its name. Picked, the gold floods it and its bulbs relight.
    component LightTile: AbstractButton {
        id: tile
        property string key
        property string name
        property int styleIndex: 0
        readonly property bool on: Christmas.lights === key
        property real zoom: pressed ? 0.93 : hovered || visualFocus ? 1.04 : 1
        Behavior on zoom { enabled: card.motion; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        padding: 0
        implicitWidth: card.s(card.compact ? 104 : 120)
        implicitHeight: card.s(card.compact ? 74 : 82)
        Accessible.role: Accessible.RadioButton
        Accessible.name: name
        Accessible.checked: on
        onPressedChanged: if (pressed) { plate.pressX = visualFocus ? width / 2 : pressX; plate.pressY = visualFocus ? height / 2 : pressY; }
        onClicked: Config.setSetting("addonsV2ChristmasLights", key)
        onOnChanged: if (on && card.initialized) preview.relight()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
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
            // a dark pane behind the bulbs, so they glow on any theme
            Rectangle {
                x: card.s(8); y: card.s(7)
                width: parent.width - 2 * x; height: parent.height * 0.5
                radius: card.corner * 0.7
                color: Qt.alpha("#0c0f0d", tile.on ? 0.85 : 0.55)
                clip: true
                ChristmasLights {
                    id: preview
                    x: card.s(4); width: parent.width - card.s(8); height: parent.height
                    on: card.active
                    instant: false
                    style: tile.styleIndex
                    live: tile.on
                    spacing: card.s(18)
                    swag: spacing * 2
                    sag: card.s(4)
                    wireY: card.s(2)
                    bulb: card.s(3.6)
                    glow: 0.7
                    seed: tile.styleIndex
                    cascade: 700
                }
            }
            Text {
                anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.1
                x: card.s(3); width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: tile.name
                color: tile.on ? card.ink : card.fg
                Behavior on color { enabled: card.motion; ColorAnimation { duration: 280 } }
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11); font.weight: Font.Bold
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: card.s(8)
                elide: Text.ElideRight
            }
        }
    }

    // The effects' opacity: the volume panel's slider, in gold and across the whole section. A drag is saved when it ends, the
    // wheel and the arrow keys after a short pause.
    component OpacityRow: RowLayout {
        id: fade
        property int pending: -1
        function save(): void {
            saveLater.stop();
            if (pending < 0) return;
            Christmas.setEffectOpacity(pending / 100);
            pending = -1;
        }
        spacing: card.s(12)
        Component.onDestruction: save()
        Timer { id: saveLater; interval: 400; onTriggered: fade.save() }
        Text {
            text: qsTr("Effect opacity")
            color: card.fg
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12); font.weight: Font.Bold
        }
        Draggable {
            id: slider
            Layout.fillWidth: true
            Layout.preferredHeight: card.s(16)
            Layout.alignment: Qt.AlignVCenter
            from: 10
            to: 100
            defaultValue: 70
            value: fade.pending >= 0 ? fade.pending : Math.round(Christmas.effectOpacity * 100)
            backgroundColor: ThemeBackend.surface1
            // shaped and coloured like the volume panel's slider, so its handle grows, lights up and flashes the same way
            accentColor: card.gold
            gradColor1: card.gold
            gradColor2: Qt.lighter(card.gold, 1.05)
            gradColor3: Qt.lighter(card.gold, 1.10)
            cornerRadius: card.s(5)
            handleSize: card.s(18)
            handleColor: Qt.lighter(card.gold, 1.15)
            handleHoverColor: Qt.lighter(card.gold, 1.5)
            handleDragColor: Qt.lighter(card.gold, 1.45)
            handleBorderColor: Qt.rgba(0, 0, 0, 0.2)
            activeFocusOnTab: true
            action_highlight: activeFocus
            Keys.onLeftPressed: nudge(-1)
            Keys.onRightPressed: nudge(1)
            Accessible.role: Accessible.Slider
            Accessible.name: qsTr("Effect opacity")
            christmasDisableWheel: true
            onMoved: function(val) { fade.pending = Math.round(val); if (!slider.isDragging) saveLater.restart(); }
            onDragStarted: saveLater.stop()
            onDragFinished: fade.save()
        }
        Text {
            Layout.preferredWidth: card.s(36)
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.effectiveValue) + "%"
            color: card.softText
            font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
        }
    }

    // The shell's toggle in gold, with a name and a line of detail. It flips itself on a press, so the setting is
    // bound back: the handle only stays moved once the setting has changed.
    component SwitchRow: RowLayout {
        id: row
        property string text
        property string detail
        property bool on: false
        signal flipped()
        spacing: card.s(12)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: card.s(1)
            Text {
                Layout.fillWidth: true
                text: row.text
                color: card.fg
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(12); font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.detail !== ""
                text: row.detail
                color: card.softText
                font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(11)
                wrapMode: Text.Wrap
            }
        }
        Toggle {
            id: toggle
            horizontalPadding: 0
            checked: row.on
            accentColor: card.gold
            baseColor: ThemeBackend.surface1
            handleColor: card.ink
            handleOffColor: ThemeBackend.text
            action_highlight: activeFocus
            Accessible.role: Accessible.CheckBox
            Accessible.name: row.text
            Accessible.checkable: true
            Accessible.checked: row.on
            Accessible.onPressAction: row.flipped()
            onToggled: {
                row.flipped();
                toggle.checked = Qt.binding(() => row.on);
            }
        }
    }
}
