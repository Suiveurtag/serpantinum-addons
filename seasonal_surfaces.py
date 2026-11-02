"""Seasonal surface hooks; compose with the core hooks rather than duplicate UI."""
import re
from seasonal import insert, MARK


def shadows(text, anchor, name, active, parent=''):
    return insert(text, anchor, (name, f'''{' ' * 8}Loader {{
            enabled: false
            {('parent: ' + parent + ';') if parent else ''}
            anchors.fill: parent; z: {'1' if parent else '0'}
            active: Halloween.animationEnabled && ({active})
            sourceComponent: DistantBats {{}}
        }}
'''))


def calendar(text):
    return shadows(text, '                id: centralHub\n', 'calendar shadows', 'window.visible', 'centralHub.parent')


def guide(text):
    return insert(text, '                id: sidebar\n', ('settings shadows', '''                Loader {
                    parent: sidebar.parent; anchors.fill: parent
                    anchors.leftMargin: sidebar.width
                    z: 0; enabled: false
                    active: Halloween.animationEnabled && root.visible
                    sourceComponent: DistantBats {}
                }
'''))


def music(text):
    return insert(text, '                id: bgEffectsLayer\n', ('music shadows', '''                Loader {
                    anchors.fill: parent; z: 2; enabled: false
                    active: Halloween.animationEnabled && root.active
                    sourceComponent: DistantBats {}
                }
'''))


def network(text):
    legacy_anchor = '                id: orbitContainer\n'
    if legacy_anchor in text:
        return shadows(text, legacy_anchor, 'network shadows', 'window.visible')
    return insert(text, '            NetworkCoreLayer {\n', ('network shadows', '''            Loader {
                enabled: false
                anchors.fill: parent; z: 0
                active: Halloween.animationEnabled && window.visible
                sourceComponent: DistantBats {}
            }
'''))


def network_core(text):
    return insert(text, '                id: centralCore\n', ('network hold', '''                property Item seasonalCharge: HoldEnergy {
                    parent: centralCore; anchors.fill: parent; z: 6
                    held: coreMa.pressed && window.currentConn && !showPassword
                    charge: centralCore.disconnectFill
                }
'''))


def fill(text):
    return insert(text, '    id: root\n', ('hold discharge', '''    property Item seasonalHold: HoldEnergy {
        parent: root; anchors.fill: parent; z: 9
        held: btnMa.pressed && root.enabled
        charge: root.fillLevel
    }
'''))


def system(text):
    return insert(text, '        id: sidebarPanel\n', ('system light', '''        Loader {
            anchors.fill: parent; z: 2; enabled: false
            active: Halloween.activeSeason && root.visible
            sourceComponent: LockVeil { authenticating: root.isDraggingVol || root.isDraggingBri }
        }
'''))


def system_power_actions(text):
    return insert(text, '            id: actionCapsule\n', ('power charge', '''            property Item seasonalCharge: HoldEnergy {
                parent: actionCapsule; anchors.fill: parent; z: 7
                held: actionMa.pressed && !actionCapsule.isDisabled
                charge: actionCapsule.fillLevel
                            }
'''))


def launcher(text):
    # A window-sized layer lets bats leave the growing frontier without being clipped.
    return insert(text, '    id: launcherWindow\n', ('launcher storm', '''    Loader {
        id: seasonalStorm
        enabled: false; anchors.fill: parent; z: 200
        active: Halloween.animationEnabled && launcherWindow.isVisible
        sourceComponent: LauncherStorm {
            resultCount: appModel.count; query: searchInput.text
            edge: launcherWindow.attachEdge
            panelRect: Qt.rect(container.x, container.y, container.width, container.height)
        }
    }
'''))


def osd(text):
    return insert(text, '    id: osdWindow\n', ('osd souls', '''    Loader {
        id: seasonalSouls; anchors.fill: parent; z: 200; enabled: false
        active: Halloween.animationEnabled && osdWindow.isVisible
        sourceComponent: OsdSouls {
            originRect: Qt.rect(osdContainer.x, osdContainer.y, osdContainer.width, osdContainer.height)
            vertical: osdWindow.isVerticalLayout
        }
        onLoaded: Qt.callLater(function() { if (seasonalSouls.item) seasonalSouls.item.release(); })
    }
    Connections {
        target: osdWindow
        function onCurrentValChanged() { if (osdWindow.isVisible && seasonalSouls.item) seasonalSouls.item.release(); }
        function onIsVisibleChanged() { if (osdWindow.isVisible && seasonalSouls.item) seasonalSouls.item.release(); }
    }
'''))


def lock(text):
    password_anchor = '                                                id: passwordInput\n'
    dashboard_anchor = '                                id: mainDashboardShell\n'
    if password_anchor in text:
        text = insert(text, password_anchor, ('lock input light', '''                                                property Item seasonalFocusLight: ControlEffects {
                                                    parent: passwordInput; anchors.fill: parent; z: 3
                                                    engaged: passwordInput.activeFocus && rootLock.locked
                                                    cornerRadius: ThemeBackend.borderRadius
                                                    charge: lockUI.authenticating ? 1 : 0
                                                }
'''))
    if dashboard_anchor not in text:
        return text
    return insert(text, dashboard_anchor, ('lock veil', '''                                Loader {
                                    anchors.fill: parent; z: 5; enabled: false
                                    active: Halloween.activeSeason && rootLock.locked && mainDashboardShell.visible && !screenRoot.isUnlocking
                                    sourceComponent: LockVeil { authenticating: lockUI.authenticating; failed: lockUI.failed }
                                }
'''))


def volume(text):
    text = insert(text, '                            id: centralCore\n', ('sound aura', '''                            Loader {
                                anchors.fill: parent; z: 2; enabled: false
                                active: Halloween.activeSeason && window.visible
                                sourceComponent: FogLayer {
                                    mode: 6; intensity: window.activeMute ? 0.15 : 0.46
                                    energy: Math.min(1,window.activeVol/100)
                                    cornerRadius: ThemeBackend.borderRadius
                                    warmth: window.activeTab === "inputs" ? 0.2 : 0.75
                                    Behavior on energy { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                }
                            }
'''))
    return insert(text, '                            id: delegateRoot\n', ('sound mist', '''                            property Item seasonalMist: EdgeMist {
                                parent: delegateRoot; anchors.fill: parent; z: 1
                                engaged: delegateRoot.isHovered
                                direction: window.activeTab === "inputs" ? -1 : 1
                                cornerRadius: delegateRoot.radius
                            }
'''))


def theme(text):
    if '    property var systemPresets: []\n' not in text:
        return text
    text = insert(text, '    property var systemPresets: []\n', ('theme data', '''    readonly property var seasonalPresets: [{
        name: "Halloween Night", category: "seasonal", colors: Halloween.colors,
        previewArtwork: Halloween.artwork
    }]
    readonly property var filteredSeasonalPresets: seasonalPresets.filter(p => !themeSearchText.trim() || p.name.toLowerCase().indexOf(themeSearchText.trim().toLowerCase()) !== -1)
'''))
    anchor = '                    GridLayout {\n                        id: themesGrid'
    marker = f'{MARK} theme category'
    text = re.sub(r'\n    // BEGIN ' + re.escape(marker) + r'\n.*?    // END ' + re.escape(marker) + r'\n', '', text, flags=re.S)
    if anchor not in text:
        return text
    if text.count(anchor) != 1: raise ValueError('Theme grid anchor changed')
    body = '''                    Text {
                        visible: themeTabRoot.filteredSeasonalPresets.length > 0
                        Layout.leftMargin: rootObj.s(14); Layout.topMargin: rootObj.s(14)
                        text: "Seasonal · Halloween"
                        font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext1
                    }
                    GridLayout {
                        visible: themeTabRoot.filteredSeasonalPresets.length > 0
                        Layout.fillWidth: true
                        Layout.maximumWidth: themeTabRoot.tileWidth
                        Layout.leftMargin: rootObj.s(12); Layout.rightMargin: rootObj.s(12)
                        Layout.topMargin: rootObj.s(10); Layout.bottomMargin: rootObj.s(8)
                        columns: 3
                        Repeater { model: themeTabRoot.filteredSeasonalPresets; delegate: presetDelegateComp }
                    }
'''
    text = text.replace(anchor, f'\n    // BEGIN {marker}\n' + body + f'    // END {marker}\n' + anchor, 1)
    text = text.replace('active: modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== ""',
                        'active: !!modelData.previewArtwork || (modelData.isMatugen === true && themeTabRoot.currentWallpaperPath !== "")')
    original = 'themeTabRoot.isWallpaperVideo ? ("file://" + Caching.getCacheDir("wallpaper") + "/current_wallpaper.png?rev=" + themeTabRoot.wallpaperRevision) : ("file://" + themeTabRoot.currentWallpaperPath)'
    if 'source: modelData.previewArtwork ?' not in text:
        text = text.replace('source: ' + original, 'source: modelData.previewArtwork ? modelData.previewArtwork : (' + original + ')', 1)
    text = text.replace('Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(modelData.previewArtwork ? 124 : 44)',
                        'Layout.preferredHeight: isDiv ? rootObj.s(17) : rootObj.s(44)')
    text = insert(text, '                            id: matugenWall\n', ('theme artwork crop', '''                            verticalAlignment: modelData.previewArtwork ? Image.AlignTop : Image.AlignVCenter
'''))
    if 'if (typeof themesGrid.forceLayout' not in text:
        text = text.replace('themesGrid.forceLayout();', 'if (typeof themesGrid.forceLayout === "function") themesGrid.forceLayout();')
    return text


def extensions(qs):
    return {qs/'guide/GuidePopup.qml':guide, qs/'calendar/NativeCalendar.qml':calendar,
            qs/'media/MusicPopup.qml':music, qs/'network/NetworkPopup.qml':network,
            qs/'network/NetworkCoreLayer.qml':network_core,
            qs/'reusables/buttons/FillButton.qml':fill, qs/'syspanel/SystemPanel.qml':system,
            qs/'syspanel/SystemPanelPowerActions.qml':system_power_actions,
            qs/'launcher/Launcher.qml':launcher, qs/'popouts/Osd.qml':osd,
            qs/'lock/Lock.qml':lock, qs/'volume/VolumePopup.qml':volume,
            qs/'guide/theme/ThemeTab.qml':theme, qs/'bar/BarModule.qml':bar_module,
            qs/'bar/BarSideModule.qml':lambda text: bar_module(text, True),
            qs/'notifications/Notification.qml':notification, qs/'Shell.qml':shell}


def bar_module(text, vertical=False):
    return insert(text, '    id: root\n', ('bar charms', '''    Loader {
        enabled: false; anchors.fill: parent; z: 8
        active: Halloween.animationEnabled && root.effectiveVisible && root.visible
            && (!root.barWindow || root.barWindow.isRevealed)
        sourceComponent: BarCharms {
            moduleId: root.moduleId
            vertical: VERTICAL
            edge: root.barWindow ? root.barWindow.barPosition : "top"
            cornerRadius: root.radius
        }
    }
'''.replace('VERTICAL', 'true' if vertical else 'false')))


def notification(text):
    return insert(text, '            id: bgContainer\n', ('notification candles', '''            Loader {
                enabled: false; anchors.fill: parent
                active: Halloween.animationEnabled && typeRoot.visible
                sourceComponent: CandleVigil { cornerRadius: visualItem.radius; urgent: typeRoot.model && typeRoot.model.urgency === 2 }
            }
'''))


def shell(text):
    return insert(text, '    ScreenshotOverlay {}\n', ('night intro', '''    Loader {
        active: Halloween.animationEnabled && Halloween.introRunning
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: NightIntro { required property var modelData; screen: modelData }
        }
    }
'''))
