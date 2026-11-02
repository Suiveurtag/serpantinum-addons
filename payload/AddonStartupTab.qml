import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

// Same rows, sliding edit control and editor as AddonKeybindsTab.
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
    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/startup.py"
    property string errorMessage: ""
    readonly property color base: ThemeBackend.base
    readonly property color text: ThemeBackend.text
    readonly property color subtext0: ThemeBackend.subtext0
    readonly property color surface0: ThemeBackend.surface0
    readonly property color surface1: ThemeBackend.surface1
    readonly property color surface2: ThemeBackend.surface2
    readonly property color peach: ThemeBackend.peach
    readonly property color red: ThemeBackend.red
    readonly property color green: ThemeBackend.green
    property string revision: ""
    property int highlightedBox: -1
    property string query: ""
    property int modelChange: 0
    ListModel { id: startupModel }
    function clearHighlight() { highlightedBox = -1; }

    function loadData(data) {
        revision = data.revision;
        startupModel.clear();
        for (let command of data.commands) startupModel.append({command: command, isEditing: false});
        modelChange++;
    }
    function add() {
        startupModel.append({command: "", isEditing: true});
        modelChange++;
        Qt.callLater(() => startupTabRoot.scrollToBottom());
    }
    function saveAll() {
        if (worker.running) return;
        let commands = [];
        for (let i = 0; i < startupModel.count; i++) {
            let command = startupModel.get(i).command.trim();
            if (command) commands.push(command);
        }
        worker.command = ["python3", backend, "save", JSON.stringify({revision: revision, commands: commands})]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (!result.ok) { root.errorMessage = result.error; return; }
                    root.errorMessage = ""; root.loadData(result.data);
                } catch (e) { root.errorMessage = String(e); }
            }
        }
    }
    function refresh() { if (!worker.running) { worker.command = ["python3", backend, "status"]; worker.running = true; } }
    Component.onCompleted: refresh()
    ColumnLayout {
        anchors.fill: parent; anchors.margins: root.s(24); spacing: root.s(14)
        SettingsRow {
            rootObj: root.rootObj
            settingId: "addon_startup_commands"
            searchTab: "addon_startup"
            searchKeywords: "startup autostart launch boot login exec discord démarrage lancement"
            title: qsTr("Startup commands")
            description: qsTr("Launched once each time the session starts, like Discord.")
            icon: "󰐥"
            ClickButton { buttonText: qsTr("Reload"); accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text; onClicked: root.refresh() }
            ClickButton { buttonText: qsTr("Add"); accentColor: ThemeBackend.peach; textColor: ThemeBackend.crust; onClicked: root.add() }
        }
        Input { Layout.fillWidth: true; placeholderText: qsTr("Search startup commands"); showClearButton: true; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text; accentColor: ThemeBackend.peach; borderColor: ThemeBackend.surface2; onTextEdited: value => root.query = value.toLowerCase() }
        Text { visible: root.errorMessage !== ""; text: root.errorMessage; color: ThemeBackend.red; font.family: ThemeBackend.fontFamily; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        Text {
            visible: startupModel.count === 0 && !worker.running && root.errorMessage === ""
            text: qsTr("No startup commands yet. Use Add to launch an app with the session.")
            color: root.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Item {
            id: startupTabRoot
            Layout.fillWidth: true; Layout.fillHeight: true

            function scrollToBottom() {
                startupFlickable.contentY = Math.max(0, startupColLayout.implicitHeight - startupFlickable.height + root.s(100));
            }

            Flickable {
                id: startupFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: startupColLayout.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                MouseArea { anchors.fill: parent; onClicked: root.clearHighlight(); z: -1 }

                ColumnLayout {
                    id: startupColLayout
                    width: parent.width
                    spacing: root.s(8)

                    ListView {
                        id: startupListView
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        implicitHeight: {
                            let revision = root.modelChange;
                            let total = 0;
                            for (let i = 0; i < count; i++) { let row = itemAtIndex(i); total += row ? row.height + spacing : root.s(56); }
                            return total + root.s(20);
                        }
                        model: startupModel
                        interactive: false
                        cacheBuffer: root.s(2000)
                        spacing: root.s(8)

                        delegate: AddonGlassSurface {
                            id: rowRect
                            property int outerIndex: index
                            visible: root.query === "" || model.command.toLowerCase().indexOf(root.query) !== -1
                            property bool isJumpHighlighted: root.highlightedBox === outerIndex

                            property bool layoutReady: false
                            Component.onCompleted: Qt.callLater(() => layoutReady = true)

                            width: startupListView.width
                            height: visible ? root.s(44) + (model.isEditing ? editPanel.implicitHeight + root.s(12) : 0) : 0
                            onHeightChanged: root.modelChange++
                            radius: root.s(8)

                            HoverHandler { id: rowHover }
                            property bool isHovered: rowHover.hovered || model.isEditing || isJumpHighlighted

                            surfaceColor: isHovered ? root.surface1 : root.surface0
                            border.color: isJumpHighlighted ? root.peach : (isHovered ? Qt.alpha(root.peach, 0.5) : root.surface1)
                            border.width: isJumpHighlighted ? 2 : 1

                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                            Behavior on surfaceColor { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutExpo } }
                            Behavior on border.width { NumberAnimation { duration: 150 } }

                            MouseArea { anchors.fill: parent; z: -2; onClicked: root.highlightedBox = outerIndex; }

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: root.s(10); spacing: root.s(10)

                                Item {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(24); clip: true

                                    AddonGlassSurface {
                                        id: launchChip
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(24); height: root.s(24); radius: root.s(4)
                                        surfaceColor: root.surface1
                                        border.color: root.surface2; border.width: 1
                                        Text {
                                            anchors.centerIn: parent; text: "󰐥"
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(12)
                                            color: root.peach
                                        }
                                    }

                                    // Edit button
                                    AddonGlassSurface {
                                        id: editButtonSlide
                                        width: root.s(26); height: root.s(26); radius: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: rowRect.isHovered ? parent.width - width : parent.width
                                        surfaceColor: model.isEditing
                                            ? root.peach
                                            : (editMa.containsMouse ? root.peach : root.surface2)

                                        Behavior on x {
                                            enabled: rowRect.layoutReady
                                            NumberAnimation { duration: 250; easing.type: Easing.OutQuart }
                                        }
                                        Behavior on surfaceColor { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: model.isEditing ? "▴" : "󰏫"
                                            font.family: model.isEditing ? "Inter" : "Iosevka Nerd Font"
                                            font.pixelSize: root.s(13)
                                            color: model.isEditing
                                                ? (ThemeBackend.liquidGlass ? root.text : root.base)
                                                : (editMa.containsMouse ? (ThemeBackend.liquidGlass ? root.text : root.base) : root.subtext0)
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                        }
                                        MouseArea {
                                            id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                startupModel.setProperty(outerIndex, "isEditing", !model.isEditing);
                                                if (!model.isEditing) root.forceActiveFocus();
                                            }
                                        }
                                    }
                                    Item {
                                        id: cmdClipRect
                                        anchors.left: launchChip.right; anchors.leftMargin: root.s(8)
                                        anchors.right: editButtonSlide.left; anchors.rightMargin: root.s(6)
                                        anchors.verticalCenter: parent.verticalCenter; height: parent.height; clip: true

                                        property int marqueeSpacing: root.s(60)
                                        property bool shouldMarquee: rowRect.isHovered && cmdTextMain.implicitWidth > width

                                        Item {
                                            id: marqueeContainer
                                            height: parent.height
                                            width: cmdClipRect.shouldMarquee ? cmdTextMain.implicitWidth * 2 + cmdClipRect.marqueeSpacing : parent.width
                                            anchors.verticalCenter: parent.verticalCenter

                                            Row {
                                                spacing: cmdClipRect.marqueeSpacing; anchors.verticalCenter: parent.verticalCenter

                                                Text {
                                                    id: cmdTextMain; text: model.command || qsTr("New command")
                                                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                                    color: model.command ? root.text : root.subtext0
                                                }
                                                Text {
                                                    text: cmdTextMain.text; font: cmdTextMain.font; color: cmdTextMain.color
                                                    visible: cmdClipRect.shouldMarquee
                                                }
                                            }

                                            SequentialAnimation on x {
                                                id: cmdAnim; loops: Animation.Infinite
                                                running: cmdClipRect.shouldMarquee && rowRect.layoutReady
                                                PauseAnimation { duration: 1500 }
                                                NumberAnimation { from: 0; to: -(cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing); duration: (cmdTextMain.implicitWidth + cmdClipRect.marqueeSpacing) * 25 }
                                                PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                            }
                                            onXChanged: { if (!cmdClipRect.shouldMarquee && x !== 0) x = 0; }
                                        }

                                        onShouldMarqueeChanged: {
                                            if (shouldMarquee) { marqueeContainer.x = 0; cmdAnim.restart(); }
                                            else { cmdAnim.stop(); marqueeContainer.x = 0; }
                                        }
                                    }

                                    MouseArea {
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: editButtonSlide.left
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton; enabled: !model.isEditing
                                        onClicked: startupModel.setProperty(outerIndex, "isEditing", true)
                                    }
                                }

                                // ── Edit panel ───────────────────────────────
                                ColumnLayout {
                                    id: editPanel
                                    Layout.fillWidth: true; visible: model.isEditing; spacing: root.s(8); clip: true

                                    // Command input
                                    AddonGlassSurface {
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(34)
                                        radius: root.s(6)
                                        surfaceColor: cmdInput.activeFocus ? Qt.alpha(root.peach, 0.08) : root.surface0
                                        border.color: cmdInput.activeFocus ? root.peach : root.surface2
                                        border.width: 1
                                        Behavior on surfaceColor { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                        TextInput {
                                            id: cmdInput
                                            anchors.fill: parent; anchors.margins: root.s(9)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: model.command
                                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                            color: root.text; clip: true; selectByMouse: true
                                            onTextEdited: startupModel.setProperty(outerIndex, "command", text)
                                            onAccepted: rowSaveMa.clicked(null)
                                            Component.onCompleted: if (model.isEditing && !model.command) forceActiveFocus()
                                            Text {
                                                text: qsTr("Command, e.g. discord")
                                                color: root.subtext0
                                                visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; Layout.alignment: Qt.AlignRight; spacing: root.s(8)
                                        // Delete button
                                        AddonGlassSurface {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            surfaceColor: delMa.containsMouse ? root.red : root.surface1
                                            border.color: delMa.containsMouse ? root.red : Qt.alpha(root.red, 0.4)
                                            border.width: 1
                                            Behavior on surfaceColor { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆴"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: delMa.containsMouse ? (ThemeBackend.liquidGlass ? root.text : root.base) : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: qsTr("Delete"); font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); font.weight: Font.Medium
                                                    color: delMa.containsMouse ? (ThemeBackend.liquidGlass ? root.text : root.base) : root.red
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea {
                                                id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.forceActiveFocus();
                                                    startupModel.remove(outerIndex);
                                                    root.modelChange++;
                                                    root.saveAll();
                                                }
                                            }
                                        }
                                        // Save button
                                        AddonGlassSurface {
                                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(30); radius: root.s(7)
                                            surfaceColor: rowSaveMa.containsMouse ? root.green : root.surface1
                                            border.color: rowSaveMa.containsMouse ? root.green : Qt.alpha(root.green, 0.4)
                                            border.width: 1
                                            Behavior on surfaceColor { ColorAnimation { duration: 180; easing.type: Easing.OutExpo } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: root.s(6)
                                                Text {
                                                    text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                                                    color: rowSaveMa.containsMouse ? (ThemeBackend.liquidGlass ? root.text : root.base) : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                                Text {
                                                    text: qsTr("Save"); font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); font.weight: Font.Medium
                                                    color: rowSaveMa.containsMouse ? (ThemeBackend.liquidGlass ? root.text : root.base) : root.green
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                }
                                            }
                                            MouseArea {
                                                id: rowSaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!model.command.trim()) { root.errorMessage = qsTr("Enter a command first."); return; }
                                                    startupModel.setProperty(outerIndex, "isEditing", false);
                                                    root.forceActiveFocus();
                                                    root.saveAll();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
