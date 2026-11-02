import importlib.util
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('addon_install', ROOT / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def test_release_binding_is_idempotent_and_uninstalls():
    original = 'hl.bind("SUPER + A", hl.dsp.exec_cmd("app"))\n'
    patched = installer.patch_beamer_release_keybind(original)
    assert 'hl.dsp.release_input_capture()' in patched
    assert 'allow_input_capture = true' in patched
    assert 'submap_universal = true' in patched
    assert 'dont_inhibit = true' in patched
    assert installer.patch_beamer_release_keybind(patched) == patched
    assert installer.strip_keybind_blocks(patched).strip() == original.strip()


def test_uninstall_preserves_unrelated_dirty_content():
    original = '-- user edit before\nhl.bind("SUPER + A", custom)\n-- user edit after\n'
    patched = installer.patch_beamer_release_keybind(original)
    assert installer.strip_keybind_blocks(patched).strip() == original.strip()


@pytest.mark.parametrize('shortcut', ['SUPER + SHIFT + F12', 'shift+mod4+f12', 'SHIFT + SUPER + code:96'])
def test_release_binding_refuses_conflicts(shortcut):
    with pytest.raises(installer.InstallError, match='already in use'):
        installer.patch_beamer_release_keybind(f'hl.bind("{shortcut}", custom)')


def test_user_owned_managed_block_is_preserved():
    block = ('-- BEGIN serpantinum-addons-v2 beamer input release\n'
             'hl.bind("SUPER + F11", custom)\n'
             '-- END serpantinum-addons-v2 beamer input release\n')
    assert installer.patch_beamer_release_keybind(block) == block


def test_beamer_overlay_rule_is_targeted_reversible_and_idempotent():
    original = '-- user settings\nhl.bind("SUPER + A", custom)\n'
    patched = installer.patch_beamer_overlay_rule(original)
    assert 'class = "^(effect_overlay_x11|effect_overlay_helper)[.]py$"' in patched
    assert 'xwayland = true' in patched
    assert 'no_blur = true' in patched
    assert 'pin = true' in patched
    assert 'move = "0 0"' in patched
    assert installer.patch_beamer_overlay_rule(patched) == patched
    assert installer.strip_keybind_blocks(patched).strip() == original.strip()
