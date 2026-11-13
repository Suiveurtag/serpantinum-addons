# Clawd, coding agent desktop pet

Clawd is a pixel companion for Claude Code, Codex, OpenCode and Hermes: a flat
`#D97757` block with two black eyes, arm stubs and four short legs, drawn from
PNG strips at an integer scale with no smoothing. He lives in Settings → Addons → General, in a terminal-style
card. Off by default; OFF unloads every window, timer and Hyprland socket. Only
the hook socket stays, so he knows what your agents are doing when he comes back.

## Controls

| Control | Behaviour |
| --- | --- |
| `Super+Shift+L` | Toggle Clawd (`addonsV2Clawd`). Search `clawd` in Keybinds to change it; the installer preserves edits |
| Left drag | Pick him up; he follows the pointer, across monitors |
| Release | Falls onto whatever is under the drop point: a window top (he lands, then perches on it) or the floor of that screen |
| Left click | Small reaction (none while working); wakes him up; opens / closes the sessions journal (after 250 ms, so a double click does not open it) |
| Double click | Opens the chat (see Chat) |
| Middle click | Petpet: a hand pets him for ~3 s (`> <` eyes); middle click again while petted for `^ ^` eyes and hearts. While an agent works he only startles, then goes back to work |
| Right click | ASCII menu: `> sleep` / `> wake` (`> revive` while he is dead), `> dreams` (the journal's dream tab), `> talk` (opens the chat; hidden while dead or chat is off), `> hide` (turns Clawd off), `> settings`. Escape or an outside click closes it |

Left alone he walks along the bottom of his screen (above the bar's reserved
area), blinks, looks toward the pointer, fidgets (a yawn, a stretch, a bubble of gum, a yo-yo…: see Idle fidgets),
sits, and falls asleep after the configured idle delay. He also lives on your windows and follows the cursor to
other screens (below). Shell performance mode cuts idle actions and stops
pointer polling.

IPC, target `clawd`:

```sh
quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml ipc call clawd toggle
quickshell -p … ipc call clawd appear   # not "show": the quickshell CLI reads it as `ipc show`
quickshell -p … ipc call clawd hide
quickshell -p … ipc call clawd play walk   # "ok", "unknown" or "off"
quickshell -p … ipc call clawd state       # debug: JSON of his mode, support, windows and tracked sessions
```

`play` accepts any animation name from `clawd.json` (`idle`, `blink`,
`look_left`, `look_right`, `look_up`, `walk`, `turn`, `sit`, `sleep`, `drag`,
`fall`, `land`, `spawn`, `think`, `work`, `oops`, `alert`, `happy`, `petpet`, `petpetheart`,
`read`, `bash`, `search`, `web`, `task`, `todo`, `compact`, `startled`, `edit`, `edit_2`, `work_2`, `read_2`,
`bash_2`, `search_2`, `web_2`, `task_2`, `todo_2`, `work_3`…`work_5`, `edit_3`, `read_3`, `bash_3`, `search_3`, `web_3`, `task_3`, `todo_3`, `think_2`, `happy_2`, `celebrate`, `sweat`, `coin`, `sad`, `wave`,
`explode`, `perch`, `perch_look`, `hop`, `stumble`, `teeter`, `peek`, `nuke`, `dead`, `dead_land`, `revive`, `tada`, `yawn`, `bubble`, `work_6`, ...; 155 in all, the idle specials included); loops play
for about 3 s, then normal behaviour resumes. Scenes: `play explode` previews the singularity (about 37 s), `play nuke` the nuclear
variant (about 20 s), `play limit` either at random (Escape skips to the end; both leave him dead); `play surge` the superpowered
weekly variant (about 41 s, he survives it); `play revive` brings him back.
Nothing else plays while he is dead.

## Windows and screens

With `windows` on (card row `world`, `addonsV2ClawdWorld`, default on), Clawd sees the
Hyprland windows of the active workspaces (`j/clients` on Hyprland's socket, not
`Hyprland.toplevels`, which keeps closed windows):

- Window tops are ledges when the window is not maximized or fullscreen, is wider than him
  plus 40 px and has room above it under the bar (in practice floating windows: tiled ones
  start right under the bar). Each screen also has its floor.
- Dropped above a window, or falling past one, he lands on it and perches (seated on its top
  edge, legs dangling). He rides it when it moves, walks along the visible part of its top
  (never into a window in front of it), teeters at its ends, then hops down or turns back.
  When the window closes, moves to another workspace, gets covered or maximized, or jumps
  away (more than 200 px at once, he is startled), he falls and lands with `oops`.
- A quarter of his walks explore: a hop onto a window top close above him, a peek from
  behind a window edge (he walks in until two thirds of him are hidden, looks out for
  3–6 s, then walks out; moving the window makes him step out), or a walk toward the cursor.
- Reactions, at most one every 5 s and six a minute, each with its own cooldown: a window
  opening on his screen → he looks at it; a window closing within 300 px → `startled`; focus
  moving to a window on his screen → a glance (only while idle, sitting or perched); switching
  workspace on his screen while he is on the floor → `stumble` (on a window he just falls).
  None while an agent works or asks for permission, while asleep, dragged or petted, or while
  the menu is open.

With `follow` on (`addonsV2ClawdFollow`, default on), when the cursor stays on another screen
for two checks in a row (2 s apart) and he is idle, sitting or perched (no agent busy, menu and
journal closed), he goes there: across the screen edge when the next screen's floor is
within his height of his own, otherwise he walks off his edge and drops in from the top of
the cursor's screen, near the cursor. Perched, he hops down first.

Performance mode: no exploring, no following, windows refreshed on Hyprland events plus
every 3 s instead of every 240 ms (60 ms while he rides a window), halved reaction budget; he
still lands on windows after a drop and falls when they go away. While he sleeps the window
list is refreshed on events only (every 3 s too when he sleeps on a window). With `windows`
off he is back to the floor of his screen only.

`ipc call clawd state` adds `support` (`null` = the floor, or `{kind: "win", id, dx}`), `cover`
(the window rect he peeks from behind) and `world` (`wins`: windows on screen, `ledges`,
`refreshes`: window snapshots taken).

## Claude Code, Codex, OpenCode and Hermes

The card's `hooks` row connects each agent; `stats` is Claude's status line relay, below. Nothing
changes an agent's config until you click its toggle. Codex then asks you to trust the new hooks.
The same thing from a terminal:

```sh
python3 ~/.local/share/serpantinum-addons-v2/scripts/clawd/hooks.py <status|install|uninstall> <claude|codex|opencode|hermes|statusline>
```

Claude Code and Codex use their native hooks files, adding one group per event next to existing
ones (Capri's included). OpenCode installs one global plugin at
`~/.config/opencode/plugins/clawd-session-watch.js`; Hermes installs and enables the
`~/.hermes/plugins/clawd-session-watch` plugin without tool overrides. The connectors are backed
up before updates or removal. Start OpenCode and Hermes again after connecting or disconnecting.

Claude Code and Codex run `scripts/clawd/hooks/clawd-hook.js` (node), which sends one JSON line
`{agent, event, session_id, tool_name, notification_type, dir, pids, target, model}` (`pids`: the hook's
ancestor processes, used to find the terminal window). An event fired inside a sub-agent also carries
`agent_id`, `agent_type`, and `sub_model` / `sub_tokens`: the model and the input tokens of its last reply,
read from its own transcript (`<session>/subagents/agent-<id>.jsonl`); nothing else of it leaves the hook. The line goes to
`$XDG_RUNTIME_DIR/serpantinum/clawd.sock`. OpenCode and Hermes plugins send the same activity fields
directly to that socket. All connectors stop quietly when the shell is not running.

Privacy: no prompts, replies or full tool inputs ever leave a connector. `target` is a short
label of the action (24 characters at most, control and bidi characters stripped, `PreToolUse` only):
a file's base name for reads and edits, only the program name of a shell command (leading
`VAR=value` assignments skipped, quoted values included; anything but a plain name such as `$(…)` gives
nothing, so no arguments, paths or secrets), the search pattern, the
host of a fetched URL, the web search query, a sub-agent's description, or `done/total` of a
todo list. Patterns, queries and descriptions are truncated, not filtered: they show above his
head in `full` thoughts mode, and stay in memory in the shell only (never written to disk).

| Event | Clawd |
| --- | --- |
| Prompt submitted | `think`, `think_2` or `think_3`, then his working loop in place while the turn runs; a new spinner verb |
| Tool failed | `oops`, then back to work |
| Permission request | `alert` (hops) + `⚠ permission · <dir>` until that session moves on |
| Idle prompt / Codex asks a question | `… waiting · <dir>` for 8 s |
| Turn finished | `happy`, `happy_2` or `happy_3` + `✓ done · <dir>` for 8 s; `celebrate` (confetti) after a turn of 3 min or more |
| Turn failed (Claude `StopFailure`: API error, limit…) | `sad` + `✗ error · <dir>` for 8 s |
| Session start | `wave`, except when Claude restarts the session after a compaction (and the spinner verbs are re-read, at most every 30 s) |
| Compaction (Claude) | `compact` (squashed flat) |
| Stats (`Status`, see below): cost crosses a new multiple of $5 | `coin` |
| Stats: 5-hour / 7-day limit reaches 100 % | nuke or blue screen / kernel panic, 50/50 for 5 h (then dead); singularity or surge, at random for 7 days |

While working he plays the loop of the last tool used by the lead session (the working
session that moved last), picking at random between the loop and its variants (`_2`, `_3`…) each time
the tool family changes, and switching variant every 8–12 s:

| Tool | Loop |
| --- | --- |
| `Read`, `NotebookRead`, `view_image` | `read` (book) / `read_2` (scroll unrolling) / `read_3` (pages flying out of the book) / `read_4` (a newspaper held wide, his eyes scanning over the top) |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `apply_patch` | `edit` (pencil on a notepad) / `edit_2` (sheet held up, diff lines) / `edit_3` (hammer and chisel on a block, chips flying) / `edit_4` (painting a pink heart on an easel) |
| `Bash`, `BashOutput`, `KillShell`, `exec_command`, `write_stdin`, `shell`, `local_shell` | `bash` (terminal above his head) / `bash_2` (output scrolling) / `bash_3` (a progress bar filling above his head) / `bash_4` (a little rocket lifting off its pad) |
| `Grep`, `Glob`, `LS`, `ToolSearch` | `search` (magnifier) / `search_2` (crouched, scanning the ground) / `search_3` (binoculars sweeping left and right) / `search_4` (rummaging through a crate, things flying over his shoulder) |
| `WebFetch`, `WebSearch`, `web_search` | `web` (globe) / `web_2` (antenna with signal waves) / `web_3` (paper planes taking off) / `web_4` (a cloud download: chevrons falling into a tray that fills up) |
| `Task`, `Agent`, `spawn_agent` | `task` (a mini Clawd) / `task_2` (two mini Clawds hopping) / `task_3` (shouting orders through a megaphone) / `task_4` (a mini Clawd hopping from side to side on his head) |
| `TodoWrite`, `update_plan` | `todo` (checklist) / `todo_2` (ticking boxes) / `todo_3` (kanban cards sliding to done) / `todo_4` (sorting his priorities: bars above his head swapping into order) |
| anything else (MCP…) | `work` (keyboard) / `work_2` (fast two-hand typing) / `work_3` (juggling) / `work_4` (coffee break) / `work_5` (meshing gears) / `work_6` (stacking crates into a tower) |

Hooks fired inside a sub-agent do not override the lead thread's tool while it is busy; once the lead thread
has been quiet for 5 s (typically waiting on the sub-agent), Clawd plays the sub-agent's tool instead. A
sub-agent still running after `Stop` (background) keeps him working until its `SubagentStop`.
The session journal lists each tracked sub-agent separately. Click its circle to follow it:
its effort colour, tool loop and thought line then use that agent's state. `follow: auto` restores automatic selection.
Click the rest of a row to raise the parent terminal. The `SubagentStart` / `SubagentStop` hooks cover all four agents;
Claude Code and Codex provide their native sub-agent events; OpenCode child sessions and Hermes delegated agents
use their plugin lifecycle hooks.

When the lead session is strained (context ≥ 80 % or 5-hour limit ≥ 90 %), each variant switch
has a 1 in 3 chance to be a `sweat` break instead. The lead's reasoning effort sets his typing
speed: low ×0.75, medium ×1, high ×1.25, xhigh and max ×1.5.

In automatic mode, the active Claude session takes priority; otherwise the most recently active session or sub-agent
supplies his tool, colour and thought line. An alert beats work beats normal life. A session with no event for 2 minutes
is forgotten, except one waiting for a permission. With two or more busy sessions and sub-agents, a `[n]` counter shows
beside his head.

### Stats (Claude status line)

The `stats` toggle in the `hooks` row makes Claude Code's status line run
`scripts/clawd/hooks/clawd-status.js` (`python3 scripts/clawd/hooks.py <status|install|uninstall> statusline`).
It relays one `Status` line per status refresh:
`{agent: "claude", event: "Status", session_id, dir, pids, model, effort, ctx, ctx_size, cost, five_hour, seven_day, five_hour_resets}`
(model display name, effort level, context used %, context window size in tokens, session cost in USD, 5-hour / 7-day usage %; numbers
that are not finite are left out). If you already had a status line, its command is wrapped
(`node clawd-status.js -- <your command>`): it still runs with the same input and its output is
shown unchanged; disconnecting restores it exactly. Without one, Clawd's prints nothing, so no
status line row appears. Status lines only update the stats of a session (an unknown session is
created idle); they never change what he is doing.

### Effort colours

While the lead session works, his body takes the colour of its reasoning effort (`js/effort.mjs`, recoloured live by
`shaders/tint.frag`: only the pixels of his exact body colour change, so eyes and props stay and every animation carries it).
The spinner glyph and verb take the same colour. Toggle: `[x] colours` in the card (`addonsV2ClawdEffort`); performance mode
keeps the flat colour and drops the motion.

| Claude | Look | | Codex | Look |
|---|---|---|---|---|
| low | yellow `#FFC107` | | light (`low`) | white |
| medium | green `#4EBA65` | | medium | mint `#ACFFD8` |
| high | pale blue `#B1B9F9` | | high | OpenAI blue `#0093FF` |
| xhigh | violet `#AF87FF`, white glint sweeping | | extra high | red `#FF6363` |
| max | the six Claude Code light colours flowing | | max | gold, sweeping glint, four-point glints popping around him, rising gold dust |
| ultracode | sky blue `#9BF6FF`, crackling white, a bolt sweeping through him, flashes, lightning with forks and sparks around him | | ultra | space: a violet-blue nebula with parallax stars and a shooting star on him, stars and shooting stars around |
| 2+ sub-agents working | "fake ultracode": the same lightning in `#EB83FF` | | | |

Claude's effort comes from the status line (`effort.level`); Codex's from the `turn_context` lines of its rollout, read by
`clawd-hook.js` (the effort word only).

### Thoughts

While the lead session works, one line floats above his head, Claude Code spinner style:
`✻ Pondering… 1m 05s`. The glyph cycles `· ✢ ✳ ✶ ✻ ✽` in Clawd orange (a static `✻` in
performance mode); the verb is one of Claude Code's own spinner verbs, re-rolled every ~30 s,
and the elapsed time counts from the prompt. The verbs come from `scripts/clawd/verbs.py`,
which reads the list out of the installed `claude` (Bun binary or npm `cli.js`), applies
`spinnerVerbs` from `~/.claude/settings.json` (`append` / `replace`), and caches the result in
`$XDG_CACHE_HOME/serpantinum-addons-v2/clawd-verbs.json`; a short generic list is used when
Claude Code is not installed.

In `full` mode the line also shows, for 2.5 s, what the lead session just started
(`Edit main.py`, `Bash npm`, at most one flash every 5 s), and every 14 s, for 4 s, the next of
`<model> · <effort>`, `ctx 42%`, `$1.24`, `5h 63% · 7d 20%` (with stats connected); strained values
show in peach and are preferred. While sub-agents run, one more entry joins the cycle: their count with the model
of the one that moved last and its context (its last reply's input tokens over the session's window), e.g.
`2 sub-agents · Haiku 5.5 · ctx 31%`.
`verbs` shows the verb and time only; `off` hides the line.
It never takes clicks, and hides while a bubble, the menu or the journal is open.

Clicking a bubble raises that session's terminal (`hyprctl dispatch focuswindow pid:…`,
the first of the hook's ancestors owning a window) and closes it. Left click on Clawd opens
the sessions journal, newest first: `●/○ ⚠/✻/✓ id dir role/tool elapsed ctx%` (context only with stats connected;
`Cl` = Claude Code, `Co` = Codex, `OC` = OpenCode, `He` = Hermes, `↳` = sub-agent). Click the circle to follow or the rest of a row to raise that terminal.
Terminals behind tmux/screen cannot be found (the multiplexer server is not an ancestor): nothing happens.
Hermes sessions served by a detached gateway are still tracked, though that gateway may have no terminal ancestor to focus.

## The shell (lot 5c)

`ClawdEvents.qml` (inside AddonClawd's Loader, so Clawd OFF destroys it) listens to the shell's singletons, each guarded
with `typeof` and each event arbitrated by `js/mind.mjs`: a new track shows `♪ <title>` (28 chars); while Spotify plays (not a video
player) at its own volume ≥ 90 % (MPRIS `volume`) and the reactions are `all` he registers as a Cava consumer (released on stop, OFF, performance mode, quiet/off and
destruction) and dances (`dance`, `dance_2`, `vibe` with headphones, favoured on a slow beat, `twirl`, `wiggle`, `breakdance`; swing under the bar) at the pace `js/beat.mjs` finds in the low bars (no beat:
normal pace); notifications make him walk under the popups layer (`qs-popups`) when he is on the floor and free, then look up and read (critical: alert, timer app: alert + `⏰ timer`; do-not-disturb mutes
all but critical); bubbles name the app only, never the summary or body; the system volume is ignored, mute
shushes, brightness ≤ 15 % makes him drowsy (shorter nap delay), a battery ≤ 15 % not charging exhausted (≤ 5 %: urgent
reaction), charging cheers; the launcher, clipboard and menus make him look up. Moods (`drowsy`, `exhausted`, `rain`)
slow his pauses, calm his walks and change how he sits. Bubble ranks: permission > error > done/waiting > notification/music
(a lower one never replaces a higher one); shell bubbles last 4 s, a click only dismisses them. Performance mode: no dance,
no Cava. Nothing starts while he is dead or in a scene.

## Widgets and weather (lot 5d)

The widgets of the shell (`qs-widget-<type>-<id>` layers, minus visualizers and huge ones, inset by their 8 px aura) are
ledges like window tops, and a window in front covers them; the widget editor (`WidgetSync.redactModeChanged`) takes them
away, and any other `WidgetSync` signal refetches the layers 450 ms later. On the hour (a timer aligned to :00) a clock
(`time`) widget on his display makes him hop or walk to it and chime; while music plays he prefers a `music` widget as his
dance spot. Rain or storm (`Weather.currentIcon`) puts him in the `rain` mood (an umbrella now and then), snow in the `snow`
mood (shivering); both clear with the sky. A running timer (`TimerState.isActive`) makes him glance up toward the bar now
and then. All of it follows the reactions setting and Mind's budget, and stops in performance mode, while he is dead or in a scene.

## Chat (lot 6)

Open him from the menu (`> talk`) or double-click him. A terminal panel opens beside him with the last
lines of the talk and a prompt. `Enter` sends, `Escape` closes it (the history stays), an outside click closes it too.
`[look]` or `/look …` attaches a screenshot of his screen (grim, JPEG, 1280 px wide at most, on demand only;
the image is used once and its temporary file deleted). `[clear]` forgets the talk. He answers in the user's
language; the UI stays English.

Each message carries a context block built by the shell: the active agent sessions (agent, tool, sanitized
target), quotas, time and mood. Never commands or paths.

Answers come from Codex CLI with the ChatGPT subscription (`gpt-6-luna`, effort low), run isolated: `--ignore-user-config`,
read-only sandbox, hooks, memories, plugins, apps, shell, exec, browser and computer-use disabled, web search off, env
whitelist, temporary dir removed after each run. The read-only sandbox alone does not prevent reads, hence the rest.
History: `~/.local/state/serpantinum/clawd/chat.json` (dir 0700, file 0600), 60 kept, the last 20 sent with each message.
An answer gets an 85 s budget (one retry after 1.5 s when Codex is busy); the desktop gives up at 95 s.
Provider: the card's `provider` row (`addonsV2ClawdChatProvider`) picks where answers come from: `codex` (default, above),
`api` (any OpenAI-compatible hosted API, default `https://api.openai.com/v1`, model `gpt-4o-mini`) or `local` (Ollama,
llama.cpp, LM Studio; default `http://127.0.0.1:11434/v1`, model `llama3.2`, no key). The card's `model` and `url` fields
(`addonsV2ClawdChatModel`, `addonsV2ClawdChatUrl`, empty = default) override them; Enter or leaving the field saves. The `api key`
field (api only) writes the first line of `~/.config/serpantinum/clawd/api-key` (0600), never `settings.json`; `CLAWD_CHAT_API_KEY` wins when set.
`api` and `local` send the persona, history, context and (for `[look]`) the screenshot to that endpoint; they stream the answer.
Setup for codex: sign in once with `codex login`. The card's `chat` row (`addonsV2ClawdChat`, default on) shows
`ChatGPT via Codex · signed in` or `run codex login`.
While he waits he thinks (`think`); while the answer shows he talks (`talk`, pet mode `chat`).
Files: `scripts/clawd/{brain.js,codex.js,api.js,cli-runner.py}`, `payload/clawd/{ClawdChat,ClawdBrain}.qml`.

## Sleep and dreams (lot 7)

He falls asleep after the idle delay (or `> sleep`), the classic way or, one time in two, under a blanket
(`sleep_blanket_in` then the `sleep_blanket` loop). Pet modes `sleep`, `dream`, `nightmare`, `sleepwalk`; `pet.asleep` covers
all four. While he sleeps, a tick every 14–28 s (60 s in low motion) may bring one event (`js/dreams.mjs` `nextSleepEvent`):

| Event | Chance per tick | Rules | What you see |
| --- | --- | --- | --- |
| turn over | 0.2 | 60 s apart | `sleep_roll` / `sleep_blanket_roll`, then the loop mirrored |
| dream | 0.18 | after 40 s asleep, 4 min apart; ~1 in 4 is a nightmare | a cloud above his head for 30 s |
| sleep talk | 0.12 | 90 s apart | a mumbled line (`z five more minutes…`) where his thoughts go; not with Thoughts off |
| sleepwalk | 0.03 | after 3 min asleep, 15 min apart; on the floor, not in low motion | `sleep_walk`, 60–140 px, then asleep again |

Click the cloud to watch the dream: `ClawdDream.qml` plays the entry's scene under him over the whole screen
(click-through), wrapped in `shaders/dream.frag` (an iris opening from his head, pastel vignette and stars; for a
nightmare black-red flicker and grain). He keeps sleeping through a dream. A nightmare ends in a jumpscare: he jolts
awake (`sleep_jolt`) and wakes up sweating. Anything else (a click, a drag, work, a quota scene, the chat) ends the dream.

| Dream | Kind | Length | Scene |
| --- | --- | --- | --- |
| Rainbow surf | dream | 24 s | `ClawdDreamSurf.qml`: the surge's max helper (`clone` poses 38–49, `clone.frag` rainbow) surfs a wave of rainbow tokens, two flips, a shaka under the moon |
| Gemini | nightmare | 11.7 s | `ClawdNightmareGemini.qml`: her drawing (`sprites/gemini.png`) in the dark, made evil by `shaders/evil.frag` (glitch slices, RGB split, red eyes); jumpscare at 11 s |
| Ouroboros | nightmare | 13.5 s | `ClawdNightmareOuroboros.qml`: the serpent bites its own tail and turns; the ring nests inside itself at every scale, an endless zoom, then a figure eight `∞`; plain pixel squares, no shader of its own; jumpscare at 12.8 s |
| Blue screen | nightmare | 12.5 s | `ClawdNightmareCrash.qml` (`kind: bsod`) around `ClawdCrashScreen.qml`: the Windows 10 blue screen, but the % stops at 99 and the stop code is `CLAWD_DIED_IN_HIS_SLEEP`; flicker, jumpscare at 11.6 s |
| Kernel panic | nightmare | 12.5 s | the same file (`kind: panic`): a Linux console, oops, call trace, `Attempted to kill init!`, then the blue panic screen (Tux, a big QR code, "Please reboot your computer.") from 9.6 s; jumpscare at 11.6 s |

Every dream he has is recorded in `addonsV2ClawdDreams` (`{seen: {id: {n, first, last}}, log: [{id, kind, at}]}`, last 40):
the journal's `☾ dreams` tab shows the collection (`? ???` for the ones he never had, `xN` for the others) and the
recent ones with their time. Waking up after 15 min or more is groggy (`wake_groggy`: squint, yawn, stretch, wobble); a
blanket is thrown off first (`sleep_blanket_out`).

IPC: `play dream`, `play nightmare` (a random one), `play dream_surf`, `play nightmare_gemini`, `play nightmare_ouroboros`, `play nightmare_bsod`, `play nightmare_panic` (the cloud appears: click it),
`play blanket`, `play sleepwalk`; every new strip also plays by name. A new dream: an entry in `js/dreams.mjs` `DREAMS`
(`id`, `kind`, `title`, `glyph`, `scene`, `duration`, `jump` for a nightmare), a scene file taking `t`, `manifest`, `pixel`,
`ox`, `oy`, `floorY`, `seed`, `reduced`, one line in `ClawdDream.qml` `scenes`, and its name in `clawd.py` `TYPES`.
Storyboard: `animations/DREAMS.md` in the Clawd project.

## Settings card

| Row | Setting |
| --- | --- |
| Enable | `addonsV2Clawd`, default off |
| Scale | `addonsV2ClawdScale`, 2–8× pixels, default 4 |
| Walk speed | `addonsV2ClawdSpeed`: calm, normal, active |
| Sleep after | `addonsV2ClawdSleep`, 1–60 minutes, default 5 |
| Summon on this screen | Respawns him on the focused monitor (disabled while off) |
| Shortcut | Opens Keybinds; search `clawd` there to change it |
| Hooks | Connect / disconnect Claude Code, Codex, OpenCode and Hermes session hooks, and Claude's status relay (`stats`) |
| Thoughts | `addonsV2ClawdThoughts`: full (default), verbs, off |
| World | `addonsV2ClawdWorld` (`windows`: perching, peeking, exploring, window reactions) and `addonsV2ClawdFollow` (`follow` the cursor to other screens), both default on |
| Reacts | `addonsV2ClawdReactions`: all (default), quiet (urgent events, bubbles, moods), off (urgent only) |
| Chat | `addonsV2ClawdChat`, default on; the `chat` row shows the provider status; `provider` row: `codex` / `api` / `local` (`addonsV2ClawdChatProvider`, see Chat) |

Settings are shared with the separate Settings process through `settings.json`,
so the card works in the Settings app and in the integrated `Super+Shift+P` panel.

## Animations

123 strips (plus the 32 idle specials below). Besides the idle life (`idle`, `blink`, `look_*`, `walk`, `turn`, `sit`, `sleep`,
`drag`, `fall`, `land`, `spawn`), the idle fidgets below, petting (`petpet`, `petpetheart`, `startled`) and the working
loops above:

| Animation | fps / loop | When | Looks like |
| --- | --- | --- | --- |
| `think`, `think_2`, `think_3` | 6 / once | prompt submitted | ✻ thinking; chin tap, `?` then a cream spark; pondering left and right, then a light bulb |
| `happy`, `happy_2`, `happy_3` | 10 / once | turn finished | hop; jump and spin with arms up; a fist pump under a pink tick |
| `celebrate` | 10 / once | turn of 3 min or more finished | big jump, cream and pink confetti |
| `oops` | 10 / once | tool failed | shakes with a `!` beside his head |
| `alert` | 6 / loop | permission request | hops with a `!` |
| `compact` | 8 / once | compaction | squashed flat |
| `sweat` | 4 / loop | strained lead session, now and then while working | sweat drop, wipes his brow, pants |
| `coin` | 10 / once | session cost crosses a multiple of $5 | flips a cream coin and catches it |
| `sad` | 4 / once | turn failed | sinks a row, eyes down, a small tear |
| `wave` | 8 / once | session start | waves one arm |
| `perch` | 2 / loop | resting on a window top | seated on the edge, legs dangling below it, slow kicks |
| `perch_look` | 2 / once | perched, now and then; a window opens | same, eyes to one side |
| `hop` | 12 / once | hopping onto or off a window | crouch, stretch, tuck, landing squash (the jump itself is a tween) |
| `stumble` | 10 / once | workspace switched under him | trips forward, flails, rights himself |
| `teeter` | 6 / loop | at the end of a window top | tilts over the edge, arms windmilling |
| `peek` | 4 / loop | half hidden behind a window | eyes at the leading edge, blinks |
| `talk` | loop, 4 frames | chat answer on screen | rebounds with a stump gesture |
| `sleep_blanket_in` | 6 / once | falls asleep, blanket variant | notices the folded blanket, lifts it, yawns, lies down, pulls it over |
| `sleep_blanket` | 2 / loop | asleep under the blanket | breathing quilt, a foot out, floating z |
| `sleep_roll`, `sleep_blanket_roll` | 8 / once | turns over in his sleep | on his side, belly up, the other side / the quilt heaves into a mound; ends mirrored |
| `sleep_blanket_out` | 8 / once | wakes under the blanket | eyes open, sits up, the quilt slides off, kicked aside |
| `sleep_jolt` | 10 / once | a nightmare's jumpscare | leaps up wide-eyed with a `!` and sweat, the quilt flung |
| `wake_groggy` | 5 / once | wakes after 15 min or more | squints, yawns, arms up on tiptoe, wobbles, shakes it off |
| `sleep_walk` | 6 / loop | sleepwalking | eyes shut, one arm out ahead, z |

An animation may have a `grip` in `clawd.json`: the point that touches the support, in frame
pixels from the frame's top-left, unmirrored (`perch` and `perch_look`: the seat line
`[10.5, 12]`, so his legs hang below the window edge). Without one it is the bottom centre
(standing). Missing new animations fall back: `perch`/`perch_look` → `sit`, `hop` → `land`,
`stumble` → `oops`, `teeter` → `idle`, `peek` → `look_right`, the sleep strips → `sleep` / `idle` / `walk`.

### Idle fidgets

17 strips on his own canvas and palette (cream and pink props only), chosen by `js/fidgets.mjs` (`pick(pose, {mood, sleepy, prev})`, weighted,
never the same twice in a row). At normal speed about one idle pause in seven on the floor plays one (one in eight on a window top), and half
of his sits on a calm day use a seated loop. None in performance mode, none while an agent works. Every standing one starts and ends on `idle`'s first
frame, every perched one on `perch`'s (same `grip`), so nothing jumps.

| Fidget | fps | Pose | Looks like |
| --- | --- | --- | --- |
| `yawn` | 6 | standing | eyes shut, stretches up, mouth wide, arms out, sinks back |
| `stretch` | 6 | standing | arms above his head, leans left then right, lets go with a happy face |
| `scratch` | 8 | standing | one arm up, the hand tapping his head, one eye shut |
| `sneeze` | 8 | standing | two breaths in, then squashed flat with a spray of drops |
| `look_around` | 4 | standing | left, right, up, a blink |
| `tap` | 8 | standing | bored eyes, arms low, a foot tapping the floor |
| `shake` | 12 | standing | shakes himself dry, drops flying both ways |
| `doze` | 4 | standing | nods off, sinks, a `z`, jolts awake with a `!`, shakes his head |
| `bubble` | 6 | standing | cross-eyed, blows a pink bubble of gum that grows and pops on his face |
| `butterfly` | 6 | standing | a pink butterfly flies in, lands on his head (he smiles), flies off the other way |
| `yoyo` | 8 | standing | a cream yo-yo down its string and back, three times, sleeping at the bottom |
| `whistle` | 6 | standing | happy eyes, bobs, pink notes floating up on both sides |
| `skip` | 8 | standing | five jumps over a cream skipping rope |
| `sit_sway` | 4 / loop | seated | rocks from side to side, humming (pink notes) |
| `sit_gaze` | 2 / loop | seated | looks up at a star twinkling here, then there |
| `perch_kick` | 8 | perched | happy, swings his legs one side then the other |
| `perch_yawn` | 6 | perched | the yawn, seated on the ledge |

Moods narrow the choice: `drowsy` and `exhausted` yawn, nod off, stretch or scratch; `rain` shakes, sneezes, looks around or taps;
`snow` mostly sneezes. Once 60 % of the idle delay has passed with nothing touching him, he is sleepy: mostly yawns and nods, no more games.
A new fidget: its frames (first and last = the resting pose), a line in `sprites.py` `ANIMS`, its name and weight in `js/fidgets.mjs`.
`quickshell ipc call clawd play yawn` (any name above) plays one at once.

### Idle specials

32 more strips, reproduced from reference videos, play as rare idle "acts" (`js/acts.mjs`, mode `act`): only on
the floor, calm state (no mood, no agent working, not low-motion), at most one per 45 s, never the same twice in a row.
Each is a sequence of strips; a loop strip is held for a random time, a one-shot plays to its end.

| Act | Strips |
| --- | --- |
| `book` | `book_idle` (glasses, book), `book_blink` between holds |
| `joy` | `content_idle`, `content_bounce` every few seconds |
| `bike`, `carry`, `broom` | `bike_ride`, `carry_walk`, `broom_fly` while he crosses the floor (mirrored going left) |
| `row` | `boat_idle`, `boat_row_in`, `boat_row`, `boat_row_out` |
| `fish` | `boat_fish_in`, `boat_fish_wait`, `boat_fish_catch`, `boat_fish_out`, `boat_bino`, `boat_row_brief` |
| `campfire` | `camp_stand`, `camp_fire_build`, `camp_fire_burn`, `camp_fire_die` |
| `binoc`, `photo`, `nap` | `camp_binoc_*` (5), `camp_camera_*` (3), `camp_lie_down`, `camp_lie_idle`, `camp_stand_up` |

These strips have their own canvas: the manifest entry carries `w`/`h`, the pet's box follows the current strip, and the
`grip` is `[anchor x, feet row]` (boat and broom: the bottom of the canvas) so the feet stay put from one strip to the next.
Their source files keep a header (`fps`, `loop`, `anchor X Y`, `pal C RRGGBB`) and their own palette. `quickshell ipc call clawd play book`
(any act name above, or any single strip name) starts one at once.

## Sprites

Frames are ASCII art in `scripts/clawd/frames/<animation>.txt`. After editing:

```sh
python3 scripts/clawd/sprites.py          # writes payload/clawd/sprites/*.png + clawd.json
python3 scripts/clawd/sprites.py --check  # exits 1 if committed outputs are stale
```

Output is deterministic. Palette: transparent, body `#D97757`, eyes `#000000`,
cream `#F0EEE6` for small props (sleep "z", ✻, keyboard, "!", paper, coin, confetti, sweat drop),
pink `#EC5B86` for petpet hearts, pencils, ticks and confetti. The blanket strips add blanket blue `#6F8FD8`, quilting
`#4A63B0`, pink trim `#F4B6C8` and sweat `#8FD3FF`. Frames face right; left is mirrored
at runtime. `hand.png` (the petpet hand, 7 frames frame-locked to `petpet*`) is cut out of
`scripts/clawd/hand-pet.gif`'s black background by the same script; its size is in `clawd.json` → `hand`.
`gemini.png` (the nightmare's drawing) is copied as is from `scripts/clawd/gemini.png`; its size is in `clawd.json` → `gemini`.

## Install and remove

`python3 install.py` installs `payload/clawd/` to `quickshell/clawd/`, registers
the types in the root `qmldir`, hosts `AddonClawd` in `Shell.qml` and adds the
`Super+Shift+L` bind to `keybinds.lua`. `python3 install.py --without-clawd`
removes only Clawd's files, blocks, bind, hooks (all four agents) and status line relay, with dated backups;
other addons are untouched.

## Validation

1. `python3 scripts/clawd/sprites.py --check` and
   `python3 -m unittest discover -s tests -v`.
2. Install, enable the card switch: Clawd spawns at the bottom of the focused
   monitor. `Super+Shift+L` twice hides and shows him.
3. Drag him to another monitor (including ones with negative offsets) and
   release: he falls to that screen's floor. The rest of the desktop stays
   click-through.
4. Right-click: menu opens; Escape closes it; `> settings` opens Settings.
5. Change scale and speed in the card: the running pet follows immediately.
   Summon from Settings on another monitor.
6. Turn Clawd off: `qs-addon-clawd` layers disappear (`hyprctl layers`).
7. Connect Claude in the card, start a new session, send a prompt: think → work →
   happy + bubble, with `✻ <Verb>… 3s` above his head while he works. Same for Codex
   (trust the hooks first). A permission prompt makes him hop with `⚠ permission`.
8. Connect `stats`, start a new Claude session: the thought line cycles model, context, cost
   and limits; the journal shows the context %. Disconnect: a previous status line comes back.
9. Open a floating window, drop Clawd above it: he perches on it; move the window, he rides it;
   close it: he falls and says `oops`. Move the cursor to the other screen for a few seconds:
   he walks over. `ipc call clawd state` shows `support` and `world`.

### Quota limits and resets

A 5-hour limit reaching 100% plays `limit5`: the nuke or a crash screen, 50/50 (the crash is a Windows blue screen or a Linux kernel panic, also 50/50: `ClawdCrash.qml` around `ClawdCrashScreen.qml`, on every screen, then his corpse falls like after the nuke; `play bsod`, `play panic`, `play crash` preview them);  a 7-day limit plays the singularity or the surge, at random (`limit7`). Each provider and window is tracked independently. A first reading at 100% establishes the current state without an explosion; a later observed transition from below 100% triggers it once per window. Stale lower readings cannot rearm the same window. At a known reset deadline, or when a fresh snapshot reports the next window, Clawd plays `recharge` for the 5-hour window; the 7-day reset is silent. Scenes wait their turn and revive him first if needed. Quota state is saved across shell restarts. The first reading after a restart establishes the current state, so an exhaustion missed while the shell was stopped is not replayed.

Claude needs the card's `stats` connection and a running session; Codex is polled every 30 s with `scripts/clawd/codex_limits.py`, which reads only the used % and reset time of the latest rate-limit snapshot in recent local session logs. If the provider has not supplied a recent snapshot, detection is best-effort.

Codex resets that never reach a deadline (announced resets, banked resets spent early) are covered two ways. Every 60 s `curl` reads [codex-resets.com](https://codex-resets.com) (`/api/v1/status`, free, no key): a new regular announcement, or a `scheduled_reset` reaching its `scheduled_for` (ignored if more than an hour old), plays `recharge`. A `banked` announcement (`Banked 1/2`) only adds to the bank and stays silent; the first poll after install only establishes the state. Spending a banked reset is detected locally: a Codex window whose used % falls 10 points or more below its recorded peak plays `recharge`. One reset plays one scene: sources within 30 min of each other are merged.

About 37 s, on Clawd's screen, above everything (layer `qs-addon-clawd-blast`, Overlay); other screens darken,
flash and come back with it. He freezes, then the screen does (a `ScreencopyView` capture taken while he is
hidden); he glides to the middle, sucks the light out of the desktop while he heats up and trembles; silence, his
eyes cross; antimatter annihilation (flash, negative impact frames, plasma shell, shock and equatorial rings, gamma
rays, particle/antiparticle spiral tracks, his pixels flung out); a black hole swallows the desktop and the debris,
collapses into a star that blinks out; 5 s of black; an energy pulse brings the live desktop back and his corpse falls in.
The frozen screen takes clicks; Escape skips to the pulse. Apps keep running underneath.

Storyboard: `animations/SINGULARITY.md` in the Clawd project. Drawn frame by frame: `explode` (12 poses: hovering,
six charging stages, pure light, crossed eyes, three cracking open) and `antimatter` (12 frames, 49×49, the
annihilation core), both from `scripts/clawd/frames`. The rest is `ClawdBlast.qml` (a pure function of time) and
three shaders in `payload/clawd/shaders`: `desk.frag` (freeze tear, light drain, lit negative), `fx.frag` (light
threads, halo, the annihilation, on his pixel grid) and `lens.frag` (shake, chromatic split, impact negatives,
black hole lensing and infall, accretion disc, star, blackout, return pulse). After editing a `.frag`, run
`scripts/clawd/shaders.py` (`qsb` from Qt Shader Tools); the installer refuses a package that does not match its
source and installs each under its hash (Qt caches shaders by URL across reloads).

The nuke, about 20 s, same window and capture: a red alarm pulses in from the edges while he panics, running back and
forth at full tilt (frozen in terror once), the screen trembling; he stops near the middle, crouches and leaps; time
dilates (grey, cold, a slow camera push toward him, two heartbeats) while he hangs in the air; his eyes cross, a white
glint swells in his chest; four black-and-white impact frames; then the flash and a nuclear mushroom grows from the
floor under him, drawn frame by frame (`mushroom`, 28 frames of 96×96: fireball, condensation ring, rolling cap
cooling from white to dark red, embers, dissipation), glowing, with embers flung out, heat shimmer, a shock front,
the shake and chromatic split of `lens.frag`, the desktop lit and scorched by it; ash drifts down, everything fades
over the live desktop and his corpse falls where it went off. Storyboard: `animations/NUKE.md` in the Clawd project.
`ClawdNuke.qml` + `shaders/nuke.frag`; poses `nuke` (13).

### The surge (7-day limit, superpowered)

About 41 s, drawn by his overlay over the live desktop (click-through, `ClawdSurge.qml` + `shaders/{surge,bulge,clone}.frag`).
He jumps with a `!`, stares at the top-left corner where light bleeds along the edges and the screen bulges inwards
(`bulge.frag` on a capture taken at the start) until a magic orb tears through and hits him: black-and-white impact
frames, an explosion of light, violet smoke and glowing wisps. Poker-faced and sooty, he inhales all of it, flashes,
pulses with lightning and keeps an aura. He dashes right: the screen darkens, the camera zooms on his glowing wink, then
out; he leaves the screen and the overlay switches his screen to an empty workspace (`workspace emptynm`), he comes back
in twice as big, skids to the middle and strikes the floor, which lights up in colour and climbs the sides of the screen.
Six helpers arrive, one per effort level, each its own way (`clone` strip recoloured by `clone.frag`): low #FFC107 falls
from the sky, medium #4EBA65 rises from the floor, high #B1B9F9 materialises in a pillar (left side); xhigh #AF87FF
slides in with a white glint now and then, max (Claude Code's light colours, flowing) steps out of a rainbow portal,
ultra #9BF6FF comes with a lightning strike and crackles (right side). One by one they start working (typing, an ASCII
spinner line with a spinner verb) and each sends a vertical beam across the screen, stronger with the effort (sparks,
rings, white sweeps, rainbow, lightning arcs and shake). Then he rises, light at the end of his arms, their streams
arc into him and an ASCII bar recharges the week (`[#####.....]  48% left` -> `RESTORED`), a burst, the helpers vanish,
he lands, a blackout hides the way back to the workspace he left, and he stays in the middle of his screen.
Storyboard: `animations/SURGE.md` in the Clawd project. Poses `surge` (22); helpers `clone` (38 poses, white body; 38–49 are
the dream surfer's).

### Dead, and revived

After either scene Clawd is dead: grey, on his back with his legs in the air, crosses for eyes, smoke rising from him
(`smoke`, 15×16, 12 frames). He no longer reacts to anything (agents, petting, dragging, the journal, the windows);
his thought line and `[n]` are hidden, bubbles still show. Death is kept in Config (`addonsV2ClawdDead`, when he
died) so a reload finds his corpse. He comes back with `> revive` in his menu, when a new Claude Code / Codex / OpenCode / Hermes session
starts (`SessionStart`, not a compaction), or when the shell starts (or Clawd is turned on) 3 hours or more after he
died. The revival (about 9 s, `ClawdRevive.qml` + `shaders/revive.frag`, drawn by his overlay, click-through): the
screen dims, a spotlight comes down on him, holy powder falls on the corpse, which floats up glowing and turns white,
bursts back into his colours, drops down and goes ta-da (`tada`) with rays of light behind him.
