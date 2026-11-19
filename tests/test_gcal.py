import importlib.util
import json
import os
import re
import shutil
import subprocess
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

    def expand(self, start, rule, until=(2028, 1, 1)):
        return [(d.year, d.month, d.day) for d in self.gcal.expand_rrule(start, rule, self.ms(start.year, 1, 1), self.ms(*until), set())]

    def test_advanced_monthly_rules(self):
        start = datetime(2026, 1, 1, 9).astimezone()
        # Last weekday of the month, then the 1st and 15th, then the last day, every 2 months on the 31st.
        self.assertEqual(self.expand(start, 'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1', (2026, 5, 1)),
                         [(2026, 1, 30), (2026, 2, 27), (2026, 3, 31), (2026, 4, 30)])
        self.assertEqual(self.expand(start, 'FREQ=MONTHLY;BYMONTHDAY=1,15', (2026, 3, 1)), [(2026, 1, 1), (2026, 1, 15), (2026, 2, 1), (2026, 2, 15)])
        self.assertEqual(self.expand(start, 'FREQ=MONTHLY;BYMONTHDAY=-1', (2026, 4, 1)), [(2026, 1, 31), (2026, 2, 28), (2026, 3, 31)])
        self.assertEqual(self.expand(datetime(2026, 1, 31, 9).astimezone(), 'FREQ=MONTHLY;INTERVAL=2', (2026, 12, 1)),
                         [(2026, 1, 31), (2026, 3, 31), (2026, 5, 31), (2026, 7, 31)])   # September and November have no 31st

    def test_advanced_yearly_rules(self):
        start = datetime(2026, 11, 26, 9).astimezone()
        self.assertEqual(self.expand(start, 'FREQ=YEARLY;BYMONTH=11;BYDAY=4TH', (2029, 1, 1)), [(2026, 11, 26), (2027, 11, 25), (2028, 11, 23)])
        self.assertEqual(self.expand(datetime(2026, 3, 5, 9).astimezone(), 'FREQ=YEARLY;INTERVAL=2;BYMONTH=3,9', (2029, 1, 1)),
                         [(2026, 3, 5), (2026, 9, 5), (2028, 3, 5), (2028, 9, 5)])
        # A 29 February series skips the years that have none.
        self.assertEqual(self.expand(datetime(2028, 2, 29, 9).astimezone(), 'FREQ=YEARLY', (2033, 1, 1)), [(2028, 2, 29), (2032, 2, 29)])

    def test_weekly_week_start_and_daily_weekday_filter(self):
        # Every 2 weeks on Sunday and Monday: the week start decides which Monday goes with which Sunday.
        start = datetime(2026, 11, 1, 9).astimezone()   # a Sunday
        self.assertEqual(self.expand(start, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU', (2026, 12, 15)),
                         [(2026, 11, 1), (2026, 11, 2), (2026, 11, 15), (2026, 11, 16), (2026, 11, 29), (2026, 11, 30), (2026, 12, 13), (2026, 12, 14)])
        self.assertEqual(self.expand(start, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO', (2026, 12, 15)),
                         [(2026, 11, 1), (2026, 11, 9), (2026, 11, 15), (2026, 11, 23), (2026, 11, 29), (2026, 12, 7), (2026, 12, 13)])
        self.assertEqual(self.expand(datetime(2026, 11, 2, 9).astimezone(), 'FREQ=DAILY;BYDAY=MO,WE;COUNT=3'), [(2026, 11, 2), (2026, 11, 4), (2026, 11, 9)])

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

    def test_reminder_checks_leave_the_public_cache_untouched(self):
        gcal = self.gcal
        now = self.ms(2026, 11, 19, 14, 0)
        event = {
            'id': 'class', 'calendarId': 'school', 'source': 'ics',
            'title': 'Class', 'start': now + 600000, 'end': now + 4200000,
        }
        gcal.mutate(lambda store: store['events'].update({event['id']: event}))
        public_inode = gcal.STATE_FILE.stat().st_ino

        with mock.patch.object(gcal, 'now_ms', return_value=now), mock.patch.object(gcal, 'notify') as notify:
            gcal.check_reminders()
            private_inode = gcal.STORE_FILE.stat().st_ino
            gcal.check_reminders()

        notify.assert_called_once()
        self.assertEqual(notify.call_args.args[1], 10)
        self.assertEqual(gcal.STATE_FILE.stat().st_ino, public_inode)
        self.assertEqual(gcal.STORE_FILE.stat().st_ino, private_inode)

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


@unittest.skipUnless(shutil.which('node'), 'node is needed to run the QML rule model')
class RuleModelTest(unittest.TestCase):
    """The recurrence model in GCal.qml (between its BEGIN/END markers) is plain JavaScript: run it under node."""

    @classmethod
    def setUpClass(cls):
        text = (ROOT/'payload/gcal/GCal.qml').read_text()
        body = re.search(r'// BEGIN rule model.*?\n(.*?)\n\s*// END rule model', text, re.S).group(1)
        names = re.findall(r'^\s*function (\w+)\(', body, re.M)
        cls.script = ('const root = {weekCodes: ["SU","MO","TU","WE","TH","FR","SA"], weekOrder: ["MO","TU","WE","TH","FR","SA","SU"],'
                      ' ruleOf: l => (l || []).find(x => x.indexOf("RRULE:") === 0) || ""};\n' + body
                      + '\n' + ''.join(f'root.{n} = {n};' for n in names) + '\n')

    def run_js(self, code):
        out = subprocess.run(['node', '-e', self.script + code], capture_output=True, text=True, env={**os.environ, 'TZ': 'Europe/Paris'})
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_round_trip_keeps_every_rule(self):
        rules = ['FREQ=DAILY', 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=8', 'FREQ=MONTHLY;BYMONTHDAY=1,15', 'FREQ=MONTHLY;BYMONTHDAY=-1',
                 'FREQ=MONTHLY;BYDAY=3TU', 'FREQ=MONTHLY;BYDAY=-1FR;INTERVAL=3', 'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1',
                 'FREQ=YEARLY;BYMONTH=11;BYDAY=4TH', 'FREQ=YEARLY;BYMONTH=3,9;BYMONTHDAY=5', 'FREQ=WEEKLY;WKST=SU;BYDAY=MO,SU',
                 'FREQ=MONTHLY;BYDAY=5MO', 'FREQ=YEARLY;BYMONTH=11;BYDAY=4FR', 'FREQ=DAILY;BYDAY=MO,WE', 'FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR',
                 'FREQ=WEEKLY;UNTIL=20261231T225959Z;BYDAY=TU']
        got = self.run_js('console.log(JSON.stringify(%s.map(r => { const l = ["RRULE:" + r]; '
                          'return root.canonicalRule(root.buildRule(root.parseRule(l, 1800000000000), false)) === root.canonicalRule(l[0]); })))' % json.dumps(rules))
        self.assertEqual(got, [True] * len(rules))

    def test_until_follows_the_all_day_switch(self):
        got = self.run_js("""const r = "RRULE:FREQ=DAILY;UNTIL=20261231T225959Z";
            console.log(JSON.stringify([root.fixUntil(r, true), root.fixUntil(r, false), root.fixUntil("RRULE:FREQ=DAILY;UNTIL=20261231", false),
            root.parseRule([r], 0).until === new Date(2026, 11, 31).getTime()]))""")
        self.assertEqual(got, ['RRULE:FREQ=DAILY;UNTIL=20261231', 'RRULE:FREQ=DAILY;UNTIL=20261231T225959Z', 'RRULE:FREQ=DAILY;UNTIL=20261231T225959Z', True])

    def test_retarget_and_presets(self):
        got = self.run_js("""const st = root.parseRule(["RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;WKST=SU;COUNT=5"], 0);
            const m = root.retarget(st, "MONTHLY", Date.UTC(2026, 10, 19, 12));
            console.log(JSON.stringify([root.buildRule(m, false), st.extra, root.canonicalRule("RRULE:FREQ=WEEKLY;BYDAY=SA,SU") === root.canonicalRule("RRULE:BYDAY=SA,SU;FREQ=WEEKLY"),
            root.withRule(["RRULE:FREQ=DAILY", "EXDATE:20261120T090000Z"], "RRULE:FREQ=WEEKLY"), root.withRule(["RRULE:FREQ=DAILY", "EXDATE:x"], "")]))""")
        self.assertEqual(got, ['RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=5', ['WKST=SU'], True,
                               ['RRULE:FREQ=WEEKLY', 'EXDATE:20261120T090000Z'], ['EXDATE:x']])


if __name__ == '__main__':
    unittest.main()
