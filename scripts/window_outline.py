#!/usr/bin/env python3
"""Persist and apply the shell's themed Hyprland window outline."""
import re
import sys

from control import CONFIG, run, write

MAIN = CONFIG / 'hypr/hyprland.lua'
LUA = CONFIG / 'hypr/config/serpantinum_window_outline.lua'
HOOK = '\n-- Serpantinum addons v2: window outline\nrequire("config/serpantinum_window_outline")\n'


def apply(enabled, accent, secondary, muted):
    colors = (accent, secondary, muted)
    if not all(re.fullmatch(r'#[0-9a-fA-F]{6}', color) for color in colors):
        raise ValueError('Invalid shell palette colors')
    if not enabled and not LUA.exists():
        return
    main = MAIN.read_text()
    old_lua = LUA.read_text() if LUA.exists() else None
    hook_needed = 'require("config/serpantinum_window_outline")' not in main
    content = ('-- Managed by Serpantinum addons v2\n'
               'hl.config({ general = { border_size = %d, col = {\n'
               '  active_border = { colors = { "rgba(%se6)", "rgba(%sc9)" }, angle = 45 },\n'
               '  inactive_border = "rgba(%s88)",\n'
               '} } })\n' % (2 if enabled else 0, *(color[1:] for color in colors)))
    if old_lua == content and not hook_needed:
        return
    try:
        write(LUA, content)
        if hook_needed:
            write(MAIN, main.rstrip() + HOOK)
        run('hyprctl', 'reload')
        errors = run('hyprctl', 'configerrors').strip()
        if errors and errors != 'ok':
            raise ValueError(errors)
    except Exception:
        if old_lua is None:
            LUA.unlink(missing_ok=True)
        else:
            write(LUA, old_lua)
        if hook_needed:
            write(MAIN, main)
        run('hyprctl', 'reload')
        raise


if __name__ == '__main__':
    try:
        if len(sys.argv) != 5 or sys.argv[1] not in ('on', 'off'):
            raise ValueError('Expected on/off and three palette colors')
        apply(sys.argv[1] == 'on', *sys.argv[2:])
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
