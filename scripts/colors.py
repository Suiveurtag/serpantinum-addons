#!/usr/bin/env python3
"""Extract actual wallpaper pixel colors; Vivid lifts their HSV values."""
import colorsys
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image

OVERRIDES = 'addons_v2_palette_overrides.json'
POINTS = 'addons_v2_palette.json'
HUES = {'red': 0, 'maroon': 0, 'peach': 25, 'yellow': 50, 'green': 105, 'teal': 165, 'sapphire': 195, 'blue': 225, 'mauve': 280, 'pink': 325}


def lift(rgb):
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    # A monochrome wallpaper remains monochrome.
    s = min(1, s * 1.3 + (0.08 if s > 0.1 else 0))
    v = min(1, max(0.82, v * 1.15))
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))


def sample(image, x, y):
    # 3x3 average on the thumbnail; the palette editor previews the same area.
    w, h = image.size
    cx, cy = min(w - 1, max(0, int(x * w))), min(h - 1, max(0, int(y * h)))
    area = [image.getpixel((i, j)) for i in range(max(0, cx - 1), min(w, cx + 2)) for j in range(max(0, cy - 1), min(h, cy + 2))]
    return tuple(round(sum(c[k] for c in area) / len(area)) for k in range(3))


def palette(path, mode, overrides=None):
    """Return ({key: hex}, {key: {x, y, color, manual}}); overrides maps key -> [x, y] in 0..1."""
    overrides = overrides or {}
    # Sample existing pixels rather than inventing hues through a preset palette.
    with Image.open(path) as source:
        image = source.convert('RGB')
        image.thumbnail((192, 192), Image.Resampling.NEAREST)
        w = image.size[0]
        bins = {}
        all_pixels = list(image.getdata())
        for index, pixel in enumerate(all_pixels):
            h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in pixel))
            if s < 0.10 or v < 0.08:
                continue
            bucket = int(h * 36)
            score = s * (0.4 + v)
            total, best_score, best, best_index = bins.get(bucket, (0, 0, pixel, index))
            if score > best_score:
                best_score, best, best_index = score, pixel, index
            bins[bucket] = (total + score, best_score, best, best_index)
        candidates = [(item[2], item[3]) for item in sorted(bins.values(), reverse=True)[:12]]
        if not candidates:
            index = max(range(len(all_pixels)), key=lambda i: sum(all_pixels[i]))
            candidates = [(all_pixels[index], index)]
        result, points = {}, {}
        for key, degrees in HUES.items():
            def distance(candidate):
                hue = colorsys.rgb_to_hsv(*(c / 255 for c in candidate[0]))[0]
                d = abs(hue - degrees / 360)
                return min(d, 1 - d)
            point = overrides.get(key)
            if point:
                x, y = (min(1, max(0, float(v))) for v in point[:2])
                rgb = sample(image, x, y)
            else:
                rgb, index = min(candidates, key=distance)
                x, y = (index % w + .5) / w, (index // w + .5) / image.size[1]
            if mode == 'vivid':
                rgb = lift(rgb)
            result[key] = '#%02x%02x%02x' % rgb
            points[key] = {'x': round(x, 4), 'y': round(y, 4), 'color': result[key], 'manual': bool(point)}
        return result, points


def read_overrides(state, image):
    try:
        entry = json.loads((state / OVERRIDES).read_text()).get(image, {})
        return {k: v for k, v in entry.items() if k in HUES and isinstance(v, list) and len(v) >= 2}
    except (OSError, ValueError, AttributeError):
        return {}


def md3(colors):
    mapping = dict(surface_container_lowest='base', surface_container_low='mantle', surface='crust', surface_container='surface0', surface_container_high='surface1', surface_container_highest='surface2', surface_variant='surface1', on_surface='text', on_surface_variant='subtext0', outline='subtext1', inverse_surface='overlay0', primary='blue', primary_container='sapphire', secondary='green', secondary_container='yellow', tertiary='peach', tertiary_container='pink', error='red', error_container='maroon', primary_fixed='sapphire', secondary_fixed='yellow', tertiary_fixed='pink', inverse_primary='mauve')
    roles = {role: colors[key] for role, key in mapping.items()}
    for role in ('primary', 'secondary', 'tertiary', 'error'):
        for suffix in ('', '_container'):
            rgb = tuple(int(roles[role + suffix][i:i+2], 16) / 255 for i in (1, 3, 5))
            lum = sum(a*b for a, b in zip(rgb, (0.2126, 0.7152, 0.0722)))
            roles['on_' + role + suffix] = colors['crust'] if lum > .5 else colors['text']
    return {'colors': {k: {mode: {'hex': v, 'color': v} for mode in ('default', 'dark', 'light')} for k, v in roles.items()}}


def tint_surfaces(colors, mode, addon_mode):
    """Carry the wallpaper palette into shell surfaces as well as accents."""
    dark = mode == 'dark'
    sampled = [colors[key] for key in ('red', 'peach', 'yellow', 'green', 'teal', 'sapphire', 'blue', 'mauve', 'pink')]
    hue, saturation, _ = max(
        (colorsys.rgb_to_hsv(*(int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))) for color in sampled),
        key=lambda hsv: hsv[1],
    )
    surface_saturation = min(0.42 if addon_mode == 'vivid' else 0.28, saturation * (0.62 if addon_mode == 'vivid' else 0.42))
    values = ({'base': .13, 'mantle': .17, 'crust': .10, 'surface0': .21, 'surface1': .27, 'surface2': .34,
               'overlay0': .52, 'overlay1': .61, 'overlay2': .70, 'text': .94, 'subtext0': .78, 'subtext1': .66}
              if dark else
              {'base': .94, 'mantle': .90, 'crust': .97, 'surface0': .86, 'surface1': .81, 'surface2': .76,
               'overlay0': .60, 'overlay1': .50, 'overlay2': .40, 'text': .14, 'subtext0': .28, 'subtext1': .39})
    for key, value in values.items():
        sat = surface_saturation * (0.18 if key in ('text', 'subtext0', 'subtext1') else 1)
        rgb = colorsys.hsv_to_rgb(hue, sat, value)
        colors[key] = '#%02x%02x%02x' % tuple(round(channel * 255) for channel in rgb)


def atomic(path, data):
    fd, name = tempfile.mkstemp(dir=path.parent)
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f)
    os.replace(name, path)


def generate(image, config, static_config, mode, scheme, addon_mode, state):
    subprocess.run(['matugen', 'image', image, '-c', config, '-m', mode, '-t', scheme, '--source-color-index', '0'], check=True)
    state = Path(state)
    colors_path = state / 'qs_colors.json'
    matugen_colors_path = state / 'qs_matugen_colors.json'
    if addon_mode == 'matugen':
        # Matugen.qml reloads both files as soon as this process exits. Keep the
        # copy in this process so its watcher cannot race a detached cp command.
        colors = json.loads(colors_path.read_text())
        atomic(matugen_colors_path, colors)
        return
    colors = json.loads(colors_path.read_text())
    accents, points = palette(image, addon_mode, read_overrides(state, image))
    colors.update(accents)
    tint_surfaces(colors, mode, addon_mode)
    with tempfile.TemporaryDirectory(prefix='serpantinum-colors-') as directory:
        synthetic = Path(directory) / 'colors.json'
        synthetic.write_text(json.dumps(md3(colors)))
        subprocess.run(['matugen', '-c', static_config, '-m', mode, 'json', str(synthetic)], cwd=Path(config).parent, check=True)
    # Publish only after both Matugen passes succeeded. The shell's file
    # watchers are notified before generationFinished is emitted by QML.
    atomic(colors_path, colors)
    atomic(matugen_colors_path, colors)
    # The theme tab's accent editor draws these sample points over the wallpaper.
    atomic(state / POINTS, {'image': image, 'mode': addon_mode, 'points': points})


if __name__ == '__main__':
    generate(*sys.argv[1:])
