import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Opening animation played once per login (Addons → General → "Boot intro", addonsV2BootIntro).
// The choreography is the upstream welcome (serp/Start.qml) made for a login: wipe in, a typed greeting with the
// colour-cycling name, then the logo filled by the water wave over "Serpantinum", and the upstream close sequence.
// Direct ShellRoot child: the IPC target "addonBootIntro" exists even while the intro is off.
// The session key changes with every compositor start (new login) but not on a shell reload, so a reload never replays it.
Scope {
    id: root

    readonly property bool enabled: Config.getSetting("addonsV2BootIntro", true) !== false
    readonly property bool soundEnabled: Config.getSetting("addonsV2BootIntroSound", true) !== false
    readonly property string sessionKey: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || Quickshell.env("NIRI_SOCKET")
                                         || Quickshell.env("XDG_SESSION_ID") || ""
    readonly property string primaryName: {
        const primary = Quickshell.primaryScreen || (Quickshell.screens.length ? Quickshell.screens[0] : null);
        return primary ? primary.name : "";
    }

    property bool running: false
    property bool closing: false
    property bool decided: false
    property bool stateRead: false
    property string lastKey: ""

    // Same names and meaning as serp/Start.qml.
    property real panelReveal: 0.0
    property real introPhase: 0.0
    property real orbBoost: 0.0
    property real shellTextReveal: 0.0
    property real shellTextOpacity: 0.0
    property real shellTextScale: 0.94
    property real authorOpacity: 0.0
    property real authorScale: 0.94
    property real toSerpReveal: 0.0
    property real toSerpOpacity: 0.0
    property real logoOpacity: 0.0
    property real logoScale: 0.94
    property bool colorizeActive: false
    property real logoFillLevel: 0.0
    property real finalAuthorOpacity: 0.0
    property real monitorZoomProgress: 0.0
    property real mainOpacity: 1.0
    property bool idleTextActive: false

    property int bgSoundHandle: -1
    property int exitSoundHandle: -1

    function sfx(name, volume) { if (root.soundEnabled) Sounds.playSfx("start/" + name, volume); }

    function reset() {
        panelReveal = 0; introPhase = 0; orbBoost = 0; shellTextReveal = 0; shellTextOpacity = 0; shellTextScale = 0.94;
        authorOpacity = 0; authorScale = 0.94; toSerpReveal = 0; toSerpOpacity = 0; logoOpacity = 0; logoScale = 0.94;
        colorizeActive = false; logoFillLevel = 0; finalAuthorOpacity = 0; monitorZoomProgress = 0; mainOpacity = 1;
        idleTextActive = false; closing = false;
    }

    function play() {
        if (running) return;
        reset();
        running = true;
        Qt.callLater(() => introChoreography.restart());
    }

    function skip() {
        if (!running || closing) return;
        introChoreography.stop();
        closeSequence.restart();
    }

    function stopSounds() {
        if (bgSoundHandle !== -1) { Sounds.stopSfx(bgSoundHandle); bgSoundHandle = -1; }
        if (exitSoundHandle !== -1) { Sounds.stopSfx(exitSoundHandle); exitSoundHandle = -1; }
    }

    function finish() {
        stopSounds();
        running = false;
        closing = false;
    }

    function decide() {
        if (decided || !stateRead || !Config.dataReady) return;
        decided = true;
        if (!root.enabled || root.sessionKey === "" || root.sessionKey === root.lastKey) return;
        stateFile.setText(JSON.stringify({ session: root.sessionKey, played: new Date().toISOString() }) + "\n");
        play();
    }

    FileView {
        id: stateFile
        path: Caching.stateDir + "/addons_v2_boot_intro.json"
        printErrors: false
        onLoaded: {
            try { root.lastKey = JSON.parse(text()).session || ""; } catch (e) { root.lastKey = ""; }
            root.stateRead = true;
            root.decide();
        }
        onLoadFailed: { root.stateRead = true; root.decide(); }
    }

    Connections {
        target: Config
        function onDataReadyChanged() { root.decide(); }
        function onSettingsLoaded() { root.decide(); }
    }
    Component.onCompleted: decide()

    // Safety net: whatever happens to the animations, the desktop is never left covered.
    Timer { interval: 20000; running: root.running; onTriggered: root.finish() }

    NumberAnimation {
        target: root; property: "introPhase"; from: 0.0; to: 1.0; duration: 2500; easing.type: Easing.OutExpo
        running: root.running && root.panelReveal > 0.5
    }

    SequentialAnimation {
        id: introChoreography
        ScriptAction { script: {
            if (root.soundEnabled) root.bgSoundHandle = Sounds.playUntilStopped("start/background.wav", 0.4, true);
            root.sfx("start.wav");
        } }
        PauseAnimation { duration: 100 }

        NumberAnimation { target: root; property: "panelReveal"; from: 0.0; to: 1.0; duration: 1400; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 150 }

        // "Good evening, Name": the upstream tagline row, the name in the colour-cycling "You" style
        ParallelAnimation {
            PropertyAction { target: root; property: "shellTextOpacity"; value: 1.0 }
            NumberAnimation { target: root; property: "shellTextReveal"; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "shellTextScale"; from: 0.94; to: 1.0; duration: 1400; easing.type: Easing.OutExpo }
        }
        PauseAnimation { duration: 150 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "authorOpacity"; to: 1.0; duration: 500; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "authorScale"; to: 1.0; duration: 500; easing.type: Easing.OutQuint }
            ScriptAction { script: root.sfx("pop_author.wav") }
        }
        PauseAnimation { duration: 900 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "shellTextOpacity"; to: 0.0; duration: 400; easing.type: Easing.OutQuart }
            NumberAnimation { target: root; property: "authorOpacity"; to: 0.0; duration: 400; easing.type: Easing.OutQuart }
        }
        ScriptAction { script: root.sfx("transition_serp.wav", 0.6) }

        // the logo over "Serpantinum", filled by the water wave
        ParallelAnimation {
            SequentialAnimation {
                PauseAnimation { duration: 800 }
                NumberAnimation { target: root; property: "finalAuthorOpacity"; to: 0.6; duration: 1000; easing.type: Easing.OutQuint }
            }
            SequentialAnimation {
                PauseAnimation { duration: 210 }
                ParallelAnimation {
                    PropertyAction { target: root; property: "toSerpOpacity"; value: 1.0 }
                    NumberAnimation { target: root; property: "toSerpReveal"; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
                    NumberAnimation { target: root; property: "logoOpacity"; to: 1.0; duration: 1500; easing.type: Easing.OutQuart }
                    NumberAnimation { target: root; property: "logoScale"; from: 0.94; to: 1.0; duration: 1800; easing.type: Easing.OutExpo }
                }
                ScriptAction { script: root.idleTextActive = true }
            }
            SequentialAnimation {
                ScriptAction { script: root.sfx("wave.wav", 0.2) }
                PauseAnimation { duration: 250 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "orbBoost"; to: 1.0; duration: 2600; easing.type: Easing.OutSine }
                    ScriptAction { script: root.colorizeActive = true }
                    NumberAnimation { target: root; property: "logoFillLevel"; to: 1.5; duration: 3000; easing.type: Easing.OutSine }
                    NumberAnimation { target: root; property: "monitorZoomProgress"; from: 0.0; to: 1.0; duration: 2800; easing.type: Easing.OutQuint }
                }
            }
        }
        PauseAnimation { duration: 300 }
        ScriptAction { script: closeSequence.restart() }
    }

    // serp/Start.qml closeSequence
    SequentialAnimation {
        id: closeSequence
        ScriptAction { script: {
            root.closing = true;
            root.sfx("transition_serp.wav", 0.6);
            if (root.soundEnabled) root.exitSoundHandle = Sounds.playUntilStopped("start/exit.wav", 0.7, false);
        } }
        PauseAnimation { duration: 400 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "mainOpacity"; to: 0.0; duration: 400; easing.type: Easing.OutQuint }
            NumberAnimation { target: root; property: "panelReveal"; to: 0.0; duration: 1760; easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: root.finish() }
    }

    IpcHandler {
        target: "addonBootIntro"
        function play(): void { root.play(); }
        function skip(): void { root.skip(); }
        // Forget this session so the next shell start plays the intro again.
        function forget(): void { root.lastKey = ""; stateFile.setText("{}\n"); }
    }

    Loader {
        active: root.running
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: BootIntroScreen {
                required property var modelData
                screen: modelData
                intro: root
                primary: modelData.name === root.primaryName || Quickshell.screens.length === 1
            }
        }
    }
}
