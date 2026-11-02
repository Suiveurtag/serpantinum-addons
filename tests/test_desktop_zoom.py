import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

from test_changes import installer

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/desktop_zoom.py'
spec = importlib.util.spec_from_file_location('desktop_zoom', SCRIPT)
zoom = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zoom)


class ZoomTests(unittest.TestCase):
    def test_limits_reject_nonfinite_input(self):
        self.assertEqual(zoom.clamp(-3), 1)
        self.assertEqual(zoom.clamp(20), 6)
        for value in (float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                zoom.clamp(value)

    def test_custom_shortcut_and_shell_registration_survive_reinstall(self):
        text = installer.patch_zoom_keybind('')
        custom = text.replace('SUPER + SHIFT + Z', 'CTRL + ALT + F9')
        self.assertEqual(installer.patch_zoom_keybind(custom), custom)
        old = text.split('-- BEGIN serpantinum-addons-v2 desktop zoom scroll')[0] + (
            '-- BEGIN serpantinum-addons-v2 desktop zoom scroll\n'
            'hl.bind("mouse_up", hl.dsp.exec_cmd(' + json.dumps(text.split('"')[3].replace('toggle', 'zoomIn')) + '), { non_consuming = true })\n'
            'hl.bind("mouse_down", hl.dsp.exec_cmd(' + json.dumps(text.split('"')[3].replace('toggle', 'zoomOut')) + '), { non_consuming = true })\n'
            '-- END serpantinum-addons-v2 desktop zoom scroll\n')
        self.assertEqual(installer.patch_zoom_keybind(old), text)
        with self.assertRaises(ValueError):
            installer.patch_zoom_keybind('hl.bind("SUPER + SHIFT + Z", action)')
        shell = installer.patch_shell('ShellRoot {\n    Main {}\n}\n')
        self.assertEqual(installer.patch_shell(shell), shell)
        self.assertEqual(shell.count('AddonDesktopZoom {}'), 1)

    def test_worker_restores_original_options_on_close_eof_and_sigterm(self):
        for action in ('close', 'eof', 'sigterm', 'invalid'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'hypr/test/.socket.sock'
                path.parent.mkdir(parents=True)
                server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                server.bind(str(path))
                server.listen()
                server.settimeout(.1)
                done = threading.Event()
                original = {'zoom_factor': 1.25, 'zoom_rigid': False, 'zoom_detached_camera': True, 'scroll_event_delay': 300}
                commands = []

                def serve():
                    while not done.is_set():
                        try:
                            client, _ = server.accept()
                        except socket.timeout:
                            continue
                        with client:
                            command = client.recv(4096).decode()
                            commands.append(command)
                            if command.startswith('j/getoption'):
                                key = command.split(':')[-1]
                                kind = {'zoom_factor': 'float', 'scroll_event_delay': 'int'}.get(key, 'bool')
                                response = json.dumps({kind: original[key]})
                            elif command == 'j/cursorpos':
                                response = '{"x":-240,"y":300}'
                            else:
                                response = 'ok'
                            client.sendall(response.encode())

                thread = threading.Thread(target=serve)
                thread.start()
                env = dict(os.environ, XDG_RUNTIME_DIR=directory, HYPRLAND_INSTANCE_SIGNATURE='test')
                process = subprocess.Popen([sys.executable, '-u', str(SCRIPT)], env=env,
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    ready = json.loads(process.stdout.readline())
                    self.assertTrue(ready['ready'])
                    self.assertEqual(ready['x'], -240)
                    process.stdin.write('{"factor":3}\n')
                    process.stdin.flush()
                    self.assertGreater(json.loads(process.stdout.readline())['factor'], 1.25)
                    if action == 'close':
                        process.stdin.write('{"close":true}\n'); process.stdin.flush()
                    elif action == 'eof':
                        process.stdin.close(); process.stdin = None
                    elif action == 'sigterm':
                        process.send_signal(signal.SIGTERM)
                    else:
                        process.stdin.write('{"factor":"nan"}\n'); process.stdin.flush()
                    process.communicate(timeout=4)
                    self.assertEqual(process.returncode, 1 if action == 'invalid' else 0)
                    self.assertIn('set_enabled(true)', ''.join(commands))
                    self.assertIn('set_enabled(false)', commands[-2])
                    self.assertIn('zoom_factor=1.25000', commands[-1])
                    self.assertIn('zoom_rigid=false', commands[-1])
                    self.assertIn('zoom_detached_camera=true', commands[-1])
                    self.assertIn('scroll_event_delay=300', commands[-1])
                    self.assertIn('scroll_event_delay=0', ''.join(commands))
                finally:
                    if process.poll() is None:
                        process.kill(); process.communicate()
                    done.set(); thread.join(2); server.close()
