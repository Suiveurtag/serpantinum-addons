#!/usr/bin/env python3
"""Niri IPC snapshots in the geometry format shared by the addon worlds."""
import json
import os
import socket
import sys
import time


from niri_ipc import request, addon


def normalize(outputs, workspaces, windows, native=None):
    native = native or {}
    active = {w['output']: w['id'] for w in workspaces if w['is_active']}
    spaces = {w['id']: w for w in workspaces}
    monitors = []
    for name, output in outputs.items():
        logical = output.get('logical')
        if not logical:
            continue
        monitors.append(dict(name=name, x=logical['x'], y=logical['y'],
                             activeWorkspace={'id': active.get(name)}, lastIpcObject={'reserved': native.get('reserved', {}).get(name, [0, 0, 0, 0])}))
    clients = []
    for w in windows:
        space = spaces.get(w.get('workspace_id'), {})
        logical = (outputs.get(space.get('output')) or {}).get('logical')
        layout = w.get('layout', {})
        position = layout.get('tile_pos_in_workspace_view')
        geometry = w.get('serpantinum_geometry')
        client = dict(address='niri:' + str(w['id']), pid=w.get('pid') or 0,
                      title=w.get('title') or '', **{'class': w.get('app_id') or ''},
                      workspace={'id': w.get('workspace_id')}, mapped=True, hidden=True,
                      floating=w.get('is_floating', False), focusHistoryID=0 if w['is_focused'] else 1)
        if geometry:
            output = (outputs.get(geometry['output']) or {}).get('logical')
            if output and geometry['w'] > 0 and geometry['h'] > 0:
                client.update(at=[geometry['x'], geometry['y']], size=[geometry['w'], geometry['h']],
                              fullscreen=geometry.get('fullscreen', False), pinned=True)
                client['hidden'] = not (geometry['x'] < output['x'] + output['width'] and geometry['y'] < output['y'] + output['height']
                    and geometry['x'] + geometry['w'] > output['x'] and geometry['y'] + geometry['h'] > output['y'])
        elif logical and position is not None:
            size = layout.get('tile_size')
            if size and len(size) == 2 and min(size) > 0:
                client.update(at=[logical['x'] + position[0], logical['y'] + position[1]], size=size, hidden=False)
        clients.append(client)
    return dict(monitors=monitors, clients=clients)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'focus':
        windows = request('Windows')
        window = next((w for pid in sys.argv[2:] for w in windows if w.get('pid') == int(pid)), None)
        if window:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(2)
                client.connect(os.environ['NIRI_SOCKET'])
                client.sendall((json.dumps({'Action': {'FocusWindow': {'id': window['id']}}}) + '\n').encode())
                with client.makefile('r') as stream:
                    reply = json.loads(stream.readline())
                if 'Err' in reply:
                    raise RuntimeError(reply['Err'])
        return
    previous = None
    extended = None
    outputs = {}
    last_outputs = 0.
    while True:
        try:
            if extended is None:
                try:
                    extended = addon('capabilities').get('version') == 1
                except RuntimeError:
                    extended = False
            if time.monotonic() - last_outputs > 2 or not outputs:
                outputs = request('Outputs')
                last_outputs = time.monotonic()
            native = addon('snapshot') if extended else {}
            state = normalize(outputs, request('Workspaces'), native['windows'] if extended else request('Windows'), native)
            if extended:
                state.update(pointer=native['pointer'], layers=native['layers'])
            line = json.dumps(state, separators=(',', ':'))
            if line != previous:
                print(line, flush=True)
                previous = line
        except (OSError, ValueError, KeyError, RuntimeError) as error:
            print('Niri world: ' + str(error), file=sys.stderr)
        time.sleep(.06 if extended else .15)


if __name__ == '__main__':
    try:
        main()
    except BrokenPipeError:
        pass
