"""Use Beamer's existing barrier/pressure/shortcut logic with Niri capture transport."""
import json
import os
import socket
import types
import uuid


def install():
    import capture_portal as capture
    class Session:
        def __init__(self, bus_factory, ei_factory, tokens, stopping):
            self.portal = self.ei = self.bus = self
            self.handle = '/serpantinum/niri/capture'
            self.enabled = False
            self.owner = uuid.uuid4().hex
            self.connection = None
            self.stream = None
            self.queued_signals = []
            self.queued_events = []
            self.device = types.SimpleNamespace(caps={4})
            self.zones_data = []
            self.activation = 0
            self.was_active = False

        def rpc(self, command, **values):
            if self.connection is None:
                raise capture.CaptureUnavailable('Niri capture connection is closed')
            self.connection.sendall((json.dumps(dict(command=command, owner=self.owner, **values), allow_nan=False) + '\n').encode())
            line = self.stream.readline(2 * 1024 * 1024 + 1)
            if not line or len(line) > 2 * 1024 * 1024:
                raise capture.CaptureUnavailable('Niri capture connection ended')
            reply = json.loads(line)
            if not reply['ok']:
                raise capture.CaptureUnavailable(reply.get('error', 'Niri capture failed'))
            return reply['data']

        def check(self):
            self.connection = socket.socket(socket.AF_UNIX)
            self.connection.settimeout(2)
            self.connection.connect(os.path.join(os.environ['XDG_RUNTIME_DIR'], 'beamer-addon/capture.sock'))
            self.stream = self.connection.makefile('rb')

        def open(self):
            metadata = self.rpc('open')
            keymap = metadata['keymap']
            self.device.keymap = lambda: keymap
            self.zones_data = metadata['zones']
            self.queued_events.append(('device_added', self.device))

        def zones(self):
            self.zones_data = self.rpc('zones')
            return [capture.crossing.Rect(*rect) for rect in self.zones_data]

        def set_barriers(self, positions):
            self.enabled = bool(positions)
            return self.rpc('barriers', positions=positions)['failed_barriers']

        def enable(self):
            self.enabled = True

        def release(self, activation_id, point):
            self.rpc('release', x=float(point[0]), y=float(point[1]))

        def fileno(self):
            return self.connection.fileno()

        def pending(self):
            batch = self.rpc('poll')
            for signal in batch['signals']:
                if signal['member'] == 'Activated':
                    self.activation = signal['options']['activation_id']
                self.queued_signals.append((self.handle, capture.INTERFACE, signal['member'], [self.handle, signal['options']]))
            for event in batch['events']:
                kind = event['kind']
                if kind == 'keymap':
                    text = event['text']
                    self.device.keymap = lambda text=text: text
                    self.queued_events.append(('device_added', self.device))
                elif kind == 'start':
                    self.queued_events.append(('start', self.device, event['activation']))
                elif kind in ('motion', 'scroll', 'scroll_discrete'):
                    self.queued_events.append((kind, self.device, event['dx'], event['dy']))
                elif kind in ('key', 'button'):
                    self.queued_events.append((kind, self.device, event['code'], event['down']))
                elif kind == 'modifiers':
                    self.queued_events.append((kind, self.device, event['depressed'], event['latched'], event['locked'], event['group']))
                elif kind == 'frame':
                    self.queued_events.append(('frame', self.device))
            return bool(self.queued_signals or self.queued_events)

        def signals(self):
            items, self.queued_signals = self.queued_signals, []
            return items

        def events(self):
            items, self.queued_events = self.queued_events, []
            return items

        def abort(self):
            if self.connection is not None:
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass

        def close(self):
            connection, self.connection = self.connection, None
            if connection is not None:
                try:
                    connection.sendall((json.dumps(dict(command='close', owner=self.owner)) + '\n').encode())
                except OSError:
                    pass
                finally:
                    if self.stream is not None:
                        self.stream.close()
                    connection.close()

    capture._Session = Session
