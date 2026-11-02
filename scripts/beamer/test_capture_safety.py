import importlib
import types
from unittest.mock import patch


class Hooks:
    def __init__(self):
        self.now = 0
        self._activation = None
        self.events = []

    def _clock(self):
        return self.now

    def _activated(self, options):
        self._activation = options["activation_id"]

    def _key_event(self, code, down, device):
        self.events.append((code, down))

    def _tick(self):
        self.events.append("tick")

    def _home(self):
        self.events.append("home")

    def _shake_release_point(self, point):
        return point[0] + 24, point[1]

    def _let_go(self, point):
        self.events.append(("release", point))
        self._activation = None


def make_hooks(monkeypatch, timeout="60"):
    # A fresh subclass avoids stacking wrappers between tests.
    class InstanceHooks(Hooks):
        pass

    if timeout is None:
        monkeypatch.delenv("BEAMER_CAPTURE_TIMEOUT", raising=False)
    else:
        monkeypatch.setenv("BEAMER_CAPTURE_TIMEOUT", timeout)
    monkeypatch.setitem(__import__("sys").modules, "capture_portal", types.SimpleNamespace(Hooks=InstanceHooks))
    monkeypatch.setitem(__import__("sys").modules, "desktop_portal", types.SimpleNamespace(cursor_position=lambda: (0, 3)))
    importlib.import_module("hyprland_capture").install()
    return InstanceHooks()


def test_short_escape_reaches_remote_as_a_tap(monkeypatch):
    h = make_hooks(monkeypatch)
    h._activated({"activation_id": 1})
    device = object()
    h._key_event(1, True, device)
    h.now = 1
    h._key_event(1, False, device)
    assert h.events == [(1, True), (1, False)]


def test_held_escape_returns_capture_without_sending_escape(monkeypatch):
    h = make_hooks(monkeypatch)
    h._activated({"activation_id": 1})
    h._key_event(1, True, object())
    h.now = 2
    h._tick()
    assert h.events == ["home", ("release", (24, 3))]
    assert h._activation is None


def test_timeout_returns_capture_even_if_no_input_arrives(monkeypatch):
    h = make_hooks(monkeypatch, timeout="10")
    h._activated({"activation_id": 1})
    h.now = 10
    h._tick()
    assert h.events == ["home", ("release", (24, 3))]


def test_healthy_long_capture_is_not_cut_off_by_default(monkeypatch):
    h = make_hooks(monkeypatch, timeout=None)
    h._activated({"activation_id": 1})
    h.now = 10000
    h._tick()
    assert h.events == ["tick"]
    assert h._activation == 1
def test_early_exit_releases_even_if_home_callback_fails(monkeypatch):
    h = make_hooks(monkeypatch, timeout="10")
    h._activated({"activation_id": 1})
    h.now = 10
    with patch.object(h, "_home", side_effect=RuntimeError("link closed")):
        try:
            h._tick()
        except RuntimeError:
            pass
    assert h._activation is None
    assert h.events == [("release", (24, 3))]
