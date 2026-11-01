#!/usr/bin/env python3
"""Install only v2 addons, preserving upstream files and unrelated v1 work.

Usage: install.py [--without-halloween|--without-capri|--without-clawd|--without-tokens]
                  [--check] [--json] [--force] | --uninstall [--purge]
Exit codes: 0 ok, 2 incompatible Serpantinum version or patch/anchor error, 3 another install is running.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import capri
import clawd
import release_ui
import seasonal
import tokens
import seasonal_surfaces
import wallpaper_engine
from datetime import datetime, timezone
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
MARK = 'serpantinum-addons-v2'
ISSUES = 'https://github.com/Suiveurtag/serpantinum-addons-v2/issues'
UPSTREAM_RAW = 'https://raw.githubusercontent.com/ilyamiro/serpantinum'
NO_SERVICES = 'SERPANTINUM_ADDONS_NO_SERVICES'   # set to skip systemctl / agent-hook side effects (tests)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = _load('addons_release', SOURCE/'scripts/addons_release.py')


def configure_paths():
    """Resolve every side-effecting location from the environment (HOME, XDG_*, SERPANTINUM_HOME) at call time."""
    global HOME, DATA, CONFIG, QS, DEPLOY
    HOME = Path.home()
    DATA = Path(os.environ.get('XDG_DATA_HOME') or HOME/'.local/share')
    CONFIG = Path(os.environ.get('XDG_CONFIG_HOME') or HOME/'.config')
    QS = Path(os.environ.get('SERPANTINUM_HOME') or DATA/'serpantinum')/'src/quickshell'
    DEPLOY = DATA/'serpantinum-addons-v2'


configure_paths()


def services_enabled():
    return not os.environ.get(NO_SERVICES)


class InstallError(ValueError):
    """An expected failure (unsupported upstream, busy lock, ...). Never shown as a traceback."""
    code = 2

    def __init__(self, message, file=None, patch=None, hint=None, code=None):
        super().__init__(message)
        self.message, self.file, self.patch, self.hint = message, file, patch, hint
        if code is not None:
            self.code = code

    def as_dict(self):
        return {'file': self.file, 'patch': self.patch, 'message': self.message, 'hint': self.hint}


class InstallBusy(InstallError):
    code = 3


def default_hint(message, file):
    if 'already in use' in message:
        return 'Free or rebind that shortcut in your Hyprland keybinds.lua, then run the installer again. Nothing was modified.'
    if 'mismatch' in message:
        return 'Rebuild the shader packages as the message says, then run the installer again. Nothing was modified.'
    version = release.serpantinum_state()['version'] or 'this version'
    tested = ((release.load_compat(SOURCE/'compat.json').get('serpantinum') or {}).get('tested')) or 'an older release'
    return (f'Serpantinum {version} changed {file or "a patched file"}; these addons are tested with {tested}. Nothing was modified. '
            f'Check for an addons update or run `addons.py doctor --report` and open an issue at {ISSUES}')


def show_path(path):
    """Short, stable name of a path for messages and the manifest: relative to the shell folder when inside src/."""
    path = Path(path)
    if path == keybinds_path():
        return 'hypr/config/keybinds.lua'
    try:
        return os.path.normpath(os.path.relpath(path, QS))
    except ValueError:
        return str(path)


def patch_file(path, transform, text=None):
    """Run one patch on one file; every failure becomes an InstallError tied to that file."""
    name = getattr(transform, '__name__', 'patch')
    try:
        if text is None:
            text = read(path)
        return transform(text)
    except InstallError as error:
        error.file = error.file or show_path(path)
        error.patch = error.patch or name
        error.hint = error.hint or default_hint(error.message, error.file)
        raise
    except Exception as error:
        message = str(error) or type(error).__name__
        raise InstallError(message, show_path(path), name, default_hint(message, show_path(path))) from error


def read(path):
    try:
        return Path(path).read_text(encoding='utf-8')
    except OSError as error:
        raise InstallError(f'Cannot read {show_path(path)}: {error.strerror or error}', show_path(path),
                           hint=default_hint('file missing', show_path(path))) from error


def payload_text(name):
    try:
        return (SOURCE/'payload'/name).read_text(encoding='utf-8')
    except OSError as error:
        raise InstallError(f'Addon payload file missing: payload/{name}', f'payload/{name}',
                           hint='This copy of the addons is incomplete; update or re-clone the repository.') from error


def keybinds_path():
    return CONFIG/'hypr/config/keybinds.lua'


def shader_package_name(folder, stem='atmosphere'):
    source = folder/(stem + '.frag')
    package = folder/(stem + '.frag.qsb')
    manifest = json.loads((folder/'manifest.json').read_text())
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
    if manifest.get('source_sha256') != source_hash or manifest.get('package_sha256') != package_hash:
        raise InstallError(f'Shader {stem} source/package mismatch; run python3 scripts/build-seasonal-shaders.py')
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
                    raise InstallError('Guide tabs model anchor changed')
                match = matches[0]
                text = text[:match.start()] + block + match.group(0) + text[match.end():]
        banners_entry = '                { id: "AddonsBanners", key: "addons_banners", name: "Banners", icon: "󰓻", file: "AddonsBannersTab.qml", iconOffsetX: 0 }'
        mouse_entry = '                { id: "AddonsMouse", key: "addons_mouse", name: "Mouse", icon: "󰍽", file: "AddonsMouseTab.qml", iconOffsetX: 0 }'
        if banners_entry not in text:
            if text.count(mouse_entry) != 1: raise InstallError('Guide addons mouse subtab anchor changed')
            text = text.replace(mouse_entry, mouse_entry + ',\n' + banners_entry, 1)
        # Added after the first release, so existing tab blocks gain it on reinstall.
        keybinds_entry = '        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },'
        startup_entry = '        { id: "Startup", key: "addon_startup", name: "Startup", icon: "󰐥", file: "AddonStartupTab.qml", iconOffsetX: 0 },'
        if startup_entry not in text:
            if text.count(keybinds_entry) != 1: raise InstallError('Guide keybinds tab anchor changed')
            text = text.replace(keybinds_entry, keybinds_entry + '\n' + startup_entry, 1)
        old ='                return I18n.t("guide.tabs." + (t.key || t.id).toLowerCase(), t.name || t.id);'
        new = '''                let key = "guide.tabs." + (t.key || t.id).toLowerCase();
                let label = I18n.t(key);
                return label && label !== key ? label : (t.name || t.id);'''
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text and 'return translated === translationKey ? (t.name || t.id) : translated;' not in text and 'return translated && translated !== translationKey ? translated : (t.name || t.id);' not in text:
            raise InstallError('Guide tab title fallback anchor changed')
        old_subtab = '                        return I18n.t("guide.tabs." + (st.key || st.id).toLowerCase(), st.name || st.id);'
        new_subtab = '''                        let key = "guide.tabs." + (st.key || st.id).toLowerCase();
                        let label = I18n.t(key);
                        return label && label !== key ? label : (st.name || st.id);'''
        if old_subtab in text:
            text = text.replace(old_subtab, new_subtab, 1)
        elif new_subtab not in text:
            raise InstallError('Guide subtab title fallback anchor changed')
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
    if text.count(anchor) != 1: raise InstallError('Guide tabs anchor changed')
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
        raise InstallError('Guide sidebar anchor changed')
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
            raise InstallError('Guide sidebar title anchor changed')
    return text


def patch_idle_tab(text):
    if 'import QtQuick.Effects' not in text:
        text = text.replace('import QtQuick\n', 'import QtQuick\nimport QtQuick.Effects\n', 1)
    if 'import Quickshell.Services.UPower' not in text:
        text = text.replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Services.UPower\n', 1)
    laptop_property = '    readonly property bool codexModeAvailable: UPower.displayDevice.ready ? UPower.displayDevice.isLaptopBattery : !SystemInfo.isDesktop'
    if laptop_property not in text:
        anchor = '    property bool lockOnSleep: idleSettings && idleSettings.lockOnSleep !== undefined ? idleSettings.lockOnSleep : true'
        if text.count(anchor) != 1: raise InstallError('Idle laptop detection anchor changed')
        text = text.replace(anchor, anchor + '\n' + laptop_property, 1)
    marker = 'settingId: "idle_manual_system_awake"'
    rectangle_anchor = '            Rectangle {\n                Layout.fillWidth: true\n                implicitHeight: actionsBoxCol.implicitHeight + rootObj.s(24)'
    if text.count(rectangle_anchor) != 1: raise InstallError('Do Not Disturb companion option anchor changed')
    if marker in text:
        option_start = text.rfind('            SettingsRow {', 0, text.index(marker))
        if option_start < 0: raise InstallError('Do Not Disturb companion option boundaries changed')
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
        if option_end < 0: raise InstallError('Do Not Disturb companion option boundaries changed')
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
            if option.count(toggle_anchor) != 1: raise InstallError('Do Not Disturb toggle anchor changed')
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
    if option_anchor < 0: raise InstallError('Do Not Disturb settings group anchor changed')
    text = text[:option_anchor].rstrip() + '\n\n' + option + '\n' + text[option_anchor:]
    default_anchor = '        "manualInhibit": false,'
    if '"keepSystemAwake": false,' not in text:
        if text.count(default_anchor) != 1: raise InstallError('Idle setting defaults anchor changed')
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
    if len(anchors) != 1: raise InstallError('Network root anchor changed')
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
        if len(matches) != 1: raise InstallError('Weather city patch markers are duplicated')
        return pattern.sub(lambda match: replacement + ('\n' if match.group(0).endswith('\n') else ''), text, count=1)
    if text.count(anchor) != 1: raise InstallError('Weather city label anchor changed')
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
            if text.count(old_anchor) != 1: raise InstallError('Matugen wallpaper generation anchor changed')
            text = text.replace(old_anchor, '''                    // BEGIN serpantinum-addons-v2 Matugen video wallpaper source
                    let imagePath = themeTabRoot.isWallpaperVideo
                        ? Caching.getCacheDir("wallpaper") + "/current_wallpaper.png"
                        : themeTabRoot.currentWallpaperPath;
                    Matugen.generate(imagePath, current.mode, current.schemeType);
                    // END serpantinum-addons-v2 Matugen video wallpaper source''', 1)
    if '// BEGIN serpantinum-addons-v2 theme cards' in text:
        return text.replace('themeTabRoot.systemPresets = sys;', 'themeTabRoot.systemPresets = sys.slice();')
    anchor = '                        themeTabRoot.userPresets = usr;'
    if text.count(anchor) != 1: raise InstallError('Theme preset list anchor changed')
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
    if text.count(anchor) != 1: raise InstallError('Theme wallpaper preview anchor changed')
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
        if text.count(anchor) != 1: raise InstallError('Matugen color mode anchor changed')
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
    if text.count(anchor) != 1: raise InstallError('Matugen command anchor changed')
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
    if text.count(anchor) != 1: raise InstallError('Shell root component anchor changed')
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
        if text.count(anchor) != 1: raise InstallError('Screenshot capture command anchor changed')
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
        if text.count(anchor) != 1: raise InstallError('Screenshot freeze lifecycle anchor changed')
        text = text.replace(anchor, anchor + '    property string pendingCaptureFreezeImg: ""\n', 1)

    anchor = '            Quickshell.execDetached(["bash", "-c", pendingCmd]);\n'
    if 'root.pendingCaptureFreezeImg = "";' not in text:
        if text.count(anchor) != 1: raise InstallError('Screenshot timer anchor changed')
        text = text.replace(anchor, anchor + '            root.pendingCaptureFreezeImg = "";\n', 1)

    anchor = '        if (root.freezeImg !== "") Quickshell.execDetached(["bash", "-c", "rm -f " + root.freezeImg]);'
    replacement = '        if (root.freezeImg !== "" && root.freezeImg !== root.pendingCaptureFreezeImg) Quickshell.execDetached(["bash", "-c", "rm -f " + root.freezeImg]);'
    if anchor in text:
        text = text.replace(anchor, replacement)
    elif text.count(replacement) != 2: raise InstallError('Screenshot freeze cleanup anchor changed')

    anchor = '        captureTimer.pendingCmd = cmd;\n'
    assignment = '        root.pendingCaptureFreezeImg = (!isRecord && root.freezeImg !== "" && root.screen) ? root.freezeImg : "";\n'
    if assignment not in text:
        if text.count(anchor) != 1: raise InstallError('Screenshot capture lifecycle anchor changed')
        text = text.replace(anchor, assignment + anchor, 1)
    return text


def patch_screenshot_script(text):
    if '        --source) SOURCE_IMG="$2"; shift 2 ;;' in text and 'crop_source() {' in text:
        return text
    marker = '# BEGIN serpantinum-addons-v2 frozen screenshot source'
    if marker in text: return text
    anchor = 'GEOMETRY=""\n'
    if text.count(anchor) != 1: raise InstallError('Screenshot geometry argument anchor changed')
    text = text.replace(anchor, anchor + 'FROZEN_IMG=""\nFROZEN_GEOMETRY=""\nFROZEN_SIZE=""\n', 1)
    anchor = '        --geometry) GEOMETRY="$2"; shift 2 ;;\n'
    if text.count(anchor) != 1: raise InstallError('Screenshot argument parser anchor changed')
    text = text.replace(anchor, anchor + '''        --frozen-image) FROZEN_IMG="$2"; shift 2 ;;
        --frozen-geometry) FROZEN_GEOMETRY="$2"; shift 2 ;;
        --frozen-size) FROZEN_SIZE="$2"; shift 2 ;;
''', 1)
    anchor = '''    if [ -n "$GEOMETRY" ]; then
        grim -l 0 -g "$GEOMETRY" "$TMP_SCREENSHOT"
    elif [ -n "$TARGET_MON" ]; then
'''
    if text.count(anchor) != 1: raise InstallError('Screenshot region capture anchor changed')
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
    if text.count(anchor) != 1: raise InstallError('Screenshot cleanup trap anchor changed')
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
    if text.count(old) != 1: raise InstallError('Frozen screenshot validation anchor changed')
    return text.replace(old, new, 1)


def patch_floating(text):
    marker = '                                // BEGIN serpantinum-addons-v2 picker action\n'
    if marker in text:
        return text.replace('Quickshell.execDetached(["quickshell", "ipc", "call", "addonColorPicker", "toggle"]);', 'Quickshell.execDetached(["quickshell", "-p", Caching.mainQml, "ipc", "call", "addonColorPicker", "toggle"]);')
    anchor = '                                Rectangle {\n                                    id: pinButton'
    if text.count(anchor) != 1: raise InstallError('Quickactions pin anchor changed')
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
    if '"SUPER + SHIFT + C"' in text: raise InstallError('Color picker shortcut already in use')
    anchor = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })'
    if text.count(anchor) != 1: raise InstallError('Screenshot shortcut anchor changed')
    addition = '''\n-- BEGIN serpantinum-addons-v2 color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("''' + command + '''"), { locked = true })
-- END serpantinum-addons-v2 color picker'''
    return text.replace(anchor, anchor + addition, 1)


def mouse_script_path():
    return DEPLOY/'scripts/mouse-next-monitor-center.sh'


def patch_window_keybinds(text):
    marker = '-- BEGIN serpantinum-addons-v2 window switching'
    mouse_script = json.dumps(shlex.quote(str(mouse_script_path())))
    if marker in text:
        # Early installs pointed Super+Tab at a script in ~/.config/hypr/scripts that this repo never shipped.
        # Upgrade only that generated command, so user edits inside the managed block survive.
        return re.sub(r'(hl\.bind\("SUPER \+ Tab", hl\.dsp\.exec_cmd\()"[^"\n]*/hypr/scripts/mouse-next-monitor-center\.sh"',
                      lambda match: match.group(1) + mouse_script, text)
    if '"SUPER + Tab"' in text or '"ALT + Tab"' in text: raise InstallError('Window switching shortcuts already in use')
    anchor = '-- END serpantinum-addons-v2 color picker'
    if text.count(anchor) != 1: raise InstallError('Color picker shortcut anchor changed')
    addition = '''\n-- BEGIN serpantinum-addons-v2 window switching
-- Super+Tab : écran suivant + souris au centre de cet écran
hl.bind("SUPER + Tab", hl.dsp.exec_cmd(''' + mouse_script + '''))
-- Alt+Tab : fenêtre suivante dans l'écran et le workspace courants, mise au premier plan
hl.bind("ALT + Tab", hl.dsp.exec_cmd("hyprctl eval 'hl.dispatch(hl.dsp.window.cycle_next()); hl.dispatch(hl.dsp.window.bring_to_top())'"))
-- END serpantinum-addons-v2 window switching'''
    return text.replace(anchor, anchor + addition, 1)


def patch_spotlight_keybind(text):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = '-- BEGIN serpantinum-addons-v2 mouse spotlight'
    if marker in text: return text
    if '"SUPER + SHIFT + M"' in text: raise InstallError('Mouse spotlight shortcut already in use')
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
            raise InstallError('Desktop zoom keybind block changed')
        return text.replace(end_marker, end_marker + '\n\n' + scroll_block, 1)
    if '"SUPER + SHIFT + Z"' in text: raise InstallError('Desktop zoom shortcut already in use')
    return (text.rstrip() + '\n\n' + marker + '\n'
            + 'hl.bind("SUPER + SHIFT + Z", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n'
            + end_marker + '\n\n' + scroll_block + '\n')


def patch_draw_keybind(text):
    marker = '-- BEGIN serpantinum-addons-v2 desktop draw'
    if marker in text: return text
    if '"SUPER + SHIFT + D"' in text: raise InstallError('Desktop drawing shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopDraw toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 desktop draw\n'


def remove_inline_settings(text, prefix):
    pattern = rf"(?m)^[ \t]*{re.escape(prefix)} BEGIN serpantinum-addons-v2 inline settings\n.*?^[ \t]*{re.escape(prefix)} END serpantinum-addons-v2 inline settings\n?"
    return re.sub(pattern, "", text, flags=re.S)


# --------------------------------------------------------------------------- companions
# Companion modules (capri, clawd, tokens, ...) expose MARK, transformations(qs), remove(text) and, optionally,
# patch_keybind(text, shell_qml) and resources(payload_dir, qs). To add one: import it above, append a Companion
# below (its `without_*` option name feeds the --without-<name> flag), add its payload copy rules to
# build_plan() and its created files to plan.created. Everything else (CLI flag, removal from the Banners tab,
# manifest, uninstall) follows from the table.
class Companion:
    def __init__(self, name, module, option):
        self.name, self.module, self.option = name, module, option


COMPANIONS = [
    Companion('halloween', seasonal, 'without_halloween'),
    Companion('capri', capri, 'without_capri'),
    Companion('clawd', clawd, 'without_clawd'),
    Companion('tokens', tokens, 'without_tokens'),
]

PAYLOAD_FILES = {
    'AddonWindowOutline.qml': 'AddonWindowOutline.qml', 'AddonAwake.qml': 'AddonAwake.qml', 'AddonDesktopDraw.qml': 'AddonDesktopDraw.qml',
    'AddonDesktopZoom.qml': 'AddonDesktopZoom.qml', 'AddonMouseSpotlight.qml': 'AddonMouseSpotlight.qml', 'AddonColorPicker.qml': 'AddonColorPicker.qml',
    'AddonsTab.qml': 'guide/AddonsTab.qml', 'AddonsMouseTab.qml': 'guide/AddonsMouseTab.qml', 'AddonsBannersTab.qml': 'guide/AddonsBannersTab.qml',
    'AddonMonitorsTab.qml': 'guide/AddonMonitorsTab.qml', 'AddonKeybindsTab.qml': 'guide/AddonKeybindsTab.qml', 'AddonStartupTab.qml': 'guide/AddonStartupTab.qml',
    'DnsControl.qml': 'network/DnsControl.qml', 'LegacyCalendar.qml': 'calendar/LegacyCalendar.qml', 'CalendarPopup.qml': 'calendar/CalendarPopup.qml',
    **{name + '.qml': 'guide/' + name + '.qml' for name in ('AddonCursorSettings', 'AddonCursorPreview', 'AddonCursorRole', 'AddonCursorTestArea')},
    'AddonPaletteEditor.qml': 'guide/theme/AddonPaletteEditor.qml',
    'AddonGlassSurface.qml': 'reusables/AddonGlassSurface.qml',
}
# Upstream files that the payload replaces outright (they exist upstream, so uninstall restores rather than deletes them).
OVERWRITES = ('calendar/CalendarPopup.qml',)
WALLPAPER_FILES = ('singletons/theme/Wallpaper.qml', 'wallpaper/WallpaperEngine.qml', 'reusables/display/WallpaperBlur.qml')
BANNER_TAB = 'guide/AddonsBannersTab.qml'


class Plan:
    def __init__(self):
        self.pending = {}        # Path -> new text (transformed upstream files and payload text copies)
        self.blobs = []          # (Path, bytes, remove) payload resources
        self.created = set()     # Paths copied from the payload (or generated) that do not exist upstream or are replaced outright
        self.shader_dirs = []    # (dir, stem, keep-name) for superseded hashed shader packages
        self.screenshot = None
        self.keybinds = keybinds_path()


def build_plan(without_halloween=False, without_capri=False, without_clawd=False, without_tokens=False):
    """Compute every change in memory. Fail closed: any unknown upstream shape raises InstallError, nothing is written."""
    options = {'without_halloween': without_halloween, 'without_capri': without_capri,
               'without_clawd': without_clawd, 'without_tokens': without_tokens}
    plan = Plan()
    pending = plan.pending
    theme_state = QS/'guide/theme/ThemeTabState.qml'
    theme_view = QS/'guide/theme/ThemeTab.qml'
    patches = {QS/'Main.qml': lambda text: remove_inline_settings(patch_main(text), '//'), QS/'WindowRegistry.js': lambda text: remove_inline_settings(text, '//'),
               QS/'Shell.qml': patch_shell, QS/'screenshot/ScreenshotOverlay.qml': patch_screenshot_overlay, QS/'quickactions/Floating.qml': patch_floating,
               QS/'guide/GuidePopup.qml': patch_guide, QS/'guide/GuideSidebar.qml': patch_guide_sidebar, QS/'guide/IdleTab.qml': patch_idle_tab,
               (theme_state if theme_state.exists() else theme_view): patch_theme, QS/'network/NetworkPopup.qml': patch_network,
               QS/'singletons/theme/Matugen.qml': patch_matugen, QS/'widgets/faces/weather/WeatherFaceFull.qml': patch_weather_face}
    for path, transform in patches.items():
        pending[path] = patch_file(path, transform)
    pending[theme_view] = patch_file(theme_view, patch_theme_view, pending.get(theme_view))
    plan.screenshot = QS.parent/'scripts/screenshot.sh'
    text = patch_file(plan.screenshot, patch_screenshot_script)
    text = patch_file(plan.screenshot, patch_screenshot_cleanup, text)
    pending[plan.screenshot] = patch_file(plan.screenshot, patch_screenshot_frozen_validation, text)

    kb = plan.keybinds
    text = read(kb)
    for transform in (patch_keybinds, patch_window_keybinds, patch_spotlight_keybind, patch_zoom_keybind, patch_draw_keybind):
        text = patch_file(kb, transform, text)
    pending[kb] = patch_file(kb, lambda value: remove_inline_settings(value, '--'), text)

    def staged(path):
        return pending[path] if path in pending else read(path)

    for companion in COMPANIONS:
        removing = options[companion.option]
        module = companion.module
        for path, transform in module.transformations(QS).items():
            pending[path] = patch_file(path, module.remove if removing else transform, staged(path))
        if companion.name == 'halloween':
            for name, transform in [('equalizer.sh', seasonal_surfaces.remove_audio_boost_backend),
                                    ('MusicEqualizerState.qml', seasonal_surfaces.remove_audio_boost_qml),
                                    ('MusicAudioView.qml', seasonal_surfaces.remove_audio_boost_qml)]:
                path = QS/'media'/name
                pending[path] = patch_file(path, transform)
        if hasattr(module, 'patch_keybind'):
            pending[kb] = patch_file(kb, module.remove if removing else (lambda value, m=module: m.patch_keybind(value, QS/'Shell.qml')), pending[kb])

    # The in-shell update UI is not optional (no --without flag): always patched, always copied.
    for path, transform in release_ui.transformations(QS).items():
        pending[path] = patch_file(path, transform, staged(path))
    for source, target in release_ui.payloads().items():
        pending[QS/target] = payload_text(source.removeprefix('payload/'))
        plan.created.add(QS/target)

    # Payload files are copied verbatim (or stripped of the options of a removed companion).
    for source, target in PAYLOAD_FILES.items():
        pending[QS/target] = payload_text(source)
        plan.created.add(QS/target)
    pending[QS/'guide/DnsControl.qml'] = payload_text('DnsControl.qml')
    plan.created.add(QS/'guide/DnsControl.qml')
    for path, declarations in [(QS/'guide/theme/qmldir', ['AddonPaletteEditor 1.0 AddonPaletteEditor.qml']),
                               (QS/'reusables/qmldir', ['AddonGlassSurface 1.0 AddonGlassSurface.qml']),
                               (QS/'guide/qmldir', [c + ' 1.0 ' + c + '.qml' for c in ('AddonCursorSettings', 'AddonCursorPreview', 'AddonCursorRole', 'AddonCursorTestArea')] + ['DnsControl 1.0 DnsControl.qml']),
                               (QS/'network/qmldir', ['DnsControl 1.0 DnsControl.qml']),
                               (QS/'qmldir', ['AddonColorPicker 1.0 AddonColorPicker.qml', 'AddonMouseSpotlight 1.0 AddonMouseSpotlight.qml', 'AddonDesktopZoom 1.0 AddonDesktopZoom.qml',
                                              'AddonDesktopDraw 1.0 AddonDesktopDraw.qml', 'AddonAwake 1.0 AddonAwake.qml', 'AddonWindowOutline 1.0 AddonWindowOutline.qml'])]:
        original = pending[path] if path in pending else (read(path) if path.exists() else '')
        for declaration in declarations:
            if declaration not in original:
                original = original.rstrip() + '\n' + declaration + '\n'
        pending[path] = original

    # NativeCalendar is captured before installing the wrapper, then patched in memory. The native UI remains
    # the source of truth for both seasonal states.
    native_calendar = QS/'calendar/NativeCalendar.qml'
    calendar_text = read(QS/'calendar/CalendarPopup.qml')
    wrapped = '// BEGIN serpantinum-addons-v2 calendar wrapper' in calendar_text
    if wrapped and not native_calendar.is_file():
        raise InstallError('Native calendar backup is missing', 'calendar/NativeCalendar.qml', 'patch_calendar',
                           'Restore calendar/NativeCalendar.qml from a backup under ~/.local/share/serpantinum-addons-v2/backups, or run `addons.py uninstall` and reinstall.')
    native_text = read(native_calendar) if wrapped else calendar_text
    clock_transform = seasonal.remove if without_halloween else (lambda text: seasonal_surfaces.calendar(seasonal.patch_calendar(text)))
    pending[native_calendar] = patch_file(native_calendar, clock_transform, native_text)
    plan.created.add(native_calendar)
    legacy = QS/'calendar/LegacyCalendar.qml'
    pending[legacy] = patch_file(legacy, clock_transform, pending[legacy])
    # The three companion options live on the Banners subtab (and, for older layouts, the General tab).
    for companion in COMPANIONS:
        if options[companion.option]:
            for tab in (QS/'guide/AddonsTab.qml', QS/BANNER_TAB):
                pending[tab] = patch_file(tab, companion.module.remove, pending[tab])

    # Read and verify all payloads before touching the installation. A forgotten shader rebuild or missing
    # resource must never leave partly applied hooks.
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
    try:
        clawd_resources = clawd.resources(SOURCE/'payload/clawd', QS)
        tokens_resources = tokens.resources(SOURCE/'payload/tokens', QS)
    except InstallError:
        raise
    except Exception as error:
        raise InstallError(str(error), 'payload', 'resources', 'Rebuild the generated assets named above (see docs), then run the installer again.') from error
    groups = [(resource_payloads, without_halloween), (capri_resources, without_capri),
              (clawd_resources, without_clawd), (tokens_resources, without_tokens)]
    for blobs, removing in groups:
        for path, blob in blobs:
            plan.blobs.append((path, blob, removing))
            if not removing:
                plan.created.add(path)
    plan.shader_dirs = [(QS/'seasonal/shaders', 'atmosphere', shader_name), (QS/'capri/shaders', 'sprite', sprite_name)]
    bridge = HOME/'.local/lib/qt6/qml/Serpantinum/Wallpaper/libSerpantinumWallpaperplugin.so'
    if bridge.is_file():
        try:
            wallpaper_engine.prepare(pending, QS, DEPLOY, HOME/'.local')
        except InstallError:
            raise
        except Exception as error:
            raise InstallError(str(error) or type(error).__name__, 'wallpaper bridge', 'wallpaper_engine.prepare', default_hint(str(error), 'the wallpaper files')) from error
    plan.options = options
    return plan


def manifest_of(plan):
    """patched: every managed upstream file (shell-folder relative; '../scripts/screenshot.sh' is src/scripts/screenshot.sh);
    created: every file copied from the payload; keybinds: absolute path of the Hyprland keybinds file, patched by marked blocks."""
    created = {show_path(path) for path in plan.created}
    patched = {show_path(path) for path in plan.pending if path != plan.keybinds and path not in plan.created}
    patched |= set(OVERWRITES)
    created |= {show_path(path) for path, _, removing in plan.blobs if not removing}
    return {'patched': sorted(patched), 'created': sorted(created), 'keybinds': str(plan.keybinds)}


# --------------------------------------------------------------------------- applying
def _mode_of(path, screenshot=None):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    return mode | 0o755 if path == screenshot else mode


def shell_ops(plan):
    """Operations that would change the shell: ('write', path, bytes, mode) or ('delete', path)."""
    ops = []
    for path, text in plan.pending.items():
        data, mode = text.encode('utf-8'), _mode_of(path, plan.screenshot)
        if path.is_file() and path.read_bytes() == data and stat.S_IMODE(path.stat().st_mode) == mode: continue
        ops.append(('write', path, data, mode))
    for path, blob, removing in plan.blobs:
        if removing:
            if path.exists(): ops.append(('delete', path))
        elif not (path.exists() and path.read_bytes() == blob):
            ops.append(('write', path, blob, _mode_of(path)))
    # Qt caches GPU programs by URL across hot reloads. Keep only the package matching this source.
    for shader_dir, stem, keep in plan.shader_dirs:
        if not shader_dir.exists(): continue
        for path in sorted(shader_dir.iterdir()):
            owned = path.name == stem + '.frag.qsb' or re.fullmatch(stem + r'\.[a-f0-9]{12}\.frag\.qsb', path.name)
            if owned and path.name != keep and ('delete', path) not in ops:
                ops.append(('delete', path))
    for path in clawd.stale_shaders(QS, everything=plan.options['without_clawd']):
        if ('delete', path) not in ops:
            ops.append(('delete', path))
    return ops


def deploy_ops():
    """DEPLOY/scripts mirrors SOURCE/scripts exactly; stale DEPLOY/install.py and DEPLOY/payload leftovers go."""
    ops = []
    if SOURCE == DEPLOY.resolve():
        return ops
    for name in ('install.py', 'payload'):
        if os.path.lexists(DEPLOY/name):
            ops.append(('remove', DEPLOY/name))
    src, dst = SOURCE/'scripts', DEPLOY/'scripts'
    wanted = {}
    for path in sorted(src.rglob('*')):
        relative = path.relative_to(src)
        if '__pycache__' in relative.parts or path.suffix == '.pyc': continue
        wanted[relative] = path
    if dst.is_symlink() or (dst.exists() and not dst.is_dir()):
        ops.append(('remove', dst))
    stale = []
    if dst.is_dir() and not dst.is_symlink():
        for path in sorted(dst.rglob('*')):
            relative = path.relative_to(dst)
            if relative not in wanted or (wanted[relative].is_dir() != (path.is_dir() and not path.is_symlink())):
                if not any(parent in stale for parent in path.parents):
                    stale.append(path)
    ops += [('remove', path) for path in stale]
    for relative, path in wanted.items():
        target = dst/relative
        if path.is_dir(): continue
        same = (target.is_file() and not target.is_symlink() and target not in stale and target.read_bytes() == path.read_bytes()
                and stat.S_IMODE(target.stat().st_mode) == stat.S_IMODE(path.stat().st_mode))
        if not same: ops.append(('copy', path, target))
    return ops


def write_atomic(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream: stream.write(data)
        os.replace(name, path)
    except BaseException:
        try: os.unlink(name)
        except OSError: pass
        raise


def backup_name(path, plan_keybinds):
    if path == plan_keybinds: return Path('hypr/keybinds.lua')
    try: return path.relative_to(QS)
    except ValueError: return Path(os.path.relpath(path, QS.parent))


def save_backup(path, backup, keybinds):
    if path.exists() or path.is_symlink():
        saved = backup/backup_name(path, keybinds)
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, saved, follow_symlinks=False)


def remove_path(path):
    if path.is_dir() and not path.is_symlink(): shutil.rmtree(path)
    else: path.unlink(missing_ok=True)


# --------------------------------------------------------------------------- gate, lock, state
def gate(force=False):
    """Version gate. Returns (serpantinum_state, compat_status, warnings); raises InstallError when too old."""
    state = release.serpantinum_state()
    compat = release.load_compat(SOURCE/'compat.json')
    status = release.compat_status(state['version'], compat)
    entry = compat.get('serpantinum') or {}
    warnings = []
    if status == 'too_old':
        message = f"Serpantinum {state['version']} is older than the minimum these addons support ({entry.get('min')})"
        if not force:
            raise InstallError(message, hint='Update Serpantinum first, or pass --force to try anyway (patches still fail closed). Nothing was modified.')
        warnings.append(message + '; continuing because of --force')
    elif status == 'newer_than_tested':
        warnings.append(f"Serpantinum {state['version']} is newer than the tested {entry.get('tested')}; continuing (patches fail closed if anything moved)")
    elif status == 'unknown':
        warnings.append('Could not determine the Serpantinum version or compatibility range; continuing (patches fail closed if anything moved)')
    return state, status, warnings


class Lock:
    def __init__(self):
        self.path = release.state_dir()/'install.lock'
        self.handle = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = open(self.path, 'a+')
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.handle.close()
            raise InstallBusy('Another addons install or uninstall is already running', str(self.path), 'lock',
                              'Wait for it to finish, or remove the lock file if no installer is running.') from error
        return self

    def __exit__(self, *exc):
        try: fcntl.flock(self.handle, fcntl.LOCK_UN)
        finally: self.handle.close()


def git_commit():
    try:
        result = subprocess.run(['git', '-C', str(SOURCE), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True, timeout=10)
        return result.stdout.strip() or None if result.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def record_install(plan, state):
    channel = 'release' if SOURCE == (DEPLOY/'source').resolve() else 'dev'
    try: version = (SOURCE/'VERSION').read_text().strip() or None
    except OSError: version = None
    without = [c.name for c in COMPANIONS if plan.options[c.option]]
    release.write_install_state({
        'version': version, 'commit': git_commit(), 'channel': channel, 'source': str(SOURCE),
        'serpantinum_version': state['version'], 'serpantinum_commit': state['commit'],
        'installed_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'without': without, 'manifest': manifest_of(plan),
    })
    for name in ('VERSION', 'compat.json'):
        if (SOURCE/name).is_file():
            shutil.copyfile(SOURCE/name, release.state_dir()/name)


def say(report, message):
    if not report.get('quiet'):
        print(message)


# --------------------------------------------------------------------------- install
def install(without_halloween=False, without_capri=False, without_clawd=False, without_tokens=False, check=False, force=False, quiet=False):
    """Install (or, with check=True, only compute) the addons. Raises InstallError; returns a report dict."""
    report = {'quiet': quiet, 'changes': 0, 'changed_files': [], 'warnings': [], 'backup': None}
    configure_paths()
    state, status, report['warnings'] = gate(force)
    for warning in report['warnings']:
        say(report, f'warning: {warning}')
    if check:
        return _install_locked(report, state, check, without_halloween, without_capri, without_clawd, without_tokens)
    with Lock():
        return _install_locked(report, state, check, without_halloween, without_capri, without_clawd, without_tokens)


def _install_locked(report, state, check, without_halloween, without_capri, without_clawd, without_tokens):
    # Calculate all transformations first. Never partly apply an unknown upstream revision.
    plan = build_plan(without_halloween, without_capri, without_clawd, without_tokens)
    ops = shell_ops(plan)
    extra = deploy_ops()
    report['changes'] = len(ops) + len(extra)
    report['changed_files'] = [show_path(op[1]) for op in ops] + ['~deploy/' + os.path.relpath(op[-1], DEPLOY) for op in extra]
    if check:
        say(report, f"check ok: {report['changes']} change(s) would be made; nothing was written")
        return report
    # Before any shell file changes: a hooks file we cannot rewrite stops the whole run.
    if without_clawd:
        clawd.uninstall_hooks()
    backup = DEPLOY/'backups'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    for op in ops:
        path = op[1]
        if not backup.exists(): backup.mkdir(parents=True)
        save_backup(path, backup, plan.keybinds)
        if op[0] == 'write': write_atomic(path, op[2], op[3])
        else: path.unlink()
    if ops: report['backup'] = str(backup)
    for op in extra:
        if op[0] == 'remove':
            remove_path(op[1])
        else:
            op[2].parent.mkdir(parents=True, exist_ok=True)
            if os.path.lexists(op[2]) and not op[2].is_file(): remove_path(op[2])
            shutil.copy2(op[1], op[2])
    record_install(plan, release.serpantinum_state())
    say(report, f"v2 installed: {len(ops)} shell files changed; backups: {backup}")
    message = tokens.service(DEPLOY, HOME, remove=without_tokens)
    say(report, message)
    return report


# --------------------------------------------------------------------------- uninstall
class UpstreamUnavailable(Exception):
    pass


def upstream_cache():
    return Path(os.environ.get('SERPANTINUM_UPSTREAM_CACHE') or HOME/'.cache/serpantinum-installer')


class Upstream:
    """Pristine files of the installed Serpantinum commit: local clone first, raw.githubusercontent.com as fallback."""
    def __init__(self, commit):
        self.commit, self.cache = commit, upstream_cache()
        self.local = None

    def _git(self, *args):
        return subprocess.run(['git', '-C', str(self.cache), *args], capture_output=True, timeout=60)

    def has_local_commit(self):
        if self.local is None:
            try: self.local = self.cache.is_dir() and self._git('cat-file', '-e', self.commit + '^{commit}').returncode == 0
            except (OSError, subprocess.SubprocessError): self.local = False
        return self.local

    def fetch(self, relative):
        """bytes, or None when the file does not exist at that commit. UpstreamUnavailable when it cannot be told."""
        if self.has_local_commit():
            try: result = self._git('show', f'{self.commit}:{relative}')
            except (OSError, subprocess.SubprocessError) as error: raise UpstreamUnavailable(str(error)) from error
            return result.stdout if result.returncode == 0 else None
        return self._http(relative)

    def _http(self, relative, probe=True):
        if probe and not hasattr(self, '_probed'):
            self._probed = True
            if self._http('src/quickshell/Shell.qml', probe=False) is None:
                raise UpstreamUnavailable(f'commit {self.commit} is unknown to {UPSTREAM_RAW}')
        try:
            with urllib.request.urlopen(f'{UPSTREAM_RAW}/{self.commit}/{relative}', timeout=10) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404: return None
            raise UpstreamUnavailable(f'HTTP {error.code} for {relative}') from error
        except (urllib.error.URLError, OSError) as error:
            raise UpstreamUnavailable(f'offline or unreachable ({error})') from error


KEYBIND_BLOCK = re.compile(r'\n*^-- BEGIN (serpantinum-[\w-]*v2) ([^\n]+)\n.*?^-- END \1 \2[ \t]*(?:\n|\Z)', re.S | re.M)


def strip_keybind_blocks(text):
    """Remove every managed `-- BEGIN serpantinum-*-v2 <name>` ... `-- END ... <name>` block, one at a time
    so adjacent blocks do not leave blank lines behind. The rest of the user's file is untouched."""
    while KEYBIND_BLOCK.search(text):
        text = KEYBIND_BLOCK.sub('\n', text, count=1)
    return text


def addon_state_dirs():
    state_home = Path(os.environ.get('XDG_STATE_HOME') or HOME/'.local/state')
    tokens_dir = Path(os.environ.get('TOKENS_STATE_DIR') or HOME/'.local/state/serpantinum/tokens')
    candidates = [tokens_dir, state_home/'serpantinum/tokens', state_home/'serpantinum/capri', state_home/'serpantinum/clawd']
    seen, result = set(), []
    for path in candidates:
        if path not in seen: seen.add(path); result.append(path)
    return result


def within_addon_data(path):
    """True only when `path` resolves inside a known addon data dir, so an env override cannot widen --purge."""
    state_home = Path(os.environ.get('XDG_STATE_HOME') or HOME/'.local/state')
    roots = {(base/name).resolve() for base in (state_home, HOME/'.local/state') for name in ('serpantinum', 'serpantinum-addons-v2')}
    resolved = path.resolve()
    return any(resolved != root and root in resolved.parents for root in roots)


def uninstall_targets(state):
    """(patched Paths, created Paths, keybinds Path) from install.json, or derived from the engine's own mappings."""
    saved = state if state and isinstance(state.get('manifest'), dict) else None
    if saved:
        manifest = saved['manifest']
        resolve = lambda entry: Path(os.path.normpath(QS/entry))
        patched = [resolve(entry) for entry in manifest.get('patched', [])]
        created = [resolve(entry) for entry in manifest.get('created', [])]
        keybinds = Path(manifest['keybinds']) if manifest.get('keybinds') else keybinds_path()
        origin = 'install.json'
    else:
        plan = build_plan()
        manifest = manifest_of(plan)
        patched = [Path(os.path.normpath(QS/entry)) for entry in manifest['patched']] + [QS/name for name in WALLPAPER_FILES]
        created = [Path(os.path.normpath(QS/entry)) for entry in manifest['created']]
        keybinds = plan.keybinds
        origin = 'the installer mappings (no install.json)'
    return patched, created, keybinds, origin


def sweep_shaders():
    """Hashed shader packages left behind by older installs (the manifest only lists the current names)."""
    found = []
    for shader_dir, stem in ((QS/'seasonal/shaders', 'atmosphere'), (QS/'capri/shaders', 'sprite')):
        if shader_dir.is_dir():
            found += [p for p in sorted(shader_dir.iterdir()) if p.name == stem + '.frag.qsb' or re.fullmatch(stem + r'\.[a-f0-9]{12}\.frag\.qsb', p.name)]
    found += clawd.stale_shaders(QS, everything=True)
    return found


def stop_wallpaper_unit(report):
    unit = HOME/'.config/systemd/user/we-layerd.service'
    if not unit.is_file(): return
    if 'Wallpaper Engine scenes for Serpantinum' not in unit.read_text(errors='replace'):
        report['kept'].append(f'{unit} (not created by the addons)')
        return
    if services_enabled():
        for args in (['disable', '--now', 'we-layerd.service'], ['daemon-reload']):
            try: subprocess.run(['systemctl', '--user', *args], capture_output=True, text=True, timeout=30)
            except (OSError, subprocess.SubprocessError): pass
    unit.unlink()
    report['removed'].append(str(unit))


def uninstall(purge=False, check=False, quiet=False):
    """Restore Serpantinum byte-identical from its installed upstream commit and remove everything the addons added."""
    report = {'quiet': quiet, 'changes': 0, 'changed_files': [], 'warnings': [], 'backup': None, 'removed': [], 'restored': [], 'kept': []}
    configure_paths()
    if check:
        return _uninstall_locked(report, purge, check)
    with Lock():
        return _uninstall_locked(report, purge, check)


def _uninstall_locked(report, purge, check):
    ss = release.serpantinum_state()
    commit = ss['commit']
    if not commit:
        raise InstallError('Cannot tell which Serpantinum commit is installed (SERPANTINUM_COMMIT is missing)',
                           hint='Restore the shell with the Serpantinum installer instead (`serpantinum update`); nothing was modified.')
    state = release.read_install_state()
    patched, created, keybinds, origin = uninstall_targets(state)
    upstream = Upstream(commit)
    targets = []
    for path in dict.fromkeys(patched + created):   # unique, order kept
        relative = os.path.relpath(path, QS.parent.parent)
        if relative.startswith('..'):
            raise InstallError(f'Refusing to touch {path}: outside the Serpantinum folder', str(path), 'manifest', 'install.json looks damaged; nothing was modified.')
        try:
            targets.append((path, upstream.fetch(relative)))
        except UpstreamUnavailable as error:
            raise InstallError(f'Cannot read the original {relative} at Serpantinum {commit}: {error}', relative, 'restore',
                               f'Clone https://github.com/ilyamiro/serpantinum into {upstream.cache} (or set SERPANTINUM_UPSTREAM_CACHE) '
                               'or go online, then retry. Nothing was modified.') from error
    ops = []
    for path, blob in targets:
        if blob is None:
            if path.exists() or path.is_symlink(): ops.append(('delete', path))
        elif not (path.is_file() and path.read_bytes() == blob):
            ops.append(('write', path, blob))
    for path in sweep_shaders():
        if ('delete', path) not in ops: ops.append(('delete', path))
    keybind_old = keybinds.read_text(encoding='utf-8') if keybinds.is_file() else None
    keybind_new = strip_keybind_blocks(keybind_old) if keybind_old is not None else None
    if keybind_new is not None and re.search(r'^-- BEGIN serpantinum-[\w-]*v2 ', keybind_new, re.M):
        report['warnings'].append(f'{keybinds}: a managed block has no matching END line and was left in place')
    report['changed_files'] = [show_path(op[1]) for op in ops]
    if keybind_new is not None and keybind_new != keybind_old: report['changed_files'].append(show_path(keybinds))
    report['changes'] = len(report['changed_files'])
    for warning in report['warnings']: say(report, f'warning: {warning}')
    if check:
        say(report, f"uninstall check ok (restoring from {origin}): {report['changes']} file(s) would change; nothing was written")
        return report
    backup = DEPLOY/'backups'/(datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-uninstall')
    report['backup'] = str(backup)
    for op in ops: save_backup(op[1], backup, keybinds)
    if keybind_new is not None and keybind_new != keybind_old: save_backup(keybinds, backup, keybinds)
    install_json = release.state_dir()/'install.json'
    if install_json.is_file():
        (backup/'state').mkdir(parents=True, exist_ok=True)
        shutil.copy2(install_json, backup/'state/install.json')
    clawd.uninstall_hooks()    # may refuse (foreign hook file): stops before any shell file changes
    for op in ops:
        if op[0] == 'write': write_atomic(op[1], op[2], _mode_of(op[1]))
        else: op[1].unlink()
        report['removed' if op[0] == 'delete' else 'restored'].append(show_path(op[1]))
    # Empty addon folders left behind (deepest first); never anything that still holds files.
    for directory in sorted({p.parent for p in created if p.parent != QS}, key=lambda d: len(d.parts), reverse=True):
        while directory != QS and QS in directory.parents:
            try: directory.rmdir()
            except OSError: break
            directory = directory.parent
    if keybind_new is not None and keybind_new != keybind_old:
        write_atomic(keybinds, keybind_new.encode('utf-8'), _mode_of(keybinds))
        report['removed'].append(f'managed blocks in {keybinds}')
    report['kept'].append(f'everything else in {keybinds}' if keybinds.exists() else str(keybinds))
    say(report, tokens.service(DEPLOY, HOME, remove=True))
    stop_wallpaper_unit(report)
    for leftover in ('scripts', 'install.py', 'payload'):
        if SOURCE == DEPLOY.resolve(): break    # the checkout itself lives at DEPLOY: never delete it
        if os.path.lexists(DEPLOY/leftover):
            remove_path(DEPLOY/leftover)
            report['removed'].append(str(DEPLOY/leftover))
    state_dir = release.state_dir()
    if purge:
        for path in addon_state_dirs():
            if path.exists():
                if not within_addon_data(path):
                    report['kept'].append(f'{path} (kept (outside addon data dirs))')
                    continue
                remove_path(path)
                report['removed'].append(f'{path} (addon data)')
        if state_dir.exists():
            remove_path(state_dir)
            report['removed'].append(f'{state_dir} (addons state)')
    else:
        for name in ('install.json', 'compat.json', 'VERSION'):
            if (state_dir/name).is_file():
                (state_dir/name).unlink()
                report['removed'].append(str(state_dir/name))
        for path in addon_state_dirs():
            if path.exists(): report['kept'].append(f'{path} (addon data; use --purge to delete)')
        if state_dir.exists(): report['kept'].append(f'{state_dir} (other addons state; use --purge to delete)')
    report['kept'] += [str(DEPLOY/name) for name in ('backups', 'source') if (DEPLOY/name).exists()]
    if not backup.exists(): report['backup'] = None
    say(report, f"v2 uninstalled: {len(report['restored'])} file(s) restored from upstream, {report['changes'] - len(report['restored'])} removed/edited; backup: {report['backup']}")
    for title in ('restored', 'removed', 'kept'):
        if report[title]: say(report, f'{title}:\n  ' + '\n  '.join(report[title]))
    say(report, 'Run `serpantinum reload` to apply.')
    return report


# --------------------------------------------------------------------------- CLI
def print_error(error):
    print(f'✗ {error.message}', file=sys.stderr)
    if error.file or error.patch:
        print(f"  why: {error.patch or 'check'} failed on {error.file or 'the installation'}", file=sys.stderr)
    if error.hint:
        print(f'  → {error.hint}', file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--without-halloween', action='store_true', help='Remove the seasonal layer while retaining other v2 addons')
    parser.add_argument('--without-capri', action='store_true', help='Remove the Capri desktop pet while retaining other v2 addons')
    parser.add_argument('--without-clawd', action='store_true', help='Remove the Clawd desktop pet while retaining other v2 addons')
    parser.add_argument('--without-tokens', action='store_true', help='Remove the AI token widget and its collector service while retaining other v2 addons')
    parser.add_argument('--check', action='store_true', help='Compute everything but write nothing')
    parser.add_argument('--json', action='store_true', help='Print one JSON object instead of prose (with --check, install or --uninstall)')
    parser.add_argument('--uninstall', action='store_true', help='Restore Serpantinum from its upstream commit and remove the addons')
    parser.add_argument('--purge', action='store_true', help='With --uninstall: also delete addon state and data (tokens DB, Capri/Clawd state)')
    parser.add_argument('--force', action='store_true', help='Install even when Serpantinum is older than the supported minimum')
    args = parser.parse_args(argv)
    if args.purge and not args.uninstall:
        parser.error('--purge only works together with --uninstall')
    configure_paths()
    report, errors, code = {}, [], 0
    try:
        if args.uninstall:
            report = uninstall(purge=args.purge, check=args.check, quiet=args.json)
        else:
            report = install(without_halloween=args.without_halloween, without_capri=args.without_capri, without_clawd=args.without_clawd,
                             without_tokens=args.without_tokens, check=args.check, force=args.force, quiet=args.json)
    except InstallError as error:
        errors, code = [error], error.code
        if not args.json: print_error(error)
    if args.json:
        try:
            state = release.serpantinum_state()
            status = release.compat_status(state['version'], release.load_compat(SOURCE/'compat.json'))
        except Exception:
            state, status = {}, 'unknown'
        output = {'ok': not errors, 'changes': report.get('changes', 0), 'serpantinum': state, 'compat': status,
                  'errors': [e.as_dict() for e in errors]}
        output.update({k: report[k] for k in ('changed_files', 'warnings', 'backup', 'removed', 'restored', 'kept') if k in report})
        print(json.dumps(output, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
