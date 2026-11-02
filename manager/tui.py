"""Serpantinum Addons terminal UI: peach/mauve/teal serpent identity (stdlib only)."""
from __future__ import annotations

import atexit
import contextlib
import os
import re
import select as _select
import shutil
import signal
import sys
import threading
import time

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

# kind -> (truecolor rgb, 256-color code); Catppuccin: peach, mauve, teal, overlay
PALETTE = {
    "accent": ((250, 179, 135), 216),  # peach #fab387
    "mauve": ((203, 166, 247), 183),   # #cba6f7
    "teal": ((148, 226, 213), 116),    # #94e2d5
    "dim": ((108, 112, 134), 243),     # #6c7086
    "ok": ((148, 226, 213), 116),
    "err": ((243, 139, 168), 211),
    "warn": ((249, 226, 175), 223),
}
GRAD = ("accent", "mauve")  # gradient endpoints


def lerp_rgb(a, b, t: float):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))

SERPENT_LEN = 10

MIN_BOX = 12
MAX_BOX = 64


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def vlen(s: str) -> int:
    """Visible width (every glyph used here is single-width)."""
    return len(strip_ansi(s))


def fit(text: str, width: int) -> str:
    """Truncate plain text to width, ending with an ellipsis."""
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    return text[: max(width - 1, 0)] + "…"


def detect_color_mode(environ, isatty: bool) -> str:
    """'truecolor' | '256' | 'none'."""
    if environ.get("NO_COLOR"):
        return "none"
    if not isatty or environ.get("TERM") == "dumb":
        return "none"
    if environ.get("COLORTERM", "").lower() in ("truecolor", "24bit"):
        return "truecolor"
    return "256"


def format_error(what: str, why: str = "", hint: str = "", log=None, issues=None) -> list:
    """Plain lines for a failure: what happened / why / what to do / log / issues."""
    lines = [f"✗ {what}"]
    if why:
        lines += [f"  {x}" for x in str(why).splitlines()]
    if hint:
        hl = str(hint).splitlines()
        lines.append(f"  → {hl[0]}")
        lines += [f"    {x}" for x in hl[1:]]
    if log:
        lines.append(f"  log: {log}")
    if issues:
        lines.append(f"  issues: {issues}")
    return lines


def decode_key(buf: bytes) -> str:
    """Map raw bytes to a key name."""
    if buf in (b"\r", b"\n"):
        return "enter"
    if buf == b" ":
        return "space"
    if buf == b"\x03":
        raise KeyboardInterrupt
    if buf in (b"\x04", b"\x1b"):
        return "esc"
    if buf in (b"\x7f", b"\x08"):
        return "backspace"
    if buf[:1] == b"\x1b":
        tail = buf[1:]
        if tail in (b"[A", b"OA"):
            return "up"
        if tail in (b"[B", b"OB"):
            return "down"
        if tail in (b"[C", b"OC"):
            return "right"
        if tail in (b"[D", b"OD"):
            return "left"
        return "esc"
    try:
        return buf.decode("utf-8")
    except UnicodeDecodeError:
        return ""


def read_key(fd: int) -> str:
    buf = os.read(fd, 1)
    if not buf:
        return "esc"
    if buf == b"\x1b":
        # escape sequence? wait briefly for the rest
        while _select.select([fd], [], [], 0.05)[0]:
            more = os.read(fd, 1)
            if not more:
                break
            buf += more
            if more.isalpha() or more == b"~":
                break
    elif buf[0] >= 0xC0:  # UTF-8 lead byte
        need = 1 if buf[0] < 0xE0 else 2 if buf[0] < 0xF0 else 3
        buf += os.read(fd, need)
    return decode_key(buf)


@contextlib.contextmanager
def raw_mode(fd: int):
    """cbreak mode with guaranteed restore (finally + atexit + SIGTERM)."""
    import termios
    import tty

    old = termios.tcgetattr(fd)

    def restore():
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except Exception:
            pass

    atexit.register(restore)
    prev_term = None
    try:
        prev_term = signal.signal(signal.SIGTERM, lambda *_: (restore(), sys.exit(143)))
    except (ValueError, OSError):
        pass
    try:
        tty.setcbreak(fd)
        yield
    finally:
        restore()
        atexit.unregister(restore)
        if prev_term is not None:
            try:
                signal.signal(signal.SIGTERM, prev_term)
            except (ValueError, OSError):
                pass


class Spinner:
    """Context manager: animated line with elapsed seconds, static when not a TTY."""

    def __init__(self, ui, label: str, interval: float = 0.07):
        self.ui = ui
        self.label = label
        self.interval = interval
        self._stop = threading.Event()
        self._thread = None
        self._start = 0.0
        self._result = None

    def __enter__(self):
        self._start = time.monotonic()
        if self.ui.animated:
            self.ui.write("\x1b[?25l")
            self._thread = threading.Thread(target=self._run, daemon=True)
            self._thread.start()
        else:
            self.ui.println(f"{self.ui.sym['step']} {self.label}…")
        return self

    def set_label(self, label: str) -> None:
        self.label = label

    def done(self, kind: str, text: str) -> None:
        """Replace the spinner by a final status line (ok / warn / err)."""
        self._result = (kind, text)

    @property
    def elapsed(self) -> int:
        return int(time.monotonic() - self._start)

    def _run(self) -> None:
        i = 0
        while not self._stop.is_set():
            frame = self.ui.serpent(i)
            tail = f" ({self.elapsed}s)"
            room = max(self.ui.columns - SERPENT_LEN - 2 - len(tail), 8)
            line = (frame + " " + fit(self.label, room)
                    + self.ui.paint(tail, "dim"))
            self.ui.write("\r\x1b[2K" + line)
            i += 1
            self._stop.wait(self.interval)

    def __exit__(self, exc_type, exc, tb):
        self._stop.set()
        if self._thread:
            self._thread.join()
            self.ui.write("\r\x1b[2K\x1b[?25h")
        if self._result and exc_type is None:
            self.ui.status(*self._result)
        return False


class UI:
    def __init__(self, out=None, inp=None, environ=None, isatty=None, columns=None):
        self.out = out if out is not None else sys.stdout
        self.inp = inp if inp is not None else sys.stdin
        self.environ = os.environ if environ is None else environ
        if isatty is None:
            self.out_tty = bool(getattr(self.out, "isatty", lambda: False)())
            self.interactive = self.out_tty and bool(getattr(self.inp, "isatty", lambda: False)())
        else:
            self.out_tty = self.interactive = bool(isatty)
        self._columns = columns
        self.color = detect_color_mode(self.environ, self.out_tty)
        enc = (getattr(self.out, "encoding", None) or "utf-8").lower()
        self.unicode = "utf" in enc and self.environ.get("TERM") != "linux"
        self.sym = {
            "cursor": "▸" if self.unicode else ">",
            "step": "◆" if self.unicode else "*",
            "child": "›" if self.unicode else ">",
            "dot": "●" if self.unicode else "o",
            "track": "·" if self.unicode else ".",
            "ask": "◇" if self.unicode else "?",
            "on": "◉" if self.unicode else "[x]",
            "off": "◯" if self.unicode else "[ ]",
        }

    # ------------------------------------------------------------ basics
    @property
    def columns(self) -> int:
        if self._columns:
            return self._columns
        return shutil.get_terminal_size((80, 24)).columns

    @property
    def animated(self) -> bool:
        return self.out_tty and self.environ.get("TERM") != "dumb"

    def paint(self, text: str, kind=None, bold: bool = False) -> str:
        if self.color == "none" or not text or (kind is None and not bold):
            return text
        codes = []
        if bold:
            codes.append("1")
        if kind:
            rgb, c256 = PALETTE[kind]
            codes.append("38;2;%d;%d;%d" % rgb if self.color == "truecolor" else f"38;5;{c256}")
        return f"\x1b[{';'.join(codes)}m{text}\x1b[0m"

    def gradient(self, text: str, phase: float = 0.0, bold: bool = False) -> str:
        """Peach -> mauve sweep over text (phase shifts it); plain/accent when no truecolor."""
        if self.color == "none" or not text:
            return text
        if self.color != "truecolor":
            return self.paint(text, "accent", bold)
        n = max(len(text) - 1, 1)
        a, b = PALETTE[GRAD[0]][0], PALETTE[GRAD[1]][0]
        out = []
        for i, ch in enumerate(text):
            t = abs(((i / n + phase) % 2.0) - 1.0)  # ping-pong 0..1
            r, g, bl = lerp_rgb(a, b, t)
            out.append(f"\x1b[{'1;' if bold else ''}38;2;{r};{g};{bl}m{ch}")
        return "".join(out) + "\x1b[0m"

    def serpent(self, i: int) -> str:
        """One frame of the slithering serpent: ·~~~● moving along a short track."""
        L = SERPENT_LEN
        period = 2 * (L - 1)
        k = i % period
        h = k if k < L else period - k
        d = 1 if k < L else -1
        cells = [self.paint(self.sym["track"], "dim")] * L
        for j in (3, 2, 1):
            pos = h - d * j
            if 0 <= pos < L:
                cells[pos] = self.paint("~", "mauve" if j > 1 else "accent")
        cells[h] = self.paint(self.sym["dot"], "accent", bold=True)
        return "".join(cells)

    def bar(self, frac: float, width: int = 20) -> str:
        """Gradient progress bar (plain: [####....])."""
        frac = min(max(frac, 0.0), 1.0)
        full = int(round(frac * width))
        if self.color == "none":
            return "[" + "#" * full + "." * (width - full) + "]"
        fill = self.gradient("█" * full) if full else ""
        return fill + self.paint("░" * (width - full), "dim")

    def celebrate(self, text: str) -> None:
        """Short sparkle sweep (<1 s) ending on a teal check line; static when not animated."""
        line = f"✓ {text}"
        if not (self.animated and self.color != "none" and self.unicode):
            self.println(self.paint("✓", "ok") + " " + text)
            return
        spark = "✦"
        n = min(len(line), max(self.columns - 2, 8))
        self.write("\x1b[?25l")
        try:
            for pos in range(0, n + 1, max(n // 14, 1)):
                shown = line[:pos]
                self.write("\r\x1b[2K" + self.paint(shown, "ok")
                           + self.gradient(spark, 0.0, bold=True))
                time.sleep(0.03)
        finally:
            self.write("\r\x1b[2K\x1b[?25h")
        self.println(self.paint("✓", "ok") + " " + text)

    def write(self, s: str) -> None:
        self.out.write(s)
        self.out.flush()

    def println(self, s: str = "") -> None:
        self.write(s + "\n")

    # ------------------------------------------------------------ blocks
    def box_lines(self, rows, phase: float = 0.0) -> list:
        """rows: list of (plain_text, kind|None, bold). Rounded box, adapts to width."""
        width = max(MIN_BOX, min(self.columns, MAX_BOX))
        inner = width - 4
        top = self.paint("╭" + "─" * (width - 2) + "╮", "accent")
        bot = self.paint("╰" + "─" * (width - 2) + "╯", "accent")
        edge = self.paint("│", "accent")
        out = [top]
        for text, kind, bold in rows:
            text = fit(text, inner)
            pad = " " * (inner - len(text))
            body = self.gradient(text, phase, bold) if kind == "grad" else self.paint(text, kind, bold)
            out.append(f"{edge} {body}{pad} {edge}")
        out.append(bot)
        return out

    def header(self, current, target, serpantinum, compat) -> None:
        cur = current or "not installed"
        rows = [
            ("~~◆ serpantinum addons", "grad", True),
            (f"{cur} → {target}", None, False),
            (f"Serpantinum {serpantinum or 'not found'} · compat {compat}", "dim", False),
        ]
        self.println()
        lines = self.box_lines(rows)
        if self.animated and self.color == "truecolor":
            # short gradient sweep over the wordmark row (~400 ms), then the final frame
            self.println(lines[0])
            for k in range(8):
                self.write("\r\x1b[2K" + self.box_lines(rows, k / 8.0)[1])
                time.sleep(0.05)
            self.write("\r\x1b[2K")
            for line in lines[1:]:
                self.println(line)
        else:
            for line in lines:
                self.println(line)
        self.println()

    def step(self, title: str) -> None:
        self.println(self.paint(self.sym["step"], "accent") + " " + self.paint(title, bold=True))

    def child(self, detail: str, kind=None) -> None:
        lines = str(detail).splitlines() or [""]
        self.println(self.paint("  " + self.sym["child"] + "  ", "mauve") + self.paint(lines[0], kind))
        for extra in lines[1:]:
            self.println("     " + self.paint(extra, kind))

    def status(self, kind: str, text: str) -> None:
        mark = {"ok": "✓", "warn": "!", "err": "✗"}.get(kind, "·")
        self.println(self.paint(mark, kind) + " " + text)

    def hint(self, text: str) -> None:
        self.println(self.paint(text, "dim"))

    def error(self, what, why="", hint="", log=None, issues=None) -> None:
        lines = format_error(what, why, hint, log, issues)
        self.println(self.paint(lines[0], "err"))
        for line in lines[1:]:
            if line.lstrip().startswith("→"):
                self.println(self.paint(line, "accent"))
            elif line.lstrip().startswith(("log:", "issues:")):
                self.println(self.paint(line, "dim"))
            else:
                self.println(line)

    def spinner(self, label: str) -> Spinner:
        return Spinner(self, label)

    # ------------------------------------------------------------ input
    def _readline(self):
        line = self.inp.readline()
        return None if line == "" else line.strip()

    def confirm(self, prompt: str, default: bool = True) -> bool:
        suffix = "[Y/n]" if default else "[y/N]"
        self.write(f"{self.paint(self.sym['ask'], 'accent')} {prompt} {self.paint(suffix, 'dim')} ")
        ans = self._readline()
        if ans is None:
            self.println()
            return default
        ans = ans.lower()
        if not ans:
            return default
        return ans in ("y", "yes", "o", "oui")

    def ask(self, prompt: str):
        self.write(f"{self.paint(self.sym['ask'], 'accent')} {prompt} ")
        return self._readline()

    def _option_lines(self, options, cursor, marks=None):
        width = max(self.columns - 1, MIN_BOX)
        lines = []
        for i, opt in enumerate(options):
            label, hint = opt[1], (opt[-1] if len(opt) > 2 and isinstance(opt[-1], str) else "")
            sel = i == cursor
            num = f"{i + 1}. "
            if marks is not None:
                box = self.sym["on"] if marks[i] else self.sym["off"]
                body = fit(f"{box} {label}", width - 4)
                head = (self.paint(self.sym["cursor"], "accent") + " ") if sel else "  "
                text = self.paint(body, "accent" if marks[i] else None, bold=sel)
            else:
                body = fit(num + label, width - 4)
                head = (self.paint(self.sym["cursor"], "accent") + " ") if sel else "  "
                text = self.paint(body, "accent" if sel else None, bold=sel)
            line = head + text
            if hint and vlen(line) + len(hint) + 3 < width:
                line += self.paint("  " + hint, "dim")
            lines.append(line)
        return lines

    def _menu_loop(self, title, options, cursor, marks, footer):
        fd = self.inp.fileno()
        self.step(title)
        first = True
        n = len(options) + 1
        self.write("\x1b[?25l")
        try:
            with raw_mode(fd):
                while True:
                    if not first:
                        self.write(f"\x1b[{n}A")
                    first = False
                    for line in self._option_lines(options, cursor, marks):
                        self.write("\r\x1b[2K" + line + "\n")
                    self.write("\r\x1b[2K" + self.paint(fit(footer, self.columns - 1), "dim") + "\n")
                    key = read_key(fd)
                    if key in ("up", "k"):
                        cursor = (cursor - 1) % len(options)
                    elif key in ("down", "j"):
                        cursor = (cursor + 1) % len(options)
                    elif key in ("q", "esc"):
                        return "cancel", cursor
                    elif key == "enter":
                        return "enter", cursor
                    elif key == "space" and marks is not None:
                        marks[cursor] = not marks[cursor]
                    elif key.isdigit() and 1 <= int(key) <= len(options):
                        cursor = int(key) - 1
                        if marks is None:
                            return "enter", cursor
                        marks[cursor] = not marks[cursor]
        finally:
            self.write(f"\x1b[{n}A\r\x1b[J\x1b[?25h")

    def select(self, title: str, options, default: int = 0):
        """options: [(value, label[, hint])]. Returns value, or None if cancelled."""
        default = default if 0 <= default < len(options) else 0
        if not self.interactive:
            return self._select_numbered(title, options, default)
        mode, idx = self._menu_loop(
            title, options, default, None, "↑↓ move · enter select · 1-9 jump · q quit")
        if mode == "cancel":
            self.child("cancelled", "dim")
            return None
        self.child(options[idx][1])
        return options[idx][0]

    def multiselect(self, title: str, options):
        """options: [(value, label, checked[, hint])]. Returns list of values, None if cancelled."""
        marks = [bool(o[2]) for o in options]
        view = [(o[0], o[1]) + ((o[3],) if len(o) > 3 else ()) for o in options]
        if not self.interactive:
            return self._multiselect_numbered(title, view, marks)
        mode, _ = self._menu_loop(
            title, view, 0, marks, "↑↓ move · space toggle · enter confirm · q quit")
        if mode == "cancel":
            self.child("cancelled", "dim")
            return None
        chosen = [o[0] for o, m in zip(options, marks) if m]
        names = [o[1] for o, m in zip(options, marks) if m]
        self.child(", ".join(names) if names else "none")
        return chosen

    # numbered fallback (no TTY)
    def _select_numbered(self, title, options, default):
        self.step(title)
        for i, o in enumerate(options):
            self.println(f"  {i + 1}) {o[1]}")
        while True:
            self.write(f"  choose [{default + 1}]: ")
            ans = self._readline()
            if ans is None:
                self.println()
                return None
            if not ans:
                return options[default][0]
            if ans.lower() in ("q", "quit"):
                return None
            if ans.isdigit() and 1 <= int(ans) <= len(options):
                return options[int(ans) - 1][0]
            self.println("  please enter a number from the list")

    def _multiselect_numbered(self, title, options, marks):
        self.step(title)
        for i, o in enumerate(options):
            self.println(f"  {i + 1}) [{'x' if marks[i] else ' '}] {o[1]}")
        default = ",".join(str(i + 1) for i, m in enumerate(marks) if m)
        while True:
            self.write(f"  numbers separated by commas, 'none' for nothing [{default}]: ")
            ans = self._readline()
            if ans is None:
                self.println()
                return None
            if not ans:
                return [o[0] for o, m in zip(options, marks) if m]
            if ans.lower() in ("q", "quit"):
                return None
            if ans.lower() == "none":
                return []
            parts = [p for p in re.split(r"[,\s]+", ans) if p]
            if all(p.isdigit() and 1 <= int(p) <= len(options) for p in parts):
                return [options[int(p) - 1][0] for p in dict.fromkeys(parts)]
            self.println("  please enter numbers from the list")
