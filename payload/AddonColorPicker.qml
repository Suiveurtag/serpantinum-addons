import QtQuick
import "reusables"
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    color: "transparent"
    visible: active
    focusable: active
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-addon-color-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    property bool active: false
    property bool opening: false
    property bool ready: false
    property bool selected: false
    property bool selectionPending: false
    property bool copying: false
    property bool closing: false
    property string capturePath: ""
    property string captureUrl: ""
    property real pointerX: width / 2
    property real pointerY: height / 2
    property int red: 0
    property int green: 0
    property int blue: 0
    property string copiedFormat: ""
    property string copyError: ""
    property real intro: 0
    property real outro: 0
    property real expansion: selected ? 1 : 0
    property real copyProgress: 0
    property real edgePhase: 0
    property bool editing: false
    property real editHue: 0
    property real editSat: 0
    property real editVal: 0
    property real editProgress: editing ? 1 : 0
    property real swatchRipple: 1
    function cursorScreen() {
        return Quickshell.cursorScreen ?? Quickshell.screens.find(screen => Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0] ?? null;
    }
    property var targetScreen: cursorScreen()
    screen: targetScreen

    Behavior on expansion { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    Behavior on editProgress { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }
    NumberAnimation { id: rippleAnimation; target: root; property: "swatchRipple"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation on edgePhase { from: 0; to: Math.PI * 2; duration: 6400; loops: Animation.Infinite; running: root.active }
    NumberAnimation { id: entrance; target: root; property: "intro"; to: 1; duration: 520; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: dismiss
        NumberAnimation { target: root; property: "outro"; to: 1; duration: 230; easing.type: Easing.InCubic }
        ScriptAction { script: root.finishClose() }
    }
    SequentialAnimation {
        id: copiedAnimation
        NumberAnimation { target: root; property: "copyProgress"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 520 }
        NumberAnimation { target: root; property: "outro"; to: 1; duration: 260; easing.type: Easing.InCubic }
        ScriptAction { script: root.finishClose() }
    }

    function s(value) { return Scaler.s(value); }
    function hexPart(value) { return Math.round(value).toString(16).padStart(2, "0").toUpperCase(); }
    readonly property string hexColor: "#" + hexPart(red) + hexPart(green) + hexPart(blue)
    readonly property string rgbColor: "rgb(" + red + ", " + green + ", " + blue + ")"
    readonly property string hslColor: {
        let r = red / 255, g = green / 255, b = blue / 255;
        let max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
        let light = (max + min) / 2, saturation = 0, hue = 0;
        if (delta > 0) {
            saturation = delta / (1 - Math.abs(2 * light - 1));
            switch (max) {
            case r: hue = ((g - b) / delta) % 6; break;
            case g: hue = (b - r) / delta + 2; break;
            default: hue = (r - g) / delta + 4;
            }
            hue = (hue * 60 + 360) % 360;
        }
        return "hsl(" + Math.round(hue) + ", " + Math.round(saturation * 100) + "%, " + Math.round(light * 100) + "%)";
    }

    IpcHandler {
        target: "addonColorPicker"
        function toggle(): void { (root.active || root.opening) ? root.close() : root.open(); }
        function activate(): void { root.open(); }
        function deactivate(): void { root.close(); }
    }

    function open() {
        if (active || opening || capture.running) return;
        targetScreen = cursorScreen();
        selected = false;
        selectionPending = false;
        editing = false;
        ready = false;
        copying = false;
        closing = false;
        copiedFormat = "";
        copyError = "";
        intro = 0;
        outro = 0;
        copyProgress = 0;
        pointerX = width / 2;
        pointerY = height / 2;
        opening = true;
        captureTimer.restart();
    }

    function close() {
        if (closing) return;
        opening = false;
        captureTimer.stop();
        if (capture.running) capture.running = false;
        if (!active) { finishClose(); return; }
        closing = true;
        copiedAnimation.stop();
        entrance.stop();
        dismiss.start();
    }

    function finishClose() {
        active = false;
        ready = false;
        selected = false;
        selectionPending = false;
        editing = false;
        opening = false;
        copying = false;
        closing = false;
        preview.source = "";
        if (captureUrl !== "") magnifier.unloadImage(captureUrl);
        if (capturePath !== "") Quickshell.execDetached(["rm", "-f", capturePath]);
        capturePath = "";
        captureUrl = "";
    }

    Timer {
        id: captureTimer
        interval: 360 // Let the quickaction retract before freezing the desktop.
        onTriggered: {
            if (!root.targetScreen) { root.finishClose(); return; }
            root.capturePath = Caching.getRunDir("screenshot") + "/picker_" + Date.now() + ".png";
            capture.command = ["grim", "-o", root.targetScreen.name, "-l", "0", root.capturePath];
            capture.running = true;
        }
    }

    Process {
        id: capture
        onExited: (exitCode) => {
            if (!root.opening) return;
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Serpantinum", "Color picker", "Could not capture the screen. Check that grim is available."]);
                root.finishClose();
                return;
            }
            root.opening = false;
            root.active = true;
            root.captureUrl = "file://" + root.capturePath;
            preview.source = root.captureUrl;
        }
    }

    Image {
        id: preview
        anchors.fill: parent
        fillMode: Image.Stretch
        // Keep native screenshot pixels for exact sampling on scaled displays.
        sourceSize: Qt.size(0, 0)
        asynchronous: false
        cache: false
        onStatusChanged: {
            if (status === Image.Ready && root.captureUrl !== "") magnifier.loadImage(root.captureUrl);
            if (status === Image.Error) root.close();
        }
    }

    Item {
        id: frozenBackdrop
        readonly property bool isGlassBackdrop: true
        anchors.fill: parent
        readonly property bool active: root.active && ThemeBackend.liquidGlass && preview.status === Image.Ready
        property alias texture: frozenTexture
        property int consumers: 0
        property int frame: 0
        readonly property real cursorX: root.pointerX
        readonly property real cursorY: root.pointerY
        readonly property real hoverAmount: root.selected ? 0 : 1
        ShaderEffectSource {
            id: frozenTexture
            sourceItem: frozenBackdrop.active ? preview : null
            live: false
            visible: false
        }
        FrameAnimation {
            running: frozenBackdrop.active && frozenBackdrop.consumers > 0
            onTriggered: frozenBackdrop.frame++
        }
    }
    readonly property Item glassBackdropItem: frozenBackdrop

    Shortcut { sequence: "Escape"; enabled: root.active; onActivated: { if (root.editing) root.editing = false; else root.close(); } }
    Shortcut { sequence: "Return"; enabled: root.ready && !root.copying && !root.closing; onActivated: root.selected ? root.copy("HEX", root.hexColor) : root.choose() }
    Shortcut { sequence: "Enter"; enabled: root.ready && !root.copying && !root.closing; onActivated: root.selected ? root.copy("HEX", root.hexColor) : root.choose() }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.crust, 0.09)
        opacity: root.intro * (1 - root.outro)
    }

    // Native shape geometry keeps the animated outline on the GPU. Its theme
    // gradient rotates, blooms on entry, then recedes with the copy confirmation.
    Item {
        id: edgeFrame
        anchors.fill: parent
        anchors.margins: root.s(3 + (1 - root.intro) * 12)
        opacity: root.intro * (1 - root.outro)
        readonly property real thickness: root.s(3.5 + root.copyProgress * 2)
        readonly property real corner: root.s(26)

        function roundedPath(x, y, w, h, r) {
            r = Math.min(r, w / 2, h / 2);
            return "M " + (x + r) + " " + y
                + " H " + (x + w - r) + " Q " + (x + w) + " " + y + " " + (x + w) + " " + (y + r)
                + " V " + (y + h - r) + " Q " + (x + w) + " " + (y + h) + " " + (x + w - r) + " " + (y + h)
                + " H " + (x + r) + " Q " + x + " " + (y + h) + " " + x + " " + (y + h - r)
                + " V " + (y + r) + " Q " + x + " " + y + " " + (x + r) + " " + y + " Z ";
        }

        MultiEffect {
            anchors.fill: outline
            source: outline
            blurEnabled: true
            blurMax: 32
            blur: 0.7
            opacity: 0.78 + Math.sin(root.edgePhase * 2) * 0.16
            autoPaddingEnabled: false
        }
        Shape {
            id: outline
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    x1: outline.width * (0.5 + Math.cos(root.edgePhase) * 0.5)
                    y1: outline.height * (0.5 + Math.sin(root.edgePhase) * 0.5)
                    x2: outline.width - x1
                    y2: outline.height - y1
                    GradientStop { position: 0; color: ThemeBackend.mauve }
                    GradientStop { position: 0.22; color: ThemeBackend.blue }
                    GradientStop { position: 0.46; color: ThemeBackend.sapphire }
                    GradientStop { position: 0.72; color: ThemeBackend.peach }
                    GradientStop { position: 1; color: ThemeBackend.mauve }
                }
                PathSvg {
                    path: edgeFrame.roundedPath(0, 0, outline.width, outline.height, edgeFrame.corner)
                        + edgeFrame.roundedPath(edgeFrame.thickness, edgeFrame.thickness,
                            outline.width - edgeFrame.thickness * 2, outline.height - edgeFrame.thickness * 2,
                            edgeFrame.corner - edgeFrame.thickness)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.ready && !root.copying && !root.closing
        cursorShape: root.selected ? Qt.ArrowCursor : Qt.CrossCursor
        onPositionChanged: mouse => {
            if (root.selected || root.selectionPending) return;
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            magnifier.requestPaint();
        }
        onClicked: mouse => {
            if (root.selected) return;
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            root.choose();
        }
    }

    AddonGlassSurface {
        id: card
        width: root.s(236 + 60 * root.expansion)
        height: root.s(98 + 142 * root.expansion + 172 * root.editProgress)
        x: Math.max(root.s(18), Math.min(root.width - width - root.s(18), root.pointerX + root.s(28)))
        y: Math.max(root.s(18), Math.min(root.height - height - root.s(18), root.pointerY + root.s(28))) - root.s(12) * root.outro
        radius: root.s(18)
        clip: true
        surfaceColor: ThemeBackend.base
        glassTint: Qt.tint(ThemeBackend.base, Qt.alpha(root.hexColor, 0.16))
        glassPulse: Math.sin(root.copyProgress * Math.PI)
        border.width: root.s(1)
        border.color: Qt.alpha(root.copyProgress > 0 ? ThemeBackend.green : root.editing ? root.hexColor : ThemeBackend.mauve, 0.5)
        visible: root.active
        opacity: root.intro * (1 - root.outro)
        scale: (0.9 + root.intro * 0.1) * (1 + Math.sin(root.copyProgress * Math.PI) * 0.045) * (1 - root.outro * 0.12)
        Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 220 } }

        Loader {
            anchors.fill: parent
            z: -1
            active: card.blurActive && root.ready
            sourceComponent: Item {
                ShaderEffectSource {
                    id: capturedRegion
                    sourceItem: preview
                    sourceRect: Qt.rect(card.x, card.y, card.width, card.height)
                    textureSize: Qt.size(Math.max(1, card.width), Math.max(1, card.height))
                    live: true
                    visible: false
                }
                Rectangle {
                    id: blurMask
                    anchors.fill: parent
                    radius: card.radius
                    color: "white"
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: capturedRegion
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 32
                    blur: 1 - card.glint * 0.12
                    maskEnabled: true
                    maskSource: blurMask
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: 1 - root.copyProgress
            Rectangle {
                id: zoomBox
                x: root.s(14); y: root.s(14)
                width: root.s(64 + 8 * root.expansion); height: width
                radius: root.s(10)
                color: ThemeBackend.surface0
                clip: true
                scale: !root.selected ? 1 : swatchMouse.pressed ? 0.94 : swatchMouse.containsMouse ? 1.12 : 1.08
                Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.hexColor
                    opacity: root.selected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                Canvas {
                    id: magnifier
                    width: 110; height: 110
                    scale: zoomBox.width / 110
                    transformOrigin: Item.TopLeft
                    renderTarget: Canvas.Image
                    opacity: root.selected ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
                    onImageLoaded: { root.ready = true; requestPaint(); entrance.restart(); }
                    onPaint: {
                        // Once selected the color belongs to the editor, a stray repaint must not resample it.
                        if (root.selected || !root.ready || !isImageLoaded(root.captureUrl)) return;
                        let ctx = getContext("2d");
                        let px = Math.max(0, Math.min(preview.implicitWidth - 1, Math.floor(root.pointerX * preview.implicitWidth / root.width)));
                        let py = Math.max(0, Math.min(preview.implicitHeight - 1, Math.floor(root.pointerY * preview.implicitHeight / root.height)));
                        let left = Math.max(0, px - 5), top = Math.max(0, py - 5);
                        let right = Math.min(preview.implicitWidth, px + 6), bottom = Math.min(preview.implicitHeight, py + 6);
                        ctx.clearRect(0, 0, 110, 110);
                        ctx.imageSmoothingEnabled = false;
                        ctx.drawImage(root.captureUrl, left, top, right - left, bottom - top,
                                      (left - px + 5) * 10, (top - py + 5) * 10,
                                      (right - left) * 10, (bottom - top) * 10);
                        let pixel = ctx.getImageData(55, 55, 1, 1).data;
                        root.red = pixel[0]; root.green = pixel[1]; root.blue = pixel[2];
                        if (root.selectionPending) {
                            root.selectionPending = false;
                            root.selected = true;
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width / 11; height: width
                    color: "transparent"
                    border.width: root.s(1)
                    border.color: "white"
                    opacity: root.selected ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.fill: parent; anchors.margins: -root.s(1); color: "transparent"; border.width: root.s(1); border.color: "#90000000" }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 2.2 * root.swatchRipple; height: width
                    radius: width / 2
                    color: "white"
                    opacity: 0.4 * (1 - root.swatchRipple)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.alpha("black", 0.3)
                    opacity: root.selected && swatchMouse.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent
                        text: root.editing ? "\uDB80\uDD56" : "\uDB80\uDFD8"
                        color: "white"
                        font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(22)
                        scale: parent.opacity > 0 ? 1 : 0.5
                        rotation: root.editing ? 90 : 0
                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                        Behavior on rotation { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                    }
                }
                MouseArea {
                    id: swatchMouse
                    anchors.fill: parent; hoverEnabled: true
                    enabled: root.selected && !root.copying && !root.closing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleEditor()
                }
            }
            // Halo in the live color marks the swatch as the editor's source.
            Rectangle {
                anchors.centerIn: zoomBox
                width: zoomBox.width * zoomBox.scale + root.s(8); height: width
                radius: zoomBox.radius + root.s(4)
                color: "transparent"
                border.width: root.s(2); border.color: root.hexColor
                opacity: root.editProgress
                scale: 0.85 + 0.15 * root.editProgress
            }

            AddonGlassSurface {
                id: hexArea
                x: zoomBox.x + zoomBox.width + root.s(12); y: root.s(10)
                width: parent.width - x - root.s(10); height: root.s(76)
                radius: root.s(10)
                surfaceColor: hexMouse.containsMouse && root.selected ? ThemeBackend.surface0 : "transparent"
                Behavior on surfaceColor { ColorAnimation { duration: 160 } }
                Rectangle {
                    x: root.s(4); y: root.s(7); width: root.s(8); height: width; radius: width / 2
                    color: root.hexColor
                    border.width: root.s(1); border.color: Qt.alpha(ThemeBackend.text, 0.35)
                }
                Text {
                    x: root.s(18); y: root.s(3)
                    text: "HEX"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10); font.bold: true
                }
                Text {
                    x: root.s(2); y: root.s(22)
                    text: root.hexColor
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(23); font.bold: true
                }
                Text {
                    x: root.s(3); y: root.s(53)
                    text: root.selected ? "Copy HEX" : "Click to select"
                    color: root.selected ? ThemeBackend.mauve : ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: root.s(8); y: root.s(54)
                    text: "󰆏"; color: ThemeBackend.mauve
                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13)
                    opacity: root.expansion
                }
                MouseArea {
                    id: hexMouse
                    anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    enabled: root.selected && !root.copying && !root.closing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) root.copy("HEX", root.hexColor);
                        else if (mouse.button === Qt.RightButton) root.copy("HEX", root.hexColor.substring(1));
                    }
                }
            }

            Column {
                x: root.s(14); y: root.s(104) + root.s(14) * (1 - root.expansion)
                width: parent.width - root.s(28)
                spacing: root.s(8)
                opacity: root.expansion
                visible: root.expansion > 0.01
                Repeater {
                    model: [
                        { name: "RGB", value: root.rgbColor },
                        { name: "HSL", value: root.hslColor }
                    ]
                    delegate: AddonGlassSurface {
                        required property var modelData
                        width: parent.width; height: root.s(42)
                        radius: root.s(9)
                        surfaceColor: rowMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
                        scale: rowMouse.pressed ? 0.97 : 1
                        Behavior on surfaceColor { ColorAnimation { duration: 160 } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: root.s(11); anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name; color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10); font.bold: true
                        }
                        Text {
                            anchors.right: copyIcon.left; anchors.rightMargin: root.s(10); anchors.verticalCenter: parent.verticalCenter
                            text: modelData.value; color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                        }
                        Text {
                            id: copyIcon
                            anchors.right: parent.right; anchors.rightMargin: root.s(11); anchors.verticalCenter: parent.verticalCenter
                            text: "󰆏"; color: rowMouse.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
                            font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13)
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent; hoverEnabled: true
                            enabled: root.selected && !root.copying && !root.closing
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copy(modelData.name, modelData.value)
                        }
                    }
                }
            }
            // Same HSV model as the shell's draw picker: saturation/value plane + hue track.
            Item {
                id: editor
                readonly property real planeReveal: Math.max(0, Math.min(1, (root.editProgress - 0.2) / 0.8))
                readonly property real hueReveal: Math.max(0, Math.min(1, (root.editProgress - 0.4) / 0.6))
                x: root.s(14); y: root.s(200)
                width: parent.width - root.s(28); height: root.s(154)
                visible: root.editProgress > 0.01

                Rectangle {
                    id: svPlane
                    width: parent.width; height: root.s(130)
                    radius: root.s(10)
                    color: Qt.hsva(root.editHue, 1, 1, 1)
                    opacity: editor.planeReveal
                    scale: 0.94 + 0.06 * editor.planeReveal
                    transform: Translate { y: root.s(16) * (1 - editor.planeReveal) }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "white" }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: "black" }
                        }
                    }
                    Rectangle {
                        id: svKnob
                        width: root.s(svMouse.pressed ? 22 : 16); height: width
                        radius: width / 2
                        x: root.editSat * svPlane.width - width / 2
                        y: (1 - root.editVal) * svPlane.height - height / 2
                        color: root.hexColor
                        border.width: root.s(2.5); border.color: "white"
                        scale: root.editing ? 1 : 0
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                        Behavior on x { enabled: !svMouse.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: !svMouse.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on scale { SequentialAnimation { PauseAnimation { duration: 160 } NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } } }
                        Rectangle { anchors.fill: parent; anchors.margins: -root.s(1); radius: width / 2; color: "transparent"; border.width: root.s(1); border.color: "#70000000" }
                    }
                    MouseArea {
                        id: svMouse
                        property bool dragging: false
                        anchors.fill: parent
                        preventStealing: true
                        enabled: root.editing && !root.copying && !root.closing
                        cursorShape: Qt.CrossCursor
                        function update(mouse) {
                            root.setHsv(root.editHue, Math.max(0, Math.min(1, mouse.x / width)), 1 - Math.max(0, Math.min(1, mouse.y / height)));
                        }
                        onPressed: mouse => update(mouse)
                        onPositionChanged: mouse => { if (pressed) { dragging = true; update(mouse); } }
                        onReleased: dragging = false
                        onCanceled: dragging = false
                    }
                }

                Rectangle {
                    id: hueTrack
                    y: root.s(140)
                    width: parent.width; height: root.s(14)
                    radius: height / 2
                    opacity: editor.hueReveal
                    transform: Translate { y: root.s(12) * (1 - editor.hueReveal) }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ff0000" }
                        GradientStop { position: 0.166; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.5; color: "#00ffff" }
                        GradientStop { position: 0.666; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1; color: "#ff0000" }
                    }
                    Rectangle {
                        width: root.s(hueMouse.pressed ? 24 : 18); height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.editHue * hueTrack.width - width / 2
                        color: Qt.hsva(root.editHue, 1, 1, 1)
                        border.width: root.s(2.5); border.color: "white"
                        scale: root.editing ? 1 : 0
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                        Behavior on x { enabled: !hueMouse.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on scale { SequentialAnimation { PauseAnimation { duration: 240 } NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } } }
                        Rectangle { anchors.fill: parent; anchors.margins: -root.s(1); radius: width / 2; color: "transparent"; border.width: root.s(1); border.color: "#70000000" }
                    }
                    MouseArea {
                        id: hueMouse
                        property bool dragging: false
                        anchors.fill: parent
                        anchors.margins: -root.s(6)
                        preventStealing: true
                        enabled: root.editing && !root.copying && !root.closing
                        cursorShape: Qt.PointingHandCursor
                        function update(mouse) {
                            root.setHsv(Math.max(0, Math.min(1, (mouse.x - root.s(6)) / hueTrack.width)), root.editSat, root.editVal);
                        }
                        onPressed: mouse => update(mouse)
                        onPositionChanged: mouse => { if (pressed) { dragging = true; update(mouse); } }
                        onReleased: dragging = false
                        onCanceled: dragging = false
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(16); anchors.horizontalCenter: parent.horizontalCenter
                text: root.copyError !== "" ? root.copyError : root.editing ? "Drag to refine · Enter to copy · Esc to go back" : "Swatch to edit · Enter to copy · Esc to close"
                color: root.copyError !== "" ? ThemeBackend.red : ThemeBackend.subtext0
                opacity: root.expansion
                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10)
            }
        }

        // A wave fills the entire card, replaces its contents with a confirmation,
        // and contracts out together with the screen outline.
        Rectangle {
            anchors.centerIn: parent
            width: card.width * 2.4 * root.copyProgress
            height: width
            radius: width / 2
            color: Qt.alpha(ThemeBackend.green, 0.16)
            visible: root.copyProgress > 0
        }
        Column {
            anchors.centerIn: parent
            spacing: root.s(8)
            opacity: root.copyProgress
            scale: 0.8 + 0.2 * root.copyProgress
            visible: root.copyProgress > 0
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "✓"; color: ThemeBackend.green; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(32); font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.copiedFormat + " copied"; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(17); font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.hexColor; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(13) }
        }
    }

    function choose() {
        if (copying || closing || selected) return;
        selectionPending = true;
        magnifier.requestPaint();
    }

    function toggleEditor() {
        if (!selected || copying || closing) return;
        if (!editing) {
            let c = Qt.rgba(red / 255, green / 255, blue / 255, 1);
            editHue = Math.max(0, c.hsvHue); // hsvHue is -1 for greys
            editSat = c.hsvSaturation;
            editVal = c.hsvValue;
        }
        rippleAnimation.restart();
        editing = !editing;
    }

    // HSV is the source of truth while editing so hue survives fully desaturated colors.
    function setHsv(h, sat, val) {
        editHue = h; editSat = sat; editVal = val;
        let c = Qt.hsva(h, sat, val, 1);
        red = Math.round(c.r * 255);
        green = Math.round(c.g * 255);
        blue = Math.round(c.b * 255);
    }

    function copy(format, value) {
        if (copying || closing || !selected) return;
        copying = true;
        copiedFormat = format;
        copyError = "";
        clipboard.command = ["wl-copy", value];
        clipboard.running = true;
    }

    Process {
        id: clipboard
        onExited: (exitCode) => {
            if (!root.active || root.closing) return;
            if (exitCode === 0) {
                copiedAnimation.restart();
            } else {
                root.copying = false;
                root.copyError = "Could not copy. Try again.";
            }
        }
    }
}
