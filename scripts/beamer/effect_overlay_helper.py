"""Run Beamer's real effect engine with safe click-through and monitor-local coordinates."""

import ctypes
import ctypes.util
import importlib.util
from pathlib import Path
import sys


def _empty_input_region(widget):
    """Give an X11 overlay an empty ShapeInput region so it cannot intercept clicks."""
    x11_name = ctypes.util.find_library("X11")
    xext_name = ctypes.util.find_library("Xext")
    if not x11_name or not xext_name:
        raise RuntimeError("X11 ShapeInput support is unavailable")
    x11, xext = ctypes.CDLL(x11_name), ctypes.CDLL(xext_name)
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XFree.argtypes = [ctypes.c_void_p]
    xext.XShapeCombineRectangles.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    ]
    xext.XShapeGetRectangles.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ]
    xext.XShapeGetRectangles.restype = ctypes.c_void_p
    display = getattr(_empty_input_region, "display", None)
    if display is None:
        display = x11.XOpenDisplay(None)
        if not display:
            raise RuntimeError("Could not connect to the XWayland display")
        _empty_input_region.display = display
    window = int(widget.winId())
    # ShapeInput=2, ShapeSet=0, Unsorted=0; zero rectangles means no input hits.
    xext.XShapeCombineRectangles(display, window, 2, 0, 0, None, 0, 0, 0)
    x11.XSync(display, 0)
    count, ordering = ctypes.c_int(), ctypes.c_int()
    rectangles = xext.XShapeGetRectangles(display, window, 2,
                                           ctypes.byref(count), ctypes.byref(ordering))
    if rectangles:
        x11.XFree(rectangles)
    if count.value != 0:
        raise RuntimeError("XWayland did not apply the empty overlay input region")


def _patch_overlay(overlay, effect_module, logical_layout):
    from PySide6.QtCore import QRect

    original_geometry, original_show, original_start = overlay.setGeometry, overlay.show, overlay._start

    def start(now):
        result = original_start(now)
        if logical_layout[0]:
            overlay._displays = [(x, y, width, height)
                                 for _, x, y, width, height in logical_layout[0]]
        return result

    def set_geometry(*args):
        if len(args) == 1 and isinstance(args[0], QRect):
            geometry = QRect(args[0])
            if overlay._fixed_geometry and geometry.width() == overlay._desk.width():
                geometry.moveLeft(0)
                return original_geometry(geometry)
        return original_geometry(*args)

    def show():
        original_show()
        _empty_input_region(overlay)

    overlay.setGeometry, overlay.show, overlay._start = set_geometry, show, start
    overlay._relative = lambda x, y: (x - overlay._desk.x(), y - overlay._desk.y())
    _empty_input_region(overlay)

    for name in ("corner_region", "edge_region"):
        original = getattr(effect_module, name)

        def mapped(*args, _original=original):
            if not logical_layout[0]:
                return _original(*args)
            from core.return_edge import Rect
            rects = [Rect(x, y, width, height) for _, x, y, width, height in logical_layout[0]]
            if _original.__name__ == "corner_region":
                corner, edge, _, _, pointer = args
                return _original(corner, edge, rects, (0, 0), pointer)
            edge, _, _, pointer, part = args
            return _original(edge, rects, (0, 0), pointer, part)

        setattr(effect_module, name, mapped)


def run():
    upstream = Path("/app/share/beamer/win_app/effect_overlay_x11.py")
    sys.path.insert(0, str(upstream.parent))
    spec = importlib.util.spec_from_file_location("beamer_effect_overlay_x11", upstream)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    import effect_overlay
    from PySide6.QtGui import QGuiApplication

    logical_layout = [None]
    original_create, original_dispatch = module.create_overlays, module.dispatch

    def dispatch(command, overlay, glow, target, point_factory=None):
        screens, desk = command.get("screens"), command.get("desk")
        if screens and desk:
            logical_layout[0] = [[name, x - desk[0], y - desk[1], width, height]
                                 for name, x, y, width, height in screens]
            if "x" in command and "y" in command:
                mapped = dict(command)
                mapped["x"] = command["x"] - desk[0]
                mapped["y"] = command["y"] - desk[1]
                mapped["desk"] = [0, 0, target.width(), target.height()]
                command = mapped
        return original_dispatch(command, overlay, glow, target, point_factory)

    def create_overlays(on_failure=None):
        overlay, glow = original_create(on_failure=on_failure)
        _patch_overlay(overlay, effect_overlay, logical_layout)
        _empty_input_region(glow)
        return overlay, glow

    module.create_overlays, module.dispatch = create_overlays, dispatch
    sys.argv[0] = str(upstream)
    return module.run_helper()


if __name__ == "__main__":
    raise SystemExit(run())
