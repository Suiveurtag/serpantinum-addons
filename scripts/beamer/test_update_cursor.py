import pytest
import update_cursor


def test_update_preserves_backup_and_is_idempotent(tmp_path, monkeypatch):
    old = b'old bridge'
    new = b'new bridge'
    monkeypatch.setattr(update_cursor, 'OLD', update_cursor.digest(old))
    monkeypatch.setattr(update_cursor, 'NEW', update_cursor.digest(new))
    target, source, socket = (tmp_path / name for name in ('input_bridge.py', 'new.py', 'input.sock'))
    target.write_bytes(old)
    source.write_bytes(new)
    update_cursor.update(target, source, socket)
    assert target.read_bytes() == new
    assert target.with_name(target.name + '.before-cursor-fix').read_bytes() == old
    assert 'déjà' in update_cursor.update(target, source, socket)


def test_update_refuses_modified_target_or_active_socket(tmp_path, monkeypatch):
    old, new = b'old', b'new'
    monkeypatch.setattr(update_cursor, 'OLD', update_cursor.digest(old))
    monkeypatch.setattr(update_cursor, 'NEW', update_cursor.digest(new))
    target, source, socket = (tmp_path / name for name in ('input_bridge.py', 'new.py', 'input.sock'))
    target.write_bytes(b'user change')
    source.write_bytes(new)
    with pytest.raises(RuntimeError, match='modifié'):
        update_cursor.update(target, source, socket)
    assert target.read_bytes() == b'user change'
    target.write_bytes(old)
    socket.touch()
    with pytest.raises(RuntimeError, match='Ferme'):
        update_cursor.update(target, source, socket)
    assert target.read_bytes() == old
