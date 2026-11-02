#!/usr/bin/env python3
"""Install only v2 addons, preserving upstream files and unrelated v1 work."""
import argparse
import hashlib
import json
import os
import shlex
import shutil
import stat
import tempfile
import seasonal
import seasonal_surfaces
from datetime import datetime
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
QS = Path(os.environ.get('SERPANTINUM_HOME', DATA / 'serpantinum')) / 'src/quickshell'
DEPLOY = DATA / 'serpantinum-addons-v2'
MARK = 'serpantinum-addons-v2'


def shader_package_name(folder):
    source = folder/'atmosphere.frag'
    package = folder/'atmosphere.frag.qsb'
    manifest = json.loads((folder/'manifest.json').read_text())
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
    if manifest.get('source_sha256') != source_hash or manifest.get('package_sha256') != package_hash:
        raise ValueError('Seasonal shader source/package mismatch; run python3 scripts/build-seasonal-shaders.py')
    return 'atmosphere.' + package_hash[:12] + '.frag.qsb'


def patch_guide(text):
    import re
    # v2.2.8 moved guide navigation and content into a model-driven loader.
    # Register addon tabs in that model so upstream handles the sidebar and content.
    if 'property var tabsModel: [' in text:
        if '// BEGIN serpantinum-addons-v2 tabs' not in text:
            import re
            match = re.search(r'(?m)^        \{ id: "About", key: "about"[^\n]*$', text)
            if not match: raise ValueError('Guide tabs model anchor changed')
            block = '''        // BEGIN serpantinum-addons-v2 tabs
        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "AddonsTab.qml" },
        { id: "Monitors", key: "addon_monitors", name: "Monitors", icon: "󰍹", file: "AddonMonitorsTab.qml" },
        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml" },
        // END serpantinum-addons-v2 tabs
'''
            text = text[:match.start()] + block + text[match.start():]
        old = '                return I18n.t("guide.tabs." + (t.key || t.id).toLowerCase(), t.name || t.id);'
        new = '''                let key = "guide.tabs." + (t.key || t.id).toLowerCase();
                let label = I18n.t(key);
                return label === key ? (t.name || t.id) : label;'''
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text and 'return label && label !== key ? label : (t.name || t.id);' not in text:
            raise ValueError('Guide tab title fallback anchor changed')
        return text
    # Migrate our first revision while leaving every upstream tab intact.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs[\s,]*(?=    \])', '', text, flags=re.S)
    text = re.sub(r'\n                                // BEGIN serpantinum-addons-v2 sidebar.*?                                // END serpantinum-addons-v2 sidebar\n', '', text, flags=re.S)
    text = text.replace('tabAbout, tabAddonAddons, tabAddonMonitors, tabAddonKeybinds', 'tabAbout')
    anchor = '        { id: "About", key: "about", name: "About", icon: "󰋽", file: "AboutTab.qml", iconOffsetX: 0 }'
    text = text.replace(anchor + ',\n', anchor + '\n')
    if text.count(anchor) != 1: raise ValueError('Guide tabs anchor changed')
    block = '''        // BEGIN serpantinum-addons-v2 tabs
        { id: "Addons", key: "addons", name: "Addons", icon: "󰐱", file: "AddonsTab.qml", iconOffsetX: 0 },
        { id: "Monitors", key: "addon_monitors", name: "Monitors", icon: "󰍹", file: "AddonMonitorsTab.qml", iconOffsetX: 0 },
        { id: "Keybinds", key: "addon_keybinds", name: "Keybinds", icon: "󰌌", file: "AddonKeybindsTab.qml", iconOffsetX: 0 },
        // END serpantinum-addons-v2 tabs
'''
    # End marker sits before About now; remove it separately on later installs.
    text = re.sub(r'        // BEGIN serpantinum-addons-v2 tabs.*?        // END serpantinum-addons-v2 tabs\n', '', text, flags=re.S)
    text = text.replace(anchor, block + anchor, 1)
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
    old = 'text: I18n.t("guide.tabs." + (tabDelegate.modelData.key || tabDelegate.modelData.id).toLowerCase(), tabDelegate.modelData.name || tabDelegate.modelData.id)'
    new = 'text: popup.resolveTabTitle(tabDelegate.modelData.key || tabDelegate.modelData.id)'
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise ValueError('Guide sidebar title anchor changed')


def patch_idle_tab(text):
    marker = 'settingId: "idle_manual_system_awake"'
    if marker not in text:
        anchor = '            Rectangle {\n                Layout.fillWidth: true\n                implicitHeight: actionsBoxCol.implicitHeight + rootObj.s(24)'
        if text.count(anchor) != 1: raise ValueError('Do Not Disturb companion option anchor changed')
        option = '''            SettingsRow {
                rootObj: idleTabRoot.rootObj
                settingId: "idle_manual_system_awake"
                searchKeywords: "codex mode keep awake suspend lid closed download network ai workflow"
                visible: idleTabRoot.idleEnabled
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
        text = text.replace(anchor, option + anchor, 1)
    else:
        option_start = text.rfind('            SettingsRow {', 0, text.index(marker))
        option_end = text.find('            Rectangle {\n                Layout.fillWidth: true\n                implicitHeight: actionsBoxCol.implicitHeight + rootObj.s(24)', option_start)
        if option_start < 0 or option_end < 0: raise ValueError('Do Not Disturb companion option boundaries changed')
        option = text[option_start:option_end]
        option = option.replace('searchKeywords: "keep awake suspend lid closed download network"', 'searchKeywords: "codex mode keep awake suspend lid closed download network ai workflow"', 1)
        option = option.replace('title: "Keep system awake"', 'title: "Codex mode"', 1)
        option = option.replace('                icon: "󰒲"', '                icon: "󰖙"', 1)
        option = option.replace('radius: rootObj.s(4)', 'radius: ThemeBackend.borderRadius', 1)
        if 'id: addonBadgeText' not in option:
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
        text = text[:option_start] + option + text[option_end:]
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
    owner = 'popupWindowRoot' if '    id: popupWindowRoot\n' in text else 'window'
    anchor = f'    id: {owner}\n'
    if text.count(anchor) != 1: raise ValueError('Network root anchor changed')
    block = '''
    // BEGIN serpantinum-addons-v2 dns
    DnsControl {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: OWNER.s(18); anchors.topMargin: OWNER.s(16)
        width: OWNER.s(160); height: OWNER.s(32); z: 100
        visible: OWNER.activeMode === "wifi" || OWNER.activeMode === "eth"
        pollEnabled: window.visible && visible
    }
    // END serpantinum-addons-v2 dns
'''
    block = block.replace('OWNER', owner).replace('pollEnabled: window.visible', f'pollEnabled: {owner}.visible')
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
        return pattern.sub(replacement, text, count=1)
    if text.count(anchor) != 1: raise ValueError('Weather city label anchor changed')
    return text.replace(anchor, replacement, 1)


def patch_theme(text):
    import re
    text = re.sub(r'                        // BEGIN serpantinum-addons-v2 theme.*?                        // END serpantinum-addons-v2 theme\n', '', text, flags=re.S)
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


def patch_matugen(text):
    if '// BEGIN ' + MARK + ' generation' in text: return text
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
    anchor = '    ScreenshotOverlay {}\n'
    addition = '    // BEGIN serpantinum-addons-v2 color picker\n    AddonColorPicker {}\n    // END serpantinum-addons-v2 color picker\n'
    if addition not in text:
        if text.count(anchor) != 1: raise ValueError('Shell screenshot anchor changed')
        text = text.replace(anchor, anchor + addition, 1)
    spotlight = '    // BEGIN serpantinum-addons-v2 mouse spotlight\n    AddonMouseSpotlight {}\n    // END serpantinum-addons-v2 mouse spotlight\n'
    if spotlight not in text: text = text.replace(addition, addition + spotlight, 1)
    zoom = '    // BEGIN serpantinum-addons-v2 desktop zoom\n    AddonDesktopZoom {}\n    // END serpantinum-addons-v2 desktop zoom\n'
    if zoom not in text: text = text.replace(addition, addition + zoom, 1)
    draw = '    // BEGIN serpantinum-addons-v2 desktop draw\n    AddonDesktopDraw {}\n    // END serpantinum-addons-v2 desktop draw\n'
    if draw not in text: text = text.replace(addition, addition + draw, 1)
    awake = '    // BEGIN serpantinum-addons-v2 awake\n    AddonAwake {}\n    // END serpantinum-addons-v2 awake\n'
    if awake not in text: text = text.replace(addition, addition + awake, 1)
    return text


def patch_screenshot_overlay(text):
    # Recent upstream releases already preserve and crop the frozen screenshot.
    if 'function frozenSourceArgs()' in text and 'root.frozenSourceArgs()' in text:
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
    # Keep upstream's native --source/--crop path when it is available.
    if 'SOURCE_IMG=' in text and 'crop_source()' in text:
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
    if 'SOURCE_IMG=' in text and 'crop_source()' in text:
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
    if 'SOURCE_IMG=' in text and 'crop_source()' in text:
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


def patch_spotlight_keybind(text):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = '-- BEGIN serpantinum-addons-v2 mouse spotlight'
    if marker in text: return text
    if '"SUPER + SHIFT + M"' in text: raise ValueError('Mouse spotlight shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonMouseSpotlight toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 mouse spotlight\n'


def patch_zoom_keybind(text):
    marker = '-- BEGIN serpantinum-addons-v2 desktop zoom'
    if marker in text: return text
    if '"SUPER + SHIFT + Z"' in text: raise ValueError('Desktop zoom shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopZoom toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + Z", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 desktop zoom\n'


def patch_draw_keybind(text):
    marker = '-- BEGIN serpantinum-addons-v2 desktop draw'
    if marker in text: return text
    if '"SUPER + SHIFT + D"' in text: raise ValueError('Desktop drawing shortcut already in use')
    command = 'quickshell -p ' + shlex.quote(str(QS/'Shell.qml')) + ' ipc call addonDesktopDraw toggle'
    return text.rstrip() + '\n\n' + marker + '\n' + 'hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n-- END serpantinum-addons-v2 desktop draw\n'


def install(without_halloween=False):
    # Calculate all transformations first. Never partly apply an unknown upstream revision.
    patches = {QS/'Main.qml': patch_main, QS/'Shell.qml': patch_shell, QS/'screenshot/ScreenshotOverlay.qml': patch_screenshot_overlay, QS/'quickactions/Floating.qml': patch_floating, QS/'guide/GuidePopup.qml': patch_guide, QS/'guide/GuideSidebar.qml': patch_guide_sidebar, QS/'guide/IdleTab.qml': patch_idle_tab, QS/'guide/theme/ThemeTabState.qml': patch_theme, QS/'network/NetworkPopup.qml': patch_network, QS/'singletons/theme/Matugen.qml': patch_matugen, QS/'widgets/faces/weather/WeatherFaceFull.qml': patch_weather_face}
    pending = {path: transform(path.read_text()) for path, transform in patches.items()}
    screenshot_script = QS.parent/'scripts/screenshot.sh'
    pending[screenshot_script] = patch_screenshot_frozen_validation(patch_screenshot_cleanup(patch_screenshot_script(screenshot_script.read_text())))
    keybind_path = HOME/'.config/hypr/config/keybinds.lua'
    pending[keybind_path] = patch_draw_keybind(patch_zoom_keybind(patch_spotlight_keybind(patch_keybinds(keybind_path.read_text()))))
    for path, transform in seasonal.transformations(QS).items():
        if path not in pending and not path.is_file():
            continue
        text = pending[path] if path in pending else path.read_text()
        pending[path] = seasonal.remove(text) if without_halloween else transform(text)
    payloads = {'AddonAwake.qml': 'AddonAwake.qml', 'AddonDesktopDraw.qml': 'AddonDesktopDraw.qml', 'AddonDesktopZoom.qml': 'AddonDesktopZoom.qml', 'AddonMouseSpotlight.qml': 'AddonMouseSpotlight.qml', 'AddonColorPicker.qml': 'AddonColorPicker.qml', 'AddonPaletteEditor.qml': 'guide/theme/AddonPaletteEditor.qml', 'AddonsTab.qml': 'guide/AddonsTab.qml', 'AddonMonitorsTab.qml': 'guide/AddonMonitorsTab.qml', 'AddonKeybindsTab.qml': 'guide/AddonKeybindsTab.qml', 'DnsControl.qml': 'network/DnsControl.qml', 'LegacyCalendar.qml': 'calendar/LegacyCalendar.qml', 'CalendarPopup.qml': 'calendar/CalendarPopup.qml'}
    for source, target in payloads.items(): pending[QS/target] = (SOURCE/'payload'/source).read_text()
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
    for folder in ('guide', 'network'):
        directory = QS/folder/'qmldir'
        original = directory.read_text() if directory.exists() else ''
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
    for path, blob in resource_payloads:
        if without_halloween:
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
    shader_dir = QS/'seasonal/shaders'
    if shader_dir.exists():
        import re
        for path in shader_dir.iterdir():
            owned = path.name == 'atmosphere.frag.qsb' or re.fullmatch(r'atmosphere\.[a-f0-9]{12}\.frag\.qsb', path.name)
            if owned and (without_halloween or path.name != shader_name):
                saved = backup/path.relative_to(QS); saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved); path.unlink(); changed += 1
    shutil.copytree(SOURCE/'scripts', DEPLOY/'scripts', dirs_exist_ok=True)
    print(f'v2 installed: {changed} shell files changed; backups: {backup}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--without-halloween', action='store_true', help='Remove the seasonal layer while retaining other v2 addons')
    install(without_halloween=parser.parse_args().without_halloween)
