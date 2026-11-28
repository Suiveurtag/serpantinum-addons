import QtQuick
import QtQuick.Controls.Basic
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
    property var gridData: null
    property int red: 0
    property int green: 0
    property int blue: 0
    property string copiedFormat: ""
    property string copyError: ""
    property real intro: 0
    property real outro: 0
    property real expansion: selected ? 1 : 0
    property real copyProgress: 0
    property rect copySource: Qt.rect(0, 0, 0, 0)
    property real editorStartHue: 0
    property real edgePhase: 0
    property bool editing: false
    property real editHue: 0
    property real editSat: 0
    property real editVal: 0
    property real editProgress: editing ? 1 : 0
    readonly property real editorUnfold: settle(editProgress, 0.06, 0.94)
    readonly property real copyImpact: phase(copyProgress, 0.33, 0.49) * (1 - phase(copyProgress, 0.49, 0.87))
    readonly property bool reducedMotion: !!Config.getSetting("general", {}).performance
    readonly property color swatchInk: swatchLuminance > 0.179 ? "black" : "white"
    readonly property real swatchLuminance: {
        const linear = [red, green, blue].map(channel => {
            const value = channel / 255;
            return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
    }
    function cursorScreen() {
        return Quickshell.cursorScreen ?? Quickshell.screens.find(screen => !Quickshell.env("NIRI_SOCKET") && Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0] ?? null;
    }
    property var targetScreen: cursorScreen()
    screen: targetScreen

    Behavior on expansion {
        enabled: root.active
        NumberAnimation { duration: root.reducedMotion ? 110 : 290 }
    }
    Behavior on editProgress {
        enabled: root.active
        NumberAnimation { duration: root.reducedMotion ? 110 : root.editing ? 430 : 300 }
    }
    NumberAnimation on edgePhase {
        from: 0; to: Math.PI * 2
        duration: 6400
        loops: Animation.Infinite
        running: root.active && !root.reducedMotion
    }
    NumberAnimation {
        id: entrance
        target: root; property: "intro"; to: 1
        duration: root.reducedMotion ? 110 : 235
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: dismiss
        target: root; property: "outro"; to: 1
        duration: root.reducedMotion ? 110 : 260
        onFinished: root.finishClose()
    }
    SequentialAnimation {
        id: copiedAnimation
        NumberAnimation { target: root; property: "copyProgress"; to: 1; duration: root.reducedMotion ? 110 : 420 }
        PauseAnimation { duration: 360 }
        onFinished: root.close()
    }

    function interval(progress, start, end) {
        return Math.max(0, Math.min(1, (progress - start) / (end - start)));
    }

    function phase(progress, start, end) {
        const t = interval(progress, start, end);
        return t * t * (3 - 2 * t);
    }

    function settle(progress, start, end) {
        const t = interval(progress, start, end);
        const remaining = 1 - t;
        // Keep the overshoot with zero velocity at both ends.
        return t * t * (3 - 2 * t + 8 * t * remaining * remaining);
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

    function openFromImage(path, monitor) {
        if (active || opening || capture.running) return false;
        open();
        captureTimer.stop();
        targetScreen = Quickshell.screens.find(screen => screen.name === monitor) ?? cursorScreen();
        opening = false;
        capturePath = path;
        active = true;
        captureUrl = "file://" + path;
        preview.source = captureUrl;
        return true;
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
        opacity: 1 - root.phase(root.outro, 0.38, 1)
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

    Shortcut { sequence: "Escape"; enabled: root.active; onActivated: { if (root.editing && !root.copying && !root.closing) root.toggleEditor(); else root.close(); } }
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
        anchors.margins: root.s(root.reducedMotion ? 3 : 3 + (1 - root.intro) * 12)
        opacity: root.intro * (1 - root.outro)
        readonly property real echo: root.reducedMotion ? 0 : root.phase(root.copyProgress, 0.55, 0.81)
            * (1 - root.phase(root.copyProgress, 0.81, 1))
        readonly property real thickness: root.s(3.5)
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
            opacity: 0.75 + Math.sin(root.edgePhase * 2) * 0.10 + 0.15 * edgeFrame.echo
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
        id: backdropInput
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.ready && !root.copying && !root.closing
        cursorShape: root.selected ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: mouse => {
            if (root.selected || root.selectionPending) return;
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            magnifier.requestPaint();
        }
        onClicked: mouse => {
            if (root.selected) {
                const point = result.mapFromItem(backdropInput, mouse.x, mouse.y);
                if (Math.hypot(point.x - result.width / 2, point.y - result.height / 2) <= result.width / 2) return;
                root.editing = false;
                root.selected = false;
                root.copyError = "";
                root.pointerX = mouse.x;
                root.pointerY = mouse.y;
                magnifier.requestPaint();
                return;
            }
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            root.choose();
        }
    }

                Canvas {
                    id: magnifier
                    width: 110; height: 110
                    x: 0; y: 0
                    transformOrigin: Item.TopLeft
                    renderTarget: Canvas.Image
                    opacity: 0.001
                    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
                    onImageLoaded: { root.ready = true; requestPaint(); entrance.restart(); }
                    onPaint: {
                        // Once selected the color belongs to the editor, a stray repaint must not resample it.
                        if (root.selected || root.closing || !root.ready || !isImageLoaded(root.captureUrl)) return;
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
                        let data = ctx.getImageData(0, 0, 110, 110).data;
                        let grid = [];
                        for (let y = 0; y < 11; y++) for (let x = 0; x < 11; x++) {
                            let i = ((y * 10 + 5) * 110 + x * 10 + 5) * 4;
                            grid.push(data[i], data[i + 1], data[i + 2], data[i + 3]);
                        }
                        root.gridData = grid;
                        loupeCanvas.requestPaint();
                        let pixel = ctx.getImageData(55, 55, 1, 1).data;
                        root.red = pixel[0]; root.green = pixel[1]; root.blue = pixel[2];
                        if (root.selectionPending) {
                            const color = Qt.rgba(root.red / 255, root.green / 255, root.blue / 255, 1);
                            root.editHue = Math.max(0, color.hsvHue);
                            root.editSat = color.hsvSaturation;
                            root.editVal = color.hsvValue;
                            root.selectionPending = false;
                            root.selected = true;
                        }
                    }
                }

    Item {
        id: loupeContainer
        z: 25
        readonly property real loupeSize: root.s(134)
        readonly property real resultSize: root.s(250)
        readonly property real innerSize: resultSize * (1 - root.s(8) / loupeSize)
        readonly property real margin: resultSize / 2 + root.s(16)
        readonly property real targetX: Math.max(margin, Math.min(root.width - margin, root.pointerX))
        readonly property real targetY: Math.max(margin, Math.min(root.height - margin, root.pointerY))
        readonly property real grow: root.settle(root.expansion, 0.09, 0.98)
        readonly property real release: root.phase(root.outro, 0.12, 1)
        readonly property real travel: root.reducedMotion ? Number(root.selected) : root.phase(root.expansion, 0.09, 0.76) * (1 - release)
        readonly property real press: root.phase(root.expansion, 0, 0.14) * (1 - root.phase(root.expansion, 0.14, 0.38))
        readonly property real surfaceMix: root.phase(root.expansion, 0.22, 0.85)

        visible: root.active && root.ready
        opacity: root.intro * (1 - root.phase(root.outro, 0.14, 0.96))
        scale: root.reducedMotion ? (root.selected ? 1 : loupeSize / resultSize)
            : (loupeSize / resultSize + (1 - loupeSize / resultSize) * grow)
                * (1 - 0.055 * press - 0.57 * release - 0.08 * (1 - root.intro)
                    + 0.045 * root.editorUnfold * (1 - root.copyProgress) + 0.055 * root.copyImpact)
        x: root.pointerX + (targetX - root.pointerX) * travel - width / 2
        y: root.pointerY + (targetY - root.pointerY) * travel - height / 2
        width: resultSize
        height: width

        MultiEffect {
            source: loupeFrame
            anchors.fill: loupeFrame
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.52
            shadowBlur: 0.85
            shadowVerticalOffset: root.s(6)
        }

        // The expanded disc turns into Liquid Glass over the frozen capture.
        GlassFill {
            id: loupeGlass
            anchors.fill: parent
            radius: width / 2
            backdropOverride: frozenBackdrop
            allowed: loupeContainer.surfaceMix > 0
            opacity: loupeContainer.surfaceMix
            tintColor: ThemeBackend.base
            tintStrength: 1
            frost: 2.6
            shadow: 0.35
            pulse: root.copyImpact
        }

        Rectangle {
            id: loupeFrame
            anchors.fill: parent
            radius: width / 2
            // On glass, a base veil keeps the labels readable over any capture.
            color: !loupeGlass.active ? Qt.tint(root.hexColor, Qt.alpha(ThemeBackend.base, loupeContainer.surfaceMix))
                : Qt.tint(Qt.alpha(root.hexColor, 1 - loupeContainer.surfaceMix), Qt.alpha(ThemeBackend.base, 0.45 * loupeContainer.surfaceMix))
            border.width: root.s(1.3) / loupeContainer.scale
            border.color: Qt.tint(Qt.alpha(root.swatchInk, 0.30), Qt.alpha(root.hexColor, loupeContainer.surfaceMix))

            Canvas {
                id: loupeCanvas
                anchors.centerIn: parent
                width: loupeContainer.innerSize
                height: loupeContainer.innerSize
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                opacity: 1 - root.phase(root.expansion, 0.10, 0.62)
                visible: opacity > 0

                onPaint: {
                    let ctx = getContext("2d");
                    let w = width;
                    let h = height;
                    let r = w / 2;
                    let gs = 11;
                    let half = 5;
                    let data = root.gridData;

                    ctx.clearRect(0, 0, w, h);
                    ctx.save();
                    ctx.beginPath();
                    ctx.arc(r, r, r, 0, Math.PI * 2);
                    ctx.clip();

                    if (data && data.length >= gs * gs * 4) {
                        let cell = w / gs;
                        for (let row = 0; row < gs; row++) {
                            let y0 = Math.floor(row * cell);
                            let y1 = Math.ceil((row + 1) * cell);
                            for (let col = 0; col < gs; col++) {
                                let x0 = Math.floor(col * cell);
                                let x1 = Math.ceil((col + 1) * cell);
                                let idx = (row * gs + col) * 4;
                                ctx.fillStyle = "rgb(" + data[idx] + "," + data[idx + 1] + "," + data[idx + 2] + ")";
                                ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
                            }
                        }

                        ctx.lineWidth = 1;
                        ctx.strokeStyle = ((0.2126 * root.red + 0.7152 * root.green + 0.0722 * root.blue) / 255) > 0.55 ? "rgba(0, 0, 0, 0.14)" : "rgba(255, 255, 255, 0.12)";
                        for (let i = 1; i < gs; i++) {
                            let pos = Math.round(i * cell) + 0.5;
                            ctx.beginPath();
                            ctx.moveTo(pos, 0);
                            ctx.lineTo(pos, h);
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(0, pos);
                            ctx.lineTo(w, pos);
                            ctx.stroke();
                        }

                        let cx = Math.floor(half * cell);
                        let cy = Math.floor(half * cell);
                        let cw = Math.ceil((half + 1) * cell) - cx;
                        let ch = Math.ceil((half + 1) * cell) - cy;

                        ctx.lineWidth = Math.max(1.5, root.s(1.5));
                        ctx.strokeStyle = "rgba(0, 0, 0, 0.85)";
                        ctx.strokeRect(cx - 0.5, cy - 0.5, cw + 1, ch + 1);

                        ctx.lineWidth = Math.max(1.5, root.s(1.5));
                        ctx.strokeStyle = "rgba(255, 255, 255, 0.96)";
                        ctx.strokeRect(cx + 1, cy + 1, cw - 2, ch - 2);
                    }

                    ctx.restore();

                    ctx.beginPath();
                    ctx.arc(r, r, r - 0.75, 0, Math.PI * 2);
                    ctx.lineWidth = Math.max(1.2, root.s(1.2));
                    ctx.strokeStyle = ((0.2126 * root.red + 0.7152 * root.green + 0.0722 * root.blue) / 255) > 0.62 ? "rgba(0, 0, 0, 0.25)" : "rgba(255, 255, 255, 0.55)";
                    ctx.stroke();
                }
            }
        }
    }

    AddonGlassSurface {
        id: colorPreview
        readonly property real gap: root.s(12)
        width: root.s(160); height: root.s(46)
        x: Math.max(root.s(12), Math.min(root.width - width - root.s(12), root.pointerX - width / 2))
        y: root.pointerY + root.s(67) + gap + height < root.height ? root.pointerY + root.s(67) + gap : root.pointerY - root.s(67) - gap - height
        radius: height / 2
        surfaceColor: ThemeBackend.base
        border.width: root.s(1)
        border.color: Qt.alpha(ThemeBackend.text, 0.22)
        visible: root.active && root.ready && opacity > 0
        opacity: root.intro * (1 - root.outro) * (1 - root.phase(root.expansion, 0.02, 0.52))
        transform: Translate {
            y: root.reducedMotion ? 0 : (colorPreview.y > root.pointerY ? -1 : 1)
                * root.s(14) * root.phase(root.expansion, 0, 0.52)
        }
        Rectangle {
            x: root.s(9); anchors.verticalCenter: parent.verticalCenter
            width: root.s(28); height: width; radius: width / 2
            color: root.hexColor; border.width: root.s(1); border.color: Qt.alpha(ThemeBackend.text, 0.4)
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: root.s(46); anchors.verticalCenter: parent.verticalCenter
            text: root.hexColor; color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(16); font.bold: true
        }
    }

    component PickerButton: Button {
        id: control
        property color fill: "transparent"
        property color ink: ThemeBackend.text
        property bool glass: false
        hoverEnabled: true
        scale: !root.reducedMotion && down ? 0.93 : 1
        Behavior on scale {
            NumberAnimation { duration: control.down ? 95 : 200; easing.type: control.down ? Easing.OutCubic : Easing.OutBack }
        }
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.s(12)
        padding: 0
        contentItem: Text {
            text: control.text
            color: control.ink
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            readonly property color shade: control.down ? Qt.tint(control.fill, Qt.alpha(ThemeBackend.text, 0.22))
                : control.hovered ? Qt.tint(control.fill, Qt.alpha(ThemeBackend.text, 0.12)) : control.fill
            radius: height / 2
            color: buttonGlass.active ? "transparent" : shade
            GlassFill {
                id: buttonGlass
                anchors.fill: parent
                radius: parent.radius
                backdropOverride: frozenBackdrop
                allowed: control.glass
                // Sits on the glass disc: use the nested, see-through material.
                forceClear: true
                tintColor: parent.shade
                press: control.down ? 1 : 0
                pulse: control.hovered ? 0.12 : 0
            }
            border.width: control.activeFocus ? root.s(2) : 0
            border.color: ThemeBackend.text
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    Item {
        id: result
        z: 26
        anchors.centerIn: loupeContainer
        width: loupeContainer.resultSize
        height: width
        readonly property bool interactive: root.selected && !root.copying && !root.closing
        readonly property real detailsReveal: root.phase(root.expansion, 0.48, 0.94)
        readonly property real controlsOpacity: 1 - root.phase(root.copyProgress, 0.04, 0.44)
        readonly property real overviewOpacity: (1 - root.phase(root.editProgress, 0.05, 0.48)) * controlsOpacity
        readonly property real editorOpacity: root.phase(root.editProgress, 0.10, 0.61) * controlsOpacity
        visible: loupeContainer.visible && root.expansion > 0
        opacity: loupeContainer.opacity
        scale: loupeContainer.scale

        PickerButton {
            readonly property real settle: root.reducedMotion ? 1 : root.phase(root.expansion, 0.22, 0.91)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - height / 2 - root.s(59) * settle
            width: root.s(66 + 158 * (1 - settle)); height: width
            fill: root.hexColor
            ink: Qt.alpha(root.swatchInk, root.phase(root.expansion, 0.64, 0.94))
            text: "Edit"
            font.bold: true
            opacity: root.phase(root.expansion, 0.23, 0.51)
                * (1 - root.phase(root.editProgress, 0.10, 0.33)) * result.controlsOpacity
            visible: opacity > 0
            enabled: result.interactive && !root.editing && result.detailsReveal > 0.85
            onClicked: root.toggleEditor()
        }

        Item {
            anchors.fill: parent
            opacity: result.detailsReveal * result.overviewOpacity
            visible: opacity > 0
            enabled: result.interactive && !root.editing && result.detailsReveal > 0.85
            transform: Translate {
                y: root.reducedMotion ? 0 : root.s(10) * (1 - result.detailsReveal)
                    + root.s(18) * root.phase(root.editProgress, 0, 0.52)
                    + root.s(9) * root.phase(root.copyProgress, 0, 0.46)
            }

            PickerButton {
                id: overviewHex
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.s(105)
                width: root.s(173); height: root.s(41)
                fill: ThemeBackend.surface0
                glass: true
                text: root.hexColor + "  󰆏"
                Accessible.name: "Copy HEX " + root.hexColor
                font.pixelSize: root.s(20)
                font.bold: true
                onClicked: root.copy("HEX", root.hexColor, overviewHex)
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.copy("HEX", root.hexColor.substring(1), overviewHex)
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.s(153)
                opacity: root.phase(root.expansion, 0.57, 1)
                spacing: root.s(1)

                Repeater {
                    model: [
                        { format: "RGB", value: root.rgbColor },
                        { format: "HSL", value: root.hslColor }
                    ]
                    delegate: PickerButton {
                        id: formatButton
                        required property var modelData
                        width: root.s(178); height: root.s(29)
                        Accessible.name: "Copy " + modelData.format + " " + modelData.value
                        contentItem: Item {
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: root.s(9)
                                anchors.verticalCenter: parent.verticalCenter
                                text: formatButton.modelData.format
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(10)
                                font.bold: true
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: root.s(9)
                                anchors.verticalCenter: parent.verticalCenter
                                text: formatButton.modelData.value
                                color: ThemeBackend.text
                                font: formatButton.font
                            }
                        }
                        onClicked: root.copy(modelData.format, modelData.value, formatButton)
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: result.editorOpacity
            visible: opacity > 0
            enabled: result.interactive && root.editing
            transform: Translate {
                y: root.reducedMotion ? 0 : -root.s(18) * root.phase(root.copyProgress, 0, 0.48)
            }

            Item {
                id: hueRing
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.s(24)
                width: root.s(166); height: width
                readonly property real sweep: root.reducedMotion ? 1 : root.phase(root.editProgress, 0.15, 0.88)
                scale: root.reducedMotion ? 1 : 0.37 + 0.63 * root.editorUnfold
                transform: Translate { y: root.reducedMotion ? 0 : -root.s(41) * (1 - root.editorUnfold) }
                readonly property real ringRadius: width / 2 - root.s(9)
                readonly property real hueAngle: root.editHue * Math.PI * 2
                containmentMask: QtObject {
                    function contains(point: point): bool {
                        const distance = Math.hypot(point.x - hueRing.width / 2, point.y - hueRing.height / 2);
                        return Math.abs(distance - hueRing.ringRadius) <= root.s(12);
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - root.s(6); height: width
                    radius: width / 2
                    color: root.hexColor
                    opacity: root.reducedMotion ? 0 : 1 - root.phase(root.editProgress, 0.20, 0.59)
                }

                Canvas {
                    id: spectrum
                    readonly property var colors: Array.from({ length: 180 }, (_, index) => Qt.hsva(index / 180, 1, 1, 1))
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onAvailableChanged: { if (available) requestPaint(); }
                    Connections {
                        target: hueRing
                        function onSweepChanged() { spectrum.requestPaint(); }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        const center = width / 2;
                        const count = colors.length;
                        const step = Math.PI * 2 / count;
                        const start = hueRing.sweep === 1 ? 0
                            : root.editorStartHue * Math.PI * 2 - Math.PI * hueRing.sweep;
                        const end = start + Math.PI * 2 * hueRing.sweep;
                        const first = Math.floor(start / step);
                        const last = Math.ceil(end / step);
                        ctx.clearRect(0, 0, width, height);
                        ctx.lineWidth = root.s(12);
                        for (let i = first; i < last; ++i) {
                            const from = Math.max(start, i * step - 0.01);
                            const to = Math.min(end, (i + 1) * step + 0.01);
                            ctx.beginPath();
                            ctx.strokeStyle = colors[(i % count + count) % count];
                            ctx.arc(center, center, hueRing.ringRadius, from, to);
                            ctx.stroke();
                        }
                    }
                }

                Repeater {
                    model: root.reducedMotion ? 0 : [-1, 1]
                    delegate: Rectangle {
                        required property int modelData
                        readonly property real angle: root.editorStartHue * Math.PI * 2 + modelData * Math.PI * hueRing.sweep
                        width: root.s(12); height: width
                        radius: width / 2
                        x: hueRing.width / 2 + Math.cos(angle) * hueRing.ringRadius - width / 2
                        y: hueRing.height / 2 + Math.sin(angle) * hueRing.ringRadius - height / 2
                        color: Qt.hsva((angle / (Math.PI * 2) + 1) % 1, 1, 1, 1)
                        border.width: root.s(1.5)
                        border.color: Qt.alpha("white", 0.72)
                        opacity: root.phase(hueRing.sweep, 0, 0.15) * (1 - root.phase(hueRing.sweep, 0.84, 1))
                        visible: opacity > 0
                    }
                }

                PickerKnob {
                    x: hueRing.width / 2 + Math.cos(hueRing.hueAngle) * hueRing.ringRadius - width / 2
                    y: hueRing.height / 2 + Math.sin(hueRing.hueAngle) * hueRing.ringRadius - height / 2
                    color: Qt.hsva(root.editHue, 1, 1, 1)
                    opacity: root.phase(root.editProgress, 0.47, 0.82)
                }

                MouseArea {
                    anchors.fill: parent
                    containmentMask: hueRing.containmentMask
                    enabled: root.editProgress >= 0.83
                    cursorShape: Qt.CrossCursor
                    function update(mouse) {
                        const angle = Math.atan2(mouse.y - height / 2, mouse.x - width / 2);
                        root.setHsv((angle / (2 * Math.PI) + 1) % 1, root.editSat, root.editVal);
                    }
                    onPressed: mouse => update(mouse)
                    onPositionChanged: mouse => { if (pressed) update(mouse); }
                }

                Rectangle {
                    id: svPlane
                    anchors.centerIn: parent
                    readonly property real open: root.settle(root.editProgress, 0.34, 0.98)
                    opacity: root.phase(root.editProgress, 0.36, 0.79)
                    scale: root.reducedMotion ? 1 : 0.56 + 0.44 * open
                    rotation: root.reducedMotion ? 0 : -26 * (1 - open)
                    width: root.s(88); height: width
                    radius: root.reducedMotion ? root.s(7) : root.s(30 - 23 * root.phase(root.editProgress, 0.34, 0.89))
                    color: Qt.hsva(root.editHue, 1, 1, 1)
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
                    PickerKnob {
                        x: root.editSat * svPlane.width - width / 2
                        y: (1 - root.editVal) * svPlane.height - height / 2
                        color: root.hexColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.editProgress >= 0.83
                        cursorShape: Qt.CrossCursor
                        function update(mouse) {
                            root.setHsv(root.editHue, Math.max(0, Math.min(1, mouse.x / width)),
                                1 - Math.max(0, Math.min(1, mouse.y / height)));
                        }
                        onPressed: mouse => update(mouse)
                        onPositionChanged: mouse => { if (pressed) update(mouse); }
                    }
                }
            }

            Row {
                id: editorActions
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.s(198)
                opacity: root.phase(root.editProgress, 0.56, 0.96)
                transform: Translate {
                    y: root.reducedMotion ? 0 : root.s(13) * (1 - root.settle(root.editProgress, 0.55, 1))
                }
                spacing: root.s(4)
                PickerButton {
                    width: root.s(43); height: root.s(31)
                    text: "Back"
                    fill: ThemeBackend.liquidGlass ? ThemeBackend.surface0 : "transparent"
                    glass: true
                    onClicked: root.toggleEditor()
                }
                PickerButton {
                    id: editorHex
                    width: root.s(99); height: root.s(31)
                    fill: root.hexColor
                    ink: root.swatchInk
                    text: root.hexColor + "  󰆏"
                    Accessible.name: "Copy HEX " + root.hexColor
                    onClicked: root.copy("HEX", root.hexColor, editorHex)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: root.copy("HEX", root.hexColor.substring(1), editorHex)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.s(root.editing ? 231 : 216)
            visible: root.copyError !== ""
            text: root.copyError
            color: ThemeBackend.red
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(10)
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.tint(ThemeBackend.text, Qt.alpha(root.hexColor, 0.63))
            opacity: root.reducedMotion ? 0 : 0.14 * root.copyImpact
            visible: opacity > 0
        }

        Shape {
            id: copyRipple
            readonly property real sweep: root.phase(root.copyProgress, 0.35, 0.94)
            readonly property real ringRadius: root.s(36 + 84 * sweep)
            readonly property real centerY: root.s(91 + 34 * sweep)
            anchors.fill: parent
            antialiasing: true
            opacity: root.reducedMotion ? 0 : root.phase(root.copyProgress, 0.35, 0.48)
                * (1 - root.phase(root.copyProgress, 0.59, 0.98))
            visible: opacity > 0

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.tint(ThemeBackend.text, Qt.alpha(root.hexColor, 0.68))
                strokeWidth: root.s(2.6 - 1.2 * copyRipple.sweep)
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: copyRipple.width / 2; centerY: copyRipple.centerY
                    radiusX: copyRipple.ringRadius; radiusY: radiusX
                    startAngle: -98 + 86 * copyRipple.sweep
                    sweepAngle: 80 + 94 * copyRipple.sweep
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(ThemeBackend.text, 0.62)
                strokeWidth: root.s(1)
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: copyRipple.width / 2; centerY: copyRipple.centerY
                    radiusX: copyRipple.ringRadius; radiusY: radiusX
                    startAngle: 82 + 86 * copyRipple.sweep
                    sweepAngle: 56 + 80 * copyRipple.sweep
                }
            }
        }

        Rectangle {
            id: copyBadge
            readonly property real arrival: root.reducedMotion ? 1 : root.settle(root.copyProgress, 0, 0.57)
            readonly property real reshape: root.reducedMotion ? 1 : root.phase(root.copyProgress, 0, 0.49)
            readonly property real curve: Math.sin(Math.PI * reshape)
            readonly property bool fromBelow: root.copySource.y > root.s(90)
            x: (root.copySource.x + (parent.width / 2 - root.copySource.x) * arrival)
                + root.s(fromBelow ? 19 : -19) * curve - width / 2
            y: root.copySource.y + (root.s(90) - root.copySource.y) * arrival - height / 2
            width: root.s(58) + (Math.min(root.copySource.width, root.s(118)) - root.s(58)) * (1 - reshape)
            height: root.s(58) + (root.copySource.height - root.s(58)) * (1 - reshape)
            scale: root.reducedMotion ? 1 : 1 + 0.12 * root.copyImpact
            rotation: root.reducedMotion ? 0 : (fromBelow ? -21 : 21) * curve
            radius: Math.min(width, height) / 2
            color: root.hexColor
            border.width: root.s(1)
            border.color: Qt.alpha(root.swatchInk, 0.24)
            opacity: root.phase(root.copyProgress, 0, 0.29)
            visible: opacity > 0

            Shape {
                id: checkmark
                readonly property real downstroke: root.phase(root.copyProgress, 0.39, 0.55)
                readonly property real upstroke: root.phase(root.copyProgress, 0.53, 0.78)
                anchors.centerIn: parent
                width: root.s(30)
                height: width
                antialiasing: true
                visible: downstroke > 0
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.swatchInk
                    strokeWidth: root.s(2.8)
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: root.s(5); startY: root.s(15)
                    PathLine {
                        x: root.s(5 + 7 * checkmark.downstroke)
                        y: root.s(15 + 7 * checkmark.downstroke)
                    }
                    PathLine {
                        x: root.s(5 + 7 * checkmark.downstroke + 13 * checkmark.upstroke)
                        y: root.s(15 + 7 * checkmark.downstroke - 14 * checkmark.upstroke)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.s(132)
            text: root.copiedFormat + " copied"
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(17)
            font.bold: true
            opacity: root.phase(root.copyProgress, 0.49, 0.92)
            visible: opacity > 0
            transform: Translate {
                y: root.reducedMotion ? 0 : root.s(12) * (1 - root.settle(root.copyProgress, 0.48, 0.98))
            }
        }
    }

    component PickerKnob: Rectangle {
        width: root.s(14); height: width; radius: width / 2
        border.width: root.s(2)
        border.color: "white"
        Rectangle {
            anchors.fill: parent; anchors.margins: -root.s(1)
            radius: width / 2
            color: "transparent"
            border.color: "#99000000"
        }
    }

    function choose() {
        if (!ready || copying || closing || selected || selectionPending) return;
        selectionPending = true;
        magnifier.requestPaint();
    }

    function toggleEditor() {
        if (!selected || copying || closing) return;
        if (editProgress <= 0 || editProgress >= 1) editorStartHue = editHue;
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

    function copy(format, value, source) {
        if (copying || closing || !selected || clipboard.running) return;
        const control = source ?? (editing ? editorHex : overviewHex);
        const center = control.mapToItem(result, control.width / 2, control.height / 2);
        copySource = Qt.rect(center.x, center.y, control.width, control.height);
        copying = true;
        copiedFormat = format;
        copyError = "";
        clipboard.command = ["wl-copy", value];
        clipboard.running = true;
    }

    Process {
        id: clipboard
        onExited: (exitCode) => {
            if (!root.active || root.closing || !root.copying) return;
            if (exitCode === 0) {
                copiedAnimation.restart();
            } else {
                root.copying = false;
                root.copyError = "Copy failed. Retry.";
            }
        }
    }
}
