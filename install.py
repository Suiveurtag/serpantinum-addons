#!/usr/bin/env python3
"""Install only v2 addons, preserving upstream files and unrelated v1 work."""
import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import tempfile
import capri
import clawd
import seasonal
import seasonal_surfaces
import wallpaper_engine
from datetime import datetime
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
QS = Path(os.environ.get('SERPANTINUM_HOME', DATA / 'serpantinum')) / 'src/quickshell'
DEPLOY = DATA / 'serpantinum-addons-v2'
MARK = 'serpantinum-addons-v2'


def shader_package_name(folder, stem='atmosphere'):
    source = folder/(stem + '.frag')
    package = folder/(stem + '.frag.qsb')
    manifest = json.loads((folder/'manifest.json').read_text())
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
    if manifest.get('source_sha256') != source_hash or manifest.get('package_sha256') != package_hash:
        raise ValueError(f'Shader {stem} source/package mismatch; run python3 scripts/build-seasonal-shaders.py')
    return stem + '.' + package_hash[:12] + '.frag.qsb'


def patch_guide(text):
    import re
    addons_entry = '        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "AddonsTab.qml", iconOffsetX: 0 },'
    addons_entry_with_subtabs = '''        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "AddonsTab.qml", iconOffsetX: 0,
            subtabs: [
                { id: "AddonsGeneral", key: "addons_general", name: "General", icon: "󰒓", file: "AddonsTab.qml", iconOffsetX: 0 },
                { id: "AddonsMouse", key: "addons_mouse", name: "Mouse", icon: "󰍽", file: "AddonsMouseTab.qml", iconOffsetX: 0 },
                { id: "AddonsBanners", key: "addons_banners", name: "Banners", icon: "󰓻", file: "AddonsBannersTab.qml", iconOffsetX: 0 }
            ]
        },'''
    # v2.2.8 moved guide navigation and content into a model-driven loader.
    # Register addon tabs in that model so upstream handles the sidebar and content.
    if 'property var tabsModel: [' in text:
        if addons_entry in text:
            text = text.replace(addons_entry, addons_entry_with_subtabs, 1)
        if '// BEGIN serpantinum-addons-v2 tabs' not in text:
            anchor = '        { id: "About", key: "about", name: "About", icon: "󰋽", file: "AboutTab.qml", iconOffsetX: 0 }'
            block = '''        // BEGIN serpantinum-addons-v2 tabs
''' + addons_entry_with_subtabs + '''
        { id: "Monitors", key: "addon_monitors", name: "Monitors", icon: "󰍹", file: "AddonMonitorsTab.qml", iconOffsetX: 0 },
        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },
        // END serpantinum-addons-v2 tabs
'''
            if text.count(anchor) == 1:
                text = text.replace(anchor, block + anchor, 1)
            else:
                # Recent upstream Guide versions omit iconOffsetX from model
                # entries, so keep the About row as the insertion anchor by
                # its stable identity and file instead of its full formatting.
                about = re.compile(
                    r'(?m)^[ \t]*\{ id: "About", key: "about", name: "About", '
                    r'icon: "[^"]+"(?:, separatorBefore: true)?, file: "AboutTab\.qml"(?:, iconOffsetX: 0)? \},?$'
                )
                matches = list(about.finditer(text))
                if len(matches) != 1:
                    raise ValueError('Guide tabs model anchor changed')
                match = matches[0]
                text = text[:match.start()] + block + match.group(0) + text[match.end():]
        # Added after the first release, so existing tab blocks gain it on reinstall.
        keybinds_entry = '        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },'
        startup_entry = '        { id: "Startup", key: "addon_startup", name: "Startup", icon: "󰐥", file: "AddonStartupTab.qml", iconOffsetX: 0 },'
        if startup_entry not in text:
            if text.count(keybinds_entry) != 1: raise ValueError('Guide keybinds tab anchor changed')
            text = text.replace(keybinds_entry, keybinds_entry + '\n' + startup_entry, 1)
        old ='                return I18n.t("guide.tabs." + (t.key || t.id).toLowerCase(), t.name || t.id);'
        new = '''                let key = "guide.tabs." + (t.key || t.id).toLowerCase();
                let label = I18n.t(key);
                return label && label !== key ? label : (t.name || t.id);'''
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text and 'return translated === translationKey ? (t.name || t.id) : translated;' not in text and 'return translated && translated !== translationKey ? translated : (t.name || t.id);' not in text:
            raise ValueError('Guide tab title fallback anchor changed')
        old_subtab = '                        return I18n.t("guide.tabs." + (st.key || st.id).toLowerCase(), st.name || st.id);'
        new_subtab = '''                        let key = "guide.tabs." + (st.key || st.id).toLowerCase();
                        let label = I18n.t(key);
                        return label && label !== key ? label : (st.name || st.id);'''
        if old_subtab in text:
            text = text.replace(old_subtab, new_subtab, 1)
        elif new_subtab not in text:
            raise ValueError('Guide subtab title fallback anchor changed')
        # Earlier deployed patches already used this resolver form.
        text = text.replace(
            'return translated === translationKey ? (t.name || t.id) : translated;',
            'return translated && translated !== translationKey ? translated : (t.name || t.id);')
        return text
    # Migrate our first revision while leaving every upstream tab intact.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs[\s,]*(?=    \])', '', text, flags=re.S)
    text = re.sub(r'\n                                // BEGIN serpantinum-addons-v2 sidebar.*?                                // END serpantinum-addons-v2 sidebar\n', '', text, flags=re.S)
    text = text.replace('tabAbout, tabAddonAddons, tabAddonMonitors, tabAddonKeybinds', 'tabAbout')
    anchor = '        { id: "About", key: "about", name: "About", icon: "󰋽", file: "AboutTab.qml", iconOffsetX: 0 }'
    text = text.replace(anchor + ',\n', anchor + '\n')
    if text.count(anchor) != 1: raise ValueError('Guide tabs anchor changed')
    block = '''        // BEGIN serpantinum-addons-v2 tabs
''' + addons_entry_with_subtabs + '''
        { id: "Monitors", key: "addon_monitors", name: "Monitors", icon: "󰍹", file: "AddonMonitorsTab.qml", iconOffsetX: 0 },
        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },
        // END serpantinum-addons-v2 tabs
'''
    # End marker sits before About now; remove it separately on later installs.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs\n', '', text, flags=re.S)
    text = text.replace(anchor, block + anchor, 1)
    # I18n.t's second parameter is interpolation data, not a fallback string.
    # If a language pack has no addon tab key it returns the key itself, which
    # is why the Guide displayed `guide.tabs.addons` in the sidebar.
    old_title = 'return I18n.t("guide.tabs." + (t.key || t.id).toLowerCase(), t.name || t.id);'
    new_title = '''let translationKey = "guide.tabs." + (t.key || t.id).toLowerCase();
                let translated = I18n.t(translationKey);
                return translated === translationKey ? (t.name || t.id) : translated;'''
    text = text.replace(old_title, new_title)
    text = text.replace(
        'I18n.t("guide.tabs." + (tabDelegate.modelData.key || tabDelegate.modelData.id).toLowerCase(), tabDelegate.modelData.name || tabDelegate.modelData.id)',
        'root.resolveTabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id)')
    legacy_sidebar_anchor = '                                Rectangle {\n                                    id: tabAbout'
    if legacy_sidebar_anchor not in text:
        # Newer Guide versions build their sidebar directly from tabsModel.
        if 'tabAbout' not in text: return text
        raise ValueError('Guide sidebar anchor changed')
    start = text.index(legacy_sidebar_anchor)
    depth = 0
    for stop in range(start, len(text)):
        if text[stop] == '{': depth += 1
        elif text[stop] == '}':
            depth -= 1
            if depth == 0: break
    original = text[start:stop + 1]
    # About's prior index can be 11 (first install) or 14 (reinstall).
    original = original.replace('(14)', '(11)').replace('[14]', '[11]').replace('=== 14', '=== 11').replace('= 14;', '= 11;')
    blocks = []
    for index, name, icon in [(11, 'Addons', '󰐱'), (12, 'Monitors', '󰍹'), (13, 'Keybinds', '󰌌')]:
        entry = original.replace('tabAbout', 'tabAddon' + name).replace('(11)', '(' + str(index) + ')').replace('[11]', '[' + str(index) + ']').replace('=== 11', '=== ' + str(index)).replace('= 11;', '= ' + str(index) + ';').replace('I18n.t("guide.tabs.about", "About")', '"' + name + '"').replace('"󰋽"', '"' + icon + '"')
        blocks.append(entry)
    about = original.replace('(11)', '(14)').replace('[11]', '[14]').replace('=== 11', '=== 14').replace('= 11;', '= 14;')
    sidebar = '\n                                // BEGIN serpantinum-addons-v2 sidebar\n' + '\n'.join(blocks) + '\n                                // END serpantinum-addons-v2 sidebar\n'
    text = text[:start] + sidebar + about + text[stop + 1:]
    return text.replace('                                    tabAbout\n', '                                    tabAddonAddons, tabAddonMonitors, tabAddonKeybinds, tabAbout\n', 1)


def patch_guide_sidebar(text):
    subtab_id = 'sub' if 'id: sub\n' in text else 'subtabItem'
    changes = [
        (
            'text: I18n.t("guide.tabs." + (tabDelegate.modelData.key || tabDelegate.modelData.id).toLowerCase(), tabDelegate.modelData.name || tabDelegate.modelData.id)',
            'text: popup.resolveTabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id)',
            'text: popup.resolveTabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id)' in text,
        ),
        (
            f'text: I18n.t("guide.tabs." + ({subtab_id}.modelData.key || {subtab_id}.modelData.id).toLowerCase(), {subtab_id}.modelData.name || {subtab_id}.modelData.id)',
            f'text: popup.resolveSubtabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id, {subtab_id}.modelData.key || {subtab_id}.modelData.id)',
            f'text: popup.resolveSubtabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id, {subtab_id}.modelData.key || {subtab_id}.modelData.id)' in text,
        ),
    ]
    for old, new, already_patched in changes:
        if old in text:
            text = text.replace(old, new, 1)
        elif not already_patched:
            raise ValueError('Guide sidebar title anchor changed')
    return text


def patch_idle_tab(text):
    if 'import QtQuick.Effects' not in text:
        text = text.replace('import QtQuick\n', 'import QtQuick\nimport QtQuick.Effects\n', 1)
    if 'import Quickshell.Services.UPower' not in text:
        text = text.replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Services.UPower\n', 1)
    laptop_property = '    readonly property bool codexModeAvailable: UPower.displayDevice.ready ? UPower.displayDevice.isLaptopBattery : !SystemInfo.isDesktop'
    if laptop_property not in text:
        anchor = '    property bool lockOnSleep: idleSettings && idleSettings.lockOnSleep !== undefined ? idleSettings.lockOnSleep : true'
        if text.count(anchor) != 1: raise ValueError('Idle laptop detection anchor changed')
        text = text.replace(anchor, anchor + '\n' + laptop_property, 1)
    marker = 'settingId: "idle_manual_system_awake"'
    rectangle_anchor = '            Rectangle {\n                Layout.fillWidth: true\n                implicitHeight: actionsBoxCol.implicitHeight + rootObj.s(24)'
    if text.count(rectangle_anchor) != 1: raise ValueError('Do Not Disturb companion option anchor changed')
    if marker in text:
        option_start = text.rfind('            SettingsRow {', 0, text.index(marker))
        if option_start < 0: raise ValueError('Do Not Disturb companion option boundaries changed')
        option_start = text.rfind('\n', 0, option_start) + 1
        depth = 0
        option_end = -1
        for index in range(text.index('{', option_start), len(text)):
            if text[index] == '{': depth += 1
            elif text[index] == '}':
                depth -= 1
                if depth == 0:
                    option_end = index + 1
                    break
        if option_end < 0: raise ValueError('Do Not Disturb companion option boundaries changed')
        option = text[option_start:option_end]
        text = text[:option_start].rstrip() + '\n' + text[option_end:].lstrip('\n')
        option = option.replace('searchKeywords: "keep awake suspend lid closed download network"', 'searchKeywords: "codex mode keep awake suspend lid closed download network ai workflow"', 1)
        option = option.replace('title: "Keep system awake"', 'title: "Codex mode"', 1)
        option = option.replace('                icon: "󰒲"', '                icon: "󰖙"', 1)
        option = option.replace('radius: rootObj.s(4)', 'radius: ThemeBackend.borderRadius', 1)
    else:
        option = '''                SettingsRow {
                rootObj: idleTabRoot.rootObj
                settingId: "idle_manual_system_awake"
                searchKeywords: "codex mode keep awake suspend lid closed download network ai workflow"
                visible: idleTabRoot.idleEnabled
                enabled: idleTabRoot.codexModeAvailable
                opacity: idleTabRoot.codexModeAvailable ? 1.0 : 0.38
                icon: "󰖙"
                title: "Codex mode"
                description: "Also block system suspend and lid-triggered sleep while Do Not Disturb is enabled."
                titleBadge: Component {
                    Rectangle {
                        implicitWidth: addonBadgeText.implicitWidth + rootObj.s(12)
                        implicitHeight: rootObj.s(18)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.mauve, 0.15)
                        border.color: Qt.alpha(ThemeBackend.mauve, 0.4)
                        border.width: 1
                        clip: true

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

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    enabled: idleTabRoot.manualInhibit
                    checked: idleTabRoot.idleSettings.keepSystemAwake === true
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(c) { idleTabRoot.updateRootSetting("keepSystemAwake", c); }
                }
                }

'''
    if 'id: badgeShimmer' not in option:
        if 'id: addonBadgeText' in option:
            badge_start = option.index('                titleBadge: Component {')
            badge_end = option.index('\n\n                Toggle {', badge_start)
            badge = option[badge_start:badge_end]
            badge = badge.replace('                        border.width: 1', '''                        border.width: 1
                        clip: true

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
                        }''', 1)
            option = option[:badge_start] + badge + option[badge_end:]
        else:
            badge = """                titleBadge: Component {
                    Rectangle {
                        implicitWidth: addonBadgeText.implicitWidth + rootObj.s(12)
                        implicitHeight: rootObj.s(18)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.mauve, 0.15)
                        border.color: Qt.alpha(ThemeBackend.mauve, 0.4)
                        border.width: 1

                        Text {
                            id: addonBadgeText
                            anchors.centerIn: parent
                            text: "Addon"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(10)
                            font.bold: true
                            color: ThemeBackend.mauve
                        }
                    }
                }

"""
            toggle_anchor = '                Toggle {\n                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter'
            if option.count(toggle_anchor) != 1: raise ValueError('Do Not Disturb toggle anchor changed')
            option = option.replace(toggle_anchor, badge + toggle_anchor, 1)
    if 'enabled: idleTabRoot.codexModeAvailable' not in option:
        option = option.replace('visible: idleTabRoot.idleEnabled', 'visible: idleTabRoot.idleEnabled\n                enabled: idleTabRoot.codexModeAvailable\n                opacity: idleTabRoot.codexModeAvailable ? 1.0 : 0.38', 1)
    option = option.replace('enabled: idleTabRoot.manualInhibit && idleTabRoot.codexModeAvailable && idleTabRoot.codexModeAvailable', 'enabled: idleTabRoot.manualInhibit && idleTabRoot.codexModeAvailable', 1)
    if 'enabled: idleTabRoot.manualInhibit && idleTabRoot.codexModeAvailable' not in option:
        option = option.replace('enabled: idleTabRoot.manualInhibit', 'enabled: idleTabRoot.manualInhibit && idleTabRoot.codexModeAvailable', 1)
    rounded_mask = '''                        id: addonBadge
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: addonBadgeMask }

                        Rectangle {
                            id: addonBadgeMask
                            anchors.fill: parent
                            radius: addonBadge.radius
                            color: "black"
                            visible: false
                            layer.enabled: true
                        }'''
    if 'id: addonBadgeMask' not in option:
        option = option.replace('                        border.width: 1\n                        clip: true', '                        border.width: 1\n' + rounded_mask, 1)
    option = '                ' + option.strip()
    inhibit_position = text.index('settingId: "idle_manual_inhibit"')
    rectangle_position = text.index(rectangle_anchor, inhibit_position)
    option_anchor = text.rfind('            }', inhibit_position, rectangle_position)
    if option_anchor < 0: raise ValueError('Do Not Disturb settings group anchor changed')
    text = text[:option_anchor].rstrip() + '\n\n' + option + '\n' + text[option_anchor:]
    default_anchor = '        "manualInhibit": false,'
    if '"keepSystemAwake": false,' not in text:
        if text.count(default_anchor) != 1: raise ValueError('Idle setting defaults anchor changed')
        text = text.replace(default_anchor, default_anchor + '\n        "keepSystemAwake": false,', 1)
    return text


def patch_main(text):
    if '// BEGIN serpantinum-addons-v2 drag area' in text: return text
    start = text.index('        DragHandler {\n            id: windowDragHandler')
    depth = 0
    for stop in range(start, len(text)):
        if text[stop] == '{': depth += 1
        elif text[stop] == '}':
            depth -= 1
            if depth == 0: break
    handler = text[start:stop + 1].replace('            acceptedButtons: Qt.LeftButton', '            acceptedButtons: Qt.LeftButton\n            grabPermissions: PointerHandler.CanTakeOverFromHandlersOfSameType | PointerHandler.ApprovesTakeOverByAnything')
    wrapper = '''        // BEGIN serpantinum-addons-v2 drag area
        Item {
            width: masterWindow.currentActive === "guide" ? Scaler.s(260) : parent.width
            height: masterWindow.currentActive === "guide" ? Scaler.s(60) : parent.height
''' + handler + '\n        }\n        // END serpantinum-addons-v2 drag area'
    return text[:start] + wrapper + text[stop+1:]


def patch_network(text):
    if '// BEGIN ' + MARK + ' dns' in text: return text
    import re
    anchors = list(re.finditer(r'(?m)^    id: (window|popupWindowRoot)\n', text))
    if len(anchors) != 1: raise ValueError('Network root anchor changed')
    root_id = anchors[0].group(1)
    block = '''
    // BEGIN serpantinum-addons-v2 dns
    DnsControl {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: %s.s(18); anchors.topMargin: %s.s(16)
        width: %s.s(160); height: %s.s(32); z: 100
        visible: %s.activeMode === "wifi" || %s.activeMode === "eth"
        pollEnabled: %s.visible && visible
    }
    // END serpantinum-addons-v2 dns
''' % (root_id, root_id, root_id, root_id, root_id, root_id, root_id)
    anchor = anchors[0].group(0)
    return text.replace(anchor, anchor + block, 1)


def patch_weather_face(text):
    import re
    marker = '// BEGIN serpantinum-addons-v2 weather city obfuscation'
    anchor = '                        text: Location.city && Location.city !== "" ? Location.city : (root.weatherData && root.weatherData.city ? root.weatherData.city : "Unknown")'
    replacement = '''                        // BEGIN serpantinum-addons-v2 weather city obfuscation
                        property string cityName: Location.city && Location.city !== "" ? Location.city : (root.weatherData && root.weatherData.city ? root.weatherData.city : "Unknown")
                        property string obfuscatedCity: ""

                        function reshuffleCity() {
                            const glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&*+-=?@"
                            let scrambled = ""
                            for (let i = 0; i < cityName.length; i++) {
                                scrambled += glyphs.charAt(Math.floor(Math.random() * glyphs.length))
                            }
                            obfuscatedCity = scrambled
                        }

                        Component.onCompleted: reshuffleCity()
                        onCityNameChanged: reshuffleCity()
                        onVisibleChanged: if (visible) reshuffleCity()

                        Timer {
                            interval: 90
                            repeat: true
                            running: Config.getSetting("addonsV2ObfuscateWeatherCity", false) && root.visible
                            onTriggered: parent.reshuffleCity()
                        }

                        text: Config.getSetting("addonsV2ObfuscateWeatherCity", false) ? (obfuscatedCity || "••••••••") : cityName
                        // END serpantinum-addons-v2 weather city obfuscation'''
    pattern = re.compile(r'(?m)^[ \t]*// BEGIN serpantinum-addons-v2 weather city obfuscation\n.*?^[ \t]*// END serpantinum-addons-v2 weather city obfuscation\n?', re.S)
    matches = list(pattern.finditer(text))
    if matches:
        if len(matches) != 1: raise ValueError('Weather city patch markers are duplicated')
        return pattern.sub(lambda match: replacement + ('\n' if match.group(0).endswith('\n') else ''), text, count=1)
    if text.count(anchor) != 1: raise ValueError('Weather city label anchor changed')
    return text.replace(anchor, replacement, 1)


def patch_theme(text):
    import re
    text = re.sub(r'                        // BEGIN serpantinum-addons-v2 theme\n.*?                        // END serpantinum-addons-v2 theme\n', '', text, flags=re.S)
    text = text.replace('themeTabRoot.systemPresets = sys;', 'themeTabRoot.systemPresets = sys.slice();')
    state_video_anchor = '                    Matugen.generate(themeTabRoot.currentWallpaperPath, current.mode, current.schemeType);'
    state_video_marker = '// BEGIN serpantinum-addons-v2 Matugen video wallpaper source'
    if state_video_marker not in text:
        if text.count(state_video_anchor) == 1:
            text = text.replace(state_video_anchor, '''                    // BEGIN serpantinum-addons-v2 Matugen video wallpaper source
                    let imagePath = themeTabRoot.isWallpaperVideo
                        ? Caching.getCacheDir("wallpaper") + "/current_wallpaper.png"
                        : themeTabRoot.currentWallpaperPath;
                    Matugen.generate(imagePath, current.mode, current.schemeType);
                    // END serpantinum-addons-v2 Matugen video wallpaper source''', 1)
        elif state_video_marker not in text:
            # The former installer targeted ThemeTab.qml, where this generation
            # call used to live. The current upstream places it in ThemeTabState.qml.
            old_anchor = '                    Matugen.generate(themeTabRoot.currentWallpaperPath, current.mode, current.schemeType);'
            if text.count(old_anchor) != 1: raise ValueError('Matugen wallpaper generation anchor changed')
            text = text.replace(old_anchor, '''                    // BEGIN serpantinum-addons-v2 Matugen video wallpaper source
                    let imagePath = themeTabRoot.isWallpaperVideo
                        ? Caching.getCacheDir("wallpaper") + "/current_wallpaper.png"
                        : themeTabRoot.currentWallpaperPath;
                    Matugen.generate(imagePath, current.mode, current.schemeType);
                    // END serpantinum-addons-v2 Matugen video wallpaper source''', 1)
    if '// BEGIN serpantinum-addons-v2 theme cards' in text:
        return text.replace('themeTabRoot.systemPresets = sys;', 'themeTabRoot.systemPresets = sys.slice();')
    anchor = '                        themeTabRoot.userPresets = usr;'
    if text.count(anchor) != 1: raise ValueError('Theme preset list anchor changed')
    text = text.replace(anchor, '''                        // BEGIN serpantinum-addons-v2 theme cards
                        let matugenIndex = sys.findIndex(p => p.isMatugen === true);
                        if (matugenIndex !== -1) {
                            sys.splice(matugenIndex + 1, 0,
                                {name: "Vibrant", isMatugen: true, addonColorMode: "vibrant"},
                                {name: "Vivid", isMatugen: true, addonColorMode: "vivid"});
                            themeTabRoot.systemPresets = sys.slice();
                        }
                        // END serpantinum-addons-v2 theme cards
''' + anchor, 1)
    anchor = '        let isMatugen = modelData.isMatugen === true;'
    block = '''        if (modelData.isMatugen === true) {
            Config.setSetting("addonsV2ColorMode", modelData.addonColorMode || "matugen");
            Matugen._hasGeneratedSuccessfully = false;
        }
'''
    text = text.replace(anchor, block + anchor, 1)
    # Give the addon cards the exact existing wallpaper tile, selection, dots and motion.
    return text


def patch_theme_view(text):
    if '// BEGIN ' + MARK + ' palette editor' in text: return text
    anchor = '            ThemeWallpaperPreview { tab: themeTabRoot }\n'
    if text.count(anchor) != 1: raise ValueError('Theme wallpaper preview anchor changed')
    return text.replace(anchor, anchor + '''
            // BEGIN serpantinum-addons-v2 palette editor
            AddonPaletteEditor { tab: themeTabRoot }
            // END serpantinum-addons-v2 palette editor
''', 1)


def patch_matugen(text):
    if '// BEGIN ' + MARK + ' generation' not in text:
        text = patch_matugen_generation(text)
    return patch_matugen_color_mode(text)


def patch_matugen_color_mode(text):
    # Startup generations can run before settings load, with the default color mode.
    # Without the mode in the dedupe key, the later Vibrant/Vivid request is skipped.
    if '// ' + MARK + ' color mode' in text: return text
    replacements = [
        ('    property string _lastGeneratedSchemeType: ""\n',
         '    property string _lastGeneratedSchemeType: ""\n'
         '    property string _lastGeneratedColorMode: "" // serpantinum-addons-v2 color mode\n'
         '    property string _currentColorMode: ""\n'),
        ('            && root._lastGeneratedSchemeType === selectedType\n',
         '            && root._lastGeneratedSchemeType === selectedType\n'
         '            && root._lastGeneratedColorMode === Config.getSetting("addonsV2ColorMode", "matugen")\n'),
        ('                && root._currentSchemeType === selectedType) {',
         '                && root._currentSchemeType === selectedType\n'
         '                && root._currentColorMode === Config.getSetting("addonsV2ColorMode", "matugen")) {'),
        ('        root._currentSchemeType = selectedType;\n        root._currentStaticJson = "";\n',
         '        root._currentSchemeType = selectedType;\n        root._currentStaticJson = "";\n'
         '        root._currentColorMode = Config.getSetting("addonsV2ColorMode", "matugen");\n'),
        ('                root._lastGeneratedSchemeType = root._currentSchemeType;\n',
         '                root._lastGeneratedSchemeType = root._currentSchemeType;\n'
         '                root._lastGeneratedColorMode = root._currentColorMode;\n'),
    ]
    for anchor, replacement in replacements:
        if text.count(anchor) != 1: raise ValueError('Matugen color mode anchor changed')
        text = text.replace(anchor, replacement, 1)
    return text


def patch_matugen_generation(text):
    anchor = '''        matugenProcess.command = [
            "nice", "-n", "15",
            "matugen", "image", cleanPath,
            "-c", root.configPath,
            "-m", selectedMode,
            "-t", selectedType,
            "--source-color-index", "0"
        ];'''
    if text.count(anchor) != 1: raise ValueError('Matugen command anchor changed')
    replacement = '''        // BEGIN serpantinum-addons-v2 generation
        matugenProcess.command = [
            "nice", "-n", "15",
            "python3", Quickshell.env("HOME") + "/.local/share/serpantinum-addons-v2/scripts/colors.py",
            cleanPath, root.configPath, root.configPathStatic, selectedMode, selectedType,
            Config.getSetting("addonsV2ColorMode", "matugen"), Caching.stateDir
        ];
        // END serpantinum-addons-v2 generation'''
    return text.replace(anchor, replacement, 1)


def patch_shell(text):
    blocks = [
        '    // BEGIN serpantinum-addons-v2 window outline\n    AddonWindowOutline {}\n    // END serpantinum-addons-v2 window outline\n',
        '    // BEGIN serpantinum-addons-v2 color picker\n    AddonColorPicker {}\n    // END serpantinum-addons-v2 color picker\n',
        '    // BEGIN serpantinum-addons-v2 awake\n    AddonAwake {}\n    // END serpantinum-addons-v2 awake\n',
        '    // BEGIN serpantinum-addons-v2 desktop draw\n    AddonDesktopDraw {}\n    // END serpantinum-addons-v2 desktop draw\n',
        '    // BEGIN serpantinum-addons-v2 desktop zoom\n    AddonDesktopZoom {}\n    // END serpantinum-addons-v2 desktop zoom\n',
        '    // BEGIN serpantinum-addons-v2 mouse spotlight\n    AddonMouseSpotlight {}\n    // END serpantinum-addons-v2 mouse spotlight\n',
    ]
    # These IPC handlers must be direct ShellRoot children. Keeping them in
    # screenshotLoader makes every shortcut fail until a screenshot activates it.
    for block in blocks:
        text = text.replace(block, '')
    anchor = '    Main {}\n'
    if text.count(anchor) != 1: raise ValueError('Shell root component anchor changed')
    prefix, suffix = text.split(anchor, 1)
    return prefix.rstrip() + '\n\n' + '\n'.join(blocks) + '\n' + anchor + suffix


def patch_screenshot_overlay(text):
    # Newer upstream capture flow already crops the frozen image through
    # screenshot.sh --source/--crop/--logical-size, so the legacy arguments
    # below must not be layered on top of it.
    if 'function frozenSourceArgs()' in text and '--source "${root.freezeImg}" --crop' in text:
        return text
    marker = '// BEGIN serpantinum-addons-v2 frozen screenshot source'
    if marker not in text:
        anchor = '        let cmd = `bash ${Caching.serpantinumDir}/scripts/screenshot.sh --geometry "${root.geometryString}"`;'
        if text.count(anchor) != 1: raise ValueError('Screenshot capture command anchor changed')
        block = '''        // BEGIN serpantinum-addons-v2 frozen screenshot source
        if (!isRecord && root.freezeImg !== "" && root.screen) {
            const frozenGeometry = `${Math.round(root.selX)},${Math.round(root.selY)} ${Math.round(root.selW)}x${Math.round(root.selH)}`;
            const frozenSize = `${Math.round(root.screen.width)}x${Math.round(root.screen.height)}`;
            cmd += ` --frozen-image "${root.freezeImg}" --frozen-geometry "${frozenGeometry}" --frozen-size "${frozenSize}"`;
        }
        // END serpantinum-addons-v2 frozen screenshot source
'''
        text = text.replace(anchor, anchor + '\n' + block.rstrip(), 1)

    anchor = '    property string freezeImg: ""\n'
    if '    property string pendingCaptureFreezeImg: ""\n' not in text:
        if text.count(anchor) != 1: raise ValueError('Screenshot freeze lifecycle anchor changed')
        text = text.replace(anchor, anchor + '    property string pendingCaptureFreezeImg: ""\n', 1)

    anchor = '            Quickshell.execDetached(["bash", "-c", pendingCmd]);\n'
    if 'root.pendingCaptureFreezeImg = "";' not in text:
        if text.count(anchor) != 1: raise ValueError('Screenshot timer anchor changed')
        text = text.replace(anchor, anchor + '            root.pendingCaptureFreezeImg = "";\n', 1)

    anchor = '        if (root.freezeImg !== "") Quickshell.execDetached(["bash", "-c", "rm -f " + root.freezeImg]);'
    replacement = '        if (root.freezeImg !== "" && root.freezeImg !== root.pendingCaptureFreezeImg) Quickshell.execDetached(["bash", "-c", "rm -f " + root.freezeImg]);'
    if anchor in text:
        text = text.replace(anchor, replacement)
    elif text.count(replacement) != 2: raise ValueError('Screenshot freeze cleanup anchor changed')

    anchor = '        captureTimer.pendingCmd = cmd;\n'
    assignment = '        root.pendingCaptureFreezeImg = (!isRecord && root.freezeImg !== "" && root.screen) ? root.freezeImg : "";\n'
    if assignment not in text:
        if text.count(anchor) != 1: raise ValueError('Screenshot capture lifecycle anchor changed')
        text = text.replace(anchor, assignment + anchor, 1)
    return text


def patch_screenshot_script(text):
    if '        --source) SOURCE_IMG="$2"; shift 2 ;;' in text and 'crop_source() {' in text:
        return text
    marker = '# BEGIN serpantinum-addons-v2 frozen screenshot source'
    if marker in text: return text
    anchor = 'GEOMETRY=""\n'
    if text.count(anchor) != 1: raise ValueError('Screenshot geometry argument anchor changed')
    text = text.replace(anchor, anchor + 'FROZEN_IMG=""\nFROZEN_GEOMETRY=""\nFROZEN_SIZE=""\n', 1)
    anchor = '        --geometry) GEOMETRY="$2"; shift 2 ;;\n'
    if text.count(anchor) != 1: raise ValueError('Screenshot argument parser anchor changed')
    text = text.replace(anchor, anchor + '''        --frozen-image) FROZEN_IMG="$2"; shift 2 ;;
        --frozen-geometry) FROZEN_GEOMETRY="$2"; shift 2 ;;
        --frozen-size) FROZEN_SIZE="$2"; shift 2 ;;
''', 1)
    anchor = '''    if [ -n "$GEOMETRY" ]; then
        grim -l 0 -g "$GEOMETRY" "$TMP_SCREENSHOT"
    elif [ -n "$TARGET_MON" ]; then
'''
    if text.count(anchor) != 1: raise ValueError('Screenshot region capture anchor changed')
    replacement = '''    if [ -n "$FROZEN_IMG" ] && [ -f "$FROZEN_IMG" ] && [ -n "$FROZEN_GEOMETRY" ] && [ -n "$FROZEN_SIZE" ]; then
        ADDON_SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum-addons-v2/scripts"
        python3 "$ADDON_SCRIPT_DIR/crop_frozen_screenshot.py" "$FROZEN_IMG" "$FROZEN_GEOMETRY" "$FROZEN_SIZE" "$TMP_SCREENSHOT"
    elif [ -n "$GEOMETRY" ]; then
        grim -l 0 -g "$GEOMETRY" "$TMP_SCREENSHOT"
    elif [ -n "$TARGET_MON" ]; then
'''
    text = text.replace(anchor, replacement, 1)
    return text.replace('    if [ -n "$FROZEN_IMG" ]', marker + '\n    if [ -n "$FROZEN_IMG" ]', 1).replace('        rm -f "$TMP_SCREENSHOT"\n', '        rm -f "$TMP_SCREENSHOT"\n    # END serpantinum-addons-v2 frozen screenshot source\n', 1)


def patch_screenshot_cleanup(text):
    if 'SOURCE_IMG=""' in text and '[ -n "$SOURCE_IMG" ] && rm -f "$SOURCE_IMG"' in text:
        return text
    marker = '# BEGIN serpantinum-addons-v2 frozen screenshot cleanup'
    if marker in text: return text
    anchor = 'done\n\nexport XDG_RUNTIME_DIR='
    if text.count(anchor) != 1: raise ValueError('Screenshot cleanup trap anchor changed')
    cleanup = '''done

# BEGIN serpantinum-addons-v2 frozen screenshot cleanup
if [ -n "$FROZEN_IMG" ]; then
    trap 'rm -f -- "$FROZEN_IMG"' EXIT
fi
# END serpantinum-addons-v2 frozen screenshot cleanup

export XDG_RUNTIME_DIR='''
    return text.replace(anchor, cleanup, 1)


def patch_screenshot_frozen_validation(text):
    if '        --source) SOURCE_IMG="$2"; shift 2 ;;' in text:
        return text
    old = '''# BEGIN serpantinum-addons-v2 frozen screenshot source
    if [ -n "$FROZEN_IMG" ] && [ -f "$FROZEN_IMG" ] && [ -n "$FROZEN_GEOMETRY" ] && [ -n "$FROZEN_SIZE" ]; then
        ADDON_SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum-addons-v2/scripts"
        python3 "$ADDON_SCRIPT_DIR/crop_frozen_screenshot.py" "$FROZEN_IMG" "$FROZEN_GEOMETRY" "$FROZEN_SIZE" "$TMP_SCREENSHOT"
    elif [ -n "$GEOMETRY" ]; then
'''
    new = '''# BEGIN serpantinum-addons-v2 frozen screenshot source
    if [ -n "$FROZEN_IMG" ]; then
        if [ -f "$FROZEN_IMG" ] && [ -n "$FROZEN_GEOMETRY" ] && [ -n "$FROZEN_SIZE" ]; then
            ADDON_SCRIPT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum-addons-v2/scripts"
            python3 "$ADDON_SCRIPT_DIR/crop_frozen_screenshot.py" "$FROZEN_IMG" "$FROZEN_GEOMETRY" "$FROZEN_SIZE" "$TMP_SCREENSHOT" || exit 1
        else
            echo "Frozen screenshot source or selection geometry is missing" >&2
            exit 1
        fi
    elif [ -n "$GEOMETRY" ]; then
'''
    if new in text: return text
    if text.count(old) != 1: raise ValueError('Frozen screenshot validation anchor changed')
    return text.replace(old, new, 1)


def patch_floating(text):
    marker = '                                // BEGIN serpantinum-addons-v2 picker action\n'
    if marker in text:
        return text.replace('Quickshell.execDetached(["quickshell", "ipc", "call", "addonColorPicker", "toggle"]);', 'Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonColorPicker", "toggle"]);')
    anchor = '                                Rectangle {\n                                    id: pinButton'
    if text.count(anchor) != 1: raise ValueError('Quickactions pin anchor changed')
    action = '''                                // BEGIN serpantinum-addons-v2 picker action
                                Rectangle {
                                    id: pickerButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    radius: width / 2
                                    x: (parent.width - width) / 2
                                    y: floatingWidget.activeEdge === "left"
                                        ? pinButton.y + pinButton.height + floatingWidget.s(6)
                                        : pinButton.y - height - floatingWidget.s(6)
                                    color: pickerMouse.containsMouse ? Qt.alpha(ThemeBackend.mauve, 0.25) : "transparent"
                                    border.width: floatingWidget.s(1)
                                    border.color: pickerMouse.containsMouse ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.text, 0.22)
                                    scale: pickerMouse.pressed ? 0.88 : (pickerMouse.containsMouse ? 1.12 : 1)
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰈊"
                                        color: pickerMouse.containsMouse ? ThemeBackend.mauve : ThemeBackend.text
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: floatingWidget.s(12)
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    MouseArea {
                                        id: pickerMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()
                                        onClicked: {
                                            floatingWidget.isExpanded = false;
                                            floatingWidget.isSidebarVisible = false;
                                            Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonColorPicker", "toggle"]);
                                        }
                                    }
                                }
                                // END serpantinum-addons-v2 picker action

'''
    text = text.replace(anchor, action + anchor, 1)
    return text.replace('property real controlAreaHeight: buttonSize * 2 + s(10)', 'property real controlAreaHeight: buttonSize * 3 + s(16)', 1)


def patch_keybinds(text):
    marker = '-- BEGIN serpantinum-addons-v2 color picker'
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonColorPicker toggle'
    if marker in text:
        return text.replace('quickshell ipc call addonColorPicker toggle', command)
    if '"SUPER + SHIFT + C"' in text: raise ValueError('Color picker shortcut already in use')
    anchor = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })'
    if text.count(anchor) != 1: raise ValueError('Screenshot shortcut anchor changed')
    addition = '''\n-- BEGIN serpantinum-addons-v2 color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("''' + command + '''"), { locked = true })
-- END serpantinum-addons-v2 color picker'''
    return text.replace(anchor, anchor + addition, 1)


def patch_window_keybinds(text):
    marker = '-- BEGIN serpantinum-addons-v2 window switching'
    if marker in text: return text
    if '"SUPER + Tab"' in text or '"ALT + Tab"' in text: raise ValueError('Window switching shortcuts already in use')
    anchor = '-- END serpantinum-addons-v2 color picker'
    if text.count(anchor) != 1: raise ValueError('Color picker shortcut anchor changed')
    mouse_script = str(HOME/'.config/hypr/scripts/mouse-next-monitor-center.sh')
    addition = '''\n-- BEGIN serpantinum-addons-v2 window switching
-- Super+Tab : écran suivant + souris au centre de cet écran
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("''' + mouse_script + '''"))
-- Alt+Tab : fenêtre suivante dans l'écran et le workspace courants, mise au premier plan
hl.bind("ALT + Tab", hl.dsp.exec_cmd("hyprctl eval 'hl.dispatch(hl.dsp.window.cycle_next()); hl.dispatch(hl.dsp.window.bring_to_top())'"))
-- END serpantinum-addons-v2 window switching'''
    return text.replace(anchor, anchor + addition, 1)


def patch_spotlight_keybind(text):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = '-- BEGIN serpantinum-addons-v2 mouse spotlight'
    if marker in text: return text
    if '"SUPER + SHIFT + M"' in text: raise ValueError('Mouse spotlight shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonMouseSpotlight toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 mouse spotlight\n'


def patch_zoom_keybind(text):
    marker = '-- BEGIN serpantinum-addons-v2 desktop zoom'
    end_marker = '-- END serpantinum-addons-v2 desktop zoom'
    scroll_marker = '-- BEGIN serpantinum-addons-v2 desktop zoom scroll'
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopZoom toggle'
    scroll_up = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopZoom zoomIn'
    scroll_down = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopZoom zoomOut'
    # Consuming binds stay disabled; desktop_zoom.py enables them only while zoom is open.
    scroll_block = (
        scroll_marker + '\n'
        + 'serpantinumDesktopZoomScroll = {\n'
        + '    hl.bind("mouse_up", hl.dsp.exec_cmd(' + json.dumps(scroll_up) + ')),\n'
        + '    hl.bind("mouse_down", hl.dsp.exec_cmd(' + json.dumps(scroll_down) + ')),\n'
        + '}\n'
        + 'for _, bind in ipairs(serpantinumDesktopZoomScroll) do bind:set_enabled(false) end\n'
        + '-- END serpantinum-addons-v2 desktop zoom scroll'
    )
    previous_scroll_blocks = (
        scroll_marker + '\n'
        + 'hl.bind("mouse_up", hl.dsp.exec_cmd(' + json.dumps(scroll_up) + '), { non_consuming = true })\n'
        + 'hl.bind("mouse_down", hl.dsp.exec_cmd(' + json.dumps(scroll_down) + '), { non_consuming = true })\n'
        + '-- END serpantinum-addons-v2 desktop zoom scroll',
        scroll_marker + '\n'
        + 'local function desktopZoomIsActive()\n'
        + '    return hl.get_config("cursor.zoom_rigid") == true and hl.get_config("cursor.zoom_detached_camera") == false\n'
        + 'end\n'
        + 'hl.bind("mouse_up", function()\n'
        + '    if desktopZoomIsActive() then hl.exec_cmd(' + json.dumps(scroll_up) + ') end\n'
        + 'end, { non_consuming = true })\n'
        + 'hl.bind("mouse_down", function()\n'
        + '    if desktopZoomIsActive() then hl.exec_cmd(' + json.dumps(scroll_down) + ') end\n'
        + 'end, { non_consuming = true })\n'
        + '-- END serpantinum-addons-v2 desktop zoom scroll',
    )
    if marker in text:
        if scroll_marker in text:
            # Upgrade the earlier generated binds without overwriting user edits.
            for previous in previous_scroll_blocks:
                if previous in text:
                    return text.replace(previous, scroll_block, 1)
            return text
        if text.count(end_marker) != 1:
            raise ValueError('Desktop zoom keybind block changed')
        return text.replace(end_marker, end_marker + '\n\n' + scroll_block, 1)
    if '"SUPER + SHIFT + Z"' in text: raise ValueError('Desktop zoom shortcut already in use')
    return (text.rstrip() + '\n\n' + marker + '\n'
            + 'hl.bind("SUPER + SHIFT + Z", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n'
            + end_marker + '\n\n' + scroll_block + '\n')


def patch_draw_keybind(text):
    marker = '-- BEGIN serpantinum-addons-v2 desktop draw'
    if marker in text: return text
    if '"SUPER + SHIFT + D"' in text: raise ValueError('Desktop drawing shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopDraw toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 desktop draw\n'


def remove_inline_settings(text, prefix):
    pattern = rf"(?m)^[ \t]*{re.escape(prefix)} BEGIN serpantinum-addons-v2 inline settings\n.*?^[ \t]*{re.escape(prefix)} END serpantinum-addons-v2 inline settings\n?"
    return re.sub(pattern, "", text, flags=re.S)


def install(without_halloween=False, without_capri=False, without_clawd=False):
    # Calculate all transformations first. Never partly apply an unknown upstream revision.
    if without_clawd:
        clawd.uninstall_hooks()
    theme_state = QS/'guide/theme/ThemeTabState.qml'
    theme_view = QS/'guide/theme/ThemeTab.qml'
    patches = {QS/'Main.qml': lambda text: remove_inline_settings(patch_main(text), '//'), QS/'WindowRegistry.js': lambda text: remove_inline_settings(text, '//'),QS/'Shell.qml': patch_shell, QS/'screenshot/ScreenshotOverlay.qml': patch_screenshot_overlay, QS/'quickactions/Floating.qml': patch_floating, QS/'guide/GuidePopup.qml': patch_guide, QS/'guide/GuideSidebar.qml': patch_guide_sidebar, QS/'guide/IdleTab.qml': patch_idle_tab, (theme_state if theme_state.exists() else theme_view): patch_theme, QS/'network/NetworkPopup.qml': patch_network, QS/'singletons/theme/Matugen.qml': patch_matugen, QS/'widgets/faces/weather/WeatherFaceFull.qml': patch_weather_face}
    pending = {path: transform(path.read_text()) for path, transform in patches.items()}
    pending[theme_view] = patch_theme_view(pending.get(theme_view, theme_view.read_text()))
    pending[QS/'guide/theme/AddonPaletteEditor.qml'] = (SOURCE/'payload/AddonPaletteEditor.qml').read_text()
    theme_qmldir = QS/'guide/theme/qmldir'
    theme_types = theme_qmldir.read_text()
    if 'AddonPaletteEditor 1.0 AddonPaletteEditor.qml' not in theme_types:
        theme_types = theme_types.rstrip() + '\nAddonPaletteEditor 1.0 AddonPaletteEditor.qml\n'
    pending[theme_qmldir] = theme_types
    screenshot_script = QS.parent/'scripts/screenshot.sh'
    pending[screenshot_script] = patch_screenshot_frozen_validation(patch_screenshot_cleanup(patch_screenshot_script(screenshot_script.read_text())))
    keybind_path = HOME/'.config/hypr/config/keybinds.lua'
    pending[keybind_path] = remove_inline_settings(patch_draw_keybind(patch_zoom_keybind(patch_spotlight_keybind(patch_window_keybinds(patch_keybinds(keybind_path.read_text()))))), '--')
    for path, transform in seasonal.transformations(QS).items():
        text = pending[path] if path in pending else path.read_text()
        pending[path] = seasonal.remove(text) if without_halloween else transform(text)
    for name, transform in [('equalizer.sh', seasonal_surfaces.remove_audio_boost_backend),
                            ('MusicEqualizerState.qml', seasonal_surfaces.remove_audio_boost_qml),
                            ('MusicAudioView.qml', seasonal_surfaces.remove_audio_boost_qml)]:
        path = QS/'media'/name
        pending[path] = transform(path.read_text())
    for path, transform in capri.transformations(QS).items():
        text = pending[path] if path in pending else path.read_text()
        pending[path] = capri.remove(text) if without_capri else transform(text)
    pending[keybind_path] = capri.remove(pending[keybind_path]) if without_capri else capri.patch_keybind(pending[keybind_path], QS/'Shell.qml')
    for path, transform in clawd.transformations(QS).items():
        text = pending[path] if path in pending else path.read_text()
        pending[path] = clawd.remove(text) if without_clawd else transform(text)
    pending[keybind_path] = clawd.remove(pending[keybind_path]) if without_clawd else clawd.patch_keybind(pending[keybind_path], QS/'Shell.qml')
    payloads = {'AddonWindowOutline.qml': 'AddonWindowOutline.qml', 'AddonAwake.qml': 'AddonAwake.qml', 'AddonDesktopDraw.qml': 'AddonDesktopDraw.qml', 'AddonDesktopZoom.qml': 'AddonDesktopZoom.qml', 'AddonMouseSpotlight.qml': 'AddonMouseSpotlight.qml', 'AddonColorPicker.qml': 'AddonColorPicker.qml', 'AddonsTab.qml': 'guide/AddonsTab.qml', 'AddonsMouseTab.qml': 'guide/AddonsMouseTab.qml', 'AddonsBannersTab.qml': 'guide/AddonsBannersTab.qml', 'AddonMonitorsTab.qml': 'guide/AddonMonitorsTab.qml', 'AddonKeybindsTab.qml': 'guide/AddonKeybindsTab.qml', 'AddonStartupTab.qml': 'guide/AddonStartupTab.qml', 'DnsControl.qml': 'network/DnsControl.qml', 'LegacyCalendar.qml': 'calendar/LegacyCalendar.qml', 'CalendarPopup.qml': 'calendar/CalendarPopup.qml'}
    for component in ('AddonCursorSettings', 'AddonCursorPreview', 'AddonCursorRole', 'AddonCursorTestArea'):
        payloads[component + '.qml'] = 'guide/' + component + '.qml'
    for source, target in payloads.items(): pending[QS/target] = (SOURCE/'payload'/source).read_text()
    pending[QS/'reusables/AddonGlassSurface.qml'] = (SOURCE/'payload/AddonGlassSurface.qml').read_text()
    reusable_qmldir = QS/'reusables/qmldir'
    reusable_types = pending.get(reusable_qmldir, reusable_qmldir.read_text())
    declaration = 'AddonGlassSurface 1.0 AddonGlassSurface.qml'
    if declaration not in reusable_types:
        reusable_types = reusable_types.rstrip() + '\n' + declaration + '\n'
    pending[reusable_qmldir] = reusable_types
    guide_qmldir = QS/'guide/qmldir'
    guide_types = pending.get(guide_qmldir, guide_qmldir.read_text())
    for component in ('AddonCursorSettings', 'AddonCursorPreview', 'AddonCursorRole', 'AddonCursorTestArea'):
        declaration = component + ' 1.0 ' + component + '.qml'
        if declaration not in guide_types:
            guide_types = guide_types.rstrip() + '\n' + declaration + '\n'
    pending[guide_qmldir] = guide_types
    # NativeCalendar is captured before installing the wrapper, then patched in
    # memory. The native UI remains the source of truth for both seasonal states.
    native_calendar = QS/'calendar/NativeCalendar.qml'
    calendar_text = (QS/'calendar/CalendarPopup.qml').read_text()
    wrapped = '// BEGIN serpantinum-addons-v2 calendar wrapper' in calendar_text
    if wrapped and not native_calendar.is_file():
        raise ValueError('Native calendar backup is missing')
    native_text = native_calendar.read_text() if wrapped else calendar_text
    clock_transform = seasonal.remove if without_halloween else lambda text: seasonal_surfaces.calendar(seasonal.patch_calendar(text))
    pending[native_calendar] = clock_transform(native_text)
    pending[QS/'calendar/LegacyCalendar.qml'] = clock_transform(pending[QS/'calendar/LegacyCalendar.qml'])
    if without_halloween:
        pending[QS/'guide/AddonsTab.qml'] = seasonal.remove(pending[QS/'guide/AddonsTab.qml'])
    if without_capri:
        pending[QS/'guide/AddonsTab.qml'] = capri.remove(pending[QS/'guide/AddonsTab.qml'])
    if without_clawd:
        pending[QS/'guide/AddonsTab.qml'] = clawd.remove(pending[QS/'guide/AddonsTab.qml'])
    # Both tabs use the same DNS component; identical payload with appropriate relative imports.
    pending[QS/'guide/DnsControl.qml'] = (SOURCE/'payload/DnsControl.qml').read_text()
    qmldir = QS/'qmldir'
    # Seasonal transformation registers its QML types in the root qmldir above.
    # Extend that pending result instead of replacing it with the addon's entry.
    qmldir_text = pending.get(qmldir, qmldir.read_text())
    pending[qmldir] = qmldir_text if 'AddonColorPicker 1.0 AddonColorPicker.qml' in qmldir_text else qmldir_text + '\nAddonColorPicker 1.0 AddonColorPicker.qml\n'
    if 'AddonMouseSpotlight 1.0 AddonMouseSpotlight.qml' not in pending[qmldir]:
        pending[qmldir] += '\nAddonMouseSpotlight 1.0 AddonMouseSpotlight.qml\n'
    if 'AddonDesktopZoom 1.0 AddonDesktopZoom.qml' not in pending[qmldir]:
        pending[qmldir] += '\nAddonDesktopZoom 1.0 AddonDesktopZoom.qml\n'
    if 'AddonDesktopDraw 1.0 AddonDesktopDraw.qml' not in pending[qmldir]:
        pending[qmldir] += '\nAddonDesktopDraw 1.0 AddonDesktopDraw.qml\n'
    if 'AddonAwake 1.0 AddonAwake.qml' not in pending[qmldir]:
        pending[qmldir] += '\nAddonAwake 1.0 AddonAwake.qml\n'
    if 'AddonWindowOutline 1.0 AddonWindowOutline.qml' not in pending[qmldir]:
        pending[qmldir] += '\nAddonWindowOutline 1.0 AddonWindowOutline.qml\n'
    for folder in ('guide', 'network'):
        directory = QS/folder/'qmldir'
        original = pending.get(directory, directory.read_text() if directory.exists() else '')
        pending[directory] = original if 'DnsControl 1.0 DnsControl.qml' in original else original + '\nDnsControl 1.0 DnsControl.qml\n'
    # Read and verify all payloads before touching the installation. A forgotten
    # shader rebuild or missing resource must never leave partly applied hooks.
    shader = SOURCE/'payload/seasonal/shaders/atmosphere.frag.qsb'
    shader_name = None if without_halloween else shader_package_name(shader.parent)
    resources = sorted((SOURCE/'payload/seasonal').rglob('*'), key=lambda path: path.suffix != '.qsb')
    resource_payloads = []
    for source in resources:
        if not source.is_file(): continue
        path = QS/'seasonal'/source.relative_to(SOURCE/'payload/seasonal')
        blob = source.read_bytes()
        if not without_halloween:
            if source == shader: path = path.with_name(shader_name)
            elif source.name == 'FogLayer.qml':
                blob = blob.replace(b'shaders/atmosphere.frag.qsb', ('shaders/' + shader_name).encode())
        resource_payloads.append((path, blob))
    sprite = SOURCE/'payload/capri/shaders/sprite.frag.qsb'
    sprite_name = None if without_capri else shader_package_name(sprite.parent, 'sprite')
    capri_resources = []
    for source in sorted((SOURCE/'payload/capri').rglob('*')):
        if not source.is_file(): continue
        path, blob = QS/'capri'/source.relative_to(SOURCE/'payload/capri'), source.read_bytes()
        if sprite_name:
            if source == sprite: path = path.with_name(sprite_name)
            elif source.name == 'CapriPet.qml': blob = blob.replace(b'shaders/sprite.frag.qsb', ('shaders/' + sprite_name).encode())
        capri_resources.append((path, blob))
    clawd_resources = clawd.resources(SOURCE/'payload/clawd', QS)
    bridge = HOME/'.local/lib/qt6/qml/Serpantinum/Wallpaper/libSerpantinumWallpaperplugin.so'
    if bridge.is_file():
        wallpaper_engine.prepare(pending, QS, DEPLOY, HOME/'.local')
    backup = DEPLOY/'backups'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    changed = 0
    for path, text in pending.items():
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
        if path == screenshot_script: mode |= 0o755
        if path.is_file() and path.read_text() == text and stat.S_IMODE(path.stat().st_mode) == mode: continue
        backup.mkdir(parents=True, exist_ok=True)
        if path.exists():
            if path == keybind_path: relative = Path('hypr/keybinds.lua')
            else:
                try: relative = path.relative_to(QS)
                except ValueError: relative = path.relative_to(QS.parent)
            saved = backup/relative; saved.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, saved)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(dir=path.parent, prefix='.'+path.name)
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w') as f: f.write(text)
        os.replace(name, path); changed += 1
    # Binary shader packages are versioned beside readable GLSL sources.
    for path, blob, remove in [(p, b, without_halloween) for p, b in resource_payloads] + [(p, b, without_capri) for p, b in capri_resources] + [(p, b, without_clawd) for p, b in clawd_resources]:
        if remove:
            if path.exists():
                saved = backup/path.relative_to(QS); saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved); path.unlink(); changed += 1
            continue
        if path.exists() and path.read_bytes() == blob: continue
        backup.mkdir(parents=True, exist_ok=True)
        if path.exists():
            saved = backup/path.relative_to(QS); saved.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, saved)
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(dir=path.parent, prefix='.'+path.name)
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream: stream.write(blob)
        os.replace(name, path); changed += 1
    # Qt caches GPU programs by URL across hot reloads. Keep only the package
    # matching this source, retaining dated backups of superseded packages.
    import re
    for shader_dir, stem, keep in ((QS/'seasonal/shaders', 'atmosphere', shader_name), (QS/'capri/shaders', 'sprite', sprite_name)):
        if not shader_dir.exists(): continue
        for path in shader_dir.iterdir():
            owned = path.name == stem + '.frag.qsb' or re.fullmatch(stem + r'\.[a-f0-9]{12}\.frag\.qsb', path.name)
            if owned and path.name != keep:
                saved = backup/path.relative_to(QS); saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved); path.unlink(); changed += 1
    for path in clawd.stale_shaders(QS, everything=without_clawd):
        saved = backup/path.relative_to(QS); saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, saved); path.unlink(); changed += 1
    shutil.copytree(SOURCE/'scripts', DEPLOY/'scripts', dirs_exist_ok=True)
    print(f'v2 installed: {changed} shell files changed; backups: {backup}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--without-halloween', action='store_true', help='Remove the seasonal layer while retaining other v2 addons')
    parser.add_argument('--without-capri', action='store_true', help='Remove the Capri desktop pet while retaining other v2 addons')
    parser.add_argument('--without-clawd', action='store_true', help='Remove the Clawd desktop pet while retaining other v2 addons')
    args = parser.parse_args()
    install(without_halloween=args.without_halloween, without_capri=args.without_capri, without_clawd=args.without_clawd)
