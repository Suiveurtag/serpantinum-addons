"""Lifetime AI token widget: registers the `tokens` widget type and runs the collector as a systemd user service."""
import os
import re
import shutil
import subprocess
from pathlib import Path

MARK = 'serpantinum-tokens-v2'
TYPES = ['singleton Tokens 1.0 tokens/Tokens.qml'] + [f'{name} 1.0 tokens/{name}.qml' for name in ('AddonTokens', 'TokensFace', 'TokensBarFace', 'TokensDigits')]
UNIT = 'serpantinum-tokens.service'


def patch_qmldir(text):
    for declaration in TYPES:
        if declaration not in text:
            text = text.rstrip('\n') + '\n' + declaration + '\n'
    return text


def patch_shell(text):
    text = remove_blocks(text)
    anchor = '    function ensureScreenshotOverlay() {\n'
    if text.count(anchor) != 1:
        raise ValueError('Tokens shell anchor changed')
    return text.replace(anchor, f'    // BEGIN {MARK} host\n    AddonTokens {{}}\n    // END {MARK} host\n' + anchor, 1)


def remove_blocks(text):
    return re.sub(r'^[ ]*// BEGIN ' + MARK + r' ([^\n]+)\n.*?^[ ]*// END ' + MARK + r' \1\n', '', text, flags=re.S | re.M)


def remove(text):
    return re.sub(r'^(?:singleton )?\w+ 1\.0 tokens/\w+\.qml\n', '', remove_blocks(text), flags=re.M)


def transformations(qs):
    return {qs/'qmldir': patch_qmldir, qs/'Shell.qml': patch_shell}


def resources(payload, qs):
    return [(qs/'tokens'/p.relative_to(payload), p.read_bytes()) for p in sorted(payload.rglob('*')) if p.is_file()]


def unit(script, codex):
    env = f'Environment=TOKENS_CODEX_CMD={codex}\n' if codex else ''
    return (f'[Unit]\nDescription=Serpantinum lifetime AI token collector\n\n[Service]\nExecStart=/usr/bin/python3 {script}\n{env}'
            'Restart=on-failure\nRestartSec=10\nNice=10\nMemoryMax=300M\n\n[Install]\nWantedBy=default.target\n')


def service(deploy, home, remove=False):
    """Install (or remove) and start the collector. Never fails the shell install: a missing systemd only prints a note."""
    if os.environ.get('SERPANTINUM_ADDONS_NO_SERVICES'):
        return 'collector service skipped (SERPANTINUM_ADDONS_NO_SERVICES is set)'
    path = home/'.config/systemd/user'/UNIT
    run = lambda *args: subprocess.run(['systemctl', '--user', *args], capture_output=True, text=True, timeout=30)
    try:
        if remove:
            run('disable', '--now', UNIT)
            path.unlink(missing_ok=True)
            run('daemon-reload')
            return 'collector service removed (its database is kept in ~/.local/state/serpantinum/tokens)'
        text = unit(deploy/'scripts/tokens/collector.py', shutil.which('codex'))
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
            run('daemon-reload')
        run('enable', UNIT)
        run('restart', UNIT)   # the collector script was just refreshed
        return 'collector service ' + run('is-active', UNIT).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        return f'collector service not managed ({error}); run `python3 {deploy}/scripts/tokens/collector.py` yourself'
