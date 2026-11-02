#!/usr/bin/env python3
"""Read the latest Codex rate-limit snapshot (used % and reset time per window) from recent rollouts, nothing else."""
import json
import os
from pathlib import Path


def latest(root):
    files = []
    for path in root.glob('*/*/*/*.jsonl'):
        try:
            files.append((path.stat().st_mtime, path))
        except OSError:
            continue
    files = [p for _, p in sorted(files, reverse=True)[:12]]
    best = None
    for path in files:
        try:
            with path.open('rb') as f:
                f.seek(0, 2)
                f.seek(max(0, f.tell() - 262144))
                lines = f.read().splitlines()
            for line in reversed(lines):
                try:
                    event = json.loads(line)
                    limits = event.get('payload', {}).get('rate_limits')
                    if limits and limits.get('limit_id') in (None, 'codex'):
                        stamp = event.get('timestamp', '')
                        if best is None or stamp > best[0]:
                            best = stamp, limits
                        break
                except (ValueError, AttributeError, TypeError):
                    continue
        except OSError:
            continue
    return best[1] if best else {}


def main():
    root = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex') / 'sessions'
    limits = latest(root)
    result = {'agent': 'codex', 'event': 'Status', 'session_id': 'rate-limits'}
    for source, dest in [('primary', 'five_hour'), ('secondary', 'seven_day')]:
        window = limits.get(source) or {}
        if not isinstance(window, dict):
            continue
        for key, suffix in (('used_percent', ''), ('resets_at', '_resets')):
            value = window.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                result[dest + suffix] = value
    if len(result) > 3:
        print(json.dumps(result))


if __name__ == '__main__':
    main()
