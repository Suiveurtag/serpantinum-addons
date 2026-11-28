"""Export the solid, visible geometry of Serpantinum's layer surfaces."""

MARK = 'serpantinum-addons-v2 snow hush surface'


def insert(text, anchor, block, suffix=''):
    mark = MARK + suffix
    if f'// BEGIN {mark}\n' in text:
        return text
    if text.count(anchor) != 1:
        raise ValueError(f'Snow Hush surface anchor changed: {anchor.strip()}')
    indent = anchor[:len(anchor) - len(anchor.lstrip(' '))]
    body = '\n'.join(indent + line for line in block.strip('\n').splitlines())
    return text.replace(anchor, f'{anchor}{indent}// BEGIN {mark}\n{body}\n{indent}// END {mark}\n', 1)


def widget(text):
    return insert(text, '    WlrLayershell.namespace: "qs-widget-" + wType + "-" + wId\n', '''
SnowHushSurface {
    name: root.wId
    kind: "widgets"
    screen: root.screen
    shown: root.visible && faceLoader.status === Loader.Ready && root.wOpacity > 0.05
    readonly property real radians: faceLoader.rotation * Math.PI / 180
    readonly property real cosine: Math.abs(Math.cos(radians))
    readonly property real sine: Math.abs(Math.sin(radians))
    readonly property real faceWidth: Math.min(root.width - 2 * root.auraMargin, cosine * faceLoader.width + sine * faceLoader.height)
    readonly property real faceHeight: Math.min(root.height - 2 * root.auraMargin, sine * faceLoader.width + cosine * faceLoader.height)
    bounds: Qt.rect(root.animX + (root.width - 2 * root.auraMargin - faceWidth) / 2,
                    root.animY + (root.height - 2 * root.auraMargin - faceHeight) / 2,
                    faceWidth, faceHeight)
    radius: faceLoader.item && faceLoader.item.isRound ? Math.min(faceWidth, faceHeight) / 2 : ThemeBackend.borderRadius
}
''')


def dock(text):
    return insert(text, '    id: dockWindowRoot\n', '''
SnowHushSurface {
    name: "dock"
    kind: "dock"
    screen: dockWindowRoot.screen
    shown: dockWindowRoot.visible && dockContainerItem.revealProgress > 0.05
    bounds: Qt.rect(dockContainerItem.x + dockTransform.x, dockContainerItem.y + dockTransform.y,
                    dockContainerItem.width, dockContainerItem.height)
    radius: dockContainerItem.dynamicCornerRadius
}
''')


def panel(text):
    return insert(text, '    WlrLayershell.namespace: "qs-master"\n', '''
SnowHushSurface {
    name: masterWindow.currentActive
    kind: "panels"
    screen: masterWindow.screen
    shown: masterWindow.isVisible && masterWindow.currentActive !== "hidden"
    bounds: Qt.rect(masterWindow._animX, masterWindow._animY, masterWindow._animW, masterWindow._animH)
    radius: ThemeBackend.borderRadius
}
''')


def dashboard(text):
    return insert(text, '    WlrLayershell.namespace: "qs-dashboard"\n', '''
SnowHushSurface {
    name: "dashboard"
    kind: "panels"
    screen: dashboardWindow.screen
    shown: dashboardWindow.visible
    bounds: Qt.rect(panel.x, panel.y, panel.width, panel.height)
    radius: ThemeBackend.borderRadius
}
''')


def bar(text, vertical):
    shift = 'Qt.point(contentWrapper.shiftX || 0, 0)' if vertical else 'Qt.point(0, hideShift.y)'
    for item_id, surface_name, indent in (
        ('solidBackground', '"solid"', '        '),
        ('groupBgRect', 'groupBgRect.groupIds.join("|")', '            '),
    ):
        block = '''
SnowHushSurface {
    name: SURFACE_NAME
    kind: "bar"
    screen: barWindow ? barWindow.screen : null
    shown: barWindow && barWindow.visible && barWindow.isRevealed && SOURCE.visible && SOURCE.opacity > 0.05
    readonly property point shift: SHIFT
    bounds: barWindow && screen ? Qt.rect(
        SOURCE.x + shift.x + (barWindow.barPosition === "right" ? screen.width - barWindow.width - barWindow.margins.right : barWindow.margins.left),
        SOURCE.y + shift.y + (barWindow.barPosition === "bottom" ? screen.height - barWindow.height - barWindow.margins.bottom : barWindow.margins.top),
        SOURCE.width, SOURCE.height
    ) : Qt.rect(0, 0, 0, 0)
    radius: Math.max(SOURCE.radius, SOURCE.topLeftRadius || 0, SOURCE.topRightRadius || 0)
}
'''.replace('SURFACE_NAME', surface_name).replace('SOURCE', item_id).replace('SHIFT', shift)
        text = insert(text, f'{indent}id: {item_id}\n', block, ' ' + item_id)
    return text


def transformations(qs):
    return {
        qs/'widgets/Widget.qml': widget,
        qs/'dock/DockWindow.qml': dock,
        qs/'Main.qml': panel,
        qs/'calendar/Dashboard.qml': dashboard,
        qs/'bar/TopBar.qml': lambda text: bar(text, False),
        qs/'bar/SideBar.qml': lambda text: bar(text, True),
    }
