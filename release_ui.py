"""In-shell addons update / version / uninstall UI (Settings window).

Owns its own mark, distinct from install.py's 'serpantinum-addons-v2', so that
install.py's block stripping and this module's remove() never touch each other.
Every patch is fail-closed (anchor must occur exactly once), idempotent (marker
present -> unchanged) and wrapped in `// BEGIN <MARK> <name>` / `// END ...`.
"""
import re

MARK = 'serpantinum-addons-release-v2'

# repo-relative payload -> QS-relative destination.
# The singleton lives next to upstream's Updater.qml (singletons/system has no
# qmldir, so the name cannot also resolve as an implicit same-directory type).
PAYLOADS = {
    'payload/AddonsUpdater.qml': 'singletons/system/AddonsUpdater.qml',
    'payload/AddonsUpdateButton.qml': 'guide/AddonsUpdateButton.qml',
    'payload/AddonsReleaseCard.qml': 'guide/AddonsReleaseCard.qml',
}

QMLDIR = {
    'qmldir': ['singleton AddonsUpdater 1.0 singletons/system/AddonsUpdater.qml'],
    'guide/qmldir': ['AddonsUpdateButton 1.0 AddonsUpdateButton.qml', 'AddonsReleaseCard 1.0 AddonsReleaseCard.qml'],
}


def payloads():
    return dict(PAYLOADS)


def qmldir_entries():
    return {path: list(lines) for path, lines in QMLDIR.items()}


def _block(indent, name, body):
    lines = ''.join(indent + line + '\n' if line else '\n' for line in body)
    return f'{indent}// BEGIN {MARK} {name}\n{lines}{indent}// END {MARK} {name}\n'


def _insert(text, name, anchor, block, after, label):
    if f'// BEGIN {MARK} {name}\n' in text:
        return text
    if text.count(anchor) != 1:
        raise ValueError(f'{label} anchor changed')
    return text.replace(anchor, anchor + block if after else block + anchor, 1)


def patch_sidebar(text):
    anchor = '            onClicked: popup.gotoTab("about")\n        }\n'
    block = _block('        ', 'sidebar button', ['AddonsUpdateButton { popup: sidebar.popup }'])
    return _insert(text, 'sidebar button', anchor, block, True, 'Guide sidebar update button')


def patch_about(text):
    card_anchor = '            RowLayout {\n                Layout.fillWidth: true\n                spacing: rootObj.s(16)\n'
    card = _block('            ', 'about card', ['AddonsReleaseCard { rootObj: aboutTabRoot.rootObj; Layout.fillWidth: true }', ''])
    text = _insert(text, 'about card', card_anchor, card, False, 'About info rows')
    footer_anchor = '            RowLayout {\n                Layout.alignment: Qt.AlignHCenter\n                spacing: rootObj.s(12)\n'
    uninstall = _block('            ', 'about uninstall', [
        'RowLayout {',
        '    Layout.alignment: Qt.AlignHCenter',
        '    spacing: rootObj.s(12)',
        '',
        '    FillButton {',
        '        Layout.preferredWidth: rootObj.s(260)',
        '        Layout.preferredHeight: rootObj.s(42)',
        '        buttonText: "Uninstall addons"',
        '        buttonIcon: "󰆴"',
        '        accentColor: ThemeBackend.red',
        '        baseColor: ThemeBackend.surface0',
        '        hoverColor: Qt.alpha(ThemeBackend.red, 0.15)',
        '        textColor: ThemeBackend.red',
        '        filledTextColor: ThemeBackend.crust',
        '        cornerRadius: ThemeBackend.borderRadius',
        '        textFontSize: rootObj.s(12)',
        '        iconFontSize: rootObj.s(16)',
        '        fillDuration: 1500',
        '        onTriggered: {',
        '            if (AddonsUpdater.launch("--focus uninstall")) rootObj.dismissHost();',
        '        }',
        '    }',
        '}',
        '',
    ])
    return _insert(text, 'about uninstall', footer_anchor, uninstall, False, 'About GitHub footer')


def patch_popup(text):
    anchor = '        Updater.checkUpdate();\n'
    block = _block('        ', 'check', ['AddonsUpdater.check(false);'])
    return _insert(text, 'check', anchor, block, True, 'Guide popup update check')


def _qmldir_patch(path):
    def patch(text):
        if text and not text.endswith('\n'):
            text += '\n'
        present = set(text.splitlines())
        for line in QMLDIR[path]:
            if line not in present:
                text += line + '\n'
        return text
    return patch


def remove(text):
    text = re.sub(r'^[ ]*// BEGIN ' + re.escape(MARK) + r' ([^\n]+)\n.*?^[ ]*// END ' + re.escape(MARK) + r' \1\n',
                  '', text, flags=re.S | re.M)
    for lines in QMLDIR.values():
        for line in lines:
            text = re.sub(r'^' + re.escape(line) + r'\n', '', text, flags=re.M)
    return text


def transformations(qs):
    return {
        qs/'qmldir': _qmldir_patch('qmldir'),
        qs/'guide/qmldir': _qmldir_patch('guide/qmldir'),
        qs/'guide/GuideSidebar.qml': patch_sidebar,
        qs/'guide/AboutTab.qml': patch_about,
        qs/'guide/GuidePopup.qml': patch_popup,
    }
