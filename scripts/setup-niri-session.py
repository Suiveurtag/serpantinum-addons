#!/usr/bin/env python3
"""Expose the installed local Niri build and its session without replacing existing launchers."""
import os
from pathlib import Path
from beamer.setup import desktop_quote

home = Path.home()
binary = home / '.local/opt/niri-serpantinum/bin/niri'
script = home / '.local/share/serpantinum-addons-v2/scripts/niri-session.sh'
if not binary.is_file() or not script.is_file():
    raise SystemExit('Build the local compositor and deploy the addons first')
for name, target in [('niri', binary), ('niri-serpantinum-session', script)]:
    link = home / '.local/bin' / name
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink() and link.resolve() == target.resolve():
        continue
    if link.exists() or link.is_symlink():
        raise SystemExit(f'Existing launcher preserved: {link}')
    link.symlink_to(target)
entry = home / '.local/share/wayland-sessions/niri-serpantinum.desktop'
entry.parent.mkdir(parents=True, exist_ok=True)
content = ('[Desktop Entry]\nName=Niri (Serpantinum + addons)\nComment=Scrollable desktop with your Serpantinum settings and addons\n'
           'Exec=/usr/bin/bash ' + desktop_quote(str(home / '.local/bin/niri-serpantinum-session')) + '\n'
           'TryExec=/usr/bin/bash\nType=Application\n')
if entry.exists() and entry.read_text() != content:
    raise SystemExit(f'Existing session entry preserved: {entry}')
entry.write_text(content)
print(entry)
print('SDDM registration: sudo install -m 644 ' + str(entry) + ' /usr/share/wayland-sessions/niri-serpantinum.desktop')
