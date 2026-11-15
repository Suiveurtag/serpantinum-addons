"""Bounded requests to the current Niri instance, including the addon API."""
import json
import os
import socket


def request(command):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(2)
        client.connect(os.environ['NIRI_SOCKET'])
        client.sendall((json.dumps(command, allow_nan=False) + '\n').encode())
        with client.makefile('r') as stream:
            line = stream.readline(8 * 1024 * 1024 + 1)
        if not line or len(line) > 8 * 1024 * 1024:
            raise RuntimeError('Invalid or oversized Niri response')
        reply = json.loads(line)
    if 'Err' in reply:
        raise RuntimeError(reply['Err'])
    response = reply.get('Ok')
    if response == 'Handled':
        return None
    if not isinstance(response, dict) or len(response) != 1:
        raise RuntimeError('Invalid Niri response')
    return next(iter(response.values()))


def addon(op, **values):
    return request({'Serpantinum': dict(op=op, **values)})
