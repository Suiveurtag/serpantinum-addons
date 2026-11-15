import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('niri_world', Path(__file__).parents[1] / 'scripts/niri_world.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

class NiriWorldTests(unittest.TestCase):
    def test_global_geometry_and_active_workspace(self):
        state = backend.normalize({'HDMI-A-1': {'logical': {'x': -1920, 'y': 27}}},
            [{'id': 7, 'output': 'HDMI-A-1', 'is_active': True}],
            [{'id': 9, 'pid': 12, 'app_id': 'kitty', 'is_focused': True, 'workspace_id': 7,
              'layout': {'tile_pos_in_workspace_view': [100, 50], 'tile_size': [800, 600]}}])
        self.assertEqual(state['monitors'][0]['activeWorkspace']['id'], 7)
        self.assertEqual(state['clients'][0]['at'], [-1820, 77])
        self.assertEqual(state['clients'][0]['address'], 'niri:9')
        self.assertEqual(state['clients'][0]['focusHistoryID'], 0)

    def test_unpositioned_or_disabled_windows_are_not_ledges(self):
        self.assertEqual(backend.normalize({'off': {'logical': None}}, [], [])['monitors'], [])
        state = backend.normalize({'on': {'logical': {'x': 0, 'y': 0}}},
            [{'id': 1, 'output': 'on', 'is_active': True}],
            [{'id': 2, 'workspace_id': 1, 'layout': {'tile_size': [20, 30]}, 'is_focused': False}])
        self.assertTrue(state['clients'][0]['hidden'])
        self.assertNotIn('at', state['clients'][0])
        self.assertEqual(state['clients'][0]['address'], 'niri:2')

if __name__ == '__main__':
    unittest.main()
