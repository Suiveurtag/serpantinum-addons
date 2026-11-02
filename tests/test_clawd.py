import json
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from test_changes import ROOT, installer

sys.path.insert(0, str(ROOT))
import capri  # noqa: E402
import clawd  # noqa: E402
import seasonal  # noqa: E402

PAYLOAD = ROOT/'payload/clawd'
SPRITES = PAYLOAD/'sprites'
ANIMATIONS = ['idle', 'blink', 'look_left', 'look_right', 'look_up', 'walk', 'turn', 'sit', 'sleep', 'drag', 'fall', 'land', 'spawn',
              'think', 'work', 'oops', 'alert', 'happy', 'petpet', 'petpetheart',
              'read', 'bash', 'search', 'web', 'task', 'todo', 'compact', 'startled',
              'edit', 'edit_2', 'work_2', 'read_2', 'bash_2', 'search_2', 'web_2', 'task_2', 'todo_2', 'think_2', 'happy_2',
              'celebrate', 'sweat', 'coin', 'sad', 'wave', 'explode',
              'perch', 'perch_look', 'hop', 'stumble', 'teeter', 'peek', 'nuke', 'dead', 'dead_land', 'revive', 'tada', 'recharge', 'conduct', 'surge',
              'climb', 'climb_top', 'hang', 'shimmy', 'swing', 'drop', 'dance', 'dance_2', 'shush', 'drowsy', 'exhausted', 'umbrella', 'shiver', 'chime', 'vibe', 'twirl', 'wiggle', 'breakdance', 'talk',
              'sleep_blanket_in', 'sleep_blanket', 'sleep_roll', 'sleep_blanket_roll', 'sleep_blanket_out', 'sleep_jolt', 'wake_groggy', 'sleep_walk']
SPECIALS = ['book_idle', 'book_blink', 'bike_ride', 'broom_fly', 'boat_idle', 'boat_row_in', 'boat_row', 'boat_row_out', 'boat_row_brief', 'boat_fish_in', 'boat_fish_wait', 'boat_fish_catch', 'boat_fish_out', 'boat_bino', 'carry_walk', 'camp_stand', 'camp_fire_build', 'camp_fire_burn', 'camp_fire_die', 'camp_binoc_raise', 'camp_binoc_look_right', 'camp_binoc_flip_left', 'camp_binoc_look_left', 'camp_binoc_lower', 'camp_camera_raise', 'camp_camera_shoot', 'camp_camera_away', 'camp_lie_down', 'camp_lie_idle', 'camp_stand_up', 'content_idle', 'content_bounce']  # the idle specials: own canvas (w, h) and grip
ANIMATIONS += SPECIALS
HOOKS = ROOT/'scripts/clawd/hooks.py'
HOOK = ROOT/'scripts/clawd/hooks/clawd-hook.js'
STATUS = ROOT/'scripts/clawd/hooks/clawd-status.js'
VERBS = ROOT/'scripts/clawd/verbs.py'
CAPRI = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node "/x/capri-hook.js"', 'async': True}]}],
                   'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'node "/x/capri-hook.js"'}]}]},
         'model': 'opus'}
PALETTE = {(0, 0, 0, 0), (0xD9, 0x77, 0x57, 255), (0, 0, 0, 255), (0xF0, 0xEE, 0xE6, 255), (0xEC, 0x5B, 0x86, 255)}
# the singularity poses heat him up to white, then show the violet void inside
BLAST = PALETTE | {(0xE8, 0x94, 0x6C, 255), (0xF4, 0xB6, 0x8E, 255), (0xFC, 0xDD, 0xC2, 255), (255, 255, 255, 255), (0x6E, 0x3B, 0xFF, 255)}
# the limit's nuclear variant, his corpse and his revival: red alarm, sweat, greys, dust, gold
LIMIT = BLAST | {(0xE5, 0x48, 0x4D, 255), (0x8F, 0xD3, 0xFF, 255), (0x8C, 0x87, 0x82, 255), (0x5C, 0x58, 0x54, 255), (0xB8, 0xB2, 0xAA, 255),
                 (0xC9, 0xC4, 0xBE, 255), (0xFF, 0xD5, 0x6B, 255), (0x8F, 0x4A, 0x38, 255), (0x7A, 0x4A, 0x30, 255)}
SHADERS = ['aura', 'bulge', 'clone', 'desk', 'dream', 'evil', 'fx', 'lens', 'nuke', 'revive', 'surge', 'symphony', 'tint']
# lot 7: the blanket clips (and the nightmare's jolt): blanket blue, quilting, pink trim, sweat
SLEEPY = PALETTE | {(0x6F, 0x8F, 0xD8, 255), (0x4A, 0x63, 0xB0, 255), (0xF4, 0xB6, 0xC8, 255), (0x8F, 0xD3, 0xFF, 255)}
SLEEPY_CLIPS = ('sleep_blanket_in', 'sleep_blanket', 'sleep_blanket_roll', 'sleep_blanket_out', 'sleep_jolt')
COLORS = {'base': '#1e1e2e', 'mantle': '#181825', 'crust': '#11111b', 'text': '#cdd6f4', 'subtext0': '#a6adc8', 'subtext1': '#bac2de', 'surface0': '#313244',
          'surface1': '#45475a', 'surface2': '#585b70', 'overlay0': '#6c7086', 'overlay1': '#7f849c', 'overlay2': '#9399b2', 'blue': '#89b4fa', 'primary': '#89b4fa',
          'mauve': '#cba6f7', 'green': '#a6e3a1', 'red': '#f38ba8', 'pink': '#f5c2e7', 'yellow': '#f9e2af', 'peach': '#fab387'}


class ClawdPatchTests(unittest.TestCase):
    def test_shell_and_qmldir_hooks_are_idempotent_and_removable(self):
        shell = (installer.QS/'Shell.qml').read_text()
        season = seasonal.transformations(installer.QS)[installer.QS/'Shell.qml']
        orders = {'clawd last': lambda text: clawd.patch_shell(capri.patch_shell(season(installer.patch_shell(text)))),
                  'clawd first': lambda text: capri.patch_shell(season(installer.patch_shell(clawd.patch_shell(text))))}
        for name, stacked in orders.items():
            with self.subTest(order=name):
                once = stacked(shell)
                self.assertEqual(once, stacked(once))
                self.assertEqual(once.count('AddonClawd {}'), 1)
                self.assertEqual(once.count('AddonCapri {}'), 1)
                removed = clawd.remove(once)
                self.assertNotIn('Clawd', removed)
                self.assertIn('AddonCapri {}', removed)
                self.assertEqual(clawd.remove(removed), removed)
                self.assertIn('AddonClawd {}', capri.remove(once))
        qmldir = clawd.remove((installer.QS/'qmldir').read_text())  # the live shell may already have Clawd installed
        patched = clawd.patch_qmldir(capri.patch_qmldir(qmldir))
        self.assertEqual(patched, clawd.patch_qmldir(patched))
        self.assertIn('singleton Clawd 1.0 clawd/Clawd.qml', patched)
        self.assertNotIn('clawd/', clawd.remove(patched))
        self.assertEqual(clawd.remove(patched), capri.patch_qmldir(qmldir))
        self.assertIn('capri/', clawd.remove(patched))
        self.assertEqual({line.split()[-1] for line in clawd.TYPES}, {'clawd/' + p.name for p in PAYLOAD.glob('*.qml')})

    def test_changed_shell_fails_closed(self):
        with self.assertRaises(ValueError):
            clawd.patch_shell('ShellRoot {\n    Main {}\n}\n')

    def test_keybind_survives_user_edits_and_is_removable(self):
        original = 'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("serpantinum screenshot"))\n'
        shell_qml = installer.QS/'Shell.qml'
        patched = clawd.patch_keybind(capri.patch_keybind(original, shell_qml), shell_qml)
        self.assertEqual(clawd.patch_keybind(patched, shell_qml), patched)
        self.assertIn('hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(', patched)
        self.assertRegex(patched, r'ipc call clawd toggle"\)\)\n-- END serpantinum-clawd-v2 keybind\n')
        self.assertEqual(clawd.remove(patched), capri.patch_keybind(original, shell_qml))
        self.assertEqual(capri.remove(clawd.remove(patched)), original)
        self.assertIn('ipc call clawd toggle', capri.remove(patched))
        custom = patched.replace('SUPER + SHIFT + L', 'CTRL + ALT + F8')
        self.assertEqual(clawd.patch_keybind(custom, shell_qml), custom)
        with self.assertRaises(ValueError):
            clawd.patch_keybind('hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("custom"))\n', shell_qml)

    def test_settings_option_is_owned_by_clawd_only(self):
        tab = (ROOT/'payload/AddonsBannersTab.qml').read_text()
        self.assertIn('ClawdSettings { rootObj: root.rootObj; viewport: addonsViewport; Layout.bottomMargin: rootObj.s(6) }', tab)
        self.assertIn('ipc call clawd toggle', (ROOT/'payload/clawd/ClawdSettings.qml').read_text())
        stripped = clawd.remove(tab)
        self.assertNotIn('Clawd', stripped)
        self.assertNotIn('clawd', stripped)
        self.assertIn('CapriSettings', stripped)
        self.assertIn('HalloweenCard', stripped)
        self.assertIn('ClawdSettings', capri.remove(tab))
        self.assertIn('ClawdSettings', seasonal.remove(tab))

    def test_ipc_surface_is_exactly_five_commands(self):
        host = (PAYLOAD/'AddonClawd.qml').read_text()
        self.assertEqual(re.findall(r'function (\w+\([^)]*\)(?::\s*\w+)?)', host),
                         ['toggle(): void', 'appear(): void', 'hide(): void', 'play(name: string): string', 'state(): string'])
        self.assertEqual(host.count('IpcHandler'), 1)
        self.assertIn('target: "clawd"', host)


class ClawdInstallTests(unittest.TestCase):
    def test_without_clawd_flag_parses(self):
        result = subprocess.run([sys.executable, str(ROOT/'install.py'), '--without-clawd', '--help'], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--without-clawd', result.stdout)
        self.assertIn('without_clawd=args.without_clawd', (ROOT/'install.py').read_text())

    def test_payload_copy_covers_every_clawd_file(self):
        qs = Path('/qs')
        copied = clawd.resources(PAYLOAD, qs)
        files = sorted(p for p in PAYLOAD.rglob('*') if p.is_file())
        names = {str(p.relative_to(PAYLOAD)) for p in files}
        expected = ({line.split()[-1].removeprefix('clawd/') for line in clawd.TYPES} | {'sprites/clawd.json'} | {f'sprites/{a}.png' for a in ANIMATIONS + ['hand', 'antimatter', 'smoke', 'mushroom', 'orchestra', 'clone', 'gemini']}
                    | {'js/world.mjs', 'js/mind.mjs', 'js/beat.mjs', 'js/acts.mjs', 'js/dreams.mjs', 'js/effort.mjs', 'shaders/manifest.json'} | {f'shaders/{n}.frag{q}' for n in SHADERS for q in ('', '.qsb')})
        self.assertEqual(names, expected)  # nothing stray gets installed
        self.assertEqual(len(copied), len(files))
        hashed = {}
        for (path, blob), source in zip(copied, files):
            if source.name.endswith('.qsb'):
                self.assertRegex(path.name, r'^\w+\.[0-9a-f]{12}\.frag\.qsb$')  # Qt caches shaders by URL across reloads
                hashed[source.name] = path.name
                self.assertEqual((path.parent, blob), (qs/'clawd/shaders', source.read_bytes()))
            elif b'shaders/' not in source.read_bytes() or source.suffix != '.qml':
                self.assertEqual((path, blob), (qs/'clawd'/source.relative_to(PAYLOAD), source.read_bytes()))
        used = {'ClawdBlast.qml': ['desk', 'fx', 'lens'], 'ClawdNuke.qml': ['nuke', 'lens'], 'ClawdRevive.qml': ['revive'], 'ClawdSymphony.qml': ['symphony'], 'ClawdSurge.qml': ['bulge', 'surge', 'clone'],
                'ClawdDream.qml': ['dream'], 'ClawdDreamSurf.qml': ['clone'], 'ClawdNightmareGemini.qml': ['evil']}  # Ouroboros draws with plain items: no shader of its own
        for qml, names in used.items():
            text = dict(copied)[qs/'clawd'/qml].decode()
            self.assertNotRegex(text, r'shaders/\w+\.frag\.qsb', qml)
            for n in names:
                self.assertIn('"shaders/' + hashed[n + '.frag.qsb'] + '"', text)

    def test_stale_shader_packages_are_found_and_mismatches_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            qs = Path(directory)
            (qs/'clawd/shaders').mkdir(parents=True)
            current = [path for path, _ in clawd.resources(PAYLOAD, qs) if path.name.endswith('.qsb')]
            for path in current + [qs/'clawd/shaders/fx.0123456789ab.frag.qsb']:
                path.write_bytes(b'x')
            self.assertEqual(clawd.stale_shaders(qs), [qs/'clawd/shaders/fx.0123456789ab.frag.qsb'])
            self.assertEqual(len(clawd.stale_shaders(qs, everything=True)), len(current) + 1)
            payload = qs/'payload'
            shutil.copytree(PAYLOAD, payload)
            (payload/'shaders/fx.frag').write_text((payload/'shaders/fx.frag').read_text() + '\n// edited, not rebuilt\n')
            with self.assertRaisesRegex(ValueError, 'shaders.py'):
                clawd.resources(payload, qs)


class ClawdSpriteTests(unittest.TestCase):
    def test_generated_sprites_are_current(self):
        result = subprocess.run([sys.executable, str(ROOT/'scripts/clawd/sprites.py'), '--check'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_singularity_drawings_are_distinct(self):
        from PIL import Image
        manifest = json.loads((SPRITES/'clawd.json').read_text())
        core = manifest['antimatter']
        self.assertEqual((core['file'], core['w'], core['h'], core['frames']), ('antimatter.png', 49, 49, 12))
        # ClawdBlast picks his poses by index: 0 hovering, 1-6 charging, 7 light, 8 crossed eyes, 9-11 cracking open
        self.assertEqual(manifest['animations']['explode']['frames'], 12)
        # ClawdNuke: 0 startled, 1-4 panic run, 5 terror, 6 crouch, 7 launch, 8 slow motion, 9 crosses, 10 glint, 11-12 impact;
        # ClawdRevive: 0-4 the corpse lighting up, 5-9 standing again, white to orange, 10 eyes open
        self.assertEqual((manifest['animations']['nuke']['frames'], manifest['animations']['revive']['frames']), (13, 11))
        self.assertEqual((manifest['animations']['recharge']['frames'], manifest['animations']['conduct']['frames']), (8, 16))
        self.assertEqual(manifest['orchestra'], {'file': 'orchestra.png', 'frames': 14, 'w': 15, 'h': 12})  # 7 musicians, A and B poses  # ClawdRecharge: 0 drained, 1-5 filling up, 6 white, 7 cream
        self.assertEqual({k: manifest[k] for k in ('smoke', 'mushroom')}, {'smoke': {'file': 'smoke.png', 'frames': 12, 'w': 15, 'h': 16, 'fps': 6},
                                                                          'mushroom': {'file': 'mushroom.png', 'frames': 28, 'w': 96, 'h': 96}})
        for strip, w, h, n in (('antimatter.png', 49, 49, 12), ('explode.png', 21, 14, 12), ('nuke.png', 21, 14, 13), ('revive.png', 21, 14, 11),
                               ('mushroom.png', 96, 96, 28), ('smoke.png', 15, 16, 12)):
            with Image.open(SPRITES/strip) as image:
                self.assertEqual(image.size, (w * n, h))
                self.assertEqual(len({image.crop((w * i, 0, w * (i + 1), h)).tobytes() for i in range(n)}), n, strip)

    def test_shader_packages_match_their_sources(self):
        result = subprocess.run([sys.executable, str(ROOT/'scripts/clawd/shaders.py'), '--check'], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_manifest_strips_and_palette(self):
        from PIL import Image
        manifest = json.loads((SPRITES/'clawd.json').read_text())
        w, h = manifest['frame']['w'], manifest['frame']['h']
        self.assertEqual(list(manifest['animations']), ANIMATIONS)
        for name, clip in manifest['animations'].items():
            with self.subTest(animation=name):
                special = name in SPECIALS
                self.assertIn(set(clip), ({'file', 'frames', 'fps', 'loop', 'w', 'h', 'grip'},) if special else ({'file', 'frames', 'fps', 'loop'}, {'file', 'frames', 'fps', 'loop', 'grip'}))
                cw, ch = (clip['w'], clip['h']) if special else (w, h)
                if 'grip' in clip:  # contact point with the support, frame px from the top-left
                    gx, gy = clip['grip']
                    self.assertTrue(0 <= gx <= cw and 0 <= gy <= ch, clip['grip'])
                self.assertEqual(clip['file'], name + '.png')
                self.assertIsInstance(clip['loop'], bool)
                self.assertGreater(clip['fps'], 0)
                with Image.open(SPRITES/clip['file']) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(image.size, (clip['frames'] * cw, ch))
                    if not special:
                        self.assertLessEqual({c for _, c in image.getcolors(image.width * image.height)}, BLAST if name == 'explode' else LIMIT if name in ('nuke', 'dead', 'dead_land', 'revive', 'tada', 'recharge', 'conduct', 'surge') else SLEEPY if name in SLEEPY_CLIPS else PALETTE)
        self.assertEqual({n for n, c in manifest['animations'].items() if c['loop']}, {'idle', 'walk', 'sit', 'sleep', 'drag', 'fall', 'work', 'alert', 'petpet', 'petpetheart',
                                                                                               'read', 'bash', 'search', 'web', 'task', 'todo',
                                                                                               'edit', 'edit_2', 'work_2', 'read_2', 'bash_2', 'search_2', 'web_2', 'task_2', 'todo_2', 'sweat',
                                                                                               'perch', 'teeter', 'peek', 'dead',
                                                                                               'climb', 'hang', 'shimmy', 'swing', 'dance', 'dance_2', 'drowsy', 'exhausted', 'umbrella', 'shiver', 'vibe', 'twirl', 'wiggle', 'breakdance',
                                                                                               'book_idle', 'bike_ride', 'broom_fly', 'boat_idle', 'boat_row', 'boat_fish_wait', 'carry_walk',
                                                                                               'camp_stand', 'camp_fire_burn', 'camp_binoc_look_right', 'camp_binoc_look_left', 'camp_lie_idle', 'content_idle', 'talk',
                                                                                               'sleep_blanket', 'sleep_walk'})
        self.assertEqual(manifest['animations']['perch'].get('grip'), [10.5, 12])  # seated on the ledge, legs below it
        self.assertEqual(manifest['hand']['frames'], manifest['animations']['petpet']['frames'])  # the hand is frame-locked to him

    def test_sleep_lot_strips(self):
        from PIL import Image, ImageOps
        manifest = json.loads((SPRITES/'clawd.json').read_text())
        frame = lambda name, i: Image.open(SPRITES/f'{name}.png').crop((21 * i, 0, 21 * (i + 1), 14))
        # a roll ends on the mirror of its loop's first frame: the pet flips `mirrored` when it ends, seamless
        for roll, loop in (('sleep_roll', 'sleep'), ('sleep_blanket_roll', 'sleep_blanket')):
            last = manifest['animations'][roll]['frames'] - 1
            self.assertEqual(frame(roll, last).tobytes(), ImageOps.mirror(frame(loop, 0)).tobytes(), roll)
        self.assertEqual(frame('sleep_blanket_in', 9).tobytes(), frame('sleep_blanket', 0).tobytes())  # the intro lands in the loop
        self.assertEqual(frame('wake_groggy', 9).tobytes(), frame('idle', 0).tobytes())                 # both wake-ups end standing
        self.assertEqual(frame('sleep_blanket_out', 5).tobytes(), frame('idle', 0).tobytes())
        # ClawdDreamSurf picks the surfer's poses 38..49 of clone.png; the 38 surge helpers' poses stay where they were
        self.assertEqual(manifest['clone']['frames'], 50)
        clone = Image.open(SPRITES/'clone.png')
        self.assertEqual(len({clone.crop((21 * i, 0, 21 * (i + 1), 14)).tobytes() for i in range(38, 50)}), 12)
        with Image.open(ROOT/'scripts/clawd/gemini.png') as drawing:
            self.assertEqual(manifest['gemini'], {'file': 'gemini.png', 'w': drawing.width, 'h': drawing.height})
        # the dream's surfer glows in the same light colours as the surge's max helper
        palette = lambda qml: re.search(r'property var rainbow: (\[[^\]]*\])', (PAYLOAD/qml).read_text()).group(1)
        self.assertEqual(palette('ClawdDreamSurf.qml'), palette('ClawdSurge.qml'))


class ClawdHooksInstallerTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix='clawd-hooks-'))
        self.addCleanup(shutil.rmtree, self.home)
        self.env = dict(os.environ, CLAUDE_CONFIG_DIR=str(self.home/'claude'), CODEX_HOME=str(self.home/'codex'),
                        XDG_CONFIG_HOME=str(self.home/'config'), HERMES_HOME=str(self.home/'hermes'))

    def hooks(self, action, agent):
        result = subprocess.run([sys.executable, str(HOOKS), action, agent], env=self.env, capture_output=True, text=True, timeout=20)
        out = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0 if out['ok'] else 1)
        return out

    def test_install_keeps_other_hooks_backs_up_and_uninstalls_cleanly(self):
        for agent, name in (('claude', 'settings.json'), ('codex', 'hooks.json')):
            with self.subTest(agent=agent):
                file = self.home/agent/name
                file.parent.mkdir()
                file.write_text(json.dumps(CAPRI))
                self.assertFalse(self.hooks('status', agent)['data']['installed'])
                data = self.hooks('install', agent)['data']
                self.assertTrue(data['installed'] and data['changed'])
                settings = json.loads(file.read_text())
                self.assertEqual(settings['hooks']['Stop'][0], CAPRI['hooks']['Stop'][0])
                self.assertEqual(settings['model'], 'opus')
                ours = [h for groups in settings['hooks'].values() for g in groups for h in g['hooks'] if 'clawd-hook.js' in h['command']]
                self.assertEqual(len(ours), {'claude': 12, 'codex': 10}[agent])
                self.assertEqual({h['command'].endswith(' --agent codex') for h in ours}, {agent == 'codex'})
                self.assertEqual({h.get('async', False) for h in ours}, {agent == 'claude'})
                self.assertEqual(len(list(file.parent.glob(name + '.clawd-backup-*'))), 1)
                self.assertFalse(self.hooks('install', agent)['data']['changed'])  # idempotent: no backup spam
                self.assertEqual(len(list(file.parent.glob(name + '.clawd-backup-*'))), 1)
                data = self.hooks('uninstall', agent)['data']
                self.assertTrue(data['changed'] and not data['installed'] and data['events'] == [])
                self.assertEqual(json.loads(file.read_text()), CAPRI)

    def test_removes_only_its_command_from_a_shared_group(self):
        file = self.home/'claude/settings.json'
        file.parent.mkdir()
        shared = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node /x/capri-hook.js'}, {'type': 'command', 'command': 'node /y/clawd-hook.js'}]}]}}
        file.write_text(json.dumps(shared))
        self.hooks('uninstall', 'claude')
        self.assertEqual(json.loads(file.read_text()), {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'node /x/capri-hook.js'}]}]}})

    def test_install_preserves_a_symlinked_settings_file(self):
        real = self.home/'dotfiles/settings.json'
        real.parent.mkdir()
        real.write_text(json.dumps(CAPRI))
        link = self.home/'claude/settings.json'
        link.parent.mkdir()
        link.symlink_to(real)
        self.hooks('install', 'claude')
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), real)
        settings = json.loads(real.read_text())
        self.assertTrue(any('clawd-hook.js' in h['command']
                            for groups in settings['hooks'].values() for group in groups for h in group['hooks']))
        self.hooks('uninstall', 'claude')
        self.assertTrue(link.is_symlink())
        self.assertEqual(json.loads(real.read_text()), CAPRI)

    def test_opencode_install_preserves_a_symlinked_plugin(self):
        real = self.home/'dotfiles/clawd-session-watch.js'
        real.parent.mkdir()
        real.write_text('// Clawd session watch\n')
        link = self.home/'config/opencode/plugins/clawd-session-watch.js'
        link.parent.mkdir(parents=True)
        link.symlink_to(real)
        data = self.hooks('install', 'opencode')['data']
        self.assertTrue(data['installed'])
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), real)
        self.assertIn('Clawd session watch', real.read_text())
        self.hooks('uninstall', 'opencode')
        self.assertFalse(link.exists())
        self.assertFalse(link.is_symlink())

    def test_missing_files_and_bad_files(self):
        self.assertFalse(self.hooks('uninstall', 'codex')['data']['changed'])
        self.assertFalse((self.home/'codex').exists())  # uninstall never creates a file
        self.assertTrue(self.hooks('install', 'codex')['data']['installed'])
        self.assertEqual(list((self.home/'codex').glob('*backup*')), [])
        for bad in ('{nope', '[]', '{"hooks": []}', '{"hooks": {"Stop": [{"command": "x"}]}}'):
            with self.subTest(bad=bad):
                file = self.home/'claude/settings.json'
                file.parent.mkdir(exist_ok=True)
                file.write_text(bad)
                out = self.hooks('install', 'claude')
                self.assertFalse(out['ok'])
                self.assertIn('nothing changed', out['error'])
                self.assertEqual(file.read_text(), bad)
        self.assertFalse(self.hooks('remove', 'claude')['ok'])
        self.assertFalse(self.hooks('status', 'antigravity')['ok'])

    def test_without_clawd_uninstalls_both_agents(self):
        for agent in ('claude', 'codex', 'statusline'):
            self.hooks('install', agent)
        self.assertTrue(self.hooks('status', 'statusline')['data']['installed'])
        subprocess.run([sys.executable, '-c', 'import clawd; clawd.uninstall_hooks()'], cwd=ROOT, env=self.env, check=True, timeout=20)
        for agent in ('claude', 'codex'):
            self.assertFalse(self.hooks('status', agent)['data']['events'])
        self.assertNotIn('statusLine', json.loads((self.home/'claude/settings.json').read_text()))

    def test_statusline_install_wraps_and_restores(self):
        file = self.home/'claude/settings.json'
        backups = lambda: sorted(file.parent.glob('settings.json.clawd-backup-*'))
        # empty: a plain relay with no output
        data = self.hooks('install', 'statusline')['data']
        self.assertEqual((data['installed'], data['wrapped'], data['changed']), (True, None, True))
        self.assertEqual(json.loads(file.read_text())['statusLine'], {'type': 'command', 'command': 'node ' + str(STATUS), 'padding': 0})
        self.assertEqual(backups(), [])  # nothing to back up
        self.assertFalse(self.hooks('install', 'statusline')['data']['changed'])
        data = self.hooks('uninstall', 'statusline')['data']
        self.assertEqual((data['installed'], data['changed']), (False, True))
        self.assertEqual(json.loads(file.read_text()), {})
        # foreign: wrapped, other keys kept, backup, idempotent, restored exactly
        original = "bash -c 'echo \"$(cat | jq -r .model.display_name)\" it''s fine'"
        foreign = {**CAPRI, 'statusLine': {'type': 'command', 'command': original, 'padding': 2, 'refreshInterval': 5}}
        file.write_text(json.dumps(foreign))
        status = self.hooks('status', 'statusline')['data']
        self.assertEqual((status['installed'], status['wrapped']), (False, None))
        before = len(backups())
        data = self.hooks('install', 'statusline')['data']
        self.assertEqual((data['installed'], data['wrapped'], data['changed']), (True, original, True))
        self.assertEqual(len(backups()), before + 1)
        settings = json.loads(file.read_text())
        self.assertEqual({k: v for k, v in settings['statusLine'].items() if k != 'command'}, {'type': 'command', 'padding': 2, 'refreshInterval': 5})
        self.assertEqual(shlex.split(settings['statusLine']['command']), ['node', str(STATUS), '--', original])
        self.assertEqual(settings['hooks'], CAPRI['hooks'])
        self.assertFalse(self.hooks('install', 'statusline')['data']['changed'])
        self.assertEqual(len(backups()), before + 1)  # no backup spam
        self.assertTrue(self.hooks('install', 'claude')['data']['installed'])  # hooks and status line coexist
        self.hooks('uninstall', 'claude')
        self.assertEqual(self.hooks('status', 'statusline')['data']['wrapped'], original)
        data = self.hooks('uninstall', 'statusline')['data']
        self.assertEqual((data['installed'], data['wrapped'], data['changed']), (False, None, True))
        self.assertEqual(json.loads(file.read_text()), foreign)
        # foreign is never touched by uninstall
        stamp = file.read_text()
        self.assertFalse(self.hooks('uninstall', 'statusline')['data']['changed'])
        self.assertEqual(file.read_text(), stamp)
        file.write_text(json.dumps({'statusLine': 'not an object'}))
        out = self.hooks('install', 'statusline')
        self.assertFalse(out['ok'])
        self.assertIn('nothing changed', out['error'])
        self.assertFalse(self.hooks('uninstall', 'statusline')['data']['changed'])
        self.assertIn('if without_clawd:\n        clawd.uninstall_hooks()', (ROOT/'install.py').read_text())


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class ClawdHookScriptTests(unittest.TestCase):
    def send(self, payload, *args, runtime):
        started = time.monotonic()
        result = subprocess.run(['node', str(HOOK), *args], input=payload, env=dict(os.environ, XDG_RUNTIME_DIR=str(runtime)), capture_output=True, text=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        self.assertLess(time.monotonic() - started, 3)

    def test_silent_without_shell_and_on_garbage(self):
        with tempfile.TemporaryDirectory() as runtime:
            for payload in ('', 'nope', '{}', json.dumps({'hook_event_name': 'Stop'})):
                self.send(payload, runtime=runtime)

    def test_sends_one_slim_line(self):
        with tempfile.TemporaryDirectory() as runtime:
            (Path(runtime)/'serpantinum').mkdir()
            server = socket.socket(socket.AF_UNIX)
            server.bind(str(Path(runtime)/'serpantinum/clawd.sock'))
            server.listen()
            server.settimeout(5)
            lines = []
            def accept(count):
                for _ in range(count):
                    conn, _ = server.accept()
                    lines.append(conn.makefile().read())
                    conn.close()
            reader = threading.Thread(target=accept, args=(2,))
            reader.start()
            secret = {'prompt': 'my secret prompt', 'tool_input': {'command': 'TOKEN=s3cret curl -H "auth: hunter2" https://x/y'}, 'last_assistant_message': 'reply'}
            self.send(json.dumps({'hook_event_name': 'PreToolUse', 'session_id': 's' * 200, 'cwd': '/home/u/Projects/Clawd', 'tool_name': 'Bash', **secret}), runtime=runtime)
            self.send(json.dumps({'hook_event_name': 'PermissionRequest', 'session_id': 'c', 'cwd': '/w', 'tool_name': 'exec_command'}), '--agent', 'codex', runtime=runtime)
            reader.join(10)
            server.close()
            self.assertEqual(len(lines), 2)
            self.assertTrue(all(line.endswith('\n') and line.count('\n') == 1 for line in lines))
            for leak in ('s3cret', 'hunter2', 'https://x', 'secret prompt', 'reply'):
                self.assertNotIn(leak, lines[0])
            claude, codex = (json.loads(line) for line in lines)
            for evt in (claude, codex):
                pids = evt.pop('pids')  # the hook's ancestors, starting with whoever ran it (this test)
                self.assertEqual(pids[0], os.getpid())
                self.assertTrue(all(isinstance(p, int) and p > 1 for p in pids))
            self.assertEqual(claude, {'agent': 'claude', 'event': 'PreToolUse', 'session_id': 's' * 80, 'tool_name': 'Bash', 'dir': 'Clawd', 'target': 'curl'})
            self.assertEqual(codex, {'agent': 'codex', 'event': 'Notification', 'session_id': 'c', 'tool_name': 'exec_command', 'notification_type': 'permission_prompt', 'dir': 'w'})

    def test_slim_targets_are_short_and_never_full_inputs(self):
        cases = [  # (tool, tool_input, expected target)
            ('Read', {'file_path': '/home/u/secret/dir/notes.md'}, 'notes.md'),
            ('Edit', {'file_path': '/a/b/main.py', 'old_string': 'password', 'new_string': 'x'}, 'main.py'),
            ('Write', {'file_path': '/a/b/c\u0007lean.txt', 'content': 'body'}, 'clean.txt'),
            ('MultiEdit', {'file_path': '/a/' + 'x' * 60}, 'x' * 24),
            ('NotebookEdit', {'notebook_path': '/n/book.ipynb'}, 'book.ipynb'),
            ('NotebookRead', {'notebook_path': '/n/read.ipynb'}, 'read.ipynb'),
            ('Bash', {'command': 'git push --force origin main'}, 'git'),
            ('Bash', {'command': '  API_KEY=sk-123 DEBUG=1 /usr/local/bin/npm run build'}, 'npm'),
            ('Bash', {'command': 'FOO=bar'}, None),
            ('Bash', {'command': 'API_KEY="sk-1 2" TOKEN=\'tok 9\' curl -s x'}, 'curl'),  # quoted values with spaces
            ('Bash', {'command': '"/opt/my app/run.sh" go'}, 'run.sh'),
            ('Bash', {'command': '"$(cat ~/.ssh/key)" x'}, None),
            ('Bash', {'command': 'echo \u202eevil'}, 'echo'),
            ('Bash', {'command': ['ls']}, 'ls'),
            ('exec_command', {'cmd': 'rg -n password src/'}, 'rg'),
            ('exec_command', {'cmd': ['/usr/bin/python3', '-c', 'print(1)']}, 'python3'),
            ('shell', {'command': ['bash', '-lc', 'rm -rf /tmp/x']}, 'bash'),
            ('local_shell', {'command': 'X=1 cargo test --all'}, 'cargo'),
            ('Grep', {'pattern': 'TODO|FIXME', 'path': '/secret'}, 'TODO|FIXME'),
            ('Grep', {'pattern': 'a\u202eb\u2066c'}, 'abc'),  # bidi overrides would reorder the line on screen
            ('Glob', {'pattern': '**/*.' + 'q' * 40}, ('**/*.' + 'q' * 40)[:24]),
            ('WebFetch', {'url': 'https://docs.example.com/a/b?token=abc', 'prompt': 'summarize'}, 'docs.example.com'),
            ('WebFetch', {'url': 'not a url'}, None),
            ('WebSearch', {'query': 'quickshell region mask'}, 'quickshell region mask'),
            ('web_search', {'query': 'q' * 30}, 'q' * 24),
            ('Task', {'description': 'Explore hooks', 'prompt': 'long secret instructions'}, 'Explore hooks'),
            ('Agent', {'description': 'Review'}, 'Review'),
            ('TodoWrite', {'todos': [{'content': 'a', 'status': 'completed'}, {'content': 'b', 'status': 'in_progress'}, {'content': 'c', 'status': 'pending'}]}, '1/3'),
            ('update_plan', {'plan': [{'step': 'a', 'status': 'completed'}, {'step': 'b', 'status': 'completed'}]}, '2/2'),
            ('apply_patch', {'input': '*** Begin Patch'}, None),
            ('mcp__x__y', {'q': 'z'}, None),
            ('Read', 'garbage', None),
        ]
        events = [{'hook_event_name': 'PreToolUse', 'tool_name': tool, 'tool_input': data, 'session_id': 'k'} for tool, data, _ in cases]
        events += [{'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_input': {'command': 'ls'}},
                   {'hook_event_name': 'SessionStart', 'model': 'gpt-5.5-codex'}, {'hook_event_name': 'Stop', 'model': 'm' * 60},
                   {'hook_event_name': 'StopFailure', 'session_id': 'k', 'prompt': 'secret'}]
        script = 'const {slim} = require(process.argv[1]); console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0, "utf8")).map(slim)))'
        result = subprocess.run(['node', '-e', script, str(HOOK)], input=json.dumps(events), capture_output=True, text=True, timeout=10, check=True)
        out = json.loads(result.stdout)
        for (tool, data, expected), evt in zip(cases, out):
            with self.subTest(tool=tool, input=data):
                self.assertEqual(evt.get('target'), expected)
                self.assertEqual(set(evt) - {'agent', 'event', 'session_id', 'tool_name', 'target'}, set())
        post, start, stop, failure = out[len(cases):]
        self.assertNotIn('target', post)
        self.assertEqual(start['model'], 'gpt-5.5-codex')
        self.assertEqual(stop['model'], 'm' * 40)
        self.assertEqual(failure, {'agent': 'claude', 'event': 'StopFailure', 'session_id': 'k'})
        for leak in ('password', 'sk-123', 'sk-1', 'tok 9', '.ssh', 'secret', 'token=abc', 'summarize', 'rm -rf', 'print(1)', 'Begin Patch'):
            self.assertNotIn(leak, result.stdout)


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class ClawdSubagentTests(unittest.TestCase):
    def test_subagent_events_carry_its_model_and_tokens_from_its_transcript(self):
        root = Path(tempfile.mkdtemp(prefix='clawd-sub-'))
        self.addCleanup(shutil.rmtree, root)
        main = root/'s1.jsonl'
        (root/'s1'/'subagents').mkdir(parents=True)
        reply = {'type': 'assistant', 'message': {'role': 'assistant', 'model': 'claude-sonnet-5-5',
                 'usage': {'input_tokens': 2, 'cache_creation_input_tokens': 509, 'cache_read_input_tokens': 155258}}}
        (root/'s1'/'subagents'/'agent-abc.jsonl').write_text(
            '{"cut": \n' + json.dumps({'type': 'user', 'message': {'role': 'user', 'content': 'secret prompt'}}) + '\n'
            + json.dumps(reply) + '\n' + json.dumps({'type': 'user', 'message': {'role': 'user', 'content': 'tool result'}}) + '\n')
        base = {'hook_event_name': 'PreToolUse', 'session_id': 's1', 'transcript_path': str(main), 'agent_type': 'general-purpose'}
        events = [
            dict(base, tool_name='Read', tool_input={'file_path': '/x/y.qml'}, agent_id='abc'),
            dict(base, hook_event_name='SubagentStop', agent_id='abc'),
            dict(base, tool_name='Read', agent_id='../etc'),   # never a file name
            dict(base, tool_name='Read', agent_id='missing'),  # no transcript yet: the id only
        ]
        script = 'const {slim} = require(process.argv[1]); console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0, "utf8")).map(slim)))'
        result = subprocess.run(['node', '-e', script, str(HOOK)], input=json.dumps(events), capture_output=True, text=True, timeout=10, check=True)
        first, stop, invalid, missing = json.loads(result.stdout)
        self.assertEqual((first['agent_id'], first['agent_type'], first['target']), ('abc', 'general-purpose', 'y.qml'))
        self.assertEqual((first['sub_model'], first['sub_tokens']), ('claude-sonnet-5-5', 2 + 509 + 155258))
        self.assertEqual((stop['event'], stop['sub_tokens']), ('SubagentStop', 2 + 509 + 155258))
        self.assertNotIn('agent_id', invalid)
        self.assertNotIn('sub_tokens', invalid)
        self.assertEqual(missing['agent_id'], 'missing')
        self.assertNotIn('sub_tokens', missing)
        for leak in ('secret prompt', 'tool result', 'cut', str(root)):
            self.assertNotIn(leak, result.stdout)


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class ClawdStatusLineTests(unittest.TestCase):
    STDIN = {'session_id': 'sess-1', 'cwd': '/home/u/Projects/Clawd', 'transcript_path': '/secret/t.jsonl',
             'model': {'id': 'claude-opus-5-5', 'display_name': 'Opus 5.5'}, 'workspace': {'current_dir': '/ignored'},
             'effort': {'level': 'xhigh'}, 'cost': {'total_cost_usd': 7.25, 'total_duration_ms': 1000},
             'context_window': {'used_percentage': 42.5, 'context_window_size': 200000},
             'rate_limits': {'five_hour': {'used_percentage': 63, 'resets_at': 1793000000}, 'seven_day': {'used_percentage': 20}}}

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='clawd-status-'))
        self.addCleanup(shutil.rmtree, self.dir)
        (self.dir/'serpantinum').mkdir()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.dir), CLAUDE_CONFIG_DIR=str(self.dir/'claude'))

    def listen(self):
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(self.dir/'serpantinum/clawd.sock'))
        server.listen()
        server.settimeout(5)
        lines = []
        def accept():
            try:
                conn, _ = server.accept()
                lines.append(conn.makefile().read())
                conn.close()
            except OSError:
                pass
        reader = threading.Thread(target=accept)
        reader.start()
        def stop():
            reader.join(10)
            server.close()
            return lines
        return stop

    def run_line(self, command, payload):
        started = time.monotonic()
        result = subprocess.run(['sh', '-c', command], input=payload, env=self.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - started, 3)
        return result.stdout

    def installed(self, original=None):
        file = self.dir/'claude/settings.json'
        file.parent.mkdir(exist_ok=True)
        file.write_text(json.dumps({'statusLine': {'type': 'command', 'command': original}} if original else {}))
        subprocess.run([sys.executable, str(HOOKS), 'install', 'statusline'], env=self.env, capture_output=True, check=True, timeout=20)
        return json.loads(file.read_text())['statusLine']['command']

    def test_unwrapped_sends_one_status_line_and_prints_nothing(self):
        stop = self.listen()
        self.assertEqual(self.run_line(self.installed(), json.dumps(self.STDIN).encode()), b'')
        lines = stop()
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].endswith('\n') and lines[0].count('\n') == 1)
        evt = json.loads(lines[0])
        pids = evt.pop('pids')  # the status line's ancestors (the sh it runs through, this test...)
        self.assertTrue(pids and all(isinstance(p, int) and p > 1 for p in pids))
        self.assertEqual(evt, {'agent': 'claude', 'event': 'Status', 'session_id': 'sess-1', 'dir': 'Clawd', 'model': 'Opus 5.5', 'effort': 'xhigh',
                               'ctx': 42.5, 'ctx_size': 200000, 'cost': 7.25, 'five_hour': 63, 'seven_day': 20, 'five_hour_resets': 1793000000})
        self.assertNotIn('secret', lines[0])

    def test_wrapped_forwards_original_stdout_byte_exact(self):
        # The original echoes its stdin back, then raw non-UTF-8 bytes, then fails: we still exit 0 with its exact output.
        original = "cat; printf '\\001\\377 end\\n'; exit 3"
        command = self.installed(original)
        payload = dict(self.STDIN, workspace={'current_dir': '/x/fromworkspace'}, cwd=None, cost={'total_cost_usd': 'NaN'}, effort=None,
                       context_window={'used_percentage': None}, rate_limits={})
        raw = json.dumps(payload).encode()
        stop = self.listen()
        self.assertEqual(self.run_line(command, raw), raw + b'\x01\xff end\n')
        lines = stop()
        self.assertEqual(len(lines), 1)
        evt = json.loads(lines[0])
        evt.pop('pids')
        self.assertEqual(evt, {'agent': 'claude', 'event': 'Status', 'session_id': 'sess-1', 'dir': 'fromworkspace', 'model': 'Opus 5.5'})
        # no shell running: still forwards, still fast; garbage stdin too
        (self.dir/'serpantinum/clawd.sock').unlink(missing_ok=True)
        self.assertEqual(self.run_line(command, b'not json'), b'not json\x01\xff end\n')
        self.assertEqual(self.run_line('node ' + shlex.quote(str(STATUS)), b''), b'')


class ClawdVerbsTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='clawd-verbs-'))
        self.addCleanup(shutil.rmtree, self.dir)
        for sub in ('bin', 'versions', 'claude', 'cache', 'empty'): (self.dir/sub).mkdir()
        self.env = dict(os.environ, HOME=str(self.dir), PATH=str(self.dir/'bin'), CLAUDE_CONFIG_DIR=str(self.dir/'claude'), XDG_CACHE_HOME=str(self.dir/'cache'))
        self.names = ['Accomplishing'] + [f'Verb{i}ing' for i in range(60)] + ['Flamb\\xE9ing', 'Saut\\u00e9ing', "Beboppin'", 'Quote\\"d']
        blob = b'\0' * 4096 + b'var X=["Accomplishing",1];' + b'\x7fELF junk' * 100 + ('[' + ','.join(f'"{n}"' for n in self.names) + '];var Y=1').encode() + b'\0' * 4096
        self.binary = self.dir/'versions/2.1.999'
        self.binary.write_bytes(blob)
        self.binary.chmod(0o755)
        (self.dir/'bin/claude').symlink_to(self.binary)
        self.expected = ['Accomplishing'] + [f'Verb{i}ing' for i in range(60)] + ['Flambéing', 'Sautéing', "Beboppin'", 'Quote"d']

    def verbs(self, **env):
        started = time.monotonic()
        result = subprocess.run([sys.executable, str(VERBS)], env=dict(self.env, **env), capture_output=True, text=True, timeout=20)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertTrue(out['ok'])
        return out['data']

    def test_reads_binary_applies_settings_and_caches(self):
        self.assertEqual(self.verbs(), {'verbs': self.expected, 'source': 'binary', 'mode': 'default'})
        settings = self.dir/'claude/settings.json'
        settings.write_text(json.dumps({'spinnerVerbs': {'mode': 'append', 'verbs': ['Clawding', 'Verb1ing', '', 7]}}))
        self.assertEqual(self.verbs(), {'verbs': self.expected + ['Clawding'], 'source': 'binary', 'mode': 'append'})
        settings.write_text(json.dumps({'spinnerVerbs': {'mode': 'replace', 'verbs': ['Napping', 'Snoozing']}}))
        os.utime(settings, ns=(time.time_ns(), time.time_ns() + 10**9))
        self.assertEqual(self.verbs(), {'verbs': ['Napping', 'Snoozing'], 'source': 'binary', 'mode': 'replace'})
        settings.write_text(json.dumps({'spinnerVerbs': {'mode': 'replace', 'verbs': []}}))
        os.utime(settings, ns=(time.time_ns(), time.time_ns() + 2 * 10**9))
        self.assertEqual(self.verbs()['verbs'], self.expected)  # replace with nothing keeps the built-in list
        # cache hit: same size and mtime -> the binary is not read again
        stat = self.binary.stat()
        self.binary.write_bytes(self.binary.read_bytes().replace(b'Verb1ing', b'Verb1ong'))
        os.utime(self.binary, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        self.assertEqual(self.verbs()['verbs'], self.expected)
        self.assertTrue((self.dir/'cache/serpantinum-addons-v2/clawd-verbs.json').is_file())
        os.utime(self.binary, ns=(stat.st_atime_ns, stat.st_mtime_ns + 10**9))
        self.assertIn('Verb1ong', self.verbs()['verbs'])

    def test_spaced_array_and_shell_without_local_bin_in_path(self):
        # a cli.js with spaces between items, found in ~/.local/bin although PATH misses it
        self.binary.write_bytes(('x = [' + ', '.join(f'"{n}"' for n in self.names) + ' ];').encode())
        (self.dir/'.local/bin').mkdir(parents=True)
        (self.dir/'.local/bin/claude').symlink_to(self.binary)
        self.assertEqual(self.verbs(PATH=str(self.dir/'empty')), {'verbs': self.expected, 'source': 'binary', 'mode': 'default'})

    def test_fallback_without_claude(self):
        data = self.verbs(PATH=str(self.dir/'empty'))
        self.assertEqual((data['source'], data['mode']), ('fallback', 'default'))
        self.assertTrue(5 <= len(data['verbs']) <= 30 and all(v.endswith('ing') for v in data['verbs']))
        self.binary.write_bytes(b'["Accomplishing","only","three"]')  # too short to be the real list
        self.assertEqual(self.verbs(XDG_CACHE_HOME=str(self.dir/'cache2'))['source'], 'fallback')
        (self.dir/'claude/settings.json').write_text(json.dumps({'spinnerVerbs': {'mode': 'append', 'verbs': ['Clawding']}}))
        data = self.verbs(PATH=str(self.dir/'empty'))
        self.assertEqual((data['source'], data['mode'], data['verbs'][-1]), ('fallback', 'append', 'Clawding'))


@unittest.skipUnless(shutil.which('node'), 'node unavailable')
class ClawdJsTests(unittest.TestCase):
    def node(self, script, marker):
        result = subprocess.run(['node', str(ROOT/'tests/clawd'/script)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(marker, result.stdout)

    def test_world_geometry(self):
        self.node('world.mjs', 'CLAWD_WORLD_PASS')

    def test_mind_rules_budget_cooldowns(self):
        self.node('mind.mjs', 'CLAWD_MIND_PASS')

    def test_beat_detector(self):
        self.node('beat.mjs', 'CLAWD_BEAT_PASS')

    def test_idle_specials_plans(self):
        self.node('acts.mjs', 'CLAWD_ACTS_PASS')

    def test_dreams_registry_and_sleep_events(self):
        self.node('dreams.mjs', 'CLAWD_DREAMS_PASS')

    def test_effort_colours_table(self):
        self.node('effort.mjs', 'CLAWD_EFFORT_PASS')

    def test_chat_brain_sidecar(self):
        if not (ROOT/'tests/clawd/chat.cjs').exists():
            self.skipTest('tests/clawd/chat.cjs does not exist yet')
        result = subprocess.run(['node', str(ROOT/'tests/clawd/chat.cjs')], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


@unittest.skipUnless(shutil.which('qml6'), 'Qt qml runtime unavailable')
class ClawdBlastRenderTests(unittest.TestCase):
    """The singularity scene on the GPU (offscreen OpenGL), a few moments of its storyboard checked by their pixels."""
    SCENE = """import QtQuick
import "%s" as C
Window {
    id: win
    width: 640; height: 360; visible: true; color: "black"
    property var times: [%s]
    property int i: 0
    Rectangle { id: desk; anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#3080c0" } GradientStop { position: 1; color: "#c0a040" } } }
    C.ClawdBlast {
        id: scene
        anchors.fill: parent
        desk: desk
        pixel: 2
        manifest: %s
        pose: ({ x: 40, y: 300, animation: "idle", frame: 0, mirrored: false })
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (win.i >= win.times.length) { Qt.quit(); return; }
            const t = win.times[win.i];
            if (scene.t !== t) { scene.t = t; return; }
            win.i++;
            win.contentItem.grabToImage(r => r.saveToFile("%s/t" + t + ".png"));
        }
    }
}
"""
    TIMES = [0.5, 1.5, 16.5, 19.3, 25.5, 33, 36.6]

    def test_storyboard_moments(self):
        from PIL import Image, ImageStat
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'scene.qml').write_text(self.SCENE % (PAYLOAD.as_uri(), ', '.join(map(str, self.TIMES)), (SPRITES/'clawd.json').read_text(), out))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['qml6', str(out/'scene.qml')], env=env, capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            self.assertNotRegex(output, r'ClawdBlast|shader|Shader|TypeError|ReferenceError', output)
            frames = {}
            for t in self.TIMES:
                if not (out/f't{t}.png').is_file():
                    self.skipTest('no offscreen GPU rendering here: ' + output[-300:])
                frames[t] = Image.open(out/f't{t}.png').convert('RGB')
            mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
            self.assertLess(mean(frames[0.5]), 1)                     # before the freeze: nothing drawn
            self.assertGreater(mean(frames[1.5]), 60)                 # the frozen desktop
            self.assertLess(mean(frames[16.5], (0, 0, 80, 60)), 40)   # the silence: drained, only his glow left...
            self.assertGreater(mean(frames[16.5], (300, 160, 340, 200)), 200)  # ...but him, white-hot in the middle
            self.assertGreater(mean(frames[19.3]), mean(frames[16.5]))  # the annihilation lights everything up
            self.assertLess(mean(frames[25.5], (316, 176, 324, 184)), 2)  # the horizon of the hole
            self.assertLess(mean(frames[33]), 1)                       # the blackout
            if not Image.open(out/'t36.6.png').mode == 'RGBA':
                return
            alpha = Image.open(out/'t36.6.png').getchannel('A')
            self.assertLess(ImageStat.Stat(alpha).mean[0], 30)         # the pulse revealed the live desktop again


class ClawdSymphonyRenderTests(unittest.TestCase):
    """The weekly reset on the GPU (offscreen OpenGL): a few moments of its storyboard checked by their pixels."""
    TIMES = [1.1, 3.3, 13.5, 18.9, 19.7, 26.9, 27.8]
    SCENE = """
import QtQuick
import QtQuick.Window
import "%s" as C
Window {
    id: win
    width: 640; height: 360; visible: true; color: "#2b2d3a"
    property var times: [%s]
    property int i: 0
    C.ClawdSymphony { id: scene; anchors.fill: parent; pixel: 2; ox: 100; oy: 300; floorY: 330; manifest: %s }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (win.i >= win.times.length) { Qt.quit(); return; }
            const t = win.times[win.i];
            if (scene.t !== t) { scene.t = t; return; }
            win.i++;
            win.contentItem.grabToImage(r => r.saveToFile("%s/t" + t + ".png"));
        }
    }
}
"""

    def test_storyboard_moments(self):
        from PIL import Image, ImageStat
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'scene.qml').write_text(self.SCENE % (PAYLOAD.as_uri(), ', '.join(map(str, self.TIMES)), (SPRITES/'clawd.json').read_text(), out))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['qml6', str(out/'scene.qml')], env=env, capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            self.assertNotRegex(output, r'ClawdSymphony|shader|Shader|TypeError|ReferenceError', output)
            frames = {}
            for t in self.TIMES:
                if not (out/f't{t}.png').is_file():
                    self.skipTest('no offscreen GPU rendering here: ' + output[-300:])
                frames[t] = Image.open(out/f't{t}.png').convert('RGB')
            mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
            red = lambda image: ImageStat.Stat(image).mean[0] - ImageStat.Stat(image).mean[2]
            sat = lambda image: ImageStat.Stat(image.convert('HSV')).mean[1]
            self.assertGreater(red(frames[1.1]), 40)                    # the curtains are closed: red velvet everywhere
            self.assertLess(mean(frames[3.3], (200, 40, 440, 220)), 60)  # the dark hall behind the open curtains
            self.assertGreater(mean(frames[13.5], (100, 20, 540, 200)), mean(frames[3.3], (100, 20, 540, 200)) + 8)  # the pillars and staves light it
            self.assertLess(sat(frames[18.9]), sat(frames[13.5]) * 0.6)   # the silence drains the colour
            self.assertGreater(mean(frames[19.7]), mean(frames[13.5]))   # the final chord
            self.assertGreater(red(frames[26.9]), 40)                    # the curtains close again
            self.assertLess(mean(frames[27.8], (200, 100, 440, 250)), mean(frames[19.7], (200, 100, 440, 250)))


class ClawdSurgeRenderTests(unittest.TestCase):
    """The superpowered weekly scene on the GPU (offscreen OpenGL): a few moments of its storyboard checked by their pixels."""
    TIMES = [0.2, 3.2, 5.02, 5.1, 13.9, 21.5, 29.1, 43.59]

    def test_storyboard_moments(self):
        from PIL import Image, ImageStat
        scene = ClawdSymphonyRenderTests.SCENE.replace('C.ClawdSymphony { id: scene;', 'C.ClawdSurge { id: scene; desk: null; verbs: ["Pondering"];')
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'scene.qml').write_text(scene % (PAYLOAD.as_uri(), ', '.join(map(str, self.TIMES)), (SPRITES/'clawd.json').read_text(), out))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['qml6', str(out/'scene.qml')], env=env, capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            self.assertNotRegex(output, r'ClawdSurge|shader|Shader|TypeError|ReferenceError', output)
            frames = {}
            for t in self.TIMES:
                if not (out/f't{t}.png').is_file():
                    self.skipTest('no offscreen GPU rendering here: ' + output[-300:])
                frames[t] = Image.open(out/f't{t}.png').convert('RGB')
            mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
            base = mean(frames[0.2], (0, 0, 120, 80))
            self.assertGreater(mean(frames[3.2], (0, 0, 120, 80)), base + 40)            # light bleeding in at the top-left corner
            self.assertGreater(mean(frames[5.02]), 150)                                    # impact frame: white
            self.assertLess(mean(frames[5.1]), 110)                                       # impact frame: black
            alpha = lambda t, box: ImageStat.Stat(Image.open(out/f't{t}.png').convert('RGBA').getchannel('A').crop(box)).mean[0]
            self.assertGreater(alpha(13.9, (0, 0, 640, 60)), 150)                          # dark while zoomed on his wink
            colours = frames[21.5].crop((0, 280, 640, 330)).getcolors(1 << 20)
            self.assertTrue(any(abs(r - 0xFF) < 8 and abs(g - 0xC1) < 8 and b < 40 for _, (r, g, b) in colours))  # the low helper, #FFC107
            self.assertGreater(mean(frames[29.1], (40, 0, 600, 200)), mean(frames[21.5], (40, 0, 600, 200)) + 10)  # six beams
            self.assertLess(alpha(43.59, (0, 0, 640, 360)), 10)                            # gone again


class ClawdDreamRenderTests(unittest.TestCase):
    """The dream and the nightmare on the GPU (offscreen OpenGL), hosted by ClawdDream: a few moments checked by their pixels."""
    SURF = '({ id: "surf", kind: "dream", scene: "ClawdDreamSurf", duration: 24 })'
    GEMINI = '({ id: "gemini", kind: "nightmare", scene: "ClawdNightmareGemini", duration: 11.7, jump: 11 })'

    def render(self, entry, times):
        from PIL import Image
        scene = ClawdSymphonyRenderTests.SCENE.replace('C.ClawdSymphony { id: scene;', 'C.ClawdDream { id: scene; entry: ' + entry + ';').replace('ox: 100; oy: 300', 'ox: 300; oy: 302')
        directory = tempfile.mkdtemp(prefix='clawd-dream-')
        self.addCleanup(shutil.rmtree, directory)
        out = Path(directory)
        (out/'scene.qml').write_text(scene % (PAYLOAD.as_uri(), ', '.join(map(str, times)), (SPRITES/'clawd.json').read_text(), out))
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['qml6', str(out/'scene.qml')], env=env, capture_output=True, text=True, timeout=90)
        output = result.stdout + result.stderr
        self.assertNotRegex(output, r'ClawdDream|ClawdNightmare|shader|Shader|TypeError|ReferenceError', output)
        frames = {}
        for t in times:
            if not (out/f't{t}.png').is_file():
                self.skipTest('no offscreen GPU rendering here: ' + output[-300:])
            frames[t] = Image.open(out/f't{t}.png').convert('RGB')
        return frames

    def test_rainbow_surf(self):
        from PIL import ImageStat
        frames = self.render(self.SURF, [0.02, 2, 7, 15.2, 23.99])  # QML writes 2.0 as 2
        mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
        diff = lambda a, b, box: sum(abs(x - y) for x, y in zip(ImageStat.Stat(a.crop(box)).mean, ImageStat.Stat(b.crop(box)).mean))
        self.assertLess(diff(frames[0.02], frames[23.99], (0, 0, 640, 360)), 6)        # nothing yet / gone again: the bare backdrop
        self.assertGreater(diff(frames[2], frames[0.02], (0, 0, 80, 60)), 15)         # the violet vignette in the corner
        hues = {round(h / 43) for _, (h, s, v) in frames[7].crop((0, 240, 640, 320)).convert('HSV').getcolors(1 << 20) if s > 90 and v > 150}
        self.assertGreaterEqual(len(hues), 5)                                           # the rainbow wave
        sky = lambda t: mean(frames[t], (200, 60, 440, 160))
        self.assertGreater(sky(15.2), sky(7) + 5)                                     # he flies high above it

    def test_gemini_nightmare(self):
        from PIL import ImageStat
        frames = self.render(self.GEMINI, [3, 8.5, 11.2])
        mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
        stat = lambda t, box=None: ImageStat.Stat(frames[t].crop(box) if box else frames[t]).mean
        self.assertLess(mean(frames[3]), 25)                                            # the cold dark room
        r, g, b = stat(8.5, (250, 90, 390, 180))
        self.assertGreater(r, g + 25)                                                   # her red eyes light up
        r, g, b = stat(11.2)
        self.assertGreater(r, g + 40)                                                   # the jumpscare fills the screen, red
        self.assertGreater(mean(frames[11.2], (0, 0, 640, 360)), mean(frames[8.5]))


class ClawdNukeRenderTests(unittest.TestCase):
    """The nuclear variant on the GPU (offscreen OpenGL), a few moments of its storyboard checked by their pixels."""
    TIMES = [0.2, 2.5, 8, 9.8, 9.9, 10.2, 12, 19.85]

    def test_storyboard_moments(self):
        from PIL import Image, ImageStat
        scene = ClawdBlastRenderTests.SCENE.replace('C.ClawdBlast {', 'C.ClawdNuke {\n        floor: 340').replace('pose: ({ x: 40, y: 300,', 'pose: ({ x: 40, y: 312,')
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'scene.qml').write_text(scene % (PAYLOAD.as_uri(), ', '.join(map(str, self.TIMES)), (SPRITES/'clawd.json').read_text(), out))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['qml6', str(out/'scene.qml')], env=env, capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            self.assertNotRegex(output, r'ClawdNuke|shader|Shader|TypeError|ReferenceError', output)
            frames = {}
            for t in self.TIMES:
                if not (out/f't{t}.png').is_file():
                    self.skipTest('no offscreen GPU rendering here: ' + output[-300:])
                frames[t] = Image.open(out/f't{t}.png').convert('RGB')
            mean = lambda image, box=None: sum(ImageStat.Stat(image.crop(box) if box else image).mean) / 3
            red = lambda image: ImageStat.Stat(image).mean[0] - ImageStat.Stat(image).mean[2]
            self.assertLess(mean(frames[0.2]), 1)                       # before the freeze: nothing drawn
            self.assertGreater(red(frames[2.5]), red(frames[8]) + 10)    # the red alarm while he panics...
            self.assertLess(mean(frames[8], (0, 0, 80, 60)), mean(frames[2.5], (0, 0, 80, 60)) - 20)  # ...then slow motion closes in
            for t in (9.8, 9.9):                                         # impact frames: black and white only
                self.assertLessEqual(sum(frames[t].convert('L').histogram()[41:215]) / (640 * 360), 0.08)
            self.assertNotAlmostEqual(mean(frames[9.8]), mean(frames[9.9]), delta=10)
            self.assertGreater(mean(frames[10.2]), 230)                  # the flash
            self.assertGreater(mean(frames[12], (300, 120, 340, 200)), mean(frames[12], (0, 0, 40, 40)))  # the fire lights the cloud's middle
            self.assertGreater(mean(frames[12]), mean(frames[8]))
            if Image.open(out/'t19.85.png').mode == 'RGBA':
                self.assertLess(ImageStat.Stat(Image.open(out/'t19.85.png').getchannel('A')).mean[0], 30)  # faded out over the live desktop


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
class ClawdRuntimeTests(unittest.TestCase):
    def test_pet_lifecycle_play_drag_sleep_summon(self):
        self.run_fixture('clawd_runtime.qml', 90)

    def test_world_windows_ledges_peek_reactions(self):
        self.run_fixture('clawd_world.qml', 130)

    def test_shell_events_music_notifications_moods(self):
        self.run_fixture('clawd_events.qml', 150)

    def test_sleep_dreams_nightmares_collection(self):
        self.run_fixture('clawd_dreams.qml', 120)

    def test_settings_card_controls(self):
        self.run_fixture('clawd_settings.qml', 40)

    def test_chat_vision_double_click(self):
        # fake codex / grim / hyprctl in a temp bin dir: the real sidecar (brain.js) is driven through the real overlay
        bins = {
            'CLAWD_CODEX': ('codex', '''#!/usr/bin/env node
const a = process.argv.slice(2);
const fs = require('fs');
fs.mkdirSync(process.env.CODEX_HOME, {recursive: true});
fs.appendFileSync(process.env.CODEX_HOME + '/argv.log', JSON.stringify(a) + '\\n');
if (a[0] === 'login') { console.log('Logged in using ChatGPT'); process.exit(0); }
const img = a.includes('-i') || a.includes('--image') ? ' [img]' : '';
console.log(JSON.stringify({type: 'thread.started', thread_id: 'fake-thread'}));
console.log(JSON.stringify({type: 'item.completed', item: {id: 'item_0', type: 'agent_message', text: 'bonjour from fake' + img}}));
console.log(JSON.stringify({type: 'turn.completed', usage: {input_tokens: 1, output_tokens: 1}}));
'''),
            'CLAWD_GRIM': ('grim', '#!/bin/sh\nfor last; do :; done\nif [ "$last" = "-" ]; then printf "\\377\\330\\377\\340fake"; else printf "\\377\\330\\377\\340fake" > "$last"; fi\n'),
            'CLAWD_HYPRCTL': ('hyprctl', '#!/bin/sh\necho \'[{"id":0,"name":"offscreen","x":0,"y":0,"width":1280,"height":720,"scale":1.0,"focused":true}]\'\n'),
        }
        logs = {}
        def after(fixture):
            logs['argv'] = (fixture/'codex/argv.log').read_text() if (fixture/'codex/argv.log').exists() else ''
        self.run_fixture('clawd_chat.qml', 90, bins=bins, after=after)
        calls = [json.loads(line) for line in logs['argv'].splitlines() if line]
        sends = [c for c in calls if c and c[0] != 'login']
        self.assertEqual(len(sends), 2, logs['argv'])
        self.assertFalse(any('-i' in c for c in sends[:1]), 'first message has no image')
        self.assertIn('-i', sends[1], 'look sends the screenshot')

    def run_fixture(self, scenario, timeout, bins=None, after=None):
        with tempfile.TemporaryDirectory(prefix='serpantinum-clawd-test-') as directory:
            fixture = Path(directory)
            shutil.copytree(PAYLOAD, fixture/'clawd')
            # No layer-shell offscreen: the real overlay in a plain window (the layer surface and mask are checked live).
            overlay = (fixture/'clawd/ClawdOverlay.qml').read_text()
            for line in ('    anchors { top: true; bottom: true; left: true; right: true }\n', '    exclusionMode: ExclusionMode.Ignore\n', '    focusable: menuHere || chatHere\n',
                         '    WlrLayershell.namespace: "qs-addon-clawd"\n', '    WlrLayershell.layer: WlrLayer.Top\n',
                         '    WlrLayershell.keyboardFocus: (menuHere || chatHere) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n'):
                self.assertIn(line, overlay)
                overlay = overlay.replace(line, '')
            self.assertEqual(overlay.count('PanelWindow {'), 1)
            (fixture/'clawd/ClawdOverlay.qml').write_text(overlay.replace('PanelWindow {', 'FloatingWindow {\n    implicitWidth: 1280; implicitHeight: 720'))
            # same for the singularity windows; its shaders and the screen capture need a GPU and Wayland (checked live)
            blast = (fixture/'clawd/ClawdSingularity.qml').read_text()
            for line in ('    anchors { top: true; bottom: true; left: true; right: true }\n', '    exclusionMode: ExclusionMode.Ignore\n',
                         '    WlrLayershell.namespace: "qs-addon-clawd-blast"\n', '    WlrLayershell.layer: WlrLayer.Overlay\n',
                         '    WlrLayershell.keyboardFocus: main && scene.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n'):
                self.assertIn(line, blast)
                blast = blast.replace(line, '')
            self.assertEqual(blast.count('PanelWindow {'), 1)
            (fixture/'clawd/ClawdSingularity.qml').write_text(blast.replace('PanelWindow {', 'FloatingWindow {\n    implicitWidth: 1280; implicitHeight: 720'))
            (fixture/'Shell.qml').write_text((ROOT/'tests/qml'/scenario).read_text())
            base = 'singleton Config 1.0 Config.qml\nsingleton Scaler 1.0 Scaler.qml\nsingleton I18n 1.0 I18n.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\nsingleton Caching 1.0 Caching.qml\nsingleton Sounds 1.0 Sounds.qml\n'
            (fixture/'qmldir').write_text(clawd.patch_qmldir(base))
            if scenario == 'clawd_settings.qml':
                shutil.copytree(installer.QS/'reusables', fixture/'reusables')
                shutil.copytree(ROOT/'payload/seasonal', fixture/'seasonal')
                (fixture/'qmldir').write_text(seasonal.patch_qmldir((fixture/'qmldir').read_text()))
            (fixture/'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var rawSettings: ({})
    function getSetting(key, fallback) { return rawSettings[key] === undefined ? fallback : rawSettings[key]; }
    function setSetting(key, value) { const next = Object.assign({}, rawSettings); next[key] = value; rawSettings = next; }
}
''')
            if scenario == 'clawd_events.qml':
                # the shell's singletons, as the shell process has them (clawd_runtime.qml has none: the typeof guards)
                stubs = {'MprisController': 'property bool isPlaying: false; property string trackTitle: ""; '
                                            'property QtObject activePlayer: QtObject { property string identity: "Spotify"; property string desktopEntry: "spotify"; '
                                            'property string busName: "org.mpris.MediaPlayer2.spotify"; property real volume: 1; property bool volumeSupported: true }',
                         'OsdController': 'property real sysVolume: 50; property bool sysMuted: false; property int sysBrightness: 0; property bool isFullscreen: false',
                         'SysNotif': 'property bool hasBattery: false; property int batteryPercentage: 0; property bool isCharging: false',
                         'NotificationManager': 'signal popupAdded(int uid, var notif)',
                         'LauncherController': 'property bool isVisible: false', 'ClipboardController': 'property bool isVisible: false',
                         'DesktopMenuController': 'property bool isVisible: false; property string mode: "desktop"',
                         'TimerState': 'property var entries: []; readonly property bool isActive: entries.length > 0', 'Weather': 'property string currentIcon: ""',
                         'WidgetSync': 'signal geometryChanged(); signal positionChanged(); signal variantChanged(); signal widgetAdded(); signal widgetRemoved(); signal widgetsByTypeRemoved(); signal widgetsCleared(); signal presetApplied(); signal redactModeChanged(string monitor, bool active)',
                         # Cava counts its consumers and plays a pulse (400 ms = 150 BPM) on the low bars
                         'Cava': 'id: cava; property var barLevels: []; property int regs: 0; property int unregs: 0; readonly property int activeConsumers: regs - unregs\n'
                                 '    function registerConsumer() { regs++; }\n    function unregisterConsumer() { unregs++; }\n'
                                 '    property var pulse: Timer { interval: 25; repeat: true; running: cava.activeConsumers > 0; onTriggered: cava.barLevels = new Array(64).fill(Date.now() % 400 < 100 ? 0.8 : 0.05) }'}
                declared = (fixture/'qmldir').read_text()
                for name, body in stubs.items():
                    (fixture/f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{\n    {body}\n}}\n')
                    declared += f'singleton {name} 1.0 {name}.qml\n'
                (fixture/'qmldir').write_text(declared)
            (fixture/'Scaler.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }\n')
            runtime = fixture/'runtime'
            (runtime/'serpantinum').mkdir(mode=0o700, parents=True)
            (fixture/'Caching.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string mainQml: ""; property string serpantinumDir: ""; property string runDir: ' + json.dumps(str(runtime/'serpantinum')) + ' }\n')
            shutil.copytree(ROOT/'scripts/clawd', fixture/'data/serpantinum-addons-v2/scripts/clawd')
            (fixture/'Sounds.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function playSfx(path) {} }\n')
            (fixture/'I18n.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function t(key) { return key; } property string currentLang: "en"; property bool rtl: false; readonly property int layoutDirection: Qt.LeftToRight; readonly property int textAlignment: Qt.AlignLeft }\n')
            (fixture/'ThemeBackend.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string fontFamily: "DejaVu Sans Mono"; property string iconFont: "Iosevka Nerd Font"; property bool liquidGlass: false; property bool glassActive: false; property real elementOpacity: 1; property real borderRadius: 16; property real clampedBorderRadius: 16; '
                                                + '; '.join(f'property color {k}: "{v}"' for k, v in COLORS.items()) + ' }\n')
            env = os.environ.copy()
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE='1',
                       XDG_DATA_HOME=str(fixture/'data'), XDG_STATE_HOME=str(fixture/'state'), XDG_CACHE_HOME=str(fixture/'cache'),
                       XDG_CONFIG_HOME=str(fixture/'config'), HERMES_HOME=str(fixture/'hermes'),
                       CLAUDE_CONFIG_DIR=str(fixture/'claude'), CODEX_HOME=str(fixture/'codex'))
            # Never let a fixture discover the real agent CLIs on this machine (Hermes can block on its state).
            bindir = fixture/'bin'
            bindir.mkdir(exist_ok=True)
            hermes = bindir/'hermes'
            hermes.write_text('#!/bin/sh\nif [ "$1" = plugins ] && [ "$2" = list ]; then echo "[]"; exit 0; fi\nexit 0\n')
            hermes.chmod(0o755)
            env['PATH'] = str(bindir) + os.pathsep + env.get('PATH', '')
            if bins:
                for key, (name, body) in bins.items():
                    (bindir/name).write_text(body)
                    (bindir/name).chmod(0o755)
                    env[key] = str(bindir/name)
            process = subprocess.Popen(['quickshell', '-p', str(fixture/'Shell.qml')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
            if scenario == 'clawd_runtime.qml':
                threading.Thread(target=self.hook_when_listening, args=(runtime, env), daemon=True).start()
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                self.fail('Clawd fixture timed out:\n' + stdout + stderr)
            output = stdout + stderr
            self.assertEqual(process.returncode, 0, output)
            self.assertIn('CLAWD_PASS', output)
            self.assertNotIn('CLAWD_FAIL', output)
            self.assertEqual([line for line in output.splitlines() if re.search(r'clawd/\w+\.qml|Clawd:', line)], [], output)
            self.assertNotRegex(output, r'TypeError|ReferenceError|SyntaxError|RangeError|Binding loop|Cannot assign|Unable to assign')
            if scenario == 'clawd_settings.qml':
                self.assertTrue(json.loads((fixture/'claude/settings.json').read_text())['hooks'])
            if after: after(fixture)
            return output

    @staticmethod
    def hook_when_listening(runtime, env):
        # a real hook event through node and the shell's socket, while Clawd is still OFF
        sock = runtime/'serpantinum/clawd.sock'
        for _ in range(200):
            if sock.exists(): break
            time.sleep(0.05)
        subprocess.run(['node', str(HOOK)], input=json.dumps({'hook_event_name': 'UserPromptSubmit', 'session_id': 'e2e', 'cwd': '/tmp/e2e-dir'}),
                       env=env, capture_output=True, text=True, timeout=10)


if __name__ == '__main__':
    unittest.main()
