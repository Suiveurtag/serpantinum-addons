# AI Tokens, lifetime counter widget

A native desktop widget (type `tokens`, "AI Tokens") showing every token you have used with Codex and Claude Code:
a large odometer-style lifetime total, smaller Codex, Claude, opencode and llama.cpp counters, a live indicator, and a status line per source.
The Codex and Claude counters always show. opencode and llama.cpp appear at 120 % of the default size or more, the same percentage the widget editor shows (width ÷ 360). They are opt-in toggles in the Addons settings; while off they show `off`.
Changes that arrive in the same burst (a 140 ms window, the same timing as the bar module) are rolled together: every counter that moved, the total included, rolls its digits at once for about a second; the others stay still.
Add it from the widgets editor like any other widget; size and position are the native ones.

It is also a **bar module**: Settings → Bar → Modules lists "AI Tokens" under available modules; drag it into any zone. Horizontal bars show
the odometer total with a live dot; hovering folds it into the Codex / Claude split. Vertical bars show the compact total (`5.55B`).
Removing the addon leaves the id in your bar layout; delete it from the bar settings first.

## How the numbers are built

| Source | Historical baseline | Live updates | Dedupe |
| --- | --- | --- | --- |
| Codex | The account's own `summary.lifetimeTokens` from `codex app-server` → `account/usage/read` (verified on codex-cli 0.166.0; its daily buckets sum exactly to it). Codex's own login is used, nothing is read or stored | `~/.codex/sessions` rollouts: growth of `total_token_usage.total_tokens`, scanned every 3 s, per file high-water mark | Repeated or replayed snapshots add nothing; forked sub-agent threads replaying parent history are counted once |
| Claude Code | None exists locally: only what `~/.claude/projects` still holds (subagents included) plus everything the collector has kept since | Transcript tails, every 3 s | `message.id` + `requestId`; a message that grows adds only the growth |
| opencode | None: sessions it still holds in `~/.local/share/opencode/opencode.db` (read-only, every 3 s) | Session table totals (input, output, reasoning, cache read/write) | A session keeps its highest total, even once opencode deletes it |
| llama.cpp | None: counters start at zero when the collector first sees them | `/metrics` of the llama-server URL set in the llama.cpp row of the Addons settings (default `http://127.0.0.1:8080`; `addonsV2TokensLlamaCppUrl` in `settings.json`), every 3 s (prompt + generated tokens) | A server restart (counters go back down) adds everything it reports again from zero; nothing is added while it is not running |

Claude tokens are input + output + cache creation + cache read. `~/.claude/stats-cache.json` is deliberately ignored: its daily
totals are 2-3x those of the deduplicated transcripts.

Codex total = account lifetime + Σ over days of `max(0, local_day − account_day)`. The second term is only usage the account has
not counted yet (today's, typically); when the account catches up it shrinks as the account figure grows, so nothing is counted twice.
If the account is unreachable the last stored account snapshot is kept, so the figure never drops; with no snapshot at all the Codex
counter shows `0` flagged `no account total` and the combined total is marked `partial`. No local estimate replaces a missing baseline.

Claude history older than the transcripts Claude Code still keeps (here: before 2026-10-20) is not recoverable and is not counted;
the card says `local since <date>`. The collector stores totals in SQLite, so anything it has seen survives Claude purging transcripts.

## Collector

`scripts/tokens/collector.py` (stdlib only), run by the user unit `serpantinum-tokens.service` (installed and enabled by `install.py`).
State lives in `~/.local/state/serpantinum/tokens/` (dir 0700): `tokens.db` (SQLite, WAL) and `state.json` (0600, counters and
status only) which the widget watches. Idle cost: a stat pass every 3 s, an account sync every 10 min (backoff up to 1 h when failing), and one read-only query every 3 s each for Hermes (`TOKENS_HERMES_DB`, default `~/.hermes/state.db`) and for opencode or llama.cpp when those are on.

The live dot (bar and widget) pulses while any agent is working: Codex and Claude Code when a token event lands in their logs; Hermes when it stores a message or spends tokens; opencode when a session's token count grows; llama.cpp when its counters grow. It stays lit for 8 s after the last change. The Hermes source is always read, since it has no settings toggle; opencode and llama.cpp follow their toggles.

```sh
python3 ~/.local/share/serpantinum-addons-v2/scripts/tokens/collector.py status   # last published state
python3 ~/.local/share/serpantinum-addons-v2/scripts/tokens/collector.py once     # scan + sync + print, no daemon
systemctl --user status serpantinum-tokens     # journalctl --user -u serpantinum-tokens
```

Recovery: a damaged database is renamed `tokens.db.corrupt-<time>` and rebuilt from the logs and the account (Claude history already
purged by Claude Code is then lost). Dedupe keys and file checkpoints older than 180 days are pruned daily. `state.json` older than
150 s makes the widget show `collector stopped`. `--without-tokens` removes the widget and service but keeps the database.

Tests: `python3 -m unittest discover -s tests -p test_tokens.py -v`.
