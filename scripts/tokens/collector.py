#!/usr/bin/env python3
"""Lifetime AI token collector for the Serpantinum tokens widget.

Codex: the account's own lifetime total (`codex app-server`, `account/usage/read`, reusing Codex's login; no credential is read here)
is the historical baseline. Local rollouts add only what the account has not counted yet, day by day.
Claude Code: ~/.claude/projects transcripts (subagents included), deduplicated by message id, kept in SQLite so the
total survives Claude deleting old transcripts. Output: state.json (atomic, 0600) which the widget watches.

    collector.py            run forever (systemd user service)
    collector.py once       scan once, print state, exit
    collector.py status     print the last state.json
"""
import calendar
import datetime
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

HOME = Path.home()
CODEX = Path(os.environ.get('TOKENS_CODEX_HOME') or os.environ.get('CODEX_HOME') or HOME/'.codex')/'sessions'
CLAUDE = Path(os.environ.get('TOKENS_CLAUDE_HOME') or HOME/'.claude')/'projects'
STATE = Path(os.environ.get('TOKENS_STATE_DIR') or HOME/'.local/state/serpantinum/tokens')
CODEX_CMD = os.environ.get('TOKENS_CODEX_CMD') or 'codex'
SCAN = 3          # seconds between log scans
SYNC = 600        # seconds between account syncs
ACTIVE = 8        # seconds a token event keeps the live indicator on
PRUNE = 400 * 86400
PERIODS = (('today', 0), ('week', 6), ('month', 29))   # recent windows, in UTC days back from today (Codex and Claude only)
SETTINGS = Path(os.environ.get('QS_SETTINGS') or HOME/'.config/serpantinum/settings.json')
OPENCODE_DB = Path(os.environ.get('TOKENS_OPENCODE_DB') or HOME/'.local/share/opencode/opencode.db')
LLAMA_URL = os.environ.get('TOKENS_LLAMACPP_URL') or 'http://127.0.0.1:8080'
OPENCODE_EVERY = 3    # seconds between reads of opencode's session table
LLAMA_EVERY = 3       # seconds between llama.cpp /metrics reads
HERMES_DB = Path(os.environ.get('TOKENS_HERMES_DB') or HOME/'.hermes/state.db')
HERMES_EVERY = 3      # seconds between reads of Hermes' session database (live indicator only, no totals)
# source -> (shell setting that enables it, default). Codex and Claude were always on; the new sources are opt-in.
OPTIONS = {'codex': ('addonsV2TokensCodex', True), 'claude': ('addonsV2TokensClaude', True),
           'opencode': ('addonsV2TokensOpencode', False), 'llamacpp': ('addonsV2TokensLlamaCpp', False)}

SCHEMA = '''
CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, inode INTEGER, off INTEGER, hw INTEGER DEFAULT 0, seen REAL);
CREATE TABLE IF NOT EXISTS codex_day(day TEXT PRIMARY KEY, tokens INTEGER);
CREATE TABLE IF NOT EXISTS codex_seen(sig INTEGER PRIMARY KEY, ts REAL);
CREATE TABLE IF NOT EXISTS claude_day(day TEXT PRIMARY KEY, input INTEGER, output INTEGER, cache_create INTEGER, cache_read INTEGER);
CREATE TABLE IF NOT EXISTS claude_seen(key INTEGER PRIMARY KEY, total INTEGER, ts REAL);
CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY CHECK(id=1), lifetime INTEGER, buckets TEXT, synced REAL);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS opencode_seen(id TEXT PRIMARY KEY, total INTEGER);
CREATE TABLE IF NOT EXISTS llama_seen(id INTEGER PRIMARY KEY CHECK(id=1), prompt INTEGER, predicted INTEGER, total INTEGER);
'''


def option_enabled(source):
    key, default = OPTIONS[source]
    try:
        return json.loads(SETTINGS.read_text()).get(key, default) is True
    except (OSError, ValueError, AttributeError):
        return default


def llama_url():
    """Where llama-server answers: the URL set in the Addons settings, else TOKENS_LLAMACPP_URL, else 127.0.0.1:8080."""
    try:
        value = json.loads(SETTINGS.read_text()).get('addonsV2TokensLlamaCppUrl')
    except (OSError, ValueError, AttributeError):
        value = None
    return value.strip() if isinstance(value, str) and value.strip() else LLAMA_URL


def opencode_totals():
    """Running token totals per OpenCode session, read-only, across database generations."""
    db = sqlite3.connect(OPENCODE_DB.as_uri() + '?mode=ro', uri=True, timeout=2)
    try:
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        totals = {}
        for table in ('session_v2', 'session'):
            if table not in tables:
                continue
            rows = db.execute(f'SELECT id, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write FROM {table}').fetchall()
            for sid, *values in rows:
                totals.setdefault(sid, sum(num(value) for value in values))
    finally:
        db.close()
    return totals


def hermes_marker():
    """Changes whenever Hermes stores a message or spends tokens. Read-only; None while Hermes has no database."""
    if not HERMES_DB.is_file():
        return None
    db = sqlite3.connect(HERMES_DB.as_uri() + '?mode=ro', uri=True, timeout=2)
    try:
        return tuple(db.execute('SELECT (SELECT max(id) FROM messages), (SELECT coalesce(sum(input_tokens)+sum(output_tokens),0) FROM sessions)').fetchone())
    finally:
        db.close()


def llama_counters(url):
    """Lifetime prompt and generated token counters of a llama-server started with --metrics."""
    with urllib.request.urlopen(url.rstrip('/') + '/metrics', timeout=2) as reply:
        text = reply.read().decode('utf-8', 'replace')
    found = {}
    for line in text.splitlines():
        name, _, value = line.partition(' ')
        if name in ('llamacpp:prompt_tokens_total', 'llamacpp:tokens_predicted_total'):
            found[name] = int(float(value))
    if len(found) != 2:
        raise ValueError('no llama.cpp token counters (start llama-server with --metrics)')
    return found['llamacpp:prompt_tokens_total'], found['llamacpp:tokens_predicted_total']


def h64(text):
    return int.from_bytes(hashlib.blake2b(text.encode(), digest_size=8).digest(), 'big', signed=True)


def num(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 0


def open_db():
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = STATE/'tokens.db'
    try:
        db = sqlite3.connect(path)
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA synchronous=NORMAL')
        db.executescript(SCHEMA)
        db.execute('SELECT count(*) FROM files').fetchone()
    except sqlite3.DatabaseError as error:
        if isinstance(error, sqlite3.OperationalError):
            raise                  # locked, read-only...: transient, never a reason to discard the history
        # Keep the damaged file for inspection and rebuild from the logs and the account.
        db.close() if 'db' in locals() else None
        path.rename(STATE/f'tokens.db.corrupt-{int(time.time())}')
        for suffix in ('-wal', '-shm'):
            (STATE/('tokens.db' + suffix)).unlink(missing_ok=True)
        return open_db()
    os.chmod(path, 0o600)
    return db


class Collector:
    def __init__(self):
        self.db = open_db()
        self.stat = {}          # path -> (mtime_ns, size) already processed
        self.corrupt = 0
        self.last_event = float(self.meta('last_event') or 0)
        self.sync_at = 0.0
        self.sync_error = None
        self.sync_fails = 0
        self.published = None
        self.pub_at = 0.0
        self.importing = False
        self.enabled = {name: option_enabled(name) for name in OPTIONS}
        self.opencode_at = 0.0
        self.opencode_error = None
        self.llama_at = 0.0
        self.llama_error = None
        self.opencode_seen_totals = None   # session id -> total at the previous read: a growing total means a running turn
        self.hermes_at = 0.0
        self.hermes_marker = None

    def meta(self, key):
        row = self.db.execute('SELECT v FROM meta WHERE k=?', (key,)).fetchone()
        return row[0] if row else None

    # ---- logs ----
    def files(self):
        for root, kind in ((CODEX, 'codex'), (CLAUDE, 'claude')):
            if not self.enabled.get(kind):
                continue
            for dirpath, _, names in os.walk(root):
                for name in names:
                    if name.endswith('.jsonl'):
                        yield os.path.join(dirpath, name), kind

    def scan(self):
        self.enabled = {name: option_enabled(name) for name in OPTIONS}
        changed = False
        todo = []
        for path, kind in self.files():
            try:
                st = os.stat(path)
            except OSError:
                continue
            if self.stat.get(path) != (st.st_mtime_ns, st.st_size):
                todo.append((path, kind, st))
        self.importing = len(todo) > 40
        for path, kind, st in todo:
            try:
                changed |= self.read(path, kind, st)
            except OSError:
                continue           # vanished or unreadable: retried on the next change
            self.stat[path] = (st.st_mtime_ns, st.st_size)
        self.poll_sources()
        self.db.commit()
        return changed

    def read(self, path, kind, st):
        row = self.db.execute('SELECT inode, off, hw FROM files WHERE path=?', (path,)).fetchone()
        inode, off, hw = row if row else (st.st_ino, 0, 0)
        if inode != st.st_ino or st.st_size < off:
            off = 0                # rotated or truncated: replays are absorbed by hw and the dedupe tables
        added = False
        with open(path, 'rb') as f:
            f.seek(off)
            while True:              # 8 MB at a time: a huge transcript never sits in memory whole
                data = f.read(8 << 20)
                end = data.rfind(b'\n') + 1   # an incomplete last line waits for its newline
                for raw in data[:end].splitlines():
                    if kind == 'codex':
                        if b'total_token_usage' in raw:
                            hw, hit = self.codex_line(raw, hw)
                            added |= hit
                    elif b'"usage"' in raw:
                        added |= self.claude_line(raw)
                off += end
                if not end and len(data) == 8 << 20:
                    off += len(data)       # one line over 8 MB (a pasted image): skip it, it never carries usage
                    self.corrupt += 1
                elif len(data) < 8 << 20 or not end:
                    break
                f.seek(off)
        self.db.execute('INSERT INTO files(path, inode, off, hw, seen) VALUES(?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET inode=?, off=?, hw=?, seen=?',
                        (path, st.st_ino, off, hw, time.time(), st.st_ino, off, hw, time.time()))
        return added

    def codex_line(self, raw, hw):
        try:
            event = json.loads(raw)
            payload = event['payload']
            usage = payload['info']['total_token_usage']
            total, stamp = num(usage['total_tokens']), event['timestamp']
            day = stamp[:10]
            time.strptime(day, '%Y-%m-%d')
        except (ValueError, KeyError, TypeError):
            self.corrupt += 1
            return hw, False
        if payload.get('type') != 'token_count' or total <= hw:
            return hw, False       # repeated or replayed snapshot: not new consumption
        delta, hw = total - hw, total
        sig = h64(f'{stamp}|{total}|{num(usage.get("input_tokens"))}|{num(usage.get("output_tokens"))}')
        if self.db.execute('SELECT 1 FROM codex_seen WHERE sig=?', (sig,)).fetchone():
            return hw, False       # same event already counted through a forked thread's replayed history
        self.db.execute('INSERT INTO codex_seen VALUES(?,?)', (sig, time.time()))
        self.db.execute('INSERT INTO codex_day VALUES(?,?) ON CONFLICT(day) DO UPDATE SET tokens=tokens+?', (day, delta, delta))
        self.touch(stamp)
        return hw, True

    def claude_line(self, raw):
        try:
            event = json.loads(raw)
            if event.get('type') != 'assistant':
                return False
            message = event['message']
            usage = message['usage']
            parts = [num(usage.get(k)) for k in ('input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')]
            stamp, mid = event['timestamp'], message['id']
            day = stamp[:10]
            time.strptime(day, '%Y-%m-%d')
        except (ValueError, KeyError, TypeError, AttributeError):
            self.corrupt += 1
            return False
        total = sum(parts)
        if not total:
            return False
        key = h64(f'{mid}|{event.get("requestId")}')
        row = self.db.execute('SELECT total FROM claude_seen WHERE key=?', (key,)).fetchone()
        if row and total <= row[0]:
            return False           # streamed duplicate, resumed conversation or rescan
        if row:                    # a later line of the same message carries its final count: book the growth only, as output
            parts = [0, total - row[0], 0, 0]
        self.db.execute('INSERT INTO claude_seen VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET total=?, ts=?', (key, total, time.time(), total, time.time()))
        self.db.execute('INSERT INTO claude_day VALUES(?,?,?,?,?) ON CONFLICT(day) DO UPDATE SET input=input+?, output=output+?, cache_create=cache_create+?, cache_read=cache_read+?',
                        (day, *parts, *parts))
        self.touch(stamp)
        return True

    def touch(self, stamp):
        # Only events from the last minute drive the live indicator, never an import of old history.
        try:
            moment = calendar.timegm(time.strptime(stamp[:19], '%Y-%m-%dT%H:%M:%S'))
        except ValueError:
            return
        if time.time() - moment < 60:
            self.mark_live()

    def mark_live(self):
        self.last_event = time.time()
        self.db.execute("INSERT INTO meta VALUES('last_event', ?) ON CONFLICT(k) DO UPDATE SET v=?", (str(self.last_event),) * 2)

    # ---- other tools ----
    def poll_sources(self):
        now = time.time()
        if self.enabled.get('opencode') and now - self.opencode_at >= OPENCODE_EVERY:
            self.opencode_at = now
            try:
                totals = opencode_totals()
                if self.opencode_seen_totals is not None and any(total > self.opencode_seen_totals.get(sid, 0) for sid, total in totals.items()):
                    self.mark_live()           # a token count grew: an opencode turn is running
                self.opencode_seen_totals = totals
                for sid, total in totals.items():
                    # max(): a session never gives back tokens it already showed, even once opencode deletes it
                    self.db.execute('INSERT INTO opencode_seen VALUES(?,?) ON CONFLICT(id) DO UPDATE SET total=max(total, excluded.total)', (sid, total))
                self.opencode_error = None
            except (sqlite3.Error, OSError, ValueError) as error:
                self.opencode_error = 'unreadable'     # the exception text can carry the database path: keep it out of state.json
            self.db.commit()
        if now - self.hermes_at >= HERMES_EVERY:
            self.hermes_at = now
            try:
                marker = hermes_marker()
            except (sqlite3.Error, OSError):
                marker = None                  # locked or unreadable: judged again on the next read
            if marker is not None:
                if self.hermes_marker is not None and marker != self.hermes_marker:
                    self.mark_live()           # a message or a token count moved: a Hermes turn is running
                self.hermes_marker = marker
        if self.enabled.get('llamacpp') and now - self.llama_at >= LLAMA_EVERY:
            self.llama_at = now
            try:
                prompt, predicted = llama_counters(llama_url())
            except (OSError, ValueError) as error:
                self.llama_error = 'not running'        # server not running: nothing is added until it answers again (no URL in state.json)
                return
            self.llama_error = None
            row = self.db.execute('SELECT prompt, predicted, total FROM llama_seen WHERE id=1').fetchone()
            if row is None:
                self.db.execute('INSERT INTO llama_seen VALUES(1,?,?,0)', (prompt, predicted))   # first reading is the baseline
            else:
                last_prompt, last_predicted, total = row
                # a counter below its last reading means the server restarted: everything it shows is new
                grown = (prompt - last_prompt if prompt >= last_prompt else prompt) + (predicted - last_predicted if predicted >= last_predicted else predicted)
                if grown:
                    self.mark_live()           # the server counted new tokens: a llama.cpp request is running
                self.db.execute('UPDATE llama_seen SET prompt=?, predicted=?, total=? WHERE id=1', (prompt, predicted, total + grown))
            self.db.commit()

    # ---- account ----
    def sync(self):
        if not self.enabled.get('codex'):
            return
        self.sync_at = time.time()
        try:
            result = account_usage()
            lifetime = result['summary']['lifetimeTokens']
            buckets = {b['startDate']: num(b['tokens']) for b in result.get('dailyUsageBuckets') or []}
            if not isinstance(lifetime, int) or isinstance(lifetime, bool) or lifetime < 0:
                raise ValueError('account reports no lifetimeTokens')
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
            self.sync_fails += 1
            self.sync_error = str(error)[:160]    # messages never contain credentials: only our own exceptions are kept
            return
        self.sync_fails, self.sync_error = 0, None
        self.db.execute('INSERT INTO account VALUES(1,?,?,?) ON CONFLICT(id) DO UPDATE SET lifetime=?, buckets=?, synced=?',
                        (lifetime, json.dumps(buckets), time.time(), lifetime, json.dumps(buckets), time.time()))
        self.db.commit()

    def due(self):
        wait = SYNC * min(2 ** self.sync_fails, 6) if self.sync_fails else SYNC
        return time.time() - self.sync_at >= wait

    # ---- output ----
    def periods(self):
        """Tokens per recent window. Days are UTC, like the logs. opencode and llama.cpp keep no per-day history, so they are not here."""
        today = datetime.datetime.now(datetime.timezone.utc).date()
        result = {'codex': {}, 'claude': {}}
        for name, back in PERIODS:
            since = (today - datetime.timedelta(days=back)).isoformat()
            if self.enabled.get('codex'):
                result['codex'][name] = sum(tokens for day, tokens in self.db.execute('SELECT day, tokens FROM codex_day') if day >= since)
            if self.enabled.get('claude'):
                result['claude'][name] = self.db.execute(
                    'SELECT coalesce(sum(input+output+cache_create+cache_read),0) FROM claude_day WHERE day>=?', (since,)).fetchone()[0]
        return result

    def state(self):
        local = dict(self.db.execute('SELECT day, tokens FROM codex_day'))
        acct = self.db.execute('SELECT lifetime, buckets, synced FROM account').fetchone()
        codex = {'local': sum(local.values()), 'local_since': min(local, default=None)}
        if acct:
            buckets = json.loads(acct[1])
            pending = sum(max(0, t - buckets.get(d, 0)) for d, t in local.items())
            codex.update(total=acct[0] + pending, account=acct[0], pending=pending, synced=acct[2],
                         status='partial' if self.sync_error else 'ok')
        else:
            codex.update(total=None, account=None, pending=None, synced=None, status='no-baseline')
        codex['error'] = self.sync_error
        c = self.db.execute('SELECT coalesce(sum(input),0), coalesce(sum(output),0), coalesce(sum(cache_create),0), coalesce(sum(cache_read),0), min(day) FROM claude_day').fetchone()
        try:
            adjustment = max(0, int(self.meta('lifetime_adjustment') or 0))
        except (TypeError, ValueError):
            adjustment = 0
        claude = {'input': c[0], 'output': c[1], 'cache_creation': c[2], 'cache_read': c[3],
                  'adjustment': adjustment, 'total': sum(c[:4]) + adjustment, 'since': c[4],
                  'status': 'local' if c[4] else 'empty' if CLAUDE.is_dir() else 'missing'}
        sources = {}
        if self.enabled.get('opencode'):
            count, sessions = self.db.execute('SELECT coalesce(sum(total),0), count(*) FROM opencode_seen').fetchone()
            sources['opencode'] = {'total': count, 'sessions': sessions, 'status': 'error' if self.opencode_error else 'ok', 'error': self.opencode_error}
        if self.enabled.get('llamacpp'):
            row = self.db.execute('SELECT total FROM llama_seen WHERE id=1').fetchone()
            sources['llamacpp'] = {'total': row[0] if row else 0, 'status': 'error' if self.llama_error else 'ok', 'error': self.llama_error}
        if not self.enabled.get('codex'):
            codex['status'] = 'off'
        if not self.enabled.get('claude'):
            claude['status'] = 'off'
        periods = self.periods()
        codex_total = (codex['total'] or 0) if self.enabled.get('codex') else 0
        claude_total = claude['total'] if self.enabled.get('claude') else 0
        # Manual lifetime correction for historical usage that was not imported
        # from any source transcript/account snapshot.
        total = codex_total + claude_total + sum(source['total'] for source in sources.values())
        complete = codex['status'] in ('ok', 'off') and claude['status'] != 'missing' and not any(source['status'] == 'error' for source in sources.values())
        return {'version': 1, 'codex': codex, 'claude': claude, 'sources': sources, 'periods': periods,
                'combined': {'total': total, 'complete': complete},
                'active': time.time() - self.last_event < ACTIVE, 'importing': self.importing, 'corrupt_lines': self.corrupt}

    def publish(self, force=False):
        state = self.state()
        key = json.dumps(state, sort_keys=True)
        if not force and key == self.published:
            return state
        self.published = key
        state['updated'] = self.pub_at = time.time()
        tmp = STATE/'state.json.tmp'
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(state, f)
        os.replace(tmp, STATE/'state.json')
        return state

    def prune(self):
        cut = time.time() - PRUNE
        self.db.execute('DELETE FROM codex_seen WHERE ts<?', (cut,))
        self.db.execute('DELETE FROM claude_seen WHERE ts<?', (cut,))
        for path, in self.db.execute('SELECT path FROM files WHERE seen<?', (cut,)).fetchall():
            if not os.path.exists(path):   # shortcut: a log gone for 400 days that returns would be rescanned
                self.db.execute('DELETE FROM files WHERE path=?', (path,))
        self.db.commit()


def account_usage():
    """One `account/usage/read` over a short-lived stdio app-server; Codex authenticates it itself."""
    proc = subprocess.Popen([CODEX_CMD, 'app-server', '--listen', 'stdio://'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    watchdog = threading.Timer(30, proc.kill)   # a silent app-server must not stall the daemon: killing it ends readline
    watchdog.start()
    try:
        def call(ident, method, params):
            proc.stdin.write(json.dumps({'id': ident, 'method': method, 'params': params}) + '\n')
            proc.stdin.flush()
            deadline = time.time() + 30
            while time.time() < deadline:
                line = proc.stdout.readline()
                if not line:
                    raise OSError('codex app-server closed')
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if message.get('id') == ident:
                    if 'error' in message:
                        raise ValueError('account/usage/read refused: ' + str((message['error'] or {}).get('message'))[:100])
                    return message['result']
            raise OSError('codex app-server timed out')
        call(1, 'initialize', {'clientInfo': {'name': 'serpantinum-tokens', 'version': '1'}})
        proc.stdin.write('{"method":"initialized"}\n')
        return call(2, 'account/usage/read', {})
    finally:
        watchdog.cancel()
        proc.kill()
        proc.wait()
        proc.stdin.close()
        proc.stdout.close()


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'run'
    if command == 'status':
        print((STATE/'state.json').read_text())
        return
    collector = Collector()
    if command == 'once':
        collector.scan()
        collector.sync()
        print(json.dumps(collector.publish(True), indent=1))
        return
    collector.sync()
    collector.scan()
    collector.publish(True)
    pruned = time.time()
    while True:
        time.sleep(SCAN)
        collector.scan()
        if collector.due():
            collector.sync()
        collector.publish(force=time.time() - collector.pub_at > 60)   # heartbeat: the widget treats an old file as a stopped collector
        if time.time() - pruned > 86400:
            collector.prune()
            pruned = time.time()


if __name__ == '__main__':
    main()
