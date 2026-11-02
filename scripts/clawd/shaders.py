#!/usr/bin/env python3
"""Compile Clawd's shaders payload/clawd/shaders/<name>.frag into <name>.frag.qsb and record each source/package pair
in manifest.json (the installer refuses a package that does not match its source).
Usage: shaders.py [--check]  (--check exits 1 when a package or the manifest is missing or stale; it does not compile)"""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT/'payload/clawd/shaders'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    return sorted(SHADERS.glob('*.frag'))


def check():
    manifest = json.loads((SHADERS/'manifest.json').read_text()) if (SHADERS/'manifest.json').is_file() else {}
    stale = [s.name for s in sources() if not (SHADERS/(s.name + '.qsb')).is_file()
             or manifest.get(s.stem) != {'source_sha256': digest(s), 'package_sha256': digest(SHADERS/(s.name + '.qsb'))}]
    extra = sorted(set(manifest) - {s.stem for s in sources()})
    return stale + extra


def build():
    compiler = shutil.which('qsb') or '/usr/lib/qt6/bin/qsb'
    manifest = {}
    for source in sources():
        package = SHADERS/(source.name + '.qsb')
        subprocess.run([compiler, '--qt6', '-o', str(package), str(source)], check=True)
        manifest[source.stem] = {'source_sha256': digest(source), 'package_sha256': digest(package)}
    (SHADERS/'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    if '--check' in sys.argv[1:]:
        stale = check()
        if stale:
            print('clawd shaders out of date: ' + ', '.join(stale) + ' (run scripts/clawd/shaders.py)')
            sys.exit(1)
    else:
        build()
