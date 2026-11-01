import importlib.util
import json
import os
import sqlite3
import stat
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

from test_changes import ROOT

sys.path.insert(0, str(ROOT))
import tokens  # noqa: E402

spec = importlib.util.spec_from_file_location('collector', ROOT/'scripts/tokens/collector.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

FAKE = '''#!/usr/bin/env python3
import json, sys, pathlib
mode = pathlib.Path(__file__).with_name('mode').read_text().strip()
if mode == 'down':
    sys.exit(1)
for line in sys.stdin:
    m = json.loads(line)
    if m.get('method') == 'initialize':
        print(json.dumps({'id': m['id'], 'result': {}}), flush=True)
    elif m.get('method') == 'account/usage/read':
        print(json.dumps({'id': m['id'], 'result': json.loads(mode)}), flush=True)
'''


def stamp(offset=0):
    return datetime.fromtimestamp(time.time() - offset, timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')


def codex_event(total, ts=None):
    return json.dumps({'timestamp': ts or stamp(), 'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': {'total_tokens': total, 'input_tokens': total, 'output_tokens': 0}}}}) + '\n'


def claude_event(mid, parts=(10, 5, 100, 1000), ts=None, side=False):
    usage = dict(zip(('input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens'), parts))
    return json.dumps({'type': 'assistant', 'timestamp': ts or stamp(), 'requestId': 'r' + mid, 'isSidechain': side, 'message': {'id': mid, 'usage': usage}}) + '\n'


class TokenTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.codex, self.claude = root/'codex/sessions/2026/11/01', root/'claude/projects/p'
        self.codex.mkdir(parents=True)
        (self.claude/'sub/subagents').mkdir(parents=True)
        fake = root/'fake-codex'
        fake.write_text(FAKE)
        fake.chmod(0o755)
        self.mode = root/'mode'
        self.account(1000)
        collector.CODEX, collector.CLAUDE, collector.STATE, collector.CODEX_CMD = root/'codex/sessions', root/'claude/projects', root/'state', str(fake)
        collector.SETTINGS = root/'settings.json'                                   # no user settings: defaults apply
        self.open()

    def tearDown(self):
        self.c.db.close()
        self.tmp.cleanup()

    def open(self):
        self.c = collector.Collector()

    def account(self, lifetime, buckets=()):
        self.mode.write_text(json.dumps({'summary': {'lifetimeTokens': lifetime}, 'dailyUsageBuckets': [{'startDate': d, 'tokens': t} for d, t in buckets]}))

    def run_once(self, sync=True):
        self.c.scan()
        if sync:
            self.c.sync()
        return self.c.publish(True)

    def write_settings(self, **options):
        collector.SETTINGS.write_text(json.dumps(options))

    def test_opencode_sessions_count_once_and_survive_deletion(self):
        path = Path(self.tmp.name)/'opencode.db'
        db = sqlite3.connect(path)
        db.execute('CREATE TABLE session(id TEXT PRIMARY KEY, tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER)')
        db.execute("INSERT INTO session VALUES('s1', 10, 5, 0, 100, 1)")
        db.execute("INSERT INTO session VALUES('s2', 1, 1, 1, 1, 1)")
        db.commit()
        db.close()
        collector.OPENCODE_DB = path
        self.write_settings(addonsV2TokensOpencode=True)
        self.assertEqual(self.run_once(sync=False)['sources']['opencode']['total'], 116 + 5)
        db = sqlite3.connect(path)
        db.execute("UPDATE session SET tokens_input=200 WHERE id='s1'")
        db.execute("DELETE FROM session WHERE id='s2'")                             # opencode prunes a session
        db.commit()
        db.close()
        self.c.opencode_at = 0
        state = self.run_once(sync=False)
        self.assertEqual((state['sources']['opencode']['total'], state['sources']['opencode']['sessions']), (306 + 5, 2))

    def test_llama_cpp_counters_start_at_zero_and_survive_restarts(self):
        readings = iter([(100, 50), (120, 60), (5, 2)])
        original = collector.llama_counters
        collector.llama_counters = lambda url: next(readings)
        self.addCleanup(setattr, collector, 'llama_counters', original)
        self.write_settings(addonsV2TokensLlamaCpp=True)
        self.c.llama_at = 0
        self.assertEqual(self.run_once(sync=False)['sources']['llamacpp']['total'], 0)     # first reading is the baseline
        self.c.llama_at = 0
        self.assertEqual(self.run_once(sync=False)['sources']['llamacpp']['total'], 30)
        self.c.llama_at = 0
        self.assertEqual(self.run_once(sync=False)['sources']['llamacpp']['total'], 30 + 5 + 2)   # restart: counters begin again at zero

    def test_llama_cpp_url_comes_from_settings(self):
        seen = []
        original = collector.llama_counters
        collector.llama_counters = lambda url: (seen.append(url), (1, 1))[1]
        self.addCleanup(setattr, collector, 'llama_counters', original)
        self.write_settings(addonsV2TokensLlamaCpp=True)
        self.c.llama_at = 0
        self.run_once(sync=False)
        self.assertEqual(seen[-1], 'http://127.0.0.1:8080')                 # default
        self.write_settings(addonsV2TokensLlamaCpp=True, addonsV2TokensLlamaCppUrl=' http://127.0.0.1:8082 ')
        self.c.llama_at = 0
        self.run_once(sync=False)
        self.assertEqual(seen[-1], 'http://127.0.0.1:8082')                 # the URL the user set, trimmed

    def test_disabled_sources_are_left_out_of_the_total(self):
        (self.codex/'rollout-a.jsonl').write_text(codex_event(300))
        self.write_settings(addonsV2TokensCodex=False)
        state = self.run_once(sync=False)
        self.assertEqual((state['codex']['status'], state['combined']['total']), ('off', 0))

    def test_account_baseline_is_included_and_local_growth_adds_once(self):
        log = self.codex/'rollout-a.jsonl'
        log.write_text(codex_event(500) + codex_event(500) + codex_event(800))      # repeated snapshot is not consumption
        state = self.run_once()
        self.assertEqual((state['codex']['account'], state['codex']['pending'], state['codex']['total']), (1000, 800, 1800))
        with log.open('a') as f:
            f.write(codex_event(900))
        self.assertEqual(self.run_once()['codex']['total'], 1900)
        log.write_text(codex_event(500) + codex_event(900))                         # rotated and rewritten: no recount
        self.c.stat.clear()
        self.assertEqual(self.run_once()['codex']['total'], 1900)

    def test_account_catching_up_does_not_double_count(self):
        (self.codex/'rollout-a.jsonl').write_text(codex_event(800))
        day = stamp()[:10]
        self.assertEqual(self.run_once()['codex']['total'], 1800)
        self.account(1800, [(day, 800)])                                             # account now includes today's tokens
        self.assertEqual(self.run_once()['codex']['total'], 1800)

    def test_account_failure_keeps_last_baseline_and_never_decreases(self):
        (self.codex/'rollout-a.jsonl').write_text(codex_event(300))
        before = self.run_once()['codex']['total']
        self.mode.write_text('down')
        state = self.run_once()
        self.assertEqual((state['codex']['total'], state['codex']['status']), (before, 'partial'))
        self.assertTrue(state['codex']['error'])

    def test_missing_baseline_is_reported_not_estimated(self):
        self.mode.write_text('down')
        (self.codex/'rollout-a.jsonl').write_text(codex_event(300))
        state = self.run_once()
        self.assertIsNone(state['codex']['total'])
        self.assertEqual((state['codex']['status'], state['codex']['local'], state['combined']['complete']), ('no-baseline', 300, False))

    def test_forked_thread_replay_counts_the_shared_history_once(self):
        shared = [codex_event(100, '2026-11-01T10:00:00.000Z'), codex_event(250, '2026-11-01T10:01:00.000Z')]
        (self.codex/'rollout-parent.jsonl').write_text(''.join(shared))
        (self.codex/'rollout-fork.jsonl').write_text(''.join(shared) + codex_event(400, '2026-11-01T10:02:00.000Z'))
        self.assertEqual(self.run_once()['codex']['local'], 400)

    def test_claude_dedupes_streams_subagents_and_resumed_sessions(self):
        (self.claude/'s1.jsonl').write_text(claude_event('m1') + claude_event('m1') + claude_event('m2', (1, 2, 3, 4)) + '{"usage" broken\n')
        (self.claude/'sub/subagents/agent-1.jsonl').write_text(claude_event('s1', (7, 7, 7, 7), side=True))
        (self.claude/'s2.jsonl').write_text(claude_event('m1'))                      # resumed conversation replays m1
        state = self.run_once(sync=False)
        self.assertEqual(state['claude']['total'], 1115 + 10 + 28)
        self.assertEqual(state['claude']['cache_read'], 1000 + 4 + 7)
        self.assertEqual(state['corrupt_lines'], 1)

    def test_periods_count_recent_days_only(self):
        (self.claude/'s1.jsonl').write_text(claude_event('m1') + claude_event('m-old', ts='2020-01-01T00:00:00.000Z'))
        state = self.run_once(sync=False)
        self.assertEqual(state['claude']['total'], 1115 * 2)                  # lifetime keeps the old day
        for window in ('today', 'week', 'month'):
            self.assertEqual(state['periods']['claude'][window], 1115)         # the 2020 day is outside every window

    def test_disabled_codex_has_no_windows(self):
        self.write_settings(addonsV2TokensCodex=False)
        (self.claude/'s1.jsonl').write_text(claude_event('m1'))
        self.open()
        state = self.run_once(sync=False)
        self.assertEqual(state['codex']['status'], 'off')
        self.assertEqual(state['periods']['codex'], {})
        self.assertEqual(state['periods']['claude']['today'], 1115)

    def test_claude_message_growth_is_added_once_and_partial_lines_wait(self):
        log = self.claude/'s1.jsonl'
        log.write_text(claude_event('m1', (10, 1, 0, 0)))
        self.assertEqual(self.run_once(sync=False)['claude']['total'], 11)
        log.write_text(log.read_text() + claude_event('m1', (10, 40, 0, 0)))
        self.assertEqual(self.run_once(sync=False)['claude']['total'], 50)
        with log.open('a') as f:
            f.write(claude_event('m3', (5, 5, 0, 0))[:-30])                          # half written line
        self.assertEqual(self.run_once(sync=False)['claude']['total'], 50)
        with log.open('a') as f:
            f.write(claude_event('m3', (5, 5, 0, 0))[-30:])
        self.assertEqual(self.run_once(sync=False)['claude']['total'], 60)

    def test_line_longer_than_a_chunk_does_not_stall_the_log(self):
        log = self.claude/'s1.jsonl'
        log.write_text('{"usage":"' + 'x' * (9 << 20) + '"}\n' + claude_event('m1', (10, 5, 0, 0)))
        self.assertEqual(self.run_once(sync=False)['claude']['total'], 15)

    def test_restart_and_deleted_logs_preserve_totals(self):
        (self.codex/'rollout-a.jsonl').write_text(codex_event(300))
        (self.claude/'s1.jsonl').write_text(claude_event('m1'))
        first = self.run_once()
        self.c.db.close()
        for path in (self.claude/'s1.jsonl', self.codex/'rollout-a.jsonl'):
            path.unlink()                                                             # Claude purges old transcripts
        self.open()
        again = self.run_once(sync=False)
        self.assertEqual(again['combined']['total'], first['combined']['total'])

    def test_state_file_is_private_and_holds_only_counters(self):
        self.run_once()
        path = collector.STATE/'state.json'
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        text = path.read_text().lower()
        for word in ('token"', 'auth', 'bearer', 'secret', 'password'):
            self.assertNotIn(word, text)

    def test_corrupt_database_is_replaced(self):
        self.c.db.close()
        (collector.STATE/'tokens.db').write_bytes(b'not a database' * 100)
        self.open()
        self.assertTrue(list(collector.STATE.glob('tokens.db.corrupt-*')))

    def test_install_hooks_are_idempotent_and_removable(self):
        shell = '    function ensureScreenshotOverlay() {\n    }\n'
        once = tokens.patch_shell(shell)
        self.assertEqual(once, tokens.patch_shell(once))
        self.assertEqual(tokens.remove(once), shell)
        qml = 'Dim 1.0 Dim.qml\n'
        patched = tokens.patch_qmldir(qml)
        self.assertEqual(patched, tokens.patch_qmldir(patched))
        self.assertEqual(tokens.remove(patched), qml)
        for declaration in tokens.TYPES:
            self.assertTrue((ROOT/'payload/tokens'/declaration.split('/')[-1]).is_file())

    def test_unit_runs_the_deployed_script(self):
        self.assertIn('ExecStart=/usr/bin/python3 /x/collector.py', tokens.unit(Path('/x/collector.py'), '/y/codex'))


if __name__ == '__main__':
    unittest.main()
