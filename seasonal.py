"""Presentation-only seasonal hooks. All patches fail closed on unknown anchors."""
import re

MARK = 'serpantinum-night-v2'


def insert(text, anchor, block):
    marker = re.escape(f'{MARK} {block[0]}')
    text = re.sub(r'\n    // BEGIN ' + marker + r'\n.*?    // END ' + marker + r'\n', '', text, flags=re.S)
    if text.count(anchor) != 1:
        raise ValueError(f'Seasonal anchor changed: {block[0]}')
    indent = len(anchor) - len(anchor.lstrip())
    lines = block[1].strip('\n').splitlines()
    body_indent = len(lines[0]) - len(lines[0].lstrip())
    body = '\n'.join(' ' * max(0, indent + len(line) - len(line.lstrip()) - body_indent) + line.lstrip() if line.strip() else '' for line in lines)
    return text.replace(anchor, anchor + f'\n    // BEGIN {MARK} {block[0]}\n' + body + f'\n    // END {MARK} {block[0]}\n', 1)


def patch_palette(text):
    text = text.replace('Halloween.enabled', 'Halloween.activeSeason').replace('Halloween.palette', 'Halloween.colors')
    if f'// BEGIN {MARK} palette' in text:
        return re.sub(r'    property color (\w+): Halloween.activeSeason \? Halloween.colors\.\1 : _normal\1\n    Behavior on \1 \{[^\n]*\}\n',
            lambda m: f'    property color {m[1]}: Halloween.presentColor("{m[1]}", _normal{m[1]})\n', text)
    # Keep the normal writable palette separate from its seasonal presentation.
    # Theme changes while ON still update the normal values, so OFF is exact.
    pattern = r'    property color (\w+): ("#[0-9a-fA-F]+")'
    colors = re.findall(pattern, text)
    modern_slots = text.count('root[slot]') == 1 and text.count('root[item.name]') == 1
    legacy_slots = text.count('root[propName]') == 2
    if len(colors) != 22 or not (modern_slots or legacy_slots):
        raise ValueError('ThemeBackend palette storage changed')
    text = re.sub(pattern, lambda m: (
        f'    property color _normal{m[1]}: {m[2]}\n'
        f'    property color {m[1]}: Halloween.presentColor("{m[1]}", _normal{m[1]})'
    ), text)
    if modern_slots:
        text = text.replace('root[slot]', 'root["_normal" + (slot.startsWith("_") ? slot.slice(1) : slot)]')
        text = text.replace('root[item.name]', 'root["_normal" + (item.name.startsWith("_") ? item.name.slice(1) : item.name)]')
    else:
        text = text.replace('root[propName]', 'root["_normal" + propName]')
    return text.replace('    id: root\n', f'    id: root\n    // BEGIN {MARK} palette\n    // Normal preset values are never overwritten by the seasonal palette.\n    // END {MARK} palette\n', 1)


def patch_main(text):
    text = insert(text, '            id: contentStage\n', ('panels', '''            Loader {
                enabled: false
                anchors.fill: parent
                z: 4
                active: Halloween.activeSeason && masterWindow.isVisible && masterWindow.currentActive !== "hidden"
                sourceComponent: NightPanel {
                    scene: masterWindow.currentActive
                    cornerRadius: ThemeBackend.borderRadius
                }
            }
'''))
    return insert(text, '    id: masterWindow\n', ('flourish', '''    // Outside panel clipping; follows the actual layout and its opening frontier.
    Loader {
        id: seasonalFlight; enabled: false; anchors.fill: parent; z: 10
        active: Halloween.animationEnabled && masterWindow.isVisible && masterWindow.currentActive !== "hidden"
        sourceComponent: PanelArrival {
            panelRect: Qt.rect(masterWindow._animX, masterWindow._animY, masterWindow._animW, masterWindow._animH)
            scene: masterWindow.currentActive
            serial: masterWindow.switchGeneration
            edge: {
                if (scene === "guide" || scene === "wallpaper") return "center";
                if (scene === "system") return masterWindow.barPosition === "right" ? "left" : "right";
                if (scene === "notifications") return "left";
                if (scene === "calendar" && (masterWindow.barPosition === "left" || masterWindow.barPosition === "right")) return "top";
                return masterWindow.barPosition;
            }
        }
    }
'''))


def patch_settings_row(text):
    return insert(text, '    id: root\n', ('row mist', '''    property HoverHandler seasonalHover: HoverHandler {
        parent: root
        enabled: Halloween.activeSeason && root.isOwnTabLive()
    }
    // Explicit parent/property: SettingsRow's default children are controls.
    property Item seasonalMist: EdgeMist {
        parent: root
        anchors.fill: parent
        visible: root.isOwnTabLive()
        engaged: root.enabled && !root.dimmed && (root.seasonalHover.hovered || root.highlightFlash > 0.1)
        cornerRadius: root.cornerRadius
    }
'''))


def patch_calendar(text):
    text = text.replace('Halloween.enabled', 'Halloween.activeSeason')
    text = text.replace('                    visible: !Halloween.activeSeason\n', '')
    anchor = '                    id: orbitCanvas\n'
    if text.count(anchor) != 1:
        raise ValueError('Clock orbit anchor changed')
    text = text.replace(anchor, anchor + '                    visible: !Halloween.activeSeason\n', 1)
    return insert(text, '                id: centralHub\n', ('dial', '''                Loader {
                    enabled: false
                    anchors.centerIn: parent
                    width: orbitCanvas.width; height: orbitCanvas.height
                    z: -9
                    active: Halloween.activeSeason && window.visible
                    sourceComponent: CelestialDial { perchedBats: true }
                }
'''))


def patch_launcher(text):
    return insert(text, '            id: bgCard\n', ('launcher hearth', '''            Loader {
                enabled: false
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: container.dynamicCornerRadius
                anchors.rightMargin: container.dynamicCornerRadius
                height: Math.min(parent.height * 0.20, parent.width * 0.15)
                active: Halloween.activeSeason && launcherWindow.isVisible
                sourceComponent: HearthGlow { intensity: 0.22; engaged: true }
            }
'''))


def patch_fill_button(text):
    # A deliberate activation (hold-to-confirm) gets the rare flourish.
    return insert(text, '    id: root\n', ('button flight', '''    property Item seasonalFlight: Loader {
        enabled: false
        parent: root
        x: -root.width * 0.75; y: -root.height * 3
        width: root.width * 2.5; height: root.height * 5
        z: 20
        property bool requested: false
        active: Halloween.activeSeason && root.visible && requested
        onActiveChanged: if (!active) requested = false
        sourceComponent: BatBurst {
            originY: height * 0.7
            onFinished: root.seasonalFlight.requested = false
        }
        onLoaded: item.play()
    }
    Connections {
        target: root
        function onTriggered() {
            if (Halloween.animationEnabled && Date.now() - Halloween.lastBurst >= Halloween.burstCooldown)
                root.seasonalFlight.requested = true;
        }
    }
'''))


def patch_qmldir(text):
    types = {'Halloween': 'singleton Halloween 1.0 seasonal/Halloween.qml',
             **{name: f'{name} 1.0 seasonal/{name}.qml' for name in
                ('FogLayer', 'EdgeMist', 'HearthGlow', 'ResponsiveCobweb', 'NightPanel', 'CelestialDial', 'BatBurst', 'NightSwitch', 'ControlEffects', 'MusicAura', 'WidgetAura', 'NetworkWeave', 'GlassReflection', 'BatSilhouette', 'DistantBats', 'ArcStrike', 'HoldEnergy', 'OsdSouls', 'LauncherStorm', 'LockVeil', 'HalloweenCard', 'OpeningFlight', 'PanelArrival', 'CandleLight', 'CandleVigil', 'BarCharms', 'IntroScene', 'NightIntro')}}
    for declaration in types.values():
        if declaration not in text:
            text += '\n' + declaration + '\n'
    return text


def patch_control(text):
    return insert(text, '    id: root\n', ('control energy', '''    property Item seasonalControls: ControlEffects {
        parent: root
        anchors.fill: parent
        z: 8
        cornerRadius: root.cornerRadius
        engaged: root.enabled && root.isHoveredOrHighlighted
        major: root.buttonIcon === "󰐊" || root.buttonIcon === "󰏤"
    }
    Connections {
        target: root
        function onClicked() { root.seasonalControls.activate(); }
    }
'''))


def patch_network(text):
    if '                id: orbitContainer\n' in text:
        text = insert(text, '                id: orbitContainer\n', ('network weave', '''                Loader {
                    enabled: false
                    anchors.fill: parent
                    active: Halloween.activeSeason && window.visible && window.currentPower
                    sourceComponent: NetworkWeave {
                        cores: coreRepeater; nodes: orbitRepeater
                        connected: window.currentConn; transport: window.activeMode
                    }
                }
'''))
    else:
        # Newer Serpantinum builds split the core and card repeaters into
        # NetworkCoreLayer and NetworkCardLayer. Keep the seasonal layer in
        # their shared parent so it can map both sets of item coordinates.
        text = insert(text, '            NetworkCoreLayer {\n', ('network weave', '''            Loader {
                anchors.fill: parent
                active: Halloween.activeSeason && window.visible && window.currentPower
                sourceComponent: NetworkWeave {
                    cores: coreLayer.repeater; nodes: cardLayer.repeater
                    connected: window.currentConn; transport: window.activeMode
                }
            }
'''))
    # Keep the original graph lightning for OFF; replace its active rendering
    # and repaint timer with vector conduits for the seasonal presentation.
    text = text.replace('visible: window.visible && opacity > 0.01\n                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 400 } }',
                        'visible: window.visible && opacity > 0.01 && !Halloween.activeSeason\n                Behavior on opacity { enabled: window.visible; NumberAnimation { duration: 400 } }', 1)
    text = text.replace('running: window.visible && nodeLinesCanvas.opacity > 0.01 && window.currentPower\n',
                        'running: window.visible && nodeLinesCanvas.opacity > 0.01 && window.currentPower && !Halloween.activeSeason\n', 1)
    return text


def patch_music(text):
    if '                        id: coverHost\n' not in text:
        # Recent upstream releases moved the cover into MusicCover.qml. Keep
        # the remaining popup effect here; the cover-specific layers belong
        # to the extracted component and must not be injected into its parent.
        return insert(text, '            id: innerBg\n', ('music vapor', '''            Loader {
                enabled: false
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.88; height: parent.height * 0.18
                active: Halloween.activeSeason && root.active
                sourceComponent: HearthGlow {
                    intensity: 0.36 + root.bassLevel * 0.25
                    engaged: !!(root.targetPlayer && root.targetPlayer.isPlaying)
                }
            }
'''))
    text = insert(text, '                        id: coverHost\n', ('album reflection', '''                        Loader {
                            id: seasonalReflection
                            enabled: false
                            anchors.centerIn: parent
                            width: coverHost.artRadius * 2; height: width
                            z: 7
                            active: Halloween.activeSeason && root.active
                            sourceComponent: GlassReflection {}
                        }
                        Connections {
                            target: root
                            function onActiveArtUrlChanged() {
                                if (seasonalReflection.item) seasonalReflection.item.sweep();
                            }
                        }
'''))
    text = insert(text, '                        id: coverHost\n', ('album corona', '''                        Loader {
                            enabled: false
                            anchors.fill: parent; z: 8
                            active: Halloween.activeSeason && root.active
                            sourceComponent: MusicAura {
                                playing: !!(root.targetPlayer && root.targetPlayer.isPlaying)
                                energy: root.bassLevel
                            }
                        }
'''))
    return insert(text, '            id: innerBg\n', ('music vapor', '''            Loader {
                enabled: false
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.88; height: parent.height * 0.18
                active: Halloween.activeSeason && root.active
                sourceComponent: HearthGlow {
                    intensity: 0.36 + root.bassLevel * 0.25
                    engaged: !!(root.targetPlayer && root.targetPlayer.isPlaying)
                }
            }
'''))


def patch_system(text):
    if '                            id: actionCapsule\n' in text:
        text = insert(text, '                            id: actionCapsule\n', ('power control', '''                            property Item seasonalEnergy: ControlEffects {
                                parent: actionCapsule
                                anchors.fill: parent; z: 6
                                cornerRadius: actionCapsule.radius
                                engaged: root.visible && !actionCapsule.isDisabled && actionMa.containsMouse
                                charge: actionCapsule.fillLevel
                            }
'''))
    return insert(text, '                        id: profileSwitchWrapper\n', ('profile current', '''                        Loader {
                            enabled: false
                            anchors.fill: parent; z: 6
                            active: Halloween.activeSeason && root.visible
                            sourceComponent: FogLayer {
                                mode: 4
                                intensity: root.powerProfile === "performance" ? 0.9 : 0.60
                                energy: root.powerProfile === "performance" ? 1 : (root.powerProfile === "balanced" ? 0.5 : 0.1)
                                warmth: root.powerProfile === "power-saver" ? 0.25 : 0.8
                                cornerRadius: profileSwitch.cornerRadius
                                Behavior on energy { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                Behavior on warmth { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
'''))


def patch_power_actions(text):
    return insert(text, '            id: actionCapsule\n', ('power control', '''            property Item seasonalEnergy: ControlEffects {
                parent: actionCapsule
                anchors.fill: parent; z: 6
                cornerRadius: actionCapsule.radius
                engaged: panel.visible && !actionCapsule.isDisabled && actionMa.containsMouse
                charge: actionCapsule.fillLevel
            }
'''))


def patch_widgets(text):
    if 'import Quickshell.Hyprland\n' not in text:
        text = text.replace('import Quickshell.Wayland\n', 'import Quickshell.Wayland\nimport Quickshell.Hyprland\n', 1)
    text = insert(text, '    id: root\n', ('widget atmosphere', '''    readonly property var seasonalMonitor: Halloween.activeSeason && root.screen
        ? Hyprland.monitors.values.find(m => m.name === root.screen.name) : null
    readonly property var seasonalWorkspace: seasonalMonitor ? seasonalMonitor.activeWorkspace : null
    readonly property bool seasonalDesktopClear: seasonalWorkspace && seasonalWorkspace.toplevels.values.length === 0
'''))
    return insert(text, '        id: faceLoader\n', ('widget effect', '''        HoverHandler {
            id: seasonalWidgetHover
            enabled: Halloween.activeSeason && root.visible
        }
        Loader {
            enabled: false
            anchors.fill: parent; z: 9
            active: Halloween.activeSeason && root.visible &&
                (root.seasonalDesktopClear || seasonalWidgetHover.hovered || root.isRedacting)
            sourceComponent: WidgetAura {
                kind: root.wType; engaged: seasonalWidgetHover.hovered
                roundShape: faceLoader.item ? !!faceLoader.item.isRound : false
            }
        }
'''))


def remove(text):
    """Remove our presentation hooks, retaining normal palette values and addons."""
    text = re.sub(r'\n    // BEGIN serpantinum-night-v2 [^\n]*\n.*?    // END serpantinum-night-v2 [^\n]*\n', '', text, flags=re.S)
    text = re.sub(
        r'    property color _normal(\w+): ("#[0-9a-fA-F]+")\n'
        r'    property color \1: [^\n]*\n(?:    Behavior on \1 \{[^\n]*\}\n)?',
        lambda m: f'    property color {m[1]}: {m[2]}\n', text)
    text = text.replace('root["_normal" + propName]', 'root[propName]')
    text = text.replace('                    visible: !Halloween.activeSeason\n', '')
    text = text.replace('visible: window.visible && opacity > 0.01 && !Halloween.activeSeason',
                        'visible: window.visible && opacity > 0.01')
    text = text.replace('running: window.visible && nodeLinesCanvas.opacity > 0.01 && window.currentPower && !Halloween.activeSeason',
                        'running: window.visible && nodeLinesCanvas.opacity > 0.01 && window.currentPower')
    text = text.replace('active: !!modelData.previewArtwork || (modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== "")',
                        'active: modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== ""')
    original = 'themeTabRoot.isWallpaperVideo ? ("file://" + Caching.getCacheDir("wallpaper") + "/current_wallpaper.png?rev=" + themeTabRoot.wallpaperRevision) : ("file://" + themeTabRoot.currentWallpaperPath)'
    text = text.replace('source: modelData.previewArtwork ? modelData.previewArtwork : (' + original + ')', 'source: ' + original)
    text = text.replace('Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(modelData.previewArtwork ? 124 : 44)',
                        'Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(44)')
    text = re.sub(r'^(?:singleton )?\w+ 1\.0 seasonal/\w+\.qml\n', '', text, flags=re.M)
    # Only the master option is owned by this layer; other addon rows remain.
    text = re.sub(r'            // BEGIN serpantinum-night-v2 option\n.*?            // END serpantinum-night-v2 option\n', '', text, flags=re.S)
    return text


def transformations(qs):
    result = {qs/'Main.qml': patch_main, qs/'qmldir': patch_qmldir,
            qs/'singletons/theme/ThemeBackend.qml': patch_palette,
            qs/'reusables/guide/SettingsRow.qml': patch_settings_row,
            qs/'reusables/buttons/FillButton.qml': patch_fill_button,
            qs/'launcher/Launcher.qml': patch_launcher,
            qs/'network/NetworkPopup.qml': patch_network,
            qs/'syspanel/SystemPanelPowerActions.qml': patch_power_actions,
            qs/'media/MusicPopup.qml': patch_music,
            qs/'syspanel/SystemPanel.qml': patch_system,
            qs/'widgets/Widget.qml': patch_widgets,
            qs/'reusables/buttons/IconButton.qml': patch_control,
            qs/'reusables/buttons/ClickButton.qml': patch_control}
    from seasonal_surfaces import extensions
    def compose(base, extension):
        return lambda text: extension(base(text))
    for path, extension in extensions(qs).items():
        if path.name == 'NativeCalendar.qml': continue  # Prepared from native source by installer.
        result[path] = compose(result[path], extension) if path in result else extension
    return result
