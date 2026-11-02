#!/usr/bin/env python3
"""Run the supported Beamer Flatpak with the addon modules, without changing the app."""
import fcntl
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import time

APP = "uk.co.kalkman.beamer"
VERSION = "1.5.18"
ENTRY = "/app/share/beamer/win_app/kvm_bridge_win.py"


def main():
    addon_dir = Path(__file__).resolve().parent
    if len(sys.argv) > 1 and sys.argv[1] == "--inside-flatpak":
        if not Path("/.flatpak-info").exists():
            raise SystemExit("This entry point must run inside Flatpak")
        sys.path.insert(0, str(addon_dir))
        import hyprland_capture
        import hyprland_inject
        import clipboard_bridge
        import effect_fix

        hyprland_capture.install()
        hyprland_inject.install()
        clipboard_bridge.install()
        effect_fix.install()
        sys.argv = [ENTRY, *sys.argv[2:]]
        runpy.run_path(ENTRY, run_name="__main__")
        return

    try:
        installed = subprocess.check_output(
            ["flatpak", "list", "--user", "--app", "--columns=application,version"],
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"Could not check the Beamer Flatpak: {exc}") from exc
    versions = [row.split("\t", 1)[1].strip() for row in installed.splitlines()
                if row.startswith(APP + "\t")]
    if versions != [VERSION]:
        raise SystemExit(f"Beamer addon requires user Flatpak {APP} version {VERSION}; found {versions or 'none'}")
    for name in ("hyprland_capture.py", "hyprland_inject.py", "hyprland_clipboard.py", "input_bridge.py", "clipboard_bridge.py", "effect_fix.py", "effect_overlay_helper.py", "overlay_place.py"):
        if not (addon_dir / name).is_file():
            raise SystemExit(f"Missing Beamer addon module: {addon_dir / name}")
    helpers = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "serpantinum-addons-v2" / "beamer"
    for name in ("clipboard-offer", "wl-paste"):
        if not os.access(helpers / name, os.X_OK):
            raise SystemExit(f"Missing Beamer helper: {helpers / name}; run build-clipboard.sh")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise SystemExit("XDG_RUNTIME_DIR is not set")
    lock_path = Path(runtime) / "beamer-addon.lock"
    lock = os.fdopen(os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "r+")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("The Beamer addon is already running") from None
    socket_path = Path(runtime) / "beamer-addon" / "input.sock"
    clipboard_socket = socket_path.with_name('clipboard.sock')
    for path in (socket_path, clipboard_socket):
        if path.exists() or path.is_symlink():
            raise SystemExit(f"Beamer bridge socket already exists: {path}")
    command = [
        "flatpak", "run", "--user", "--die-with-parent", f"--filesystem={addon_dir}:ro",
        f"--filesystem={helpers}:ro", "--filesystem=xdg-run/beamer-addon",
        f"--env=BEAMER_HELPERS={helpers}", "--env=LD_LIBRARY_PATH=/app/lib64",
    ]
    if "BEAMER_CAPTURE_TIMEOUT" in os.environ:
        command.append(f"--env=BEAMER_CAPTURE_TIMEOUT={os.environ['BEAMER_CAPTURE_TIMEOUT']}")
    command.extend(["--command=python3", APP, str(addon_dir / "launcher.py"),
                    "--inside-flatpak", *sys.argv[1:]])
    bridge = subprocess.Popen([sys.executable, str(addon_dir / "input_bridge.py")])
    app = clipboard = None
    old_term = signal.signal(signal.SIGTERM, lambda *_: sys.exit(128 + signal.SIGTERM))
    try:
        deadline = time.monotonic() + 12
        while not socket_path.exists():
            if bridge.poll() is not None:
                raise SystemExit(f"Beamer input bridge failed (exit {bridge.returncode})")
            if time.monotonic() >= deadline:
                raise SystemExit("Beamer input bridge did not start")
            time.sleep(0.05)
        if bridge.poll() is not None:
            raise SystemExit(f"Beamer input bridge failed (exit {bridge.returncode})")
        clipboard = subprocess.Popen([sys.executable, str(addon_dir / 'clipboard_bridge.py')],
                                     env={**os.environ, 'BEAMER_HELPERS': str(helpers)})
        deadline = time.monotonic() + 5
        while not clipboard_socket.exists():
            if clipboard.poll() is not None:
                raise SystemExit(f"Beamer clipboard bridge failed (exit {clipboard.returncode})")
            if bridge.poll() is not None or time.monotonic() >= deadline:
                raise SystemExit("Beamer clipboard bridge did not start")
            time.sleep(0.05)
        if clipboard.poll() is not None:
            raise SystemExit(f"Beamer clipboard bridge failed (exit {clipboard.returncode})")
        import overlay_place
        overlay_place.start()
        app = subprocess.Popen(command)
        while app.poll() is None:
            if bridge.poll() is not None:
                raise SystemExit(f"Beamer input bridge stopped (exit {bridge.returncode})")
            if clipboard.poll() is not None:
                raise SystemExit(f"Beamer clipboard bridge stopped (exit {clipboard.returncode})")
            time.sleep(0.2)
        return app.returncode
    finally:
        try:
            import overlay_place
            overlay_place.clear()
        except (ImportError, OSError):
            pass
        for process in (app, clipboard, bridge):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        signal.signal(signal.SIGTERM, old_term)


if __name__ == "__main__":
    sys.exit(main())
