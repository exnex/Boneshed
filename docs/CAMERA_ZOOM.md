# Smooth third-person camera zoom

**Confirmed task scope:** ordinary mouse-wheel zoom extends the camera from combat
presentation PR #19. Wheel up selects a closer third-person view; wheel down selects
farther. Keep the existing framing, orbit, lock-on/manual override and obstruction
handling. Keep the selection throughout the current game session's encounters,
defeat/retry and salvage/equipment flow. Restart persistence is not required.
**Provisional:** the numerical settings below. **Open:** human comfort, closest-view
attack readability and response at physical-device/high-refresh rates.

## Tuning and ownership

The single runtime owner is the **Camera Zoom (provisional)** export group at the top
of [`scripts/characters/player.gd`](../scripts/characters/player.gd). Change these
trusted presentation settings together, with `minimum <= default <= maximum`,
positive step/response, and rerun the framing checks after changing geometry/FOV.
Sensitivity is per Godot wheel unit (`factor = 1`); the engine scales fractional
or multi-unit events. In the pinned Web engine, DOM pixel deltas are multiplied
by 0.03, so browser tests send 1/0.03 pixels for one unit, rather than treating
100 pixels (three units) as a single wheel notch.

| Export | Initial value | Meaning |
| --- | --- | --- |
| `camera_min_distance` | 3.25 m | Closest preferred arm length |
| `camera_distance` | 6.0 m | Existing initial/default arm length |
| `camera_max_distance` | 7.5 m | Farthest preferred arm length |
| `camera_zoom_step` | 0.65 m | Per wheel step; respects the event's fractional factor |
| `camera_zoom_speed` | 12 s⁻¹ | Exponential response: ~95% of a change in 0.25 s |

Distances measure the spring arm from the existing shoulder pivot, not from the
player's center. With the existing 1.2 m shoulder offset, 1.8 m pivot height and 65°
vertical FOV, 2.5 m puts the player's feet below the 720 px frame at pitch −0.12
and +0.15 (approximately y=732 and y=811). At 3.25 m, feet remain in frame over the
whole existing −0.75…+0.15 pitch range (worst case approximately y=697).
The focused suite checks the player's feet/head at all four pitch samples. This
is geometry evidence; human readability still needs the playtest below.

- `preferred_camera_distance` is the player's clamped selection, updated only by
  wheel presses and initialized once from `camera_distance` when the player starts.
- `spring.spring_length` is the smoothly changing requested arm length. The blend
  uses `1 - exp(-speed * delta)`, follows a reversal on the next physics update,
  and has no queued tweens. The existing 60 Hz camera update mode is retained.
- `spring.get_hit_length()` is the actual distance allowed by the environment.
  The existing 0.2 m swept sphere, 0.25 m margin and shoulder-anchor ray remain
  responsible for collision. Collision can shorten the actual arm below the
  preferred minimum; clamping that result upward would push the camera into walls.
  Collision recovery uses the existing spring-arm behavior. It never writes the
  player's preference back from a hit length.

The courtyard retains its player node when replacing combat state for retry,
equipment and the next duel. Zoom belongs to that player, not `CombatState` or the
progression inventory. `reset_at()` intentionally retains both preference and
interpolation. A new game/player instance starts at the configured default.
No camera architecture correction was needed.

Wheel input uses `_unhandled_input`, respects `input_enabled`, and consumes only
vertical wheel presses. Wheel releases and horizontal scrolling do not zoom.
Zoom works with captured or released mouse input; it does not recapture the pointer
or extend the mouse-motion lock-on override. LMB/RMB and keyboard bindings retain
their existing routes. F1 lists wheel zoom; there is no zoom HUD or slider.

## Reproduction

Use the pinned Godot **4.7.2.stable.official.ed1daf0bf** through the existing runners.
Use fresh output directories; Xvfb/Godot and local Chromium need working sockets.
No preview publication is part of these commands.

```sh
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test_camera_zoom.sh artifacts/zoom
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test.sh artifacts/native
bash scripts/tooling/test_presentation.sh artifacts/presentation
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test_marrow.sh artifacts/marrow
bash scripts/tooling/test_builds.sh artifacts/builds
bash scripts/tooling/test_anatomy.sh artifacts/anatomy
bash scripts/tooling/test_worldgen.sh artifacts/worldgen
bash scripts/tooling/test_web.sh artifacts/web
```

The focused test uses actual Godot mouse/button dispatch, live player physics and
the real courtyard. Enemy AI/duel resolution are paused for controlled obstruction
and framing fixtures; the progression fixture resolves a real lethal contact before
using F/E/N. Three isolated source mutations must fail named checks: snapping the
arm, resetting the selection and disabling spring collision. Existing suites
retain AI playthroughs, combat/pose timing, progression and negative controls.
Browser additions use actual Chromium wheel events, including during attack and
held guard, plus near-wall recovery and retry. The release export has no QA bridge.

See [executed results and rendered evidence](evidence/camera-zoom/README.md).

## Human playtest

Run `bash scripts/tooling/play.sh` on the PR branch. Record commit, OS, mouse,
display resolution and refresh rate. Start with F3 off; use F1 for controls.

1. At the initial 6 m view, compare framing/orbit/Tab lock against PR #19. Scroll
   one step each way, then sweep to both limits. Reverse direction quickly while
   zoom is moving. Check prompt response without a jump or continued movement
   toward an old selection. At the close limit, look fully up/down and inspect
   the player's silhouette, weapon and incoming cuts; at far zoom, judge whether
   both characters and their attack cues remain large enough.
2. Circle/strafe the enemy at sword range; back away while locked. Use mouse motion
   during zoom to override tracking, then stop moving the mouse and let tracking
   resume. Let the enemy cross behind you and bring both characters toward the
   camera. Look for lost framing, abrupt yaw or camera entry into a character.
3. Select far zoom; back toward each wall, a corner and the pillars. While the arm
   is shortened, change the selection, then walk back to open space. Confirm it
   returns to the newly selected distance. Repeat close and unlocked, orbiting
   beside the right shoulder wall. Report any clipping or severe obstruction.
4. Scroll during light/heavy windup, active cuts and recovery, while holding RMB,
   on a fresh deflect press and while dodging. Confirm LMB still attacks, RMB does
   not drop/restart guard, and WASD/Space/C/Q/Tab/Esc/F1/F3 remain responsive.
5. Choose a noticeable non-default distance. Retry with R, lose and retry, then
   win legitimately, F salvage, E inspect/equip, N next duel and Q Marrow Lunge.
   Confirm each keeps the selected distance; toggle lock off/on as well. Closing
   and reopening should start at the default again.

Repeat at the display's normal refresh rate. Report feel/readability separately
from test pass counts. Rendered software frames do not establish either, or desktop
GPU performance. No high-refresh interpolation setting was changed in this PR.
