#!/usr/bin/env python3
"""Calendar backend for the Serpantinum calendar addon: Google Calendar (OAuth, read/write) and iCal subscriptions (read only).

The shell never talks to the network itself. It reads STATE/state.json (watched by GCal.qml) and runs this script
for every action; the `daemon` command (systemd user service) keeps the cache fresh, replays offline edits and
sends reminder notifications.

Commands (each prints one JSON line):
  status | sync [--force] | ensure FROM_MS TO_MS | daemon
  connect --client-id ID --client-secret SECRET [--no-browser] | disconnect
  create JSON | update JSON | delete JSON | rsvp JSON | prefs JSON | ics-add JSON | ics-remove ID
"""
import argparse
import base64
import calendar as calmod
import contextlib
import copy
import fcntl
import hashlib
import html
import http.server as httpserver
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

STATE = Path(os.environ.get('GCAL_STATE_DIR') or Path(os.environ.get('XDG_STATE_HOME') or Path.home()/'.local/state')/'serpantinum/gcal')
STATE_FILE = STATE/'state.json'
STORE_FILE = STATE/'store.json'
SECRET_FILE = STATE/'secrets.json'
LOCK_FILE = STATE/'.lock'
API = 'https://www.googleapis.com/calendar/v3'
AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
TOKEN_URL = 'https://oauth2.googleapis.com/token'
REVOKE_URL = 'https://oauth2.googleapis.com/revoke'
USERINFO_URL = 'https://openidconnect.googleapis.com/v1/userinfo'
SCOPES = 'openid email https://www.googleapis.com/auth/calendar'
SYNC_INTERVAL = int(os.environ.get('GCAL_SYNC_INTERVAL') or 300)
KEYRING = ('service', 'serpantinum-gcal')
UA = 'serpantinum-calendar/1'


class Offline(Exception):
    """Network unreachable: the action is queued and replayed later."""


class ApiError(Exception):
    def __init__(self, status, message, code=None):
        super().__init__(message)
        self.status = status
        self.code = code


def now_ms():
    return int(time.time() * 1000)


# --------------------------------------------------------------------------- storage

@contextlib.contextmanager
def locked():
    STATE.mkdir(parents=True, exist_ok=True)
    with open(LOCK_FILE, 'a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def write_json(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name('.' + path.name + '.' + str(os.getpid()))
    with open(tmp, 'w') as stream:
        json.dump(data, stream, ensure_ascii=False, separators=(',', ':'))
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def read_json(path, default):
    try:
        with open(path) as stream:
            return json.load(stream)
    except (OSError, ValueError):
        return copy.deepcopy(default)


DEFAULT_STORE = {
    'google': None,          # {'email', 'clientId'}
    'status': 'disconnected', 'error': '', 'authUrl': '',
    'calendars': [], 'colors': {}, 'events': {}, 'masters': {},
    'ics': [], 'ranges': [], 'queue': [], 'tombstones': {},
    'prefs': {'hidden': [], 'reminders': True, 'defaultCalendar': '', 'weekStart': 1},
    'sent': {}, 'lastSync': 0, 'syncing': False,
}


def load_store():
    store = read_json(STORE_FILE, DEFAULT_STORE)
    for key, value in DEFAULT_STORE.items():
        store.setdefault(key, copy.deepcopy(value))
    for key, value in DEFAULT_STORE['prefs'].items():
        store['prefs'].setdefault(key, value)
    return store


def window():
    today = date.today()
    first = date(today.year, today.month, 1)
    start = add_months(first, -3)
    end = add_months(first, 13)
    return local_ms(start), local_ms(end)


def add_months(day, months):
    month = day.month - 1 + months
    year = day.year + month // 12
    month = month % 12 + 1
    return date(year, month, min(day.day, calmod.monthrange(year, month)[1]))


def local_ms(day):
    return int(datetime(day.year, day.month, day.day).astimezone().timestamp() * 1000)


def save(store):
    """Persist the private store and publish the public state the shell watches."""
    write_json(STORE_FILE, store)
    lo, hi = window()
    for a, b in store['ranges']:
        lo, hi = min(lo, a), max(hi, b)
    hidden = set(store['prefs'].get('hidden') or [])
    calendars = [dict(c, visible=c['id'] not in hidden) for c in store['calendars']]
    events = sorted(store['events'].values(), key=lambda e: (e['start'], -e['end'], e['title']))
    for event in events:
        master = store['masters'].get(event['calendarId'] + '/' + (event.get('recurringEventId') or ''))
        event['recurrence'] = master['recurrence'] if master else event.get('recurrence') or []
    state = {
        'version': 1, 'updated': int(time.time()), 'status': store['status'], 'error': store['error'],
        'authUrl': store['authUrl'], 'google': store['google'], 'calendars': calendars, 'colors': store['colors'],
        'events': events, 'range': {'from': lo, 'to': hi}, 'pending': len(store['queue']),
        'lastSync': store['lastSync'], 'syncing': store['syncing'], 'prefs': store['prefs'],
        'ics': [{k: v for k, v in s.items() if k != 'etag'} for s in store['ics']],
        'tz': local_zone_name(),
    }
    write_json(STATE_FILE, state)


def mutate(fn):
    """Read-modify-write the store under the lock; returns fn's result."""
    with locked():
        store = load_store()
        result = fn(store)
        save(store)
        return result


# --------------------------------------------------------------------------- secrets

def secret_get(kind):
    if shutil.which('secret-tool'):
        try:
            out = subprocess.run(['secret-tool', 'lookup', *KEYRING, 'kind', kind], capture_output=True, text=True, timeout=10)
            if out.returncode == 0 and out.stdout:
                return out.stdout
        except (OSError, subprocess.SubprocessError):
            pass
    return read_json(SECRET_FILE, {}).get(kind)


def secret_set(kind, value):
    if shutil.which('secret-tool'):
        try:
            out = subprocess.run(['secret-tool', 'store', '--label', f'Serpantinum calendar ({kind})', *KEYRING, 'kind', kind],
                                 input=value, capture_output=True, text=True, timeout=10)
            if out.returncode == 0:
                data = read_json(SECRET_FILE, {})
                if data.pop(kind, None) is not None:
                    write_json(SECRET_FILE, data)
                return
        except (OSError, subprocess.SubprocessError):
            pass
    data = read_json(SECRET_FILE, {})
    data[kind] = value
    write_json(SECRET_FILE, data)


def secret_clear():
    if shutil.which('secret-tool'):
        for kind in ('refresh', 'client_secret', 'client_id'):
            subprocess.run(['secret-tool', 'clear', *KEYRING, 'kind', kind], capture_output=True, timeout=10)
    with contextlib.suppress(FileNotFoundError):
        SECRET_FILE.unlink()
    with contextlib.suppress(FileNotFoundError):
        (STATE/'access.json').unlink()


# --------------------------------------------------------------------------- http

def http(method, url, body=None, headers=None, form=None, timeout=20, raw=False):
    data = None
    headers = dict(headers or {})
    headers.setdefault('User-Agent', UA)
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    elif body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = response.read()
            if raw:
                return payload
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        text = error.read().decode('utf-8', 'replace')
        message = text[:200]
        code = None
        with contextlib.suppress(ValueError, AttributeError):
            detail = json.loads(text)
            inner = detail.get('error')
            code = inner if isinstance(inner, str) else None
            message = detail.get('error_description') or (inner.get('message') if isinstance(inner, dict) else inner) or message
        raise ApiError(error.code, message or f'HTTP {error.code}', code) from error
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as error:
        raise Offline(str(error)) from error


def access_token(force=False):
    cache = STATE/'access.json'
    token = read_json(cache, {})
    if not force and token.get('token') and token.get('expires', 0) > time.time() + 60:
        return token['token']
    refresh = secret_get('refresh')
    client_id, client_secret = secret_get('client_id'), secret_get('client_secret')
    if not refresh or not client_id:
        raise ApiError(401, 'Not connected to Google')
    try:
        reply = http('POST', TOKEN_URL, form={'client_id': client_id, 'client_secret': client_secret or '',
                                              'refresh_token': refresh, 'grant_type': 'refresh_token'})
    except ApiError as error:
        if error.status in (400, 401):
            raise ApiError(401, 'Google access was revoked or expired. Reconnect your account.') from error
        raise
    write_json(cache, {'token': reply['access_token'], 'expires': time.time() + int(reply.get('expires_in', 3600))})
    return reply['access_token']


def gapi(method, path, body=None, params=None):
    url = (path if path.startswith('http') else API + path)
    if params:
        url += ('&' if '?' in url else '?') + urllib.parse.urlencode(params, doseq=True)
    for attempt in range(2):
        headers = {'Authorization': 'Bearer ' + access_token(force=attempt > 0)}
        try:
            return http(method, url, body=body, headers=headers)
        except ApiError as error:
            if error.status == 401 and attempt == 0:
                continue
            raise


def quote(value):
    return urllib.parse.quote(value, safe='')


# --------------------------------------------------------------------------- time helpers

def local_zone_name():
    tz = os.environ.get('TZ')
    if tz and '/' in tz:
        return tz.lstrip(':')
    try:
        link = os.readlink('/etc/localtime')
        if 'zoneinfo/' in link:
            return link.split('zoneinfo/', 1)[1]
    except OSError:
        pass
    return 'UTC'


def parse_gtime(value):
    """Google start/end object → (epoch ms, all-day)."""
    if 'dateTime' in value:
        return int(datetime.fromisoformat(value['dateTime'].replace('Z', '+00:00')).timestamp() * 1000), False
    day = date.fromisoformat(value['date'])
    return local_ms(day), True


def gtime(ms, all_day, tz):
    moment = datetime.fromtimestamp(ms / 1000).astimezone()
    if all_day:
        return {'date': moment.date().isoformat()}
    return {'dateTime': moment.isoformat(timespec='seconds'), 'timeZone': tz}


MEET_RE = re.compile(r'https://(?:meet\.google\.com/[a-z\-]+|[\w.-]*zoom\.us/[jw]/\S+|teams\.microsoft\.com/l/meetup-join/\S+|[\w.-]*webex\.com/\S+)', re.I)


def find_meet(*texts):
    for text in texts:
        match = MEET_RE.search(text or '')
        if match:
            return match.group(0).rstrip('>)".,')
    return ''


def normalize(raw, calendar):
    start, all_day = parse_gtime(raw.get('start') or {})
    end, _ = parse_gtime(raw.get('end') or raw.get('start') or {})
    attendees = raw.get('attendees') or []
    me = next((a for a in attendees if a.get('self')), None)
    meet = raw.get('hangoutLink') or ''
    if not meet:
        for point in ((raw.get('conferenceData') or {}).get('entryPoints') or []):
            if point.get('entryPointType') == 'video':
                meet = point.get('uri', '')
                break
    meet = meet or find_meet(raw.get('location'), raw.get('description'))
    organizer = raw.get('organizer') or {}
    writable = calendar.get('writable', False) and (organizer.get('self', True) or raw.get('guestsCanModify', False) or calendar.get('accessRole') == 'owner')
    reminders = raw.get('reminders') or {'useDefault': True}
    return {
        'id': raw['id'], 'calendarId': calendar['id'], 'source': 'google', 'title': raw.get('summary') or '',
        'description': raw.get('description') or '', 'location': raw.get('location') or '', 'start': start, 'end': max(end, start),
        'allDay': all_day, 'colorId': raw.get('colorId') or '', 'recurringEventId': raw.get('recurringEventId') or '',
        'meet': meet, 'htmlLink': raw.get('htmlLink') or '', 'status': raw.get('status') or 'confirmed',
        'rsvp': me.get('responseStatus', '') if me else '', 'organizerSelf': bool(organizer.get('self', True)),
        'organizer': organizer.get('displayName') or organizer.get('email') or '',
        'attendees': [{'email': a.get('email', ''), 'name': a.get('displayName') or '', 'status': a.get('responseStatus', ''),
                       'self': bool(a.get('self')), 'organizer': bool(a.get('organizer'))} for a in attendees[:40]],
        'reminders': {'useDefault': bool(reminders.get('useDefault')),
                      'overrides': sorted({int(r.get('minutes', 0)) for r in reminders.get('overrides') or [] if r.get('method', 'popup') == 'popup'})},
        'transparency': raw.get('transparency') or 'opaque', 'editable': bool(writable), 'pending': False,
    }


# --------------------------------------------------------------------------- iCal

def ics_unfold(text):
    lines = []
    for line in text.replace('\r\n', '\n').replace('\r', '\n').split('\n'):
        if line[:1] in (' ', '\t') and lines:
            lines[-1] += line[1:]
        elif line:
            lines.append(line)
    return lines


def ics_prop(line):
    head, _, value = line.partition(':')
    parts = head.split(';')
    params = {}
    for part in parts[1:]:
        key, _, val = part.partition('=')
        params[key.upper()] = val.strip('"')
    return parts[0].upper(), params, value


def ics_text(value):
    return value.replace('\\n', '\n').replace('\\N', '\n').replace('\\,', ',').replace('\\;', ';').replace('\\\\', '\\')


def ics_time(value, params):
    """→ (aware or naive datetime, all-day)."""
    value = value.strip()
    if params.get('VALUE') == 'DATE' or (len(value) == 8 and value.isdigit()):
        return datetime.strptime(value[:8], '%Y%m%d'), True
    if value.endswith('Z'):
        return datetime.strptime(value[:15], '%Y%m%dT%H%M%S').replace(tzinfo=timezone.utc), False
    moment = datetime.strptime(value[:15], '%Y%m%dT%H%M%S')
    tzid = params.get('TZID')
    if tzid and ZoneInfo:
        try:
            return moment.replace(tzinfo=ZoneInfo(tzid)), False
        except Exception:
            pass
    return moment.astimezone(), False


def to_ms(moment, all_day):
    if all_day:
        return local_ms(moment.date() if isinstance(moment, datetime) else moment)
    if moment.tzinfo is None:
        moment = moment.astimezone()
    return int(moment.timestamp() * 1000)


WEEKDAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']


def expand_rrule(start, rule, lo, hi, exdates, limit=3000):
    """Occurrence starts of an RRULE (common subset: FREQ, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY, BYMONTH)."""
    parts = dict(p.split('=', 1) for p in rule.split(';') if '=' in p)
    freq = parts.get('FREQ', 'DAILY')
    interval = max(1, int(parts.get('INTERVAL', '1') or 1))
    count = int(parts['COUNT']) if 'COUNT' in parts else None
    until = None
    if 'UNTIL' in parts:
        until_value, all_day = ics_time(parts['UNTIL'], {})
        until = to_ms(until_value, all_day) + (86400000 - 1 if all_day else 0)
    byday = [d for d in parts.get('BYDAY', '').split(',') if d]
    bymonthday = [int(d) for d in parts.get('BYMONTHDAY', '').split(',') if d.lstrip('-').isdigit()]
    bymonth = [int(m) for m in parts.get('BYMONTH', '').split(',') if m.isdigit()]
    out, produced, step = [], 0, 0
    if count is None:
        # Jump close to the window so a long-running series (daily since years) never exhausts the iteration budget.
        first = datetime.fromtimestamp(lo / 1000).date()
        origin = start.date() if isinstance(start, datetime) else start
        gap = {'DAILY': (first - origin).days, 'WEEKLY': (first - origin).days // 7,
               'MONTHLY': (first.year - origin.year) * 12 + first.month - origin.month, 'YEARLY': first.year - origin.year}.get(freq, 0)
        step = max(0, gap // interval - 1)
    limit += step
    while step < limit:
        candidates = []
        if freq == 'DAILY':
            candidates = [start + timedelta(days=step * interval)]
        elif freq == 'WEEKLY':
            week = start - timedelta(days=start.weekday()) + timedelta(weeks=step * interval)
            days = [WEEKDAYS.index(d[-2:]) for d in byday if d[-2:] in WEEKDAYS] or [start.weekday()]
            candidates = [week + timedelta(days=d) for d in sorted(days)]
        elif freq == 'MONTHLY':
            base = add_months(date(start.year, start.month, 1), step * interval)
            last = calmod.monthrange(base.year, base.month)[1]
            if byday:
                for token in byday:
                    match = re.match(r'([+-]?\d*)(MO|TU|WE|TH|FR|SA|SU)', token)
                    if not match:
                        continue
                    nth, wd = int(match.group(1) or 0), WEEKDAYS.index(match.group(2))
                    days = [d for d in range(1, last + 1) if date(base.year, base.month, d).weekday() == wd]
                    picks = days if nth == 0 else ([days[nth - 1]] if 0 < nth <= len(days) else ([days[nth]] if -len(days) <= nth < 0 else []))
                    candidates += [start.replace(year=base.year, month=base.month, day=d) for d in picks]
            else:
                for d in (bymonthday or [start.day]):
                    d = d if d > 0 else last + d + 1
                    if 1 <= d <= last:
                        candidates.append(start.replace(year=base.year, month=base.month, day=d))
        elif freq == 'YEARLY':
            year = start.year + step * interval
            for month in (bymonth or [start.month]):
                with contextlib.suppress(ValueError):
                    candidates.append(start.replace(year=year, month=month))
        else:
            break
        for moment in sorted(candidates):
            if moment < start:
                continue
            if bymonth and freq != 'YEARLY' and moment.month not in bymonth:
                continue
            ms = to_ms(moment, False) if moment.tzinfo else int(moment.timestamp() * 1000)
            if until is not None and ms > until:
                return out
            produced += 1
            if count is not None and produced > count:
                return out
            if ms >= hi:
                return out
            if ms not in exdates:
                out.append(moment)
        step += 1
    return out


def parse_ics(text, source, lo, hi):
    events, overrides, name, color = [], {}, '', ''
    current = None
    for line in ics_unfold(text):
        key, params, value = ics_prop(line)
        if key == 'BEGIN' and value.upper() == 'VEVENT':
            current = {'props': {}, 'exdates': set()}
        elif key == 'END' and value.upper() == 'VEVENT' and current is not None:
            events.append(current)
            current = None
        elif current is not None:
            if key == 'EXDATE':
                for item in value.split(','):
                    with contextlib.suppress(ValueError):
                        moment, all_day = ics_time(item, params)
                        current['exdates'].add(to_ms(moment, all_day) if all_day else to_ms(moment, False))
            else:
                current['props'].setdefault(key, (params, value))
        elif key == 'X-WR-CALNAME':
            name = ics_text(value)
        elif key in ('X-APPLE-CALENDAR-COLOR', 'COLOR') and re.match(r'#[0-9a-fA-F]{6}', value):
            color = value[:7]
    out = {}
    masters = []
    for item in events:
        props = item['props']
        if 'DTSTART' not in props or (props.get('STATUS', ({}, ''))[1].upper() == 'CANCELLED' and 'RECURRENCE-ID' not in props):
            continue
        start, all_day = ics_time(props['DTSTART'][1], props['DTSTART'][0])
        if 'DTEND' in props:
            end, _ = ics_time(props['DTEND'][1], props['DTEND'][0])
        elif 'DURATION' in props:
            end = start + parse_duration(props['DURATION'][1])
        else:
            end = start + (timedelta(days=1) if all_day else timedelta(0))
        uid = props.get('UID', ({}, ''))[1] or hashlib.sha1((props.get('SUMMARY', ({}, ''))[1] + props['DTSTART'][1]).encode()).hexdigest()
        base = {
            'calendarId': source['id'], 'source': 'ics', 'title': ics_text(props.get('SUMMARY', ({}, ''))[1]),
            'description': ics_text(props.get('DESCRIPTION', ({}, ''))[1]), 'location': ics_text(props.get('LOCATION', ({}, ''))[1]),
            'allDay': all_day, 'colorId': '', 'htmlLink': props.get('URL', ({}, ''))[1], 'status': 'confirmed', 'rsvp': '',
            'organizerSelf': False, 'organizer': '', 'attendees': [], 'reminders': {'useDefault': True, 'overrides': []},
            'transparency': 'opaque', 'editable': False, 'pending': False,
        }
        base['meet'] = find_meet(base['location'], base['description'], base['htmlLink'])
        duration = to_ms(end, all_day) - to_ms(start, all_day)
        if 'RECURRENCE-ID' in props:
            rid, rid_all = ics_time(props['RECURRENCE-ID'][1], props['RECURRENCE-ID'][0])
            overrides[(uid, to_ms(rid, rid_all))] = (start, all_day, duration, base)
            continue
        masters.append((uid, start, all_day, duration, base, props.get('RRULE', ({}, ''))[1], item['exdates']))
    for uid, start, all_day, duration, base, rule, exdates in masters:
        starts = expand_rrule(start, rule, lo, hi, exdates) if rule else [start]
        for moment in starts:
            ms = to_ms(moment, all_day)
            key = (uid, ms)
            ev_start, ev_all, ev_dur, ev_base = overrides.pop(key, (moment, all_day, duration, base))
            s = to_ms(ev_start, ev_all)
            if s + ev_dur < lo or s >= hi:
                continue
            ident = 'ics:' + hashlib.sha1(f"{source['id']}|{uid}|{ms}".encode()).hexdigest()[:20]
            out[ident] = dict(ev_base, id=ident, start=s, end=s + max(0, ev_dur), recurringEventId=('ics:' + uid) if rule else '')
    for (uid, ms), (ev_start, ev_all, ev_dur, ev_base) in overrides.items():
        s = to_ms(ev_start, ev_all)
        if lo <= s < hi:
            ident = 'ics:' + hashlib.sha1(f"{source['id']}|{uid}|{ms}".encode()).hexdigest()[:20]
            out[ident] = dict(ev_base, id=ident, start=s, end=s + ev_dur, recurringEventId='ics:' + uid)
    return out, name, color


def parse_duration(value):
    match = re.match(r'([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?', value.strip())
    if not match:
        return timedelta(0)
    sign = -1 if match.group(1) == '-' else 1
    w, d, h, m, s = (int(g or 0) for g in match.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=m, seconds=s)


# --------------------------------------------------------------------------- sync

def fetch_google(store, ranges):
    """Calendar list, colours, events (expanded) and recurring masters for every visible-or-not Google calendar."""
    listing = gapi('GET', '/users/me/calendarList', params={'maxResults': 250})
    calendars = []
    for item in listing.get('items') or []:
        if item.get('deleted'):
            continue
        role = item.get('accessRole', 'reader')
        calendars.append({
            'id': item['id'], 'name': item.get('summaryOverride') or item.get('summary') or item['id'], 'source': 'google',
            'color': item.get('backgroundColor') or '#4285f4', 'primary': bool(item.get('primary')),
            'writable': role in ('owner', 'writer'), 'accessRole': role,
            'defaultReminders': sorted({int(r.get('minutes', 0)) for r in item.get('defaultReminders') or [] if r.get('method') == 'popup'}),
        })
    calendars.sort(key=lambda c: (not c['primary'], not c['writable'], c['name'].lower()))
    colors = {}
    with contextlib.suppress(ApiError):
        palette = gapi('GET', '/colors')
        colors = {key: value.get('background') for key, value in (palette.get('event') or {}).items()}
    events, masters = {}, {}
    for cal in calendars:
        for lo, hi in ranges:
            base = {'timeMin': iso(lo), 'timeMax': iso(hi), 'maxResults': 2500}
            token = None
            while True:
                params = dict(base, singleEvents='true', orderBy='startTime', **({'pageToken': token} if token else {}))
                try:
                    page = gapi('GET', f"/calendars/{quote(cal['id'])}/events", params=params)
                except ApiError as error:
                    if error.status in (403, 404):
                        break
                    raise
                for raw in page.get('items') or []:
                    if raw.get('status') == 'cancelled' or 'start' not in raw:
                        continue
                    event = normalize(raw, cal)
                    events[event['id']] = event
                token = page.get('nextPageToken')
                if not token:
                    break
            token = None
            while True:
                params = dict(base, singleEvents='false', **({'pageToken': token} if token else {}))
                try:
                    page = gapi('GET', f"/calendars/{quote(cal['id'])}/events", params=params)
                except ApiError:
                    break
                for raw in page.get('items') or []:
                    if raw.get('recurrence'):
                        masters[cal['id'] + '/' + raw['id']] = {'recurrence': raw['recurrence'], 'start': raw.get('start')}
                token = page.get('nextPageToken')
                if not token:
                    break
    return calendars, colors, events, masters


def iso(ms):
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat().replace('+00:00', 'Z')


def fetch_ics(source, ranges):
    url = re.sub(r'^webcal://', 'https://', source['url'].strip(), flags=re.I)
    text = http('GET', url, raw=True, timeout=30).decode('utf-8', 'replace')
    if 'BEGIN:VCALENDAR' not in text:
        raise ApiError(400, 'This address is not an iCal (.ics) calendar')
    events = {}
    name = color = ''
    for lo, hi in ranges:
        found, name, color = parse_ics(text, source, lo, hi)
        events.update(found)
    return events, name, color


def ranges_of(store):
    lo, hi = window()
    ranges = [(lo, hi)]
    for a, b in store['ranges'][-6:]:
        if a < lo or b > hi:
            ranges.append((a, b))
    return ranges


def sync(force=False, extra=None):
    started = now_ms()

    def begin(store):
        if extra:
            store['ranges'] = (store['ranges'] + [list(extra)])[-6:]
        if store['google'] or store['ics']:
            store['syncing'] = True
        return copy.deepcopy(store)
    snapshot = mutate(begin)
    if not snapshot['google'] and not snapshot['ics']:
        return {'ok': True, 'status': snapshot['status']}
    flush_queue()
    ranges = ranges_of(snapshot)
    result = {'google': None, 'ics': {}, 'error': '', 'offline': False, 'revoked': False}
    if snapshot['google']:
        try:
            result['google'] = fetch_google(snapshot, ranges)
        except Offline as error:
            result['offline'] = True
            result['error'] = str(error)
        except ApiError as error:
            result['error'] = str(error)
            result['revoked'] = error.status == 401
    for source in snapshot['ics']:
        try:
            result['ics'][source['id']] = fetch_ics(source, ranges)
        except Offline as error:
            result['offline'] = True
        except (ApiError, ValueError) as error:
            result['error'] = result['error'] or f"{source.get('name') or 'iCal'}: {error}"

    def merge(store):
        store['syncing'] = False
        pending_ids = {op.get('eventId') for op in store['queue']} | {op.get('tempId') for op in store['queue']}
        recent = {k: v for k, v in store['events'].items() if v.get('pending') or v.get('_local', 0) > started or k in pending_ids}
        fresh = {}
        if result['google'] is not None:
            calendars, colors, events, masters = result['google']
            store['calendars'] = calendars + [c for c in store['calendars'] if c.get('source') == 'ics']
            store['colors'] = colors or store['colors']
            store['masters'] = masters
            fresh.update(events)
        else:
            fresh.update({k: v for k, v in store['events'].items() if v.get('source') == 'google'})
        ics_calendars = []
        for source in store['ics']:
            fetched = result['ics'].get(source['id'])
            if fetched:
                events, name, color = fetched
                source['name'] = source.get('name') or name or 'iCal'
                source['color'] = source.get('color') or color or '#89b4fa'
                fresh.update(events)
            else:
                fresh.update({k: v for k, v in store['events'].items() if v.get('calendarId') == source['id']})
            ics_calendars.append({'id': source['id'], 'name': source.get('name') or 'iCal', 'source': 'ics', 'color': source.get('color') or '#89b4fa',
                                  'primary': False, 'writable': False, 'accessRole': 'reader', 'defaultReminders': []})
        store['calendars'] = [c for c in store['calendars'] if c.get('source') != 'ics'] + ics_calendars
        tomb = {k: t for k, t in store['tombstones'].items() if t > started - 600000}
        store['tombstones'] = tomb
        for key, event in recent.items():
            fresh[key] = event
        for key in tomb:
            fresh.pop(key, None)
        store['events'] = fresh
        if result['revoked']:
            store['status'], store['error'] = 'error', result['error']
        elif result['offline']:
            store['status'], store['error'] = 'offline', ''
        else:
            store['status'] = 'ok'
            store['error'] = result['error']
            store['lastSync'] = int(time.time())
        return {'ok': not result['error'], 'status': store['status'], 'error': store['error'], 'events': len(fresh)}
    return mutate(merge)


# --------------------------------------------------------------------------- OAuth

SUCCESS_PAGE = '''<!doctype html><meta charset=utf-8><title>Serpantinum</title>
<style>body{{margin:0;height:100vh;display:grid;place-items:center;background:#11111b;color:#cdd6f4;font:600 18px system-ui}}
div{{text-align:center;animation:in .7s cubic-bezier(.2,1.4,.4,1)}}b{{display:block;font-size:64px;margin-bottom:12px}}
@keyframes in{{from{{opacity:0;transform:scale(.8) translateY(20px)}}}}</style>
<div><b>{icon}</b>{text}<br><small style="opacity:.6">{sub}</small></div>'''


def connection_error(reason, message):
    mutate(lambda s: s.update(status='error', error=message, authUrl=''))
    return {'ok': False, 'reason': reason, 'error': message}


def connect(client_id, client_secret, open_browser=True):
    client_id, client_secret = client_id.strip(), client_secret.strip()
    if not client_id.endswith('.apps.googleusercontent.com'):
        return connection_error('client_id', 'The client ID must end with .apps.googleusercontent.com.')
    if not client_secret:
        return connection_error('client_secret', 'Enter the OAuth client secret.')
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    state_token = secrets.token_urlsafe(16)
    result = {}

    class Handler(httpserver.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if 'code' not in query and 'error' not in query:
                self.send_response(404)
                self.end_headers()
                return
            ok = query.get('state', [''])[0] == state_token and 'code' in query
            result['code'] = query.get('code', [''])[0] if ok else ''
            result['error'] = '' if ok else (query.get('error', ['state mismatch'])[0])
            page = SUCCESS_PAGE.format(icon='✓' if ok else '✕', text='Authorization received' if ok else 'Authorization failed',
                                       sub='Go back to Serpantinum to see the connection status.' if ok else html.escape(result['error']))
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(page.encode())

    try:
        server = httpserver.HTTPServer(('127.0.0.1', 0), Handler)
    except OSError:
        return connection_error('callback_unavailable', 'Could not start the local server that receives Google’s response.')
    server.timeout = 1
    redirect = f'http://127.0.0.1:{server.server_port}'
    url = AUTH_URL + '?' + urllib.parse.urlencode({
        'client_id': client_id, 'redirect_uri': redirect, 'response_type': 'code', 'scope': SCOPES,
        'access_type': 'offline', 'prompt': 'consent', 'code_challenge': challenge, 'code_challenge_method': 'S256', 'state': state_token,
    })
    def cancelled(*_):
        mutate(lambda s: s.update(status='ok' if s['google'] or s['ics'] else 'disconnected', authUrl='', error=''))
        sys.exit(0)
    signal.signal(signal.SIGTERM, cancelled)
    mutate(lambda s: s.update(status='connecting', error='', authUrl=url))
    if open_browser:
        with contextlib.suppress(OSError):
            subprocess.Popen(['xdg-open', url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + 300
    while 'code' not in result and time.time() < deadline:
        server.handle_request()
    server.server_close()
    if not result.get('code'):
        failure = result.get('error')
        if not failure:
            return connection_error('timeout', 'Google did not respond within five minutes. Try again and finish signing in in the browser.')
        if failure == 'access_denied':
            return connection_error('access_denied', 'Google denied access. Authorize Calendar in the browser and try again.')
        if failure == 'state mismatch':
            return connection_error('callback_mismatch', 'This response does not match the current sign-in. Start again and use the latest browser tab.')
        return connection_error('authorization_failed', f'Google refused authorization ({failure}).')
    try:
        reply = http('POST', TOKEN_URL, form={'client_id': client_id, 'client_secret': client_secret, 'code': result['code'],
                                              'code_verifier': verifier, 'grant_type': 'authorization_code', 'redirect_uri': redirect})
    except Offline:
        return connection_error('network', 'Could not reach Google to finish signing in. Check your internet connection and try again.')
    except ApiError as error:
        if error.code == 'invalid_client':
            return connection_error('invalid_client', 'Google rejected the OAuth client. Check that the ID and secret are from the same Desktop app client.')
        if error.code == 'invalid_grant':
            return connection_error('invalid_grant', 'Google rejected the authorization code. Start a new sign-in and finish it in the latest browser tab.')
        return connection_error('token_exchange', f'Google rejected the token exchange (HTTP {error.status}): {error}')
    if not reply.get('refresh_token'):
        return connection_error('no_refresh_token', 'Google did not grant ongoing access. Remove this app’s access in your Google account and try again.')
    secret_set('client_id', client_id)
    secret_set('client_secret', client_secret)
    secret_set('refresh', reply['refresh_token'])
    write_json(STATE/'access.json', {'token': reply['access_token'], 'expires': time.time() + int(reply.get('expires_in', 3600))})
    email = ''
    with contextlib.suppress(ApiError, Offline):
        email = http('GET', USERINFO_URL, headers={'Authorization': 'Bearer ' + reply['access_token']}).get('email', '')
    mutate(lambda s: s.update(google={'email': email, 'clientId': client_id}, status='syncing', error='', authUrl=''))
    synced = sync(force=True)
    if synced['status'] == 'offline' and not synced['ok']:
        return {**synced, 'reason': 'sync_offline', 'error': 'Google is connected. Check your internet connection to finish syncing your calendars.'}
    return synced


def disconnect():
    refresh = secret_get('refresh')
    if refresh:
        with contextlib.suppress(ApiError, Offline):
            http('POST', REVOKE_URL, form={'token': refresh})
    secret_clear()

    def clear(store):
        store['google'] = None
        store['calendars'] = [c for c in store['calendars'] if c.get('source') == 'ics']
        store['events'] = {k: v for k, v in store['events'].items() if v.get('source') == 'ics'}
        store['masters'], store['queue'], store['error'], store['authUrl'] = {}, [], '', ''
        store['status'] = 'ok' if store['ics'] else 'disconnected'
        return {'ok': True}
    return mutate(clear)


# --------------------------------------------------------------------------- mutations

def event_body(payload, tz):
    body = {}
    if 'title' in payload:
        body['summary'] = payload['title']
    for key in ('description', 'location'):
        if key in payload:
            body[key] = payload[key]
    if 'start' in payload:
        all_day = bool(payload.get('allDay'))
        end = payload.get('end', payload['start'])
        if all_day and end <= payload['start']:
            end = payload['start'] + 86400000
        body['start'] = gtime(payload['start'], all_day, tz)
        body['end'] = gtime(end, all_day, tz)
    if 'colorId' in payload:
        body['colorId'] = payload['colorId'] or None
    if 'recurrence' in payload:
        body['recurrence'] = payload['recurrence'] or []
    if 'reminders' in payload:
        reminders = payload['reminders'] or {}
        body['reminders'] = {'useDefault': bool(reminders.get('useDefault', True))}
        if not body['reminders']['useDefault']:
            body['reminders']['overrides'] = [{'method': 'popup', 'minutes': int(m)} for m in (reminders.get('overrides') or [])[:5]]
    if 'transparency' in payload:
        body['transparency'] = payload['transparency']
    if payload.get('addMeet'):
        body['conferenceData'] = {'createRequest': {'requestId': secrets.token_hex(8), 'conferenceSolutionKey': {'type': 'hangoutsMeet'}}}
    return body


def calendar_of(store, calendar_id):
    return next((c for c in store['calendars'] if c['id'] == calendar_id), {'id': calendar_id, 'writable': True, 'source': 'google'})


def local_event(store, payload, ident):
    previous = store['events'].get(ident) or {}
    event = dict(previous) if previous else {
        'id': ident, 'calendarId': payload.get('calendarId'), 'source': 'google', 'title': '', 'description': '', 'location': '',
        'allDay': False, 'colorId': '', 'recurringEventId': '', 'meet': '', 'htmlLink': '', 'status': 'confirmed', 'rsvp': '',
        'organizerSelf': True, 'organizer': '', 'attendees': [], 'reminders': {'useDefault': True, 'overrides': []},
        'transparency': 'opaque', 'editable': True, 'start': payload.get('start', now_ms()), 'end': payload.get('end', now_ms()),
    }
    for key in ('title', 'description', 'location', 'allDay', 'colorId', 'start', 'end', 'reminders', 'transparency', 'calendarId'):
        if key in payload:
            event[key] = payload[key]
    if 'recurrence' in payload:
        event['recurrence'] = payload['recurrence']
    event['pending'] = True
    event['_local'] = now_ms()
    return event


def run_op(op, store_snapshot):
    """Apply one queued operation against Google. Returns the server event (or None)."""
    kind, payload = op['type'], op['payload']
    tz = local_zone_name()
    cal = payload['calendarId']
    if kind == 'create':
        body = event_body(payload, tz)
        return gapi('POST', f'/calendars/{quote(cal)}/events', body=body, params={'conferenceDataVersion': 1})
    if kind == 'update':
        target = payload['id']
        body = event_body(payload, tz)
        if payload.get('scope') == 'all' and payload.get('recurringEventId'):
            target = payload['recurringEventId']
            master = gapi('GET', f'/calendars/{quote(cal)}/events/{quote(target)}')
            if 'start' in payload and 'originalStart' in payload:
                delta = payload['start'] - payload['originalStart']
                duration = payload['end'] - payload['start']
                m_start, all_day = parse_gtime(master['start'])
                new_start = m_start + delta
                body['start'] = gtime(new_start, bool(payload.get('allDay')), tz)
                body['end'] = gtime(new_start + duration, bool(payload.get('allDay')), tz)
        elif payload.get('recurringEventId'):
            body.pop('recurrence', None)
        result = gapi('PATCH', f'/calendars/{quote(cal)}/events/{quote(target)}', body=body, params={'conferenceDataVersion': 1})
        destination = payload.get('moveTo')
        if destination and destination != cal:
            result = gapi('POST', f'/calendars/{quote(cal)}/events/{quote(target)}/move', params={'destination': destination})
        return result
    if kind == 'delete':
        target = payload['recurringEventId'] if payload.get('scope') == 'all' and payload.get('recurringEventId') else payload['id']
        try:
            gapi('DELETE', f'/calendars/{quote(cal)}/events/{quote(target)}')
        except ApiError as error:
            if error.status not in (404, 410):
                raise
        return None
    if kind == 'rsvp':
        raw = gapi('GET', f"/calendars/{quote(cal)}/events/{quote(payload['id'])}")
        attendees = raw.get('attendees') or []
        for attendee in attendees:
            if attendee.get('self'):
                attendee['responseStatus'] = payload['response']
        return gapi('PATCH', f"/calendars/{quote(cal)}/events/{quote(payload['id'])}", body={'attendees': attendees}, params={'sendUpdates': 'all'})
    raise ValueError('unknown operation ' + kind)


def apply_mutation(kind, payload):
    if kind in ('create', 'update', 'delete', 'rsvp') and not payload.get('calendarId'):
        return {'ok': False, 'error': 'calendarId missing'}

    def optimistic(store):
        if not store['google']:
            return None
        cal = calendar_of(store, payload['calendarId'])
        if cal.get('source') == 'ics' or not cal.get('writable', True):
            return 'readonly'
        op = {'type': kind, 'payload': payload, 'ts': now_ms(), 'eventId': payload.get('id', '')}
        if kind == 'create':
            temp = 'local-' + secrets.token_hex(6)
            op['tempId'] = temp
            store['events'][temp] = local_event(store, payload, temp)
        elif kind == 'update':
            ident = payload['id']
            if ident in store['events']:
                if payload.get('scope') == 'all' and payload.get('recurringEventId'):
                    delta = payload.get('start', 0) - payload.get('originalStart', payload.get('start', 0))
                    for event in store['events'].values():
                        if event.get('recurringEventId') == payload['recurringEventId']:
                            for key in ('title', 'description', 'location', 'colorId', 'reminders'):
                                if key in payload:
                                    event[key] = payload[key]
                            if delta and 'start' in payload:
                                length = payload['end'] - payload['start']
                                event['start'] += delta
                                event['end'] = event['start'] + length
                            event['pending'], event['_local'] = True, now_ms()
                else:
                    store['events'][ident] = local_event(store, payload, ident)
                if payload.get('moveTo'):
                    store['events'][ident]['calendarId'] = payload['moveTo']
        elif kind == 'delete':
            ident = payload['id']
            if payload.get('scope') == 'all' and payload.get('recurringEventId'):
                for key in [k for k, e in store['events'].items() if e.get('recurringEventId') == payload['recurringEventId']]:
                    store['events'].pop(key, None)
                    store['tombstones'][key] = now_ms()
            else:
                store['events'].pop(ident, None)
                store['tombstones'][ident] = now_ms()
        elif kind == 'rsvp':
            event = store['events'].get(payload['id'])
            if event:
                event['rsvp'] = payload['response']
                event['pending'], event['_local'] = True, now_ms()
        store['queue'].append(op)
        return op
    op = mutate(optimistic)
    if op is None:
        return {'ok': False, 'error': 'Connect a Google account to edit events'}
    if op == 'readonly':
        return {'ok': False, 'error': 'This calendar is read only'}
    flushed = flush_queue()
    if flushed.get('offline'):
        return {'ok': True, 'queued': True}
    if flushed.get('error'):
        return {'ok': False, 'error': flushed['error']}
    sync()
    return {'ok': True, 'id': flushed.get('ids', {}).get(op.get('tempId'), payload.get('id'))}


def flush_queue():
    """Replay queued edits in order. Stops at the first network failure; drops edits Google rejects (and reports them)."""
    report = {'ids': {}, 'error': '', 'offline': False}
    flush_lock = open(STATE/'.flush', 'a') if STATE.exists() else None
    if flush_lock:
        fcntl.flock(flush_lock, fcntl.LOCK_EX)
    try:
        while True:
            with locked():
                store = load_store()
                if not store['queue'] or not store['google']:
                    return report
                op = copy.deepcopy(store['queue'][0])
            for temp, real in report['ids'].items():
                if op['payload'].get('id') == temp:
                    op['payload']['id'] = real
            if str(op['payload'].get('id', '')).startswith('local-'):
                result, failure = None, 'The event was never created'
            else:
                try:
                    result, failure = run_op(op, store), ''
                except Offline:
                    report['offline'] = True
                    mutate(lambda s: s.update(status='offline'))
                    return report
                except ApiError as error:
                    result, failure = None, str(error)
                    if error.status == 401:
                        mutate(lambda s: s.update(status='error', error=str(error)))
                        report['error'] = str(error)
                        return report

            def done(store, op=op, result=result, failure=failure):
                if store['queue'] and store['queue'][0].get('ts') == op['ts']:
                    store['queue'].pop(0)
                temp = op.get('tempId')
                if temp:
                    store['events'].pop(temp, None)
                if result and result.get('id') and 'start' in result:
                    cal = calendar_of(store, op['payload'].get('moveTo') or op['payload']['calendarId'])
                    event = normalize(result, cal)
                    if not result.get('recurrence'):
                        store['events'][event['id']] = event
                    if temp:
                        report['ids'][temp] = event['id']
                if failure:
                    report['error'] = failure
                    store['error'] = failure
                    ident = op['payload'].get('id')
                    if ident in store['events']:
                        store['events'][ident]['pending'] = False
                    # A refused delete must reappear at the next sync: forget its tombstones.
                    if op['type'] == 'delete':
                        store['tombstones'] = {k: v for k, v in store['tombstones'].items() if v < op['ts']}
            mutate(done)
    finally:
        if flush_lock:
            fcntl.flock(flush_lock, fcntl.LOCK_UN)
            flush_lock.close()


def set_prefs(payload):
    def apply(store):
        for key in ('hidden', 'reminders', 'defaultCalendar', 'weekStart'):
            if key in payload:
                store['prefs'][key] = payload[key]
        return {'ok': True}
    return mutate(apply)


def ics_add(payload):
    url = (payload.get('url') or '').strip()
    if not re.match(r'^(https?|webcal)://', url, re.I):
        return {'ok': False, 'error': 'Enter an http(s):// or webcal:// address'}
    source = {'id': 'ics-' + hashlib.sha1(url.encode()).hexdigest()[:10], 'url': url, 'name': (payload.get('name') or '').strip(), 'color': payload.get('color') or ''}
    try:
        events, name, color = fetch_ics(source, [window()])
    except (Offline, ApiError, ValueError) as error:
        return {'ok': False, 'error': f'Could not read this calendar: {error}'}
    source['name'] = source['name'] or name or 'iCal'
    source['color'] = source['color'] or color or ['#89b4fa', '#a6e3a1', '#f9e2af', '#f5c2e7', '#94e2d5', '#fab387'][len(url) % 6]

    def add(store):
        store['ics'] = [s for s in store['ics'] if s['id'] != source['id']] + [source]
        store['events'].update(events)
        store['calendars'] = [c for c in store['calendars'] if c['id'] != source['id']] + [{
            'id': source['id'], 'name': source['name'], 'source': 'ics', 'color': source['color'], 'primary': False,
            'writable': False, 'accessRole': 'reader', 'defaultReminders': []}]
        if store['status'] == 'disconnected':
            store['status'] = 'ok'
        return {'ok': True, 'id': source['id'], 'events': len(events)}
    return mutate(add)


def ics_remove(ident):
    def remove(store):
        store['ics'] = [s for s in store['ics'] if s['id'] != ident]
        store['calendars'] = [c for c in store['calendars'] if c['id'] != ident]
        store['events'] = {k: v for k, v in store['events'].items() if v.get('calendarId') != ident}
        if not store['ics'] and not store['google']:
            store['status'] = 'disconnected'
        return {'ok': True}
    return mutate(remove)


# --------------------------------------------------------------------------- reminders / daemon

def due_reminders(store, now):
    if not store['prefs'].get('reminders', True):
        return []
    hidden = set(store['prefs'].get('hidden') or [])
    calendars = {c['id']: c for c in store['calendars']}
    due = []
    for event in store['events'].values():
        if event['calendarId'] in hidden or event.get('rsvp') == 'declined' or event['start'] < now - 600000 or event['start'] > now + 2 * 86400000:
            continue
        reminders = event.get('reminders') or {}
        minutes = (calendars.get(event['calendarId'], {}).get('defaultReminders') or []) if reminders.get('useDefault', True) else reminders.get('overrides') or []
        if event.get('source') == 'ics' and not event.get('allDay'):
            minutes = [10]
        for m in minutes:
            fire = event['start'] - m * 60000
            key = f"{event['id']}|{event['start']}|{m}"
            if fire <= now < fire + 600000 and key not in store['sent']:
                due.append((key, event, m))
    return due


def notify(event, minutes):
    start = datetime.fromtimestamp(event['start'] / 1000)
    when = 'now' if minutes == 0 else (f'in {minutes} min' if minutes < 60 else (f'in {minutes // 60} h' if minutes < 1440 else 'tomorrow'))
    body = ('All day' if event.get('allDay') else start.strftime('%H:%M')) + f' · {when}'
    if event.get('location'):
        body += '\n' + event['location']
    command = ['notify-send', '-a', 'Calendar', '-i', 'x-office-calendar', '-u', 'normal', event.get('title') or '(No title)', body]
    if event.get('meet'):
        command[1:1] = ['--action=join=Join', '--action=open=Open']
    else:
        command[1:1] = ['--action=open=Open']

    def wait():
        try:
            out = subprocess.run(command, capture_output=True, text=True, timeout=3600).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return
        if out == 'join' and event.get('meet'):
            subprocess.Popen(['xdg-open', event['meet']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif out == 'open':
            qs = Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share')/'serpantinum/src/quickshell/Shell.qml'
            subprocess.Popen(['quickshell', '-p', str(qs), 'ipc', 'call', 'addonCalendar', 'openEvent', event['id']],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    threading.Thread(target=wait, daemon=True).start()


def check_reminders():
    now = now_ms()

    def pick(store):
        due = due_reminders(store, now)
        for key, _, _ in due:
            store['sent'][key] = now
        store['sent'] = {k: v for k, v in store['sent'].items() if v > now - 3 * 86400000}
        return due
    for _, event, minutes in mutate(pick) if (STORE_FILE.exists()) else []:
        notify(event, minutes)


def daemon():
    STATE.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    mutate(lambda s: s.update(syncing=False))   # publish state.json even before any account exists
    last = 0
    while True:
        store = load_store()
        connected = bool(store['google'] or store['ics'])
        if connected and (time.time() - max(last, store['lastSync']) >= SYNC_INTERVAL or (store['queue'] and time.time() - last >= 60)):
            last = time.time()
            try:
                sync()
            except Exception as error:  # never let the service die on one bad sync
                mutate(lambda s, e=error: s.update(syncing=False, error=f'Sync failed: {e}'))
        if connected:
            with contextlib.suppress(Exception):
                check_reminders()
        time.sleep(20)


# --------------------------------------------------------------------------- CLI

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('status')
    sync_p = sub.add_parser('sync')
    sync_p.add_argument('--force', action='store_true')
    ensure_p = sub.add_parser('ensure')
    ensure_p.add_argument('lo', type=int)
    ensure_p.add_argument('hi', type=int)
    sub.add_parser('daemon')
    connect_p = sub.add_parser('connect')
    connect_p.add_argument('--client-id', required=True)
    connect_p.add_argument('--client-secret', required=True)
    connect_p.add_argument('--no-browser', action='store_true')
    sub.add_parser('disconnect')
    for name in ('create', 'update', 'delete', 'rsvp', 'prefs', 'ics-add'):
        sub.add_parser(name).add_argument('payload')
    sub.add_parser('ics-remove').add_argument('id')
    args = parser.parse_args(argv)
    STATE.mkdir(parents=True, exist_ok=True)
    os.chmod(STATE, 0o700)
    if args.command == 'status':
        if not STATE_FILE.exists():
            mutate(lambda s: None)
        out = read_json(STATE_FILE, {})
        out = {k: v for k, v in out.items() if k != 'events'} | {'events': len(out.get('events') or [])}
    elif args.command == 'sync':
        out = sync(force=args.force)
    elif args.command == 'ensure':
        lo, hi = window()
        out = {'ok': True} if lo <= args.lo and args.hi <= hi else sync(extra=(args.lo, args.hi))
    elif args.command == 'daemon':
        daemon()
        return 0
    elif args.command == 'connect':
        out = connect(args.client_id, args.client_secret, not args.no_browser)
    elif args.command == 'disconnect':
        out = disconnect()
    elif args.command == 'ics-remove':
        out = ics_remove(args.id)
    else:
        payload = json.loads(args.payload)
        if args.command == 'prefs':
            out = set_prefs(payload)
        elif args.command == 'ics-add':
            out = ics_add(payload)
        else:
            out = apply_mutation(args.command, payload)
    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get('ok', True) else 1


if __name__ == '__main__':
    sys.exit(main())
