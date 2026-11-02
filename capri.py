"""Capri desktop pet hooks. Owns its mark so --without-halloween never strips it."""
import json
import re
import shlex

MARK = 'serpantinum-capri-v2'
TYPES = ['singleton Capri 1.0 capri/Capri.qml'] + [f'{name} 1.0 capri/{name}.qml' for name in
         ('AddonCapri', 'CapriOverlay', 'CapriWorld', 'CapriEngine', 'CapriPet', 'CapriSettings', 'CapriCard', 'CapriCardPreview', 'CapriSwitch', 'CapriBrain', 'CapriPanel', 'CapriTicker', 'CapriMenu', 'CapriPlate', 'CapriButton', 'CapriChat', 'CapriChatSettings', 'CapriVoice')]
CHORD = 'SUPER + SHIFT + K'
STOW_CHORD = 'CTRL + ALT + C'  # upstream's shortcut: put her away / bring her back


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text += '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # IpcHandler "capri" must be a direct ShellRoot child. Anchored away from
    # "    Main {}", which install.patch_shell re-flows on every run.
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Capri shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonCapri {{}}\n    // END {MARK} host\n' + anchor, 1)


def patch_keybind(text, shell_qml):
    text = _bind(text, 'keybind', CHORD, 'toggle', shell_qml)
    return _bind(text, 'stow', STOW_CHORD, "act stowToggle ''", shell_qml)


def _bind(text, name, chord, call, shell_qml):
    # Preserve user edits and deletions inside the managed block on reinstall.
    marker = f'-- BEGIN {MARK} {name}'
    if marker in text: return text
    if f'"{chord}"' in text: raise ValueError(f'Capri shortcut {chord} already in use')
    command = 'quickshell -p ' + shlex.quote(str(shell_qml)) + ' ipc call capri ' + call
    return text.rstrip() + '\n\n' + marker + '\n' + f'hl.bind("{chord}", hl.dsp.exec_cmd(' + json.dumps(command) + '))\n' + f'-- END {MARK} {name}\n'


def remove_blocks(text):
    text = re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)
    # one Lua block at a time: adjacent blocks would each leave a blank line behind
    lua = re.compile(r'\n*^-- BEGIN ' + MARK + r' ([^\n]+)\n.*?^-- END ' + MARK + r' \1\n', re.S | re.M)
    while lua.search(text):
        text = lua.sub('\n', text, count=1)
    return text


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 capri/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}
