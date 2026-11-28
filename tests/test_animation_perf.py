import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import animation_perf


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell runtime unavailable')
class PulseRuntimeTests(unittest.TestCase):
    def test_capri_report_counter_animates_stops_and_finishes(self):
        source = (ROOT/'payload/capri/CapriPanel.qml').read_text()
        anchor = '        id: counts\n'
        pos = source.index(anchor)
        start = source.rfind('    ', 0, source.rfind('\n', 0, pos) + 1)
        end = source.index('\n    }\n    CapriPlate {', pos) + len('\n    }')
        counter = source[start:end]
        fixture = (ROOT/'tests/qml/capri_counter.qml').read_text().replace('            /* COUNTER_ANIMATION */', counter)
        with tempfile.TemporaryDirectory(prefix='serpantinum-capri-counter-') as directory:
            path = Path(directory)/'Shell.qml'
            path.write_text(fixture)
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=directory)
            env.pop('WAYLAND_DISPLAY', None)
            process = subprocess.Popen(['quickshell', '-p', str(path)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = process.communicate(timeout=3.2)
            except subprocess.TimeoutExpired:
                process.terminate()
                output, _ = process.communicate(timeout=5)
        self.assertNotRegex(output, r'ReferenceError|TypeError|SyntaxError|Binding loop')
        mid = re.search(r'CAPRI_MID\s+(\d+)\s+(true|false)', output)
        end = re.search(r'CAPRI_END\s+([\d.]+)', output)
        self.assertIsNotNone(mid, output)
        self.assertIsNotNone(end, output)
        self.assertGreater(int(mid.group(1)), 25)
        self.assertEqual(mid.group(2), 'true')
        self.assertAlmostEqual(float(end.group(1)), 1.0, delta=0.01)

    def test_lumen_clock_stops_and_resumes_with_visibility(self):
        original = (ROOT/'tests/qml/lumen_clock.qml').read_text()
        patched = animation_perf.lumen_clock(original)
        self.assertNotEqual(original, patched)
        self.assertEqual(patched, animation_perf.lumen_clock(patched))
        with tempfile.TemporaryDirectory(prefix='serpantinum-lumen-test-') as directory:
            path = Path(directory)/'Shell.qml'
            path.write_text(patched)
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=directory)
            env.pop('WAYLAND_DISPLAY', None)
            process = subprocess.Popen(['quickshell', '-p', str(path)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = process.communicate(timeout=4.2)
            except subprocess.TimeoutExpired:
                process.terminate()
                output, _ = process.communicate(timeout=5)
        self.assertNotRegex(output, r'ReferenceError|TypeError|SyntaxError|Binding loop')
        match = re.search(r'LUMEN_RESULT\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)', output)
        self.assertIsNotNone(match, output)
        first, stopped, resumed, hidden, visible = map(int, match.groups())
        self.assertGreater(first, 20)
        self.assertLessEqual(stopped, 1)
        self.assertGreater(resumed, 20)
        self.assertLessEqual(hidden, 1)
        self.assertGreater(visible, 20)

    def test_pulses_start_pause_and_resume(self):
        original = (ROOT/'tests/qml/animation_pulses.qml').read_text()
        patched = animation_perf.volume(animation_perf.network(original))
        self.assertNotEqual(original, patched)
        self.assertEqual(patched, animation_perf.volume(animation_perf.network(patched)))
        with tempfile.TemporaryDirectory(prefix='serpantinum-pulse-test-') as directory:
            path = Path(directory)/'Shell.qml'
            path.write_text(patched)
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=directory)
            env.pop('WAYLAND_DISPLAY', None)
            process = subprocess.Popen(['quickshell', '-p', str(path)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = process.communicate(timeout=3.5)
            except subprocess.TimeoutExpired:
                process.terminate()
                output, _ = process.communicate(timeout=5)
        self.assertNotRegex(output, r'ReferenceError|TypeError|SyntaxError|Binding loop')
        match = re.search(r'PULSE_RESULT\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)', output)
        self.assertIsNotNone(match, output)
        network_start, network_pause, network_resume, volume_start, volume_pause, volume_resume = map(int, match.groups())
        self.assertGreater(network_start, 8)
        self.assertLessEqual(network_pause, 1)
        self.assertGreater(network_resume, 8)
        self.assertGreater(volume_start, 8)
        self.assertLessEqual(volume_pause, 1)
        self.assertGreater(volume_resume, 8)


@unittest.skipUnless(shutil.which('node'), 'Node.js unavailable')
class VisualizerCadenceTests(unittest.TestCase):
    def test_clawd_movement_keeps_its_cadence_on_fast_displays(self):
        source = (ROOT/'payload/clawd/ClawdPet.qml').read_text()
        movement_clock = source.split('readonly property real period: 1 / 60', 1)[1]
        handler = movement_clock.split('onTriggered: {\n', 1)[1].split('\n        }', 1)[0]
        script = r"""
const update = new Function('clock', 'pet', 'frameTime', `
    const period = 1 / 60;
    let pendingTime = clock.pendingTime;
    try { ${process.argv[1]} }
    finally { clock.pendingTime = pendingTime; }
`);
const results = {};
for (const hz of [60, 120, 144, 165, 240]) {
    const clock = {pendingTime: 0};
    let moves = 0;
    const pet = {step: () => moves++};
    for (let frame = 0; frame < hz * 4; frame++) update(clock, pet, 1 / hz);
    results[hz] = moves;
}
console.log(JSON.stringify(results));
"""
        result = subprocess.run(['node', '-e', script, handler], capture_output=True, text=True, timeout=10, check=True)
        for hz, moves in json.loads(result.stdout).items():
            with self.subTest(refresh_rate=hz):
                self.assertIn(moves, (239, 240, 241))

    def test_cadence_and_smoothing_time_across_refresh_rates(self):
        original = (ROOT/'tests/qml/visualizer_clock.qml').read_text()
        patched = animation_perf.visualizer(original)
        self.assertNotEqual(original, patched)
        self.assertEqual(patched, animation_perf.visualizer(patched))
        code = patched.split('        onTriggered: {\n', 1)[1].split('\n\n            let target', 1)[0]
        script = r"""
const step = new Function('levelAnimation', 'frameTime', process.argv[1] + '\nreturn elapsed;');
const results = {};
for (const hz of [60, 75, 90, 120, 144, 165, 240]) {
    const clock = {pendingTime: 0, elapsedTime: 0};
    let count = 0, elapsed = 0;
    for (let i = 0; i < hz * 4; i++) {
        const dt = step(clock, 1 / hz);
        if (dt !== undefined) { count++; elapsed += dt; }
    }
    results[hz] = {count, elapsed};
}
{
    const clock = {pendingTime: 0, elapsedTime: 0};
    let count = 0, elapsed = 0;
    for (let i = 0; i < 240; i++) {
        const dt = step(clock, (1 + 0.25 * Math.sin(i * 0.43)) / 60);
        if (dt !== undefined) { count++; elapsed += dt; }
    }
    results.jittered60 = {count, elapsed};
}
console.log(JSON.stringify(results));
"""
        result = subprocess.run(['node', '-e', script, code], capture_output=True, text=True, timeout=10, check=True)
        for hz, stats in json.loads(result.stdout).items():
            with self.subTest(refresh_rate=hz):
                self.assertGreaterEqual(stats['count'], 238)
                self.assertLessEqual(stats['count'], 300 if hz == '75' else 241)
                self.assertAlmostEqual(stats['elapsed'], 4.0, delta=0.04)


if __name__ == '__main__':
    unittest.main()
