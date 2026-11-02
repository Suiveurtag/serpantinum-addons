"""Animated outline on the bar module whose panel is open (the v1 "topbar button effects").

Off by default: Addons → General → "Animated bar outlines" (`addonsV2BarOutlines`). Modules styled classic / button /
minimal get the outline around their button (the pill); every other style gets it around the module itself.
Fail-closed (an anchor must occur exactly once), idempotent (marker present -> unchanged), own MARK.
"""
MARK = 'serpantinum-addons-bar-outline'
OPTION = 'addonsV2BarOutlines'


def _once(text, anchor, label):
    if text.count(anchor) != 1:
        raise ValueError(f'{label} anchor changed')


def _marked(text, name):
    return f'// BEGIN {MARK} {name}\n' in text


def patch_main(text):
    """current_widget also carries the panel argument (network: wifi or bt)."""
    if _marked(text, 'arg-report'):
        return text
    payload = '            widget: masterWindow.currentActive,\n            screen: sName\n'
    _once(text, payload, 'Main widget report')
    text = text.replace(payload, f'            widget: masterWindow.currentActive,\n            arg: masterWindow.activeArg, // {MARK}\n            screen: sName\n', 1)
    anchor = '    property string activeArg: ""\n'
    _once(text, anchor, 'Main activeArg')
    return text.replace(anchor, anchor + f'    // BEGIN {MARK} arg-report\n    onActiveArgChanged: if (currentActive !== "hidden") reportWidgetState()\n    // END {MARK} arg-report\n', 1)


def patch_bar(text):
    """Every bar keeps which panel is open on its own screen (openWidget / openArg)."""
    if _marked(text, 'open panel'):
        return text
    for anchor, label in (('            property string activeWidget: ""\n', 'Bar activeWidget'),
                          ('                    let targetScreen = "";\n', 'Bar target screen'),
                          ('                            targetScreen = parsed.screen || "";\n', 'Bar parsed screen'),
                          ('                    let effectiveWidget = "";\n', 'Bar effective widget')):
        _once(text, anchor, label)
    text = text.replace('            property string activeWidget: ""\n',
                        f'            property string activeWidget: ""\n            // BEGIN {MARK} open panel\n            property string openWidget: ""\n            property string openArg: ""\n            // END {MARK} open panel\n', 1)
    text = text.replace('                    let targetScreen = "";\n', '                    let targetScreen = "";\n                    let widgetArg = ""; // ' + MARK + '\n', 1)
    text = text.replace('                            targetScreen = parsed.screen || "";\n',
                        '                            targetScreen = parsed.screen || "";\n                            widgetArg = parsed.arg || ""; // ' + MARK + '\n', 1)
    return text.replace('                    let effectiveWidget = "";\n', f'''                    let effectiveWidget = "";
                    // BEGIN {MARK} open panel state
                    let ownPanel = !targetScreen || targetScreen === myScreenName;
                    if (barWindowRoot.openWidget !== (ownPanel ? widget : "")) barWindowRoot.openWidget = ownPanel ? widget : "";
                    if (barWindowRoot.openArg !== (ownPanel ? widgetArg : "")) barWindowRoot.openArg = ownPanel ? widgetArg : "";
                    // END {MARK} open panel state
''', 1)


MODULE_BLOCK = f'''
    // BEGIN {MARK} module
    // Panel each module opens: [widget, argument]; the network panel is shared by wifi and bt.
    readonly property var outlinePanel: ({{ timedate: ["calendar", ""], weather: ["calendar", ""], media: ["music", ""],
        wifi: ["network", "wifi"], bt: ["network", "bt"], vol: ["volume", ""], bat: ["system", ""] }})[moduleId] || null
    readonly property bool outlineOpen: !!outlinePanel && !!barWindow && barWindow.openWidget === outlinePanel[0]
        && (outlinePanel[0] !== "network" || ((barWindow.openArg === "bt") === (outlinePanel[1] === "bt")))
    // classic / button / minimal: around the button; any other style: around its group when grouped (drawn by the
    // bar, once for the whole group), else around the module itself
    readonly property Item outlinePill: moduleId === "wifi" ? wifiPill : moduleId === "bt" ? btPill : moduleId === "vol" ? volPill : moduleId === "bat" ? batPill : null
    // the style lives in the face (wifiStyle, volStyle, ...), `variant` is empty for those modules
    readonly property string outlineStyle: variant !== "" ? variant : ((faceItem && faceItem[moduleId + "Style"]) || "")
    readonly property bool outlineOnPill: ["classic", "button", "minimal"].indexOf(outlineStyle) !== -1 && !!outlinePill
    readonly property bool outlineOnGroup: !outlineOnPill && isGrouped && !!providedBackdrop && !!providedBackdrop.parent && providedBackdrop.parent.groupIds !== undefined
    readonly property Item outlineTarget: outlineOnPill ? outlinePill : root
    AddonButtonEffect {{
        parent: root.outlineTarget
        anchors.fill: parent
        requiresOption: "{OPTION}"
        active: root.outlineOpen && !root.outlineOnGroup
        cornerRadius: parent.radius !== undefined ? parent.radius : root.radius
    }}
    // END {MARK} module
'''


def _strip(text, name):
    start = text.find(f'\n    // BEGIN {MARK} {name}\n')
    if start < 0:
        return text
    end = text.index(f'    // END {MARK} {name}\n', start) + len(f'    // END {MARK} {name}\n')
    return text[:start] + text[end:]


def patch_module(text):
    text = _strip(text, 'module')   # the block evolves: always re-inserted
    anchor = '\n    property string orientation: "horizontal"\n'
    _once(text, anchor, 'BarModule orientation')
    return text.replace(anchor, MODULE_BLOCK + anchor, 1)


GROUP_BLOCK = f'''            // BEGIN {MARK} group
            // One outline around the whole group when a module of it opens its panel (clock + weather share the calendar).
            AddonButtonEffect {{
                anchors.fill: parent
                requiresOption: "{OPTION}"
                cornerRadius: groupBgRect.radius
                active: {{
                    void contentWrapper.groupRev;
                    for (let i = 0; i < groupBgRect.groupIds.length; i++) {{
                        const w = contentWrapper.getPositionedWidget(groupBgRect.groupIds[i]);
                        if (w && w.outlineOpen && w.outlineOnGroup) return true;
                    }}
                    return false;
                }}
            }}
            // END {MARK} group
'''


def patch_group(text):
    text = _strip_at(text, 'group', '            ')
    anchor = '            property Item blurSurface: groupBlur\n'
    _once(text, anchor, 'bar group background')
    return text.replace(anchor, anchor + GROUP_BLOCK, 1)


def _strip_at(text, name, indent):
    begin = f'{indent}// BEGIN {MARK} {name}\n'
    start = text.find(begin)
    if start < 0:
        return text
    end_mark = f'{indent}// END {MARK} {name}\n'
    return text[:start] + text[text.index(end_mark, start) + len(end_mark):]


def patch_left(text):
    """The settings and launcher buttons of the left module are outlined while their panel is open."""
    text = _strip_at(text, 'menu button', '        ')
    anchor = '            onClicked: menuBtn.clicked()\n        }\n    }\n'
    _once(text, anchor, 'LeftFace menu button')
    block = f'''        // BEGIN {MARK} menu button
        AddonButtonEffect {{
            anchors.fill: parent
            requiresOption: "{OPTION}"
            active: menuBtn.panel === "launcher"
                ? (LauncherController.isVisible && (!LauncherController.screen || !root.barWindow || !root.barWindow.screen || LauncherController.screen.name === root.barWindow.screen.name))
                : (menuBtn.panel !== "" && !!root.barWindow && root.barWindow.openWidget === menuBtn.panel)
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        }}
        // END {MARK} menu button
'''
    text = text.replace(anchor, anchor[:-6] + block + '    }\n', 1)
    if 'property string panel: ""' not in text:
        glyph = '        property string glyph: ""\n        signal clicked()\n\n        width: root.isVertical ? root.s(root.isCompact ? 28 : 30)'
        _once(text, glyph, 'LeftFace menu glyph')
        text = text.replace(glyph, glyph.replace('        signal clicked()', f'        property string panel: "" // {MARK}\n        signal clicked()'), 1)
        for button, panel in (('settingsBtn', 'guide'), ('launcherBtn', 'launcher')):
            anchor_id = f'            id: {button}\n'
            _once(text, anchor_id, 'LeftFace ' + button)
            text = text.replace(anchor_id, anchor_id + f'            panel: "{panel}" // {MARK}\n', 1)
    return text.replace(f'panel: "settings" // {MARK}', f'panel: "guide" // {MARK}')   # the embedded settings window is the "guide" panel


def transformations(qs):
    return {qs/'Main.qml': patch_main, qs/'bar/Bar.qml': patch_bar, qs/'bar/BarModule.qml': patch_module,
            qs/'bar/TopBar.qml': patch_group, qs/'bar/SideBar.qml': patch_group, qs/'bar/faces/left/LeftFace.qml': patch_left}
