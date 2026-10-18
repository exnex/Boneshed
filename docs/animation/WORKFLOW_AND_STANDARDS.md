# Character workflow (concept → Blender → Godot) and rig/animation standards

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). Everything here is
**Proposed**: it becomes a project standard only after human approval. Items marked
*(lab-verified)* were exercised by the animation lab on Godot 4.7.2. Everything else is
recommended practice that has not been tested here.

## 1. Workflow

| Step | Owner | Output | Gate |
| --- | --- | --- | --- |
| 1. **Concept and combat brief**: silhouette, weapon, body family, list of moves with *rule* timing (windup/active/recovery from the build catalog) | Design (human) | One page per character plus a move list | Moves exist in the build catalog |
| 2. **Blockout mesh** at game scale (1 unit = 1 m), facing −Y in Blender (exports as +Z, as the trial asset does) | Artist / AI-assisted | `.blend` | Silhouette readable at duel distance (screenshot at 6 m) |
| 3. **Rig**: Rigify (or Mesh2Motion fit for quick tests) as the *control* rig. Generate a clean *deform* rig with the [family bone names](#2-skeleton-standard). Game Rig Tools and RigPort are add-ons that do this (vendor-reported). Plain Rigify deform chains are split and export badly | Rigger | Control + deform rig | Bone names and rests pass the import check (see step 7) |
| 4. **Skin**: automatic weights, then hand-paint shoulders, hips, wrists and the weapon hand; test the deformation poses in §4 | Rigger | Weighted mesh | Deformation sheet rendered (see §4) |
| 5. **Animate** on the control rig. Key **poses first** (anticipation, loaded, contact, follow-through, settle), then breakdowns, then spacing | Animator (human) | Actions per move | Timing review against the rule durations |
| 6. **Bake** to the deform rig (Rigify/GRT "bake action"), one action per clip, named `family__move` (e.g. `humanoid__slash_light`). Loops end in `_loop` (Godot sets the loop flag for `loop`/`cycle` tokens) | Animator | Baked actions | No end-frame pop (checked in step 7) |
| 7. **Export glTF 2.0** (`.glb`): +Y up, apply transforms, deform bones only, sampling at 30 fps, no Draco (Godot cannot read Draco). Then **import into Godot** with an `EditorScenePostImport` script that applies the clip manifest | Tech art / agent | `.glb` + manifest | Automated import checks (see below) |
| 8. **Markers and data**: author combat markers in the manifest (§3), bake the weapon trace, record known defects | Animator + agent | `clip_manifest.json`, baked traces | Lab-style tests pass |
| 9. **In-engine review**: render the move with the lab director (overview, timing, close-up) next to the rule timeline | Human | Clips | Human sign-off; automated checks cannot judge feel |

**Automated import checks** *(lab-verified as tests)*: expected bone count and names;
every manifest clip present; loop flags; markers embedded; in-place clips hold the root;
loop seam gap < 2 cm unless declared as a defect; first frame of additive clips equals
rest; contact marker on the first live tick; blade not in front before the rule window and
in front for ≥ 80 % of it; trace reproducible.

Blender cannot carry timeline markers into glTF. Markers therefore live in the manifest
(JSON) and are written into `Animation` markers at import *(lab-verified:
`Animation.add_marker`)*.

## 2. Skeleton standard

- **One skeleton per body family.** The humanoid family uses the UE-style
  66-bone hierarchy the trial asset uses: `root → pelvis → spine_01..03 → neck_01 → head`,
  `clavicle/upperarm/lowerarm/hand_{l,r}`, five-finger chains,
  `thigh/calf/foot/ball_{l,r}`. It auto-maps to `SkeletonProfileHumanoid` by name (Godot
  docs: pattern-matched English names). That keeps editor retargeting available for
  third-party humanoid clips.
- **`root` at the floor between the feet**, no rotation, Y-up. In-place clips keep it fixed.
  Root-motion clips (`_rm`) translate it on the ground plane only.
- **Rest pose:** T- or A-pose consistently across the family. Do not mix: Godot needs both the
  bone names and the bone rests to match before clips can be shared (Godot retargeting docs).
- **Weapon socket:** add a `weapon_r` (and `weapon_l`) **prop bone** under each hand in
  production rigs, so a clip can animate the weapon's twist and grip slide. The lab used a
  `BoneAttachment3D` on `hand_r` with a grip offset, which is the fallback when a library
  rig has no prop bone.
- **Extra limbs are appended, never inserted:** `upperarm_l_low` etc. (suffix per pair),
  parented to the spine bone they emerge from. Existing bone indices stay valid and every
  family clip keeps working *(lab-verified: shared bones identical to < 0.1 mm)*.
- **Collision bones** for hurtboxes are the existing deform bones; do not add
  hitbox-only bones.

## 3. Animation standards

| Topic | Standard |
| --- | --- |
| Frame rate | Author at 30 fps; Godot interpolates. Sample at export; keep cubic/linear as authored |
| Units and scale | 1 unit = 1 m. Character height recorded in the manifest |
| Facing | Model +Z after import. The scene wraps the model in a node rotated 180° so gameplay forward is −Z *(lab-verified)* |
| Combat markers (per attack) | `start`, `loaded` (anticipation peak; begins the *committed* section), `release` (blade starts toward the target), `contact` (**first frame the blade enters the forward hit volume**), `active_end` (arc complete), `recovered` (back to a pose that blends into guard/idle). Names map 1:1 to CombatState stages (`early`, `committed`, `release`, `active`, `recovery`) |
| Pacing vs rules | Author so each section's **warp ratio** (clip seconds ÷ rule seconds) is between **0.67 and 1.5** at the rule timings that will play it. Outside that range, re-author: the trial clip needs 3.8× in its early windup, which reads as a twitch, not a telegraph |
| Telegraph | A visible *hold* at `loaded` of ≥ 4 frames, with the blade above or behind the body and out of the forward hit volume until `contact`. Silhouette must change from guard (blade raised, shoulder drawn back) |
| Recovery | Must reach a pose that blends into guard within the recovery window, and must not dip the blade into the floor (the trial slash ends 0.16 m above it) |
| Loops | First and last frames identical, root fixed; seam gap < 2 cm |
| Locomotion | Constant foot-contact speed during stance. Record the stride speed (the lab measures it automatically). Provide cycles near real play speeds (walk ~1, jog ~3, run ~5.5 m/s); the trial walk is 0.78 m/s |
| Hit reactions | Author an **additive** flinch (delta from its first frame) for light hits, and full-body clips for stagger, posture break, knockdown and death. Additive deltas apply on top of guard, idle or movement *(lab-verified)* |
| Root motion | Only for moves whose displacement *is* the move (dodge, lunge, knockback). Rules read the authored root curve as data |
| Naming | `family__move[_variant][_loop|_rm]`, ASCII snake case |
| Defect ledger | Known defects are recorded in the manifest (`known_defects`), and tests assert that the ledger matches measurements |

## 4. Deformation test poses (render each new rig)

Arms overhead (sword raised) · arm across the chest (guard) · full shoulder wind-back ·
deep lunge (hips and knee) · twisted torso 60° · wrist flexed with a blade. Look for candy-wrapper
forearm twist, collapsing shoulders and armpit tearing. A `BoneTwistDisperser3D`
modifier (4.6+, docs) or twist bones in the rig address forearm twist; untested here.
