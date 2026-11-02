pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

ColumnLayout {
    id: root
    required property var rootObj
    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/custom_cursor.py"
    property var draft: ({baseTheme: "", size: 32, roles: {}, normalOnly: false})
    property var saved: ({})
    property var themes: []
    property var roles: []
    property string revision: ""
    property string selectedRole: "left_ptr"
    property string error: ""
    property string notice: ""
    property bool pendingPreview: false
    property bool pendingApply: false
    property bool loaded: false
    readonly property bool busy: worker.running || pendingApply
    readonly property bool dirty: loaded && JSON.stringify(draft) !== JSON.stringify(saved)
    readonly property int roleIndex: roleIds.indexOf(selectedRole)
    readonly property var currentRole: roles.find(entry => entry.id === selectedRole) || ({preview: "", source: "", hotspot: [0, 0], width: 0, height: 0, frames: 0})
    readonly property string selectedPath: draft.roles[selectedRole] ? (draft.roles[selectedRole].originalPath || draft.roles[selectedRole].source) : ""
    readonly property var roleIds: ["left_ptr", "help", "progress", "wait", "pointer", "text", "vertical-text", "crosshair", "cell", "move", "grab", "grabbing", "not-allowed", "copy", "alias", "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "n-resize", "s-resize", "e-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize", "zoom-in", "zoom-out", "context-menu", "pencil"]
    readonly property var roleNames: [qsTr("Normal select"), qsTr("Help select"), qsTr("Working in background"), qsTr("Busy"), qsTr("Link select"), qsTr("Text select"), qsTr("Vertical text"), qsTr("Precision select"), qsTr("Cell select"), qsTr("Move"), qsTr("Grab"), qsTr("Grabbing"), qsTr("Unavailable"), qsTr("Copy"), qsTr("Create link"), qsTr("Horizontal resize"), qsTr("Vertical resize"), qsTr("Diagonal resize ↗"), qsTr("Diagonal resize ↖"), qsTr("Resize top"), qsTr("Resize bottom"), qsTr("Resize right"), qsTr("Resize left"), qsTr("Resize top right"), qsTr("Resize top left"), qsTr("Resize bottom right"), qsTr("Resize bottom left"), qsTr("Zoom in"), qsTr("Zoom out"), qsTr("Context menu"), qsTr("Handwriting")]
    spacing: rootObj.s(8)

    function execute(action, value) {
        if (busy) return;
        if (action === "import" || action === "install" || action === "apply") previewTimer.stop();
        error = "";
        worker.action = action;
        worker.requestSignature = JSON.stringify(draft);
        worker.command = ["python3", backend, action];
        if (value !== undefined) worker.command = worker.command.concat([typeof value === "string" ? value : JSON.stringify(value)]);
        worker.running = true;
    }
    function change(key, value) {
        let next = JSON.parse(JSON.stringify(draft));
        next[key] = value;
        draft = next;
        previewTimer.restart();
    }
    function resetRole() {
        let next = Object.assign({}, draft.roles);
        delete next[selectedRole];
        change("roles", next);
    }
    function resetIcons() {
        draft = Object.assign({}, draft, {roles: {}, normalOnly: false});
        selectedRole = "left_ptr";
        previewTimer.stop();
        execute("apply", {settings: draft, revision: revision});
    }
    function selectTheme(themeId) {
        draft = Object.assign({}, draft, {baseTheme: themeId, roles: {}, normalOnly: false});
        selectedRole = "left_ptr";
        previewTimer.stop();
        execute("apply", {settings: draft, revision: revision});
    }
    function setNormalOnly(enabled) {
        if (enabled) selectedRole = "left_ptr";
        change("normalOnly", enabled);
        previewTimer.stop();
        pendingApply = true;
        applyTimer.restart();
    }
    function setPoint(x, y) {
        if (!currentRole.source) return;
        let next = JSON.parse(JSON.stringify(draft.roles));
        let custom = next[selectedRole] || {source: currentRole.source, name: roleNames[roleIndex], originalPath: currentRole.source};
        custom.hotspot = [x, y];
        next[selectedRole] = custom;
        change("roles", next);
        let updated = Object.assign({}, currentRole, {hotspot: [x, y]});
        roles = roles.map(entry => entry.id === selectedRole ? updated : entry);
    }
    function accept(raw) {
        try {
            let result = JSON.parse(raw);
            if (!result.ok) throw new Error(result.error);
            let data = result.data;
            if (worker.action === "preview" && worker.requestSignature !== JSON.stringify(draft)) {
                pendingPreview = true;
                return;
            }
            if (worker.action === "export") {
                notice = qsTr("Scheme exported to %1").arg(data.path);
            } else if (worker.action === "import") {
                let next = Object.assign({}, draft.roles);
                next[selectedRole] = {source: data.source, name: data.name, originalPath: data.originalPath, hotspot: data.hotspot};
                draft = Object.assign({}, draft, {roles: next});
                pendingApply = true;
            } else if (worker.action === "install") {
                themes = data.themes;
                if (!loaded) {
                    saved = data.settings;
                    revision = data.revision;
                    loaded = true;
                }
                draft = Object.assign({}, draft, {baseTheme: data.installed[0], roles: {}, normalOnly: false});
                pendingApply = true;
            } else {
                themes = data.themes;
                roles = data.roles;
                if (worker.action !== "preview") {
                    draft = data.settings;
                    saved = JSON.parse(JSON.stringify(data.settings));
                    revision = data.revision;
                    loaded = true;
                    notice = worker.action === "apply" ? qsTr("Applied. Restart applications that still show the previous cursor.") : "";
                }
                if (data.warnings.length) notice = data.warnings.join("\n");
            }
        } catch (failure) { error = String(failure); }
    }
    Process {
        id: worker
        property string action: ""
        property string requestSignature: ""
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.error = text.trim(); } }
        onExited: code => {
            if (code !== 0 && !root.error) root.error = qsTr("Could not update cursor settings.");
            if (root.pendingApply) {
                applyTimer.restart();
            } else if (root.pendingPreview) {
                root.pendingPreview = false;
                previewTimer.restart();
            }
        }
    }
    Timer {
        id: applyTimer
        interval: 1
        onTriggered: {
            root.pendingApply = false;
            root.execute("apply", {settings: root.draft, revision: root.revision});
        }
    }
    Timer {
        id: previewTimer
        interval: 220
        onTriggered: {
            if (root.busy) restart();
            else root.execute("preview", root.draft);
        }
    }
    Component.onCompleted: execute("status")
    ImagePicker {
        id: cursorPicker
        rootObj: root.rootObj
        titleText: qsTr("Choose cursor image or animation")
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.cur", "*.ani", "*.ico", "*.xcursor", "*.cursor"]
        onImageSelected: (path, name) => root.execute("import", path)
    }
    ImagePicker {
        id: themePicker
        rootObj: root.rootObj
        titleText: qsTr("Import cursor theme")
        nameFilters: ["*.zip", "*.tar", "*.tar.gz", "*.tgz", "*.tar.xz", "*.tar.bz2"]
        showPreview: false
        onImageSelected: (path, name) => root.execute("install", path)
    }
    SettingsGroup {
        rootObj: root.rootObj
        title: qsTr("Cursors"); icon: "󰍽"; wrapText: true
        description: root.error || root.notice || qsTr("Theme, size, icons and cursor behaviour")
        ClickButton {
            buttonText: root.busy ? qsTr("Working…") : qsTr("Apply")
            visible: root.dirty
            enabled: root.loaded && !root.busy && !previewTimer.running
            accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
            onTriggered: root.execute("apply", {settings: root.draft, revision: root.revision})
        }
        subSettings: [
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_custom_cursor"; searchTab: "addons"
                title: qsTr("Custom cursor"); icon: "󰆹"; wrapText: true
                searchKeywords: "cursor pointer theme image animation size hotspot souris curseur thème taille point clic"
                description: qsTr("Choose an image for this role. It is applied immediately over the selected theme.")
                RowLayout {
                    spacing: root.rootObj.s(12)
                    ColumnLayout {
                        spacing: root.rootObj.s(8)
                        ClickButton {
                            Layout.alignment: Qt.AlignRight
                            buttonText: qsTr("Select"); buttonIcon: "󰉋"
                            implicitHeight: root.rootObj.s(32)
                            accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
                            enabled: root.loaded && !root.busy
                            onTriggered: cursorPicker.openPicker(root.selectedPath)
                        }
                        Dropdown {
                            Layout.preferredWidth: root.rootObj.s(280)
                            implicitHeight: root.rootObj.s(32)
                            options: root.selectedPath ? [root.selectedPath] : []
                            currentIndex: 0
                            placeholderText: qsTr("Choose an image for this role…")
                            isPathSelector: true; fuzzySearch: true
                            enabled: root.loaded && !root.busy
                            accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text; fontPixelSize: root.rootObj.s(11)
                            onSelected: (index, value) => { if (value && value !== root.selectedPath) root.execute("import", value); }
                        }
                    }
                    AddonCursorPreview {
                        Layout.preferredWidth: root.rootObj.s(72)
                        Layout.preferredHeight: root.rootObj.s(72)
                        cursorInfo: root.currentRole
                    }
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_theme"; searchTab: "addons"
                title: qsTr("Cursor theme"); icon: "󰏘"; wrapText: true
                description: qsTr("Select and apply a complete theme immediately. Replaces current icon and click-point customisations.")
                Dropdown {
                    Layout.preferredWidth: root.rootObj.s(240)
                    options: root.themes.map(theme => theme.name)
                    currentIndex: root.themes.findIndex(theme => theme.id === root.draft.baseTheme)
                    enabled: root.loaded && !root.busy
                    fuzzySearch: true
                    accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                    onSelected: (index, value) => { if (index >= 0 && root.themes[index].id !== root.draft.baseTheme) root.selectTheme(root.themes[index].id); }
                }
                ClickButton {
                    buttonText: qsTr("Import theme"); buttonIcon: "󰉋"
                    enabled: !root.busy
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: themePicker.openPicker(Quickshell.env("HOME") + "/Downloads")
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_size"; searchTab: "addons"
                title: qsTr("Cursor size"); icon: "󰩨"
                description: qsTr("%1 px · multiple resolutions for scaled displays").arg(root.draft.size)
                Draggable {
                    Layout.preferredWidth: root.rootObj.s(220)
                    implicitHeight: root.rootObj.s(18)
                    from: 16; to: 128; stepSize: 1
                    value: root.draft.size
                    enabled: root.loaded && (!root.busy || isDragging)
                    showValueBubble: true
                    valueFormatter: value => Math.round(value) + " px"
                    backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                    handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                    onMoved: value => root.change("size", Math.round(value))
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_normal_only"; searchTab: "addons"
                title: qsTr("Use Normal select for every cursor"); icon: "󰍽"; wrapText: true
                searchKeywords: "cursor normal select all same pointer curseur identique unique tous"
                description: qsTr("Immediately use the Normal select icon, animation and click point for every role. Turning this off restores your other role customisations.")
                Toggle {
                    enabled: root.loaded && !root.busy
                    checked: root.draft.normalOnly === true
                    accentColor: ThemeBackend.mauve
                    onToggled: value => {
                        root.setNormalOnly(value);
                        checked = Qt.binding(() => root.draft.normalOnly === true);
                    }
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_reset_icons"; searchTab: "addons"
                title: qsTr("Default cursor icons"); icon: "󰑐"; wrapText: true
                searchKeywords: "cursor reset restore default icons curseur réinitialiser défaut icônes"
                description: qsTr("Restore and apply all icons and click points from the selected base theme immediately. The cursor size is kept.")
                ClickButton {
                    buttonText: qsTr("Restore default icons")
                    enabled: root.loaded && !root.busy
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.resetIcons()
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_role"; searchTab: "addons"
                title: qsTr("Cursor role"); icon: "󰍽"; wrapText: true
                description: root.draft.normalOnly ? qsTr("Every cursor uses Normal select. Turn off the toggle above to edit other roles.") : qsTr("Normal, links, text, busy, resizing and drag and drop pointers.")
                Dropdown {
                    Layout.preferredWidth: root.rootObj.s(300)
                    options: root.roleNames
                    currentIndex: root.roleIndex
                    enabled: root.loaded && !root.busy && !root.draft.normalOnly
                    fuzzySearch: true
                    accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                    onSelected: (index, value) => { if (index >= 0) root.selectedRole = root.roleIds[index]; }
                }
                bottomContent: [
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.rootObj.s(8)
                        Repeater {
                            model: ["left_ptr", "pointer", "text", "wait", "progress", "move", "ew-resize", "not-allowed"]
                            delegate: AddonCursorRole {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.rootObj.s(72)
                                cursorInfo: root.roles.find(entry => entry.id === modelData) || ({preview: ""})
                                label: root.roleNames[root.roleIds.indexOf(modelData)]
                                selected: root.selectedRole === modelData
                                enabled: root.loaded && !root.busy && !root.draft.normalOnly
                                onClicked: root.selectedRole = modelData
                            }
                        }
                    }
                ]
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_hotspot"; searchTab: "addons"
                title: root.roleNames[root.roleIndex]; icon: "󰐙"; wrapText: true
                description: root.draft.roles[root.selectedRole] ? qsTr("Custom · %1").arg(root.draft.roles[root.selectedRole].name || "") : qsTr("From base theme")
                ClickButton {
                    buttonText: qsTr("Browse…"); buttonIcon: "󰉋"
                    enabled: root.loaded && !root.busy
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: cursorPicker.openPicker(root.selectedPath)
                }
                ClickButton {
                    buttonText: qsTr("Reset role")
                    enabled: !!root.draft.roles[root.selectedRole] && !root.busy
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.resetRole()
                }
                bottomContent: [
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.rootObj.s(20)
                        AddonCursorPreview {
                            Layout.preferredWidth: root.rootObj.s(128)
                            Layout.preferredHeight: root.rootObj.s(128)
                            cursorInfo: root.currentRole
                            editable: root.loaded
                            onPointSelected: (x, y) => root.setPoint(x, y)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Click the preview to set the exact click point. Arrow keys move it one image pixel at a time.")
                                wrapMode: Text.WordWrap
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11)
                            }
                            Text {
                                text: qsTr("Click point: %1, %2 · %3 × %4 · %5 frame(s)")
                                    .arg(Math.round(root.currentRole.hotspot[0] * Math.max(0, root.currentRole.width - 1)))
                                    .arg(Math.round(root.currentRole.hotspot[1] * Math.max(0, root.currentRole.height - 1)))
                                    .arg(root.currentRole.width).arg(root.currentRole.height).arg(root.currentRole.frames)
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11)
                            }
                        }
                    }
                ]
            },
            AddonCursorTestArea { rootObj: root.rootObj; Layout.fillWidth: true },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_apply"; searchTab: "addons"
                title: root.dirty ? qsTr("Unsaved cursor changes") : qsTr("Cursor settings")
                description: qsTr("Applies to Hyprland, GTK, Qt, XWayland and Flatpak. Applications that draw their own pointer may use a different cursor.")
                icon: "󰆓"; wrapText: true
                ClickButton {
                    buttonText: qsTr("Export scheme")
                    enabled: root.loaded && !root.busy && !previewTimer.running
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.execute("export", root.draft)
                }
                ClickButton {
                    buttonText: qsTr("Discard")
                    enabled: root.dirty && !root.busy
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: { previewTimer.stop(); root.execute("status"); }
                }
                ClickButton {
                    buttonText: root.busy ? qsTr("Working…") : qsTr("Apply")
                    enabled: root.loaded && !root.busy && !previewTimer.running
                    accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
                    onTriggered: root.execute("apply", {settings: root.draft, revision: root.revision})
                }
            }
        ]
    }
}
