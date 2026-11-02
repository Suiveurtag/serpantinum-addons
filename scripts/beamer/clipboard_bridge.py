#!/usr/bin/env python3
"""Limited clipboard RPC: the Wayland data-control client runs outside Flatpak."""
import base64
import json
import logging
import os
from pathlib import Path
import signal
import socket
import socketserver
import stat
import struct
import sys
import threading

LOG = logging.getLogger(__name__)
MAX_PACKET = 24 * 1024 * 1024
MAX_DATA = 8 * 1024 * 1024
TIMEOUT = 10


def socket_path():
    return Path(os.environ['XDG_RUNTIME_DIR']) / 'beamer-addon' / 'clipboard.sock'


def receive(sock):
    def read(n):
        chunks = bytearray()
        while len(chunks) < n:
            data = sock.recv(min(65536, n - len(chunks)))
            if not data:
                raise OSError('clipboard connection closed')
            chunks.extend(data)
        return bytes(chunks)
    size = struct.unpack('!I', read(4))[0]
    if size > MAX_PACKET:
        raise OSError('clipboard request too large')
    try:
        return json.loads(read(size))
    except (ValueError, UnicodeError) as exc:
        raise OSError('invalid clipboard response') from exc


def send(sock, value):
    data = json.dumps(value, separators=(',', ':')).encode('utf-8')
    if len(data) > MAX_PACKET:
        raise OSError('clipboard request too large')
    sock.sendall(struct.pack('!I', len(data)) + data)


def call(op, **kwargs):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(TIMEOUT)
        sock.connect(str(socket_path()))
        send(sock, {'op': op, **kwargs})
        answer = receive(sock)
    if not isinstance(answer, dict) or not answer.get('ok'):
        raise OSError('clipboard bridge failed')
    return answer.get('value')


def read_contents():
    result = call('read')
    if not isinstance(result, list) or len(result) != 2:
        raise OSError('invalid clipboard bridge result')
    text, image = result
    try:
        return text, base64.b64decode(image, validate=True) if image is not None else None
    except (ValueError, TypeError) as exc:
        raise OSError('invalid clipboard image') from exc


def get_contents():
    try:
        return read_contents()
    except OSError:
        LOG.exception('Could not read from the clipboard bridge')
        return None, None


def change_stamp():
    try:
        return call('stamp')
    except OSError:
        LOG.exception('Could not watch the clipboard bridge')
        return None


def set_contents(text, png):
    if text is not None and len(text.encode('utf-8')) > MAX_DATA:
        return False
    if png is not None and len(png) > MAX_DATA:
        return False
    try:
        return bool(call('set', text=text, image=base64.b64encode(png).decode('ascii') if png is not None else None))
    except OSError:
        LOG.exception('Could not write to the clipboard bridge')
        return False


def install():
    import platform_parts
    platform_parts._parts.clipboard = platform_parts.clipboard = sys.modules[__name__]


class Handler(socketserver.BaseRequestHandler):
    lock = threading.Lock()

    def handle(self):
        self.request.settimeout(TIMEOUT)
        try:
            request = receive(self.request)
            if not isinstance(request, dict):
                raise ValueError('invalid request')
            import hyprland_clipboard as clipboard
            with self.lock:
                op = request.get('op')
                if op == 'stamp':
                    value = clipboard.change_stamp()
                elif op == 'read':
                    text, png = clipboard.read_contents()
                    value = [text, base64.b64encode(png).decode('ascii') if png is not None else None]
                elif op == 'set':
                    text, image = request.get('text'), request.get('image')
                    if text is not None and (not isinstance(text, str) or len(text.encode('utf-8')) > MAX_DATA):
                        raise ValueError('invalid text')
                    png = base64.b64decode(image, validate=True) if image is not None else None
                    if png is not None and len(png) > MAX_DATA:
                        raise ValueError('invalid image')
                    value = clipboard.set_contents(text, png)
                else:
                    raise ValueError('unknown operation')
            send(self.request, {'ok': True, 'value': value})
        except (OSError, ValueError, TypeError):
            try:
                send(self.request, {'ok': False})
            except OSError:
                pass


def serve():
    path = socket_path()
    info = path.parent.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('unsafe clipboard socket directory')
    if path.exists() or path.is_symlink():
        raise RuntimeError('clipboard socket already exists')
    with socketserver.ThreadingUnixStreamServer(str(path), Handler) as server:
        server.daemon_threads = True
        os.chmod(path, 0o600)
        try:
            server.serve_forever(poll_interval=0.2)
        finally:
            path.unlink(missing_ok=True)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    serve()
