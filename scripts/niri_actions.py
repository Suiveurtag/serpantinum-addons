#!/usr/bin/env python3
"""Niri actions shared by addon processes, scoped to NIRI_SOCKET."""
import json
import os
import signal
import socket
import sys
from niri_world import request


from niri_ipc import request as ipc_request, addon


def action(name, **arguments):
    return ipc_request({'Action': {name: arguments}})


def surge(screen, stream=sys.stdin):
    spaces = [s for s in request('Workspaces') if s['output'] == screen]
    home = next((s for s in spaces if s['is_active']), None)
    occupied = {w['workspace_id'] for w in request('Windows')}
    away = next((s for s in spaces if home and s['id'] != home['id'] and s['id'] not in occupied), None)
    if not home or not away:
        raise RuntimeError('No empty workspace on the selected monitor')
    try:
        action('FocusMonitor', output=screen)
        action('FocusWorkspace', reference={'Id': away['id']})
        print(json.dumps({'ready': True, 'home': home['id']}), flush=True)
        for line in stream:
            if json.loads(line).get('close'):
                break
    finally:
        # Stable workspace IDs survive reordering while the scene is running.
        action('FocusMonitor', output=screen)
        action('FocusWorkspace', reference={'Id': home['id']})


def main():
    if sys.argv[1] == 'surge':
        def stop(*_):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, stop)
        try:
            surge(sys.argv[2])
        except KeyboardInterrupt:
            pass
    elif sys.argv[1] == 'next-monitor':
        action('FocusMonitorNext')
        output = request('FocusedOutput')
        if output and output.get('logical'):
            geo = output['logical']
            addon('warp', x=geo['x'] + geo['width'] / 2, y=geo['y'] + geo['height'] / 2)
    elif sys.argv[1] == 'warp':
        addon('warp', x=float(sys.argv[2]), y=float(sys.argv[3]))
    elif sys.argv[1] == 'cycle-window':
        spaces = request('Workspaces')
        space = next((s for s in spaces if s['is_focused']), None)
        windows = [w for w in request('Windows') if space and w['workspace_id'] == space['id']]
        windows.sort(key=lambda w: w['id'])
        index = next((i for i, w in enumerate(windows) if w['is_focused']), -1)
        if windows:
            action('FocusWindow', id=windows[(index + 1) % len(windows)]['id'])
    else:
        raise ValueError('Unknown Niri action')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
