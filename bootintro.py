"""Boot intro: the opening animation played once per login (payload/bootintro, docs in README "Boot intro").

Always installed, like the update UI; Addons → General turns it off (`addonsV2BootIntro`). Own MARK, fail-closed
anchors, idempotent. The scene reuses the upstream welcome's shaders, logo and sounds (serp/Start.qml)."""
import re
from pathlib import Path

MARK = 'serpantinum-addons-boot-intro'
OPTION = 'addonsV2BootIntro'
TYPES = [f'{name} 1.0 bootintro/{name}.qml' for name in ('AddonBootIntro', 'BootIntroScreen')]
PAYLOAD = Path(__file__).resolve().parent/'payload/bootintro'


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    # The IpcHandler must be a direct ShellRoot child; same anchor as Clawd and Capri.
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Boot intro shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonBootIntro {{}}\n    // END {MARK} host\n' + anchor, 1)


def remove_blocks(text):
    return re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)


def remove(text):
    return re.sub(r'^\w+ 1\.0 bootintro/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}


def resources(qs, payload=PAYLOAD):
    return [(qs/'bootintro'/source.relative_to(payload), source.read_bytes()) for source in sorted(payload.rglob('*.qml'))]


def stale_shaders(qs, everything=False):
    # The first version shipped its own shaders; the intro now uses only the upstream ones, so every package goes.
    shaders = qs/'bootintro/shaders'
    return sorted(shaders.glob('*.frag.qsb')) if shaders.is_dir() else []
