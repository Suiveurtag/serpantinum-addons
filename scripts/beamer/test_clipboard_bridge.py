import socket
import socketserver
import threading
from types import SimpleNamespace

import pytest
import clipboard_bridge as bridge


@pytest.fixture
def rpc(tmp_path, monkeypatch):
    monkeypatch.setenv('XDG_RUNTIME_DIR', str(tmp_path))
    (tmp_path / 'beamer-addon').mkdir(mode=0o700)
    state = {'contents': ('avant', b'PNG'), 'stamp': 1}

    def set_contents(text, image):
        state['contents'] = (text, image)
        state['stamp'] += 1
        return True

    backend = SimpleNamespace(read_contents=lambda: state['contents'],
                              change_stamp=lambda: state['stamp'], set_contents=set_contents)
    monkeypatch.setitem(__import__('sys').modules, 'hyprland_clipboard', backend)
    server = socketserver.ThreadingUnixStreamServer(str(bridge.socket_path()), bridge.Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield state
    server.shutdown()
    server.server_close()
    thread.join()


def test_clipboard_round_trip_and_stamp(rpc):
    assert bridge.change_stamp() == 1
    assert bridge.read_contents() == ('avant', b'PNG')
    assert bridge.set_contents('après', b'\0\xff')
    assert bridge.change_stamp() == 2
    assert bridge.read_contents() == ('après', b'\0\xff')


def test_bridge_rejects_unknown_operation_and_oversize(rpc, monkeypatch):
    with pytest.raises(OSError):
        bridge.call('run', command='anything')
    monkeypatch.setattr(bridge, 'MAX_DATA', 2)
    assert not bridge.set_contents('abc', None)
    assert rpc['contents'] == ('avant', b'PNG')


def test_receiver_rejects_oversized_packet():
    left, right = socket.socketpair()
    try:
        left.sendall((bridge.MAX_PACKET + 1).to_bytes(4, 'big'))
        with pytest.raises(OSError, match='too large'):
            bridge.receive(right)
    finally:
        left.close()
        right.close()
