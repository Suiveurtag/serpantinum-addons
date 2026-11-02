import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("hyprland_clipboard", HERE / "hyprland_clipboard.py")
clip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clip)


class ClipboardTests(unittest.TestCase):
    def test_reads_text_and_image_without_adding_newline(self):
        responses = [b'text/plain;charset=utf-8\nimage/png\n', b'bonjour\n', b'PNG DATA']
        with patch.object(clip, '_paste', side_effect=responses) as paste:
            self.assertEqual(clip.read_contents(), ('bonjour\n', b'PNG DATA'))
        self.assertEqual(paste.call_args_list[1].args, ('--no-newline', '--type', 'text/plain;charset=utf-8'))

    def test_does_not_echo_own_selection(self):
        with patch.object(clip, '_paste', return_value=(clip.OWN_MIME + '\nimage/png\n').encode()) as paste:
            self.assertEqual(clip.read_contents(), (None, None))
            self.assertEqual(paste.call_count, 1)

    def test_read_failure_does_not_look_like_success(self):
        with patch.object(clip, '_paste', side_effect=subprocess.TimeoutExpired('wl-paste', 1)):
            with self.assertRaises(OSError):
                clip.read_contents()

    def test_set_sends_both_formats_and_preserves_newline(self):
        with tempfile.TemporaryDirectory() as temp:
            script = Path(temp) / 'offer'
            captured = Path(temp) / 'bytes'
            script.write_text('#!' + sys.executable + '\nimport sys\nfrom pathlib import Path\n'
                              'Path(' + repr(str(captured)) + ').write_bytes(sys.stdin.buffer.read())\n'
                              'sys.stdout.write("1"); sys.stdout.flush()\n')
            script.chmod(0o755)
            with patch.object(clip, 'OFFER', str(script)), patch.object(clip, 'change_stamp', return_value=3):
                self.assertTrue(clip.set_contents('a\r\nb', b'PNG'))
                clip._offer.wait(timeout=2)
                clip._offer.stdout.close()
            self.assertEqual(captured.read_bytes(), b'\0\0\0\3\0\0\0\3a\nbPNG')

    def test_rejects_oversize_without_starting_process(self):
        with patch.object(clip, 'MAX_BYTES', 2), patch.object(clip.subprocess, 'Popen') as spawn:
            self.assertFalse(clip.set_contents('abc', None))
            spawn.assert_not_called()

    def test_paste_stops_reading_at_limit(self):
        with patch.object(clip, 'MAX_BYTES', 8), patch.object(clip, 'WL_PASTE', sys.executable):
            with self.assertRaises(OSError):
                clip._paste('-c', 'import sys; sys.stdout.write("x" * 10000)')

    def test_paste_times_out(self):
        with patch.object(clip, 'TIMEOUT', .1), patch.object(clip, 'WL_PASTE', sys.executable):
            with self.assertRaises(TimeoutError):
                clip._paste('-c', 'import time; time.sleep(3)')


if __name__ == '__main__':
    unittest.main()
