import importlib.util
import json
import os
import tempfile
import unittest
import urllib.parse
from datetime import datetime
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load(state_dir):
    os.environ['GCAL_STATE_DIR'] = state_dir
    spec = importlib.util.spec_from_file_location('gcal_under_test', ROOT/'scripts/gcal/gcal.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ICS = """BEGIN:VCALENDAR\r
X-WR-CALNAME:Cours\r
BEGIN:VEVENT\r
UID:weekly-1\r
DTSTART;TZID=Europe/Paris:20261102T100000\r
DTEND;TZID=Europe/Paris:20261102T113000\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r
EXDATE;TZID=Europe/Paris:20261104T100000\r
SUMMARY:Algo\\, TD\r
LOCATION:Salle 12\r
DESCRIPTION:Lien https://meet.google.com/abc-defg-hij\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:weekly-1\r
RECURRENCE-ID;TZID=Europe/Paris:20261109T100000\r
DTSTART;TZID=Europe/Paris:20261109T140000\r
DTEND;TZID=Europe/Paris:20261109T153000\r
SUMMARY:Algo moved\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:holiday\r
DTSTART;VALUE=DATE:20261111\r
DTEND;VALUE=DATE:20261112\r
SUMMARY:Armistice\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:daily-old\r
DTSTART:20150101T080000Z\r
DURATION:PT30M\r
RRULE:FREQ=DAILY\r
SUMMARY:Standup with a long\r
 folded title\r
END:VEVENT\r
END:VCALENDAR\r
"""


class GcalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.gcal = load(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop('GCAL_STATE_DIR', None)

    def ms(self, *args):
        return int(datetime(*args).timestamp() * 1000)

    def parse(self):
        lo, hi = self.ms(2026, 11, 1), self.ms(2026, 12, 1)
        return self.gcal.parse_ics(ICS, {'id': 'ics-test'}, lo, hi)

    def test_google_connection_preserves_token_failure_reason(self):
        gcal = self.gcal

        def authorize():
            url = json.loads(gcal.STATE_FILE.read_text())['authUrl']
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
            handler = server.call_args.args[1]
            request = mock.Mock()
            request.path = '/?' + urllib.parse.urlencode({'state': query['state'][0], 'code': 'test-code'})
            handler.do_GET(request)

        with mock.patch.object(gcal.httpserver, 'HTTPServer') as server, \
                mock.patch.object(gcal.signal, 'signal'), \
                mock.patch.object(gcal, 'http', side_effect=gcal.ApiError(401, 'Unauthorized', 'invalid_client')):
            server.return_value.server_port = 12345
            server.return_value.handle_request.side_effect = authorize
            result = gcal.connect('test.apps.googleusercontent.com', 'test-secret', open_browser=False)

        self.assertFalse(result['ok'])
        self.assertEqual(result['reason'], 'invalid_client')
        self.assertIn('Desktop app client', result['error'])
        state = json.loads(gcal.STATE_FILE.read_text())
        self.assertEqual(state['error'], result['error'])
        self.assertEqual(state['authUrl'], '')

    def test_weekly_rule_exdate_and_override(self):
        events, name, _ = self.parse()
        self.assertEqual(name, 'Cours')
        algo = sorted((e for e in events.values() if e['title'].startswith('Algo')), key=lambda e: e['start'])
        starts = [datetime.fromtimestamp(e['start'] / 1000) for e in algo]
        # COUNT=6 → 2,4,9,11,16,18 Nov; 4 Nov excluded; 9 Nov moved to 14:00.
        self.assertEqual([(d.day, d.hour) for d in starts], [(2, 10), (9, 14), (11, 10), (16, 10), (18, 10)])
        self.assertEqual(algo[0]['title'], 'Algo, TD')
        self.assertEqual(algo[1]['title'], 'Algo moved')
        self.assertEqual(algo[0]['meet'], 'https://meet.google.com/abc-defg-hij')
        self.assertEqual(algo[0]['end'] - algo[0]['start'], 90 * 60000)
        self.assertTrue(all(not e['editable'] for e in algo))

    def test_all_day_and_long_daily_series(self):
        events, _, _ = self.parse()
        holiday = next(e for e in events.values() if e['title'] == 'Armistice')
        self.assertTrue(holiday['allDay'])
        self.assertEqual(holiday['start'], self.ms(2026, 11, 11))
        self.assertEqual(holiday['end'], self.ms(2026, 11, 12))
        standups = [e for e in events.values() if e['title'] == 'Standup with a longfolded title']
        self.assertEqual(len(standups), 30)

    def test_monthly_nth_weekday(self):
        start = datetime(2026, 1, 1, 9).astimezone()
        lo, hi = self.ms(2026, 1, 1), self.ms(2026, 7, 1)
        out = self.gcal.expand_rrule(start, 'FREQ=MONTHLY;BYDAY=-1FR', lo, hi, set())
        self.assertEqual([d.day for d in out], [30, 27, 27, 24, 29, 26])

    def test_until_stops_series(self):
        start = datetime(2026, 3, 1, 9).astimezone()
        out = self.gcal.expand_rrule(start, 'FREQ=DAILY;UNTIL=20260305T235959Z', self.ms(2026, 1, 1), self.ms(2027, 1, 1), set())
        self.assertEqual(len(out), 5)

    def test_state_publishes_visibility_and_prefs(self):
        def seed(store):
            store['calendars'] = [{'id': 'a', 'name': 'A', 'source': 'ics', 'color': '#fff'}, {'id': 'b', 'name': 'B', 'source': 'ics', 'color': '#000'}]
            store['prefs']['hidden'] = ['b']
        self.gcal.mutate(seed)
        state = json.loads((Path(self.tmp.name)/'state.json').read_text())
        self.assertEqual([c['visible'] for c in state['calendars']], [True, False])
        self.assertEqual(state['status'], 'disconnected')
        self.assertEqual(oct(os.stat(Path(self.tmp.name)/'store.json').st_mode & 0o777), '0o600')

    def test_edit_without_google_is_refused(self):
        out = self.gcal.apply_mutation('create', {'calendarId': 'primary', 'title': 'x', 'start': 0, 'end': 1})
        self.assertFalse(out['ok'])

    def test_offline_create_is_queued_and_optimistic(self):
        self.gcal.mutate(lambda s: s.update(google={'email': 'me@example.com'}, calendars=[{'id': 'primary', 'writable': True, 'source': 'google', 'color': '#00f', 'name': 'Me'}]))
        with mock.patch.object(self.gcal, 'access_token', side_effect=self.gcal.Offline('down')):
            out = self.gcal.apply_mutation('create', {'calendarId': 'primary', 'title': 'Lunch', 'start': self.ms(2026, 11, 20, 12), 'end': self.ms(2026, 11, 20, 13)})
        self.assertTrue(out['queued'])
        state = json.loads((Path(self.tmp.name)/'state.json').read_text())
        self.assertEqual(state['pending'], 1)
        self.assertEqual(state['events'][0]['title'], 'Lunch')
        self.assertTrue(state['events'][0]['pending'])

    def test_event_body_all_day_and_reminders(self):
        body = self.gcal.event_body({'title': 'T', 'allDay': True, 'start': self.ms(2026, 11, 20), 'end': self.ms(2026, 11, 20),
                                     'reminders': {'useDefault': False, 'overrides': [10, 60]}, 'recurrence': ['RRULE:FREQ=WEEKLY']}, 'Europe/Paris')
        self.assertEqual(body['start'], {'date': '2026-11-20'})
        self.assertEqual(body['end'], {'date': '2026-11-21'})
        self.assertEqual([r['minutes'] for r in body['reminders']['overrides']], [10, 60])

    def test_reminders_due_once(self):
        now = self.ms(2026, 11, 20, 9, 50)
        event = {'id': 'e', 'calendarId': 'c', 'start': self.ms(2026, 11, 20, 10), 'end': self.ms(2026, 11, 20, 11), 'source': 'google',
                 'reminders': {'useDefault': True, 'overrides': []}}
        store = self.gcal.load_store()
        store['calendars'] = [{'id': 'c', 'defaultReminders': [10]}]
        store['events'] = {'e': event}
        self.assertEqual(len(self.gcal.due_reminders(store, now)), 1)
        store['sent']['e|%d|10' % event['start']] = now
        self.assertEqual(self.gcal.due_reminders(store, now), [])


if __name__ == '__main__':
    unittest.main()
