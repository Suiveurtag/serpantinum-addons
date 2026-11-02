#!/usr/bin/env python3
"""Build Clawd's sprite strips from the ASCII frames in scripts/clawd/frames/<anim>.txt.
'.' transparent, '#' body, 'o' eyes, 'z' cream props (sleep z, ✻, keyboard, !, book, terminal, lens, globe, checklist, sheets, coin, confetti),
'h' pink (hearts, pencil, diff marks, ticks, confetti); frames separated by a blank line.
explode = the singularity poses (ClawdBlast.qml picks them by index): he heats up ('a' 'b' 'c' 'w'), crosses his eyes, then cracks
open on the violet void 'v'. antimatter = the 49x49 annihilation core drawn over his last pose.
nuke = the nuclear variant's poses (ClawdNuke.qml picks them by index): startled, panic run, terror, crouch, launch, slow-motion
float, crossed eyes, the glint, black and white impact silhouettes ('r' red alarm, 'y' sweat). mushroom = the 96x96 cloud, frame by frame.
After either: dead (grey 'g' corpse on his back) / dead_land (the thud, 'u' dust), smoke = 15x16 wisps drawn above the corpse
('n' 'm' 's', translucent); revive = the revival poses (ClawdRevive.qml), from grey through holy white back to orange; tada ('q' gold).
conduct = the weekly reset's conductor (bow tie 'r', baton 'z'/'w'; 16 poses: front, bows, turning, back, beats, leap, cutoff, spin, triumph);
orchestra = its 7 musicians 15x12, A/B frames each (violin, flute, cello, trumpet, harp, timpani, cymbals; brown 'k').
surge = the superpowered weekly scene's poses (ClawdSurge.qml: startle, look, poker face, inhale, power, dash, wink, skid, slam,
levitate, triumph; white 'w' glowing eyes); clone = his helpers, white-bodied ('w', recoloured per effort level by clone.frag):
idle, bob, typing A/B, cheer A/B, landing squash, looking at the middle, then A/B work poses copied from read, bash, search, edit, todo, web,
then (38..49) the dream surfer on a brown 'k' board with a gold 'q' stripe: ride, crouch, lean forward/back, balance A/B, pre-jump crouch,
launch, tuck, back view (mid-flip), landing squash, shaka (ClawdDreamSurf.qml picks them by index).
lot 7 (sleep): the blanket clips use SLEEPY (blanket blue 'b', quilting 'n', pink trim 'p', sweat 'y'); a roll's last frame is the mirror
of its loop's frame 0 (the pet flips `mirrored` when it ends). gemini.png (the nightmare's drawing) is copied as is from scripts/clawd/gemini.png.
recharge = the 5 h reset poses (ClawdRecharge.qml): drained and dark ('e'), refilling from the feet up in 5 levels, white, cream.
hand.png (the petpet hand, drawn over Clawd in sync with his frames) is cut out of scripts/clawd/hand-pet.gif.
An animation may set a grip = its contact point with the support, in frame pixels from the frame's top-left, unmirrored
(mirrored: W - gx). The pet places him at x = contactX - gx*scale, y = contactY - gy*scale; without one the manifest has no
'grip' and the default is [W/2, H] (bottom centre: standing on the floor).
Specials (SPECIALS: a prop or a bigger canvas each: book, bike, broom, boat, carry, camp, content; reproduced from reference videos) keep their own
header in frames/<anim>.txt (# comments, fps, loop, anchor X Y = the cell of his bottom centre in the first frame, pal C RRGGBB, then a blank line)
and their own canvas: the manifest entry has w/h, and its grip = [anchor x, his feet row] (boat/broom: the bottom of the canvas).
Usage: sprites.py [--check]  (--check exits 1 when payload/clawd/sprites differs from the frames)"""
import io
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FRAMES = Path(__file__).resolve().parent/'frames'
OUT = ROOT/'payload/clawd/sprites'
W, H = 21, 14
PALETTE = {'.': (0, 0, 0, 0), '#': (0xD9, 0x77, 0x57, 255), 'o': (0, 0, 0, 255), 'z': (0xF0, 0xEE, 0xE6, 255), 'h': (0xEC, 0x5B, 0x86, 255)}
# name: (fps, loop) or (fps, loop, (gx, gy)) with a grip (see above); order is the manifest order
ANIMS = {
    'idle': (2, True), 'blink': (12, False), 'look_left': (2, False), 'look_right': (2, False),
    'look_up': (2, False), 'walk': (8, True), 'turn': (12, False), 'sit': (2, True), 'sleep': (3, True),
    'drag': (6, True), 'fall': (8, True), 'land': (10, False), 'spawn': (10, False),
    'think': (6, False), 'work': (6, True), 'oops': (10, False), 'alert': (6, True), 'happy': (10, False),
    'petpet': (20, True), 'petpetheart': (20, True),
    # one working loop per tool family (Clawd.toolAnim), plus compaction and being disturbed at work
    'read': (4, True), 'bash': (5, True), 'search': (3, True), 'web': (6, True), 'task': (6, True), 'todo': (3, True),
    'compact': (8, False), 'startled': (6, False),
    # lot 4: edit family, a second variant per working loop (Clawd picks F or F_2), moods driven by session stats
    'edit': (5, True), 'edit_2': (5, True), 'work_2': (8, True), 'read_2': (4, True), 'bash_2': (5, True), 'search_2': (4, True),
    'web_2': (4, True), 'task_2': (6, True), 'todo_2': (3, True), 'think_2': (6, False), 'happy_2': (10, False),
    'celebrate': (10, False), 'sweat': (4, True), 'coin': (10, False), 'sad': (4, False), 'wave': (8, False),
    # lot 8: a third (and more) variant per working loop, picked at random by Clawd.variant / ClawdPet.shuffle
    'work_3': (6, True), 'work_4': (4, True), 'work_5': (6, True), 'edit_3': (5, True), 'read_3': (4, True),
    'bash_3': (5, True), 'search_3': (5, True), 'web_3': (5, True), 'task_3': (5, True), 'todo_3': (4, True),
    # lot 5a: windows and ledges (perch grip = the seat line, his legs dangle below it), hopping, tripping, peeking out
    'explode': (10, False), 'perch': (2, True, (10.5, 12)), 'perch_look': (2, False, (10.5, 12)), 'hop': (12, False), 'stumble': (10, False),
    'teeter': (6, True), 'peek': (4, True),
    # the limit: the nuclear variant's poses, then dead until revived
    'nuke': (12, False), 'dead': (1, True), 'dead_land': (10, False), 'revive': (10, False), 'tada': (8, False),
    # the 5 h limit resetting: drained, charging up level by level, the white flash
    'recharge': (10, False),
    # the weekly reset: the conductor's poses (ClawdSymphony.qml picks them by index; the 7 musicians are orchestra.png)
    'conduct': (8, False),
    # the weekly limit, the superpowered way: startled, hit by a magic orb, absorbs it, dashes, slams, levitates (ClawdSurge.qml)
    'surge': (10, False),
    # lot 5b: climb, hang (the grips: the wall at mid height, the bar at row 0, the ground for the mantle's end)
    'climb': (6, True, (19, 7)), 'climb_top': (10, False, (10.5, 14)), 'hang': (2, True, (10.5, 0)),
    'shimmy': (6, True, (10.5, 0)), 'swing': (4, True, (10.5, 0)), 'drop': (10, False, (10.5, 0)),
    # lot 5c: dance, moods
    'dance': (8, True), 'dance_2': (6, True), 'shush': (6, False), 'drowsy': (2, True), 'exhausted': (2, True),
    # lot 5d: weather, chime
    'umbrella': (4, True), 'shiver': (12, True), 'chime': (6, False),
    # more dances: headphones on, a spin, a hip wiggle (ClawdPet.danceClip picks one)
    'vibe': (4, True), 'twirl': (8, True), 'wiggle': (8, True),
    # breakdance: toprock, drop, handstand, head spin with legs flying, recover (ClawdPet.danceClip picks it too)
    'breakdance': (8, True),
    # lot 6: chat
    'talk': (6, True),
    # lot 7: sleep (a blanket, turning over, the nightmare's jolt, the groggy wake-up, sleepwalking)
    'sleep_blanket_in': (6, False), 'sleep_blanket': (2, True), 'sleep_roll': (8, False), 'sleep_blanket_roll': (8, False),
    'sleep_blanket_out': (8, False), 'sleep_jolt': (10, False), 'wake_groggy': (5, False), 'sleep_walk': (6, True),
}
BLAST = {**PALETTE, **{k: tuple(bytes.fromhex(v)) + (255,) for k, v in {
    'a': 'e8946c', 'b': 'f4b68e', 'c': 'fcddc2', 'w': 'ffffff', 'v': '6e3bff'}.items()}}
ANTIMATTER = {'.': (0, 0, 0, 0), **{k: tuple(bytes.fromhex(v)) + (255,) for k, v in {
    'w': 'ffffff', 'c': 'a8f4ff', 'b': '38c8ff', 'v': '8b5cff', 'm': 'ff4fd8', 'd': '2b0f52', 'k': '06020c'}.items()}}
LIMIT = {**BLAST, **{k: tuple(bytes.fromhex(v)) + (255,) for k, v in {
    'r': 'e5484d', 'y': '8fd3ff', 'g': '8c8782', 'd': '5c5854', 'u': 'b8b2aa', 'l': 'c9c4be', 'q': 'ffd56b', 'e': '8f4a38', 'k': '7a4a30'}.items()}}
SMOKE = {'.': (0, 0, 0, 0), 'n': (0x5c, 0x58, 0x54, 200), 'm': (0x8c, 0x87, 0x82, 170), 's': (0xbe, 0xba, 0xb4, 140)}
MUSHROOM = {'.': (0, 0, 0, 0), **{k: tuple(bytes.fromhex(v)) + (255,) for k, v in {
    'W': 'ffffff', 'Y': 'fff2b8', 'E': 'ffcf4d', 'O': 'ff9028', 'R': 'e0501c', 'D': '9e2c18', 'B': '5a2a1e',
    'K': '3a2b27', 'G': '6e5f57', 'L': 'a8988c', 'C': 'e6ecf2'}.items()}}
SPECIALS = ('book_idle', 'book_blink', 'bike_ride', 'broom_fly', 'boat_idle', 'boat_row_in', 'boat_row', 'boat_row_out', 'boat_row_brief',
            'boat_fish_in', 'boat_fish_wait', 'boat_fish_catch', 'boat_fish_out', 'boat_bino', 'carry_walk', 'camp_stand', 'camp_fire_build',
            'camp_fire_burn', 'camp_fire_die', 'camp_binoc_raise', 'camp_binoc_look_right', 'camp_binoc_flip_left', 'camp_binoc_look_left',
            'camp_binoc_lower', 'camp_camera_raise', 'camp_camera_shoot', 'camp_camera_away', 'camp_lie_down', 'camp_lie_idle', 'camp_stand_up',
            'content_idle', 'content_bounce')
SLEEPY = {**PALETTE, **{k: tuple(bytes.fromhex(v)) + (255,) for k, v in {'b': '6f8fd8', 'n': '4a63b0', 'p': 'f4b6c8', 'y': '8fd3ff'}.items()}}
SLEEPY_CLIPS = {'sleep_blanket_in', 'sleep_blanket', 'sleep_blanket_roll', 'sleep_blanket_out', 'sleep_jolt'}
NEW = {'nuke', 'dead', 'dead_land', 'revive', 'tada', 'recharge', 'conduct', 'surge'}
HAND = Path(__file__).resolve().parent/'hand-pet.gif'
GEMINI = Path(__file__).resolve().parent/'gemini.png'
HAND_SCALE = 3  # source frames are 474x498, Clawd shows the hand at most ~16 px x8


def frames(name, w=W, h=H, palette=PALETTE):
    path = FRAMES/f'{name}.txt'
    blocks = [b.split('\n') for b in path.read_text().strip('\n').split('\n\n')]
    for i, rows in enumerate(blocks):
        if len(rows) != h or any(len(r) != w for r in rows):
            sys.exit(f'{path}: frame {i} is not {w}x{h}')
        bad = set(''.join(rows)) - set(palette)
        if bad:
            sys.exit(f'{path}: frame {i} uses unknown pixels {sorted(bad)}')
    return blocks


def special(name):
    """One special: (fps, loop, anchor, palette, blocks, w, h) from its header + frames."""
    path = FRAMES/f'{name}.txt'
    head, _, body = path.read_text().partition('\n\n')
    meta, pal = {}, {'.': (0, 0, 0, 0)}
    for line in head.splitlines():
        key, *rest = line.split() or ['#']
        if key == '#' or key.startswith('#'):
            continue
        if key == 'pal':
            pal[rest[0]] = tuple(bytes.fromhex(rest[1])) + (255,)
        elif key in ('fps', 'loop', 'anchor'):
            meta[key] = rest
        else:
            sys.exit(f'{path}: unknown header line {line!r}')
    blocks = [b.split('\n') for b in body.strip('\n').split('\n\n')]
    h, w = len(blocks[0]), len(blocks[0][0])
    for i, rows in enumerate(blocks):
        if len(rows) != h or any(len(r) != w for r in rows):
            sys.exit(f'{path}: frame {i} is not {w}x{h}')
        bad = set(''.join(rows)) - set(pal)
        if bad:
            sys.exit(f'{path}: frame {i} uses unknown pixels {sorted(bad)}')
    ax, ay = int(meta['anchor'][0]), int(meta['anchor'][1])
    grip = [ax, h if name.startswith(('boat_', 'broom_')) else min(h, ay + 1)]
    return int(meta['fps'][0]), meta['loop'][0] == 'true', grip, pal, blocks, w, h


def png(blocks, w=W, h=H, palette=PALETTE):
    img = Image.new('RGBA', (w * len(blocks), h))
    img.putdata([palette[c] for y in range(h) for i in range(len(blocks)) for c in blocks[i][y]])
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=False, compress_level=9)  # no metadata chunks: bytes depend only on pixels
    return buf.getvalue()


def hand():
    """Cut the hand out of the gif's near-black background: flood from the borders, then drop the dark specks it leaves."""
    gif = Image.open(HAND)
    out = []
    for i in range(gif.n_frames):
        gif.seek(i)
        f = gif.convert('RGBA')
        w, h = f.size
        px = f.load()
        seen = set()
        stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
        while stack:
            x, y = stack.pop()
            if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or max(px[x, y][:3]) > 95:
                continue
            seen.add((x, y))
            px[x, y] = (0, 0, 0, 0)
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        seen = set()
        for sy in range(h):
            for sx in range(w):
                if (sx, sy) in seen or not px[sx, sy][3]:
                    continue
                comp, stack = [], [(sx, sy)]
                seen.add((sx, sy))
                while stack:
                    x, y = stack.pop()
                    comp.append((x, y))
                    for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and px[n][3]:
                            seen.add(n)
                            stack.append(n)
                if len(comp) < 500:
                    for p in comp:
                        px[p] = (0, 0, 0, 0)
        out.append(f.convert('RGBa').resize((w // HAND_SCALE, h // HAND_SCALE), Image.LANCZOS).convert('RGBA'))
    fw, fh = out[0].size
    img = Image.new('RGBA', (fw * len(out), fh))
    for i, f in enumerate(out):
        img.paste(f, (i * fw, 0))
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=False, compress_level=9)
    return buf.getvalue(), {'file': 'hand.png', 'frames': len(out), 'w': fw, 'h': fh}


def build():
    files = {}
    manifest = {'frame': {'w': W, 'h': H}, 'animations': {}}
    for name, (fps, loop, *grip) in ANIMS.items():
        palette = BLAST if name == 'explode' else LIMIT if name in NEW else SLEEPY if name in SLEEPY_CLIPS else PALETTE
        blocks = frames(name, palette=palette)
        files[f'{name}.png'] = png(blocks, palette=palette)
        manifest['animations'][name] = {'file': f'{name}.png', 'frames': len(blocks), 'fps': fps, 'loop': loop}
        if grip:
            manifest['animations'][name]['grip'] = list(grip[0])
    for name in SPECIALS:
        fps, loop, grip, pal, blocks, w, h = special(name)
        files[f'{name}.png'] = png(blocks, w, h, pal)
        manifest['animations'][name] = {'file': f'{name}.png', 'frames': len(blocks), 'fps': fps, 'loop': loop, 'w': w, 'h': h, 'grip': grip}
    core = frames('antimatter', 49, 49, ANTIMATTER)
    files['antimatter.png'] = png(core, 49, 49, ANTIMATTER)
    manifest['antimatter'] = {'file': 'antimatter.png', 'frames': len(core), 'w': 49, 'h': 49}
    smoke = frames('smoke', 15, 16, SMOKE)
    files['smoke.png'] = png(smoke, 15, 16, SMOKE)
    manifest['smoke'] = {'file': 'smoke.png', 'frames': len(smoke), 'w': 15, 'h': 16, 'fps': 6}
    band = frames('orchestra', 15, 12, LIMIT)
    files['orchestra.png'] = png(band, 15, 12, LIMIT)
    manifest['orchestra'] = {'file': 'orchestra.png', 'frames': len(band), 'w': 15, 'h': 12}
    clones = frames('clone', W, H, LIMIT)
    files['clone.png'] = png(clones, W, H, LIMIT)
    manifest['clone'] = {'file': 'clone.png', 'frames': len(clones), 'w': W, 'h': H}
    cloud = frames('mushroom', 96, 96, MUSHROOM)
    files['mushroom.png'] = png(cloud, 96, 96, MUSHROOM)
    manifest['mushroom'] = {'file': 'mushroom.png', 'frames': len(cloud), 'w': 96, 'h': 96}
    files['hand.png'], manifest['hand'] = hand()
    files['gemini.png'] = GEMINI.read_bytes()
    gw, gh = Image.open(GEMINI).size
    manifest['gemini'] = {'file': 'gemini.png', 'w': gw, 'h': gh}
    files['clawd.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    return files


def same(name, data):
    old = (OUT/name).read_bytes()
    if not name.endswith('.png'):
        return old == data
    # pixels, not bytes: another zlib build may compress the same image differently
    a, b = (Image.open(io.BytesIO(d)) for d in (old, data))
    return a.mode == b.mode and a.size == b.size and a.tobytes() == b.tobytes()


def main():
    files = build()
    if '--check' in sys.argv[1:]:
        stale = [n for n, data in files.items() if not (OUT/n).is_file() or not same(n, data)]
        extra = [p.name for p in OUT.glob('*') if p.name not in files] if OUT.is_dir() else []
        if stale or extra:
            print('clawd sprites out of date: ' + ', '.join(stale + extra) + ' (run scripts/clawd/sprites.py)')
            sys.exit(1)
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for n, data in files.items():
        (OUT/n).write_bytes(data)


if __name__ == '__main__':
    main()
