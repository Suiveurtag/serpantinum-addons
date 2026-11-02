"""Host-side Hyprland guard for Beamer, started by the launcher.

1. Hyprland ignores the position XWayland asks for (and the `move` window rule), and re-places the effect overlay
   when it is re-shown, so the 2-screen overlay is kept on the leftmost monitor's origin by polling.
   The overlay is click-through, so moving it is safe.
2. The monitor edges where a Beamer peer sits are published in $XDG_RUNTIME_DIR/beamer-addon/edges.json so the shell's
   quick actions can ignore them (the pointer is pinned there while crossing)."""
import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

CLASS = re.compile(r'^(effect_overlay_x11|effect_overlay_helper)\.py$')
SETTINGS = Path.home() / '.var/app/uk.co.kalkman.beamer/config/Beamer/settings.json'


def edges_path():
    return Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp')) / 'beamer-addon/edges.json'


def _hyprctl(*args):
    return subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=5).stdout


def monitors():
    return json.loads(_hyprctl('monitors', '-j'))


def place_all(mons=None):
    mons = mons or monitors()
    origin = min(mons, key=lambda m: (m['x'], m['y']))
    for client in json.loads(_hyprctl('clients', '-j')):
        if CLASS.match(client.get('class', '')) and client['at'] != [origin['x'], origin['y']]:
            _hyprctl('dispatch', 'hl.dsp.window.move({ x = %d, y = %d, window = "address:%s" })'
                     % (origin['x'], origin['y'], client['address']))


def peer_edges(mons, settings=SETTINGS):
    """[{monitor, edge}] for every outer monitor edge that faces an active Beamer peer."""
    try:
        peers = json.loads(Path(settings).read_text()).get('peers', [])
    except (OSError, ValueError):
        return []
    result = []
    for peer in peers:
        side = peer.get('side')
        if not peer.get('in_use') or side not in ('left', 'right', 'top', 'bottom'):
            continue
        key, pick = {'left': (lambda m: m['x'], min), 'right': (lambda m: m['x'] + m['width'], max),
                     'top': (lambda m: m['y'], min), 'bottom': (lambda m: m['y'] + m['height'], max)}[side]
        best = pick(key(m) for m in mons)
        result += [{'monitor': m['name'], 'edge': side} for m in mons if key(m) == best]
    return result


def write_edges(edges):
    path = edges_path()
    data = json.dumps(edges)
    try:
        if path.exists() and path.read_text() == data:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix('.tmp')
        tmp.write_text(data)
        tmp.replace(path)
    except OSError:
        pass


def clear():
    try:
        edges_path().unlink()
    except OSError:
        pass


def _loop(interval):
    while True:
        try:
            mons = monitors()
            place_all(mons)
            write_edges(peer_edges(mons))
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            pass
        time.sleep(interval)


def start(interval=0.5):
    thread = threading.Thread(target=_loop, args=(interval,), name='beamer-hyprland-guard', daemon=True)
    thread.start()
    return thread
