"""Keep Beamer's effect commands, transport them to the host's layer-shell renderer."""
import json
import os
import socket


def install():
    import effect_overlay_x11
    original = effect_overlay_x11.EffectOverlayX11Proxy
    class NativeProxy(original):
        def __init__(self, on_failure=None, popen=None):
            super().__init__(on_failure=on_failure)
            self._native_socket = None

        def _send(self, op, check=True, **values):
            if self._failed:
                return
            try:
                if self._native_socket is None:
                    self._native_socket = socket.socket(socket.AF_UNIX)
                    self._native_socket.settimeout(1)
                    self._native_socket.connect(os.path.join(os.environ['XDG_RUNTIME_DIR'], 'beamer-addon', 'effects.sock'))
                self._native_socket.sendall((json.dumps(dict(op=op, **values), allow_nan=False) + '\n').encode())
            except (OSError, ValueError):
                self._fail()

        def _fail(self):
            if self._native_socket is not None:
                self._native_socket.close()
                self._native_socket = None
            super()._fail()

    effect_overlay_x11.EffectOverlayX11Proxy = NativeProxy
    # Niri uses the native host renderer even when DISPLAY is absent.
    effect_overlay_x11.available = lambda *args, **kwargs: True
