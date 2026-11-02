import unittest
from unittest import mock

import input_bridge as bridge


class Device:
    def __init__(self):
        self.events = []

    def write(self, *event):
        self.events.append(event)

    def syn(self):
        pass


class InputTest(unittest.TestCase):
    def test_place_uses_hyprland_lua_dispatcher_and_checks_response(self):
        session = bridge.Input(Device())
        with mock.patch.object(bridge.subprocess, 'run') as run:
            run.return_value.stdout = 'ok\n'
            session.handle({'op': 'place', 'x': -20, 'y': 40})
            self.assertEqual(run.call_args.args[0], [
                'hyprctl', 'dispatch', 'hl.dsp.cursor.move({ x = -20, y = 40 })'])
            run.return_value.stdout = 'error: invalid dispatcher\n'
            with self.assertRaisesRegex(ValueError, 'cursor placement failed'):
                session.handle({'op': 'place', 'x': 1, 'y': 2})

    def test_disconnect_releases_keys_and_buttons(self):
        device = Device()
        session = bridge.Input(device)
        session.handle({'op': 'key', 'code': 30, 'down': True})
        session.handle({'op': 'key', 'code': bridge.e.BTN_LEFT, 'down': True})
        session.release()
        self.assertIn((bridge.e.EV_KEY, 30, 0), device.events)
        self.assertIn((bridge.e.EV_KEY, bridge.e.BTN_LEFT, 0), device.events)
        self.assertFalse(session.held)

    def test_invalid_command_never_reaches_device(self):
        device = Device()
        session = bridge.Input(device)
        with self.assertRaises(ValueError):
            session.handle({'op': 'key', 'code': 9999, 'down': True})
        self.assertFalse(device.events)

    def test_high_resolution_scroll_emits_detents(self):
        device = Device()
        session = bridge.Input(device)
        session.handle({'op': 'scroll', 'x': 0, 'y': 60})
        session.handle({'op': 'scroll', 'x': 0, 'y': 60})
        self.assertIn((bridge.e.EV_REL, bridge.e.REL_WHEEL, 1), device.events)

    def test_keyboard_and_pointer_go_to_separate_devices(self):
        keyboard, pointer = Device(), Device()
        session = bridge.Input(keyboard, pointer)
        session.handle({'op': 'key', 'code': 30, 'down': True})
        session.handle({'op': 'key', 'code': bridge.e.BTN_LEFT, 'down': True})
        session.handle({'op': 'move', 'x': 2, 'y': -1})
        session.release()
        self.assertIn((bridge.e.EV_KEY, 30, 0), keyboard.events)
        self.assertNotIn((bridge.e.EV_KEY, 30, 0), pointer.events)
        self.assertIn((bridge.e.EV_KEY, bridge.e.BTN_LEFT, 0), pointer.events)
        self.assertIn((bridge.e.EV_REL, bridge.e.REL_X, 2), pointer.events)


if __name__ == '__main__':
    unittest.main()
