pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

// Cursor customisation.
//
// Model: every control edits a local *draft*. Nothing touches the desktop until
// "Apply". Live previews of the draft are rendered by the backend (debounced), and
// requests are queued instead of being dropped while the backend is busy.
ColumnLayout {
    id: root
    required property var rootObj
    readonly property string backend: Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/custom_cursor.py"

    // ---- State -----------------------------------------------------------------
    property var draft: ({baseTheme: "", size: 32, roles: {}, normalOnly: false})
    property var saved: ({})
    property var themes: []
    property var roles: []
    property string revision: ""
    property string selectedRole: "left_ptr"
    property string error: ""
    property string notice: ""
    property bool loaded: false
    property bool conflict: false
    readonly property bool applying: worker.running && worker.action === "apply"
    readonly property bool working: worker.running || queued !== null
    readonly property bool editable: loaded && !applying
    readonly property bool dirty: loaded && JSON.stringify(draft) !== JSON.stringify(saved)

    // Single pending job; a newer request of the same kind replaces an older one.
    property var queued: null

    // ---- Static catalogue ------------------------------------------------------
    readonly property var roleIds: ["left_ptr", "help", "progress", "wait", "pointer", "text", "vertical-text", "crosshair", "cell", "move", "grab", "grabbing", "not-allowed", "copy", "alias", "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "n-resize", "s-resize", "e-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize", "zoom-in", "zoom-out", "context-menu", "pencil"]
    readonly property var roleNames: [qsTr("Normal select"), qsTr("Help select"), qsTr("Working in background"), qsTr("Busy"), qsTr("Link select"), qsTr("Text select"), qsTr("Vertical text"), qsTr("Precision select"), qsTr("Cell select"), qsTr("Move"), qsTr("Grab"), qsTr("Grabbing"), qsTr("Unavailable"), qsTr("Copy"), qsTr("Create link"), qsTr("Horizontal resize"), qsTr("Vertical resize"), qsTr("Diagonal resize ↗"), qsTr("Diagonal resize ↖"), qsTr("Resize top"), qsTr("Resize bottom"), qsTr("Resize right"), qsTr("Resize left"), qsTr("Resize top right"), qsTr("Resize top left"), qsTr("Resize bottom right"), qsTr("Resize bottom left"), qsTr("Zoom in"), qsTr("Zoom out"), qsTr("Context menu"), qsTr("Handwriting")]
    readonly property var groups: [
        {title: qsTr("Everyday"), ids: ["left_ptr", "pointer", "text", "help", "wait", "progress", "not-allowed", "crosshair"]},
        {title: qsTr("Move and drag"), ids: ["move", "grab", "grabbing", "copy", "alias", "cell", "context-menu", "pencil", "vertical-text", "zoom-in", "zoom-out"]},
        {title: qsTr("Resize"), ids: ["ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "n-resize", "s-resize", "e-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize"]}
    ]
    readonly property int columns: Math.max(2, Math.floor((width - rootObj.s(48)) / rootObj.s(92)))
    readonly property var currentRole: roleInfo(selectedRole)
    readonly property var customRole: draft.roles ? draft.roles[selectedRole] : undefined
    readonly property string selectedPath: customRole ? (customRole.originalPath || customRole.source) : ""
    readonly property int customCount: draft.roles ? Object.keys(draft.roles).length : 0
    readonly property string status: error ? error
        : applying ? qsTr("Applying…")
        : conflict ? qsTr("Settings changed elsewhere.")
        : dirty ? qsTr("Unsaved changes — previewed below, press Apply to use them.")
        : notice ? notice
        : qsTr("Theme, size and the shape of every pointer.")

    function roleName(id) {
        let index = roleIds.indexOf(id);
        return index >= 0 ? roleNames[index] : id;
    }
    function roleInfo(id) {
        return roles.find(entry => entry.id === id) || ({id: id, preview: "", source: "", hotspot: [0, 0], width: 0, height: 0, frames: 0});
    }
    function clone(value) { return JSON.parse(JSON.stringify(value)); }

    // ---- Backend job queue -----------------------------------------------------
    function request(action, value, role) {
        // A preview never replaces a queued apply/import/install.
        if (queued && queued.action !== "preview" && action === "preview") return;
        queued = {action: action, value: value, role: role || ""};
        pump();
    }
    function pump() {
        if (worker.running || !queued) return;
        let job = queued;
        queued = null;
        error = "";
        worker.action = job.action;
        worker.requestSignature = JSON.stringify(draft);
        worker.role = job.role;
        let args = ["python3", backend, job.action];
        if (job.value !== undefined) args.push(typeof job.value === "string" ? job.value : JSON.stringify(job.value));
        worker.command = args;
        worker.running = true;
    }
    function edit(mutator) {
        if (!editable) return;
        let next = clone(draft);
        mutator(next);
        draft = next;
        previewTimer.restart();
    }
    function apply() {
        if (!loaded || applying || !dirty) return;
        previewTimer.stop();
        queued = null;
        notice = "";
        request("apply", {settings: draft, revision: revision});
    }
    function discard() {
        previewTimer.stop();
        queued = null;
        conflict = false;
        request("status");
    }

    // ---- Edits (draft only) ----------------------------------------------------
    function setSize(value) { edit(next => { next.size = Math.round(value); }); }
    function setTheme(themeId) { edit(next => { next.baseTheme = themeId; }); }
    function setNormalOnly(enabled) {
        edit(next => { next.normalOnly = enabled; });
        if (enabled) selectedRole = "left_ptr";
    }
    function setPoint(x, y) {
        if (!currentRole.source) return;
        let role = selectedRole;
        let source = currentRole.source;
        edit(next => {
            let custom = next.roles[role] || {source: source, name: roleName(role), originalPath: source};
            custom.hotspot = [x, y];
            next.roles[role] = custom;
        });
        // Move the crosshair immediately; the real preview follows.
        roles = roles.map(entry => entry.id === role ? Object.assign({}, entry, {hotspot: [x, y]}) : entry);
    }
    function resetRole() {
        let role = selectedRole;
        edit(next => { delete next.roles[role]; });
    }
    function resetAll() {
        edit(next => { next.roles = {}; next.normalOnly = false; });
        selectedRole = "left_ptr";
    }

    // ---- Backend responses -----------------------------------------------------
    function accept(raw, action, role, signature) {
        let result;
        try { result = JSON.parse(raw); } catch (failure) { if (!error) error = qsTr("Unexpected reply from the cursor backend."); return; }
        if (!result.ok) {
            error = result.error || qsTr("Could not update cursor settings.");
            conflict = /changed elsewhere/i.test(error);
            return;
        }
        let data = result.data;
        if (action === "export") {
            notice = qsTr("Scheme exported to %1").arg(data.path);
        } else if (action === "import") {
            edit(next => { next.roles[role] = {source: data.source, name: data.name, originalPath: data.originalPath, hotspot: data.hotspot}; });
            notice = qsTr("“%1” set for %2.").arg(data.name).arg(roleName(role));
        } else if (action === "install") {
            themes = data.themes;
            if (data.installed && data.installed.length) edit(next => { next.baseTheme = data.installed[0]; });
            notice = qsTr("Theme imported.");
        } else {
            themes = data.themes;
            roles = data.roles;
            if (action === "preview") {
                // Stale preview: the draft moved on while rendering.
                if (signature !== JSON.stringify(draft)) previewTimer.restart();
            } else {
                draft = data.settings;
                saved = clone(data.settings);
                revision = data.revision;
                loaded = true;
                conflict = false;
                notice = action === "apply" ? qsTr("Applied. Restart applications that still show the previous cursor.") : "";
            }
            if (data.warnings && data.warnings.length) notice = data.warnings.join("\n");
        }
    }

    Process {
        id: worker
        property string action: ""
        property string role: ""
        property string requestSignature: ""
        stdout: StdioCollector {
            onStreamFinished: root.accept(text, worker.action, worker.role, worker.requestSignature)
        }
        stderr: StdioCollector { onStreamFinished: { if (text.trim() && !root.error) root.error = text.trim(); } }
        onExited: code => {
            if (code !== 0 && !root.error) root.error = qsTr("Could not update cursor settings.");
            root.pump();
        }
    }
    Timer {
        id: previewTimer
        interval: 250
        onTriggered: root.request("preview", root.draft)
    }
    Component.onCompleted: request("status")

    ImagePicker {
        id: cursorPicker
        rootObj: root.rootObj
        titleText: qsTr("Choose cursor image or animation")
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.cur", "*.ani", "*.ico", "*.xcursor", "*.cursor"]
        // Remember the role at request time: the selection may change while importing.
        onImageSelected: (path, name) => root.request("import", path, root.selectedRole)
    }
    ImagePicker {
        id: themePicker
        rootObj: root.rootObj
        titleText: qsTr("Import cursor theme")
        nameFilters: ["*.zip", "*.tar", "*.tar.gz", "*.tgz", "*.tar.xz", "*.tar.bz2"]
        showPreview: false
        onImageSelected: (path, name) => root.request("install", path)
    }

    spacing: rootObj.s(8)

    SettingsGroup {
        rootObj: root.rootObj
        title: qsTr("Cursors"); icon: "󰍽"; wrapText: true
        description: root.status
        ClickButton {
            buttonText: qsTr("Reload")
            visible: root.conflict
            accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
            onTriggered: root.discard()
        }
        ClickButton {
            buttonText: qsTr("Discard")
            visible: root.dirty && !root.conflict
            enabled: !root.applying
            accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
            onTriggered: root.discard()
        }
        ClickButton {
            buttonText: root.applying ? qsTr("Applying…") : qsTr("Apply")
            visible: root.dirty && !root.conflict
            enabled: root.editable
            accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
            onTriggered: root.apply()
        }
        subSettings: [
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_theme"; searchTab: "addons"
                title: qsTr("Theme"); icon: "󰏘"; wrapText: true
                searchKeywords: "cursor theme import curseur thème pointer souris"
                description: qsTr("The base set of pointers. Your custom images below stay on top of it.")
                Dropdown {
                    Layout.preferredWidth: root.rootObj.s(240)
                    options: root.themes.map(theme => theme.name)
                    currentIndex: root.themes.findIndex(theme => theme.id === root.draft.baseTheme)
                    enabled: root.editable
                    fuzzySearch: true
                    accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface0; textColor: ThemeBackend.text
                    onSelected: (index, value) => {
                        if (index >= 0 && root.themes[index].id !== root.draft.baseTheme) root.setTheme(root.themes[index].id);
                    }
                }
                ClickButton {
                    buttonText: qsTr("Import…"); buttonIcon: "󰉋"
                    enabled: root.editable
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: themePicker.openPicker(Quickshell.env("HOME") + "/Downloads")
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_size"; searchTab: "addons"
                title: qsTr("Size"); icon: "󰩨"; wrapText: true
                searchKeywords: "cursor size taille curseur"
                description: qsTr("%1 px · sharp on scaled displays").arg(root.draft.size)
                Draggable {
                    Layout.preferredWidth: root.rootObj.s(220)
                    implicitHeight: root.rootObj.s(18)
                    from: 16; to: 128; stepSize: 1
                    value: root.draft.size
                    enabled: root.editable
                    showValueBubble: true
                    valueFormatter: value => Math.round(value) + " px"
                    backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                    handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                    onMoved: value => root.setSize(value)
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_normal_only"; searchTab: "addons"
                title: qsTr("Same pointer everywhere"); icon: "󰍽"; wrapText: true
                searchKeywords: "cursor normal select all same pointer curseur identique unique tous"
                description: qsTr("Use the Normal select pointer in every situation. Your other customisations are kept for when you turn this off.")
                Toggle {
                    enabled: root.editable
                    checked: root.draft.normalOnly === true
                    accentColor: ThemeBackend.mauve
                    onToggled: value => {
                        root.setNormalOnly(value);
                        checked = Qt.binding(() => root.draft.normalOnly === true);
                    }
                }
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_role"; searchTab: "addons"
                title: qsTr("Pointer shapes"); icon: "󰐙"; wrapText: true
                searchKeywords: "cursor role icon image custom pointer hotspot curseur icône image personnalisé"
                description: root.draft.normalOnly
                    ? qsTr("Every pointer currently uses Normal select. Turn off “Same pointer everywhere” to edit the others.")
                    : qsTr("Pick a shape to preview or replace it. A dot marks shapes you customised (%1).").arg(root.customCount)
                ClickButton {
                    buttonText: qsTr("Restore defaults")
                    enabled: root.editable && (root.customCount > 0 || root.draft.normalOnly)
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.resetAll()
                }
                bottomContent: [
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.rootObj.s(10)
                        Repeater {
                            model: root.groups
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: root.rootObj.s(6)
                                Text {
                                    text: group.modelData.title
                                    color: ThemeBackend.subtext0
                                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11); font.bold: true
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: root.columns
                                    rowSpacing: root.rootObj.s(6); columnSpacing: root.rootObj.s(6)
                                    Repeater {
                                        model: group.modelData.ids
                                        delegate: AddonCursorRole {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: root.rootObj.s(76)
                                            cursorInfo: root.roleInfo(modelData)
                                            label: root.roleName(modelData)
                                            selected: root.selectedRole === modelData
                                            customized: !!(root.draft.roles && root.draft.roles[modelData])
                                            enabled: root.editable && !root.draft.normalOnly
                                            onClicked: root.selectedRole = modelData
                                        }
                                    }
                                }
                            }
                        }
                    }
                ]
            },
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_cursor_hotspot"; searchTab: "addons"
                title: root.roleName(root.selectedRole); icon: "󰆹"; wrapText: true
                searchKeywords: "cursor image hotspot click point curseur point de clic"
                description: root.customRole
                    ? qsTr("Custom · %1").arg(root.customRole.name || "")
                    : qsTr("From the base theme")
                ClickButton {
                    buttonText: qsTr("Choose image…"); buttonIcon: "󰉋"
                    enabled: root.editable && !root.draft.normalOnly
                    accentColor: ThemeBackend.mauve; textColor: ThemeBackend.crust
                    onTriggered: cursorPicker.openPicker(root.selectedPath)
                }
                ClickButton {
                    buttonText: qsTr("Reset")
                    enabled: root.editable && !!root.customRole
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.resetRole()
                }
                bottomContent: [
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.rootObj.s(20)
                        AddonCursorPreview {
                            Layout.preferredWidth: root.rootObj.s(140)
                            Layout.preferredHeight: root.rootObj.s(140)
                            cursorInfo: root.currentRole
                            editable: root.editable && !root.draft.normalOnly
                            onPointSelected: (x, y) => root.setPoint(x, y)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.rootObj.s(6)
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("The crosshair is the click point — where the pointer actually clicks. Click the preview to move it, or use the arrow keys for pixel-perfect placement.")
                                wrapMode: Text.WordWrap
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.rootObj.s(11)
                            }
                            Text {
                                visible: root.currentRole.width > 0
                                text: qsTr("Click point %1, %2  ·  %3 × %4 px  ·  %5 frame(s)")
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
                rootObj: root.rootObj; settingId: "addons_cursor_export"; searchTab: "addons"
                title: qsTr("Share this scheme"); icon: "󰆓"; wrapText: true
                description: qsTr("Applies to Hyprland, GTK, Qt, XWayland and Flatpak. Applications that draw their own pointer may differ.")
                ClickButton {
                    buttonText: qsTr("Export scheme")
                    enabled: root.editable && !root.working
                    accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text
                    onTriggered: root.request("export", root.draft)
                }
            }
        ]
    }
}
