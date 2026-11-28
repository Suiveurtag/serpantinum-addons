"""Build and run the pinned Snowhush engine with Serpantinum's surface bridge."""

import fcntl
import hashlib
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = "https://github.com/mbezruchko/Snowhush.git"
TAG = "v0.14.0"
COMMIT = "38ef2982ec8cd3ad6f8a70cb3bbbef1efd79bed1"
PATCH = Path(__file__).with_name("serpantinum.patch")


def xdg(name, fallback):
    path = Path(os.environ.get(name, ""))
    return path if path.is_absolute() else Path.home() / fallback


def build_key():
    return f"{TAG}-{hashlib.sha256(PATCH.read_bytes()).hexdigest()[:12]}"


class Progress:
    """Tells the shell how the build goes, one `SNOWHUSH_PROGRESS stage done total detail` line per change."""

    def __init__(self):
        self.last = None
        self.said_at = 0.0

    def __call__(self, stage, done=0, total=0, detail=""):
        detail = " ".join(str(detail).split())[:80]
        key = (stage, done, total)
        now = time.monotonic()
        if key == self.last and now - self.said_at < 0.5:
            return
        self.last, self.said_at = key, now
        print(f"SNOWHUSH_PROGRESS {stage} {done} {total} {detail}".rstrip(), flush=True)


GIT_PROGRESS = re.compile(r"(Receiving objects|Resolving deltas):\s+\d+% \((\d+)/(\d+)\)")
CARGO_PROGRESS = re.compile(r"Building \[[^\]]*\]\s+(\d+)/(\d+)(?::\s*(.*))?")
CARGO_FETCH = re.compile(r"Download(?:ing|ed)\s+(.*)")


def git_reader(say):
    def read(segment):
        match = GIT_PROGRESS.search(segment)
        if match:
            say("fetch", int(match[2]), int(match[3]), match[1].lower())
    return read


def cargo_reader(say):
    def read(segment):
        match = CARGO_PROGRESS.search(segment)
        if match:
            done, total = int(match[1]), int(match[2])
            crates = (match[3] or "").strip()
            first = crates.split(",")[0].strip()
            # The last unit is the engine itself: a long thin-LTO link with nothing to count.
            linking = total > 0 and done >= total - 1 and "(bin)" in crates
            say("link" if linking else "compile", done, total, first)
            return
        match = CARGO_FETCH.search(segment)
        if match:
            say("crates", 0, 0, match[1])
    return read


def lower_priority():
    os.nice(10)


def run_build(args, log, reader=None, **kwargs):
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
                          preexec_fn=lower_priority, **kwargs) as process:
        try:
            pending = b""
            while chunk := os.read(process.stdout.fileno(), 65536):
                log.write(chunk.decode("utf-8", "replace"))
                log.flush()
                if reader:
                    *segments, pending = re.split(rb"[\r\n]", pending + chunk)
                    for segment in segments:
                        reader(segment.decode("utf-8", "replace"))
            if reader and pending:
                reader(pending.decode("utf-8", "replace"))
            if process.wait():
                raise subprocess.CalledProcessError(process.returncode, args)
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
            raise


def install(cache):
    folder = cache / build_key()
    binary = folder / "snowhush"
    if binary.is_file() and os.access(binary, os.X_OK):
        return binary

    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if binary.is_file() and os.access(binary, os.X_OK):
            return binary
        say = Progress()
        print("SNOWHUSH_BUILD", flush=True)
        say("tools")
        required = {name: shutil.which(name) for name in ("git", "cargo", "curl", "cc", "pkg-config")}
        if not required["cargo"]:
            cargo = Path.home() / ".cargo/bin/cargo"
            if os.access(cargo, os.X_OK):
                required["cargo"] = str(cargo)
        missing = [name for name, path in required.items() if not path]
        if missing:
            raise ValueError("Install the Snowhush build tools: " + ", ".join(missing) + ".")
        if subprocess.run(["pkg-config", "--exists", "wayland-client", "wayland-egl"], check=False).returncode:
            raise ValueError("Install the Wayland development libraries (wayland-devel on Fedora).")

        log_path = cache / "build.log"
        try:
            with tempfile.TemporaryDirectory(dir=cache) as temporary, log_path.open("w", encoding="utf-8") as log:
                source = Path(temporary) / "source"
                say("fetch")
                run_build(["git", "clone", "--progress", "--depth", "1", "--branch", TAG, REPO, str(source)], log,
                          git_reader(say))
                revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
                if revision != COMMIT:
                    raise ValueError("Snowhush release revision mismatch.")
                say("patch")
                run_build(["git", "-C", str(source), "apply", "--whitespace=nowarn", str(PATCH)], log)
                target = cache / "target"
                env = dict(os.environ, CARGO_TARGET_DIR=str(target), CARGO_TERM_COLOR="never",
                           CARGO_TERM_PROGRESS_WHEN="always", CARGO_TERM_PROGRESS_WIDTH="200")
                say("crates")
                run_build([
                    required["cargo"], "rustc", "--locked", "--release",
                    "--manifest-path", str(source / "linux/Cargo.toml"),
                    "--", "-C", "lto=thin", "-C", "codegen-units=8",
                ], log, cargo_reader(say), env=env)
                say("install")
                folder.mkdir(exist_ok=True)
                shutil.copy2(source / "LICENSE", folder / "LICENSE")
                notices = source / "Resources/ThirdParty"
                if notices.is_dir():
                    shutil.copytree(notices, folder / "ThirdParty", dirs_exist_ok=True)
                staging = Path(temporary) / "snowhush"
                shutil.copy2(target / "release/snowhush", staging)
                staging.replace(binary)
                shutil.rmtree(target, ignore_errors=True)
                # Engines built from an earlier patch or release are never run again.
                for old in cache.glob("v*-*"):
                    if old.is_dir() and old != folder:
                        shutil.rmtree(old, ignore_errors=True)
        except subprocess.CalledProcessError as error:
            raise ValueError(f"Snowhush build failed. See {log_path}.") from error
    return binary


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise ValueError("Snow Hush requires a Wayland session.")
    if not shutil.which("dbus-send"):
        raise ValueError("Install dbus-send (dbus-tools on Fedora) to connect Snowhush to the shell.")
    state = xdg("XDG_STATE_HOME", ".local/state") / "serpantinum-addons-v2" / "snowhush"
    cache = xdg("XDG_CACHE_HOME", ".cache") / "serpantinum-addons-v2" / "snowhush"
    binary = install(cache)
    env = dict(os.environ, XDG_CONFIG_HOME=str(state), XDG_STATE_HOME=str(state), XDG_CACHE_HOME=str(cache))
    print("SNOWHUSH_ENGINE_STARTING", flush=True)
    os.execve(binary, [str(binary)], env)


def cancelled(_signal, _frame):
    raise SystemExit(143)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, cancelled)
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"Snow Hush: {error}")
