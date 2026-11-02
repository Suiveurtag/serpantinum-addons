"""Temporary capture safeguards while the Hyprland return path is being validated."""
import logging
import os

LOG = logging.getLogger(__name__)
ESC = 1  # Linux evdev KEY_ESC, independent of the keyboard layout.
HOLD_SECONDS = 2.0


def install():
    import capture_portal
    import desktop_portal

    timeout = None
    if "BEAMER_CAPTURE_TIMEOUT" in os.environ:
        try:
            timeout = float(os.environ["BEAMER_CAPTURE_TIMEOUT"])
            if not 5 <= timeout <= 3600:
                raise ValueError
        except ValueError as exc:
            raise RuntimeError("BEAMER_CAPTURE_TIMEOUT must be between 5 and 3600 seconds") from exc

    hooks = capture_portal.Hooks
    original_activated = hooks._activated
    original_key = hooks._key_event
    original_tick = hooks._tick

    def activated(self, options):
        self._addon_capture_at = self._clock()
        self._addon_escape = None
        original_activated(self, options)

    def key_event(self, code, down, device):
        if code != ESC or self._activation is None:
            return original_key(self, code, down, device)
        held = getattr(self, "_addon_escape", None)
        if down:
            if held is None:
                self._addon_escape = (id(device), self._clock())
        elif held is not None and held[0] == id(device):
            self._addon_escape = None
            original_key(self, code, True, device)
            original_key(self, code, False, device)

    def tick(self):
        if self._activation is not None:
            now = self._clock()
            held = getattr(self, "_addon_escape", None)
            started = getattr(self, "_addon_capture_at", now)
            reason = "holding Escape" if held and now - held[1] >= HOLD_SECONDS else None
            if reason is None and timeout is not None and now - started >= timeout:
                reason = "safety timeout"
            if reason:
                LOG.warning("Returning input to Hyprland after %s", reason)
                self._addon_escape = None
                try:
                    self._home()
                finally:
                    if self._activation is not None:
                        self._let_go(self._shake_release_point(desktop_portal.cursor_position()))
                return
        return original_tick(self)

    hooks._activated = activated
    hooks._key_event = key_event
    hooks._tick = tick
