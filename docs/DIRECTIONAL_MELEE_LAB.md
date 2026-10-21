# Directional melee lab — isolated playable prototype

**Status: experimental prototype, not production combat. Every control, number and rule
here is Proposed, for the owner's playtest; nothing is Confirmed.** First Expedition, its
default entry point, the current combat rules, the survival AI, salvage/equip, keyword
generation, the build catalog file and the published browser preview are unchanged.
Engine: Godot **4.7.2.stable.official.ed1daf0bf** (checked with `--version` by the
tooling), GL Compatibility, Linux x86_64. Built 2026-10-20.

Owner direction this explores ([DECISIONS.md](DECISIONS.md), 2026-10-19/20): Last
Oasis-inspired mouse-directed attacks and blocks, Mordhau-like angle/inertia-dependent
weapon handling, Sekiro-like immediacy and deflection, weapons described by reach, weight,
class and grip — "prototype in isolation before replacing production combat". The
references are inspiration; no undocumented commercial mechanic is reproduced or claimed.

| Section | |
| --- | --- |
| [1. Launch](#1-launch) | Exact commands, scene path |
| [2. Controls and rationale](#2-controls-and-rationale) | Click-then-flick aim, guard aiming, camera separation |
| [3. Architecture](#3-architecture) | Files, layers, step order, isolation |
| [4. Weapon physics](#4-weapon-physics-what-really-depends-on-the-weapon) | The handling model and exactly which mechanics read weapon data |
| [5. Directional defense](#5-directional-defense) | Block, deflect, bad angle, guard break, clash |
| [6. Weapon contact](#6-weapon-contact-swept-segments) | Swept segments, anti-tunnelling, tie rule |
| [7. Responsiveness](#7-responsiveness-and-cancels) | Cancels and their documented constraints |
| [8. Opponent](#8-experimental-opponent) | Delayed perception, modes, fairness |
| [9. Tuning parameters](#9-tuning-parameters) | Every value, its unit and meaning |
| [10. Tests and evidence](#10-tests-and-evidence) | Commands, results, rendered clips |
| [11. Known limitations](#11-known-limitations) | |
| [12. Owner playtest checklist](#12-owner-playtest-checklist) | |
| [13. Proposed next milestone](#13-proposed-next-milestone) | |

**2026-10-21 addition (experimental):** stamina, equipment weight, a dodge roll, a small
poison/slow status pipeline, armor resistances and resource-aware AI legality now run in
this lab. Their rules, numbers, schemas, tests and playtest checklist are in
[MELEE_LAB_COMBAT_RESOURCES.md](MELEE_LAB_COMBAT_RESOURCES.md); the controls and
contact rules below are unchanged except where marked.

## 1. Launch

```sh
cd /path/to/Boneshed
bash scripts/tooling/setup.sh          # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/play_melee_lab.sh # opens res://scenes/melee_lab.tscn
```

Equivalent: `bash scripts/tooling/play.sh res://scenes/melee_lab.tscn`. In the Godot
editor, open `scenes/melee_lab.tscn` and press **F6** (Run Current Scene); **F5** still
runs First Expedition. The lab is also exported separately for the browser at
<https://exnex.github.io/Boneshed/melee-lab/> (`data/melee_lab/*.json` is in the Web
export filter); nothing links to it from the game.

## 2. Controls and rationale

Shown in-game (F1). All bindings live in one table,
[`scripts/melee_lab/lab_input.gd`](../scripts/melee_lab/lab_input.gd), as `lab_*` actions
added at runtime only if absent (production actions and `project.godot` are untouched).

| Input | Action |
| --- | --- |
| **LMB press** | Start preparing a cut *immediately*, toward the natural follow-up side |
| **LMB held + mouse** | Mouse moves the aim cursor (not the camera). Flick past the deadzone: **right** / **up-right** / **up** / **up-left** / **left** = the side the blade is chambered on; **down** = thrust. The blade heads to the new chamber at once |
| **LMB release** | Commit: the swing fires when the chamber is reached (never before `min_windup`). The chamber holds as long as LMB is held; a tap = follow-up cut |
| **RMB held + mouse** | Remain in guard until RMB is released (unless guard is broken or a dodge overrides it); mouse points at the side to cover (same layout, **down** = centre against thrusts). The last guard side is kept if you don't flick |
| **RMB fresh press** | Opens the deflect window; cancels any attack |
| **Space** | Dodge step: cancels everything, brief invulnerability (costs stamina) |
| **Shift** | Dodge roll (2026-10-21, experimental): further, costlier, vulnerable tail — see [combat resources](MELEE_LAB_COMBAT_RESOURCES.md) |
| WASD · Tab | Move · toggle lock-on (on by default) |
| R · Esc | Reset duel · free the mouse |
| F1 · F2 · F3 · F4 | Help · handling/tuning table · hitboxes · slow motion ×0.3 |
| T · Y · U | Blade trails · telegraph arcs · intent labels |
| `[` `]` · `,` `.` | Cycle your build · the opponent's build (weapons, plus the evasive/balanced/resistant armor profiles) |
| M · G · V | Opponent mode (duel/defend/attack/dummy) · dummy guard side · toxic miasma world condition |

Direction names describe the swing's travel: chambering **right** cuts **right→left**.

**Why "click, then flick".** The alternatives considered:

| Scheme | Problem it has | Verdict |
| --- | --- | --- |
| Flick *before* click (read recent mouse motion at the click) | The flick also turns the camera — exactly the interference the brief forbids | Rejected |
| Always-on cursor while locked on | Mouse never turns the view; turning while attacking needs lock-on | Kept as a future option |
| Number/arrow keys per direction | Fast, but not mouse-directed and hard to combine with WASD | Rejected as the default |
| **Click, then flick (chosen)** | Adds no delay: the windup starts on the press; the flick only redirects it | Default |

The mouse belongs to the aim cursor only while LMB is held before release, or while RMB
is held. After release (during the swing and recovery) it turns the camera again, so you
can attack while moving and turning, and turning into a released cut drags it with the
body (the blade's world path follows the body's facing each tick). A direction can be
changed until release and the weapon stays chambered indefinitely while held, which makes feints and late redirects possible; the opponent only
sees the change after its reaction delay.

## 3. Architecture

```
data/melee_lab/weapons.json  ─┐   lab weapon items (appended in memory to the shared catalog)
data/builds/catalog.json  ────┼─► lab_loadout.gd ── BuildRules.resolve ── resolved.equipment.weapons
data/melee_lab/tuning.json ───┘                                              │
                                                              weapon_handling.gd (inertia, accel, …)
swing_geometry.gd (directions, arcs, poses) ──► duelist_state.gd (rules: windup/swing/guard/dodge)
                                                              │
contact_solver.gd (swept segments, outcomes) ◄────────────────┘
lab_duelist.gd (body, movement) ◄─ lab_player.gd (input) / lab_opponent.gd (AI)
lab_visual.gd, lab_hud.gd (presentation: reads state only)      melee_lab.gd (arena, step order)
```

| Layer | Files (`scripts/melee_lab/`) | Owns |
| --- | --- | --- |
| Data | `weapons.json`, `tuning.json` | Lab weapons, loadouts, every provisional number |
| Adapter | `lab_loadout.gd` | Catalog merge, validation, build resolution |
| Rules | `weapon_handling.gd`, `swing_geometry.gd`, `duelist_state.gd`, `contact_solver.gd` | Pure, deterministic, no nodes, no input |
| Actors | `lab_duelist.gd` | Locomotion, facing, the rules frame |
| Controllers | `lab_player.gd`, `lab_opponent.gd`, `lab_input.gd` | Input/AI → rules calls |
| Presentation | `lab_visual.gd`, `lab_hud.gd` | Meshes at the rules pose, overlays, HUD |
| Scene | `melee_lab.gd`, `scenes/melee_lab.tscn` | Arena and fixed step order |

**Step order each physics tick:** player controller → opponent controller → player
rules + movement → opponent rules + movement → contact for the player's blade → contact
for the opponent's blade. Outcomes never depend on node processing order.

**Reuse and isolation.** The lab reuses the shared build foundation unmodified: the
production catalog file is read, lab items are appended in memory, and the combined catalog
goes through the same `build_catalog.gd` validation and `build_rules.gd` resolution as
production builds; profile stats (health, posture, move speed, deflect window, posture
recovery) come from the shared profiles. Grip rules apply (a two-hander with an off-hand
weapon is rejected). It does **not** reuse `CombatState`, `Fighter`, the courtyard
adapter or the survival AI: those encode the production timing model, and reusing them
would either change production behaviour or force it to carry lab mechanics. The
opponent re-implements the production *principle* (reaction-delayed perception of drawn
cues) for directional cues. No production file references the lab (tested).

## 4. Weapon physics: what really depends on the weapon

A controllable, tunable model, not rigid-body dynamics. The weapon is a rigid rod held at
its grip on a fixed-length arm, swinging about a shoulder pivot. From
`resolved.equipment.weapons[0]` (`handling.length` L, `mass` m, `balance` b, `grip`,
`defense`):

```
r_com   = arm_reach + b·L                         pivot → centre of mass (m)
I       = m·(r_com² + L²/12) + arm_inertia        moment of inertia (kg·m²)
α       = torque / I,  torque × two_handed_torque_scale for two-handed grips
ω       ≤ max_angular_speed                        the same hand-speed cap for every weapon
reach   = arm_reach + L
guard strength = (m / ref_mass)^exp × two_handed_guard_scale
```

| Mechanic | Depends on | How (measured values from the test run) |
| --- | --- | --- |
| Swing acceleration and time to contact | I, grip | α = τ/I. From an idle stance to the blade pointing straight ahead: knife 0.33 s, sword 0.45 s, greatsword 0.53 s (windup part 0.18 / 0.25 / 0.28 s). A cut lands slightly earlier on a target at 2 m (sword ≈ 0.42 s). Production light attack: 0.34 s windup |
| Momentum at contact (damage, posture, recoil) | I, ω | I·ω at the speed cap: knife 9.4, sword 27.7, greatsword 73.2 kg·m²/s; damage ∝ √(KE/KE_ref) |
| Changing direction | I | The chamber move is a bang-bang (accelerate/brake) rotation at α. Follow-up vs repeat windup: sword 0.18 vs 0.35 s, greatsword 0.18 vs 0.43 s |
| Recovery after a miss | I, ω | recovery_base + ω/brake — the blade must stop |
| Guard-cancel of a swing | I, ω | guard waits ω/brake (capped) before moving |
| Guard raise / guard shift speed | I | rate = guard_shift_rate·√(I_ref/I): rest → high guard knife 0.07 s, sword 0.10 s, greatsword 0.15 s |
| Turning while attacking | I | turn rate = 270°/s·√(I_ref/I), clamped ×0.5–1.25 |
| Reach and guard coverage | L | Hit segment and guard segment are the weapon (hand → tip) |
| Posture absorbed when blocking | m, grip | pressure ÷ guard strength; a heavy blow can overwhelm a light guard outright |
| Can block / can deflect | `defense.guard`, `defense.deflect` | The lab staff has `deflect: false`: it blocks, never deflects |
| Thrust acceleration and momentum | m (+ arm mass), grip | linear: a = F/(m + arm_mass) |

**Does not depend on the weapon (yet):** the deflect window (profile stat), alignment
tolerances, the minimum windup floor, dodge, hit stagger, blade edge vs flat, where along
the blade contact happens, and weapon class beyond `defense` (blade vs staff only changes
the mesh and the deflect flag). Two-handed weapons use the same single swing pivot.

The **minimum windup** (0.18 s) is a readability floor, not physics: a knife could
otherwise chamber in under 0.1 s. Every visible preparation lasts at least this long.

## 5. Directional defense

Guards are geometric: the guard pose places the defending weapon across the covered side
(hand pushed toward that side and forward, blade perpendicular to it). An attack is
defended only if its swept blade actually **touches the defending weapon before the
body**. Then the attack's arrival side (from the touching point's velocity in the
defender's frame; thrusts arrive at the centre) is compared with the guard side:

| Outcome | Condition | Effect |
| --- | --- | --- |
| **Deflection** | Weapon touched, fresh press ≤ deflect window (0.16 s), alignment ≤ 40°, weapon can deflect | Attacker: posture 30 + 0.6·momentum, recoil 0.3 + 0.012·momentum s (punish window). Next deflect attempt re-armed |
| **Block** | Weapon touched, alignment ≤ 60° | Defender posture += 1.1·momentum ÷ guard strength. Attacker bounces into a short recovery |
| **Bad angle** (misaligned) | Weapon touched, alignment > 60° | Blade slides off: 50 % damage, 150 % posture, defender staggered |
| **Guard break** | A block whose pressure ≥ 75 in one blow, or that fills posture | Defender broken 1.6 s, takes ×2 damage |
| **Hit** | Body touched first (guard elsewhere = "guard held on the wrong side") | Damage, posture, stagger |
| **Clash** | Two live blades cross | Both recoil 0.3 s, +10 posture each |
| **Evaded** | Body touched during dodge invulnerability | Nothing |

Measured alignment matrix (sword vs sword at 2 m, every attack vs every settled guard):

| Attack ↓ / guard → | right | high_right | high | high_left | left | centre |
| --- | --- | --- | --- | --- | --- | --- |
| right→left (arrives on the defender's left) | hit | hit | hit | block | **block** | hit |
| left→right | **block** | block | hit | hit | hit | hit |
| overhead | hit | block | **block** | block | hit | bad angle |
| high right (diag_right) | hit | hit | block | **block** | block | hit |
| high left (diag_left) | block | **block** | block | hit | hit | hit |
| thrust | hit | hit | hit | hit | hit | **block** |

Bold = the matching guard. Adjacent 45° guards also block (never deflect: 45° > 40°).
Shields are not required for any of this; shield coverage and reduced posture are deferred.

## 6. Weapon contact: swept segments

Weapons are segments (hand → tip) with radii (blade 0.03 m, guard 0.05 m); bodies are a
vertical capsule (axis 0.2–1.55 m, radius 0.32 m). Each tick the attacker's blade moves
from its previous pose to its current pose; for swings the direction is slerped, which is
exactly the great-circle arc. The sweep is split so the tip moves at most
`contact_spacing` (0.05 m) per substep — less than blade + guard radius, so a guard
cannot be tunnelled through even at 80 rad/s (tested; with substeps disabled the same case
passes through: negative control). Both actors' transforms are interpolated across the
tick too. The first substep with contact decides; if the weapon and body touch in the same
substep the weapon wins (fixed, defender-favouring rule). On weapon contact the blade
stops at the contact pose, so the drawn sword never passes through the guard it hit. The
reported point lies on both drawn weapons (tested). Outcomes are identical at 30, 60 and
120 Hz in the tested exchange. No physics server is involved in contact: it is pure maths
and deterministic across processes (cross-process replay is compared byte for byte).

## 7. Responsiveness and cancels

| Action | Constraint (experimental) |
| --- | --- |
| Attack press | Windup starts on the same tick; no input lag is added by aiming |
| Fresh guard press during **windup** | Cancels instantly; the guard starts moving the same tick |
| Fresh guard press during **swing/recovery** | Cancels the cut instantly (it can no longer hit), but the guard waits ω/brake, capped at `cancel_brake_cap` 0.15 s, while the blade stops. Set the cap to 0 for instant guards |
| Dodge | Cancels windup, swing and recovery instantly; 0.3 s invulnerability, 0.65 s cooldown |
| Attack during recovery | Buffered for 0.2 s and starts the moment the blade is free |
| Redirect | Allowed until release (feint) |
| Movement | Full locomotion through windup, swing and recovery; guard walks at ×0.6 |
| Turning | Instant-feeling (14 rad/s) outside attacks; weapon-limited while attacking |

The tension between inertia and control is resolved toward control: the hand-speed cap is
shared, windups have a short floor rather than a long one, and the only inertia-imposed
delays on defense are the bounded brake and the guard shift (0.07–0.15 s). These are the
first numbers to tune if the owner finds heavy weapons sluggish. One honest gap: an
opening cut from an idle stance reaches the target about 0.08 s later than the current
production light attack (sword ≈ 0.42 s vs 0.34 s windup), while follow-up cuts are
quicker (0.18 s preparation). Raising `torque_one_handed` or lowering `swing_start_deg`
closes it. Animation does not hide
any delay: the drawn weapon *is* the rules pose.

## 8. Experimental opponent

A contained, scripted opponent ([`lab_opponent.gd`](../scripts/melee_lab/lab_opponent.gd)),
not the production survival AI. It sees only drawn cues — phase, the chamber the blade is
heading to, whether it is reached, guard side — **after a 0.22 s reaction delay**. It
never reads input, the aim cursor, `released`, or future timing. One seeded stream
(seed 20261020) drives every choice, so a duel replays identically.

- **Defense:** guards the side the visible chamber threatens (85 % accurate; a misread
  picks another sector). A late redirect is only seen after the delay, so feints work.
  45 % of swings it tries a timed deflect instead: guard down until the chamber is seen
  reached, then a fresh press after 0–0.08 s — baitable by holding the chamber.
- **Offense:** attacks from spacing just inside its reach, prefers sides the visible guard
  does not cover, never the same cut three times running, holds windups 0.32–0.52 s
  (readable), may counter after a block or deflect it felt.
- **Modes (M):** *duel*, *defend* (never attacks: practise offense), *attack* (never
  guards: practise defense), *dummy* (holds the guard chosen with G, or none: controlled
  comparisons).

## 9. Tuning parameters

All in [`data/melee_lab/tuning.json`](../data/melee_lab/tuning.json) (single owner,
validated as finite numbers; restart the scene after editing). Weapons and loadouts are
in [`data/melee_lab/weapons.json`](../data/melee_lab/weapons.json).

| Group | Key | Default | Meaning |
| --- | --- | --- | --- |
| Body | `pivot_height` | 1.35 m | Shoulder pivot height (swing centre) |
| | `arm_reach` | 0.55 m | Pivot → grip |
| | `blade_radius`, `guard_radius` | 0.03, 0.05 m | Contact radii of attacking blade / defending weapon |
| | `body_radius`, `body_bottom`, `body_top` | 0.32, 0.2, 1.55 m | Body capsule |
| | `contact_spacing` | 0.05 m | Max tip travel per contact substep |
| Swing | `torque_one_handed` | 220 N·m | Wielder torque |
| | `two_handed_torque_scale` | 1.5 | Torque and thrust force ×, two grips |
| | `arm_inertia` | 0.35 kg·m² | Added to every weapon's inertia |
| | `max_angular_speed` | 13 rad/s | Shared hand-speed cap |
| | `swing_start_deg`, `swing_live_deg` | 100°, 80° | Chamber angle; arc becomes live below this |
| | `swing_end_horizontal_deg`, `swing_end_overhead_deg` | −80°, −30° | Arc end (overhead stops above ground) |
| | `min_windup` | 0.18 s | Readability floor for every preparation; holding continues indefinitely without attacking |
| | `max_hold` | 1.0 s | Legacy tuning value, no longer triggers player or state auto-release | A held chamber auto-releases after this |
| | `brake_ratio` | 1.2 | Braking accel = α × this |
| | `recovery_base` | 0.15 s | Recovery after a miss = this + ω/brake |
| | `cancel_brake_cap` | 0.15 s | Max guard delay when cancelling a swing |
| Thrust | `thrust_force`, `arm_mass` | 160 N, 2 kg | a = F/(m + arm_mass) |
| | `max_thrust_speed` | 8 m/s | |
| | `thrust_extension`, `thrust_live_extension` | 0.6, 0.15 m | Hand travel; live after this |
| | `thrust_retract` | 0.15 s | Base recovery after a thrust |
| Damage | `swing_damage`, `energy_ref` | 18, 150 J | Damage = 18·√(KE/150) |
| | `thrust_damage`, `thrust_momentum_ref` | 15, 25 kg·m/s | Damage = 15·p/25 |
| | `hit_posture` | 16 | × impact ratio |
| | `stagger_hit` | 0.3 s | Hit stagger |
| | `broken_duration`, `broken_damage_scale` | 1.6 s, ×2 | Guard break |
| Defense | `block_posture_per_momentum` | 1.1 | Block pressure per unit momentum |
| | `thrust_block_scale` | 0.6 | Thrust pressure × |
| | `guard_strength_ref_mass`, `guard_strength_mass_exponent`, `two_handed_guard_scale` | 1.4 kg, 0.35, 1.35 | Guard strength |
| | `guard_overwhelm` | 75 | One block at or above this breaks the guard |
| | `block_align_deg`, `deflect_align_deg` | 60°, 40° | Alignment tolerances |
| | `deflect_rearm` | 0.32 s | A re-press within this cannot deflect (anti-spam) |
| | `deflect_posture_base`, `deflect_posture_per_momentum` | 30, 0.6 | Attacker posture on deflect |
| | `deflect_recoil_base`, `deflect_recoil_per_momentum` | 0.3 s, 0.012 | Attacker recoil on deflect |
| | `block_bounce_base`, `block_bounce_per_momentum` | 0.25 s, 0.006 | Attacker bounce on block |
| | `misaligned_damage_scale`, `misaligned_posture_scale` | 0.5, 1.5 | Bad angle |
| | `guard_shift_rate`, `guard_ref_inertia` | 16 rad/s, 2.13 kg·m² | Guard shift speed at the reference (sword) inertia |
| | `clash_posture`, `clash_recoil` | 10, 0.3 s | Clash |
| Movement | `dodge_duration`, `dodge_cooldown`, `dodge_speed` | 0.3 s, 0.65 s, 10 m/s | |
| | `guard_move_scale` | 0.6 | Walk speed while guarding |
| | `attack_turn_rate_deg` | 270°/s | Turn limit while attacking at reference inertia |
| Input | `aim_sensitivity` | 0.012 /px | Cursor units per mouse pixel |
| | `aim_deadzone` | 0.35 | Below this the follow-up / last guard side applies |
| AI | `ai_reaction_delay` | 0.22 s | Perception delay |
| | `ai_guard_accuracy`, `ai_deflect_attempt`, `ai_counter_chance` | 0.85, 0.45, 0.6 | |
| | `ai_min_windup`, `ai_hold_max` | 0.32, 0.2 s | Readable windup hold |
| | `ai_attack_interval` | 0.9 s | + random 0–0.5 s |

Lab weapons (placeholders): Notched Sword (shared catalog: 1.8 m, 1.4 kg, balance 0.25,
one-handed), Long Knife (0.9 m, 0.7 kg, 0.15), Greatsword (2.1 m, 3.0 kg, 0.3,
two-handed), Quarterstaff (2.0 m, 1.8 kg, 0.45, two-handed, cannot deflect).

## 10. Tests and evidence

```sh
bash scripts/tooling/test_melee_lab.sh   # ≈ 6 min on the cloud image (llvmpipe)
```

It parse-checks every lab script, runs **86 deterministic checks** (77 at first
merge, plus the 6 hold-to-release checks of PR #48 and one load check per added
loadout; the runner's expected count had not been updated after PR #48 and is fixed
now)
([`melee_lab_tests.gd`](../scripts/qa/melee_lab_tests.gd)) twice in separate processes
and compares the results byte for byte, runs two negative controls that must fail their
named checks (`--negative=no-substeps` → tunnelling; `--negative=omniscient` → AI
reaction delay), runs the combat-resources suite with its own replay and two negative
controls ([details](MELEE_LAB_COMBAT_RESOURCES.md#7-tests-and-evidence)), renders 23 clips
(14 original + 9 resource clips) under Xvfb/llvmpipe that each assert their outcome
([`melee_lab_capture.gd`](../scripts/qa/melee_lab_capture.gd)), builds contact sheets and
MP4s, and fails if the branch touched `project.godot`, export presets, workflows, the
roadmap/decision log, production scenes or production combat/AI/build/world scripts.

Check groups: data and build reuse (8), direction classification (4), swing arcs (8),
weapon handling (12), defensive alignment (14, including the matrix above), hit
registration (6: anti-tunnelling, control, contact on drawn weapons, reach per weapon,
tick-rate independence, determinism), cancels (9), real-input scene checks (4: aim owns
the mouse without turning the camera, camera returns, guard aiming, tap = immediate
follow-up), AI (5: reaction delay, late redirect, variety, contacts, replay), isolation (2).

Evidence and results: [`docs/evidence/directional-melee-lab/`](evidence/directional-melee-lab/README.md).

Two runs produced byte-identical `results.json` and `clips.json`.

**Existing regression suites** run on this branch all pass: `test.sh` (after re-running
with `BONESHED_GRAPHICAL_TIMEOUT=900`; the default 180 s graphical timeout expired on this
software renderer), `test_builds.sh`, `test_expedition.sh`, `test_marrow.sh`,
`test_keyword_grammar.sh`, `test_worldgen.sh`, `test_enemy_ai.sh`. Details and what was
not run: [regressions.md](evidence/directional-melee-lab/regressions.md).

## 11. Known limitations

- **No human has played it.** Automated checks prove reachable behaviour and invariants,
  not feel. Whether click-then-flick is comfortable is the main open question.
- Placeholder bodies and poses; arms are straight segments; two-handed weapons swing about
  the same single pivot as one-handed ones. No animation polish was attempted.
- Five fixed cut directions plus thrust; no continuous angles, no underhand cuts.
- The direction cursor is relative to the camera-independent body frame, so aiming feels
  the same in any camera orbit; it is not screen-space Mordhau-style aiming.
- Body contact is one capsule: no head/limb zones, no hit location effects.
- No edge alignment, no blade–blade parry geometry beyond "weapon touched first", no
  chambers/counter-attacks through attacks (Mordhau's chamber), no feint penalty.
- The AI uses a fixed seed and simple rules; it is a sparring partner, not the
  production survival AI. It never dodges in this version.
- Death has no flow: press R. Slow motion uses `Engine.time_scale`. Stamina and statuses:
  see [combat resources §8](MELEE_LAB_COMBAT_RESOURCES.md#8-known-problems-and-deferred-mechanics).
- Tuning is first-pass; heavy weapons may feel sluggish or overwhelming, and the thrust is
  weak at typical spacing (it often lands early in its extension).
- Contact uses the rules frame only; walls do not stop blades.

## 12. Owner playtest checklist

1. Launch with `bash scripts/tooling/play_melee_lab.sh`; read F1.
2. Set the opponent to **dummy** (M) with no guard. Tap LMB repeatedly — do flowing
   right/left cuts feel immediate? Now hold LMB and flick up, down, left, right before
   releasing. Is the direction easy to choose without looking at the cursor?
3. While holding LMB, does the camera stay still, and does it feel right that it does?
   After release, turn the mouse during the swing: does the blade drag with you?
4. Cycle the dummy guard (G) and attack each side: is block vs hit vs **bad angle**
   readable? Switch your weapon (`]`) to the knife and greatsword: is the handling
   difference obvious, and is the greatsword still fun rather than sluggish?
5. Set the opponent to **attack** (M). Read its telegraph (arc colour, chamber pose,
   label) and guard the matching side with RMB + mouse. Is there enough time?
   Try fresh presses just before contact: are deflections achievable and consistent?
6. Try cancelling: start a cut and press RMB; start a cut and dodge. Any input feel late?
7. **Duel** mode: does fighting feel like a dangerous sword duel? Does the AI feel fair?
   Do feints (hold, then redirect late) fool it sometimes but not always?
8. Toggle F3 (hitboxes), T (trails), F4 (slow motion): do hits land where the blade is?
9. Compare with First Expedition's current combat: what is better, what is lost?
10. Note any desired tuning (windup floor, guard speed, alignment tolerance, damage).

## 13. Proposed next milestone

After the owner's playtest, a **tuning-and-control pass in the lab only**: adjust the
handful of numbers the playtest flags (min windup, guard shift, brake cap, tolerances,
damage), try the "always-on cursor while locked on" variant as an F-key toggle for A/B
comparison, add a stamina/posture cost for feints if feints dominate, and give the
opponent a dodge and a riposte after deflecting. Only then decide whether a production
integration plan (mapping directional attacks onto the shared combat rules and the
survival AI) is worth scoping. Owner decisions needed: preferred aim scheme, whether
heavy-weapon inertia should ever delay defense, whether thrusts stay, and whether natural
weapons (Marrow Arm) should use the same directional system.
