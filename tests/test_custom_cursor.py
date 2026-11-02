import io
import json
from pathlib import Path
import struct
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import cursor_images as images
import custom_cursor as cursor


def chunk(kind, body):
    return kind + struct.pack('<I', len(body)) + body + (b'\0' if len(body) % 2 else b'')


def windows_cur(color, hotspot=(3, 4)):
    stream = io.BytesIO()
    Image.new('RGBA', (16, 16), color).save(stream, format='PNG')
    data = stream.getvalue()
    return struct.pack('<3H', 0, 2, 1) + struct.pack('<4B2H2I', 16, 16, 0, 0, *hotspot, len(data), 22) + data


class CursorFormatsTest(unittest.TestCase):
    def test_xcursor_roundtrip_keeps_sizes_alpha_hotspots_and_delays(self):
        original = [(32, Image.new('RGBA', (32, 20), (240, 20, 30, 128)), (5, 7), 80),
                    (32, Image.new('RGBA', (32, 20), (10, 200, 30, 255)), (5, 7), 140)]
        frames = images.xcursor_frames(images.encode_frames(original))
        selected = images.closest_frames(frames, 32)
        self.assertEqual([frame[3] for frame in selected], [80, 140])
        pixel = selected[0][1].getpixel((0, 0))
        self.assertTrue(all(abs(actual - expected) <= 1 for actual, expected in zip(pixel, (240, 20, 30, 128))))
        encoded = images.encode_frames(original)
        position = struct.unpack_from('<I', encoded, 24)[0] + 36
        self.assertTrue(all(channel <= encoded[position + 3] for channel in encoded[position:position + 3]))
        self.assertEqual(selected[0][2], (5, 7))
        self.assertEqual({frame[0] for frame in frames}, {16, 24, 32, 48, 64, 96, 128})
        changed = images.xcursor_frames(images.encode_frames(frames, [1, 1]))
        self.assertTrue(all(frame[2] == (frame[1].width - 1, frame[1].height - 1) for frame in changed))

    def test_cur_and_ani_preserve_hotspots_sequence_and_rates(self):
        first = windows_cur('red')
        second = windows_cur('blue', (8, 9))
        self.assertEqual(images.windows_cursor(second)[2], (8, 9))
        header = struct.pack('<9I', 36, 2, 3, 16, 16, 32, 1, 6, 3)
        body = b'ACON' + chunk(b'anih', header) + chunk(b'rate', struct.pack('<3I', 6, 12, 3))
        body += chunk(b'seq ', struct.pack('<3I', 1, 0, 1))
        body += chunk(b'LIST', b'fram' + chunk(b'icon', first) + chunk(b'icon', second))
        frames = images.ani_frames(b'RIFF' + struct.pack('<I', len(body)) + body)
        self.assertEqual([frame[2] for frame in frames], [(8, 9), (3, 4), (8, 9)])
        self.assertEqual([frame[3] for frame in frames], [100, 200, 50])
        self.assertEqual(frames[0][1].getpixel((0, 0)), (0, 0, 255, 255))

    def test_rejects_truncated_and_out_of_bounds_cursor_data(self):
        blob = bytearray(images.encode_frames([(32, Image.new('RGBA', (32, 32)), (0, 0), 50)]))
        with self.assertRaises(ValueError):
            images.xcursor_frames(blob[:70])
        offset = struct.unpack_from('<I', blob, 24)[0]
        struct.pack_into('<I', blob, offset + 24, 5000)
        with self.assertRaises(ValueError):
            images.xcursor_frames(blob)
        with self.assertRaises(ValueError):
            images.windows_cursor(windows_cur('red')[:-2])


class CursorManagerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name)
        self.data = self.home / '.local/share'
        self.config = self.home / '.config'
        self.store = self.data / 'serpantinum-addons-v2/cursor'
        replacements = {'HOME': self.home, 'DATA': self.data, 'CONFIG': self.config,
                        'ADDON': self.data / 'serpantinum-addons-v2', 'STORE': self.store,
                        'STATE': self.store / 'settings.json', 'ASSETS': self.store / 'assets',
                        'CACHE': self.store / 'previews', 'ENV_LUA': self.config / 'hypr/config/env.lua'}
        self.patcher = patch.multiple(cursor, **replacements)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.addCleanup(self.temporary.cleanup)
        self.theme = self.data / 'icons/Base'
        cursors = self.theme / 'cursors'
        cursors.mkdir(parents=True)
        self.original = images.encode_frames([(32, Image.new('RGBA', (32, 32), 'white'), (2, 2), 100)])
        (cursors / 'left_ptr').write_bytes(self.original)
        (cursors / 'default').symlink_to('left_ptr')
        (cursors / '08e8e1c95fe2fc01f976f1e063a24ccd').symlink_to('left_ptr')
        (cursors / 'text').write_bytes(self.original)
        (self.theme / 'index.theme').write_text('[Icon Theme]\nName=Base\n')
        self.roots = patch.object(cursor, 'icon_roots', return_value=[self.data / 'icons', self.home / '.icons'])
        self.roots.start()
        self.addCleanup(self.roots.stop)
        self.settings = {'baseTheme': 'Base', 'size': 40, 'roles': {}}

    def test_scheme_is_self_contained_and_propagates_custom_legacy_aliases(self):
        image = self.home / 'custom.png'
        Image.new('RGBA', (40, 40), 'red').save(image)
        self.settings['roles']['left_ptr'] = {'source': str(image), 'hotspot': [0.5, 0.25]}
        target = self.home / 'Built'
        cursor.build_theme(self.settings, target)
        entries = target / 'cursors'
        self.assertEqual((entries / 'left_ptr').read_bytes(), (entries / '08e8e1c95fe2fc01f976f1e063a24ccd').read_bytes())
        self.assertNotEqual((entries / 'left_ptr').read_bytes(), self.original)
        self.assertEqual((entries / 'text').read_bytes(), self.original)
        self.assertTrue(all(not entry.is_symlink() for entry in entries.iterdir()))
        self.assertTrue(all((entries / role).exists() for role in cursor.ROLES))

    def test_exported_scheme_can_be_reimported_without_changing_current_settings(self):
        result = cursor.export_theme(self.settings)
        self.assertTrue(Path(result['path']).is_file())
        installed = cursor.install_theme(result['path'])['installed']
        self.assertEqual(len(installed), 1)
        self.assertFalse(cursor.STATE.exists())

    def test_custom_pencil_does_not_overwrite_the_crosshair_fallback(self):
        crosshair = self.theme / 'cursors/crosshair'
        crosshair.write_bytes(self.original)
        image = self.home / 'pencil.png'
        Image.new('RGBA', (16, 16), 'blue').save(image)
        self.settings['roles']['pencil'] = {'source': str(image), 'hotspot': None}
        target = self.home / 'Built'
        cursor.build_theme(self.settings, target)
        self.assertEqual((target / 'cursors/crosshair').read_bytes(), self.original)
        self.assertNotEqual((target / 'cursors/pencil').read_bytes(), self.original)

    def test_normal_select_mode_is_uniform_reversible_and_resettable(self):
        pointer = self.home / 'normal.png'
        text = self.home / 'text.png'
        Image.new('RGBA', (32, 32), 'red').save(pointer)
        Image.new('RGBA', (32, 32), 'blue').save(text)
        self.settings['roles'] = {
            'left_ptr': {'source': str(pointer), 'hotspot': [0.25, 0.5]},
            'text': {'source': str(text), 'hotspot': [0.5, 0.5]},
        }
        self.settings['normalOnly'] = True
        target = self.home / 'Uniform'
        cursor.build_theme(self.settings, target)
        normal = (target / 'cursors/left_ptr').read_bytes()
        self.assertTrue(all(path.read_bytes() == normal for path in (target / 'cursors').iterdir()))
        self.assertEqual(self.settings['roles']['text']['source'], str(text))
        self.settings['normalOnly'] = False
        target = self.home / 'Restored'
        cursor.build_theme(self.settings, target)
        self.assertNotEqual((target / 'cursors/text').read_bytes(), normal)
        self.settings['roles'] = {}
        target = self.home / 'Defaults'
        cursor.build_theme(self.settings, target)
        self.assertEqual((target / 'cursors/left_ptr').read_bytes(), self.original)
        self.assertEqual((target / 'cursors/text').read_bytes(), self.original)
        self.assertEqual(cursor.validate_settings(self.settings)['size'], 40)

    def test_normal_select_mode_persists_and_previews_match_the_generated_theme(self):
        pointer = self.home / 'normal.png'
        Image.new('RGBA', (32, 32), 'red').save(pointer)
        self.settings['roles']['left_ptr'] = {'source': str(pointer), 'hotspot': [0.25, 0.75]}
        self.settings['normalOnly'] = True
        with patch.object(cursor, 'run', return_value=''), patch.object(cursor, 'sync_session', return_value=[]):
            result = cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
        self.assertTrue(json.loads(cursor.STATE.read_text())['normalOnly'])
        self.assertTrue(result['settings']['normalOnly'])
        self.assertEqual(len({role['preview'] for role in result['roles']}), 1)
        self.assertEqual(len({tuple(role['hotspot']) for role in result['roles']}), 1)

    def test_reset_announces_a_new_theme_to_invalidate_custom_cursor_caches(self):
        pointer = self.home / 'custom.png'
        Image.new('RGBA', (32, 32), 'red').save(pointer)
        self.settings['roles']['left_ptr'] = {'source': str(pointer), 'hotspot': None}
        environments = []
        commands = []
        def command(args, **kwargs):
            commands.append(args)
            return ''
        def session(environment):
            environments.append(environment)
            return []
        with patch.object(cursor, 'run', side_effect=command), patch.object(cursor, 'sync_session', side_effect=session):
            first = cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
            reset = dict(first['settings'], roles={}, normalOnly=False)
            cursor.apply({'settings': reset, 'revision': cursor.revision()})
        self.assertNotEqual(environments[0]['XCURSOR_THEME'], environments[1]['XCURSOR_THEME'])
        active = environments[-1]['XCURSOR_THEME']
        self.assertEqual(environments[-1]['HYPRCURSOR_THEME'], active)
        self.assertEqual([args for args in commands if args[:2] == ['hyprctl', 'setcursor']][-1][2], active)
        gtk = (self.config / 'gtk-3.0/settings.ini').read_text()
        self.assertIn('gtk-cursor-theme-name=' + active, gtk)
        self.assertIn('cursorTheme=' + active, (self.config / 'kcminputrc').read_text())

    def test_switching_full_themes_updates_runtime_identity_and_preserves_the_previous_scheme(self):
        other = self.data / 'icons/Other'
        (other / 'cursors').mkdir(parents=True)
        blue = images.encode_frames([(32, Image.new('RGBA', (32, 32), 'blue'), (0, 0), 100)])
        (other / 'cursors/left_ptr').write_bytes(blue)
        (other / 'index.theme').write_text('[Icon Theme]\nName=Other\n')
        environments = []
        with patch.object(cursor, 'run', return_value=''), patch.object(cursor, 'sync_session', side_effect=lambda env: environments.append(env) or []):
            first = cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
            first_state = cursor.STATE.read_bytes()
            switched = dict(first['settings'], baseTheme='Other', roles={}, normalOnly=False)
            second = cursor.apply({'settings': switched, 'revision': cursor.revision()})
            third = cursor.apply({'settings': switched, 'revision': cursor.revision()})
        self.assertNotEqual(environments[0]['XCURSOR_THEME'], environments[1]['XCURSOR_THEME'])
        self.assertEqual(environments[1]['XCURSOR_THEME'], environments[2]['XCURSOR_THEME'])
        active = json.loads(cursor.STATE.read_text())['runtimeTheme']
        self.assertEqual((self.data / 'icons' / active / 'cursors/left_ptr').read_bytes(), blue)
        self.assertEqual((Path(second['backup']) / cursor.backup_relative(cursor.STATE)).read_bytes(), first_state)
        self.assertTrue(all(not name.startswith(cursor.THEME) for name in cursor.theme_paths()))

    def test_normal_select_mode_defaults_off_and_rejects_non_boolean_values(self):
        self.assertFalse(cursor.validate_settings(self.settings)['normalOnly'])
        for value in (1, 'true', None, []):
            self.settings['normalOnly'] = value
            with self.assertRaisesRegex(ValueError, 'boolean'):
                cursor.validate_settings(self.settings)

    def test_imported_animation_is_owned_and_survives_original_deletion(self):
        source = self.home / 'animation.gif'
        Image.new('RGBA', (16, 16), 'red').save(source, save_all=True,
             append_images=[Image.new('RGBA', (16, 16), 'blue')], duration=[50, 200], loop=0)
        imported = cursor.import_cursor(source)
        source.unlink()
        self.assertTrue(Path(imported['source']).is_file())
        self.assertEqual(imported['frames'], 2)
        self.assertEqual([frame[3] for frame in images.load_frames(imported['source'])], [50, 200])

    def test_native_import_preserves_original_bytes_and_per_frame_click_points(self):
        frames = [(32, Image.new('RGBA', (32, 32), 'red'), (2, 4), 50),
                  (32, Image.new('RGBA', (32, 32), 'blue'), (9, 7), 120)]
        blob = images.encode_frames(frames)
        source = self.home / 'native.xcursor'
        source.write_bytes(blob)
        imported = cursor.import_cursor(source)
        self.assertIsNone(imported['hotspot'])
        self.settings['roles']['left_ptr'] = imported
        target = self.home / 'Built'
        cursor.build_theme(self.settings, target)
        self.assertEqual((target / 'cursors/left_ptr').read_bytes(), blob)

    def test_rejects_traversal_external_links_and_invalid_hotspots(self):
        for name in ('../../escape', '/absolute'):
            with self.assertRaises(ValueError):
                cursor.safe_relative(name)
        archive = self.home / 'bad.tar'
        with tarfile.open(archive, 'w') as opened:
            entry = tarfile.TarInfo('theme/cursors/left_ptr')
            entry.type = tarfile.SYMTYPE
            entry.linkname = '/etc/passwd'
            opened.addfile(entry)
        destination = self.home / 'extract'
        destination.mkdir()
        with self.assertRaises(ValueError):
            cursor.extract_theme(archive, destination)
        image = self.theme / 'cursors/left_ptr'
        self.settings['roles'] = {'left_ptr': {'source': str(image), 'hotspot': [float('nan'), 0]}}
        with self.assertRaises(ValueError):
            cursor.validate_settings(self.settings)

    def test_theme_archive_materialises_internal_aliases(self):
        archive = self.home / 'theme.tar'
        with tarfile.open(archive, 'w') as opened:
            opened.add(self.theme, arcname='Theme', recursive=True)
        result = cursor.install_theme(archive)
        self.assertEqual(len(result['installed']), 1)
        directory = self.data / 'icons' / result['installed'][0] / 'cursors'
        self.assertEqual((directory / 'default').read_bytes(), self.original)
        self.assertFalse((directory / 'default').is_symlink())

    def test_failed_live_apply_restores_theme_files_and_environment(self):
        target = self.data / 'icons' / cursor.THEME
        (target / 'cursors').mkdir(parents=True)
        (target / 'cursors/left_ptr').write_bytes(self.original)
        cursor.ENV_LUA.parent.mkdir(parents=True)
        cursor.ENV_LUA.write_text('hl.env("KEEP", "yes")\n')
        before = cursor.ENV_LUA.read_bytes()
        def command(args, **kwargs):
            if kwargs.get('required') and args[1] == 'setcursor':
                raise ValueError('simulated compositor failure')
            return ''
        with patch.object(cursor, 'run', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'simulated'):
                cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
        self.assertEqual(cursor.ENV_LUA.read_bytes(), before)
        self.assertEqual((target / 'cursors/left_ptr').read_bytes(), self.original)
        self.assertFalse(cursor.STATE.exists())
        self.assertFalse((self.config / 'gtk-3.0/settings.ini').exists())

    def test_hyprland_parse_error_prevents_persisting_a_broken_scheme(self):
        def command(args, **kwargs):
            return 'unexpected option' if args[1] == 'configerrors' else ''
        with patch.object(cursor, 'run', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'configuration error'):
                cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
        self.assertFalse(cursor.STATE.exists())
        self.assertFalse(cursor.ENV_LUA.exists())
        self.assertFalse((self.data / 'icons' / cursor.THEME).exists())

    def test_symlinked_icon_roots_apply_to_one_theme_directory(self):
        (self.home / '.icons').symlink_to(self.data / 'icons')
        with patch.object(cursor, 'run', return_value=''), patch.object(cursor, 'sync_session', return_value=[]):
            cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
        self.assertEqual((self.home / '.icons' / cursor.THEME / 'cursors/text').read_bytes(), self.original)

    def test_configuration_preserves_other_preferences_and_checks_revision(self):
        gtk = self.config / 'gtk-3.0/settings.ini'
        gtk.parent.mkdir(parents=True)
        gtk.write_text('[Settings]\ngtk-theme-name=KeepMe\ngtk-cursor-theme-name=Old\n[Other]\nx=1\n')
        files, environment = cursor.configuration(48)
        self.assertIn('gtk-theme-name=KeepMe', files[gtk])
        self.assertIn('[Other]\nx=1', files[gtk])
        self.assertIn('gtk-cursor-theme-size=48', files[gtk])
        self.assertEqual(environment['XCURSOR_SIZE'], '48')
        self.assertIn('HYPRCURSOR_SIZE', environment)
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'):
            cursor.apply({'settings': self.settings, 'revision': 'stale'})

    def test_successful_apply_persists_and_mirrors_every_role(self):
        with patch.object(cursor, 'run', return_value=''), patch.object(cursor, 'sync_session', return_value=[]):
            result = cursor.apply({'settings': self.settings, 'revision': cursor.revision()})
        self.assertEqual(json.loads(cursor.STATE.read_text())['size'], 40)
        self.assertEqual(result['settings']['baseTheme'], 'Base')
        self.assertEqual(len(result['roles']), len(cursor.ROLES))
        for role in cursor.ROLES:
            self.assertTrue((self.home / '.icons' / cursor.THEME / 'cursors' / role).exists())


if __name__ == '__main__':
    unittest.main()
