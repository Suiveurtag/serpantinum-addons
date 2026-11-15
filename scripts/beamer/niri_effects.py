#!/usr/bin/env python3
"""Render Beamer's existing effects on click-through native per-output layer surfaces."""
import ctypes
import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys


def app_source():
    location = subprocess.check_output(['flatpak', 'info', '--user', '--show-location', 'uk.co.kalkman.beamer'], text=True).strip()
    return Path(location) / 'files/share/beamer/win_app'


def run():
    os.environ['QT_QPA_PLATFORM'] = 'wayland'
    os.environ['QT_WAYLAND_SHELL_INTEGRATION'] = 'layer-shell'
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    source = app_source()
    sys.path.insert(0, str(source.parent))
    sys.path.insert(0, str(source))
    from niri_ipc import addon
    from PySide6.QtCore import QPointF, QRect, QSocketNotifier, QTimer
    from PySide6.QtGui import QCursor, QPainter
    from PySide6.QtWidgets import QApplication
    import shiboken6
    import effect_overlay as effect
    import effect_overlay_x11 as engine
    import edge_glow as glow_engine

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    library = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'serpantinum-addons-v2/beamer/layershell.so'
    native = ctypes.CDLL(str(library))
    native.serpantinum_layer.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p]
    native.serpantinum_layer.restype = None

    class Cursor:
        @staticmethod
        def pos():
            p = addon('snapshot')['pointer']
            return QPointF(p['x'], p['y']).toPoint()
    effect.QCursor = glow_engine.QCursor = Cursor
    # Stacking is provided by the layer role, without xdg activation requests.
    glow_engine.keep_on_top = lambda widget: None

    def attach(widget, screen, scope):
        widget.winId()
        native.serpantinum_layer(shiboken6.getCppPointer(widget.windowHandle())[0], shiboken6.getCppPointer(screen)[0], scope.encode())

    class Overlay(effect.EffectOverlay):
        def __init__(self, screen):
            self.output = screen
            super().__init__(fixed_geometry=True)
            self.resize(screen.size())
            attach(self, screen, 'qs-addon-beamer-effects')

        def setGeometry(self, *args):
            super().setGeometry(QRect(0, 0, self.output.geometry().width(), self.output.geometry().height()))

        def update(self, *args):
            super().update()

        def paintEvent(self, event):
            geo = self.output.geometry()
            self._offset = (geo.x() - self._desk.x(), geo.y() - self._desk.y())
            super().paintEvent(event)

    class Glow(glow_engine.EdgeGlow):
        def __init__(self, screen):
            self.output = screen
            self.desired = QRect()
            super().__init__()
            self.resize(screen.size())
            attach(self, screen, 'qs-addon-beamer-glow')

        def setGeometry(self, *args):
            self.desired = QRect(*args)
            super().setGeometry(QRect(0, 0, self.output.geometry().width(), self.output.geometry().height()))

        def paintEvent(self, event):
            painter = QPainter(self)
            try:
                geo = self.output.geometry()
                painter.translate(self.desired.x() - geo.x(), self.desired.y() - geo.y())
                rect = QRect(0, 0, self.desired.width(), self.desired.height())
                if self._part in glow_engine.crossing.CORNERS:
                    glow_engine.paint_corner(painter, rect, self._part, self._style, self._colour, self._state, band=self._band, dark=self._dark)
                else:
                    glow_engine.paint(painter, rect, self._edge, self._style, self._colour, self._state, band=self._band, dark=self._dark, taper=self._part in glow_engine.crossing.PARTS)
            finally:
                painter.end()

    pairs = {}
    configuration = {}
    def screens():
        for screen in app.screens():
            if screen.name() not in pairs:
                pair = (Overlay(screen), Glow(screen))
                pairs[screen.name()] = pair
                for command in configuration.values():
                    engine.dispatch(command, *pair, effect.desktop_box(), QPointF)
        active = {s.name() for s in app.screens()}
        for name in list(pairs):
            if name not in active:
                for widget in pairs.pop(name):
                    widget.close(); widget.deleteLater()
    app.screenAdded.connect(lambda *_: screens())
    app.screenRemoved.connect(lambda *_: screens())
    screens()

    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'beamer-addon/effects.sock'
    path.parent.mkdir(mode=0o700, exist_ok=True)
    info = path.parent.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('Unsafe Beamer socket directory')
    if path.exists() or path.is_symlink():
        raise RuntimeError('Beamer effect socket already exists')
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path)); os.chmod(path, 0o600); server.listen(4); server.setblocking(False)
    clients = {}
    def accept():
        conn, _ = server.accept(); conn.setblocking(False)
        notifier = QSocketNotifier(conn.fileno(), QSocketNotifier.Type.Read)
        clients[conn] = [notifier, bytearray()]
        def read():
            try:
                data = conn.recv(65536)
                if not data:
                    raise EOFError
                buffer = clients[conn][1]
                buffer.extend(data)
                if len(buffer) > 1024 * 1024:
                    raise ValueError('Oversized effect message')
                while b'\n' in buffer:
                    line, _, rest = buffer.partition(b'\n'); buffer[:] = rest
                    command = json.loads(line)
                    if command.get('op') in ('effect_configure', 'glow_configure'):
                        configuration[command['op']] = command
                    for pair in pairs.values():
                        engine.dispatch(command, *pair, effect.desktop_box(), QPointF)
            except (EOFError, OSError, ValueError, KeyError, TypeError) as error:
                notifier.setEnabled(False); notifier.deleteLater(); conn.close(); clients.pop(conn, None)
                for overlay, glow in pairs.values():
                    overlay.stop(); glow.hide()
                if not isinstance(error, EOFError):
                    print('Beamer native effects: ' + str(error), file=sys.stderr)
        notifier.activated.connect(read)
    incoming = QSocketNotifier(server.fileno(), QSocketNotifier.Type.Read)
    incoming.activated.connect(accept)
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    timer = QTimer(); timer.timeout.connect(lambda: None); timer.start(200)
    try:
        return app.exec()
    finally:
        for conn, (notifier, _) in list(clients.items()):
            notifier.setEnabled(False); conn.close()
        server.close(); path.unlink(missing_ok=True)

if __name__ == '__main__':
    sys.exit(run())
