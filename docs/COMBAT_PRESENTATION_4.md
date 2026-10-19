# Combat presentation, iteration 4: key-pose attack animation

**Status: presentation-only slice. Proposed, not human-validated.** Branch
`feat/combat-presentation-slice` from main `79289f0`. Engine: Godot
**4.7.2.stable.official.ed1daf0bf** (checked with `--version` and the pinned SHA-512 setup),
GL Compatibility, llvmpipe under Xvfb. Renders are not a playtest. This document makes no
claim that combat feels good.

**Unchanged:** attack damage, timings, stages, collision and hit acceptance, posture,
guard, deflection, parry, dodge, AI and builds. `combat_state.gd`, `fighter.gd`,
`player.gd`, `swordsman.gd`, the courtyard, HUD, scenes, catalog, worldgen, keyword and
expedition files are untouched. Every existing pose, timing and rules fixture passes
without edits, including the pre-integration rules trace.

## What changes on screen

| Area | Before (PR #19) | Now |
| --- | --- | --- |
| Attack motion | Straight linear blends between three poses. The blade stops at contact. | Cubic key-pose tracks (8–10 keys per attack) on curved arcs. The blade carries momentum through contact into a follow-through and settle. |
| Anticipation | Loads during the early stage, then lerps straight to contact. | Gathers in *early*, then holds a still-coiling **loaded pose** for all of *committed* (the lab standard: a visible hold at `loaded`), then accelerates in *release*. |
| Weight | Torso turns; the hips barely move. | Crouch and weight shift back on load. The lead foot **steps and lands** on release (0.30–0.42 m) and recovers in *recovery*. The pelvis follows the chest twist and the head steadies toward the opponent. |
| Light vs heavy silhouette | Different hand heights. | Light draws out wide and low to the sword side and cuts across. Heavy lifts two-handed overhead, sinks deeper, then chops and drives low after the hit volume closes. |
| Limbs | Fixed endpoints with a midpoint elbow and knee, so limbs stretch. | Fixed-length **two-bone IK** arms and legs. Knees bend under the crouch. The shoulder protracts up to 0.12 m before an arm stretches (measured worst stretch is in the checks). |
| Release/contact cue | None beyond the pose. | A **blade trail** computed from the pose track: faint steel during *release*, bright exactly over the rule's **ACTIVE** window, drained 0.1 s after it ends. |
| Commitment cue | None. | A brief code-generated **glint** on the weapon tip during the first 0.14 s of *committed*. It is larger for heavy and appears on the bone tip for Marrow Lunge. |
| Body hit | A static chest-back pose scaled by stagger time. | An **additive reaction layer**: on the resolving frame the chest snaps away from the attacker's side, the knees give, the sword arm flings wide, then a damped settle. A short **slash streak** appears on the struck body (diagonal for light, near-vertical for heavy, a stab for the lunge). |
| Poised heavy hit | Indistinguishable. | The body flinches while the weapon keeps its rule-aligned path, so hyper-armour reads. |
| Guard / deflect | A small kick on block. The deflected attacker's weapon snaps to a thrown pose. | Block: blade driven back and weight sinks. Deflect: a crisp, small brace for the defender plus a **contact flash**; the attacker's weapon rebound overshoots, then gives ground with a back step. |
| Exits | Stagger, break, dodge and cancels snap to idle. | Stagger and break ease back over the last 0.18/0.35 s of their rule lockout. Dodge ducks and rises inside its duration. Guard raise/lower and attack cancels get a 0.08 s crossfade. |
| Marrow Lunge | Fixed bone root; torso set inside the bone code. | The bone grows from the shoulder and follows the coil and lunge step. Its length is shortened by the body's forward travel, so the tip still lands on the rule reach on every ACTIVE tick (checked to 2 cm). |

Light and heavy keys are authored right-handed and **mirrored exactly** for a left-hand
sword (the Marrow-equipped fighters). Before, only the hand position flipped; the blade
rotation did not.

## How it works

- [`attack_pose_keys.gd`](../scripts/characters/presentation/attack_pose_keys.gd): data
  only. Key poses with channels hand, blade, torso, body (crouch, lean, step, lift),
  off-hand grip. Keys sit on the animation lab's **marker clip time** (0 start, 1 loaded,
  2 release, 3 contact, 4 active_end, 5 recovered). Contact keys are pinned to the
  2.35 m hit volume. A GDScript constant file is used instead of JSON so the web export
  filter needs no change.
- [`pose_sampler.gd`](../scripts/characters/presentation/pose_sampler.gd): pure. It reuses
  the lab's tested [`phase_warp.gd`](../scripts/animation_lab/phase_warp.gd) to map
  `(phase, remaining)` to marker time, so the key poses land on rule boundaries for any
  build timing (windup scale included). It also provides the Hermite key interpolation
  (`hold` keys have zero velocity), the mirror, the reaction envelope and layer, and
  two-bone IK.
- [`combat_fx.gd`](../scripts/characters/presentation/combat_fx.gd): trail, glint, hit
  streak and deflect flash. Every cue is recomputed from rule state and resolved results
  each frame. Nothing keeps history, so cancels, resets and teleports cannot leave a
  stale trail. The glint texture is generated in code. **No third-party assets.**
- [`fighter_visual.gd`](../scripts/characters/fighter_visual.gd) composes them in four
  steps: base pose → crossfade → additive reaction → limbs, Marrow and effects. The
  existing node fields and the F3 debug volumes are kept. The only presentation state
  added is the crossfade record, stored as metadata on the fighter's visual node, so
  `Fighter` gains no fields. Zero-delta refreshes (hit resolution, fixtures) always show
  the exact rule pose.

The rendered pose still never decides a hit. `valid_attack_target` and `CombatState`
are untouched.

## Validation (this branch, 2026-10-19)

| Run | Result |
| --- | --- |
| `test_combat_motion.sh` (new) | **63/63** checks pass. `--negative=contact` (blade rendered 0.06 s late) fails the contact and hit-volume checks in both scenes. `--negative=hold` (holds removed) fails `loaded_hold_is_visible_*`. Close-up captures from two cameras in both courtyards. |
| `test.sh` | Passed. Covers the rules baseline trace (532), combat (118) plus 6 negative controls, adapter mutations, encounters, attack timing (headless and rendered; blade in the volume on every active tick, first contact at 2.35 m) and graphical (111). |
| `test_presentation.sh` | Passed. Covers 319+ pose and rules-isolation checks and both reaction mutations. |
| `test_marrow.sh` | Passed. Covers the shared lunge and the rendered bone tip on the rule reach during the inherited lunge. |
| `test_builds.sh`, `test_anatomy.sh`, `test_worldgen.sh`, `test_camera_zoom.sh`, `test_animation_lab.sh` | Passed (137, 190, 80 checks; zoom; 76 lab checks plus its negative control). |
| `test_web.sh` | **Not run.** Export templates and the browser setup were not installed in this session. |
| Cost | `sync_visual` takes **~140 µs** per fighter per physics tick, against ~23 µs on main (headless, same 4-vCPU cloud machine, 3,200 attack ticks, mean of three runs). That is about 0.3 ms per tick for two fighters, mostly the trail re-sampling 12 poses. No optimisation was attempted; profile on the web export before adding more fighters. |

New checks cover:
- Rule boundaries land on the markers for windups of 0.34, 0.62, 0.85 and 0.7 (lunge).
- Every ACTIVE sample keeps the tip in the volume above 1 m.
- The blade stays out of the volume during the committed hold.
- The hold decelerates into `loaded` and moves far less than release.
- The mirror is an exact reflection.
- Two-bone IK keeps limb lengths: legs exact, arms stretch less than 0.12 m.
- The glint appears only during *committed*; the trail only from release to 0.1 s after ACTIVE.
- A dodge cancel clears the trail.
- A hit snaps the chest and shows the streak, then both expire.
- A poised heavy's blade does not move when hit.
- Guard raise eases, then settles exactly.
- Rendering never changes rules.

## Evidence

See [evidence](evidence/combat-presentation-4/README.md). The before and after renders
come from the same capture script (`combat_motion_capture.gd`, which also runs unchanged
on main), the same cameras and the same rule ticks.

## Limitations and open questions

- **Human playtest needed.** Recognition at real distance and speed, whether the glint or
  trail over-teaches the timing, and whether the 0.08 s guard crossfade feels laggy.
  Deflection timing itself is unchanged.
- The courtyard light windup leaves *early* only 0.10 s for the player's light attack. The
  gather is necessarily quick; the hold carries the read. The lab's conclusion stands:
  real timing needs authored clips.
- Still primitives. The locomotion cycle is unchanged (feet can slide while moving).
  Death is still an instant topple, because existing fixtures require it on the first
  frame. The trail is in character space, so it turns with a steering attacker. The hit
  streak faces the attacker, so it is mostly hidden from the over-the-shoulder camera when
  the player is struck; the body snap carries that read.
- The attacker gets no blade rebound when its strike is merely blocked (only on deflect).
  Adding one would move the blade inside ACTIVE and needs a separate decision.
- No audio, hitstop or camera shake. These were deliberately left out because they alter
  perceived timing.

## Integration notes

- New files live under `scripts/characters/presentation/`. The only modified runtime file
  is `fighter_visual.gd`. Game code now preloads the lab's pure `phase_warp.gd`; if the lab
  directory is ever removed, move that file rather than deleting it.
- No scene, roadmap, export preset or data file changed. Codex's expedition branch should
  merge cleanly unless it edits `fighter_visual.gd`.
