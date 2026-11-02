#!/usr/bin/env python3
"""Manage complete, self-contained cursor schemes across the desktop session."""
import configparser
import fcntl
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath

from PIL.Image import DecompressionBombError

from cursor_images import closest_frames, encode_frames, load_frames, read_bytes, xcursor_frames

HOME = Path.home()
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config'))
ADDON = DATA / 'serpantinum-addons-v2'
STORE = ADDON / 'cursor'
STATE = STORE / 'settings.json'
ASSETS = STORE / 'assets'
CACHE = STORE / 'previews'
THEME = 'SerpantinumCustomCursor'
ENV_LUA = CONFIG / 'hypr/config/env.lua'
BEGIN = '-- BEGIN serpantinum-addons-v2 custom cursor'
END = '-- END serpantinum-addons-v2 custom cursor'
ROLES = {
    'left_ptr': ['default', 'arrow', 'top_left_arrow'],
    'help': ['question_arrow', 'whats_this'],
    'progress': ['left_ptr_watch', 'half-busy'],
    'wait': ['watch'],
    'pointer': ['hand2', 'hand1', 'pointing_hand', 'hand'],
    'text': ['xterm', 'ibeam'],
    'vertical-text': ['vertical_text'],
    'crosshair': ['cross', 'cross_reverse', 'tcross'],
    'cell': ['plus'],
    'move': ['fleur', 'all-scroll', 'size_all', 'dnd-move', 'dnd_move'],
    'grab': ['openhand', 'open_hand'],
    'grabbing': ['closedhand', 'closed_hand'],
    'not-allowed': ['forbidden', 'crossed_circle', 'circle', 'no-drop', 'dnd-no-drop'],
    'copy': ['dnd-copy', 'dnd_copy'], 'alias': ['dnd-link', 'dnd_link', 'link'],
    'ew-resize': ['sb_h_double_arrow', 'h_double_arrow', 'size_hor', 'col-resize', 'split_h'],
    'ns-resize': ['sb_v_double_arrow', 'v_double_arrow', 'size_ver', 'row-resize', 'split_v'],
    'nesw-resize': ['size_bdiag', 'fd_double_arrow'],
    'nwse-resize': ['size_fdiag', 'bd_double_arrow'],
    'n-resize': ['top_side'], 's-resize': ['bottom_side'],
    'e-resize': ['right_side'], 'w-resize': ['left_side'],
    'ne-resize': ['top_right_corner'], 'nw-resize': ['top_left_corner'],
    'se-resize': ['bottom_right_corner'], 'sw-resize': ['bottom_left_corner'],
    'zoom-in': ['zoom_in'], 'zoom-out': ['zoom_out'],
    'context-menu': ['context_menu'], 'pencil': ['draft', 'draft_small', 'draft_large'],
}


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run(args, *, required=False, output=False, **kwargs):
    if not shutil.which(args[0]):
        if required:
            raise ValueError(args[0] + ' is not installed')
        return args[0] + ' is not installed'
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=15, **kwargs)
        if result.returncode:
            raise ValueError((result.stderr or result.stdout or 'Command failed').strip())
        if required and result.stdout.strip().lower().startswith(('error', 'failed')):
            raise ValueError(result.stdout.strip())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        if required:
            raise ValueError(args[0] + ': ' + str(error)) from error
        return args[0] + ': ' + str(error)
    return result.stdout if output else ''


def icon_roots():
    return list(dict.fromkeys([DATA / 'icons', HOME / '.icons'] +
                             [Path(path) / 'icons' for path in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if path]))


def theme_paths():
    themes = {}
    for root in icon_roots():
        if root.is_dir():
            for path in sorted(root.iterdir()):
                if path.name != 'default' and not path.name.startswith(THEME) and (path / 'cursors').is_dir():
                    themes.setdefault(path.name, path)
    return themes


def index_values(path):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        config.read(path / 'index.theme', encoding='utf-8')
        return dict(config['Icon Theme']) if config.has_section('Icon Theme') else {}
    except (configparser.Error, UnicodeError):
        return {}


def theme_files(name, themes, seen=None):
    seen = set() if seen is None else seen
    if name in seen or name not in themes:
        return {}
    seen.add(name)
    path = themes[name]
    files = {}
    for parent in re.split('[,;]', index_values(path).get('inherits', '')):
        if parent.strip():
            for key, value in theme_files(parent.strip(), themes, seen).items():
                files.setdefault(key, value)
    for entry in (path / 'cursors').iterdir():
        if entry.is_file() and entry.stat().st_size <= 32 * 1024 * 1024:
            with entry.open('rb') as stream:
                if stream.read(4) == b'Xcur':
                    files[entry.name] = entry
    return files


def find_role(files, role):
    source = next((files[key] for key in [role] + ROLES[role] if key in files), None)
    if source:
        return source
    fallback = {'pencil': 'crosshair', 'progress': 'wait', 'copy': 'pointer', 'alias': 'pointer',
                'zoom-in': 'crosshair', 'zoom-out': 'crosshair', 'grab': 'pointer', 'grabbing': 'move'}.get(role, 'left_ptr')
    return (next((files[key] for key in [fallback] + ROLES[fallback] if key in files), None)
            or next((files[key] for key in ['left_ptr'] + ROLES['left_ptr'] if key in files), None))


def default_settings():
    themes = theme_paths()
    preferred = 'Adwaita' if 'Adwaita' in themes else next(iter(themes), '')
    current = index_values(DATA / 'icons' / THEME).get('inherits', preferred).split(',')[0].strip()
    settings = {'baseTheme': current if current in themes else preferred, 'size': 32, 'roles': {}, 'normalOnly': False}
    # Preserve the image selected by the earlier single-pointer implementation.
    try:
        legacy = json.loads((CONFIG / 'serpantinum/settings.json').read_text()).get('addonsV2CustomCursorPath', '')
        if legacy and Path(legacy).is_file() and (DATA / 'icons' / THEME / 'cursors/left_ptr').exists():
            settings['roles']['left_ptr'] = {'source': legacy, 'hotspot': None}
    except (OSError, ValueError):
        pass
    return settings


def read_settings():
    return json.loads(STATE.read_text()) if STATE.exists() else default_settings()


def revision():
    return hashlib.sha256(STATE.read_bytes() if STATE.exists() else b'').hexdigest()


def validate_settings(settings):
    if not isinstance(settings, dict) or settings.get('baseTheme') not in theme_paths():
        raise ValueError('Choose an installed Xcursor theme')
    size = settings.get('size')
    if type(size) is not int or not 16 <= size <= 128:
        raise ValueError('Cursor size must be between 16 and 128 px')
    normal_only = settings.get('normalOnly', False)
    if type(normal_only) is not bool:
        raise ValueError('Normal-select mode must be a boolean')
    roles = settings.get('roles', {})
    if not isinstance(roles, dict) or set(roles) - ROLES.keys():
        raise ValueError('Unknown cursor role')
    clean = {}
    for role, value in roles.items():
        if not isinstance(value, dict) or not isinstance(value.get('source'), str):
            raise ValueError('Invalid cursor source')
        source = Path(value['source']).expanduser().resolve(strict=True)
        if not source.is_file():
            raise ValueError('Choose a cursor file')
        hotspot = value.get('hotspot')
        if hotspot is not None and (not isinstance(hotspot, list) or len(hotspot) != 2 or
                                   any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 1 for v in hotspot)):
            raise ValueError('Click point must be inside the cursor image')
        clean[role] = {'source': str(source), 'hotspot': hotspot,
                       'name': str(value.get('name', source.name))[:512],
                       'originalPath': str(value.get('originalPath', source))[:4096]}
    return {'baseTheme': settings['baseTheme'], 'size': size, 'roles': clean, 'normalOnly': normal_only}


def preview(path, size, hotspot=None):
    data = read_bytes(path)
    frames = closest_frames(load_frames(path), size)
    key = hashlib.sha256(b'premult-v1' + data + str(frames[0][0]).encode()).hexdigest()
    destination = CACHE / (key + '.gif')
    _, image, point, _ = frames[0]
    if not destination.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        images = [frame[1] for frame in frames]
        images[0].save(destination, format='GIF', save_all=True, append_images=images[1:],
                       duration=[frame[3] for frame in frames], loop=0, disposal=2)
    point = hotspot if hotspot is not None else [point[0] / max(1, image.width - 1), point[1] / max(1, image.height - 1)]
    return {'preview': destination.as_uri(), 'frames': len(frames), 'width': image.width,
            'height': image.height, 'hotspot': point}


def status(draft=None):
    warnings = []
    themes = theme_paths()
    if draft is None:
        try:
            draft = read_settings()
        except (OSError, ValueError):
            draft = default_settings()
            warnings.append('Saved cursor settings could not be read; choose a theme and apply again.')
        if not isinstance(draft, dict) or not isinstance(draft.get('roles', {}), dict):
            draft = default_settings()
            warnings.append('Invalid saved cursor scheme; using the default theme.')
        if draft.get('baseTheme') not in themes:
            draft['baseTheme'] = default_settings()['baseTheme']
            warnings.append('The previous base theme is no longer installed.')
        for role, custom in list(draft.get('roles', {}).items()):
            if not Path(custom.get('source', '')).is_file():
                del draft['roles'][role]
                warnings.append(role + ': cursor file no longer exists; using the base theme.')
    settings = validate_settings(draft)
    files = theme_files(settings['baseTheme'], themes)
    roles = []
    for role in ROLES:
        effective_role = 'left_ptr' if settings['normalOnly'] else role
        custom = settings['roles'].get(effective_role)
        source = Path(custom['source']) if custom else find_role(files, effective_role)
        entry = {'id': role, 'custom': bool(custom), 'source': str(source) if source else '', 'preview': '', 'frames': 0,
                 'width': 0, 'height': 0, 'hotspot': [0, 0]}
        if source:
            try:
                entry.update(preview(source, settings['size'], custom.get('hotspot') if custom else None))
            except (OSError, ValueError) as error:
                warnings.append(role + ': ' + str(error))
        roles.append(entry)
    return {'settings': settings, 'themes': [{'id': name, 'name': index_values(path).get('name', name)}
                                            for name, path in sorted(themes.items(), key=lambda item: item[0].lower())],
            'roles': roles, 'revision': revision(), 'warnings': warnings}


def import_cursor(path):
    source = Path(path).expanduser().resolve(strict=True)
    load_frames(source)
    data = read_bytes(source)
    ASSETS.mkdir(parents=True, exist_ok=True)
    destination = ASSETS / (hashlib.sha256(data).hexdigest() + '.cursor')
    if not destination.exists():
        atomic_write(destination, data)
    return {'source': str(destination), 'name': source.name, 'originalPath': str(source),
            **preview(destination, 32), 'hotspot': None}


def safe_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or '\0' in name:
        raise ValueError('Unsafe path in cursor theme archive')
    return Path(*path.parts)


def extract_theme(archive, destination):
    total, count, links = 0, 0, []

    def write(name, length, stream):
        nonlocal total, count
        count += 1
        total += length
        if count > 10000 or total > 256 * 1024 * 1024 or length > 32 * 1024 * 1024:
            raise ValueError('Cursor theme archive exceeds extraction limits')
        target = destination / safe_relative(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('wb') as output:
            shutil.copyfileobj(stream, output, length=65536)

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as opened:
            for entry in opened.infolist():
                safe_relative(entry.filename)
                if entry.is_dir():
                    continue
                with opened.open(entry) as stream:
                    if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                        if entry.file_size > 4096:
                            raise ValueError('Invalid theme link')
                        links.append((entry.filename, stream.read().decode(), False))
                    else:
                        write(entry.filename, entry.file_size, stream)
    else:
        with tarfile.open(archive) as opened:
            for entry in opened:
                safe_relative(entry.name)
                if entry.isfile():
                    with opened.extractfile(entry) as stream:
                        write(entry.name, entry.size, stream)
                elif entry.issym() or entry.islnk():
                    links.append((entry.name, entry.linkname, entry.islnk()))
                elif not entry.isdir():
                    raise ValueError('Unsupported special file in theme archive')
    if len(links) > 10000:
        raise ValueError('Too many links in theme archive')
    # Resolve only internal links, materialising them as files for sandbox compatibility.
    for _ in range(min(len(links) + 1, 64)):
        pending = []
        for name, link, hard in links:
            target = destination / safe_relative(name)
            raw = PurePosixPath(link)
            if raw.is_absolute() or '\\' in link:
                raise ValueError('External link in cursor theme archive')
            source = ((destination if hard else target.parent) / link).resolve()
            if not source.is_relative_to(destination.resolve()):
                raise ValueError('External link in cursor theme archive')
            if source.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open('rb') as stream:
                    write(name, source.stat().st_size, stream)
            else:
                pending.append((name, link, hard))
        if len(pending) == len(links):
            if pending:
                raise ValueError('Broken or cyclic link in theme archive')
            break
        links = pending
    if links:
        raise ValueError('Theme archive links are nested too deeply')


def install_theme(path):
    archive = Path(path).expanduser().resolve(strict=True)
    if archive.stat().st_size > 128 * 1024 * 1024:
        raise ValueError('Theme archive exceeds 128 MiB')
    installed = []
    with tempfile.TemporaryDirectory(prefix='serpantinum-cursors-') as temporary:
        root = Path(temporary)
        extract_theme(archive, root)
        for cursors in sorted(root.rglob('cursors')):
            if not cursors.is_dir():
                continue
            valid = {}
            for entry in cursors.iterdir():
                if entry.is_file() and read_bytes(entry)[:4] == b'Xcur':
                    xcursor_frames(read_bytes(entry))
                    valid[entry.name] = entry
            if not any(name in valid for name in ['left_ptr'] + ROLES['left_ptr']):
                continue
            slug = re.sub(r'[^A-Za-z0-9_.-]+', '-', cursors.parent.name)[:64] or 'Imported'
            digest = hashlib.sha256(b''.join(name.encode() + read_bytes(value) for name, value in sorted(valid.items()))).hexdigest()[:10]
            name = 'Serpantinum-' + slug + '-' + digest
            target = DATA / 'icons' / name
            if not target.exists():
                with tempfile.TemporaryDirectory(dir=DATA / 'icons', prefix='.cursor-import-') as staging:
                    stage = Path(staging) / name
                    (stage / 'cursors').mkdir(parents=True)
                    for filename, source in valid.items():
                        shutil.copyfile(source, stage / 'cursors' / filename)
                    values = index_values(cursors.parent)
                    title = values.get('name', cursors.parent.name).replace('\n', ' ')
                    (stage / 'index.theme').write_text('[Icon Theme]\nName=' + title + '\nInherits=Adwaita\n')
                    os.replace(stage, target)
            installed.append(name)
    if not installed:
        raise ValueError('No Xcursor theme found. Import a Linux cursor theme archive, or select .cur/.ani files for individual roles.')
    return {'installed': installed, **status()}


def export_theme(settings):
    settings = validate_settings(settings)
    directory = HOME / 'Downloads'
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / ('Serpantinum-cursors-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.tar.gz')
    with tempfile.TemporaryDirectory(prefix='cursor-export-') as temporary:
        root = Path(temporary) / 'Serpantinum-cursors'
        build_theme(settings, root)
        archive = Path(temporary) / 'scheme.tar.gz'
        with tarfile.open(archive, 'w:gz') as opened:
            opened.add(root, arcname=root.name)
        shutil.copyfile(archive, destination)
    return {'path': str(destination)}


def update_ini(text, section, values):
    lines = text.splitlines()
    heading = '[' + section + ']'
    if not any(line.strip() == heading for line in lines):
        lines.extend(['', heading])
    start = next(index for index, line in enumerate(lines) if line.strip() == heading) + 1
    end = next((index for index in range(start, len(lines)) if lines[index].strip().startswith('[')), len(lines))
    found, updated = set(), []
    for line in lines[start:end]:
        key = line.split('=', 1)[0].strip() if '=' in line else ''
        if key not in values:
            updated.append(line)
        elif key not in found:
            updated.append(key + '=' + str(values[key]))
            found.add(key)
    updated.extend(key + '=' + str(value) for key, value in values.items() if key not in found)
    lines[start:end] = updated
    return '\n'.join(lines).strip() + '\n'


def update_lines(text, values, separator):
    keys = '|'.join(re.escape(key) for key in values)
    delimiter = r'\s+' if separator == ' ' else r'\s*' + re.escape(separator.strip()) + r'\s*'
    lines = [line for line in text.splitlines() if not re.match(r'^\s*(?:' + keys + r')' + delimiter, line)]
    return '\n'.join(lines + [key + separator + str(value) for key, value in values.items()]) + '\n'


def configuration(size, theme=THEME):
    paths = list(dict.fromkeys([str(path) for path in icon_roots()] + ['/usr/share/pixmaps']))
    environment = {'XCURSOR_THEME': theme, 'XCURSOR_SIZE': str(size), 'HYPRCURSOR_THEME': theme,
                   'HYPRCURSOR_SIZE': str(size), 'XCURSOR_PATH': ':'.join(paths)}
    text = ENV_LUA.read_text() if ENV_LUA.exists() else ''
    block = BEGIN + '\n' + '\n'.join('hl.env(' + json.dumps(key) + ', ' + json.dumps(value) + ')' for key, value in environment.items())
    command = 'hyprctl setcursor ' + shlex.quote(theme) + ' ' + str(size)
    block += '\nhl.on("hyprland.start", function() hl.exec_cmd(' + json.dumps(command) + ') end)\n' + END
    if BEGIN in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1 or text.index(END) < text.index(BEGIN):
            raise ValueError('Invalid custom cursor block in Hyprland env.lua')
        text = text[:text.index(BEGIN)] + block + text[text.index(END) + len(END):]
    else:
        text = text.rstrip() + '\n\n' + block + '\n'
    files = {ENV_LUA: text}
    for version in ('3.0', '4.0'):
        path = CONFIG / ('gtk-' + version) / 'settings.ini'
        files[path] = update_ini(path.read_text() if path.exists() else '', 'Settings',
                                 {'gtk-cursor-theme-name': theme, 'gtk-cursor-theme-size': size})
    path = HOME / '.gtkrc-2.0'
    files[path] = update_lines(path.read_text() if path.exists() else '',
                               {'gtk-cursor-theme-name': json.dumps(theme), 'gtk-cursor-theme-size': size}, '=')
    path = CONFIG / 'kcminputrc'
    files[path] = update_ini(path.read_text() if path.exists() else '', 'Mouse', {'cursorTheme': theme, 'cursorSize': size})
    path = CONFIG / 'xsettingsd/xsettingsd.conf'
    files[path] = update_lines(path.read_text() if path.exists() else '',
                               {'Gtk/CursorThemeName': json.dumps(theme), 'Gtk/CursorThemeSize': size}, ' ')
    path = HOME / '.Xresources'
    files[path] = update_lines(path.read_text() if path.exists() else '', {'Xcursor.theme': theme, 'Xcursor.size': size}, ': ')
    path = CONFIG / 'environment.d/90-serpantinum-cursor.conf'
    files[path] = '\n'.join(key + '=' + json.dumps(value) for key, value in environment.items()) + '\n'
    for root in icon_roots()[:2]:
        path = root / 'default/index.theme'
        files[path] = update_ini(path.read_text() if path.exists() else '', 'Icon Theme', {'Name': 'Default', 'Inherits': theme})
    return files, environment


def build_theme(settings, target):
    themes = theme_paths()
    files = theme_files(settings['baseTheme'], themes)
    # A complete fallback keeps uncommon application cursor names functional.
    fallback = 'Adwaita' if 'Adwaita' in themes else settings['baseTheme']
    for name, path in theme_files(fallback, themes).items():
        files.setdefault(name, path)
    directory = target / 'cursors'
    directory.mkdir(parents=True)
    for name, source in files.items():
        shutil.copyfile(source, directory / name)
    for role, custom in settings['roles'].items():
        frames = load_frames(custom['source'])
        data = read_bytes(custom['source'])
        blob = data if data[:4] == b'Xcur' and custom.get('hotspot') is None else encode_frames(frames, custom.get('hotspot'))
        base = next((files[name] for name in [role] + ROLES[role] if name in files), None)
        aliases = {role, *ROLES[role]}
        known_names = set(ROLES).union(*(set(names) for names in ROLES.values()))
        if base:
            aliases.update(name for name, path in files.items()
                           if path.resolve() == base.resolve() and (name not in known_names or name in aliases))
        for name in aliases:
            (directory / name).write_bytes(blob)
    # Materialise named aliases even when the chosen theme uses only legacy names.
    for role, aliases in ROLES.items():
        source = find_role({entry.name: entry for entry in directory.iterdir()}, role)
        if source:
            for name in [role] + aliases:
                destination = directory / name
                if not destination.exists():
                    shutil.copyfile(source, destination)
    if not (directory / 'left_ptr').is_file():
        raise ValueError('The selected theme has no normal pointer')
    if settings.get('normalOnly', False):
        pointer = (directory / 'left_ptr').read_bytes()
        for path in directory.iterdir():
            if path.is_file():
                path.write_bytes(pointer)
    (target / 'index.theme').write_text('[Icon Theme]\nName=Serpantinum custom cursor\nInherits=' + settings['baseTheme'] + '\n')


def sync_session(environment):
    theme = environment['XCURSOR_THEME']
    warnings = []
    commands = [
        ['gsettings', 'set', 'org.gnome.desktop.interface', 'cursor-theme', theme],
        ['gsettings', 'set', 'org.gnome.desktop.interface', 'cursor-size', environment['XCURSOR_SIZE']],
        ['dbus-update-activation-environment', '--systemd', *environment.keys()],
    ]
    if os.environ.get('DISPLAY'):
        warning = run(['xrdb', '-merge'], input='Xcursor.theme: ' + theme + '\nXcursor.size: ' + environment['XCURSOR_SIZE'] + '\n')
        if warning:
            warnings.append(warning)
    if shutil.which('flatpak'):
        commands.append(['flatpak', 'override', '--user', '--filesystem=' + str(HOME / '.icons' / theme) + ':ro',
                         '--filesystem=' + str(HOME / '.icons/default') + ':ro',
                         '--env=XCURSOR_THEME=' + theme, '--env=XCURSOR_SIZE=' + environment['XCURSOR_SIZE'],
                         '--env=XCURSOR_PATH=' + str(HOME / '.icons') + ':/usr/share/icons:/run/host/share/icons'])
    for command in commands:
        warning = run(command, env={**os.environ, **environment})
        if warning:
            warnings.append(warning)
    if shutil.which('pgrep'):
        processes = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'xsettingsd'], capture_output=True, text=True, timeout=5)
        for pid in processes.stdout.split():
            try:
                os.kill(int(pid), signal.SIGHUP)
            except ProcessLookupError:
                pass
    return warnings


def backup_relative(path):
    try:
        return path.relative_to(HOME)
    except ValueError:
        return Path('external') / hashlib.sha256(str(path.parent).encode()).hexdigest()[:16] / path.name


def apply(payload):
    if payload.get('revision') != revision():
        raise ValueError('Cursor settings changed elsewhere. Refresh before applying.')
    settings = validate_settings(payload.get('settings'))
    for custom in settings['roles'].values():
        custom['source'] = import_cursor(custom['source'])['source']
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = ADDON / 'backups' / ('custom-cursor-' + stamp)
    try:
        old = read_settings()
    except (OSError, ValueError):
        old = default_settings()
    DATA.joinpath('icons').mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=DATA / 'icons', prefix='.cursor-build-') as temporary:
        stage = Path(temporary) / THEME
        build_theme(settings, stage)
        digest = hashlib.sha256(str(settings['size']).encode())
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                digest.update(str(path.relative_to(stage)).encode() + b'\0' + path.read_bytes())
        theme = THEME + '-' + digest.hexdigest()[:16]
        files, environment = configuration(settings['size'], theme)
        snapshot = {path: path.read_bytes() if path.exists() else None for path in files}
        destinations = list(dict.fromkeys(root.resolve() / name
                             for root in (DATA / 'icons', HOME / '.icons') for name in (THEME, theme)))
        previous, changed = {}, []
        try:
            for index, destination in enumerate(destinations):
                destination.parent.mkdir(parents=True, exist_ok=True)
                saved = backup / ('theme-' + str(index))
                if destination.exists() or destination.is_symlink():
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(destination), saved)
                    previous[destination] = saved
                changed.append(destination)
                shutil.copytree(stage, destination)
            for path, content in files.items():
                if snapshot[path] is not None:
                    saved = backup / backup_relative(path)
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, saved)
                atomic_write(path, content.encode())
            run(['hyprctl', 'reload', 'config-only'], required=True)
            errors = run(['hyprctl', 'configerrors'], required=True, output=True).strip()
            if errors:
                raise ValueError('Hyprland configuration error: ' + errors)
            run(['hyprctl', 'setcursor', theme, str(settings['size'])], required=True)
        except Exception:
            for path, content in snapshot.items():
                if content is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic_write(path, content)
            for destination in reversed(changed):
                if destination.is_symlink():
                    destination.unlink()
                elif destination.exists():
                    shutil.rmtree(destination)
                if destination in previous:
                    shutil.move(str(previous[destination]), destination)
            run(['hyprctl', 'reload', 'config-only'])
            run(['hyprctl', 'setcursor', old.get('runtimeTheme', THEME if (DATA / 'icons' / THEME).exists() else old['baseTheme']), str(old['size'])])
            raise
    override = DATA / 'flatpak/overrides/global'
    if override.is_file():
        saved = backup / backup_relative(override)
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(override, saved)
    warnings = sync_session(environment)
    if STATE.exists():
        saved = backup / backup_relative(STATE)
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(STATE, saved)
    atomic_write(STATE, (json.dumps({**settings, 'runtimeTheme': theme}, indent=2) + '\n').encode())
    result = status()
    result['warnings'].extend(warnings)
    result['backup'] = str(backup)
    return result


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'status'
    STORE.mkdir(parents=True, exist_ok=True)
    with (STORE / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if command == 'status':
            result = status()
        elif command == 'preview':
            result = status(json.loads(sys.argv[2]))
        elif command == 'import':
            result = import_cursor(sys.argv[2])
        elif command == 'install':
            DATA.joinpath('icons').mkdir(parents=True, exist_ok=True)
            result = install_theme(sys.argv[2])
        elif command == 'export':
            result = export_theme(json.loads(sys.argv[2]))
        elif command == 'apply':
            # Retain compatibility with the original image-only CLI.
            if not sys.argv[2].lstrip().startswith('{'):
                settings = read_settings()
                settings['roles']['left_ptr'] = import_cursor(sys.argv[2])
                result = apply({'settings': settings, 'revision': revision()})
            else:
                result = apply(json.loads(sys.argv[2]))
        else:
            raise ValueError('Unknown cursor command: ' + command)
    print(json.dumps({'ok': True, 'data': result}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, IndexError, DecompressionBombError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        sys.exit(1)
