import importlib.util
from pathlib import Path
import sys

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('beamer_setup', HERE / 'setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


@pytest.fixture
def context(tmp_path, monkeypatch):
    for key in ('DATA', 'CACHE', 'STATE'):
        monkeypatch.setenv('XDG_' + key + '_HOME', str(tmp_path / key.lower()))
    monkeypatch.setattr(setup, 'check_dependencies', lambda: None)

    def build(cmd, check):
        assert check
        for name in setup.HELPERS:
            (Path(cmd[1]) / name).write_bytes(name.encode())

    monkeypatch.setattr(setup.subprocess, 'run', build)
    return tmp_path


def test_install_reinstall_and_uninstall(context):
    desktop = setup.install(HERE)
    content = desktop.read_bytes()
    assert b'Name=Beamer (Hyprland)' in content
    assert str(HERE / 'launcher.py').encode() in content
    assert setup.install(HERE).read_bytes() == content
    assert setup.uninstall() == []
    assert not desktop.exists()
    assert all(not (setup.paths()[2] / name).exists() for name in setup.HELPERS)
    assert not setup.paths()[1].exists()


def test_foreign_launcher_is_never_overwritten(context):
    desktop = setup.paths()[0]
    desktop.parent.mkdir(parents=True)
    desktop.write_text('user launcher')
    with pytest.raises(RuntimeError, match='unowned or modified launcher'):
        setup.install(HERE)
    assert desktop.read_text() == 'user launcher'


def test_uninstall_preserves_user_modified_files(context):
    desktop = setup.install(HERE)
    desktop.write_text('user customization')
    assert setup.uninstall() == [desktop]
    assert desktop.read_text() == 'user customization'
    assert setup.paths()[1].exists()


def test_adopts_identical_helpers_but_rejects_different_data(context):
    cache = setup.paths()[2]
    cache.mkdir(parents=True)
    for name in setup.HELPERS:
        (cache / name).write_bytes(name.encode())
    setup.install(HERE)
    setup.uninstall()
    cache.mkdir(parents=True, exist_ok=True)
    (cache / setup.HELPERS[0]).write_bytes(b'user content')
    with pytest.raises(RuntimeError, match='unowned helper'):
        setup.install(HERE)
    assert (cache / setup.HELPERS[0]).read_bytes() == b'user content'


def test_desktop_exec_quotes_path_and_field_codes(context):
    content = setup.desktop_content(Path('/tmp/with space/percent%/"quote"')).decode()
    assert '/tmp/with space/percent%%/\\"quote\\"/launcher.py' in content


def test_missing_dependencies_fail_before_writes(context, monkeypatch):
    def fail():
        raise RuntimeError('missing')
    monkeypatch.setattr(setup, 'check_dependencies', fail)
    with pytest.raises(RuntimeError, match='missing'):
        setup.install(HERE)
    assert not setup.paths()[0].exists()
    assert not setup.paths()[1].exists()


def test_dangling_state_symlink_is_not_replaced(context):
    state = setup.paths()[1]
    state.parent.mkdir(parents=True)
    state.symlink_to(state.parent / 'missing')
    with pytest.raises(RuntimeError, match='Refusing symbolic link'):
        setup.install(HERE)
    assert state.is_symlink()


def test_failed_menu_write_rolls_back_helpers(context, monkeypatch):
    desktop, state, cache = setup.paths()
    real_write = setup.atomic_write

    def fail_desktop(path, data, mode=0o644):
        if path == desktop:
            raise OSError('test write failure')
        return real_write(path, data, mode)

    monkeypatch.setattr(setup, 'atomic_write', fail_desktop)
    with pytest.raises(OSError, match='test write failure'):
        setup.install(HERE)
    assert not desktop.exists()
    assert not state.exists()
    assert all(not (cache / name).exists() for name in setup.HELPERS)
