# Capri, native desktop companion

Capri lives in Settings → Addons → General. Click the illustrated card or its
switch to enable her; `Super+Shift+K` toggles the same setting, and
`Ctrl+Alt+C` puts her away in her biochip (bottom left) or brings her back, as
upstream. OFF destroys the
pet windows, engine, timers, system watcher and Node helper. The settings card
remains available as a still image. Node is required for hooks and AI.

## Controls

Open **Capri options** below the card. These are the same persisted options used
by Capri’s own right-click menu, shared between standalone Settings and the shell.

| Control | Behaviour |
| --- | --- |
| Size | Small 0.45, medium 0.6, large 0.8; applies immediately |
| Screen | Move the running pet to an available display |
| Follow across screens | Join the pointer on another display |
| Wander / window effects | Allow walking, perching and possession |
| Jealousy / PC reactions | Independently control assistant and system reactions |
| Resting place | Corner or taskbar |
| Animations | Automatic follows shell performance mode, Full overrides it for the pet, Reduced uses still/fade alternatives |
| Language | Shell language, English, French, Spanish, Portuguese or Russian; unsupported shell languages fall back to English |
| Watched assistant | Codex, Claude Code, Antigravity or none; separate from the AI chat provider |
| AI provider and model | Opens the existing native provider editor beside Capri |
| Make her yours | Opens the existing name, persona, remembered facts and custom-line editor (her menu's **Make her yours…** runs the upstream guided version) |
| Try Capri | Demo, teleport, talk, reminders, mission report, stow and show |

The settings copy is available in English and French, with English fallback.
Capri’s dialogue retains all five upstream catalogues. Rows participate in native
Settings search; searching can reveal the collapsed options group. Search `capri`
in the Keybinds editor to customize the shortcut. The installer preserves edits.
The master switch supports Tab, Space, Return and the accessible checkbox action.

Live actions need Capri enabled. The AI and personal controls deliberately open
the shared native editor; provider configuration is owned by the running helper,
not by a second backend in Settings. A fullscreen app can cover the Top-layer
pet/editor. Leave fullscreen or select another screen to see her. DND suppresses
unsolicited attention without stopping hook bookkeeping.

## Agent hooks: explicit opt-in

1. Open Capri options → Connect agent hooks. The initial check only reads status.
2. Choose **Connect** for Claude Code and/or Codex. The existing installers add
   only Capri’s hook commands and keep a dated `*.capri-backup-*` when replacing
   an existing configuration. The actual configuration path is shown in the row;
   `CLAUDE_CONFIG_DIR` and `CODEX_HOME` overrides are respected.
3. Start a new Claude Code session, or restart Codex and review/trust its hooks
   when prompted. Choose the watched assistant separately above.
4. **Disconnect** removes only Capri hooks, preserving other agent settings and
   commands. **Check again** rereads both statuses after external edits.

Neither installation, opening Settings nor enabling Capri installs agent hooks.
Disabling/removing the addon does not modify agent configurations; disconnect
hooks first if desired. Hooks fail silently when Capri’s bridge is offline.
The bridge listens only on `127.0.0.1:47823` and rejects browser-origin events.
Antigravity is connected the same way (upstream installer, `~/.gemini/config/hooks.json`,
`AGY_CONFIG_DIR` respected; start a new conversation afterwards). Her right-click
menu also has **Install/Remove … hooks** for the watched assistant, and her guide's
**Plug me in** button: both are explicit clicks, like the Settings rows.

## Her menu, guide and setup

Right-click her for the upstream menu: teleport, satellite, demo, **How does it
work?**, talk, **Look at my screen**, AI model (set it up with her, service/model,
key or address, Ollama sign-in, forget), make her yours, report, reminders, stow,
size, screen, **Sound** (mute, custom sounds folder), wander/possess/jealousy/PC,
**Look at my screen now and then**, resting place, animations, watch, hooks,
language, quit.

- **How does it work?** She points at things with her arm: **Where's Claude?**
  (the window you typed your last prompt in, from Hyprland's focus history),
  **Claude's folder** (opens `~/.claude`, `~/.codex` or `~/.gemini/config` in the
  file manager with its hook file selected, then points at the window),
  **Where's my icon?** (no tray icon on this shell: she points at her chip's
  corner and gives the shortcuts), **Plug me in**, talk, make her yours.
  Labels follow the watched assistant.
- **Her welcome**: after her entrance, the first time or while the watched
  assistant has no hooks, she offers to plug in; otherwise "Capri online"
  (with your name if she knows it). Not in DND. In automatic animation mode with
  shell performance on, she first asks whether to move anyway.
- **Set it up with her** (or when her chat can't answer yet): on this PC with
  Ollama (woken with `ollama serve` if needed, a model fetched with a progress
  bar: gemma3:4b or llama3.2, bigger first on a roomy PC; Ollama's free cloud
  models when signed in), online with no account (Pollinations), or a pasted key
  (hidden as you type, checked, kept in the helper's 0600 state). Without
  Ollama installed she opens its download page: there is no unprivileged package
  manager to drive here, as upstream off Windows. **Free with Ollama** opens a
  terminal (`$TERMINAL`, xdg-terminal-exec, kitty, foot…) on
  `ollama launch claude|codex`, after her hooks.
- DND holds what she says on her own, never what you open yourself (chat,
  guide, a look).

## Looking at your screen

Her menu › **Look at my screen**, or "look at my screen"/"regarde mon écran" in
her chat. The first time she says where the picture goes (your AI on this PC, or
the online service) and asks. `grim` takes the screen she's on, 1280 px wide at
most, as JPEG kept in the helper's memory for one use (two minutes at most),
never on disk; with ChatGPT the CLI gets it with `codex exec -i` from the private
per-call temporary directory, removed afterwards. Her eyes go to the window in
front while a scanline sweeps it. **Now and then** (off until ticked) looks every
8–15 minutes when you're there and on another window. It needs a model that can
see (gemma3, ChatGPT, Gemini, OpenAI); Claude Code and llama3.2 cannot, and she
says so and stops looking on her own.

## Sounds

The 18 upstream cues (teleport, done, alert, error, hello, voice blips, tick,
star, land, rise, bolt, charge, possess, throw, crash, remind, jealous) are the
upstream Web Audio synthesis rendered to WAV by
`scripts/build-capri-sounds.py` (deterministic; variants for the random parts,
blips per note and mood, throw/crash per power) and played with QtMultimedia.
Files named after a cue (`done.mp3`, `alert.wav`, `.ogg`, `.m4a`) in
`~/.config/serpantinum/capri/sounds/` replace it (menu › Sound › open the folder;
read when she starts). Menu › Sound › Mute, or `addonsV2CapriMuted`.

## AI providers and data

**Configure AI** opens the provider/model/address/password-key form. Saving checks
the provider and restores the previous configuration and model list on failure.
Providers: Ollama, LM Studio, llama.cpp/vLLM, Pollinations, OpenRouter, OpenAI,
Groq, Gemini, DeepSeek, Mistral, compatible HTTP, Claude Code and ChatGPT/Codex.
API-key services require their own credentials. An online provider sends the
conversation to that service; the chat displays a local/online disclosure.

For a ChatGPT subscription, authenticate in a terminal with `codex login`, then
select **ChatGPT** in the native editor and save. Capri checks that the CLI is
logged in using ChatGPT. This uses the existing Codex authentication store;
there is no subscription credential form. Codex calls use an ephemeral empty
working directory, read-only sandbox, ignored user configuration, disabled
hooks/memories/plugins/apps and execution/browser tools. CLI supervision kills
the process group on cancellation or abrupt helper exit. Claude Code retains
its existing separate agent configuration and confirmation behaviour.

Provider keys and chat state live under
`~/.local/state/serpantinum/capri/{chat,memory}.json` (or `XDG_STATE_HOME`), with
0700 directory / 0600 files. Public configuration exposes key IDs only.
**Forget our conversations** clears chat history and the Claude session; personal
facts remain editable separately. Behaviour and personality settings use the
shell’s Config store. Internal state uses `addonsV2CapriState.*`; never nest
settings under the boolean `addonsV2Capri`.

## Design and ownership

| Surface | Contract |
| --- | --- |
| Card | Halloween’s 180 px / 18 px rounded house glass frame; compact 210 px height, shell typography and surface tokens |
| Illustration | Supplied Capri head; bounded red/violet channel offsets, mane shards and scanline; no desktop engine in Settings |
| Switch | One 300/240 ms ignition driver; state always derives from Config |
| Preview lifetime | Enabled, current visible tab/window, nonzero size, inside scroll viewport, no performance/reduced motion |
| Performance / OFF | Still head; preview Loader destroyed, no preview animation clock |
| Pet panels | Existing chamfered plates, hard violet offsets, Chakra Petch and fixed neon accents |
| Desktop | One persistent engine travelling between Top-layer monitor surfaces; input mask covers only pet and open UI |

The preview has no pointer handlers or focus. Its clock is local to the preview;
it never pumps/resets the desktop engine’s shared JS timer. The card always
respects shell performance mode even if the pet’s motion option is Full.
Hook helpers run only for an explicit status/connect/disconnect request.
Settings invokes shell actions through IPC and reports delivery failures.

## Install, update and remove

```sh
python3 install.py
serpantinum reload
```

Reinstall after shell updates. Patches use unique anchors, their own
`serpantinum-capri-v2` marker and fail closed on upstream drift. Resources are
installed directly from this checkout into the shell’s `capri/` directory;
backend scripts use the deployed addons scripts directory. All QML types are
registered in the root qmldir. The sprite shader has a verified content hash.

```sh
python3 install.py --without-capri
serpantinum reload
```

Removal backs up/deletes Capri resources and removes its host, options, type
registrations and shortcut; dormant Config values are kept. Halloween and other
addons have independent markers and survive. `--without-halloween` keeps Capri.

## Validation

Run `python3 -m unittest discover -s tests -v`. The settings fixture uses actual
installed SettingsRow/SettingsGroup/Toggle/ClickButton/glass components, isolated
Config, temporary agent homes and a mock shell IPC receiver. It exercises the
master switch, preview lifecycle, languages, compact/RTL layout, selection,
explicit hook install/uninstall and Settings-to-shell action delivery. Other
Capri fixtures cover the actual engine, Brain, reminders, streaming chat and
provider configuration; patch tests cover idempotence and independent removal.

### Lot 6 results, 29 October 2026

- Full suite: **86 passed**, 141.390 s (`/tmp/capri-lot6-final.log`), with the
  final settings interaction fixture additionally rechecked after its last edits.
- `qmllint` reports no diagnostics for the four new/rewritten Settings components;
  `git diff --check` passes. GPU captures inspect ON/OFF, French compact layout,
  RTL and the reachable options footer (`/tmp/capri-lot6-ui/`). The software
  backend does not render the card's MultiEffect mask correctly; it is used for
  lifecycle/interaction assertions, not as visual evidence for the card.
- Actual installed components were also loaded with the real Config in a native
  validation window. QtTest delivered mouse clicks directly to the switch,
  both offscreen and in Wayland: the live shell reached OFF (0 instances/layers,
  helper absent, port 47823 closed) then ON (2 surfaces/helper, HTTP health 200).
  This validates QML event delivery and cross-process state; it does not claim
  physical pointer delivery from the desktop or keyboard typing into chat.
- The Settings-to-shell provider action returned success in Wayland and the
  provider/personal editors rendered on HDMI-A-1. No AI settings or credentials
  were saved. Captures: `/tmp/capri-lot6-live/`, including `linked-provider.png`
  and `personal-editor.png`. The ordinary Settings → Addons page also rendered.
- Final deployment matches source, including the installer-rewritten sprite
  path. Reload reports Configuration Loaded, `hyprctl configerrors` is empty,
  and a second install reports **0 shell files changed**.
- Real Claude/Codex hook files retain their pre-validation timestamps. Only
  temporary agent homes were connected/disconnected. Temporary native windows,
  input helper and compositor rule were removed/disabled; size/follow overrides
  were removed, DND remained true, Capri remained ON on DP-1, and the game was
  restored to its original fullscreen state. Real mission/bond data was retained.

Physical USB/battery/network/monitor events, every remote provider,
physical keyboard/chat focus, report clipboard and desktop click-through retain
prior-lot limits.

### README parity, 30 October 2026

- Added: guide (topics, pointing, welcome, online line, animations question),
  guided chat setup and Free with Ollama, guided Make her yours, screen looks
  (manual, in chat, automatic), sounds and custom sounds, `Ctrl+Alt+C`,
  Antigravity hooks, the upstream menu entries.
- `tests/capri/guide.mjs` drives the real Panel through every guide topic, DND,
  setup (Ollama/model/key/site/free), Make her yours and looks;
  `tests/capri/setup.cjs` checks model download progress against a fake Ollama,
  the terminal launch, the picture reaching `codex -i` once and its file removed,
  Antigravity hooks in a temporary home and custom sound discovery. QML fixtures
  now use temporary agent homes and start muted.
- Live: guide menu and icon topic, Where's Codex pointing at a real window
  (demo-flagged session, not counted), setup, Make her yours (all skipped),
  look consent (declined: no picture sent), `Ctrl+Alt+C` bind registered and
  stow/unstow, audio stream active during a cue, menu rendered.
- Not exercised live: a real look answer (sending the screen to ChatGPT was not
  done without your go-ahead), a model download, Free with Ollama's terminal,
  Antigravity itself, custom sound files, physically pressing `Ctrl+Alt+C`.
