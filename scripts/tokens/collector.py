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
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time
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

SCHEMA = '''
CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, inode INTEGER, off INTEGER, hw INTEGER DEFAULT 0, seen REAL);
CREATE TABLE IF NOT EXISTS codex_day(day TEXT PRIMARY KEY, tokens INTEGER);
CREATE TABLE IF NOT EXISTS codex_seen(sig INTEGER PRIMARY KEY, ts REAL);
CREATE TABLE IF NOT EXISTS claude_day(day TEXT PRIMARY KEY, input INTEGER, output INTEGER, cache_create INTEGER, cache_read INTEGER);
CREATE TABLE IF NOT EXISTS claude_seen(key INTEGER PRIMARY KEY, total INTEGER, ts REAL);
CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY CHECK(id=1), lifetime INTEGER, buckets TEXT, synced REAL);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
'''


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

    def meta(self, key):
        row = self.db.execute('SELECT v FROM meta WHERE k=?', (key,)).fetchone()
        return row[0] if row else None

    # ---- logs ----
    def files(self):
        for root, kind in ((CODEX, 'codex'), (CLAUDE, 'claude')):
            for dirpath, _, names in os.walk(root):
                for name in names:
                    if name.endswith('.jsonl'):
                        yield os.path.join(dirpath, name), kind

    def scan(self):
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
            self.last_event = time.time()
            self.db.execute("INSERT INTO meta VALUES('last_event', ?) ON CONFLICT(k) DO UPDATE SET v=?", (str(self.last_event),) * 2)

    # ---- account ----
    def sync(self):
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
        claude = {'input': c[0], 'output': c[1], 'cache_creation': c[2], 'cache_read': c[3], 'total': sum(c[:4]), 'since': c[4],
                  'status': 'local' if c[4] else 'empty' if CLAUDE.is_dir() else 'missing'}
        total = (codex['total'] or 0) + claude['total']
        return {'version': 1, 'codex': codex, 'claude': claude,
                'combined': {'total': total, 'complete': codex['status'] == 'ok' and claude['status'] != 'missing'},
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
