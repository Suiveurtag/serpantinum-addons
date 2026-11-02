# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Clawd chat provider: choose Codex (default), an OpenAI-compatible API, or a local server (Ollama, llama.cpp, LM Studio) from the Clawd card.
- Clawd session watch: connect OpenCode and Hermes alongside Claude Code and Codex.

### Removed
- Wallpaper Engine scene backgrounds (scenes, `we-layerd` bridge, installer, docs and tests). The feature will return later.

## [2.0.1] - 2026-11-01

### Added
- AI Tokens: opt-in sources for opencode (read from its session database) and
  llama.cpp (`/metrics`, start `llama-server` with `--metrics`), plus
  today / week / month windows for Codex and Claude.
- AI Tokens: new logos for Claude Code, Codex, opencode and llama.cpp, and a token icon.
- Settings → Bar → Modules → Actions: "Show update icon" toggle.
- Addon badge on the wallpaper accents row, as in Claude mode.

### Changed
- AI Tokens: the live dot pulses for Hermes and opencode (and llama.cpp) activity too, not only for Codex and Claude Code.
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
