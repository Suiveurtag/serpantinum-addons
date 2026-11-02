#!/usr/bin/env python3
"""Claude Code spinner verbs for Clawd's thoughts.
Usage: verbs.py  ->  {"ok": true, "data": {"verbs": [...], "source": "binary"|"fallback", "mode": "append"|"replace"|"default"}}
Built-in list read from the installed Claude Code (Bun binary or npm cli.js), then settings.json "spinnerVerbs" applied.
Cached in $XDG_CACHE_HOME/serpantinum-addons-v2/clawd-verbs.json, keyed on the binary and settings stats."""
import json
import mmap
import os
import re
import shutil
import sys
from pathlib import Path

MARKER = b'["Accomplishing",'
FALLBACK = ['Thinking', 'Working', 'Pondering', 'Brewing', 'Computing', 'Crafting', 'Cooking', 'Mulling', 'Noodling', 'Tinkering', 'Wrangling', 'Clauding']
ESCAPE = re.compile(r'\\(x[0-9A-Fa-f]{2}|u\{[0-9A-Fa-f]+\}|u[0-9A-Fa-f]{4}|\r\n|.)', re.S)
SIMPLE = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v', '0': '\0', '\n': '', '\r\n': '', '\r': ''}


def unescape(body):
    def one(match):
        code = match.group(1)
        if code[0] in 'xu' and len(code) > 1: return chr(int(code.strip('xu{}'), 16))
        return SIMPLE.get(code, code)
    text = ESCAPE.sub(one, body)
    return text.encode('utf-16', 'surrogatepass').decode('utf-16')  # rejoin \uD83D\uDE00 pairs


def parse(blob, start):
    # The JS array literal at blob[start] ('[' + quoted strings + ']'), or None.
    verbs, i, end = [], start + 1, min(len(blob), start + 65536)
    while i < end:
        while blob[i:i + 1] in (b' ', b'\n', b'\r', b'\t'): i += 1
        quote = blob[i:i + 1]
        if quote == b']': return verbs
        if quote not in (b'"', b"'"): return None
        j = i + 1
        while j < end and blob[j:j + 1] != quote:
            j += 2 if blob[j:j + 1] == b'\\' else 1
        if j >= end: return None
        verbs.append(unescape(blob[i + 1:j].decode('utf-8')))
        i = j + 1
        while blob[i:i + 1] in (b' ', b'\n', b'\r', b'\t'): i += 1
        if blob[i:i + 1] == b',': i += 1
    return None


def valid(verbs):
    return isinstance(verbs, list) and 50 <= len(verbs) <= 1000 and all(isinstance(v, str) and v and len(v) <= 40 for v in verbs)


def builtin(binary):
    if not binary: return None
    try:
        with open(binary, 'rb') as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as blob:
            at = blob.find(MARKER)
            for _ in range(4):  # a bundle may hold stale copies; take the first that parses
                if at < 0: return None
                try: verbs = parse(blob, at)
                except (ValueError, UnicodeError): verbs = None
                if valid(verbs): return verbs
                at = blob.find(MARKER, at + 1)
    except (OSError, ValueError):
        return None
    return None


def custom(settings):
    # settings.json "spinnerVerbs": {"mode": "append"|"replace", "verbs": [...]}  ->  (mode, verbs) or None
    try: spinner = json.loads(settings.read_text()).get('spinnerVerbs')
    except (OSError, ValueError, AttributeError): return None
    if not isinstance(spinner, dict) or spinner.get('mode') not in ('append', 'replace'): return None
    verbs = spinner.get('verbs')
    verbs = [v.strip()[:40] for v in verbs if isinstance(v, str) and v.strip()] if isinstance(verbs, list) else []
    return spinner['mode'], verbs


def stat(path):
    try:
        info = os.stat(path)
        return [info.st_size, info.st_mtime_ns]
    except (OSError, TypeError):
        return None


def compute(binary, settings):
    verbs = builtin(binary)
    data = {'verbs': verbs or FALLBACK, 'source': 'binary' if verbs else 'fallback', 'mode': 'default'}
    extra = custom(settings)
    if extra and extra[1]:
        mode, more = extra
        data['verbs'] = list(dict.fromkeys(data['verbs'] + more)) if mode == 'append' else list(dict.fromkeys(more))
        data['mode'] = mode
    return data


def main():
    found = shutil.which('claude') or next((str(p) for p in (Path.home()/'.local/bin/claude', Path.home()/'.claude/local/claude') if p.is_file()), None)
    binary = os.path.realpath(found) if found else None
    settings = Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home()/'.claude')/'settings.json'
    key = [binary, stat(binary), str(settings), stat(settings), stat(__file__)]
    cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home()/'.cache')/'serpantinum-addons-v2'/'clawd-verbs.json'
    try:
        cached = json.loads(cache.read_text())
        verbs = cached['data']['verbs']
        if cached['key'] == key and verbs and all(isinstance(v, str) and v for v in verbs):
            print(json.dumps({'ok': True, 'data': cached['data']}, ensure_ascii=False))
            return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        pass
    data = compute(binary, settings)
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        tmp = cache.with_name(cache.name + f'.{os.getpid()}.tmp')
        tmp.write_text(json.dumps({'key': key, 'data': data}, ensure_ascii=False))
        os.replace(tmp, cache)
    except OSError:
        pass
    print(json.dumps({'ok': True, 'data': data}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
