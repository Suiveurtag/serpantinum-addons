"""Find tools installed in per-user bin directories that the session PATH does not list yet.

A global npm install (Codex CLI), cargo, bun... lands in ~/.npm-global/bin, ~/.cargo/bin and so on. Those directories are
added to PATH by the shell rc files, but Quickshell (and the terminal it opens) keeps the PATH of the login session, so a
freshly installed tool looks missing until the next login. Appending the usual directories removes the need to reboot.
"""
from __future__ import annotations

import glob
import os
import re
from pathlib import Path


def _npmrc_prefix(home):
    try:
        text = (home / '.npmrc').read_text(errors='replace')
    except OSError:
        return None
    match = re.search(r'^\s*prefix\s*=\s*(\S+)', text, re.M)
    return match.group(1).replace('${HOME}', str(home)).replace('~', str(home), 1) if match else None


def candidate_dirs(home=None, environ=None):
    home = Path(home) if home else Path.home()
    env = os.environ if environ is None else environ
    h = str(home)
    dirs = []
    for var, sub in (('NPM_CONFIG_PREFIX', 'bin'), ('npm_config_prefix', 'bin'), ('PNPM_HOME', ''), ('BUN_INSTALL', 'bin'),
                     ('VOLTA_HOME', 'bin'), ('CARGO_HOME', 'bin'), ('NVM_BIN', '')):
        if env.get(var):
            dirs.append(str(Path(env[var]) / sub) if sub else env[var])
    prefix = _npmrc_prefix(home)
    if prefix:
        dirs.append(str(Path(prefix) / 'bin'))
    dirs += [f'{h}/.local/bin', f'{h}/.npm-global/bin', f'{h}/.npm-packages/bin', f'{h}/.local/share/npm/bin',
             f'{h}/.local/share/pnpm', f'{h}/.bun/bin', f'{h}/.volta/bin', f'{h}/.cargo/bin', f'{h}/.yarn/bin',
             f'{h}/.config/yarn/global/node_modules/.bin', f'{h}/.asdf/shims', f'{h}/.local/share/mise/shims', f'{h}/bin']
    # version managers keep one bin directory per Node version: newest first
    for pattern in (f'{h}/.nvm/versions/node/*/bin', f'{h}/.local/share/fnm/node-versions/*/installation/bin',
                    f'{h}/.fnm/node-versions/*/installation/bin', f'{h}/.local/share/mise/installs/node/*/bin'):
        dirs += sorted(glob.glob(pattern), key=_version_key, reverse=True)
    dirs += ['/usr/local/bin']
    return dirs


def _version_key(path):
    return [int(n) for n in re.findall(r'\d+', path)]


def augmented_path(path=None, home=None, environ=None):
    """The session PATH followed by the usual per-user bin directories that exist and are not on it yet."""
    base = (os.environ.get('PATH', '') if path is None else path)
    have = [d for d in base.split(os.pathsep) if d]
    seen = set(have)
    for d in candidate_dirs(home, environ):
        if d not in seen and os.path.isdir(d):
            have.append(d)
            seen.add(d)
    return os.pathsep.join(have)


def extend_environ():
    """Make the current process, and everything it launches, see the per-user bin directories."""
    os.environ['PATH'] = augmented_path()
