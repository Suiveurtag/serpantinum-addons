"""Beamer clipboard backend for Hyprland's data-control protocol.

Install before the application constructs its sender. The watcher is started lazily;
no clipboard contents are read or changed by importing this module.
"""
import logging
import atexit
import os
from pathlib import Path
import selectors
import shutil
import signal
import struct
import subprocess
import threading
import time

LOG = logging.getLogger(__name__)
ROOT = Path(__file__).resolve().parent
HELPERS = Path(os.environ.get("BEAMER_HELPERS", ROOT))
WL_PASTE = os.environ.get("BEAMER_WL_PASTE") or str(HELPERS / "wl-paste")
if not os.path.exists(WL_PASTE):
    WL_PASTE = shutil.which("wl-paste") or WL_PASTE
OFFER = str(HELPERS / "clipboard-offer")
OWN_MIME = "application/x-beamer-hyprland-clipboard"
MAX_BYTES = 8 * 1024 * 1024
TIMEOUT = 2
_lock = threading.Lock()
_counter = 0
_synced = None
_watcher = None
_offer = None


def _watch():
    global _counter, _watcher
    try:
        proc = subprocess.Popen([WL_PASTE, "--watch", "sh", "-c", "printf 'changed\\n'; cat >/dev/null"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, close_fds=True,
                                start_new_session=True)
        with _lock:
            _watcher = proc
        for _ in proc.stdout:
            with _lock:
                _counter += 1
        proc.stdout.close()
        proc.wait()
    except OSError:
        LOG.exception("Could not watch the Wayland clipboard")
    finally:
        with _lock:
            _watcher = None


def _start_watcher():
    global _watcher
    with _lock:
        if _watcher is None:
            # Sentinel prevents two calling threads from launching concurrent watchers.
            _watcher = True
            threading.Thread(target=_watch, name="beamer-clipboard-watch", daemon=True).start()


def change_stamp():
    _start_watcher()
    with _lock:
        return _counter if _watcher is not None else None


def _paste(*args):
    proc = subprocess.Popen([WL_PASTE, *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    data = bytearray()
    deadline = time.monotonic() + TIMEOUT
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise TimeoutError("Wayland clipboard timed out")
                chunk = os.read(proc.stdout.fileno(), min(65536, MAX_BYTES + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > MAX_BYTES:
                    raise OSError("Wayland clipboard is too large")
        if proc.wait(timeout=max(0.01, deadline - time.monotonic())):
            raise OSError("wl-paste failed")
        return bytes(data)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        proc.stdout.close()


def read_contents():
    try:
        offered = _paste("--list-types").decode("utf-8", "replace").splitlines()
        if OWN_MIME in offered:
            return None, None
        mime = next((m for m in ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT") if m in offered), None)
        text = _paste("--no-newline", "--type", mime).decode("utf-8", "replace").replace("\r\n", "\n") if mime else None
        png = _paste("--type", "image/png") if "image/png" in offered else None
        return text or None, png or None
    except (OSError, subprocess.SubprocessError) as exc:
        raise OSError("Wayland clipboard could not be read") from exc


def get_contents():
    try:
        return read_contents()
    except OSError:
        LOG.exception("Wayland clipboard could not be read")
        return None, None


def changed_contents():
    global _synced
    stamp = change_stamp()
    if stamp is not None and stamp == _synced:
        return None, None
    contents = get_contents()
    if contents != (None, None):
        _synced = stamp
    return contents


def forget_sync():
    global _synced
    _synced = None


def set_contents(text, png):
    global _offer, _synced
    if text is None and png is None:
        return False
    text_data = text.replace("\r\n", "\n").encode("utf-8") if text is not None else None
    if any(part is not None and len(part) > MAX_BYTES for part in (text_data, png)):
        return False
    payload = struct.pack("!II", *(len(part) if part is not None else 0xffffffff for part in (text_data, png)))
    payload += (text_data or b"") + (png or b"")
    proc = None
    try:
        proc = subprocess.Popen([OFFER], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        proc.stdin.write(payload)
        proc.stdin.close()
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            if not selector.select(TIMEOUT) or proc.stdout.read(1) != b"1":
                proc.kill()
                proc.wait()
                return False
        previous = _offer
        _offer = proc
        proc.stdout.close()
        if previous:
            if previous.poll() is None:
                previous.terminate()
            previous.wait()
        _synced = change_stamp()
        return True
    except (OSError, subprocess.SubprocessError):
        if proc:
            proc.kill()
            proc.wait()
        LOG.exception("Could not offer the Wayland clipboard")
        return False


def install():
    import platform_parts
    platform_parts._parts.clipboard = platform_parts.clipboard = __import__(__name__)


@atexit.register
def _shutdown():
    with _lock:
        watcher = _watcher
    if watcher and watcher is not True and watcher.poll() is None:
        try:
            os.killpg(watcher.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        watcher.wait()
    if _offer and _offer.poll() is None:
        _offer.terminate()
        _offer.wait()
