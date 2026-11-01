#!/usr/bin/env python3
"""Release/update helpers for serpantinum-addons-v2 (stdlib only)."""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO = "Suiveurtag/serpantinum-addons-v2"
UPSTREAM_REPO = "ilyamiro/serpantinum"
CACHE_TTL = 3600
TIMEOUT = 5
UA = "serpantinum-addons-v2-updater"


# ---------------------------------------------------------------- paths
def _home() -> Path:
    return Path(os.path.expanduser("~"))


def _xdg_state() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or _home() / ".local" / "state")


def _xdg_data() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or _home() / ".local" / "share")


def state_dir() -> Path:
    return _xdg_state() / "serpantinum-addons-v2"


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------- versions
def parse_version(s) -> tuple:
    if not s:
        return ()
    m = re.match(r"\s*v?(\d+(?:\.\d+)*)", str(s))
    if not m:
        return ()
    return tuple(int(x) for x in m.group(1).split("."))


def compare(a, b) -> int:
    pa, pb = parse_version(a), parse_version(b)
    n = max(len(pa), len(pb))
    pa += (0,) * (n - len(pa))
    pb += (0,) * (n - len(pb))
    return (pa > pb) - (pa < pb)


def serpantinum_state() -> dict:
    home = Path(os.environ.get("SERPANTINUM_HOME") or _xdg_data() / "serpantinum")
    version = commit = None
    try:
        for line in (_xdg_state() / "serpantinum" / "version").read_text().splitlines():
            m = re.match(r'\s*([A-Z_]+)=(["\']?)(.*?)\2\s*$', line)
            if not m:
                continue
            if m.group(1) == "SERPANTINUM_VERSION":
                version = m.group(3) or None
            elif m.group(1) == "SERPANTINUM_COMMIT":
                commit = m.group(3) or None
    except OSError:
        pass
    if not version:
        try:
            version = (home / "version.txt").read_text().strip() or None
        except OSError:
            pass
    return {"version": version, "commit": commit, "home": str(home)}


# ---------------------------------------------------------------- install state
def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_install_state():
    try:
        d = json.loads((state_dir() / "install.json").read_text())
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def write_install_state(d: dict) -> None:
    _atomic_write(state_dir() / "install.json", json.dumps(d, indent=2) + "\n")


# ---------------------------------------------------------------- compat
def load_compat(path=None) -> dict:
    candidates = [Path(path)] if path else [_repo_root() / "compat.json", state_dir() / "compat.json"]
    for p in candidates:
        try:
            d = json.loads(p.read_text())
            if isinstance(d, dict):
                return d
        except (OSError, ValueError):
            continue
    return {}


def compat_status(serpantinum_version, compat) -> str:
    sv = parse_version(serpantinum_version)
    s = (compat or {}).get("serpantinum") or {}
    mn, tested = s.get("min"), s.get("tested")
    if not sv or not (mn or tested):
        return "unknown"
    if mn and compare(serpantinum_version, mn) < 0:
        return "too_old"
    if tested and compare(serpantinum_version, tested) > 0:
        return "newer_than_tested"
    return "ok"


# ---------------------------------------------------------------- network
class NotFound(RuntimeError):
    """HTTP 404 from GitHub (e.g. no release published yet)."""


def _default_fetch(url: str) -> bytes:
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "application/vnd.github+json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise NotFound("HTTP error 404 while contacting GitHub") from e
        if e.code == 403 and e.headers.get("X-RateLimit-Remaining") == "0":
            raise RuntimeError("GitHub rate limit reached, try again later") from e
        raise RuntimeError(f"HTTP error {e.code} while contacting GitHub") from e
    except (urllib.error.URLError, OSError) as e:
        raise RuntimeError("Offline or GitHub unreachable") from e


def _cache_path() -> Path:
    return state_dir() / "release-cache.json"


def _read_cache() -> dict:
    try:
        d = json.loads(_cache_path().read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_cache(d: dict) -> None:
    try:
        _atomic_write(_cache_path(), json.dumps(d))
    except OSError:
        pass


def _fresh(entry, force) -> bool:
    return (
        not force
        and isinstance(entry, dict)
        and time.time() - entry.get("at", 0) < CACHE_TTL
    )


def latest_release(force=False, fetch=None) -> dict:
    cache = _read_cache()
    if _fresh(cache.get("release"), force):
        return cache["release"]["data"]
    fetch = fetch or _default_fetch
    try:
        raw = fetch(f"https://api.github.com/repos/{REPO}/releases/latest")
    except NotFound:
        raw = None
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raw = None
        else:
            raise RuntimeError(f"HTTP error {e.code} while contacting GitHub") from e
    if raw is None:
        data: dict = {}
    else:
        j = json.loads(raw)
        tag = j.get("tag_name") or ""
        try:
            compat = json.loads(
                fetch(f"https://raw.githubusercontent.com/{REPO}/{tag}/compat.json")
            )
        except Exception:
            compat = {}
        data = {
            "tag": tag,
            "version": ".".join(map(str, parse_version(tag))),
            "url": j.get("html_url"),
            "notes": j.get("body") or "",
            "compat": compat if isinstance(compat, dict) else {},
        }
    cache["release"] = {"at": time.time(), "data": data}
    _write_cache(cache)
    return data


def upstream_latest_version(fetch=None):
    cache = _read_cache()
    if _fresh(cache.get("upstream"), False):
        return cache["upstream"]["data"]
    fetch = fetch or _default_fetch
    try:
        v = fetch(
            f"https://raw.githubusercontent.com/{UPSTREAM_REPO}/master/version.txt"
        ).decode().strip() or None
    except Exception:
        return None
    cache["upstream"] = {"at": time.time(), "data": v}
    _write_cache(cache)
    return v


# ---------------------------------------------------------------- check
def _local_version(inst):
    if inst and inst.get("version"):
        return inst["version"]
    try:
        return (_repo_root() / "VERSION").read_text().strip() or None
    except OSError:
        return None


def check(force=False, fetch=None) -> dict:
    inst = read_install_state()
    ss = serpantinum_state()
    local = _local_version(inst)
    inst_sv = (inst or {}).get("serpantinum_version")
    out = {
        "state": "up_to_date",
        "local": local,
        "remote": None,
        "serpantinum": ss["version"],
        "compat": compat_status(ss["version"], load_compat()),
        "notes_url": None,
        "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "error": None,
    }
    if not inst:
        out["state"] = "not_installed"
        return out
    out["compat"] = compat_status(ss["version"], load_compat(state_dir() / "compat.json")
                                  if (state_dir() / "compat.json").exists() else None)
    if (inst.get("serpantinum_version") != ss["version"]
            or inst.get("serpantinum_commit") != ss["commit"]):
        out["state"] = "reinstall_needed"
        return out
    try:
        rel = latest_release(force=force, fetch=fetch)
    except Exception as e:
        out["state"] = "error"
        out["error"] = str(e) or e.__class__.__name__
        stale = _read_cache().get("release", {}).get("data") or {}
        out["remote"] = stale.get("version")
        out["notes_url"] = stale.get("url")
        return out
    out["remote"] = rel.get("version")
    out["notes_url"] = rel.get("url")
    newer = bool(rel) and compare(rel.get("version"), local) > 0
    if newer:
        up = upstream_latest_version(fetch=fetch)
        rmin = ((rel.get("compat") or {}).get("serpantinum") or {}).get("min")
        if up and compare(up, inst_sv) > 0:
            out["state"] = "serpantinum_outdated"
        elif rmin and compare(rmin, inst_sv) > 0:
            out["state"] = "incompatible"
        else:
            out["state"] = "available"
    elif inst.get("channel") == "dev":
        out["state"] = "dev"
    return out


# ---------------------------------------------------------------- CLI
def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    try:
        cmd = argv[0] if argv else "check"
        if cmd == "version":
            print(_local_version(read_install_state()) or "")
        elif cmd == "source":
            # Checkout the addons were installed from (dev clone or managed source).
            print((read_install_state() or {}).get("source") or "")
        else:
            print(json.dumps(check(force="--force" in argv)))
    except Exception as e:  # never a traceback: QML parses stdout
        print(json.dumps({"state": "error", "local": None, "remote": None,
                          "serpantinum": None, "compat": "unknown",
                          "notes_url": None, "checked_at": None,
                          "error": str(e) or e.__class__.__name__}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
