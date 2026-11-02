import importlib.util
from pathlib import Path
import subprocess

import pytest


spec = importlib.util.spec_from_file_location('beamer_launcher', Path(__file__).resolve().parent / 'launcher.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


def prepare(monkeypatch, tmp_path, version='1.5.18'):
    monkeypatch.setattr(launcher, '__file__', str(tmp_path / 'launcher.py'))
    monkeypatch.setattr(launcher.sys, 'argv', ['launcher.py'])
    monkeypatch.setenv('XDG_RUNTIME_DIR', str(tmp_path))
    monkeypatch.setattr(launcher.subprocess, 'check_output', lambda *a, **k: f'{launcher.APP}\t{version}\n')
    for name in ('hyprland_capture.py', 'hyprland_inject.py', 'hyprland_clipboard.py', 'input_bridge.py'):
        (tmp_path / name).touch()
    monkeypatch.setenv('XDG_CACHE_HOME', str(tmp_path))
    helpers = tmp_path / 'serpantinum-addons-v2/beamer'
    helpers.mkdir(parents=True)
    for name in ('clipboard-offer', 'wl-paste'):
        (helpers / name).touch(mode=0o755)


def test_rejects_different_version(monkeypatch, tmp_path):
    prepare(monkeypatch, tmp_path, '9.0')
    with pytest.raises(SystemExit, match='requires user Flatpak'):
        launcher.main()


def test_existing_socket_is_not_removed(monkeypatch, tmp_path):
    prepare(monkeypatch, tmp_path)
    socket = tmp_path / 'beamer-addon/input.sock'
    socket.parent.mkdir()
    socket.touch()
    with pytest.raises(SystemExit, match='already exists'):
        launcher.main()
    assert socket.exists()


def test_stops_owned_bridge_after_app_exit(monkeypatch, tmp_path):
    prepare(monkeypatch, tmp_path)
    socket = tmp_path / 'beamer-addon/input.sock'
    calls = []

    class Process:
        def __init__(self, cmd):
            calls.append(cmd)
            self.bridge = len(calls) == 1
            self.returncode = None if self.bridge else 0
            self.terminated = False
            if self.bridge:
                socket.parent.mkdir()
                socket.touch()
        def poll(self):
            return self.returncode
        def terminate(self):
            self.terminated = True
            self.returncode = 0
        def wait(self, timeout=None):
            return self.returncode

    processes = []
    def popen(cmd):
        proc = Process(cmd)
        processes.append(proc)
        return proc
    monkeypatch.setattr(launcher.subprocess, 'Popen', popen)
    assert launcher.main() == 0
    assert processes[0].terminated
    assert calls[1][0:3] == ['flatpak', 'run', '--user']
    assert f'--filesystem={tmp_path}:ro' in calls[1]


def test_bridge_failure_prevents_app_launch(monkeypatch, tmp_path):
    prepare(monkeypatch, tmp_path)
    class Failed:
        returncode = 1
        def poll(self):
            return 1
    calls = []
    monkeypatch.setattr(launcher.subprocess, 'Popen', lambda cmd: calls.append(cmd) or Failed())
    with pytest.raises(SystemExit, match='bridge failed'):
        launcher.main()
    assert len(calls) == 1


def test_second_launcher_does_not_start(monkeypatch, tmp_path):
    import fcntl
    prepare(monkeypatch, tmp_path)
    with open(tmp_path / 'beamer-addon.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(SystemExit, match='already running'):
            launcher.main()


def test_running_app_stops_if_bridge_dies(monkeypatch, tmp_path):
    prepare(monkeypatch, tmp_path)
    socket = tmp_path / 'beamer-addon/input.sock'
    processes = []

    class Process:
        def __init__(self, cmd):
            self.bridge = not processes
            self.returncode = None
            self.polls = 0
            self.terminated = False
            if self.bridge:
                socket.parent.mkdir()
                socket.touch()
            processes.append(self)
        def poll(self):
            self.polls += 1
            if self.bridge and self.polls > 1:
                self.returncode = 1
            return self.returncode
        def terminate(self):
            self.terminated = True
            self.returncode = -15
        def wait(self, timeout=None):
            return self.returncode
    monkeypatch.setattr(launcher.subprocess, 'Popen', Process)
    with pytest.raises(SystemExit, match='bridge stopped'):
        launcher.main()
    assert processes[1].terminated
