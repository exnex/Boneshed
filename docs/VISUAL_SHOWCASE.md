# Visual quality milestone 1 — character, gear and dungeon showcase

**Status: experimental, isolated, separately selectable scene awaiting Command Center
review and owner evaluation.** Owner authorization: [NEXT_DEVELOPMENT_PLAN.md — "Owner
authorization: first visual quality and scalable content milestone", 2026-10-21](NEXT_DEVELOPMENT_PLAN.md).
Nothing here changes the default scene (`first_expedition.tscn`), `project.godot`,
`export_presets.cfg`, the Pages workflow, the melee lab, the directional expedition or
any production rule. Every visual choice, preset and number below is **Proposed** and
provisional; it is not an approved art direction or asset policy. This is a credible
first step toward a dark, atmospheric presentation — it is **not** AAA art, and
automated runs say nothing about how combat *feels*.

Engine: Godot **4.7.2.stable.official.ed1daf0bf** (checked by the tooling). Default
renderer GL Compatibility (unchanged); Forward+ only per run, via a command-line flag.
Built 2026-10-21.

| Section | |
| --- | --- |
| [1. Play](#1-play) | Commands, keys, what to look at |
| [2. What was built](#2-what-was-built) | Scene, characters, rig, equipment, crypt |
| [3. Combat contract: drawn weapon = contact segment](#3-combat-contract-drawn-weapon--contact-segment) | The mapping and its tests |
| [4. Animation and presentation](#4-animation-and-presentation) | Pose layer, chambers, guard, dodge, roll, hits, release |
| [5. Equipment](#5-equipment) | Weapons, armor, Marrow Arm, swapping |
| [6. Environment](#6-environment) | Modular kit, layout data, lighting, fog |
| [7. Rendering evaluation and benchmarks](#7-rendering-evaluation-and-benchmarks) | Compatibility vs Forward+, numbers, presets |
| [8. Tests and evidence](#8-tests-and-evidence) | Commands, results, images, clips |
| [9. Provenance](#9-provenance) | Where every asset comes from |
| [10. What is still crude](#10-what-is-still-crude) | Honest gap list |
| [11. Owner playtest guide](#11-owner-playtest-guide) | |
| [12. Recommendation for visual milestone 2](#12-recommendation-for-visual-milestone-2) | |

## 1. Play

```sh
bash scripts/tooling/setup.sh                                   # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/play_visual_showcase.sh                    # GL Compatibility (the project's renderer)
bash scripts/tooling/play_visual_showcase.sh --forward          # Forward+ for this run only (needs Vulkan)
bash scripts/tooling/play_visual_showcase.sh -- --quality=low   # presets: high · medium · low
```

In the editor, open `scenes/visual_showcase.tscn` and press **F6** (F5 still runs First
Expedition). The first launch generates and caches its procedural textures under
`user://showcase_textures/` (≈ 2–4 s on this machine); later launches load the cache.
The scene is **desktop-only for now**: it is not exported to the browser and the Pages
workflow is untouched (adding it is one workflow step once the owner wants it).

**Controls** — the melee lab's approved controls, unchanged (same `lab_player.gd`,
`lab_input.gd`, `lab_opponent.gd`): LMB press/hold + mouse to chamber (held
indefinitely, re-chamber through the forward neutral), release to cut; RMB hold + mouse
for directional guard (fresh press = deflect window); Space dodge step; Shift roll; Tab
lock-on; R reset; F1 lab help; F2 handling table; F3 hit segments; T trails; Y
telegraph arcs; U labels; M soul AI mode; G dummy guard. Showcase additions (raw keys,
no input-map changes):

| Key | Showcase action |
| --- | --- |
| 1 · 2 · 3 | Pilgrim weapon: light (Long Knife) · medium (Notched Sword) · heavy (Greatsword) |
| 4 · 5 · 6 · 0 | Pilgrim armor: cloth wraps · mail shirt · bog-iron plate · none |
| 7 · 8 · 9 | Soul weapon: light · medium · heavy |
| O | Cycle the soul's armor |
| K | Toggle the soul's Marrow Arm |
| L | Hide/show the showcase legend |

Changing equipment starts a fresh duel, exactly as the lab's loadout keys do.
Presentation defaults differ from the lab in one way: the lab's telegraph **arcs (Y)**
and **text labels (U)** start *off*; the real blade's edge glow (same colours and phase
logic as the lab's blade colouring) and a thinner trail carry the telegraph. Both lab
overlays are one key away.

## 2. What was built

```
scenes/visual_showcase.tscn → scripts/visual_showcase/showcase.gd  (extends melee_lab.gd)
  ├ crypt_builder.gd   data/visual_showcase/crypt_layout.json → one merged static mesh, box collision,
  │   └ crypt_kit.gd   lights from piece sockets, fog, fire, dust, contact sparks; quality.gd presets
  ├ material_library.gd   procedural PBR texture sets (albedo, normal, roughness, emission), cached
  └ per duelist: showcase_visual.gd (extends lab_visual.gd; replaces the capsule visual)
        ├ character_builder.gd  body + armor layers + Marrow Arm module, skinned to
        │     humanoid_rig.gd   the reusable 22-bone rig with 8 sockets
        ├ weapon_builder.gd     weapon meshes whose tip is the rules tip
        ├ pose_solver.gd        rules state → model-space pose (pure maths, deterministic)
        └ pose_modifier.gd      SkeletonModifier3D that writes the pose to the skeleton
```

`showcase.gd` overrides only presentation and selection: `_build_arena` (the crypt),
the visuals, `_record`/`_marker` (contact reports also reach the visuals and spawn
sparks) and extra hotkeys. Controllers, rules state, AI, stamina, statuses, the step
order and the contact solver are the lab's, unmodified. The only lab file touched is
`scripts/qa/melee_lab_tests.gd`, whose isolation allowlist (`LAB_CONSUMERS`) now names
the showcase as an authorized consumer, as it already names the directional expedition.

**Characters.** One player (the *pilgrim*) and one *corrupted soul*, built at load from
original procedural geometry (lofted, skinned limbs and torso; sculpted head blobs with
baked crease shading; fists closed around the grip; boots; hood or coif with a cloth
face-wrap). The soul uses the same rig with different proportions: taller, gaunt,
long-armed and hunched, ash-grey cracked skin with glowing veins, a skull face with lit
sockets and a bare mandible, ribs and spinal spurs, tattered shroud and skirt.

**Rig.** `humanoid_rig.gd`: 22 bones with UE-style names (`pelvis`, `spine_01..03`,
`neck_01`, `head`, `clavicle_*`, `upperarm_*`, `lowerarm_*`, `hand_*`, `thigh_*`,
`calf_*`, `foot_*`, `ball_*`) — the naming the [animation pipeline research](ANIMATION_PIPELINE.md)
recommends, so a future Blender/glTF rig can replace it without renaming. Each bone's
+Y aims at its child. Sockets (`BoneAttachment3D` → `Marker3D`): `grip_r`, `grip_l`,
`head`, `chest`, `back`, `hip_l`, `hip_r`, `forearm_l`. Proportion presets: pilgrim
1.815 m (arm/stature 0.309, leg/stature 0.518); soul 1.885 m.

## 3. Combat contract: drawn weapon = contact segment

The contact solver tests the segment **hand → hand + dir × length** of the rules pose
(`swing_geometry.gd`, `contact_solver.gd`). The showcase keeps the lab's rule — *the
drawn weapon is the hit segment* — and adds a body that follows it:

1. The weapon node is placed at the rules pose (`hand`, `dir`) every frame. Its mesh is
   built so the tip is exactly `z = −length` of the rules handling; nothing is scaled.
   Only the blade's roll about its own axis is a presentation choice (the edge faces
   the swing plane or the guarded side); a segment has no roll, so contact cannot see it.
2. The right fist is put **on** that grip by two-bone IK (wrist beside the grip,
   knuckles perpendicular to the handle). When the grip lies beyond the arm, the trunk
   lunges/leans (≤ 0.16 m step, ≤ 0.5 rad), turns (≤ 0.9 rad, whichever way helps) and
   the clavicle protracts — each by the smallest amount that suffices (bisection).
   Result over 11,700 sampled poses (3 weapons × 2 bodies × 6 attacks, 6 guards and a
   redirect, every tick): **fist-to-grip error < 0.005 m, zero arm stretch**.
3. **Exceptions, stated:**
   - **Roll and death.** The solver ignores an evading fighter's weapon and a dead
     fighter's, so during ROLL the blade rides in the tumbling fist and during DEAD it
     falls to the floor. The roll is back on the rules pose from its first tick after
     ROLL (tested: `weapon_free_only_during_roll`).
   - **Two-handed second hand.** The lab draws its second hand 0.2 m *toward the blade*;
     at the end of a cross-body cut that point is ~0.9 m from the left shoulder, beyond a
     human arm. The showcase uses the anatomical pommel-side grip (0.2 m behind the
     primary fist) and, where even that is out of reach (wide right-side guards, some
     cut endings), the off hand reaches toward the hilt and lets go rather than
     stretching. Both hands are on the hilt in 70 % of sampled greatsword ticks.
   - **The hilt behind the primary fist** (≈ 0.09 m on one-handers, ≈ 0.27 m on the
     greatsword's two-hand grip) is drawn but is not part of the contact segment —
     exactly as the lab's own pommel is not.
   - **Body vs hurt capsule.** The hurt capsule (radius 0.32 m) never moves; the drawn
     trunk leans and lunges inside it (maximum horizontal offset of pelvis/spine bones
     0.274 m, tested), the head and limbs may leave it — as the lab's capsule figures'
     arms already did.
4. **Outcomes unchanged.** The same scripted exchanges (three loadout pairings, swings,
   guard, roll, thrust; the soul's seeded AI in duel mode) produce **byte-identical
   contact logs** in `melee_lab.tscn` and `visual_showcase.tscn`, with a processed frame
   between ticks so the presentation runs as in play (16 contacts compared). A mutation
   that lets the presentation touch rules state is caught by this check.

**A design finding, not a change:** drawn truthfully, the lab's Notched Sword (rules
length **1.8 m** from the fist) is about 1.8× a real arming sword and reads like a
greatsword; the knife (0.9 m) is a short sword and the greatsword (2.1 m) is close to a
real two-hander. If the owner wants believable one-handed swords, weapon lengths (and so
reach) need a design decision; the showcase does not alter them.

## 4. Animation and presentation

`pose_solver.gd` is a pure function of a read-only view of the rules state (phase,
hand, dir, direction, guard, handling inertia, velocity, dodge direction, roll/dodge
progress, posture) plus its own springs; `pose_modifier.gd` (a `SkeletonModifier3D`
using `_process_modification_with_delta`, as the engineering guide requires for
procedural layers) writes the resulting bone transforms. Nothing in it feeds back.

| Situation | What the body does (presentation only) |
| --- | --- |
| Idle / locomotion | Fighting stance (left foot leads), breathing-free settle; procedural gait from velocity (stride, foot lift, pelvis bob, lean into motion), leg IK, feet follow hip yaw |
| Chambers (held indefinitely) | The blade is where the rules hold it; the hips and then the chest wind toward the hand (hips lead), the off hand counterbalances |
| Left/right switching | The rules route the hand through the forward neutral; the body follows the same path (tested with real mouse input: the tip never passes behind the body) |
| Held guard | Lower, wider stance; the edge faces the guarded side (tested for all five sectors) |
| Swings | Weight transfer forward, trunk unwinds; **weapon mass**: trunk springs are softer for heavier weapons (1.7–3.2 Hz), so a greatsword drags the body through and settles later |
| Dodge step | Lean and hip shift toward the dodge, crouch |
| Roll | Full tumble about the roll axis (tucked), then the weapon returns to the rules pose |
| Hit / block / deflect / clash | An impulse spring pushes the trunk and head away from the blow (scaled by outcome) and settles; a red flash overlay on hits |
| Posture damage | Stance sinks and hunches as posture fills; guard break doubles the fighter over |
| Death / release | Knees buckle, the body falls to the side away from the blow, the weapon slips and lands; the corrupted soul's light fades and pale wisps rise from it |

Directional control is never replaced by canned clips: every attack, chamber, redirect
and guard is the player's aimed rules pose. Stamina, momentum, timings and input
responsiveness are the lab's; the presentation adds no delay to anything.

## 5. Equipment

All selections are existing data, resolved through the lab adapter (`lab_loadout.gd` →
`BuildRules`) exactly as the lab's own loadouts: `data/visual_showcase/showcase.json`
only names which shared items and lab armor ids the keys combine. No item, slot,
balance value or inventory rule was added.

| Visual set | Data | Look |
| --- | --- | --- |
| Light weapon | `item.lab_long_knife` (0.9 m, 0.7 kg) | Seax-profile single-edged blade, small guard |
| Medium weapon | `item.notched_sword` (1.8 m, 1.4 kg) | Long hexagonal-section blade with fuller and notches, bronze quillons |
| Heavy weapon | `item.lab_greatsword` (2.1 m, 3.0 kg, two-handed) | Wide blade, ricasso and parrying lugs, long two-hand grip |
| Armor A | `armor.lab_cloth_wraps` | Robe tabard and tattered skirt, arm and shin wraps, sash, hood |
| Armor B | `armor.lab_mail_shirt` | Skinned hauberk with sleeves and skirt, mail coif, gambeson collar, belt and pouch |
| Armor C | `armor.lab_bog_iron_plate` | Breastplate, lames, fauld, layered pauldrons, couters, vambraces, gauntlets, cuisses, poleyns, greaves, sabatons, gorget, great helm (rusted variant on the soul, with a crown band instead of a helm) |
| Marrow Arm | `item.marrow_arm` in `arm_l` (shared catalog) | The soul's left arm becomes split bone: humerus, radius/ulna, spurs, three-talon claw, glowing marrow cracks |

The shared grip rule still applies: a two-handed greatsword beside the handless Marrow
Arm is rejected by `BuildRules` and the previous selection stays (tested). In the
showcase the Marrow Arm is shown, not used: its lunge lives in the directional
expedition (`expedition_state.gd`) and is not wired into this scene.

**Attachment and deformation strategy.** Each character is three or four skinned layers
(body, armor, module) bound to one `Skin`; the weapon is a separate rigid node. Skin,
cloth and mail blend neighbouring bones (shoulder, elbow, waist, knee; skirts split
their weights by side between pelvis and the matching thigh). Every plate, buckle, bone
piece and helm is bound **100 % to one bone** so hard surfaces never bend (tested). One
draw call per material per layer.

## 6. Environment

A ruined ossuary nave, 16 × 20 m, built from **17 reusable piece types** on a 4 m grid
(`crypt_kit.gd`): flagstone floor tile (individual slabs, cracks, broken variant), wall
(plain / ossuary niche with skull shelves / collapsed), doorway with portcullis,
clustered pier (plain / snapped), arcade arch and transverse rib (wedge voussoirs),
ceiling slab (plain / collapsed opening), dais, sarcophagus with effigy, brazier,
candles, fallen column, rubble, bones, banner, chain and sconce. The room is **data**:
`data/visual_showcase/crypt_layout.json` lists 108 placed pieces (`piece`, `at`, `rot`,
`variant`, `seed`, optional `y`). Every piece uses its own seeded RNG, so the same file
always builds the same room (tested); a future dungeon generator only needs to emit the
same list. All pieces merge into **one static mesh with one surface per material**.

Lighting: a cold moon through the collapsed ceiling (shadowed directional light), a
shadowless moon-bounce fill on the duel floor, two flickering braziers (shadowed on
high/Forward+), four torch sconces, emissive candles; AgX tonemapping, glow, depth and
height fog. Compatibility uses additive fog cards and a fake light shaft; Forward+ uses
volumetric fog (god rays through the opening), SSAO and (high) SSIL. The duel floor is
kept clear: no collision within 4 m of the duel centre (tested).

## 7. Rendering evaluation and benchmarks

BENCHMARK_SECTION

## 8. Tests and evidence

TESTS_SECTION

## 9. Provenance

Every mesh, texture, material, particle and light in the showcase is **generated by code
in this repository** (`scripts/visual_showcase/*.gd`) from Godot built-ins
(`SurfaceTool`, `FastNoiseLite`, `Image`, `StandardMaterial3D`, `CPUParticles3D`). No
image, model, sound, font, shader library or animation file was imported, downloaded or
adapted; no third-party asset, paid asset or new dependency was added. The procedural
textures cached under `user://` are regenerated from the committed code and are not
committed. Godot 4.7.2 itself is MIT-licensed. The only environment change was
installing Mesa's `mesa-vulkan-drivers` (lavapipe) **inside the throwaway cloud
container** to render Forward+ evidence; nothing in the repository depends on it.

## 10. What is still crude

LIMITATIONS_SECTION

## 11. Owner playtest guide

PLAYTEST_SECTION

## 12. Recommendation for visual milestone 2

RECOMMENDATION_SECTION
