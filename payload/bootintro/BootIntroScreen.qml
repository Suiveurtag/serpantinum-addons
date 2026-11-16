import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../"

// One screen of the boot intro; AddonBootIntro.qml owns the timeline. Built like serp/Start.qml (same wipe, orbs,
// vignette, monitor zoom, masked logo with the water wave, typewriter words), so it reads as the native welcome.
// The primary screen gets the whole scene; the others get the wipe and the orbs, in step with it.
PanelWindow {
    id: window

    required property var intro
    property bool primary: true

    WlrLayershell.namespace: "serpantinum-boot-intro"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: primary && !intro.closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    function s(val) {
        let res = Scaler.s(val);
        return res > 0 ? res : val;
    }

    readonly property color base:     ThemeBackend.base
    readonly property color crust:    ThemeBackend.crust
    readonly property color surface1: ThemeBackend.surface1
    readonly property color text:     ThemeBackend.text
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color blue:     ThemeBackend.blue     || "#89b4fa"
    readonly property color mauve:    ThemeBackend.mauve    || "#cba6f7"
    readonly property color peach:    ThemeBackend.peach    || "#fab387"
    readonly property string assets: "file://" + Caching.serpantinumDir + "/assets/"

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real idlePhase: 0.0
    NumberAnimation on idlePhase {
        from: 0.0; to: Math.PI * 2; duration: 8000; loops: Animation.Infinite; running: window.intro.idleTextActive
    }

    readonly property bool french: (I18n.currentLang || "").startsWith("fr")
    readonly property string userName: {
        const raw = Quickshell.env("USER") || "";
        return raw ? raw.charAt(0).toUpperCase() + raw.slice(1) : "";
    }
    readonly property string greeting: {
        const hour = new Date().getHours();
        if (french) return hour < 5 ? "Bonne nuit," : hour < 12 ? "Bonjour," : hour < 18 ? "Bon après-midi," : hour < 22 ? "Bonsoir," : "Bonne nuit,";
        return hour < 5 ? "Good night," : hour < 12 ? "Good morning," : hour < 18 ? "Good afternoon," : hour < 22 ? "Good evening," : "Good night,";
    }
    readonly property string dateLine: {
        const now = new Date();
        const day = now.toLocaleDateString(Qt.locale(), "dddd d MMMM");
        return day.charAt(0).toUpperCase() + day.slice(1);
    }
    readonly property string timeLine: new Date().toLocaleTimeString(Qt.locale(), "HH:mm")

    component TypewriterText : Row {
        id: twRoot
        property string text: ""
        property real reveal: 0.0
        property font font
        property color color: window.text
        property bool soundEnabled: true
        property string typeSfx: "start/type.wav"

        spacing: 0
        Repeater {
            model: Array.from(twRoot.text)
            Text {
                required property string modelData
                required property int index
                text: modelData === " " ? " " : modelData
                font: twRoot.font
                color: twRoot.color

                property bool shown: (twRoot.reveal * (twRoot.text.length + 2)) > index

                onShownChanged: {
                    if (shown && twRoot.soundEnabled && window.primary && window.intro.soundEnabled && modelData !== " ") Sounds.playSfx(twRoot.typeSfx);
                }

                opacity: shown ? 1.0 : 0.0
                scale: shown ? 1.0 : 0.94

                transform: Translate {
                    y: (shown ? 0 : window.s(10)) + (window.intro.idleTextActive && shown ? Math.sin(window.idlePhase + (index * 0.3)) * window.s(1.2) : 0)
                    Behavior on y { NumberAnimation { duration: 550; easing.type: Easing.OutQuint } }
                }

                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                Behavior on color { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
        }
    }

    component Orb : Item {
        id: orb
        property color tint
        property real orbitX
        property real orbitY
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - height / 2
        z: 1
        transform: Translate { x: orb.orbitX; y: orb.orbitY }
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            Rectangle { id: orbSource; anchors.fill: parent; radius: width / 2; color: orb.tint; visible: false }
            MultiEffect { source: orbSource; anchors.fill: parent; blurEnabled: true; blur: 0.8; blurMax: 36 }
        }
    }

    ShaderEffect {
        id: bgCanvas
        anchors.fill: parent

        property real phase: 0.0
        NumberAnimation on phase {
            loops: Animation.Infinite
            running: window.intro.panelReveal > 0.0 && window.intro.panelReveal < 1.0
            from: 0; to: Math.PI * 2; duration: 3600
        }

        property vector2d itemSize: Qt.vector2d(width, height)
        property real reveal: window.intro.panelReveal
        property color color0: window.crust
        property color color1: window.surface1
        property color color2: window.blue
        property color color3: window.mauve
        property color color4: window.base
        property vector4d params: Qt.vector4d(window.s(45), 0.0, 0.0, 0.0)

        fragmentShader: window.assets + "shaders/effects/screen_wipe.frag.qsb"
    }

    Item {
        id: rootItem
        anchors.fill: parent
        focus: true
        opacity: window.intro.mainOpacity

        Keys.onPressed: event => { event.accepted = true; window.intro.skip(); }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: window.intro.skip() }

        Orb {
            width: window.s(1200); height: width
            tint: window.mauve
            opacity: window.intro.introPhase * 0.04 + window.intro.orbBoost * 0.12
            orbitX: Math.cos(window.globalOrbitAngle * 2) * window.s(450)
            orbitY: Math.sin(window.globalOrbitAngle * 2) * window.s(250)
        }
        Orb {
            width: window.s(1400); height: width
            tint: window.blue
            opacity: window.intro.introPhase * 0.04 + window.intro.orbBoost * 0.10
            orbitX: Math.sin(window.globalOrbitAngle * 1.5) * window.s(-450)
            orbitY: Math.cos(window.globalOrbitAngle * 1.5) * window.s(-250)
        }

        ShaderEffect {
            anchors.fill: parent
            z: 0
            property vector2d itemSize: Qt.vector2d(width, height)
            property color vignetteColor: "#000000"
            property vector4d params: Qt.vector4d(0.4, 0.75, 0.4, 0.0)
            fragmentShader: window.assets + "shaders/effects/vignette.frag.qsb"
        }

        Item {
            id: monitorRig
            visible: window.primary
            width: window.s(1200)
            height: window.s(900)
            anchors.centerIn: parent
            scale: 1.5 - (0.5 * window.intro.monitorZoomProgress)
            opacity: window.intro.monitorZoomProgress
            transformOrigin: Item.Center
            z: 2

            Item {
                anchors.fill: parent
                opacity: window.intro.toSerpOpacity

                Item {
                    id: logoContainer
                    width: window.s(400)
                    height: window.s(400)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: window.s(-84)
                    scale: window.intro.logoScale
                    opacity: window.intro.logoOpacity
                    transformOrigin: Item.Center

                    Item {
                        id: paddedMaskSource
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        layer.smooth: true

                        Image {
                            anchors.centerIn: parent
                            width: window.s(360)
                            height: window.s(360)
                            source: window.assets + "logo.svg"
                            sourceSize: Qt.size(width, height)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            antialiasing: true
                        }
                    }

                    Item {
                        id: logoColorBlock
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        layer.smooth: true

                        Rectangle { anchors.fill: parent; color: window.text }

                        ShaderEffect {
                            anchors.fill: parent

                            property real wavePhase: 0.0
                            NumberAnimation on wavePhase {
                                running: window.intro.logoFillLevel > 0.0 && window.intro.logoFillLevel < 1.45
                                loops: Animation.Infinite
                                from: 0; to: Math.PI * 2; duration: 3500
                            }

                            property vector2d itemSize: Qt.vector2d(width, height)
                            property real fillLevel: window.intro.logoFillLevel
                            property color baseColor: window.mauve
                            property vector4d params: Qt.vector4d(window.s(16), 0.0, 0.0, 0.0)

                            fragmentShader: window.assets + "shaders/fluid/logo_water_wave.frag.qsb"
                        }
                    }

                    MultiEffect {
                        source: logoColorBlock
                        anchors.fill: parent
                        maskEnabled: true
                        maskSource: paddedMaskSource
                        autoPaddingEnabled: false
                        shadowEnabled: true

                        shadowColor: window.intro.colorizeActive ? window.mauve : window.crust
                        shadowBlur: window.intro.colorizeActive ? 1.0 : 0.6
                        shadowOpacity: window.intro.colorizeActive ? 0.3 : 0.6
                        shadowVerticalOffset: window.intro.colorizeActive ? 0 : window.s(6)

                        Behavior on shadowColor { ColorAnimation { duration: 800; easing.type: Easing.InOutCubic } }
                        Behavior on shadowBlur { NumberAnimation { duration: 800; easing.type: Easing.InOutCubic } }
                        Behavior on shadowOpacity { NumberAnimation { duration: 800; easing.type: Easing.InOutCubic } }
                        Behavior on shadowVerticalOffset { NumberAnimation { duration: 800; easing.type: Easing.InOutCubic } }
                    }
                }

                TypewriterText {
                    id: serpText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: window.s(120)
                    text: I18n.t("start.title")
                    reveal: window.intro.toSerpReveal
                    color: window.intro.colorizeActive ? window.mauve : window.text
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: window.s(48)
                    soundEnabled: false
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: serpText.bottom
                    anchors.topMargin: window.s(12)
                    text: window.timeLine + "  ·  " + window.dateLine
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: window.s(15)
                    scale: 0.88
                    color: window.subtext0
                    opacity: window.intro.finalAuthorOpacity
                }
            }
        }

        // "Good evening, Name": the upstream tagline row with the name in the colour-cycling "You" style
        Item {
            id: textScene
            visible: window.primary
            anchors.centerIn: parent
            width: shellTextRow.implicitWidth
            height: shellTextRow.implicitHeight + window.s(40)
            opacity: window.intro.shellTextOpacity
            scale: window.intro.shellTextScale
            z: 5

            Row {
                id: shellTextRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: window.s(8)

                TypewriterText {
                    text: window.greeting
                    reveal: Math.min(1.0, window.intro.shellTextReveal * 1.4)
                    color: window.text
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: window.s(28)
                    y: window.s(12)
                }

                TypewriterText {
                    id: nameText
                    visible: window.userName !== ""
                    text: window.userName
                    reveal: Math.max(0.0, Math.min(1.0, (window.intro.shellTextReveal - 0.70) * 3.33))
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: window.s(48)

                    property color blinkColor: window.mauve
                    SequentialAnimation on blinkColor {
                        loops: Animation.Infinite
                        running: window.intro.shellTextOpacity > 0
                        ColorAnimation { to: window.blue; duration: 900; easing.type: Easing.InOutSine }
                        ColorAnimation { to: window.peach; duration: 900; easing.type: Easing.InOutSine }
                        ColorAnimation { to: window.mauve; duration: 900; easing.type: Easing.InOutSine }
                    }
                    color: blinkColor

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: nameText.blinkColor
                        shadowBlur: 0.8
                        shadowOpacity: 0.85
                        shadowVerticalOffset: 0
                    }
                }
            }

            Text {
                anchors.top: shellTextRow.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                text: window.dateLine
                font.family: ThemeBackend.fontFamily
                font.pixelSize: window.s(14)
                color: window.subtext0
                opacity: window.intro.authorOpacity
                scale: window.intro.authorScale
            }
        }
    }
}
