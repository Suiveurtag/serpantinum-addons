"""Christmas: seasonal presentation hooks across the shell. Owns its mark so other companions never strip it.

Every hook is a marked block inserted after a single anchor line; an unknown anchor stops the install (fail closed),
a reinstall replaces the block (idempotent) and remove() takes every block and declaration out again.
"""
import hashlib
import json
import re
from pathlib import Path

MARK = 'serpantinum-christmas-v2'
TYPES = ['singleton Christmas 1.0 christmas/Christmas.qml'] + [f'{name} 1.0 christmas/{name}.qml' for name in
         ('ChristmasSettings', 'ChristmasCard', 'ChristmasHost', 'ChristmasPanel', 'ChristmasTouch', 'ChristmasGarland',
          'ChristmasFrost', 'ChristmasRibbon', 'ChristmasLights', 'ChristmasBow', 'ChristmasHolly', 'ChristmasBurst',
          'ChristmasIntro', 'ChristmasWindowLights', 'ChristmasSendOff')]


def remove_blocks(text):
    return re.sub(r'^[ \t]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ \t]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)


def insert(text, anchor, name, block):
    """Insert `block` (written at indent 0) right after the single line `anchor`, at the anchor's indentation."""
    text = re.sub(r'^[ \t]*// BEGIN ' + MARK + ' ' + re.escape(name) + r'\n.*?^[ \t]*// END ' + MARK + ' ' + re.escape(name) + r'\n',
                  '', text, flags=re.S | re.M)
    if text.count(anchor) != 1:
        raise ValueError(f'Christmas anchor changed: {name} ({anchor.strip()})')
    indent = anchor[:len(anchor) - len(anchor.lstrip(' '))]
    body = ''.join(indent + line if line.strip() else line for line in block.strip('\n').splitlines(keepends=True))
    return text.replace(anchor, f'{anchor}{indent}// BEGIN {MARK} {name}\n{body}\n{indent}// END {MARK} {name}\n', 1)


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # Window lights and the switch-on garland live in their own layer windows, one per screen.
    text = re.sub(r'^[ \t]*// BEGIN ' + MARK + r' host\n.*?^[ \t]*// END ' + MARK + r' host\n', '', text, flags=re.S | re.M)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Christmas shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    ChristmasHost {{}}\n    // END {MARK} host\n' + anchor, 1)


PANEL_EDGE = '''edge: {
    if (scene === "guide" || scene === "wallpaper") return "center";
    if (scene === "system") return masterWindow.barPosition === "right" ? "left" : "right";
    if (scene === "notifications") return "left";
    if (scene === "calendar" && (masterWindow.barPosition === "left" || masterWindow.barPosition === "right")) return "top";
    return masterWindow.barPosition;
}'''


def patch_main(text):
    # Window-sized layer over the panels: the gift unwrapping and the holly sit outside the panel's clipping.
    return insert(text, '    id: masterWindow\n', 'panel gift', '''
Loader {
    id: christmasGift; enabled: false; anchors.fill: parent; z: 11
    readonly property bool shown: masterWindow.isVisible && masterWindow.currentActive !== "hidden"
    // stays loaded a moment after the panel goes, for the outro (reading `item` in `active` would be a binding loop)
    property bool held: false
    property Timer linger: Timer { interval: 200; onTriggered: christmasGift.held = false }
    onShownChanged: if (shown) { linger.stop(); held = true; } else linger.restart()
    active: Christmas.panels && held
    sourceComponent: ChristmasPanel {
        open: christmasGift.shown && masterWindow.targetActive !== "hidden"
        panelRect: Qt.rect(masterWindow._animX, masterWindow._animY, masterWindow._animW, masterWindow._animH)
        scene: masterWindow.currentActive
        serial: masterWindow.switchGeneration
        screenName: masterWindow.screen ? masterWindow.screen.name : ""
        cornerRadius: ThemeBackend.borderRadius
''' + '\n'.join('        ' + line for line in PANEL_EDGE.splitlines()) + '''
    }
}
''')


def patch_launcher(text):
    return insert(text, '    id: launcherWindow\n', 'launcher gift', '''
Loader {
    id: christmasGift; enabled: false; anchors.fill: parent; z: 201
    readonly property bool shown: launcherWindow.isVisible
    property bool held: false
    property Timer linger: Timer { interval: 200; onTriggered: christmasGift.held = false }
    onShownChanged: if (shown) { linger.stop(); held = true; } else linger.restart()
    active: Christmas.panels && held
    sourceComponent: ChristmasPanel {
        panelRect: Qt.rect(container.x, container.y, container.width, container.height)
        scene: "launcher"
        edge: launcherWindow.attachEdge
        open: launcherWindow.isVisible
        screenName: launcherWindow.screen ? launcherWindow.screen.name : ""
        cornerRadius: container.dynamicCornerRadius
    }
}
''')


def patch_draggable(text):
    text = insert(text, '    id: root\n', 'slider wheel option', '''
property bool christmasDisableWheel: false
''')
    return insert(text, '        onWheel: wheel => {\n', 'slider wheel guard', '''
if (root.christmasDisableWheel) { wheel.accepted = false; return; }
''')


def patch_settings_row(text):
    # Explicit parent/property: SettingsRow's default children are controls. Banner rows (custom content) stay clear.
    return insert(text, '    id: root\n', 'row frost', '''
readonly property bool christmasFrostEligible: root.customLeftContent === null && root.height <= root.s(110)
property HoverHandler christmasHover: HoverHandler {
    parent: root
    enabled: Christmas.settings && root.christmasFrostEligible && root.isOwnTabLive()
}
property Item christmasFrost: Loader {
    parent: root
    anchors.fill: parent
    enabled: false
    active: Christmas.settings && root.christmasFrostEligible
    sourceComponent: ChristmasFrost {
        visible: root.isOwnTabLive()
        active: Christmas.enabled
        engaged: root.enabled && !root.dimmed && (root.christmasHover.hovered || root.highlightFlash > 0.1)
        cornerRadius: root.cornerRadius
    }
}
''')


def _button(text, bell):
    return insert(text, '    id: root\n', 'button touch', '''
property Item christmasTouch: Loader {
    parent: root
    anchors.fill: parent
    z: 9
    enabled: false
    active: Christmas.buttons && root.visible
    sourceComponent: ChristmasTouch {
        cornerRadius: root.cornerRadius
        hovered: root.isHoveredOrHighlighted && root.enabled
        bell: BELL
    }
}
Connections {
    target: root
    function onClicked() { if (root.christmasTouch.item) root.christmasTouch.item.press(btnMa.mouseX, btnMa.mouseY); }
}
'''.replace('BELL', bell))


def patch_icon_button(text):
    return _button(text, 'btnContainer')


def patch_click_button(text):
    return _button(text, 'null')


def patch_fill_button(text):
    # A hold-to-confirm button pulls a cracker when it fires.
    return insert(text, '    id: root\n', 'button cracker', '''
property Item christmasTouch: Loader {
    parent: root
    anchors.fill: parent
    z: 21
    enabled: false
    active: Christmas.buttons && root.visible
    sourceComponent: ChristmasTouch {
        cornerRadius: root.effectiveRadius
        hovered: root.isHoveredOrHighlighted && root.enabled
        cracker: true
    }
}
Connections {
    target: root
    function onTriggered() { if (root.christmasTouch.item) root.christmasTouch.item.press(root.width / 2, root.height / 2); }
}
''')


def patch_bar(text):
    # Each bar section gets its own string of lights; a solid bar gets one along its whole length, above the bar's
    # surface and below the modules (z >= 1).
    text = insert(text, '            id: groupBgRect\n', 'bar garland', '''
Loader {
    anchors.fill: parent; z: 1; enabled: false
    active: Christmas.bar && groupBgRect.visible && (!barWindow || barWindow.isRevealed)
    sourceComponent: ChristmasGarland {
        cornerRadius: groupBgRect.radius
        edge: barWindow ? barWindow.barPosition : "top"
        seed: groupBgRect.groupIds.join("").length
    }
}
''')
    return insert(text, '        id: solidBackground\n', 'bar garland solid', '''
property Item christmasGarland: Loader {
    parent: contentWrapper
    x: solidBackground.x; y: solidBackground.y
    width: solidBackground.width; height: solidBackground.height
    z: 0.5; enabled: false
    active: Christmas.bar && solidBackground.visible && (!barWindow || barWindow.isRevealed)
    sourceComponent: ChristmasGarland {
        cornerRadius: solidBackground.radius
        edge: barWindow ? barWindow.barPosition : "top"
        seed: 7
    }
}
''')


def patch_bar_module(text):
    # A module outside any group draws its own pill: it gets its own string.
    return insert(text, '    id: root\n', 'module garland', '''
Loader {
    anchors.fill: parent; enabled: false
    active: Christmas.bar && !root.isGrouped && (!root.isSolid || root.distinctPills) && root.effectiveVisible
        && (!root.barWindow || root.barWindow.isRevealed)
    sourceComponent: ChristmasGarland {
        cornerRadius: root.radius
        edge: root.barWindow ? root.barWindow.barPosition : "top"
        seed: String(root.moduleId).length
    }
}
''')


def patch_notification(text):
    return insert(text, '            id: bgContainer\n', 'notification ribbon', '''
Loader {
    enabled: false; anchors.fill: parent
    active: Christmas.notifications && typeRoot.visible
    sourceComponent: ChristmasRibbon { cornerRadius: visualItem.radius; urgent: typeRoot.urgency === 2 }
}
''')


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 christmas/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def resources(payload, qs):
    # Qt caches GPU programs by URL across hot reloads: each shader package is installed under its content hash and
    # every QML file using one is rewritten to it. A package that does not match its source stops the install.
    shaders = payload/'shaders'
    manifest = json.loads((shaders/'manifest.json').read_text())
    names = {}
    for source in sorted(shaders.glob('*.frag')):
        package = shaders/(source.name + '.qsb')
        record = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'package_sha256': hashlib.sha256(package.read_bytes()).hexdigest()}
        if manifest.get(source.stem) != record:
            raise ValueError(f'Christmas shader {source.stem} source/package mismatch; run python3 scripts/christmas/shaders.py')
        names[package.name] = f"{source.stem}.{record['package_sha256'][:12]}.frag.qsb"
    out = []
    for source in sorted(payload.rglob('*')):
        if not source.is_file():
            continue
        path, blob = qs/'christmas'/source.relative_to(payload), source.read_bytes()
        if source.parent == shaders and source.name in names:
            path = path.with_name(names[source.name])
        elif source.suffix == '.qml':
            for plain, hashed in names.items():
                blob = blob.replace(f'shaders/{plain}'.encode(), f'shaders/{hashed}'.encode())
        out.append((path, blob))
    return out


def stale_shaders(qs, everything=False):
    # Superseded hashed packages (all of them when Christmas is removed), deleted once the new ones are in place.
    shaders = qs/'christmas/shaders'
    keep = set() if everything else {path.name for path, _ in resources(Path(__file__).resolve().parent/'payload/christmas', qs) if path.parent == shaders}
    return sorted(p for p in shaders.glob('*.frag.qsb') if p.name not in keep) if shaders.is_dir() else []


def transformations(qs):
    result = {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell, qs/'Main.qml': patch_main,
              qs/'launcher/Launcher.qml': patch_launcher,
              qs/'reusables/guide/SettingsRow.qml': patch_settings_row,
              qs/'reusables/behavior/Draggable.qml': patch_draggable,
              qs/'reusables/buttons/IconButton.qml': patch_icon_button,
              qs/'reusables/buttons/ClickButton.qml': patch_click_button,
              qs/'reusables/buttons/FillButton.qml': patch_fill_button,
              qs/'bar/TopBar.qml': patch_bar, qs/'bar/BarModule.qml': patch_bar_module,
              qs/'notifications/Notification.qml': patch_notification}
    if (qs/'bar/SideBar.qml').is_file():
        result[qs/'bar/SideBar.qml'] = patch_bar
    return result
