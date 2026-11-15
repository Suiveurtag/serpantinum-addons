#!/usr/bin/env python3
"""Narrow host broker for Beamer's Niri input-capture session."""
import json
import os
from pathlib import Path
import signal
import socket
import stat
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from niri_ipc import addon


def serve():
    addon('capabilities')
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'beamer-addon/capture.sock'
    path.parent.mkdir(mode=0o700, exist_ok=True)
    info = path.parent.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('Unsafe capture socket directory')
    if path.exists() or path.is_symlink():
        raise RuntimeError('Capture broker already exists')
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path)); os.chmod(path, 0o600); server.listen(1)
        try:
            while True:
                conn, _ = server.accept()
                owner = None
                try:
                    with conn, conn.makefile('rb') as stream:
                        while line := stream.readline(65537):
                            if len(line) > 65536:
                                break
                            try:
                                command = json.loads(line)
                                if command.get('command') not in ('open', 'barriers', 'poll', 'release', 'close', 'zones'):
                                    raise ValueError('Invalid capture operation')
                                token = command.get('owner')
                                if not isinstance(token, str) or len(token) != 32 or any(c not in '0123456789abcdef' for c in token):
                                    raise ValueError('Invalid capture owner')
                                if owner is not None and owner != token:
                                    raise ValueError('Capture owner changed')
                                owner = token
                                reply = dict(ok=True, data=addon('capture', **command))
                            except (ValueError, RuntimeError, OSError) as error:
                                reply = dict(ok=False, error=str(error))
                            conn.sendall((json.dumps(reply, allow_nan=False) + '\n').encode())
                except (OSError, ValueError):
                    pass
                finally:
                    if owner is not None:
                        try:
                            addon('capture', command='close', owner=owner)
                        except (OSError, RuntimeError):
                            pass  # The compositor lease independently releases input.
        finally:
            path.unlink(missing_ok=True)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    serve()
