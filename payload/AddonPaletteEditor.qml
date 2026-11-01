import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Vibrant/Vivid accent editor: drag where each accent is sampled on the
// wallpaper. Positions are saved per wallpaper and read back by scripts/colors.py.
SettingsBlob {
    id: editor
    required property var tab
    readonly property var rootObj: tab.rootObj

    readonly property string colorMode: Config.getSetting("addonsV2ColorMode", "matugen")
    readonly property bool shown: tab.useMatugen && (colorMode === "vibrant" || colorMode === "vivid")
    readonly property string imagePath: tab.isWallpaperVideo ? Caching.getCacheDir("wallpaper") + "/current_wallpaper.png" : tab.currentWallpaperPath
    readonly property bool pointsCurrent: pointsData.image === imagePath && !!pointsData.points

    readonly property var keys: ["blue", "sapphire", "green", "teal", "yellow", "peach", "red", "maroon", "mauve", "pink"]
    readonly property var labels: ({ blue: "Primary", sapphire: "Sapphire", green: "Secondary", teal: "Teal", yellow: "Yellow", peach: "Tertiary", red: "Red", maroon: "Maroon", mauve: "Mauve", pink: "Pink" })

    property var pointsData: ({})
    property var overrides: ({})
    readonly property var imageOverrides: overrides[imagePath] || ({})
    readonly property bool hasOverrides: Object.keys(imageOverrides).length > 0
    property string selectedKey: "blue"
    // Collapsed by default: the wallpaper stage is tall.
    property bool expanded: false
    property string draggingKey: ""
    property real dragX: 0
    property real dragY: 0
    property bool pendingRegenerate: false
    property var thumbPixels: null
    property var optimistic: ({})

    // Bound to reveal, not implicitHeight: visibility feeds back into the layout that sets implicitHeight,
    // and the two bindings toggled each other in a loop that froze the shell.
    visible: reveal > 0.001
    opacity: shown ? 1 : 0
    // Progress values scale measured heights; chained height Behaviors trail each other and read as lag.
    property real reveal: shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
    implicitHeight: editorCol.implicitHeight * reveal
    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    function pointFor(key) {
        if (key === draggingKey) return { x: dragX, y: dragY, color: liveColor(dragX, dragY), manual: true };
        let p = optimistic[key] || (pointsCurrent ? pointsData.points[key] : null);
        return p || { x: 0.5, y: 0.5, color: ThemeBackend[key] || "#888888", manual: false };
    }

    // Approximates colors.py: 3x3 average on the 192px thumbnail, Vivid lift.
    function liveColor(x, y) {
        let fallback = pointsCurrent && pointsData.points[draggingKey] ? pointsData.points[draggingKey].color : "#888888";
        if (!thumbPixels) return fallback;
        let w = sampler.width, h = sampler.height;
        let cx = Math.min(w - 1, Math.max(0, Math.floor(x * w))), cy = Math.min(h - 1, Math.max(0, Math.floor(y * h)));
        let r = 0, g = 0, b = 0, n = 0;
        for (let i = Math.max(0, cx - 1); i < Math.min(w, cx + 2); i++)
            for (let j = Math.max(0, cy - 1); j < Math.min(h, cy + 2); j++) {
                let o = (j * w + i) * 4;
                r += thumbPixels[o]; g += thumbPixels[o + 1]; b += thumbPixels[o + 2]; n++;
            }
        let c = Qt.rgba(r / n / 255, g / n / 255, b / n / 255, 1);
        if (colorMode === "vivid") {
            let s = Math.min(1, c.hsvSaturation * 1.3 + (c.hsvSaturation > 0.1 ? 0.08 : 0));
            let v = Math.min(1, Math.max(0.82, c.hsvValue * 1.15));
            c = Qt.hsva(Math.max(0, c.hsvHue), s, v, 1);
        }
        return c;
    }

    function saveOverrides(entry) {
        let all = JSON.parse(JSON.stringify(overrides));
        if (Object.keys(entry).length > 0) all[imagePath] = entry; else delete all[imagePath];
        overrides = all;
        overridesFile.setText(JSON.stringify(all, null, 2));
        regenerate();
    }

    function movePoint(key, x, y) {
        let entry = JSON.parse(JSON.stringify(imageOverrides));
        entry[key] = [Math.round(x * 10000) / 10000, Math.round(y * 10000) / 10000];
        saveOverrides(entry);
    }

    function resetPoint(key) {
        let entry = JSON.parse(JSON.stringify(imageOverrides));
        delete entry[key];
        saveOverrides(entry);
    }

    function regenerate() {
        // A run already in flight for this image would swallow the request.
        if (Matugen.isRunning) { pendingRegenerate = true; return; }
        pendingRegenerate = false;
        tab.applyPreset({ name: tab.currentPreset, isMatugen: true, addonColorMode: colorMode });
    }

    Connections {
        target: Matugen
        function onGenerationFinished(success) { if (editor.pendingRegenerate) editor.regenerate(); }
    }

    FileView {
        path: Caching.stateDir + "/addons_v2_palette.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { editor.pointsData = JSON.parse(text()); editor.optimistic = {}; } catch (e) {} }
    }

    FileView {
        id: overridesFile
        path: Caching.stateDir + "/addons_v2_palette_overrides.json"
        printErrors: false
        onLoaded: { try { editor.overrides = JSON.parse(text()) || {}; } catch (e) {} }
    }

    ColumnLayout {
        id: editorCol
        Layout.fillWidth: true
        spacing: 0

        SettingsRow {
            rootObj: editor.rootObj
            // The whole header toggles the stage, not only the chevron.
            clickable: true
            onClicked: editor.expanded = !editor.expanded
            settingId: "addons_palette_editor"
            icon: "󰈊"
            title: "Wallpaper accents"
            description: "Drag a point onto the wallpaper to choose each accent. Double-click a point to restore it."
            searchKeywords: "vibrant vivid accent palette colors wallpaper pick move matugen"
            titleBadge: Component {
                Rectangle {
                    id: addonBadge
                    implicitWidth: addonBadgeText.implicitWidth + rootObj.s(12)
                    implicitHeight: rootObj.s(18)
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.mauve, 0.15)
                    border.color: Qt.alpha(ThemeBackend.mauve, 0.4)
                    border.width: 1
                    clip: true
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: addonBadgeMask }

                    Rectangle {
                        id: addonBadgeMask
                        anchors.fill: parent
                        radius: addonBadge.radius
                        color: "black"
                        visible: false
                        layer.enabled: true
                    }

                    Text {
                        id: addonBadgeText
                        anchors.centerIn: parent
                        text: "Addon"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        font.bold: true
                        color: ThemeBackend.mauve
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: badgeShimmerAnimation.restart()
                    }

                    Rectangle {
                        id: badgeShimmer
                        x: -width
                        y: -height / 4
                        width: parent.width * 0.45
                        height: parent.height * 1.5
                        rotation: 18
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.alpha(ThemeBackend.text, 0.45) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        NumberAnimation on x {
                            id: badgeShimmerAnimation
                            from: -badgeShimmer.width
                            to: badgeShimmer.parent.width + badgeShimmer.width
                            duration: 450
                            running: false
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "Applying…"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
                opacity: Matugen.isRunning ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            IconButton {
                Layout.preferredWidth: rootObj.s(32)
                Layout.preferredHeight: rootObj.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: rootObj.s(6)
                buttonIcon: "󰑓"
                iconFontSize: rootObj.s(14)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2
                enabled: editor.hasOverrides
                opacity: enabled ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: 200 } }
                onClicked: editor.saveOverrides({})
            }

            IconButton {
                Layout.preferredWidth: rootObj.s(32)
                Layout.preferredHeight: rootObj.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: rootObj.s(6)
                buttonIcon: "󰅀"
                iconFontSize: rootObj.s(14)
                accentColor: ThemeBackend.surface0
                textColor: isHoveredOrHighlighted || editor.expanded ? ThemeBackend.text : ThemeBackend.overlay2
                rotation: editor.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                onClicked: editor.expanded = !editor.expanded
            }
        }

        Item {
            id: body
            Layout.fillWidth: true
            property real openAmount: editor.expanded ? 1 : 0
            Behavior on openAmount { NumberAnimation { duration: editor.expanded ? 340 : 230; easing.type: editor.expanded ? Easing.OutQuint : Easing.OutCubic } }
            Layout.preferredHeight: bodyCol.implicitHeight * openAmount
            clip: true
            opacity: Math.min(1, openAmount * 1.8)
            visible: openAmount > 0.001

            ColumnLayout {
                id: bodyCol
                width: parent.width
                spacing: 0
                // Content glides down into the opening space rather than being uncovered in place.
                y: -rootObj.s(18) * (1 - body.openAmount)
                scale: 0.97 + 0.03 * body.openAmount
                transformOrigin: Item.Top

                Item {
                    id: stage
                    Layout.fillWidth: true
                    // Follow the wallpaper's ratio so it fills the width; the cap keeps tall images reachable.
                    Layout.preferredHeight: Math.min(rootObj.s(620), Math.max(rootObj.s(230), (width - rootObj.s(20)) / sampler.ratio + rootObj.s(20)))
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    Layout.leftMargin: rootObj.s(12)
                    Layout.rightMargin: rootObj.s(12)

                    readonly property real px: wallImage.x + (wallImage.width - wallImage.paintedWidth) / 2
                    readonly property real py: wallImage.y + (wallImage.height - wallImage.paintedHeight) / 2
                    readonly property real pw: Math.max(1, wallImage.paintedWidth)
                    readonly property real ph: Math.max(1, wallImage.paintedHeight)

                    // Hidden thumbnail used only to preview the color under a dragged point.
                    Canvas {
                        id: sampler
                        readonly property string url: editor.shown && editor.imagePath ? "file://" + editor.imagePath + "?rev=" + editor.tab.wallpaperRevision : ""
                        property real ratio: wallImage.sourceSize.height > 0 ? wallImage.sourceSize.width / wallImage.sourceSize.height : 1
                        width: ratio >= 1 ? 192 : Math.max(1, Math.round(192 * ratio))
                        height: ratio >= 1 ? Math.max(1, Math.round(192 / ratio)) : 192
                        opacity: 0
                        enabled: false
                        onUrlChanged: { editor.thumbPixels = null; if (url) loadImage(url); }
                        onImageLoaded: requestPaint()
                        onPaint: {
                            if (!url || !isImageLoaded(url)) return;
                            let ctx = getContext("2d");
                            ctx.drawImage(url, 0, 0, width, height);
                            editor.thumbPixels = ctx.getImageData(0, 0, width, height).data;
                        }
                    }

                    Rectangle { id: stageMask; anchors.fill: parent; radius: ThemeBackend.borderRadius; visible: false; layer.enabled: true }

                    Item {
                        id: stageContent
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Rectangle { anchors.fill: parent; color: ThemeBackend.crust }

                        // Blurred crop fills the letterbox so the fitted image floats on its own colors.
                        Image {
                            id: backdrop
                            anchors.fill: parent
                            source: wallImage.source
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 256
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: backdrop
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 48
                            brightness: -0.25
                            saturation: 0.15
                        }

                        Image {
                            id: wallImage
                            anchors.fill: parent
                            anchors.margins: rootObj.s(10)
                            source: editor.shown && editor.imagePath ? "file://" + editor.imagePath + "?rev=" + editor.tab.wallpaperRevision : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            cache: false
                            opacity: status === Image.Ready ? 1 : 0
                            scale: status === Image.Ready ? 1 : 0.97
                            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
                        }
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: stageContent
                        maskEnabled: true
                        maskSource: stageMask
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: wallImage.status === Image.Ready && !editor.pointsCurrent
                        text: "Generating accents…"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: stageArea
                        x: stage.px; y: stage.py; width: stage.pw; height: stage.ph
                        enabled: editor.pointsCurrent
                        hoverEnabled: true
                        preventStealing: true
                        property string hoverKey: ""
                        cursorShape: editor.draggingKey !== "" ? Qt.ClosedHandCursor : (hoverKey !== "" ? Qt.OpenHandCursor : Qt.CrossCursor)

                        function keyAt(mx, my) {
                            let hit = rootObj.s(14), best = "", bestD = hit * hit;
                            for (let k of editor.keys) {
                                let p = editor.pointFor(k), dx = p.x * width - mx, dy = p.y * height - my, d = dx * dx + dy * dy;
                                // The selected point wins when points overlap.
                                if (k === editor.selectedKey && d <= hit * hit) return k;
                                if (d < bestD) { best = k; bestD = d; }
                            }
                            return best;
                        }
                        function track(mx, my) {
                            editor.dragX = Math.min(1, Math.max(0, mx / width));
                            editor.dragY = Math.min(1, Math.max(0, my / height));
                        }

                        onPositionChanged: mouse => {
                            if (editor.draggingKey !== "") track(mouse.x, mouse.y);
                            else hoverKey = keyAt(mouse.x, mouse.y);
                        }
                        onExited: hoverKey = ""
                        onPressed: mouse => {
                            let k = keyAt(mouse.x, mouse.y);
                            if (k !== "") editor.selectedKey = k;
                            track(mouse.x, mouse.y);
                            editor.draggingKey = editor.selectedKey;
                        }
                        onReleased: {
                            let k = editor.draggingKey;
                            if (k === "") return;
                            let p = editor.pointFor(k);
                            let o = Object.assign({}, editor.optimistic);
                            o[k] = p;
                            editor.optimistic = o;
                            editor.draggingKey = "";
                            dropRipple.fire(p.x, p.y, p.color);
                            editor.movePoint(k, p.x, p.y);
                        }
                        onCanceled: editor.draggingKey = ""
                        onDoubleClicked: mouse => {
                            let k = keyAt(mouse.x, mouse.y);
                            if (k !== "" && editor.imageOverrides[k]) editor.resetPoint(k);
                        }
                    }

                    Rectangle {
                        id: dropRipple
                        property real cx: 0
                        property real cy: 0
                        function fire(x, y, c) {
                            cx = x; cy = y; color = "transparent"; border.color = c;
                            rippleAnim.restart();
                        }
                        x: stage.px + cx * stage.pw - width / 2
                        y: stage.py + cy * stage.ph - height / 2
                        width: rootObj.s(18); height: width; radius: width / 2
                        border.width: rootObj.s(2)
                        color: "transparent"
                        opacity: 0
                        ParallelAnimation {
                            id: rippleAnim
                            NumberAnimation { target: dropRipple; property: "width"; from: rootObj.s(18); to: rootObj.s(64); duration: 560; easing.type: Easing.OutCubic }
                            NumberAnimation { target: dropRipple; property: "opacity"; from: 0.9; to: 0; duration: 560; easing.type: Easing.OutQuad }
                        }
                    }

                    Repeater {
                        model: editor.keys
                        delegate: Item {
                            id: dot
                            required property string modelData
                            required property int index
                            readonly property var point: editor.pointFor(modelData)
                            readonly property bool selected: editor.selectedKey === modelData
                            readonly property bool dragging: editor.draggingKey === modelData
                            readonly property bool hovered: stageArea.hoverKey === modelData || chipHoverKey === modelData
                            readonly property string chipHoverKey: chips.hoverKey

                            width: rootObj.s(18); height: width
                            x: stage.px + point.x * stage.pw - width / 2
                            y: stage.py + point.y * stage.ph - height / 2
                            z: dragging ? 30 : selected ? 20 : hovered ? 10 : index * 0.1
                            visible: editor.pointsCurrent
                            Behavior on x { enabled: !dot.dragging; SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.25 } }
                            Behavior on y { enabled: !dot.dragging; SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.25 } }

                            property real appear: 0
                            scale: appear * (dragging ? 1.35 : selected ? 1.18 : hovered ? 1.12 : 1)
                            Behavior on scale { enabled: dot.appear === 1; NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                            SequentialAnimation {
                                running: editor.shown && editor.expanded && editor.pointsCurrent
                                PauseAnimation { duration: 40 + dot.index * 22 }
                                NumberAnimation { target: dot; property: "appear"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                            }
                            Connections {
                                target: editor
                                function onShownChanged() { if (!editor.shown) dot.appear = 0; }
                                function onExpandedChanged() { if (!editor.expanded) dot.appear = 0; }
                            }

                            // Breathing halo on the point the next press will move.
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 1.9; height: width; radius: width / 2
                                color: "transparent"
                                border.color: Qt.alpha("#ffffff", 0.7)
                                border.width: rootObj.s(1.5)
                                visible: dot.selected && !dot.dragging
                                SequentialAnimation on scale {
                                    running: dot.selected && !dot.dragging && editor.shown && editor.expanded
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.75; to: 1.05; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.05; to: 0.75; duration: 900; easing.type: Easing.InOutSine }
                                }
                                opacity: 2 - scale * 1.6
                            }

                            RectangularShadow {
                                anchors.fill: fill
                                radius: width / 2
                                blur: rootObj.s(8)
                                spread: 0
                                color: Qt.rgba(0, 0, 0, 0.55)
                            }
                            Rectangle {
                                id: fill
                                anchors.fill: parent
                                radius: width / 2
                                color: dot.point.color
                                border.color: "#ffffff"
                                border.width: rootObj.s(2.5)
                                Behavior on color { enabled: !dot.dragging; ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            }
                            // Manual points carry a small pin so they read as user choices.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: rootObj.s(2)
                                width: rootObj.s(4); height: width; radius: width / 2
                                color: "#ffffff"
                                scale: dot.point.manual && !dot.dragging ? 1 : 0
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                            }

                            // Loupe: a larger swatch lifting above the point while dragging,
                            // dropping below it when the stage's top edge would clip it.
                            Item {
                                readonly property bool below: dot.y < height + rootObj.s(10)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: below ? dot.height + rootObj.s(10) : -height - rootObj.s(10)
                                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                width: rootObj.s(64); height: rootObj.s(64) + loupeLabel.height
                                transformOrigin: below ? Item.Top : Item.Bottom
                                property real shownAmount: dot.dragging ? 1 : 0
                                Behavior on shownAmount { NumberAnimation { duration: dot.dragging ? 320 : 180; easing.type: dot.dragging ? Easing.OutBack : Easing.InCubic } }
                                scale: 0.4 + 0.6 * shownAmount
                                opacity: shownAmount
                                visible: opacity > 0.01

                                RectangularShadow {
                                    anchors.fill: loupe
                                    radius: loupe.radius
                                    blur: rootObj.s(14)
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                }
                                Rectangle {
                                    id: loupe
                                    width: rootObj.s(52); height: width; radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: dot.point.color
                                    border.color: "#ffffff"
                                    border.width: rootObj.s(3)
                                }
                                Text {
                                    id: loupeLabel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: loupe.bottom
                                    anchors.topMargin: rootObj.s(4)
                                    text: editor.labels[dot.modelData]
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(10)
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.6)
                                }
                            }
                        }
                    }
                }

                Flow {
                    id: chips
                    Layout.fillWidth: true
                    Layout.margins: rootObj.s(12)
                    spacing: rootObj.s(6)
                    property string hoverKey: ""

                    Repeater {
                        model: editor.keys
                        delegate: Rectangle {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property bool selected: editor.selectedKey === modelData
                            readonly property bool manual: !!editor.imageOverrides[modelData]
                            implicitWidth: chipRow.implicitWidth + rootObj.s(20)
                            implicitHeight: rootObj.s(28)
                            radius: height / 2
                            color: selected ? Qt.alpha(ThemeBackend.mauve, 0.18) : (chipMa.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
                            border.color: selected ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface2, 0.6)
                            border.width: 1
                            scale: chipMa.pressed ? 0.94 : 1
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: rootObj.s(6)
                                Rectangle {
                                    implicitWidth: rootObj.s(12); implicitHeight: implicitWidth; radius: implicitWidth / 2
                                    color: editor.pointFor(chip.modelData).color
                                    border.color: Qt.alpha("#ffffff", 0.5)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    text: editor.labels[chip.modelData] + (chip.manual ? " •" : "")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(11)
                                    font.weight: chip.selected ? Font.Bold : Font.Normal
                                    color: chip.selected ? ThemeBackend.text : ThemeBackend.subtext0
                                }
                            }

                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onContainsMouseChanged: chips.hoverKey = containsMouse ? chip.modelData : (chips.hoverKey === chip.modelData ? "" : chips.hoverKey)
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) { if (chip.manual) editor.resetPoint(chip.modelData); }
                                    else editor.selectedKey = chip.modelData;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
