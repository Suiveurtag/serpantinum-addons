"""Terminal manager for serpantinum-addons-v2 (stdlib only)."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ISSUES_URL = "https://github.com/Suiveurtag/serpantinum-addons/issues"
SERPANTINUM_URL = "https://github.com/ilyamiro/serpantinum"

_release = None


def release():
    """Load scripts/addons_release.py (the shared release/state API)."""
    global _release
    if _release is None:
        path = REPO_ROOT / "scripts" / "addons_release.py"
        spec = importlib.util.spec_from_file_location("addons_release", path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules["addons_release"] = mod
        spec.loader.exec_module(mod)
        _release = mod
    return _release


def local_version() -> str:
    try:
        return (REPO_ROOT / "VERSION").read_text().strip() or "0.0.0"
    except OSError:
        return "0.0.0"
