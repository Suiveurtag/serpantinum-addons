# Christmas

A seasonal layer that dresses the shell for Christmas with light, ribbon and holly. It never changes the wallpaper or
the palette, and it never makes anything fall from the sky (Snow Hush does that). Settings → Addons → Banners holds
the switch, the light styles and one switch per decorated area.

## Design

| Role | Value |
| --- | --- |
| Gold (selection, piping, sparks) | `#f2c46d`, pale `#ffe3a6` |
| Ribbon | cranberry `#c8344a`, shade `#7d1828` |
| Holly | leaf `#2f7c50`, berry `#d42a3e` |
| Wire | `#16261c` |
| Title | Berkshire Swash (SIL OFL 1.1, `payload/christmas/BerkshireSwash-OFL.txt`) |
| Artwork | Viggo Johansen, *Glade jul* (1891), oil on canvas, Hirschsprung Collection; public domain, from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Viggo_Johansen_-_Glade_jul_-_1891.jpg). Cropped around the tree. |

Light styles (bulb colours in `shaders/lights.frag` and `Christmas.bulbs`): Classic red/gold/green/blue, Warm white,
Candy cane red/white, Nordic ice/silver/pale gold.

### The banner

- A string of lights runs across the top, dark glass while off. Pressing the bauble lights it from above the bauble.
- The bauble is the switch (keyboard: Tab, Space/Enter). It swings like a pendulum on every press; lit, it turns
  cranberry, glows and mirrors four twinkling bulbs.
- The last door of an Advent calendar (24, with holly) swings open in perspective on the painting once the first
  bulbs are lit, and shuts when the lights go out. While on, the painting's candles flicker slightly on the lights'
  clock.
- Two panels unfold under the hero: **Lights** (four tiles that preview their bulbs; the chosen one floods gold from
  the point pressed, then relights) with **Twinkle**, and **Decorations** with one switch per area. The footer credits
  the painting and the font, and *Replay the lights* replays the switch-on.

### In the shell

| Area | Where it is hooked | What it does |
| --- | --- | --- |
| Switch-on | `Shell.qml` → `ChristmasHost` | A garland drops over the top of every screen, its bulbs light from the middle, a warm glow spills down, then it is drawn back up (~3 s). Only when switched on (or `ipc call christmas intro`), never at shell start. |
| Bar | `bar/TopBar.qml`, `bar/SideBar.qml` (sections, solid bar), `bar/BarModule.qml` (modules outside a section) | Fairy lights hang from the top inner edge of every pill; on a side bar they point in from the outer edge. They light in a cascade when switched on. |
| Panels | `Main.qml` (every panel), `launcher/Launcher.qml` | The gift unwrapping, then holly on the corner away from the bar (`ChristmasPanel`). Rate-limited to one opening every 260 ms. Closing wraps the panel into a parcel that leaves toward the bar in a few gold stars (~0.5 s, `ChristmasSendOff`, on the screen layer so it outlives the panel) while the holly folds away. |
| Settings | `reusables/guide/SettingsRow.qml` | Frost grows in from the left of the hovered row (or a row highlighted by search), melts on leave (`ChristmasFrost`, from `extras/frost-hover`). Banner rows are left alone. |
| Buttons | `reusables/buttons/IconButton.qml`, `ClickButton.qml`, `FillButton.qml` | Hover glint clipped to the button's shape; gold stars from the press point; icon buttons swing once like a bell; hold-to-confirm buttons pull a cracker (`ChristmasTouch`). |
| Windows | `ChristmasHost` (Hyprland only) | On a focus change, `hyprctl -j activewindow` gives the frame; lights run along the top from the middle, down both sides and meet at the bottom, then fade (~1.8 s). Fullscreen and tiny windows are skipped; rate-limited to one every 420 ms. |
| Notifications | `notifications/Notification.qml` | A satin sash slides across the lower corner and a bow pops onto it; gold for urgent notifications. |

## Performance

- One shader draws a whole string of lights (`shaders/lights.frag`): each pixel only looks at its three nearest
  bulbs, so the cost does not grow with the length of the string.
- The twinkle is one `Timer` at ~12 Hz in the `Christmas` singleton. Strings register while they are visible and lit;
  the timer stops when none is, when Twinkle is off, or in performance mode.
- Every other effect is a `Loader` that is active only while its area is on, and only for the moment it plays (glint,
  bursts, unwrapping, window lights). The per-screen layer windows are mapped only while the intro, the window
  lights or a panel send-off play.
- Performance mode (Settings → General) keeps the lights lit but steady and skips every animation.
- Switching off lets the lights go out (~0.9 s) before the effects unload.

## Settings and IPC

| Key | Default | |
| --- | --- | --- |
| `addonsV2Christmas` | `false` | master switch |
| `addonsV2ChristmasLights` | `"classic"` | `classic`, `warm`, `candy`, `nordic` |
| `addonsV2ChristmasTwinkle` | `true` | |
| `addonsV2ChristmasFx.<area>` | `true` | `bar`, `panels`, `settings`, `buttons`, `windows`, `notifications` |
| `addonsV2ChristmasOpacity` | `0.7` | 0.1 to 1, for the large effects: panel wrapping (not the holly), window lights, notification wrap, switch-on garland; **Effect opacity** under Decorations (the volume panel's slider, in gold) |

```sh
SHELL_QML=~/.local/share/serpantinum/src/quickshell/Shell.qml
quickshell -p "$SHELL_QML" ipc call christmas toggle
quickshell -p "$SHELL_QML" ipc call christmas setEnabled true
quickshell -p "$SHELL_QML" ipc call christmas setLights nordic
quickshell -p "$SHELL_QML" ipc call christmas setArea windows false
quickshell -p "$SHELL_QML" ipc call christmas setOpacity 70
quickshell -p "$SHELL_QML" ipc call christmas intro
quickshell -p "$SHELL_QML" ipc call christmas status
```

## Install, removal, validation

- `christmas.py` owns the `serpantinum-christmas-v2` mark. Every hook is a marked block after one anchor line; an
  unknown anchor stops the install with nothing written; a reinstall replaces the blocks; `--without-christmas` and
  uninstall take them out with the qmldir declarations and the Banners option.
- Shaders are installed under content-hashed names (Qt caches GPU programs by URL). After editing a `.frag`, run
  `python3 scripts/christmas/shaders.py` (`--check` verifies).
- Every component in `payload/christmas/` must be declared in the shell's qmldir (`christmas.TYPES`): files loaded
  through the root qmldir do not see their neighbours. Property names must not redeclare a FINAL `Item` property
  (`top`, `bottom`, `enabled`, `palette`…); `tests/test_christmas.py` checks both.
- `tests/test_christmas.py` covers idempotence and removal of each hook, composition with the Halloween and Snow Hush
  hooks, fail-closed anchors, hashed resources and the IPC surface.
- Visual checks run on the real display (the offscreen platform skips shaders): enable the switch, open a panel, hover
  a settings row and a button, focus a window, send a notification.
