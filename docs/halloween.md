# Autumn night

The normal Serpantinum interface is the source of truth. The seasonal layer is
optional and makes no wallpaper changes. Settings → Addons → Halloween effects
controls motion. Settings → Themes → Seasonal · Halloween independently selects
the Halloween Night palette. Its card uses the supplied moon artwork and the
same dimensions and delegate as the other theme cards.

## Audit and cleanup

At the start of this rebuild, commit `60085a5` and the running installation
already had the previous experiment removed. Its dated backups remained in
`~/.local/share/serpantinum-addons-v2/backups/20261007-*`. Those backups were used
for the audit, not as source material for the new effects.

The old `HalloweenOverlay` repeated sprites, two bright webs, an orange border,
a flat bottom glow, six looping particles and three looping bats on unrelated
surfaces. Fixed sprite offsets and per-object animation loops made composition
fragile. `HalloweenCard` retained purple/orange styling and literal decorations
when disabled; a second motion toggle complicated the master switch. None of
that implementation is deployed or referenced by the new system. Pacman ghosts
and emoji search data are unrelated upstream features and remain intact.

## Design rules

| Role | Treatment |
| --- | --- |
| Surfaces | Smoked near-black `#171216`, blackened burgundy `#2b2026` |
| Warm light | Ember `#cd7745`, candle ivory `#e9b77c` |
| Cold light | Moonlight `#acb3cb`, desaturated vapor `#9d8caa` |
| Text | Warm ivory, with subdued rose-grey secondary text |
| Settings | One directional mist interaction per row, behind all text/controls |
| Important panels | Low asymmetric underlight, folded vapor and at most four sparks |
| Corner detail | One fine, irregular, dimension-dependent web on Settings |
| Clock | Thin celestial arcs, engraved ticks and three distant points |
| Major actions | Seven to ten larger silhouettes with warm rim light and ember trails |
| Sustained hover | Play/Pause launches a new escape every 4.2 s; shared retrigger guard 1.6 s |
| Music | Audio-reactive album corona, rising vapor and an expanded Play flourish |
| System | Conductive currents around power profiles and charged action contours |
| Widgets | Round clock halo, meter filaments, weather mist, musical ribbon and moving reflections |
| Network | Signals travel along real hub/card links, with radio halos and transport-specific light |

The clock and music player are showcase elements. Panel hearths, side mist and
hover energy are deliberately more visible following the user's second brief.
There is no full-desktop fog surface or continuously crossing swarm.

The supplied `Recording_2026-10-07-011026.mp4` was inspected at eight samples per
second: Play gains an electric outline, then bats and gold streaks spread beyond
the button before dissipating. `doctrine_animate.mp4` was inspected for warm
moonlight, red atmospheric layers, cold mist and depth. Their motion/lighting
qualities inform the effects; their character artwork/assets are not copied.

## Ownership and lifetime

`Halloween.qml` owns the effects state, presentation tokens, motion timings and
one ambient clock. Theme colors follow the native preset workflow independently
of that switch. Selecting Halloween Night writes its colors through the existing
preset backend; disabling effects keeps the selected palette. Existing wallpaper
and Matugen presets continue to work. The large illustrated effects card is a
static settings control and remains available while motion is disabled.

`FogLayer` is a small three-octave noise shader, reused for directional `EdgeMist`
and rising `HearthGlow`. It draws directly into its bounded rectangle: no blur,
texture capture or full-desktop intermediate surface. Rounded row corners use
a distance mask. Fog folds and lighting drift with a periodic shared phase;
the warm source combines two asymmetric lobes with slow irregular flicker.
Sparks use the same phase and fade to zero at each wrap.

`ResponsiveCobweb` and `CelestialDial` render at their actual resolution on
creation/resize, rather than repainting each frame. `NightPanel` composes the
selected effects. `BatBurst` runs a finite 1.75 s eased escape, with staggered
paths and secondary wing motion; controls create it only on activation.
`ControlEffects` adds a moving edge filament and a finite excitation on hover or
activation, with the larger escape reserved for Play/Pause. `MusicAura` responds
to the player's existing bass data without adding an audio sampler. The system
profile current changes its warmth/energy smoothly with the selected profile.
An album change gets one bounded `GlassReflection` sweep over the disc. Its
shader is destroyed after the 1.1 s transition; it has no ambient clock consumer.
Widget variants use `WidgetAura`, respecting circular faces; desktop effects
load on an empty workspace, actual hover or editing and unload when obscured.

`NetworkWeave` maps the actual core/card positions into its own coordinate space.
Thin quadratic vector conduits stop at the real circular/rectangular boundaries;
three eased comet-like packets follow each link. Wi-Fi uses warm radio waves,
Bluetooth colder paired motion, and Ethernet straighter transmissions. The old
upstream Canvas lightning and its repaint timer are used for OFF only. Network
controls and connection actions retain their existing implementation.

`HalloweenCard` is a title card on the moon artwork: OFF, the moon is cold and
grey; ON, it fills with blood over 1.6 s, mist and distant bats load (only while
visible and animated) and a bat burst leaves the moon. `NightSwitch` is a moon
phase: new moon OFF, waxing to a full ember moon ON, with keyboard support and
accessibility state.

Loaders destroy effects when OFF or their panel is hidden. Settings mist is
also gated by the current tab, and its shader unloads after the exit fade.
In the standalone Settings window, the hearth, corner web and distant crossings
belong to the content viewport. They follow its resized bounds and the compact
or right-to-left sidebar, and unload when Settings is hidden or the viewport is
empty. Vibrant and Vivid remain owned by the shell's wallpaper/theme workflow.
The ambient clock pauses when the last visible consumer releases it and stops
when Halloween is OFF. Performance
mode retains a still atmosphere and disables ambient motion and bursts.
While ON the clock pauses in place rather than restarting at phase zero. Shader
consumers park their own phase when paused/hidden, so resuming music does not
jump even when another panel kept the shared clock moving. Window visibility
and zero-size surfaces are included in the motion lifetime checks.
Decorations have no pointer handlers, input regions, focus or windows.
Decorative Items and their Loader carriers explicitly disable input; the master
switch remains an interactive control. Repeat timers stop on hover exit,
hidden controls, performance mode or OFF.

Hooks are isolated in `seasonal.py`, validated before installation and marked
in upstream files. The installer preserves the other v2 addons and dated
backups. To remove this entire layer rather than just disable it:

```sh
python3 install.py --without-halloween
serpantinum reload
```

Install normally to restore the option. Reinstall after upstream updates, as
with the other v2 addons. The dormant setting value is retained on removal.

## Validation, 7 October 2026

- Loaded in the actual shell, with no new QML/shader runtime errors.
- Real Settings hover loads one additional shader/clock consumer; leaving
  unloads it after the fade. Closing panels releases all ambient consumers.
- OFF with Settings, clock, music, system and launcher visible reports zero effect instances,
  zero ambient consumers, a stopped animation, and all 22 normal colors matching.
- Actual panel captures inspected at Settings sizes 1200×750, 940×650,
  1100×500 and 1000×890; launcher sizes 640×540, 380×540, 640×210 and 480×800.
- Both clock renderers keep their original orbit for OFF; seasonal geometry is
  separately loaded for ON.
- Python integration checks cover reinstall idempotence, normal palette storage,
  changed-upstream fail-closed behavior, clock preservation and clean removal.
- `qmllint` passes for all new QML components; shader compilation succeeds.
- Desktop ON loaded 20 tracked effect instances / 13 clock consumers across
  the installed widgets; OFF removed all of them and left the selected colors intact.
- The shell remained alive across several minutes of native hover, panel and
  workspace interaction after fixing a Qt pointer-handler parenting crash.
  Widget hover handlers are declared inside their Loader, never reparented to a
  not-yet-created item. Shader URLs are resolved at the effect's source file.
- Removal/reinstall was exercised in an isolated copy of the actual shell:
  all seasonal references/assets disappeared, DNS/monitor addons survived,
  and a second reinstall changed zero files.
- A held-activation check using the actual patched IconButton/ControlEffects
  rendered four escapes during the test, then reported zero repeat loops after
  activation ended. The check used isolated settings and made no playback or
  connection changes.
- Network ON was inspected in the live shell; OFF removed all seasonal objects,
  ambient/repeat loops while preserving the selected palette. Network scanning and
  Bluetooth readiness warnings already belong to the original panel/backend.
- Shader packages deploy with content-derived filenames, preventing the stale
  GPU program observed when replacing a same-named package during hot reload.
  Superseded packages are backed up and removed; writes are atomic.

Before the increased-motion follow-up, short whole-process samples with music/other shell animations active measured
GPU engine busy time around 3–4%, and roughly 49–93% of one CPU core. ON Settings
was 3.94% GPU / 85.91% CPU versus OFF 3.66% / 93.37%. These samples are noisy and
are not a controlled benchmark or a claim about idle shell CPU use. The strong
performance guarantee is structural and verified live: the seasonal clock
and effects are absent when OFF, and paused/unloaded when hidden.

The packaged shader is generated with Qt's shader tool:

```sh
python3 scripts/build-seasonal-shaders.py
```

Shader layout and premultiplied output follow the official
[Qt ShaderEffect contract](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html).

## Autonomous polish pass

- Bat escapes use distinct eased flight lanes, steady wing timing and a
  directional warm rim instead of a uniform outline. A flight already running
  is never restarted, and a denied cooldown does not keep an empty Loader alive.
  Bursts are requested once per interaction, not once per flash animation frame.
- A hidden control cancels its pulses/flights; changing performance mode mid-flight
  stops every repeat and finite motion. Invisible network hubs do not instantiate
  their shaders, and hidden conduits have no packet delegates.
- Payloads and both shader hashes are checked before any installed file is
  modified. The manifest detects stale GLSL or damaged packages. Removing the
  seasonal layer remains possible independently of that validation.
- The Qt runtime regression runs offscreen with isolated settings. It checks
  constructor activation, repeated hover, rejected cooldowns, hide/show,
  phase continuity, performance mode, OFF mid-flight and finite reflection
  cleanup. This is animation/lifetime proof, not software-renderer visual proof.
- A separate native GPU capture inspected the new reflection, halo and bat rim
  in a background surface without opening a foreground desktop panel. It loaded
  without shader/QML errors.

## Expanded surfaces

- OSD souls use eight pooled finite animations: luminous teardrop heads and
  folded ribbon tails leave sideways, with paired releases throttled at 240 ms.
- Background bats cross the clock, network, settings and music panels after
  a first 0.65–1.2 s delay, then randomized 3.2–8 s gaps. Two silhouettes
  with independent offsets take a 4.6–6.6 s curved flight. Widths are 28–63 px
  and rim light makes them legible on the actual clock background. Flights stop
  when their surface is hidden.
- Launcher opening and shrinking search results trigger finite bat escapes and
  cached branching lightning; search changes are throttled at 380 ms.
- Hold effects follow the actual press and confirmation progress on reusable
  buttons, the network hub and system actions. Sound controls add bounded vapor
  and directional row mist. Lock effects follow focus/authentication state.
- Offscreen Qt tests exercise these effects and their hide/performance/OFF
  lifetimes. Native GPU previews inspected souls, arcs and the illustrated card;
  the sound panel and theme/settings cards were also inspected in the live shell.
  Authentication, power actions and disconnection were not exercised.
- Lock decoration now follows its parent Item visibility instead of reading the
  native window visibility during screen creation. This avoids that early window
  getter in the added binding; a live screen hotplug regression remains untested.

## Directional arrivals and permanent decorations

Opening flights are drawn outside each panel's clip, using its live rectangle.
Top/bottom attachments emit at the moving lower/upper frontier; side attachments
emit at the opposite frontier. Centered panels emit at both sides. Settings,
clock, music, network, sound, system, wallpaper and notification-center openings
use the native layout and bar position. The launcher uses its actual attachEdge
and animated container bounds, including list-height changes.

The 43–67 px bats launch in 65 ms intervals along curved, unequal lanes over a
finite 2.05 s flight, with amber rim trails and different wing phases. Wing
contours are cached and flap at their shoulders independently of the body.
Opening flights have their own lifetime so a recent control flourish cannot
silence a panel opening through the global control cooldown.

Each visible horizontal or vertical bar module receives a moving ember. Selected modules also have a small hanging bat. Decorations live
inside the module bounds, follow grouping/resizing/reordering and do not change
module widths, clipping, pointer handlers or the bar's input mask. OFF and
performance mode unload them; native autohide pauses their clock consumers.

Notification cards, including history cards, receive two small wax candles and
a bounded warm underlight. Their shader combines uneven flame lean/flicker with
an ivory center, amber edge and cool wick. Native text, dismiss gestures, actions
and expiration remain intact.

At shell load or effects activation, a finite 3.9 s intro reveals an eclipsed
moon within the engraved dial, branching light, a larger departing flock, low
vapor and two candle flames. Its separate overlay has an empty input region and
never takes focus. It unloads after 4.05 s and cancels immediately on OFF or
performance mode. Leaving performance mode does not replay the intro.

Validation for this pass:

- 14 tests pass, including an actual Qt regression for all five flight directions,
  overlapping opens, early background crossing, hide cancellation, horizontal and
  vertical bar effects, startup/activation intro, finite completion and OFF.
- Native GPU captures inspected the current launcher, settings, clock, music,
  network, system and sound openings, background crossings, eclipse intro,
  horizontal bar and a real notification. An isolated GPU preview also inspected
  the vertical decoration and candle shader. No new QML/shader errors were logged.
- Live OFF reports zero instances, ambient users and running clocks while keeping
  Vibrant selected. After the intro, only the permanent bar consumers remain.
  Isolated installer checks cover idempotence and full seasonal removal.
- Other launcher placements are direction-tested in Qt; they were not exercised
  by changing the user's live launcher/bar settings.

## Final adjustments

Music and network opening flights now fan out from a single corner: lower right
for a top-attached music panel, lower left for the network panel, with the
corresponding leading corner used for bottom/side attachment. Other panels keep
their previous edge/center opening paths. The clock also keeps three small,
slowly fluttering bats on its dial, alongside the random background crossings.

The activation switch now has a larger thumb, clearer border and inline ON/OFF
labels, with a shorter 240–300 ms transition. Keyboard and accessibility toggle
behavior remain intact. Bar webs were removed; bats and moving embers remain.
Native captures checked all four adjusted surfaces, and the 14-test suite includes
corner launch assertions alongside the existing direction/lifetime checks.
