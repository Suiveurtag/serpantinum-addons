#!/usr/bin/env python3
"""Expose the installed local Niri build and its session without replacing existing launchers."""
import os
from pathlib import Path

home = Path.home()
# SDDM splits Exec on whitespace without interpreting shell quotes.
if any(char.isspace() for char in str(home)):
    raise SystemExit('SDDM session launcher requires a home path without whitespace')
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
           'Exec=/usr/bin/bash ' + str(home / '.local/bin/niri-serpantinum-session') + '\n'
           'TryExec=/usr/bin/bash\nType=Application\n')
legacy_content = content.replace('Exec=/usr/bin/bash ' + str(home / '.local/bin/niri-serpantinum-session'),
                                 'Exec=/usr/bin/bash "' + str(home / '.local/bin/niri-serpantinum-session') + '"')
if entry.exists() and entry.read_text() not in (content, legacy_content):
    raise SystemExit(f'Existing session entry preserved: {entry}')
entry.write_text(content)
print(entry)
print('SDDM registration: sudo install -m 644 ' + str(entry) + ' /usr/share/wayland-sessions/niri-serpantinum.desktop')
