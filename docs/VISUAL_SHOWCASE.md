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

**Renderers.** The project stays on **GL Compatibility** (browser-safe; `project.godot`
untouched). The showcase also runs on **Forward+** when started with
`--rendering-method forward_plus` (`play_visual_showcase.sh --forward`); nothing is
saved. What Forward+ adds here: volumetric fog with light shafts from the moon and
braziers, SSAO, SSIL (high), cheaper many-light shading (clustered) and better
positional shadows. Compatibility has no SSAO/SSIL/volumetric fog; the showcase
substitutes depth + height fog, additive fog cards and a fake shaft mesh, and limits
shadowed positional lights to one. Side-by-side: `docs/evidence/visual-showcase/forward_vs_compat_*.jpg`.

**Measurement conditions — read before the numbers.** This cloud container has **no
GPU**. Both renderers ran on **CPU software rasterisers**: Mesa *llvmpipe* (OpenGL) for
Compatibility and Mesa *lavapipe* (Vulkan, installed only inside the throwaway
container) for Forward+, on 4 cores of an Intel Xeon @ 2.80 GHz, Xvfb 1280×720,
Godot 4.7.2. Frame times below therefore measure *CPU pixel-shading cost* and only
rank configurations against each other; **they are not desktop GPU frame times** and
must not be read as "the showcase runs at 1–7 fps". Draw calls, primitives, node and
mesh counts, triangle counts and memory are renderer facts and do carry over.
Command: `bash scripts/tooling/bench_visual_showcase.sh` (same seeded AI duel, 60
warm-up + 240 measured frames per case, then 120 frames with every shadow off).
Raw data: `docs/evidence/visual-showcase/bench_gl_compatibility.json`, `bench_forward_plus.json`.

GL Compatibility (llvmpipe):

| Case | Frame ms mean | p95 | No-shadow ms | Shadow cost ms | Draw calls | Primitives | Nodes | Meshes | Lights / shadowed | Static MB | Video MB | Texture MB | Startup ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Melee lab (before) | 66.8 | 78.2 | 41.8 | 25.0 | 188 | 60,750 | 94 | 62 | 1 / 1 | 47.4 | 19.5 | 13.1 | 136 |
| Showcase low | 142.6 | 165.9 | 136.4 | 6.2 | 189 | 228,027 | 255 | 58 | 4 / 1 | 51.1 | 32.8 | 23.5 | 7,482 |
| Showcase medium | 399.2 | 445.2 | 362.2 | 37.0 | 196 | 228,560 | 267 | 62 | 8 / 1 | 51.4 | 61.9 | 52.6 | 10,006 |
| Showcase high | 615.4 | 682.2 | 330.9 | 284.5 | 256 | 567,702 | 267 | 62 | 8 / 2 | 51.6 | 80.9 | 71.7 | 9,595 |

Forward+ (lavapipe):

| Case | Frame ms mean | p95 | No-shadow ms | Shadow cost ms | Draw calls | Primitives | Nodes | Meshes | Lights / shadowed | Static MB | Video MB | Texture MB | Startup ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Melee lab (before) | 76.7 | 94.2 | 58.3 | 18.4 | 194 | 63,041 | 91 | 61 | 1 / 1 | 60.8 | 144.8 | 56.9 | 420 |
| Showcase low | 184.2 | 206.5 | 159.1 | 25.1 | 195 | 227,985 | 255 | 58 | 4 / 1 | 65.9 | 121.7 | 31.0 | 21,054 |
| Showcase medium | 440.3 | 483.1 | 385.0 | 55.3 | 198 | 228,481 | 263 | 58 | 8 / 1 | 66.2 | 183.8 | 93.1 | 11,202 |
| Showcase high | 919.3 | 1,054.8 | 741.0 | 178.3 | 302 | 906,235 | 263 | 58 | 8 / 3 | 66.8 | 327.5 | 234.0 | 34,670 |

Scene content (all presets): environment **54,808 triangles** in one merged mesh
(108 pieces, 8 surfaces: one per material); characters **15,524 triangles** together for the
default pair (pilgrim in mail + soul in cloth with the Marrow Arm; the heaviest
configurations, plate, are 10,434 (pilgrim) and 10,572 (soul) — the < 20,000 per
character budget check passes for all 12 body × armor × arm configurations); weapons **1,948**; 5 skinned meshes with
**9,660 skinned vertices** (GPU skinning). **Draw calls stay at the lab's level**
(≈ 190–200 low/medium; 256–302 high, where extra shadow passes appear) because
architecture and characters merge per material. *Primitives* include shadow passes.

**Animation / skinning cost.** The pose layer (rules tick + solve, both measured
together) costs **111–135 µs per character per frame** on this CPU (≈ 0.25 ms per frame
for the duel); the reach-assist bisection is the largest part. Skinning runs on the
GPU and could not be separated on a software rasteriser.

**Startup** includes procedural texture generation when the size is not cached yet
(0.7–2.6 s of it here) and first-frame shader compilation (most of the rest on a
software renderer). Later launches load the cached textures.

**Where the time goes (relative, software).** Low → medium is mostly four more
point lights, 2× MSAA and twice the texture size; medium → high is positional-light
shadows (Compatibility: +285 ms shadow cost — omni shadows are six cube faces) and,
on Forward+, SSIL and full-resolution volumetric fog.

**Proposed presets (provisional; to be confirmed on real hardware with this same
benchmark):**

| Tier | Example hardware (estimate, not measured) | Renderer | Preset | Notes |
| --- | --- | --- | --- | --- |
| High-end PC | Discrete GPU, GTX 1660 / RX 5600 class or better | Forward+ | `high` | Volumetric fog, SSAO + SSIL, 4096 shadows, two shadowed braziers, 4× MSAA |
| Mid-range PC | GTX 1050 Ti class, or recent integrated (Iris Xe, Radeon 680M) | Forward+ | `medium` | Volumetric fog, SSAO, no SSIL, no positional shadows, 2× MSAA |
| Low-end PC / browser | Older integrated GPUs, WebGL2 | Compatibility | `low` | Depth fog only, 1024 shadows, no torches or MSAA, 128 px textures |

The preset table lives in one place (`scripts/visual_showcase/quality.gd`) and is not
connected to any production setting.

## 8. Tests and evidence

```sh
bash scripts/tooling/test_visual_showcase.sh artifacts/visual-showcase      # ≈ 45 min here (rendering is software)
BONESHED_SKIP_RENDER=1 bash scripts/tooling/test_visual_showcase.sh artifacts/vs-fast   # headless parts only
bash scripts/tooling/bench_visual_showcase.sh artifacts/visual-showcase-bench
```

The runner parse-checks every showcase script, runs `visual_showcase_tests.gd`
(**49 checks**) and replays it in a second process (results byte-identical), runs three
**source mutations in a disposable copy** (each must fail its named check), renders the
evidence in GL Compatibility (llvmpipe) and, when a Vulkan driver exists, Forward+
hero shots (lavapipe), encodes contact sheets and MP4s, and fails if a protected
production, lab, shared-data or coordination file differs from `origin/main`.

| Area | Checks (all passing) |
| --- | --- |
| Rig integrity | 22 bones, parents before children, every bone aims at its tail, mirror symmetry, skeleton rest = definition, every socket on an existing bone (both bodies); human proportions (pilgrim); soul taller and longer-armed |
| Skin | 4 normalised influences per vertex and valid bone indices on every layer of all 12 configurations; < 20,000 triangles per character; plate surfaces bound to a single bone; layers match equipment |
| Weapon / contact agreement | Each weapon mesh ends at exactly the rules length; over 11,700 solved poses the drawn weapon equals the rules segment (max 2.5e-7 m); in the engine (after the `SkeletonModifier3D`, through `BoneAttachment3D`) the grip socket is on the rules hand (5e-7 m) and the tip marker on the rules tip (3e-7 m) |
| Weapon / hand alignment | Right fist on the grip for 3 weapons × 2 bodies × all attacks, guards and a redirect (< 5 mm; measured 0.0); second fist on the hilt whenever reachable (< 1 mm, 70 % of greatsword ticks); arm stretch never above 1.0 |
| Directional chambers | Real mouse input: hold right chamber, flick left → the rules route through the forward neutral, the drawn tip never goes behind the body (max tip z 0.41 m), fist stays on the grip, the released cut is the aimed side |
| Guard / dodge / roll | Edge faces each of five guard sectors; held guard lowers the stance; dodge shifts the body toward the dodge with the weapon exact; roll tumbles the body and the weapon is free only during ROLL |
| Hits, posture, death | Kick recoils and settles; posture lowers the stance; death drops the body and lands the weapon |
| Equipment swapping | All 12 weapon × armor selections derive the same rules state as resolving the same items directly; armor layers follow the selection; no node leak; greatsword + Marrow Arm rejected by `BuildRules`; Marrow Arm module attached when equipped |
| Combat outcomes | Byte-identical contact logs vs the melee lab (16 contacts, three pairings, scripted player + seeded AI) |
| Environment data | Showcase and layout data valid; crypt assembly deterministic; duel floor free of collision |
| Isolation | Default scene and project renderer unchanged; no game or lab script references the showcase |

| Mutation (disposable copy) | Caught by |
| --- | --- |
| Weapon drawn 5 cm off the rules hand | `drawn_weapon_equals_rules_segment_every_tick`, `engine_weapon_tip_on_rules_tip` |
| Fist aimed 5 cm off the grip | `right_fist_on_grip_all_weapons_directions_guards`, `engine_grip_socket_on_rules_hand` |
| Presentation writes rules state (`omega *= 0.97`) | `combat_outcomes_identical_to_melee_lab` |

Regression suites run on the final code of this branch (same machine, all passed):
`test.sh` (production courtyard: combat, adapter mutations, encounters, timing,
graphical 111 checks — run with `BONESHED_GRAPHICAL_TIMEOUT=900` because its default
180 s graphical limit expired on this software renderer while still passing),
`test_melee_lab.sh` (90 + 73 checks, replays, negative controls, 23 rendered clips, its
isolation guard), `test_directional_expedition.sh` (94 fixtures, five playthroughs,
trace equality, four mutations), `test_expedition_preview.sh`, `test_builds.sh` (205
checks).

Evidence (curated): [`docs/evidence/visual-showcase/`](evidence/visual-showcase/README.md) —
before/after pairs, character and equipment close-ups with the contact-segment overlay,
crypt shots, Forward+ shots, clips (MP4 + contact sheets), test results, contact logs
and benchmark JSON.

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

Stated plainly, so the owner can judge the gap rather than infer it from screenshots:

- **Faces and heads.** Sculpted from deformed spheres with baked crease shading; no
  real eyes, lips, hair or facial animation. They are hidden by hood, face-wrap, coif or
  helm on the pilgrim and stylised as a skull on the soul — a deliberate way to avoid a
  face pipeline, not a solution. Close-ups expose it.
- **Anatomy is tube-and-blob.** Limbs and torso are lofted cross-sections: no muscle
  definition, collarbones, knuckles or fingers (the fists are closed shapes), and
  joints are simple linear-blend skinning (some candy-wrapper at extreme elbow twists).
  Proportions are believable at gameplay distance; silhouettes are still "mannequin".
- **Cloth and mail are rigid lofts skinned to bones**, not simulated: no folds, no
  secondary motion, skirts only follow the thighs. Banners do not move.
- **Animation is procedural.** Gait, trunk wind-up, hit reactions, roll and death are
  springs and IK, not authored motion: no anticipation poses, no foot-roll, no
  hand-keyed weight. It is readable and honest to the rules, but it is not the
  "authored weight and follow-through" the animation research recommends. Locomotion
  feet can slide during fast turns; there is no foot locking.
- **Weapon lengths are the lab's.** The 1.8 m Notched Sword looks like a greatsword
  (§3); only a design decision fixes that.
- **Second hand releases** on the greatsword in ~30 % of sampled ticks (wide guards,
  cut endings) — visible when it happens.
- **Textures are procedural noise** at 128–512 px: convincing at gameplay distance,
  flat up close; tiling is visible on large walls; no decals, dirt masks, moss or
  vertex-painted wear.
- **Lighting in Compatibility** relies on fake shafts, fog cards and a fill light; light
  leaks through ceiling joints draw bright floor patches. Forward+ looks clearly better
  (volumetric fog, SSAO), at a GPU cost not measured on a GPU here.
- **No audio, no camera polish** (the lab's camera, unchanged), no hit-stop, no blood
  or damage decals, no corpse persistence beyond lying on the floor.
- **Performance is unmeasured on a GPU.** All frame times are software rendering; the
  preset tiers are estimates.
- **Desktop only.** Not exported to the browser; texture generation would be slower in
  WebAssembly.
- **Owner feel is unknown.** No human has played it; nothing here claims the combat
  feels better or worse than the lab.

## 11. Owner playtest guide

1. `bash scripts/tooling/setup.sh`, then `bash scripts/tooling/play_visual_showcase.sh`
   (Compatibility). If the machine has a Vulkan GPU, repeat with `--forward`; try
   `-- --quality=high` and `-- --quality=low` too.
2. Fight the soul in its default duel mode (sword + cloth + Marrow Arm vs your sword +
   mail). Does the directional control feel **exactly** like the melee lab — held
   chambers, the forward-neutral re-chamber, release, fresh-press deflects, stamina?
   (It should: same code. Anything different is a bug.)
3. Watch the blade, not the HUD: is the edge glow + trail enough to read the incoming
   side, or do you want the lab's arcs (Y) and labels (U) back by default?
4. Switch weapons 1/2/3 and armor 4/5/6/0. Do the knife, sword and greatsword *look*
   light, medium and heavy in your hands and in the trunk's follow-through? Does plate
   look worth its weight?
5. Press K to remove/restore the soul's Marrow Arm; 7/8/9 change its weapon (9 is
   refused with the arm, by the shared grip rule). Is the arm readable as a left-arm
   modification?
6. Dodge (Space) and roll (Shift) near the soul; take hits; let your posture fill; win
   and watch the release. Which of these presentations helps you read the fight, and
   which distracts?
7. Note the camera, darkness and fog: too dark to fight? Is the crypt the right
   *direction* for the game's look?
8. Record: anything that looked wrong (weapon not in the hand, body through armor,
   jitter), the frame rate you see with each preset, and
   whether this direction should continue.

## 12. Recommendation for visual milestone 2

**Recommendation: keep the code-built rig, sockets, equipment contract and modular
room format from this milestone, and replace the procedural *art* with an authored
pipeline for one character family — the step this milestone could not take here.**

1. **One authored humanoid (Blender → glTF), same 22-bone names and sockets** so it
   drops into `humanoid_rig.gd`'s contract and the tests (rig, sockets, fist-on-grip,
   drawn weapon = contact segment) keep guarding it. Sculpted face/hands, proper
   topology for deformation, baked normal/AO. Owner decision needed: commission or
   in-house artist, and an asset-licence policy (AGENTS.md).
2. **Authored combat poses as data, timed by the rules**: keyed chamber/guard poses per
   direction and weapon class blended with the existing IK so the fist stays exact,
   plus authored locomotion, hit and death clips (the animation research's
   AnimationTree plan). Keep procedural IK only for the grip, off hand and feet.
3. **Decide weapon lengths** (§3) before authoring weapons, so the art matches reach.
4. **Measure on real hardware**: run `bench_visual_showcase.sh` on two or three owner
   machines and fix the preset table from data; decide whether Forward+ becomes the
   desktop renderer (Compatibility remains for the browser).
5. **Environment**: a small authored trim-sheet + decal set for the same crypt pieces,
   and the first generator that emits `crypt_layout.json` from a seed (the format and
   determinism test already exist).
6. Only after the owner accepts the look: bring the presentation into the directional
   expedition behind a toggle, and consider the browser export.
