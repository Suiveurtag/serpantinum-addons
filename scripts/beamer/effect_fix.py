"""Route Beamer's XWayland effect helper through the safe multi-monitor wrapper."""

from pathlib import Path
import subprocess
import sys


def install():
    import effect_overlay_x11
    from PySide6.QtGui import QGuiApplication

    addon_helper = Path(__file__).resolve().with_name("effect_overlay_helper.py")
    proxy = effect_overlay_x11.EffectOverlayX11Proxy
    original_init = proxy.__init__
    original_send = proxy._send

    def send(self, op, check=True, **values):
        if op in ("push", "arrive", "switched") and "x" in values:
            x, y = values["x"], values["y"]
            screen = next((screen for screen in QGuiApplication.screens()
                           if screen.geometry().contains(round(x), round(y))), None)
            if screen is not None:
                geometry = screen.geometry()
                values["monitor"] = screen.name()
                values["monitor_geometry"] = [geometry.x(), geometry.y(),
                                               geometry.width(), geometry.height()]
            values["screens"] = [[screen.name(), screen.geometry().x(), screen.geometry().y(),
                                  screen.geometry().width(), screen.geometry().height()]
                                 for screen in QGuiApplication.screens()]
        return original_send(self, op, check=check, **values)

    def init(self, on_failure=None, popen=subprocess.Popen):
        def launch(command, *args, **kwargs):
            if (len(command) >= 2
                    and Path(command[1]).name == "effect_overlay_x11.py"):
                command = [command[0], str(addon_helper), *command[2:]]
            return popen(command, *args, **kwargs)

        original_init(self, on_failure=on_failure, popen=launch)

    proxy.__init__ = init
    proxy._send = send
