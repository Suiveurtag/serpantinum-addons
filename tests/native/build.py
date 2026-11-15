#!/usr/bin/env python3
"""Build isolated input fixtures from the protocols downloaded by Niri's Cargo build."""
import glob
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
output = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    sources = []
    for name, pattern in [('virtual-keyboard-unstable-v1', 'wayland-protocols-misc-*/protocols/virtual-keyboard-unstable-v1.xml'),
                          ('wlr-virtual-pointer-unstable-v1', 'wayland-protocols-wlr-*/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml')]:
        matches = sorted(glob.glob(str(Path.home() / '.cargo/registry/src/*' / pattern)))
        if not matches:
            raise SystemExit('Build Niri first to obtain its Wayland test protocols')
        protocol = matches[-1]
        subprocess.run(['wayland-scanner', 'client-header', protocol, str(temp / (name+'-client-protocol.h'))], check=True)
        source = temp / (name+'.c'); sources.append(str(source))
        subprocess.run(['wayland-scanner', 'private-code', protocol, str(source)], check=True)
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'wayland-client', 'xkbcommon'], text=True).split()
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I'+str(temp), str(here/'niri_input.c'), *sources, *flags, '-o', str(output)], check=True)
