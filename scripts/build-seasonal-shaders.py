#!/usr/bin/env python3
"""Compile the seasonal and Capri shaders and record each exact source/package pair."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHADERS = [(ROOT/'payload/seasonal/shaders', 'atmosphere'), (ROOT/'payload/capri/shaders', 'sprite')]


def build(folder, stem):
    compiler = shutil.which('qsb') or '/usr/lib/qt6/bin/qsb'
    source = folder/(stem + '.frag')
    package = folder/(stem + '.frag.qsb')
    subprocess.run([compiler, '--qt6', '-o', str(package), str(source)], check=True)
    manifest = {
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'package_sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
    }
    (folder/'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    for shader in SHADERS: build(*shader)
