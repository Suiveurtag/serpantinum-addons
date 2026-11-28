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

HUES = {'red': 0, 'maroon': 0, 'peach': 25, 'yellow': 50, 'green': 105, 'teal': 165, 'sapphire': 195, 'blue': 225, 'mauve': 280, 'pink': 325}


def palette(path, mode):
    # Sample existing pixels rather than inventing hues through a preset palette.
    with Image.open(path) as source:
        image = source.convert('RGB')
        image.thumbnail((192, 192), Image.Resampling.NEAREST)
        bins = {}
        all_pixels = list(image.getdata())
        for pixel in all_pixels:
            h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in pixel))
            if s < 0.10 or v < 0.08:
                continue
            bucket = int(h * 36)
            score = s * (0.4 + v)
            total, best_score, best = bins.get(bucket, (0, 0, pixel))
            bins[bucket] = (total + score, max(best_score, score), pixel if score > best_score else best)
        candidates = [item[2] for item in sorted(bins.values(), reverse=True)[:12]]
        if not candidates:
            candidates = [max(all_pixels, key=lambda rgb: sum(rgb))]
        result = {}
        for key, degrees in HUES.items():
            def distance(rgb):
                hue = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))[0]
                d = abs(hue - degrees / 360)
                return min(d, 1 - d)
            rgb = min(candidates, key=distance)
            if mode == 'vivid':
                h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
                # A monochrome wallpaper remains monochrome.
                s = min(1, s * 1.3 + (0.08 if s > 0.1 else 0))
                v = min(1, max(0.82, v * 1.15))
                rgb = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
            result[key] = '#%02x%02x%02x' % rgb
        return result


def md3(colors):
    mapping = dict(surface_container_lowest='base', surface_container_low='mantle', surface='crust', surface_container='surface0', surface_container_high='surface1', surface_container_highest='surface2', surface_variant='surface1', on_surface='text', on_surface_variant='subtext0', outline='subtext1', inverse_surface='overlay0', primary='blue', primary_container='sapphire', secondary='green', secondary_container='yellow', tertiary='peach', tertiary_container='pink', error='red', error_container='maroon', primary_fixed='sapphire', secondary_fixed='yellow', tertiary_fixed='pink', inverse_primary='mauve')
    roles = {role: colors[key] for role, key in mapping.items()}
    for role in ('primary', 'secondary', 'tertiary', 'error'):
        for suffix in ('', '_container'):
            rgb = tuple(int(roles[role + suffix][i:i+2], 16) / 255 for i in (1, 3, 5))
            lum = sum(a*b for a, b in zip(rgb, (0.2126, 0.7152, 0.0722)))
            roles['on_' + role + suffix] = colors['crust'] if lum > .5 else colors['text']
    return {'colors': {k: {mode: {'hex': v, 'color': v} for mode in ('default', 'dark', 'light')} for k, v in roles.items()}}


def atomic(path, data):
    fd, name = tempfile.mkstemp(dir=path.parent)
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f)
    os.replace(name, path)


def generate(image, config, static_config, mode, scheme, addon_mode, state):
    subprocess.run(['matugen', 'image', image, '-c', config, '-m', mode, '-t', scheme,
                    '--source-color-index', '0'], check=True)
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
    colors.update(palette(image, addon_mode))
    with tempfile.TemporaryDirectory(prefix='serpantinum-colors-') as directory:
        synthetic = Path(directory) / 'colors.json'
        synthetic.write_text(json.dumps(md3(colors)))
        subprocess.run(['matugen', '-c', static_config, '-m', mode, 'json', str(synthetic)], cwd=Path(config).parent, check=True)
    # config-static generates app templates but has no Quickshell output. Publish
    # the first-pass palette with the sampled accents overlaid to both shell files.
    final_colors = colors
    final_colors.update(palette(image, addon_mode))
    atomic(matugen_colors_path, final_colors)
    atomic(colors_path, final_colors)


if __name__ == '__main__':
    generate(*sys.argv[1:])
