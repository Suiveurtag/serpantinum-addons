"""Build and run the pinned Snowhush engine with Serpantinum's surface bridge."""

import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

REPO = "https://github.com/mbezruchko/Snowhush.git"
TAG = "v0.14.0"
COMMIT = "38ef2982ec8cd3ad6f8a70cb3bbbef1efd79bed1"
PATCH = Path(__file__).with_name("serpantinum.patch")


def xdg(name, fallback):
    path = Path(os.environ.get(name, ""))
    return path if path.is_absolute() else Path.home() / fallback


def build_key():
    return f"{TAG}-{hashlib.sha256(PATCH.read_bytes()).hexdigest()[:12]}"


def run_build(args, log, **kwargs):
    with subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, **kwargs) as process:
        try:
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
                run_build(["git", "clone", "--quiet", "--depth", "1", "--branch", TAG, REPO, str(source)], log)
                revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
                if revision != COMMIT:
                    raise ValueError("Snowhush release revision mismatch.")
                run_build(["git", "-C", str(source), "apply", "--whitespace=nowarn", str(PATCH)], log)
                target = cache / "target"
                env = dict(os.environ, CARGO_TARGET_DIR=str(target))
                run_build([
                    required["cargo"], "rustc", "--locked", "--release",
                    "--manifest-path", str(source / "linux/Cargo.toml"),
                    "--", "-C", "lto=thin", "-C", "codegen-units=8",
                ], log, env=env)
                folder.mkdir(exist_ok=True)
                shutil.copy2(source / "LICENSE", folder / "LICENSE")
                notices = source / "Resources/ThirdParty"
                if notices.is_dir():
                    shutil.copytree(notices, folder / "ThirdParty", dirs_exist_ok=True)
                staging = Path(temporary) / "snowhush"
                shutil.copy2(target / "release/snowhush", staging)
                staging.replace(binary)
                shutil.rmtree(target, ignore_errors=True)
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
