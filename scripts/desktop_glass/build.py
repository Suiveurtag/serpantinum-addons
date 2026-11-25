#!/usr/bin/env python3
"""Build the optional QML capture module on first use; print its QML entry point."""
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parent
cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'serpantinum-addons-v2' / 'desktop-glass'
cache.mkdir(parents=True, exist_ok=True, mode=0o700)
try:
    qt_version = subprocess.check_output(['pkg-config', '--modversion', 'Qt6Core'], text=True).strip()
    digest = hashlib.sha256(qt_version.encode())
    for file in sorted(source.iterdir()):
        if file.is_file():
            digest.update(file.name.encode())
            digest.update(file.read_bytes())
    target = cache / digest.hexdigest()[:20]
    with (cache / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not (target / 'desktopcapture' / 'libdesktopcapture.so').is_file():
            with tempfile.TemporaryDirectory(prefix='build-', dir=cache) as temp:
                build = Path(temp) / 'build'
                subprocess.run(['cmake', '-S', str(source), '-B', str(build), '-DCMAKE_BUILD_TYPE=Release'], check=True, stdout=sys.stderr)
                subprocess.run(['cmake', '--build', str(build), '--parallel', '2'], check=True, stdout=sys.stderr)
                staged = Path(temp) / 'module'
                plugin = staged / 'desktopcapture'
                plugin.mkdir(parents=True)
                shutil.copy2(build / 'libdesktopcapture.so', plugin)
                (plugin / 'qmldir').write_text('module desktopcapture\nplugin desktopcapture\n')
                (staged / 'CaptureView.qml').write_text('import QtQuick\nimport "desktopcapture"\nDesktopCapture {}\n')
                if target.exists(): shutil.rmtree(target)
                os.replace(staged, target)
    print(target / 'CaptureView.qml')
except (OSError, subprocess.CalledProcessError) as error:
    print(f'Desktop glass capture unavailable: {error}', file=sys.stderr)
    sys.exit(1)
