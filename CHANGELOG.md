# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.1.3] - 2026-11-13

### Changed
- The legacy calendar and its setting have been removed; the native calendar is used.
- The About page links to the Suiveurtag Serpantinum fork.

### Fixed
- Compatibility with Serpantinum 2.5: calendar sizing and seasonal effects, bar outlines, and the AI Tokens settings card.
- AI Tokens number grouping and wallpaper color generation.
- Clawd idle animation sprites and timing.
- A tool installed after login (Codex CLI through `npm install -g`, cargo, bun, nvm...) is now found without rebooting: the manager, `install.py` and the Clawd/Capri Codex chat add the usual per-user bin directories to PATH. Before, the addons reported "Codex CLI not found" until the next login.
- The installer no longer aborts when a system dependency is missing or fails to install (declined sudo, AUR-only or unpackaged tool, no supported package manager): it warns which feature stays off and installs the addons anyway. Node.js is only required when Clawd or Capri is selected, and the addons are chosen before the packages are checked.
- Beamer's package install no longer waits on an invisible sudo password prompt while the manager captures the output; it fails fast with the command to run yourself.

### Added
- Clawd idle fidgets (17 animations), played now and then while he rests: `yawn`, `stretch`, `scratch`, `sneeze`, `look_around`, `tap`, `shake`, `doze`, `bubble` (gum), `butterfly`, `yoyo`, `whistle`, `skip` (rope); seated `sit_sway` and `sit_gaze`; on a window top `perch_kick` and `perch_yawn`. They follow his mood (tired: yawns and nods; rain or snow: sneezes and shakes), favour yawns when his nap is near, never repeat twice in a row and stay off in performance mode.
- Clawd working loops: one more per tool family (`work_6` stacking crates, `edit_4` easel, `read_4` newspaper, `bash_4` rocket launch, `search_4` rummaging through a crate, `web_4` cloud download, `task_4` a mini Clawd on his head, `todo_4` sorting bars), plus `think_3` (light bulb) and `happy_3` (fist pump under a tick).

## [2.1.2] - 2026-11-02

### Added
- Clawd nightmares: "Ouroboros" (a serpent biting its tail, endless nested rings), "Blue screen" (Windows 10) and "Kernel panic" (Linux console, then the blue panic screen with Tux and a QR code).
- The 5-hour limit plays the nuke or a crash screen (a blue screen or a kernel panic), 50/50; `play bsod`, `play panic`, `play crash` and `play limit5` preview them.
- Clawd working loops: a third variant (and more) per tool family (`work_3`…`work_5`, `edit_3`, `read_3`, `bash_3`, `search_3`, `web_3`, `task_3`, `todo_3`), picked at random and never the one already playing.
- AI Tokens: a "Codex account total" setting (Addons → Tokens): the account's lifetime total across devices, or only the tokens run on this PC.

### Changed
- Custom cursor settings page reworked.
- The update error for a modified source checkout now suggests `git stash push -u` (keeps your changes) before the destructive reset.

## [2.1.1] - 2026-11-02

### Fixed
- Wallpaper colours: apply vibrant and vivid palette surfaces correctly.
- Matugen palette generation and the wallpaper accent preview.

## [2.1.0] - 2026-11-02

### Added
- Animated bar outlines (Addons → General, off by default): the bar button whose panel is open gets the v1 flowing outline; classic / button / minimal styles outline the button, other styles the whole module; grouped modules (clock + weather) share one outline around their group; the settings and launcher buttons are outlined while open; the AI tokens bar item is outlined on hover.
- AI Tokens card in Settings → Bar → Modules: a live preview and a toggle per provider (Codex, Claude, OpenCode, llama.cpp) to choose which ones the bar module shows on hover (Codex and Claude by default, at least one stays on).
- AI Tokens: the button that adds the widget in the widgets editor wears the flowing outline until you hover or use it (once per install).
- AI Tokens collector reacts to inotify instead of a 3 s poll: Codex, Claude Code, opencode and Hermes changes reach the widget in about 50 ms; llama.cpp is polled every second.
- Beamer (KVM) integration for Hyprland: launcher, clipboard bridge, click-through crossing effects on two screens; optional (`--without-beamer`).
- Clawd chat provider: choose Codex (default), an OpenAI-compatible API, or a local server (Ollama, llama.cpp, LM Studio) from the Clawd card.
- Clawd session watch: connect OpenCode and Hermes alongside Claude Code and Codex.

### Changed
- AI Tokens: the live dot pulses for Hermes and opencode (and llama.cpp) activity too, not only for Codex and Claude Code.
- The installer now installs missing prerequisites itself: `git`, `curl` and Python 3 (bootstrap script), then the required system packages with `pacman`, `dnf` or `xbps-install` (no confirmation question from the addons; `sudo` and the package manager still prompt). `--yes` no longer refuses to install them.
- The installer runs Serpantinum's official installer when Serpantinum is not installed, instead of stopping.
- Beamer launcher: the installer installs the addon's build tools but no longer fetches the Beamer Flatpak; without it the integration is skipped with a note.
- Addons tab: the Beamer row shows the Beamer logo and no longer lists the removed emergency shortcut (settings rows can now draw an addon's SVG as their icon); new icons for the weather-location and next-screen rows.

### Fixed
- Installer: a customised or commented `Super+Shift+S` screenshot line in the keybinds file no longer stops the install; the colour picker and window switching shortcuts are appended at the end of the file instead.
- AI Tokens digits: a new value arriving while a digit is still rolling no longer leaves the wheel parked between two digits.
- AI Tokens: an opencode session listed in both tables of its database keeps its larger total instead of the first one read.
- Beamer launcher: a stopped input bridge is reported as such, not as "clipboard bridge did not start".

### Removed
- Wallpaper Engine scene backgrounds (scenes, `we-layerd` bridge, installer, docs and tests). The feature will return later.
- Beamer: the `Super+Shift+F12` emergency release bind and its remote rescue shortcut (the block written by an earlier install is removed on the next install); the crossing relies on Beamer's own Escape hold instead.

## [2.0.1] - 2026-11-01

### Added
- AI Tokens: opt-in sources for opencode (read from its session database) and
  llama.cpp (`/metrics`, start `llama-server` with `--metrics`), plus
  today / week / month windows for Codex and Claude.
- AI Tokens: new logos for Claude Code, Codex, opencode and llama.cpp, and a token icon.
- Settings → Bar → Modules → Actions: "Show update icon" toggle.
- Addon badge on the wallpaper accents row, as in Claude mode.

### Changed
- Settings sidebar: addons now sit in their own separate group.
- Clawd journal: a click on a session row follows it, a double click raises its terminal.
- Capri and Clawd card wording updated ("Capricorn", "cute pal").
- Idle option "Codex mode" renamed to "Claude mode" (also in files patched by earlier releases).
- All project URLs now point to the renamed repository.
- README: Discord link, "Seasonal effects" naming, Appearance section removed.

### Fixed
- Shell freeze when switching to the Vibrant palette (circular visibility binding in the palette editor).
- Token digits: alpha is clamped, which stops the `setAlphaF` warnings flooding the log.
- Bar and widget module labels staying as raw translation keys when registered before translations loaded.
- Installer: the latest-release lookup now follows redirects (the repository was renamed).

## [2.0.0] - 2026-11-01

First public release.

### Added
- Clawd: pixel mascot for Claude Code, with hooks, status relay and chat.
- Capri: desktop companion with local (Ollama) and ChatGPT providers.
- Halloween: seasonal effects and night switch.
- AI Tokens: token counter widget with a background collector service.
- Wallpaper Engine backgrounds (scenes) with a dedicated user service.
- Mouse, cursors and trackpad: acceleration, custom cursors, spotlight, trackpad guard.
- Keybinds and keyboard layout settings.
- Monitors settings.
- Desktop tools: zoom, window outline, colour picker, frozen capture.
- Theme and colours generation.
- Appearance: Liquid Glass and classic blur.
- Network (Mullvad DNS) and idle settings.
- Startup applications management.
- Release tooling: one-line installer, in-shell update checks, uninstall,
  doctor and Serpantinum compatibility check (`compat.json`).
