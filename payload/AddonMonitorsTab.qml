import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    function s(value) { return rootObj.s(value); }
    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/control.py"
    property string errorMessage: ""
    readonly property color text: ThemeBackend.text
    readonly property color crust: ThemeBackend.crust
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color surface1: ThemeBackend.surface1
    readonly property color surface2: ThemeBackend.surface2
    readonly property color base: ThemeBackend.base
    readonly property color mantle: ThemeBackend.mantle
    readonly property color surface0: ThemeBackend.surface0
    readonly property color overlay0: ThemeBackend.subtext0
    readonly property color peach: ThemeBackend.peach
    readonly property color green: ThemeBackend.green
    readonly property color red: ThemeBackend.red
    readonly property color mauve: ThemeBackend.mauve
    readonly property color pink: ThemeBackend.pink
    readonly property color blue: ThemeBackend.blue
    readonly property color teal: ThemeBackend.teal
    readonly property color yellow: ThemeBackend.yellow
    readonly property color sapphire: ThemeBackend.sapphire
    readonly property color sky: ThemeBackend.sapphire
    readonly property color lavender: ThemeBackend.mauve
    readonly property color flamingo: ThemeBackend.pink
    property color monSelectedResAccent: mauve
    property color monSelectedRateAccent: blue
    property int monChangeTrigger: 0
    property var monResAccentColors: [root.pink, root.mauve, root.blue, root.teal, root.yellow, root.peach, root.green, root.red, root.sapphire, root.sky, root.lavender, root.flamingo]

    function getResLabel(w, h) {
        if (w === 7680 && h === 4320) return "8K UHD";
        if (w === 5120 && h === 2880) return "5K";
        if (w === 5120 && h === 1440) return "DQHD";
        if (w === 4096 && h === 2160) return "DCI 4K";
        if (w === 3840 && h === 2160) return "4K UHD";
        if (w === 3840 && h === 1600) return "UW4K";
        if (w === 3440 && h === 1440) return "UWQHD";
        if (w === 2560 && h === 1440) return "QHD";
        if (w === 2560 && h === 1080) return "UWFHD";
        if (w === 1920 && h === 1200) return "WUXGA";
        if (w === 1920 && h === 1080) return "FHD";
        if (w === 1680 && h === 1050) return "WSXGA+";
        if (w === 1600 && h === 900)  return "HD+";
        if (w === 1440 && h === 900)  return "WXGA+";
        if (w === 1366 && h === 768)  return "FWXGA";
        if (w === 1280 && h === 1024) return "SXGA";
        if (w === 1280 && h === 800)  return "WXGA";
        if (w === 1280 && h === 720)  return "HD";
        if (w === 1024 && h === 768)  return "XGA";
        if (w === 800  && h === 600)  return "SVGA";
        return w + "×" + h;
    }
    property var monAvailableResolutions: {
        let _ = monChangeTrigger + modelState.monActiveEditIndex;
        if (modelState.monitorsModel.count === 0) return [];
        try {
            let modes = JSON.parse(modelState.monitorsModel.get(modelState.monActiveEditIndex).availableModes || "[]");
            let seen = {}, list = [];
            for (let m of modes) {
                let match = m.match(/^(\d+)x(\d+)@/);
                if (!match) continue;
                let key = match[1] + "x" + match[2];
                if (!seen[key]) { seen[key] = true; list.push({w: parseInt(match[1]), h: parseInt(match[2])}); }
            }
            list.sort((a, b) => (b.w * b.h) - (a.w * a.h));
            return list;
        } catch(e) { return []; }
    }
    property var monAvailableRates: {
        let _ = monChangeTrigger + modelState.monActiveEditIndex;
        if (modelState.monitorsModel.count === 0) return [];
        try {
            let mon = modelState.monitorsModel.get(modelState.monActiveEditIndex);
            let modes = JSON.parse(mon.availableModes || "[]");
            let rates = [], seen = {};
            let prefix = Math.round(mon.resW) + "x" + Math.round(mon.resH) + "@";
            for (let m of modes) {
                if (m.startsWith(prefix)) {
                    let r = parseFloat(m.slice(prefix.length).replace("Hz", ""));
                    if (!isNaN(r) && !seen[r]) { seen[r] = true; rates.push(r); }
                }
            }
            rates.sort((a,b) => a-b);
            return rates;
        } catch(e) { return []; }
    }
    property int monCurrentTransform: {
        let _ = monChangeTrigger;
        return modelState.monitorsModel.count > 0 ? modelState.monitorsModel.get(modelState.monActiveEditIndex).transform : 0;
    }
    property bool monCurrentIsPortrait: monCurrentTransform % 2 === 1
    property real monCurrentSimW: {
        if (modelState.monitorsModel.count === 0) return 1920;
        let mon = modelState.monitorsModel.get(modelState.monActiveEditIndex);
        return monCurrentIsPortrait ? mon.resH : mon.resW;
    }
    property real monCurrentSimH: {
        if (modelState.monitorsModel.count === 0) return 1080;
        let mon = modelState.monitorsModel.get(modelState.monActiveEditIndex);
        return monCurrentIsPortrait ? mon.resW : mon.resH;
    }

    property var selected: modelState.monitorsModel.count ? modelState.monitorsModel.get(modelState.monActiveEditIndex) : null
    function loadData(data) {
        monitorList.clear();
        for (let m of data) { let modes = m.availableModes || []; let current = modes.find(v => v.startsWith(m.width + "x" + m.height + "@") && Math.abs(parseFloat(v.split("@")[1]) - m.refreshRate) < 0.01); monitorList.append({name: m.name, resW: m.width, resH: m.height, rate: String(m.refreshRate), sysScale: m.scale, transform: m.transform, uiX: m.x * modelState.monUiScale, uiY: m.y * modelState.monUiScale, mode: current || m.width + "x" + m.height + "@" + m.refreshRate + "Hz", availableModes: JSON.stringify(modes)}); }
        modelState.monActiveEditIndex = Math.min(modelState.monActiveEditIndex, Math.max(0, monitorList.count - 1));
        root.monChangeTrigger++;
    }
    function updateSelected(key, value) { monitorList.setProperty(modelState.monActiveEditIndex, key, value); root.monChangeTrigger++; }
    function selectMode(value) {
        let parts = value.match(/^(\d+)x(\d+)@([\d.]+)/);
        if (!parts) return;
        updateSelected("resW", Number(parts[1])); updateSelected("resH", Number(parts[2])); updateSelected("rate", parts[3]); updateSelected("mode", value);
    }
    function save() {
        if (worker.running) return;
        let rows = [];
        for (let i = 0; i < monitorList.count; i++) {
            let m = monitorList.get(i);
            let modes = JSON.parse(m.availableModes);
            let mode = modes.find(v => v.startsWith(m.resW + "x" + m.resH + "@") && Math.abs(parseFloat(v.split("@")[1]) - parseFloat(m.rate)) < 0.01) || m.mode;
            if (modes.indexOf(mode) === -1) mode = modes.find(v => v.startsWith(m.resW + "x" + m.resH + "@") && Math.abs(parseFloat(v.split("@")[1]) - parseFloat(m.rate)) < 0.6) || mode;
            rows.push({name: m.name, mode: mode, x: Math.round(m.uiX / modelState.monUiScale), y: Math.round(m.uiY / modelState.monUiScale), scale: m.sysScale, transform: m.transform});
        }
        worker.command = ["python3", backend, "save-monitors", JSON.stringify(rows)]; worker.running = true;
    }
    ListModel { id: monitorList }
    Timer { id: layoutUpdate; interval: 10; onTriggered: root.monChangeTrigger++ }
    QtObject {
        id: modelState
        property var monDelayedLayoutUpdate: layoutUpdate
        property var monitorsModel: monitorList
        property real monUiScale: 0.1
        property int monActiveEditIndex: 0
    function monIsOverlapping(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function monIsOverlappingAny(x, y, w, h, skipIdx) {
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === skipIdx) continue;
            let m = monitorsModel.get(i);
            let portrait = m.transform % 2 === 1;
            let mw = (portrait ? m.resH : m.resW) / m.sysScale * monUiScale;
            let mh = (portrait ? m.resW : m.resH) / m.sysScale * monUiScale;
            if (monIsOverlapping(x, y, w, h, m.uiX, m.uiY, mw, mh)) return true;
        }
        return false;
    }

    function monGetPerimeterSnap(px, py, sx, sy, sw, sh, mw, mh, snap) {
        let candidates = [
            { x: sx - mw, y: py }, { x: sx + sw, y: py },
            { x: px, y: sy - mh }, { x: px, y: sy + sh }
        ];
        let best = candidates[0];
        let distance = Number.MAX_VALUE;
        for (let candidate of candidates) {
            let d = Math.hypot(px - candidate.x, py - candidate.y);
            if (d < distance) { best = candidate; distance = d; }
        }
        return { x: Math.abs(px - best.x) <= snap ? best.x : px, y: Math.abs(py - best.y) <= snap ? best.y : py };
    }

    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let response = JSON.parse(text);
                    if (!response.ok) { root.errorMessage = response.error; return; }
                    root.errorMessage = "";
                    root.loadData(response.data);
                } catch (e) { root.errorMessage = String(e); }
            }
        }
    }
    function refresh() {
        if (worker.running) return;
        worker.command = ["python3", backend, "monitors"]; worker.running = true;
    }
    Component.onCompleted: refresh()
    Flickable {
        anchors.fill: parent; anchors.margins: root.s(24); contentWidth: width; contentHeight: contents.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: contents; width: parent.width; spacing: root.s(14)
            SettingsRow {
                title: "Monitors"; description: "Drag screens to arrange them, then apply the layout."; icon: "󰍹"; rootObj: root.rootObj
                ClickButton { buttonText: "Reload"; accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text; onClicked: root.refresh() }
                ClickButton { buttonText: "Apply"; enabled: !worker.running; accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust; onClicked: root.save() }
            }
            Text { visible: root.errorMessage !== ""; text: root.errorMessage; color: ThemeBackend.red; font.family: ThemeBackend.fontFamily; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                // ── Single Monitor Preview ──────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(220)
                    visible: modelState.monitorsModel.count <= 1

                    Item {
                        id: singleMonPreview
                        anchors.centerIn: parent
                        width: root.s(270)
                        height: root.s(200)

                        property real baseScale: Math.min(1.0, Math.min(1800 / root.monCurrentSimW, 1100 / Math.max(1, root.monCurrentSimH)))
                        scale: baseScale
                        Behavior on baseScale { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                        AddonGlassSurface {
                            width: parent.width * 0.88
                            height: root.s(10)
                            radius: root.s(5)
                            anchors.top: monStandBase.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            surfaceColor: root.mantle
                            border.color: root.surface0
                            border.width: 1
                        }
                        AddonGlassSurface {
                            id: monStandBase
                            width: root.s(100)
                            height: root.s(7)
                            radius: root.s(4)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.s(12)
                            anchors.horizontalCenter: parent.horizontalCenter
                            surfaceColor: root.surface1
                        }
                        AddonGlassSurface {
                            id: monStandNeck
                            width: root.s(26)
                            height: root.s(52)
                            anchors.bottom: monStandBase.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            surfaceColor: root.surface0
                            AddonGlassSurface {
                                width: root.s(8)
                                height: root.s(20)
                                radius: root.s(4)
                                anchors.centerIn: parent
                                surfaceColor: root.base
                            }
                        }
                        AddonGlassSurface {
                            id: monScreenBezel
                            width: root.s(270) * (root.monCurrentSimW / 1920.0)
                            height: root.s(270) * (root.monCurrentSimH / 1920.0)
                            anchors.bottom: monStandNeck.top
                            anchors.bottomMargin: root.s(-8)
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: root.s(10)
                            surfaceColor: root.crust
                            border.color: root.surface2
                            border.width: root.s(2)
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                            Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                            AddonGlassSurface {
                                anchors.fill: parent
                                anchors.margins: root.s(8)
                                radius: root.s(5)
                                surfaceColor: root.surface0
                                clip: true

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    gradient: ThemeBackend.liquidGlass ? null : monitorGradient
                                    property Gradient monitorGradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { position: 0.0; color: Qt.tint(root.surface0, Qt.alpha(root.monSelectedResAccent, 0.18)); Behavior on color { ColorAnimation { duration: 400 } } }
                                        GradientStop { position: 1.0; color: Qt.tint(root.surface0, Qt.alpha(root.monSelectedRateAccent, 0.12)); Behavior on color { ColorAnimation { duration: 400 } } }
                                    }
                                    Grid {
                                        anchors.centerIn: parent
                                        rows: 7; columns: 11; spacing: root.s(18)
                                        Repeater { model: 77; Rectangle { width: root.s(2); height: root.s(2); radius: root.s(1); color: Qt.alpha(root.text, 0.08) } }
                                    }
                                }

                                Item {
                                    anchors.centerIn: parent
                                    width: root.s(140)
                                    height: root.s(90)
                                    property real counterScale: 1.0 / singleMonPreview.scale
                                    property real maxPhysicalScale: root.monCurrentIsPortrait
                                        ? Math.min((parent.width * 0.9) / height, (parent.height * 0.9) / width)
                                        : Math.min((parent.width * 0.9) / width, (parent.height * 0.9) / height)
                                    scale: Math.min(counterScale, maxPhysicalScale)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: root.s(4)
                                        rotation: root.monCurrentTransform * 90
                                        Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                                        Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(32); color: root.monSelectedResAccent; text: "󰍹"; Behavior on color { ColorAnimation { duration: 400 } } }
                                        Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text; text: modelState.monitorsModel.count > 0 ? modelState.monitorsModel.get(0).name : "—" }
                                        Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); color: root.subtext0; text: root.monCurrentSimW + "\xd7" + root.monCurrentSimH + " @ " + (modelState.monitorsModel.count > 0 ? modelState.monitorsModel.get(0).rate : "60") + "Hz" }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Multi-Monitor Drag Canvas ───────────────────────────────
                Item {
                    id: multiMonContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(320)
                    visible: modelState.monitorsModel.count > 1
                    clip: true

                    // Background dot grid
                    Item {
                        id: monitorCanvasDots
                        anchors.fill: parent
                        property real dotSpacing: root.s(18)
                        property int dotColumns: Math.ceil(width / dotSpacing)
                        property int dotRows: Math.ceil(height / dotSpacing)

                        Repeater {
                            model: monitorCanvasDots.dotColumns * monitorCanvasDots.dotRows
                            Rectangle {
                                x: (index % monitorCanvasDots.dotColumns) * monitorCanvasDots.dotSpacing
                                y: Math.floor(index / monitorCanvasDots.dotColumns) * monitorCanvasDots.dotSpacing
                                width: root.s(2)
                                height: width
                                radius: width / 2
                                color: Qt.alpha(root.text, 0.07)
                            }
                        }
                    }

                    // Compute layout scale/offset to fit all monitors in the canvas
                    property real targetScale: {
                        let _ = root.monChangeTrigger;
                        if (modelState.monitorsModel.count < 2) return 1.0;
                        let minX = 999999, minY = 999999, maxX = -999999, maxY = -999999;
                        for (let i = 0; i < modelState.monitorsModel.count; i++) {
                            let m = modelState.monitorsModel.get(i);
                            let isP = m.transform % 2 === 1;
                            let w = ((isP ? m.resH : m.resW) / m.sysScale) * modelState.monUiScale;
                            let h = ((isP ? m.resW : m.resH) / m.sysScale) * modelState.monUiScale;
                            minX = Math.min(minX, m.uiX); minY = Math.min(minY, m.uiY);
                            maxX = Math.max(maxX, m.uiX + w); maxY = Math.max(maxY, m.uiY + h);
                        }
                        let requiredW = (maxX - minX) + root.s(60);
                        let requiredH = (maxY - minY) + root.s(60);
                        return Math.min((multiMonContainer.width - root.s(20)) / requiredW,
                                        root.s(280) / requiredH,
                                        1.8);
                    }
                    property real offsetX: {
                        let _ = root.monChangeTrigger;
                        if (modelState.monitorsModel.count < 2) return 0;
                        let minX = 999999, maxX = -999999;
                        for (let i = 0; i < modelState.monitorsModel.count; i++) {
                            let m = modelState.monitorsModel.get(i);
                            let isP = m.transform % 2 === 1;
                            let w = ((isP ? m.resH : m.resW) / m.sysScale) * modelState.monUiScale;
                            minX = Math.min(minX, m.uiX); maxX = Math.max(maxX, m.uiX + w);
                        }
                        return (multiMonContainer.width / 2) - ((minX + (maxX - minX) / 2) * targetScale);
                    }
                    property real offsetY: {
                        let _ = root.monChangeTrigger;
                        if (modelState.monitorsModel.count < 2) return 0;
                        let minY = 999999, maxY = -999999;
                        for (let i = 0; i < modelState.monitorsModel.count; i++) {
                            let m = modelState.monitorsModel.get(i);
                            let isP = m.transform % 2 === 1;
                            let h = ((isP ? m.resW : m.resH) / m.sysScale) * modelState.monUiScale;
                            minY = Math.min(minY, m.uiY); maxY = Math.max(maxY, m.uiY + h);
                        }
                        return (multiMonContainer.height / 2) - ((minY + (maxY - minY) / 2) * targetScale);
                    }

                    Item {
                        id: monTransformNode
                        x: multiMonContainer.offsetX
                        y: multiMonContainer.offsetY
                        scale: multiMonContainer.targetScale
                        transformOrigin: Item.TopLeft
                        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                        Repeater {
                            model: modelState.monitorsModel
                            delegate: Item {
                                id: monDelegateItem
                                property bool isActive: modelState.monActiveEditIndex === index
                                property bool isPortrait: model.transform % 2 === 1
                                property real cardW: (isPortrait ? model.resH : model.resW) / model.sysScale * modelState.monUiScale
                                property real cardH: (isPortrait ? model.resW : model.resH) / model.sysScale * modelState.monUiScale

                                // Visible card
                                AddonGlassSurface {
                                    id: monCard
                                    x: model.uiX
                                    y: model.uiY
                                    width: monDelegateItem.cardW
                                    height: monDelegateItem.cardH
                                    radius: root.s(8)
                                    surfaceColor: isActive ? root.surface1 : root.crust
                                    border.color: isActive ? root.monSelectedResAccent : root.surface2
                                    border.width: isActive ? root.s(2) : root.s(1)
                                    z: isActive ? 5 : 0
                                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                    Behavior on surfaceColor { ColorAnimation { duration: 300 } }
                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                                    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                                    Item {
                                        anchors.centerIn: parent
                                        width: root.s(110)
                                        height: root.s(80)
                                        property real idealScale: 1.2 / monTransformNode.scale
                                        property real maxPhysicalScale: isPortrait
                                            ? Math.min((parent.width * 0.9) / height, (parent.height * 0.9) / width)
                                            : Math.min((parent.width * 0.9) / width, (parent.height * 0.9) / height)
                                        scale: Math.min(idealScale, maxPhysicalScale)

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: root.s(2)
                                            rotation: model.transform * 90
                                            Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                                            Text { Layout.alignment: Qt.AlignHCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(26); color: isActive ? root.monSelectedResAccent : root.text; text: "󰍹"; Behavior on color { ColorAnimation { duration: 300 } } }
                                            Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.weight: Font.Black; font.pixelSize: root.s(10); color: root.text; text: model.name }
                                            Text { Layout.alignment: Qt.AlignHCenter; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(9); color: root.subtext0; text: model.resW + "\xd7" + model.resH + "@" + model.rate }
                                        }
                                    }
                                }

                                // Invisible ghost dragger — sits on top, handles drag
                                Item {
                                    id: ghostDrag
                                    x: model.uiX
                                    y: model.uiY
                                    width: monDelegateItem.cardW
                                    height: monDelegateItem.cardH
                                    z: isActive ? 10 : 1

                                    MouseArea {
                                        id: ghostMa
                                        anchors.fill: parent
                                        preventStealing: true
                                        drag.target: ghostDrag
                                        drag.axis: Drag.XAndYAxis
                                        cursorShape: Qt.SizeAllCursor

                                        onPressed: {
                                            modelState.monActiveEditIndex = index;
                                            ghostDrag.x = model.uiX;
                                            ghostDrag.y = model.uiY;
                                        }

                                        onPositionChanged: {
                                            if (!drag.active || modelState.monitorsModel.count < 2) return;

                                            let mW = monDelegateItem.cardW;
                                            let mH = monDelegateItem.cardH;
                                            let padding = root.s(40);

                                            // Compute drag bounds from all other monitors
                                            let boundMinX = 999999, boundMinY = 999999;
                                            let boundMaxX = -999999, boundMaxY = -999999;
                                            for (let j = 0; j < modelState.monitorsModel.count; j++) {
                                                if (j === index) continue;
                                                let sModel = modelState.monitorsModel.get(j);
                                                let sIsP = sModel.transform === 1 || sModel.transform === 3;
                                                let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * modelState.monUiScale;
                                                let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * modelState.monUiScale;
                                                boundMinX = Math.min(boundMinX, sModel.uiX - mW - padding);
                                                boundMinY = Math.min(boundMinY, sModel.uiY - mH - padding);
                                                boundMaxX = Math.max(boundMaxX, sModel.uiX + sW + padding);
                                                boundMaxY = Math.max(boundMaxY, sModel.uiY + sH + padding);
                                            }
                                            ghostDrag.x = Math.max(boundMinX, Math.min(ghostDrag.x, boundMaxX));
                                            ghostDrag.y = Math.max(boundMinY, Math.min(ghostDrag.y, boundMaxY));

                                            // Perimeter snap against each other monitor
                                            let bestX = ghostDrag.x, bestY = ghostDrag.y, bestDist = 999999;
                                            for (let j = 0; j < modelState.monitorsModel.count; j++) {
                                                if (j === index) continue;
                                                let sModel = modelState.monitorsModel.get(j);
                                                let sIsP = sModel.transform === 1 || sModel.transform === 3;
                                                let sW = ((sIsP ? sModel.resH : sModel.resW) / sModel.sysScale) * modelState.monUiScale;
                                                let sH = ((sIsP ? sModel.resW : sModel.resH) / sModel.sysScale) * modelState.monUiScale;
                                                let snapped = modelState.monGetPerimeterSnap(
                                                    ghostDrag.x, ghostDrag.y,
                                                    sModel.uiX, sModel.uiY, sW, sH, mW, mH, root.s(20)
                                                );
                                                let dist = Math.hypot(ghostDrag.x - snapped.x, ghostDrag.y - snapped.y);
                                                if (dist < bestDist) { bestDist = dist; bestX = snapped.x; bestY = snapped.y; }
                                            }

                                            if (!modelState.monIsOverlappingAny(bestX, bestY, mW, mH, index)) {
                                                modelState.monitorsModel.setProperty(index, "uiX", bestX);
                                                modelState.monitorsModel.setProperty(index, "uiY", bestY);
                                            }
                                        }

                                        onReleased: {
                                            // Snap ghost back to model position
                                            ghostDrag.x = model.uiX;
                                            ghostDrag.y = model.uiY;
                                            root.monChangeTrigger++;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Resolution Grid ─────────────────────────────────────────
                GridLayout {
                    id: resGrid
                    Layout.fillWidth: true
                    columns: Math.max(2, Math.floor(width / root.s(230)))
                    columnSpacing: root.s(8)
                    rowSpacing: root.s(8)

                    Repeater {
                        model: root.monAvailableResolutions
                        delegate: AddonGlassSurface {
                            property var md: root.monAvailableResolutions[index]
                            property string resLabel: md ? root.getResLabel(md.w, md.h) : ""
                            property color accent: root.monResAccentColors[index % root.monResAccentColors.length]
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(40)
                            radius: root.s(10)
                            property bool isSel: {
                                let _ = root.monChangeTrigger;
                                if (!md || modelState.monitorsModel.count === 0) return false;
                                let a = modelState.monitorsModel.get(modelState.monActiveEditIndex);
                                return a.resW === md.w && a.resH === md.h;
                            }
                            surfaceColor: isSel ? Qt.alpha(accent, 0.15) : (rMa.containsMouse ? root.surface0 : root.mantle)
                            border.color: isSel ? accent : (rMa.containsMouse ? root.surface1 : "transparent")
                            border.width: isSel ? root.s(2) : root.s(1)
                            Behavior on surfaceColor { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                            scale: rMa.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutSine } }

                            RowLayout {
                                anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(6)
                                Text {
                                    font.family: ThemeBackend.fontFamily; font.weight: isSel ? Font.Black : Font.Bold; font.pixelSize: root.s(13)
                                    color: isSel ? accent : root.text; text: resLabel
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10)
                                    color: isSel ? root.text : root.overlay0
                                    text: md ? (md.w + "×" + md.h) : ""
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }

                            MouseArea {
                                id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!md || modelState.monitorsModel.count === 0) return;
                                    root.monSelectedResAccent = accent;
                                    modelState.monitorsModel.setProperty(modelState.monActiveEditIndex, "resW", md.w);
                                    modelState.monitorsModel.setProperty(modelState.monActiveEditIndex, "resH", md.h);

                                    // Auto-select highest compatible refresh rate
                                    let mon = modelState.monitorsModel.get(modelState.monActiveEditIndex);
                                    let modes = JSON.parse(mon.availableModes || "[]");
                                    let prefix = md.w + "x" + md.h + "@";
                                    let validRates = [];
                                    for (let m of modes) {
                                        if (m.startsWith(prefix)) {
                                            let r = parseFloat(m.slice(prefix.length).replace("Hz", ""));
                                            if (!isNaN(r)) validRates.push(r);
                                        }
                                    }
                                    if (validRates.length > 0) {
                                        validRates.sort((a, b) => b - a);
                                        let currentRate = parseFloat(mon.rate);
                                        let closest = validRates[0];
                                        let minDiff = 99999;
                                        for (let r of validRates) {
                                            let diff = Math.abs(r - currentRate);
                                            if (diff < minDiff) { minDiff = diff; closest = r; }
                                        }
                                        modelState.monitorsModel.setProperty(modelState.monActiveEditIndex, "rate", closest.toString());
                                    }
                                    root.monChangeTrigger++;
                                    modelState.monDelayedLayoutUpdate.restart();
                                }
                            }
                        }
                    }
                }

                // ── Rotation Dial + Refresh Rate Slider ─────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(16)

                    // Rotation dial
                    AddonGlassSurface {
                        id: monDial
                        Layout.preferredWidth: root.s(120)
                        Layout.preferredHeight: root.s(120)
                        Layout.alignment: Qt.AlignVCenter
                        radius: width / 2
                        surfaceColor: root.surface0
                        border.color: root.surface1
                        border.width: root.s(2)

                        Repeater {
                            model: 12
                            Item {
                                anchors.fill: parent
                                rotation: index * 30
                                Rectangle {
                                    width: index % 3 === 0 ? root.s(3) : root.s(2)
                                    height: index % 3 === 0 ? root.s(8) : root.s(4)
                                    radius: width / 2
                                    color: index % 3 === 0 ? root.subtext0 : root.surface2
                                    anchors.top: parent.top
                                    anchors.topMargin: root.s(6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            property int tf: {
                                let _ = root.monChangeTrigger;
                                return modelState.monitorsModel.count > 0 ? modelState.monitorsModel.get(modelState.monActiveEditIndex).transform : 0;
                            }
                            rotation: tf * 90
                            Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }

                            Rectangle {
                                width: root.s(4)
                                height: parent.height / 2 - root.s(22)
                                radius: root.s(2)
                                color: root.monSelectedResAccent
                                anchors.bottom: parent.verticalCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            AddonGlassSurface {
                                width: root.s(18); height: root.s(18); radius: root.s(9)
                                surfaceColor: root.base
                                border.color: root.monSelectedResAccent
                                border.width: root.s(4)
                                anchors.centerIn: parent
                                Behavior on border.color { ColorAnimation { duration: 300 } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            function updateAngle(mx, my) {
                                if (modelState.monitorsModel.count === 0) return;
                                let cx = width / 2; let cy = height / 2;
                                let dx = mx - cx; let dy = my - cy;
                                if (Math.hypot(dx, dy) < root.s(18)) return;
                                let tf = modelState.monitorsModel.get(modelState.monActiveEditIndex).transform;
                                let angle = tf * Math.PI / 2;
                                let rdx = dx * Math.cos(-angle) - dy * Math.sin(-angle);
                                let rdy = dx * Math.sin(-angle) + dy * Math.cos(-angle);
                                let rawSnap = Math.abs(rdx) > Math.abs(rdy) ? (rdx > 0 ? 1 : 3) : (rdy > 0 ? 2 : 0);
                                let snap = (rawSnap + tf) % 4;
                                modelState.monitorsModel.setProperty(modelState.monActiveEditIndex, "transform", snap);
                                root.monChangeTrigger++;
                                modelState.monDelayedLayoutUpdate.restart();
                            }
                            onPressed: (mouse) => updateAngle(mouse.x, mouse.y)
                            onPositionChanged: (mouse) => { if (pressed) updateAngle(mouse.x, mouse.y) }
                        }
                    }

                    // Refresh rate slider
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.s(6)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Refresh Rate"
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                color: root.subtext0; Layout.fillWidth: true
                            }
                            Text {
                                text: {
                                    let _ = root.monChangeTrigger;
                                    if (modelState.monitorsModel.count === 0) return "—";
                                    if (rateSlider.numRates > 0) return rateSlider.rates[rateSlider.curIdx] + " Hz";
                                    return Math.round(parseFloat(modelState.monitorsModel.get(modelState.monActiveEditIndex).rate) || 60) + " Hz";
                                }
                                font.family: ThemeBackend.fontFamily; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                color: root.monSelectedRateAccent
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        Item {
                            id: rateSlider
                            Layout.fillWidth: true
                            property var rates: root.monAvailableRates
                            property int numRates: rates ? rates.length : 0
                            Layout.preferredHeight: numRates > 1 ? root.s(50) : 0
                            opacity: numRates > 1 ? 1.0 : 0.0
                            visible: Layout.preferredHeight > 0
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            property int curIdx: {
                                let _ = root.monChangeTrigger;
                                if (modelState.monitorsModel.count === 0 || numRates === 0) return 0;
                                let rawRate = modelState.monitorsModel.get(modelState.monActiveEditIndex).rate;
                                let val = Math.round(parseFloat(rawRate));
                                if (isNaN(val)) val = rates[rates.length - 1];
                                let best = 0, minDiff = 99999;
                                for (let i = 0; i < numRates; i++) {
                                    let diff = Math.abs(rates[i] - val);
                                    if (diff < minDiff) { minDiff = diff; best = i; }
                                }
                                return best;
                            }
                            property real tLeft: root.s(8)
                            property real tW: Math.max(1, width - root.s(16))
                            property real knobX: numRates <= 1 ? tLeft : tLeft + (curIdx / (numRates - 1)) * tW

                            AddonGlassSurface {
                                id: rTrack
                                x: rateSlider.tLeft; width: rateSlider.tW
                                y: root.s(8); height: root.s(6); radius: root.s(3)
                                surfaceColor: root.mantle; border.color: root.surface1; border.width: 1

                                Rectangle {
                                    width: Math.max(0, rKnob.x - rateSlider.tLeft + rKnob.width / 2)
                                    height: parent.height; radius: parent.radius
                                    color: root.monSelectedRateAccent
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            AddonGlassSurface {
                                id: rKnob
                                width: root.s(16); height: root.s(16); radius: root.s(8)
                                surfaceColor: rateMa.containsPress ? root.monSelectedRateAccent : root.text
                                y: rTrack.y + rTrack.height / 2 - height / 2
                                x: rateSlider.knobX - width / 2
                                Behavior on x { enabled: !rateMa.pressed; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on surfaceColor { ColorAnimation { duration: 150 } }
                            }
                            Repeater {
                                model: rateSlider.numRates
                                Item {
                                    x: rateSlider.numRates <= 1 ? rateSlider.tLeft : rateSlider.tLeft + (index / (rateSlider.numRates - 1)) * rateSlider.tW
                                    y: rTrack.y + rTrack.height + root.s(3)
                                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: root.s(1); height: root.s(3); color: rateSlider.curIdx === index ? root.monSelectedRateAccent : root.overlay0 }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter; y: root.s(4)
                                        text: rateSlider.rates[index]
                                        font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(8)
                                        font.weight: rateSlider.curIdx === index ? Font.Bold : Font.Normal
                                        color: rateSlider.curIdx === index ? root.monSelectedRateAccent : root.overlay0
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }
                            }
                            MouseArea {
                                id: rateMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                function doSnap(mx) {
                                    if (modelState.monitorsModel.count === 0 || rateSlider.numRates === 0) return;
                                    let pct = (mx - rateSlider.tLeft) / rateSlider.tW;
                                    pct = Math.max(0, Math.min(1, pct));
                                    let idx = Math.round(pct * (rateSlider.numRates - 1));
                                    modelState.monitorsModel.setProperty(modelState.monActiveEditIndex, "rate", rateSlider.rates[idx].toString());
                                    root.monChangeTrigger++;
                                }
                                onPressed: (mouse) => doSnap(mouse.x)
                                onPositionChanged: (mouse) => { if (pressed) doSnap(mouse.x) }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: root.s(16) }
            SettingsRow {
                title: "Display"; rootObj: root.rootObj
                Dropdown {
                    Layout.preferredWidth: root.s(260); options: { let a = []; for (let i = 0; i < monitorList.count; i++) a.push(monitorList.get(i).name); return a; }
                    currentIndex: modelState.monActiveEditIndex
                    accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text; dropdownColor: ThemeBackend.surface0; borderColor: ThemeBackend.surface2
                    onValueChanged: (index, value) => modelState.monActiveEditIndex = index
                }
            }
            SettingsRow {
                title: "Orientation"; rootObj: root.rootObj
                Dropdown {
                    Layout.preferredWidth: root.s(260); options: ["0°", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
                    currentIndex: root.selected ? root.selected.transform : 0
                    accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text; dropdownColor: ThemeBackend.surface0; borderColor: ThemeBackend.surface2
                    onValueChanged: (index, value) => root.updateSelected("transform", index)
                }
            }
            SettingsRow {
                title: "Position"; description: "Logical pixels"; rootObj: root.rootObj
                Repeater {
                    model: ["uiX", "uiY"]
                    Input {
                        required property string modelData
                        Layout.preferredWidth: root.s(120); placeholderText: modelData === "uiX" ? "X" : "Y"
                        text: root.selected ? String(Math.round(root.selected[modelData] / modelState.monUiScale)) : "0"
                        validator: IntValidator {}
                        baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text; accentColor: ThemeBackend.mauve; borderColor: ThemeBackend.surface2
                        onTextEdited: value => { if (/^-?\d+$/.test(value)) root.updateSelected(modelData, Number(value) * modelState.monUiScale); }
                    }
                }
            }
        }
    }
}
