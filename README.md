# Serpantinum — personal addons v2

Addons pack for the [Serpantinum](https://github.com/Suiveurtag) desktop shell: Clawd, Capri, Seasonal effects, AI Tokens, cursors, keybinds, monitors and more.

**Discord:** <https://discord.gg/qwVDZAtJqE>

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)"
```

> **Note:** this is a personal project that I use daily. It is shared as is: it may be unstable, and updates and support are best effort. Large chunks of the code was written with vibe coding. Installation backs up every file it touches and can be undone, but review the changes and try them in your own setup before relying on them.

## Contents

1. [Compatibility](#compatibility)
2. [Prerequisites](#prerequisites)
3. [Installation and removal](#installation-and-removal)
4. [Troubleshooting](#troubleshooting)
5. [Releases and changelog](#releases-and-changelog)
6. [Feature list](#feature-list)
   1. [Clawd, Claude Code mascot](#1-clawd-claude-code-mascot)
   2. [Capri, desktop companion](#2-capri-desktop-companion)
   3. [Halloween, seasonal effects](#3-halloween-seasonal-effects)
   4. [AI Tokens, token counter](#4-ai-tokens-token-counter)
   5. [Wallpaper Engine backgrounds (scenes)](#5-wallpaper-engine-backgrounds-scenes)
   6. [Mouse, cursors and trackpad](#6-mouse-cursors-and-trackpad)
   7. [Keybinds and keyboard layout](#7-keybinds-and-keyboard-layout)
   8. [Monitors](#8-monitors)
   9. [Desktop tools](#9-desktop-tools)
   10. [Theme and colours](#10-theme-and-colours)
   11. [Network and idle](#11-network-and-idle)
   12. [Startup](#12-startup)
   13. [General settings (Addons → General)](#13-general-settings-addons--general)
7. [Keyboard shortcuts added](#keyboard-shortcuts-added)
8. [IPC commands](#ipc-commands)
9. [Tests and validation](#tests-and-validation)
10. [Development tools](#development-tools)
11. [Detailed documentation](#detailed-documentation)

## Compatibility

Policy: **always the latest Serpantinum release.** Each addons release records the Serpantinum version it was tested on (as `min` and `tested` in [`compat.json`](compat.json)). A newer Serpantinum only gives a warning; an older one is refused unless you pass `--force`.

| Component | Requirement |
| --- | --- |
| Serpantinum | Always use the newest version |
| Hyprland | 0.55 or newer, with Lua configuration |
| Quickshell | 0.3.0 or newer |

After a Serpantinum update the addons must be reinstalled; the shell shows "Reinstall addons" in Settings when needed.

## Prerequisites

| Item | Use |
| --- | --- |
| Serpantinum installed (see [Compatibility](#compatibility)) | Shell modified by the installer |
| Hyprland with Lua configuration | Shortcuts, cursors, trackpad, zoom, outline (the click guard needs Hyprland 0.55+) |
| NetworkManager, systemd-resolved, `jq`, `matugen` | Mullvad DNS and colour generation |
| Python 3 with Pillow | Installer, colours, cursors |
| Node.js | Hooks and chat for Capri and Clawd |
| `grim`, `wl-copy` | Colour picker, frozen capture |
| `udevadm` | Trackpad detection |
| systemd (user session) | AI Tokens collector, Wallpaper Engine service |
| Codex CLI (`codex login`) | Clawd chat and Capri's ChatGPT provider (subscription) |
| Ollama (optional) | Capri running locally |
| Qt 6.12, CMake, EGL, GBM, epoxy, `we-layerd` | Wallpaper Engine backgrounds (optional) |

## Installation and removal

### Install

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)"
```

This opens the terminal manager (`addons.py`). Extra arguments go after `_`, e.g. `... _ update`.

- Shell changes are computed first, then applied. An unknown anchor stops the installation **without changing anything**.
- Each modified file is backed up (dated) in `~/.local/share/serpantinum-addons-v2/backups/`.
- A second installation changes no file (idempotent).

### Update

- In the shell: the peach **Addons update** button at the bottom of the Settings sidebar (checked about hourly), or the addons card in Settings → About (hold to update).
- In a terminal: `bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)" _ update`

### Reinstall

Needed after each Serpantinum update (Settings shows "Reinstall addons"), or to repair an installation:

```sh
python3 addons.py reinstall          # from a clone
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)" _ reinstall
```

To install a specific release (rollback), add `--ref vX.Y.Z`.

### Uninstall

Settings → About → red **hold to uninstall** button (opens the terminal manager on Uninstall), or:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)" _ uninstall
```

Uninstall restores the shell and removes the services, hooks and addon files. Your settings values and data (for example the AI Tokens database, backups) are **kept**; add `--purge` to remove them too.

### Partial removal

The other addons stay in place:

```sh
python3 install.py --without-halloween   # seasonal effects
python3 install.py --without-capri       # Capri
python3 install.py --without-clawd       # Clawd (also removes its Claude/Codex hooks and the status relay)
python3 install.py --without-tokens      # AI Tokens widget and its service (the database stays)
serpantinum reload
```

Setting values stay in the configuration, dormant, and come back when you reinstall.

### Developer mode

```sh
git clone https://github.com/Suiveurtag/serpantinum-addons-v2
cd serpantinum-addons-v2
python3 install.py && serpantinum reload
```

`python3 install.py --check` reports the state without changing anything (`--json` for machines; exit 0 ok, 2 and 3 for problems).

## Troubleshooting

- Run `python3 addons.py doctor --report`: it checks the installation and prints a report you can paste into an issue.
- Logs: `~/.local/state/serpantinum-addons-v2/logs/`.
- Quickshell shows a ghost or old shell after installing: run `serpantinum reload`.
- Open an issue on [GitHub](https://github.com/Suiveurtag/serpantinum-addons-v2/issues) with the doctor report, your Serpantinum version and what you expected.

## Releases and changelog

See [`CHANGELOG.md`](CHANGELOG.md) and the [GitHub Releases](https://github.com/Suiveurtag/serpantinum-addons-v2/releases). Maintainers: [`docs/releasing.md`](docs/releasing.md).

---

## Feature list

Ordered from the largest features to the smallest.

### 1. Clawd, Claude Code mascot

Pixel mascot of Claude Code, a flat orange (`#D97757`) figure, drawn as PNG strips at whole-number scale without smoothing.

**Activation and settings (the "terminal" card in Addons → General)**
- Enable (off by default); scale from 2× to 8× (4× by default); walking speed (calm, normal, active); sleep delay from 1 to 60 minutes (5 by default); "Summon on this screen".
- `Super+Shift+L` toggles Clawd.
- When disabled: windows, timers and sockets are unloaded; only the hook socket stays.

**Interactions**
- Drag: he follows the pointer, including across screens; on release he falls onto whatever is under the drop point (top of a window or the bottom of the screen).
- Left click: small reaction; wakes him; opens or closes the session log (after 250 ms, so a double-click does not open the log).
- Double-click: opens the chat.
- Middle click: petting (petpet) with a hand for about 3 s, then hearts on the next click; during work he jumps, then carries on.
- Right click: ASCII menu — `> sleep` / `> wake`, `> revive`, `> dreams`, `> talk`, `> hide`, `> settings`; Escape or a click outside closes it.

**Autonomous life**
- Walks along the bottom of his screen (above the bar), blinks, watches the pointer, sits down, falls asleep after the configured delay.
- Performance mode: no exploring, no following, reduced window refresh.

**Windows and screens** (`world` switch, `windows`)
- Perches on top of floating windows, follows them when they move, walks along their visible edge, hesitates at the end of the run, jumps or comes back.
- When the window disappears, moves to another workspace, is covered, maximised or moved away: he falls and lands with `oops`.
- A quarter of his walks explore: jump onto a nearby window, watch from a window edge (`peek`), or walk toward the cursor.
- Window reactions: a window opens on his screen → he looks at it; a window closes near him → `startled`; focus changes → a glance; workspace change → he trips.
- Follows the cursor to another screen (`follow` switch) when he is free.

**Claude Code and Codex**
- `hooks` line on the card: `[ ] claude · [ ] codex · [ ] stats`. Nothing is touched until you click.
- Install from a terminal: `scripts/clawd/hooks.py <status|install|uninstall> <claude|codex|statusline>`.
- Each installation adds one group per event next to the existing ones, backs up the file (dated) before every change, and only removes `clawd-hook.js` commands.
- The hook sends one local JSON line (agent, event, session id, tool, directory, process PID to find the terminal, action target, model), always exits with 0 in under 500 ms, and does nothing if the shell is not running.
- Privacy: no prompt, no answer and no full tool input leaves the hook. The target is a short name (file name, program name of a command, search pattern, URL host, task list `x/y`). Patterns and queries stay in shell memory, never on disk.

**What he shows for each event**

| Event | Clawd |
| --- | --- |
| Prompt submitted | `think`, then his work loop; new spinner verb |
| Tool failure | `oops`, then recovers |
| Permission request | `alert` + `⚠ permission · <folder>` |
| Waiting for an answer | `… waiting · <folder>` for 8 s |
| Turn finished | `happy` + `✓ done · <folder>`; `celebrate` (confetti) after 3 min |
| Turn error (API, limit) | `sad` + `✗ error · <folder>` |
| Session start | `wave` (except after a compaction) |
| Compaction | `compact` |
| Cost crossing a 5 $ step | `coin` |
| 5 h or 7 d limit at 100 % | scene (see below) |

**Work loops by tool**

| Tool | Loop (`_2` variant alternates) |
| --- | --- |
| `Read`, `NotebookRead`, `view_image` | reading (book / scroll) |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `apply_patch` | writing (pencil / sheet with a diff) |
| `Bash`, `exec_command`, `shell`… | terminal / scrolling output |
| `Grep`, `Glob`, `LS`, `ToolSearch` | magnifier / sweeping the ground |
| `WebFetch`, `WebSearch` | globe / radio antenna |
| `Task`, `Agent`, `spawn_agent` | mini-Clawd / two mini-Clawds |
| `TodoWrite`, `update_plan` | task list / ticked boxes |
| Others (MCP…) | keyboard / fast typing |

- Events from a sub-agent do not replace the main thread's tool; after 5 s of calm on the main thread, he plays the sub-agent's tool.
- Typing speed depends on effort: low ×0.75, medium ×1, high ×1.25, xhigh and max ×1.5.
- Very full context (≥ 80 %) or 5 h limit ≥ 90 %: sometimes a `sweat` pause.

**Effort colours** (`colours` switch, shader recolouring of the body pixels only)

| Claude | Colour | Codex | Colour |
| --- | --- | --- | --- |
| low | yellow `#FFC107` | light | white |
| medium | green `#4EBA65` | medium | mint `#ACFFD8` |
| high | pale blue `#B1B9F9` | high | OpenAI blue `#0093FF` |
| xhigh | violet `#AF87FF` + white glint | extra high | red `#FF6363` |
| max | Claude Code colours scrolling | max | gold, glints, golden dust |
| ultracode | sky blue `#9BF6FF`, lightning | ultra | nebula and shooting stars |
| 2 sub-agents or more | "fake ultracode" in `#EB83FF` | | |

The effort settings are per level and per agent, in the **effort** line of the card. Each level name is drawn letter by letter, cycling through its colours like a terminal.

**Thoughts (bubble above his head)**
- `✻ Pondering… 1m 05s`: the glyph turns orange, the verb comes from the spinner verbs of the installed Claude Code (or a generic list), and the elapsed time since the prompt is shown.
- `full` mode: also shows, for 2.5 s, the action that just started (`Edit main.py`, `Bash npm`), and every 14 s the model, effort, context, cost and limits (alert colours in peach).
- `verbs` mode (verbs and time only) or `off`.
- Count of running sub-agents (`2 sub-agents · Haiku 5.5 · ctx 31%`); a `[n]` counter when several sessions are working.

**Session log** (left click on Clawd)
- List of Claude Code and Codex sessions, most recent first, with state (●/○), alert/working/done, folder, role, tool, time and context.
- Clicking the circle follows a session or a sub-agent; clicking the rest of the row brings the terminal to the front.
- `☾ dreams` tab: the dream collection.

**Bubbles**: permission > error > done/waiting > notification/music; a lower-ranked bubble never replaces a higher one. Clicking a bubble brings the session's terminal forward. Terminals behind tmux or screen are not found.

**Statistics (`stats` line)**
- Makes Claude Code's status bar run the `clawd-status.js` relay, which sends model, effort, context (%, window size), cost, and 5 h and 7 d usage.
- If a status bar already existed, it is wrapped and keeps displaying; disconnecting restores it exactly.

**Shell integration** (`ClawdEvents.qml`)
- Current track title (`♪ <title>`, 28 characters at most).
- Spotify music above 90 % volume: dancing (`dance`, `vibe` with headphones, `twirl`, `wiggle`, `breakdance`) to the beat detected in the bass; registers as a Cava consumer.
- Notifications: he walks under the popups, looks up and reads; critical alerts and timers trigger an alert; Do Not Disturb only lets critical ones through.
- Low battery: tired; very low: urgent reaction; charging: applauds.
- Brightness ≤ 15 %: drowsy; muted sound: shh; launcher, clipboard and menus: he looks up.
- Clock on the hour: jumps to a clock widget and rings; rain or snow: `rain` mood (umbrella) or `snow` mood (shivers); active timer: a glance at the bar.
- He also walks on desktop widgets, which act as platforms like window tops.

**Chat** (`> talk`, double-click)
- Terminal beside him; Enter sends, Escape closes (history stays), a click outside also closes.
- `[look]` or `/look …` attaches a capture of the screen (JPEG 1280 px, on request, deleted after use). `[clear]` clears the conversation.
- Each message gets the shell context (active sessions, tool, cleaned target, quotas, time, mood), never commands or paths.
- Answers come from Codex CLI (ChatGPT subscription, low effort), isolated (read-only sandbox, tools and browser disabled, filtered environment, temporary directory deleted). History: 60 messages kept, 20 sent. 85 s budget, retry after 1.5 s if Codex is busy.
- He answers in the user's language; the interface stays in English.
- Setup: `codex login` once; the card shows `ChatGPT via Codex · signed in` or `run codex login`.

**Sleep and dreams**
- He falls asleep after the delay, in the classic way or (every other time) under a blanket (`sleep_blanket`).
- While asleep, events can happen: turning over, dreaming (a cloud above his head, clickable), talking in his sleep (a sentence in the thought bubble), sleepwalking on the ground.
- Dreams: "Rainbow surf" (surfing a wave of rainbow tokens) and "Gemini" (nightmare, startled at the end).
- The collection (`addonsV2ClawdDreams`) keeps the last 40 dreams; dreams never had appear as `? ???`.
- Waking after 15 min or more: groggy (`wake_groggy`).

**Quota scenes**
- 5 h limit at 100 %: nuclear scene (≈ 20 s), then he dies.
- 7 d limit at 100 %: singularity (≈ 37 s, he dies) or surge (≈ 41 s, he survives and recharges the week), chosen at random.
- Not triggered on the first reading (no explosion for a state already reached); once per window.
- Recharge (`recharge`) at the end of the 5 h window; silent 7 d reset.
- Codex: `scripts/clawd/codex_limits.py` reads the local logs every 30 s; `codex-resets.com` is queried every 60 s (announcements, scheduled resets, banked resets).
- Several close sources (less than 30 min apart) produce only one scene.

**Death and revival**
- After a scene: grey, on his back, crosses in his eyes, smoke. He no longer reacts to anything; his bubbles stay visible.
- Revives with `> revive`, when a new Claude Code or Codex session starts (except after a compaction), or when the shell starts / is activated 3 h or more after his death. Revival takes about 9 s with a halo of light.

**Animations**: 60 strips plus 32 idle "acts" (book, cheering, bike, carrying, broom, rowing, fishing, campfire, binoculars, photo, nap), played rarely on the ground, never twice in a row.

**IPC**
- `clawd toggle`, `appear`, `hide`, `play <name>` (animations, scenes, dreams), `state` (debug JSON).

**Documentation**: [`docs/clawd.md`](docs/clawd.md).

### 2. Capri, desktop companion

A small animated companion installed on the desktop, with an illustrated card in Addons → General.

**Activation and display**
- Switch in Settings; `Super+Shift+K` toggles the same option.
- `Ctrl+Alt+C` tucks her into her biochip (bottom-left corner) or brings her back out.
- Disabled: windows, timers, engine and Node helper are unloaded; the card stays a still image.
- Size: small (0.45), medium (0.6), large (0.8), applied immediately.
- On another screen: move, or follow the pointer between screens.
- Wandering, perching on windows and possessing windows (switch "wander / window effects").
- Independent reactions: jealousy of assistants and system reactions ("PC reactions").
- Resting place: a corner or the taskbar.
- Animations: automatic (follows the shell's performance mode), full, or reduced.
- Language: shell language, English, French, Spanish, Portuguese or Russian; falls back to English.
- Watched assistant: Codex, Claude Code, Antigravity or none (separate from the chat provider).
- Do Not Disturb (DND) mode: she no longer makes spontaneous reactions, but keeps counting hook events.

**Agent hooks (on request only)**
- Explicit connection to Claude Code, Codex and Antigravity, each with "Connect", "Disconnect" and "Check again".
- Only adds Capri's commands, backs up the file before changing it (`*.capri-backup-*`), respects `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `AGY_CONFIG_DIR`.
- Nothing is installed when the settings open, when Capri is activated, or at installation.
- The bridge listens only on `127.0.0.1:47823` and rejects requests coming from a browser.

**Menu (right click)**
- Teleport, satellite, demo, "How does it work?", talk, "Look at my screen", AI model choice, "Make her yours", report, reminders, tuck away, size, screen, sound, wander/possess/jealousy/PC, "Look at my screen from time to time", resting place, animations, monitoring, hooks, language, quit.
- "How does it work?": she points with her arm to "Where is Claude?" (the window of the last prompt), "Claude folder" (opens `~/.claude`, `~/.codex` or `~/.gemini/config` and selects the hooks file), "Where is my icon?" (no bar icon on this shell), "Plug me in", talk, customise.
- Welcome: first run or missing hooks, she offers to connect; otherwise "Capri online".

**Chat setup ("Set her up with her")**
- Locally with Ollama: starts `ollama serve` if needed, downloads a model with a progress bar (gemma3:4b or llama3.2, the bigger one first if the machine allows it), Ollama cloud models if signed in.
- Online without an account: Pollinations.
- Pasted API key: masked while typing, verified, kept in the helper state (0600).
- "Free with Ollama": opens a terminal (`$TERMINAL`, xdg-terminal-exec, kitty, foot…) that runs `ollama launch claude|codex`, after its hooks.
- Without Ollama installed: she opens the download page.

**Providers**
- Ollama, LM Studio, llama.cpp / vLLM, Pollinations, OpenRouter, OpenAI, Groq, Gemini, DeepSeek, Mistral, any compatible HTTP server, Claude Code, ChatGPT / Codex.
- Keyed services ask for their own credentials. An online provider receives the conversation; the chat says so ("local" or "online").
- ChatGPT / Codex: `codex login`, then choose **ChatGPT**; Capri checks the connection, with no credentials form. Isolated calls (empty temporary directory, read-only sandbox, user configuration ignored, hooks, memories, plugins, execution tools and browser disabled).
- Saving is verified; the previous configuration is restored if it fails.

**Looking at the screen**
- "Look at my screen" menu entry, or "look at my screen" in her chat.
- First time: she asks where to send the image (local AI or an online service).
- Capture with `grim` on her screen, 1280 px wide at most, JPEG kept in memory for two minutes at most, never on disk; with ChatGPT, passed to `codex exec -i` from a temporary directory that is deleted afterwards.
- "From time to time" option: every 8 to 15 minutes when you are present and on another window.
- Needs a vision-capable model (gemma3, ChatGPT, Gemini, OpenAI); otherwise she says so and stops.

**Chat and memory**
- History and remembered facts are stored in `~/.local/state/serpantinum/capri/{chat,memory}.json` (folder 0700, files 0600).
- "Forget our conversations" clears the history and the Claude session; facts stay editable separately.
- "Make her yours": name, persona, remembered facts and custom lines; the menu also offers the guided version.

**Sounds**
- 18 signals (teleport, done, alert, error, hello, voice blips, tic, star, landing, takeoff, lightning, charge, possession, launch, fall, reminder, jealousy) synthesised as WAV by `scripts/build-capri-sounds.py`, played with QtMultimedia.
- Replace them with your own files (`done.mp3`, `alert.wav`, `.ogg`, `.m4a`…) in `~/.config/serpantinum/capri/sounds/`; the folder opens from the Sound menu.
- Muted from the menu (`addonsV2CapriMuted`).

**Known limits**: a full-screen app can cover the companion or its editor; leaving full screen or choosing another screen makes her visible again.

**Documentation**: [`docs/capri.md`](docs/capri.md).

### 3. Halloween, seasonal effects

Optional layer, no change to the background. Two independent switches: **Addons → Halloween effects** (motion) and **Theme → Seasonal · Halloween** (the "Halloween Night" palette with the moon illustration).

**Palette and surfaces**
- Smoky surfaces (`#171216`, burnt maroon `#2b2026`), warm lights (ember `#cd7745`, candle ivory `#e9b77c`), cold lights (moonlight `#acb3cb`).
- The theme stays in place when the effects are off; the normal palette is never overwritten.

**Settings and panels**
- Directional haze on each Settings line, under the controls.
- Glowing hearth at the bottom of important panels; reactive cobwebs in the corner of Settings.
- Engraved celestial dial with three distant points and bats perched on the clock.
- Major actions (play/pause…) have bat silhouettes (1.75 s exit); on sustained hover, a new leak every 4.2 s with a 1.6 s debounce.
- Pulsing halo on control buttons; energy on system actions; hold: confirmation energy.

**Music**
- Cover crown reacting to the bass.
- Glass glint on the cover at every track change.
- The Play/Pause button gains an electric outline, then an enlarged fleuron.

**System, network, widgets**
- Conductive currents around power profiles; energy vapour on loaded controls.
- Network: real vector conduits between the core and the cards; packets travelling along them; Wi-Fi as warm waves, Bluetooth as cold motion, Ethernet straight.
- Widgets: clock halo, gauge filaments, weather haze, music ribbon, moving reflections.

**Launcher, OSD, lock, sound**
- Launcher: bats and branching lightning when it opens and at every change of results (380 ms limit).
- Volume/brightness: teardrop-shaped souls (eight pools), directional mist in the lines, sound vapour.
- Lock: veil adjusted to authentication and failure; focus light on the password field.

**Directional openings and background**
- Each panel (Settings, clock, music, network, sound, system, backgrounds, notifications, launcher) opens with bats leaving from the correct edge; the bats follow 2.05 s paths.
- Silhouettes cross the background from time to time (every 3.2 to 8 s), when their surface is visible.

**Bar and notifications**
- Each vertical or horizontal module gets an ember; selected modules have a small hanging bat. No change in width or clicks.
- Notification cards: two candles and a warm under-light; actions and expiry stay native.

**Intro**
- At startup or on activation: a 3.9 s intro (eclipsed moon, lightning, wider bird flight, vapour, two flames). Cancelled on shutdown or in performance mode.

**Performance mode and shutdown**
- Performance: still atmosphere, no ambient motion, no bursts.
- Disabled: all effects, loops and clocks are unloaded; the selected theme stays.
- Moon switch: new moon = off, full ember moon = on, with keyboard and accessibility support.

**Documentation**: [`docs/halloween.md`](docs/halloween.md).

### 4. AI Tokens, token counter

Native widget (type `tokens`, "AI Tokens") and bar module.

**Display**
- Widget: large token total (rolling counter), Codex and Claude totals, live indicator and the state of each source. Added from the widget editor.
- Bar module: Settings → Bar → Modules → "AI Tokens", to drag into a zone. Horizontal bar: rolling total, hover to see the Codex / Claude split. Vertical bar: compact total (`5.55B`).
- Live indicator: lights up for 8 s after each token event.

**Calculation**
- **Codex**: base = the account's lifetime total (`codex app-server` → `account/usage/read`, using the existing Codex login); plus the local logs in `~/.codex/sessions`, counted by changes in `total_token_usage`; replayed and duplicated sub-agent entries are counted only once.
- **Claude Code**: `~/.claude/projects` (sub-agents included), deduplicated by `message.id` + `requestId`; tokens = input + output + cache creation + cache read. `stats-cache.json` is deliberately ignored.
- If the account is unreachable: the last known value is kept, and the total never drops; without any base, `0` marked "no account total" and the total marked as partial.
- Claude history older than the transcripts Claude Code keeps cannot be recovered; the card shows `local since <date>`.

**Collector**
- `scripts/tokens/collector.py` (standard library only), user service `serpantinum-tokens.service`, installed and enabled by `install.py`.
- SQLite database in WAL mode in `~/.local/state/serpantinum/tokens/` (folder 0700); `state.json` (0600) read by the widget.
- Costs: scan every 3 s, account sync every 10 min (backs off up to 1 h on failure). systemd limits: 300 MB, lower priority.
- Corrupt database: renamed `tokens.db.corrupt-<time>` and rebuilt from the logs and the account.
- `state.json` older than 150 s: the widget shows `collector stopped`.
- Commands: `collector.py status`, `collector.py once`, `systemctl --user status serpantinum-tokens`.

**Documentation**: [`docs/tokens.md`](docs/tokens.md).

### 5. Wallpaper Engine backgrounds (scenes)

Optional integration described in detail in [`WALLPAPER_ENGINE.md`](WALLPAPER_ENGINE.md).

- Displays Wallpaper Engine scenes on each screen through the local daemon `we-layerd` and the `we-gui` application (scenes only, with the 16 bundled scenes).
- Choosing a background in the shell only frees the affected screen; `output-clear` excludes a screen from global backgrounds.
- Pauses: manual, full screen, maximised, lock and screen power combine; automatic resume keeps a manual pause.
- Audio capture stops when no background is configured or when paused/locked.
- GPU channel: DMA-BUF buffer shared with Qt (pool of three GBM buffers); the glass blur samples the live scene.
- The last presented frame serves an open panel during a pause.
- Installation: `python3 scripts/install-wallpaper-engine.py --engine <we-layerd repository>`; dated backups, atomic replacement, no system package modified.
- Service `we-layerd.service`, assignments restored at startup.
- Control: `we-layerd ctl status|pause|resume`, `we-layerd output-clear <screen>`.
- Out of scope for now: universal compatibility with Workshop scenes, advanced puppets (morphing), physical unplugging, Windows parity.

**Documentation**: [`WALLPAPER_ENGINE.md`](WALLPAPER_ENGINE.md).

### 6. Mouse, cursors and trackpad

Tab **Addons → Mouse** (sub-tab "Mouse").

**Cursor themes**
- Installed Xcursor themes, with sizes from 16 to 128 px.
- Import of theme archives (zip, tar.gz); the imported theme is kept locally.
- 31 customisable pointer roles: arrow, help, progress, busy, hand, text, vertical text, cross, cell, move, input, forbidden, copy, alias, resizing (east-west, north-south, diagonals, edges and corners), zoom in and out, context menu, pencil.
- Formats: animated PNG, GIF and WebP, Windows `.cur` and `.ani`, Xcursor; the click point is adjustable visually.
- Animated preview of each role.
- "Normal select": the same cursor for every role, without losing customisations.
- Reset a role, discard pending changes, export a reusable archive to `~/Downloads` (`.tar.gz`).
- Immediate application for a full theme or restoring default icons; other changes go through "Apply".
- Each scheme gets a unique theme name, so applications reload the modified cursors.
- Sync: Hyprland (`env.lua`, `hyprctl setcursor`), GTK 2/3/4, Qt/KDE (`kcminputrc`), XWayland (`Xresources`), xsettingsd, D-Bus and systemd, gsettings, Flatpak. Applications that draw their own pointer keep it.
- Full rollback on a Hyprland configuration error.
- Restart applications that cache cursors.

**Mouse acceleration** (Addons → Mouse)
- Switches Hyprland between adaptive (`adaptive`) and flat (`flat`) acceleration, for mice only.
- Saved in `serpantinum_mouse_acceleration.lua`, applied when Hyprland reloads.

**Mouse spotlight** (`Super+Shift+M`)
- Animated circular halo around the pointer, which converges on entry and fades on exit; the rest of each screen darkens.
- Click or Escape closes; the closing click is consumed.
- Scroll wheel: resizes the circle (saved).
- Settings: radius (35 to 350 px, 95 by default) and background darkness (0 to 100 %, 35 % by default, cubic Bézier curve).
- Pointer tracking only runs while it is shown and needs an active Hyprland session.
- Shortcut editable from the "Shortcut" button (opens Keybinds, searches `addonMouseSpotlight`).

**Trackpad** (Addons → Mouse)
- Pointer speed (slider from -1 to 1, step 0.05).
- "Disable trackpad while typing": native libinput protection against accidental movement and taps.
- "Disable clicks while typing": Lua guard that ignores left, right and middle clicks while typing and for 600 ms after the last release; movement remains possible; Ctrl, Alt and Super are not affected. The text is never recorded or sent.
- Only trackpads recognised by udev are configured; mice and TrackPoints are untouched.
- Saved in `serpantinum_trackpad.lua`; backup and rollback on error.

**Documentation**: none separate; see this section.

### 7. Keybinds and keyboard layout

**Shortcut editor**
- List of `hl.bind` bindings from `keybinds.lua`, search across shortcuts and commands.
- Edit by clicking: record a combination (press the keys, Escape to confirm), type (`bind`), action (`exec` or other), command, sliding edit button.
- Add, delete, save; refuses duplicates and empty commands.
- Lua actions, options and generated workspace loops are kept as they are.
- Changes made outside the editor are detected: you must reload before saving.
- Workspaces: `SUPER + 1` to `SUPER + 0` buttons.

**Keyboard layout** (selector at the top of the tab)
- Several installed XKB layouts, in the chosen order; search by language or XKB code.
- `Alt+Shift` switches layout (option `grp:alt_shift_toggle`, enabled only when several layouts are chosen).
- Remove a layout (at least one must remain), applied immediately and saved in `settings.lua`, keeping the other XKB options.
- Rollback if Hyprland reports an error.

### 8. Monitors

- Screen layout: drag and drop, snapping to the edges of other screens (screens never overlap), screen list, screen selector.
- Resolution cards with common names (4K UHD, WUXGA, UWQHD, DCI 4K…), sorted from largest to smallest; choosing a resolution automatically picks the closest refresh rate.
- Refresh rate slider, with the available values.
- Rotation: an 8-position dial (0°, 90°, 180°, 270° and their flipped versions).
- Numeric X/Y position in logical pixels.
- Preview of a single screen; animation of changes.
- "Apply" writes `~/.config/hypr/config/monitors.lua`, reloads Hyprland and restores the previous file on error. If the connected screens changed, it refuses and asks you to reload.

### 9. Desktop tools

**On-screen drawing** (`Super+Shift+D`)
- Annotation layer on the active screen, with a toolbar at the bottom (`P` freehand pencil, `C` ellipse, `R` rectangle, `E` stroke eraser).
- Left button: draw; right-button drag: erase strokes; scroll wheel: stroke thickness.
- `Ctrl+Z` undo, `Ctrl+Shift+Z` redo, `Delete` clears all, `Escape` or the shortcut closes and discards the session.
- Listed in the passive addons; shortcut editable (`addonDesktopDraw` in Keybinds).

**Desktop zoom** (`Super+Shift+Z`)
- Live magnifier around the pointer (1× to 6×); the wheel moves the zoom without scrolling the application underneath.
- Clicks pass through the zoom.
- `Escape` or the shortcut restores the previous zoom; the last chosen level is remembered.
- Session cursor settings are restored when the zoom closes or the shell reloads.
- Needs Hyprland with Lua configuration. Shortcut editable (`addonDesktopZoom`).

**Colour picker** (`Super+Shift+C` or the eyedropper in quick actions)
- Freezes the current screen, outline animation in the theme colours and a compact HEX preview.
- A click expands the HEX, RGB and HSL copy buttons; a confirmation animation closes the picker after copying.
- Escape closes; Enter picks the colour and copies the HEX.
- Needs `grim` and `wl-copy`.

**Frozen capture**
- Frozen screen capture (`Super+Shift+S`), cropped from the frozen image (`crop_frozen_screenshot.py`), with temporary files deleted at the end.

**Windows and screens**
- `Super+Tab`: next screen, pointer moved to the centre of that screen (`mouse-next-monitor-center.sh`).
- `Alt+Tab`: next window on the current screen and workspace, brought to the front.

### 10. Theme and colours

- **Vibrant**: real accent colours sampled from the wallpaper.
- **Vivid**: keeps Vibrant's hue and raises saturation and brightness.
- Surfaces and text keep the shell palette for readability; the synthetic Matugen templates also update application colours.
- Vibrant and Vivid tiles use the same tiles, selection and animations as the shell themes.
- **Accent editor** (Theme, in Vibrant or Vivid mode): drag a point on the wallpaper to choose where each colour is sampled from; double-click (or right-click the swatch) to restore it.
- Choices are saved per wallpaper in `~/.local/state/serpantinum/addons_v2_palette_overrides.json`.
- A video wallpaper uses its starting image for Matugen.
- Matugen mode follows the native generator.

### 11. Network and idle

**Mullvad DNS** (Addons → General and the Network panel)
- Switches to Mullvad DNS-over-TLS on the active Wi-Fi or Ethernet connection; the network panel shows the connection and its mode.
- Detected modes: `mullvad`, `home` (automatic DHCP) or `custom`.
- Checks that resolution works; otherwise restores the previous configuration and reports the error.
- Script: `scripts/dns.sh status|toggle|set home|mullvad` (lock to prevent concurrent runs).

**"Claude mode" idle setting** (Settings → Idle)
- Extra option: when "Do Not Disturb" (Keep Awake) is active, also blocks system suspend and lid close.
- Off by default; only visible and usable on laptops (UPower detection).
- Keeps the session and network alive during long tasks, downloads and AI streams.

### 12. Startup

- Tab next to Keybinds, also reachable from the built-in panel `Super+Shift+P`.
- List of commands launched once when the session starts (`discord`, for example).
- Add, edit, delete, search; same editor as Keybinds.
- Saved in `~/.config/hypr/config/serpantinum_startup.json`, generates `serpantinum_startup.lua` (`hl.on("hyprland.start", …)`). A configuration error restores the previous files.

### 13. General settings (Addons → General)

- **Themed window outline**: thin Hyprland border in the colours of the active palette, seasonal colours included. Off by default.
- **Hide weather location**: the city name in the weather widget is continuously scrambled (random characters), without changing the data.
- **Mullvad DNS**: switch to Mullvad DNS-over-TLS on the active connection (see [Network and idle](#11-network-and-idle)).
- **Legacy clock design**: restores the v1 calendar and clock.
- **Passive addons**: list of tools without a switch, with their shortcut (Capri, Clawd, drawing, zoom, colour picker, capture, monitors, shortcuts, Vibrant/Vivid).
- **Halloween**: switch for the seasonal effects (see [Halloween](#3-halloween-seasonal-effects)).
- **Capri** and **Clawd**: cards with a switch and options (see above).
- The lines are findable in the Settings search (including collapsed options).

---

## Keyboard shortcuts added

| Shortcut | Action |
| --- | --- |
| `Super+Shift+K` | Show / hide Capri |
| `Ctrl+Alt+C` | Tuck away / bring back Capri (biochip) |
| `Super+Shift+L` | Show / hide Clawd |
| `Super+Shift+D` | On-screen drawing |
| `Super+Shift+Z` | Desktop zoom |
| `Super+Shift+M` | Mouse spotlight |
| `Super+Shift+C` | Colour picker |
| `Super+Shift+S` | Screenshot (frozen, corrected version) |
| `Super+Tab` | Next screen, pointer to its centre |
| `Alt+Tab` | Next window on the current screen |
| `Alt+Shift` | Next keyboard layout (if several) |
| Scroll wheel (zoom open) | Adjust the zoom |

All shortcuts are editable in **Keybinds** (search the addon name, for example `capri`, `clawd`, `addonDesktopZoom`). User changes are kept when you reinstall.

## IPC commands

All go through the shell:

```sh
SHELL_QML=~/.local/share/serpantinum/src/quickshell/Shell.qml
quickshell -p "$SHELL_QML" ipc call capri toggle
quickshell -p "$SHELL_QML" ipc call clawd toggle
quickshell -p "$SHELL_QML" ipc call clawd appear     # "show" is read by the CLI as "ipc show"
quickshell -p "$SHELL_QML" ipc call clawd hide
quickshell -p "$SHELL_QML" ipc call clawd play walk  # ok / unknown / off
quickshell -p "$SHELL_QML" ipc call clawd state      # debug JSON
quickshell -p "$SHELL_QML" ipc call addonColorPicker toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopDraw toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom zoomIn
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom zoomOut
quickshell -p "$SHELL_QML" ipc call addonMouseSpotlight toggle
```

## Tests and validation

```sh
python3 -m unittest discover -s tests -v                 # once Serpantinum is installed
python3 -m unittest discover -s tests -p test_tokens.py -v
python3 -m unittest tests.test_release tests.test_release_ui tests.test_manager tests.test_uninstall -v
python3 scripts/clawd/sprites.py --check                  # Clawd sprites up to date
```

- The tests cover native theme integration, tab order and idempotence, preservation of Lua actions, external-edit conflicts, Capri (settings, chat, hooks, guide, AI configuration), Clawd (states, chat, dreams, effort colours), seasonal effects (Qt lifecycle), cursors, zoom, magnifier, trackpad, outline, installation and removal, release/update logic (`test_release`), the in-shell update UI (`test_release_ui`), the terminal manager (`test_manager`) and uninstall (`test_uninstall`).
- Validation in a real session (captures, interactions, logs) is described in the detailed documents.

## Development tools

| Script | Role |
| --- | --- |
| `scripts/build-capri-assets.py` | Generates Capri's assets |
| `scripts/build-capri-sounds.py` | Synthesises Capri's sounds as WAV |
| `scripts/build-seasonal-shaders.py` | Recompiles the Halloween shaders (`.qsb`) |
| `scripts/clawd/sprites.py` | Generates Clawd's sprites from ASCII images (`--check` verifies) |
| `scripts/clawd/shaders.py` | Recompiles Clawd's shaders |
| `scripts/clawd/codex_limits.py` | Reads Codex limits from local logs |
| `scripts/clawd/verbs.py` | Reads the spinner verbs of the installed Claude Code |
| `scripts/clawd/hooks.py` | Installs / removes the hooks and the status relay |
| `scripts/colors.py` | Extracts colours from the wallpaper (Vibrant / Vivid) |
| `scripts/control.py` | Backend for shortcuts, screens and keyboard layout |
| `scripts/startup.py` | Backend for startup |
| `scripts/trackpad.py`, `scripts/mouse_acceleration.py` | Backends for the trackpad and acceleration |
| `scripts/custom_cursor.py`, `scripts/cursor_images.py` | Cursor themes and image conversion |
| `scripts/desktop_zoom.py`, `scripts/mouse_spotlight.py`, `scripts/window_outline.py` | Zoom, spotlight, outline |
| `scripts/crop_frozen_screenshot.py`, `scripts/tokens/collector.py` | Frozen capture, token collector |
| `scripts/dns.sh` | Mullvad DNS switch |
| `scripts/release.py` | Cuts a release (`--dry-run` to rehearse; see `docs/releasing.md`) |
| `native/wallpaper-bridge/` | C++ GPU bridge for Wallpaper Engine (`ctest` tests) |

## Detailed documentation

- [`docs/clawd.md`](docs/clawd.md) — Clawd: controls, sprites, scenes, validation
- [`docs/capri.md`](docs/capri.md) — Capri: controls, hooks, providers, validation
- [`docs/halloween.md`](docs/halloween.md) — Halloween effects: design and validation
- [`docs/tokens.md`](docs/tokens.md) — AI Tokens: sources, calculation, recovery
- [`docs/releasing.md`](docs/releasing.md) — Releasing: versions, changelog, compatibility, rollback
- [`WALLPAPER_ENGINE.md`](WALLPAPER_ENGINE.md) — Wallpaper Engine scenes: installation, control, GPU channel
