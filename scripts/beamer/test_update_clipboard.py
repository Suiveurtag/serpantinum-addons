import pytest
import update_clipboard as updater


@pytest.fixture
def files(tmp_path, monkeypatch):
    dest, source, runtime = (tmp_path / n for n in ('dest', 'source', 'runtime'))
    for d in (dest, source, runtime):
        d.mkdir()
    (dest / 'launcher.py').write_bytes(b'old')
    (source / 'launcher.py').write_bytes(b'new')
    (source / 'clipboard_bridge.py').write_bytes(b'bridge')
    monkeypatch.setattr(updater, 'OLD_LAUNCHER', updater.digest(b'old'))
    monkeypatch.setattr(updater, 'NEW_LAUNCHER', updater.digest(b'new'))
    monkeypatch.setattr(updater, 'BRIDGE', updater.digest(b'bridge'))
    return dest, source, runtime


def test_updates_and_can_run_twice(files):
    dest, source, runtime = files
    updater.update(dest, source, runtime)
    assert (dest / 'launcher.py').read_bytes() == b'new'
    assert (dest / 'launcher.py.before-clipboard-bridge').read_bytes() == b'old'
    assert (dest / 'clipboard_bridge.py').read_bytes() == b'bridge'
    updater.update(dest, source, runtime)


def test_preserves_modified_or_active_installation(files):
    dest, source, runtime = files
    (dest / 'launcher.py').write_bytes(b'user change')
    with pytest.raises(RuntimeError, match='modifié'):
        updater.update(dest, source, runtime)
    assert (dest / 'launcher.py').read_bytes() == b'user change'
    assert not (dest / 'clipboard_bridge.py').exists()
    (dest / 'launcher.py').write_bytes(b'old')
    (runtime / 'beamer-addon').mkdir()
    (runtime / 'beamer-addon/input.sock').touch()
    with pytest.raises(RuntimeError, match='Ferme'):
        updater.update(dest, source, runtime)


def test_failed_replacement_cleans_new_bridge(files, monkeypatch):
    dest, source, runtime = files
    def fail(*args):
        raise OSError('simulated write failure')
    monkeypatch.setattr(updater, 'replace', fail)
    with pytest.raises(OSError):
        updater.update(dest, source, runtime)
    assert (dest / 'launcher.py').read_bytes() == b'old'
    assert not (dest / 'clipboard_bridge.py').exists()
