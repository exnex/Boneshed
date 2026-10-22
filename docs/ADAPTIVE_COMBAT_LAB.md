# Adaptive Combat Lab 1 — structure-driven combat experiment

**Status: experimental, isolated, separately selectable scene. It is awaiting Command Center review and owner playtest.**
It implements the first playable proof that [ADAPTIVE_MORPHOLOGY_COMBAT.md](ADAPTIVE_MORPHOLOGY_COMBAT.md) asks for: in the
general-object form recorded in DECISIONS (2026-10-22), "Object-first improvised equipment".
Every number, threshold, archetype key, control and data shape below is **Proposed / provisional**. None of it is an
approved algorithm, balance, input map or content grammar. Automated runs show that the pipeline is consistent. They say
nothing about whether combat *feels* good.

Engine: Godot **4.7.2.stable.official.ed1daf0bf**. The tooling checks this version, and `bash scripts/tooling/setup.sh`
verifies it with a checksum. Renderer: GL Compatibility, the project default and unchanged. Built 2026-10-22.

**Unchanged:** `project.godot` and its default scene (First Expedition), `export_presets.cfg`, the Pages workflow and
browser builds, the directional expedition, Melee Lab, Visual Showcase, the animation lab, combat rules and shared
build data. The lab reuses the showcase's rig, character builder, mesh kit, pose modifier and materials **read-only**.

## 1. Play

```sh
bash scripts/tooling/setup.sh                       # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/play_adaptive_lab.sh           # GL Compatibility
bash scripts/tooling/play_adaptive_lab.sh --forward # Forward+ for this run only (Vulkan desktop)
bash scripts/tooling/play_adaptive_lab.sh -- --player=demo.ribbed_canopy --soul=demo.double_ended_pole --player-marrow
```

In the editor, open `scenes/adaptive_combat_lab.tscn` and press **F6**. F5 still runs First Expedition. The scene is
desktop-only for now: no browser export was added.

| Input (proposed) | Meaning |
| --- | --- |
| WASD | Move (camera-relative; the camera and facing lock onto the soul) |
| LMB / J | **Light**. Repeat late in a strike to chain three hits. |
| MMB / F / K | **Heavy** |
| RMB / L (hold) | **Guard**. A fresh press opens the object's deflect window. |
| Space | Dodge. Invulnerable from 0.04 to 0.3 s; recovery grows with carried mass. |
| 1–5 / 6–0 | Your object / the soul's object. The order is shovel-like, umbrella-like, pole, organic, awkward. |
| V / C (Shift: fresh seed) | Next seeded variant of your / the soul's object. Shift makes a brand-new unpredictable seed and shows it on the HUD. |
| B / N | Toggle your / the soul's **Marrow Arm**: the left arm becomes a handless bone limb. |
| G | Give your object another recipe's **label**. Behaviour must not change. |
| M | Soul AI: aggressive / defensive / passive dummy |
| R · T · F3 · F4 · H | Reset · trails · grip & contact overlay · slow motion · help |

The HUD lists, for each fighter, what the solver derived:
- the object's label (marked "UI only"), recipe, seed and **structural fingerprint**;
- the chosen hold;
- what Light, Heavy and Guard do, with the striking feature, damage channel and windup;
- why other moves are **not granted**.

## 2. Architecture

```
recipe + seed ─► object_generator.gd ─► descriptor (parts only; label is UI text)
                                          │            └──────────────► object_mesher.gd (drawn mesh, same numbers)
                                          ▼
                                   object_analysis.gd ─► mass, COM, inertia samples, grip candidates,
                                          │              contact features, covers, body-probe points
body id + mods ─► body_plans.gd ──────────┤
                                          ▼
                                 affordance_solver.gd ─► holds → feasible (archetype, feature) → timing/damage
                                          │              → motion validation → input map + rejection reasons
                                          ▼
                                 motion_library.gd  (authored archetype keys + procedural fitting)
                                          │  sampled at rule time by both ▼                  ▼
                    adaptive_fighter.gd (shared rules)            adaptive_actor.gd + adaptive_pose.gd
                    intent → state → contact sweep                 22-bone rig, two-bone IK onto grips
                          ▲            ▲
          adaptive_input.gd (player)   adaptive_ai.gd (soul) — both emit the same intent
```

| File | Layer | Role |
| --- | --- | --- |
| `data/adaptive_lab/objects.json` | data | Materials (density, hardness, visual id), five demonstration recipes with parameter ranges and seeds. **No moves.** |
| `data/adaptive_lab/bodies.json` | data | Body strength limits (inertia, torque, mass, wrist roll per one/two hands); the Marrow Arm modification (`removes_hands`). |
| `object_generator.gd` | generation | Primitive vocabulary: `rod`, `arc` (crook), `branch` (random-walk segments), `spike`, `plate`, `lump`, `membrane`. Seeded with one named stream: `hash(recipe:seed)`. |
| `object_analysis.gd` | measurement | Mass, centre of mass and point-mass inertia samples. Grip candidates: rods of graspable radius 12–26 mm with a hand's width (±40 mm) and 45 mm clearance. Contact features: spike **point** (sharpness = taper × hardness), plate **edges** (bevel × hardness) and **faces**, free rod **ends**, lump **mass**, folded-membrane **bundle**. Covers: membrane, plate, lump. |
| `body_plans.gd` | anatomy | Proportions (showcase rig presets), existing hands, arm length, grip-span limits, strength limits. |
| `affordance_solver.gd` | rules | Holds → geometric requirements per archetype → physics loads → timing and damage → motion validation → light chain / heavy / guard, plus `rejections[]`. |
| `motion_library.gd` | motion | Five authored archetypes (`thrust`, `sweep`, `overhead`, `alternate`, `shove`), heavy variants and three guard styles. Fits the object to keys, adapts it for reach and torso clearance, and validates it. |
| `adaptive_fighter.gd` | rules | Shared player/enemy state machine: idle, attack, guard, dodge, stagger, recoil, broken, dead. Owns HP, posture, chains, buffering, deflect and spacing-adaptive footwork. Contact is a swept capsule. |
| `adaptive_ai.gd` | AI | Seeded soul controller that only produces intents |
| `adaptive_pose.gd` · `adaptive_actor.gd` · `object_mesher.gd` | presentation | Rig pose and IK; drawn object, canopy openness, telegraph glow, trail, popups and overlay. Reads the rules only. |
| `adaptive_lab.gd` · `adaptive_hud.gd` · `adaptive_input.gd` | scene | Arena, camera, tick order, hotkeys, HUD, runtime-only `alab_*` input actions |

### 2.1 Why moves cannot come from names

The solver's only inputs are the analysis of the parts and the body. Nothing below the scene reads `label`, and a
source scan checks this. Each archetype has a **geometric requirement**:

| Archetype | Granted only when |
| --- | --- |
| thrust | A feature lies ≥ 0.25 m from the hold, within 28° of the hold axis, and faces forward (normal·axis ≥ 0.75, or is a mass). It must be the object's furthest point along that line and be on the lead hand's side. Total mass must be controllable. |
| sweep / overhead | A feature ≥ 0.3 m from the hold, at the far end (≥ 60 % of the object's extent in that direction), whose surface can *lead* the swing (normal ⟂ strike axis, or a mass). Inertia about the hold must be ≤ the hands' limit. The mass's off-axis **roll torque** must be ≤ the wrists' limit. |
| alternate ends | A spread two-hand hold (≥ 0.30 m) with strikable features ≥ 0.25 m beyond *both* hands |
| shove | The shaft between spread hands, or the nearest face/mass/end within 0.5 m of the hold |
| guard | A deployable membrane (`deploy_cover`), a plate or lump surface (`surface_cover`), or the shaft (`cross_guard` two-handed, `upright_guard` one-handed). The guard's arc, absorption and deflect window come from size and hardness. |

The damage channel is the feature's: a point with sharpness ≥ 0.25 pierces, an edge with sharpness ≥ 0.25 cuts, and
everything else is blunt. Timing scales with `max(inertia / limit, mass / limit)`. Damage scales with the effective mass
at the feature, lever speed, sharpness and hardness. Then every chosen action is **sampled over its whole timeline**. It
is rejected if a grip leaves the arm's reach (> 15 mm after adaptation) or if the object enters the wielder's torso or
head (> 35 mm).

### 2.2 Motion: authored principles + procedural adaptation + IK

Each archetype is authored as three keys (loaded, contact, through) and a ready pose. A key gives:
- the hold centre's position;
- the **strike-axis direction** D (hold → active feature);
- the torso's turn and lean;
- a swing rotation axis.

The key also uses footwork. The object's rotation maps its own strike axis onto D and its *leading surface* onto the
swing's travel direction. So a shovel jab leads with the blade's edge, a staff sweep rotates about the hands, and the
rear-end strike mirrors the key set. Keys are scaled to the body's arm length.

Between keys, the object transform is slerped from the pose the action started in, so a combo flows from wherever the
last strike ended. Every sampled pose is then adapted:
1. The object is pushed out of the torso/head capsule.
2. The hold is pulled toward the shoulders until every gripping hand can reach.

The rig places each fist on its grip point by two-bone IK. Attack footwork steps in when the opponent stands beyond the
feature's sweet spot and steps back when crowded.

The rules sample the same function for contact and the actor draws the same transform. That makes the **drawn object,
the fists and the damage capsule one rigid placement of one descriptor**.

### 2.3 Shared rules (player = enemy)

`AdaptiveFighter.equip(descriptor, body)` calls the solver. Player input and AI produce the same intent dictionary. An
intent without a capability logs `light_unsupported` / `heavy_unsupported` / `guard_unsupported` with the reason and does
nothing.

Damage happens only in the active window. The swept capsule is tested in four rule-time sub-samples per tick against the
defender's body capsule. Outcomes:
- **hit**: interrupts unless the attacker is in a heavy windup, which has hyper-armour;
- **block**: chip damage plus posture;
- **deflect**: a fresh guard press inside the object-derived window; the attacker recoils and takes posture;
- **evaded**: the defender was in dodge invulnerability;
- **punish**: a hit on a posture-broken fighter, ×1.5.

## 3. Demonstration objects and what the solver derived

These are anonymous structures from **recipes**: lists of primitive templates with ranges. They are not weapon
classes, and their labels are HUD text only. Seed 1 of each, pilgrim body:

| Recipe | Mass | Hold | Light (3-hit chain) | Heavy | Guard |
| --- | --- | --- | --- | --- | --- |
| broad terminal plate (shovel-like) | 3.04 kg | 2 hands, spread 0.36 m (crossbar + shaft) | edge **thrust** (cut) · shaft **shove** · thrust | edge thrust | cross |
| ribbed canopy (umbrella-like) | 1.02 kg | 1 hand on the crook | ferrule **thrust** (pierce) · crook shove · thrust | ferrule thrust | **deploys canopy** |
| double-ended pole | 2.52 kg | 2 hands, spread 0.32 m | **alternate ends**: lead · rear · lead (blunt) | **sweep** with the lead cap | cross |
| irregular organic (gnarled root) | 2.81 kg | 2 hands on the thin end | thorn **sweep** (pierce) · knot thrust · thorn sweep | thorn sweep | cross |
| awkward offset mass (kiln weight) | 8.40 kg | 2 hands on the short handle | **shove only** | **none**: roll torque 25 N·m > wrists 10 | cross |

**Body modification (Marrow Arm, no left hand):**
- The pole becomes **one-hand thrusts only**; alternating ends need two hands.
- The shovel is choked up one-handed: slower (0.34 s vs 0.24 s), with a face sweep and a blade-face guard.
- The kiln weight **cannot be wielded at all**: mass > one-hand limit. It lies at the fighter's feet.

**Longer-armed corrupted body:** gains a wider legal grip span and a shovel sweep the pilgrim's chain does not pick.

## 4. Tests and evidence

```sh
bash scripts/tooling/test_adaptive_lab.sh            # full: checks ×2, mutations, rendered evidence
BONESHED_SKIP_RENDER=1 bash scripts/tooling/test_adaptive_lab.sh   # headless parts only
```

`scripts/qa/adaptive_lab_tests.gd` has **56 checks**. The runner replays them in a second process, and
`results.json` and a 20 s AI-vs-AI duel log must be byte-identical. Four source mutations, run in a disposable copy,
must each fail their named checks:

| Mutation | Must fail |
| --- | --- |
| The solver strengthens the body when the label says "spear" | label-swap equality and the no-label source scan |
| The contact capsule is offset 5 cm from the object | rigid feature and drawn-object = contact-capsule checks |
| The fist is 5 cm off the grip | hands-on-grips (sampled) and drawn-fist checks |
| Timing ignores weight | heavier-is-slower and one-hand-is-slower checks |

The checks cover:
- **Determinism and generation.** The same recipe and seed give an identical descriptor; seeds differ; descriptors and
  recipe data carry no move lists.
- **Labels.** Five objects × six decoy labels ("Bone spear…", "Executioner's greataxe", "Tower shield", …) × two bodies
  give identical capability sets and fingerprints. An umbrella called a spear still only thrusts with its ferrule point.
  A plate-only object named "Sword", a too-thick log or a bare stick named "Spear" gets no grip, no cut and no pierce.
- **Structure.** Removing the ferrule removes every pierce. Adding a spike adds one. Dulling the plate edge removes
  cutting.
- **Affordances.** The same Light input resolves differently for all five structures; Heavy resolves to at least four
  different actions. Each object's expected behaviour is checked (the pole alternates ends, the kiln is limited to
  shoving, …).
- **Grips.** Every grip lies on a generated graspable rod (< 0.5 mm off its axis) held by an existing hand. Two-hand
  spans respect anatomy, and longer arms allow wider grips.
- **Motion.** Fists stay on grips through every sampled light and heavy for three bodies: socket error < 2 cm and arm
  stretch ≤ 1.035. Objects stay out of the wielder. The feature moves rigidly with the grips. Strike paths differ
  between structures.
- **Weight and size.** Heavier ends mean longer windup and recovery for the same action. A longer object reaches
  further.
- **Rules.** Contact happens only inside active windows, and every light and heavy connects in reach.
  Hit/block/deflect/evade follow from timing. Blocked heavies break posture and open a punish.
- **Real input.** `Input.parse_input_event` mouse presses start the object-specific light within two ticks for all five
  objects. Presses chain lead → rear → lead on the pole. Middle-button heavy and right-button guard reach the rules. The
  kiln's heavy refuses and says why. Live relabel keeps capabilities. The live Marrow Arm toggle rebuilds the body and
  regrips.
- **Scene geometry.** The drawn object node's feature equals the rules' contact capsule at every attack frame
  (< 0.5 mm), and the drawn fists hold the rules' grip points. The umbrella guard visibly deploys its canopy at the
  generated radius.
- **Parity and isolation.** The player and the enemy get identical capabilities for the same object and body. The AI's
  unsupported heavy requests are refused. Nothing outside the lab references it.

`scripts/qa/adaptive_lab_capture.gd` renders the stills and clip frames, and the runner encodes the MP4s and contact
sheets. Selected evidence is in [evidence/adaptive-combat-lab/](evidence/adaptive-combat-lab/README.md).

## 5. Provisional interface and migration (Lab object-data direction)

This lab coordinates with the Lab's object-structure / affordance-validator direction **conceptually only**. It does not
read, vendor or assume any unmerged AI Game Dev Lab PR. The game-side contracts it introduces are deliberately small:

| Contract | Shape (v0, provisional) | Expected migration |
| --- | --- | --- |
| `boneshed.adaptive_object.v0` | `{schema, generator_version, recipe, seed, label, parts[]}`. Each part is a primitive (`rod`/`spike`: `a`,`b`,`radius`; `plate`: `center`,`u`,`v`,`n`,`length`,`width`,`thickness`,`bevel_*`; `lump`: `center`,`axis`,`radii`; `membrane`: `a`,`b`,`folded_radius`,`open_radius`,`ribs`) plus a `material` id. | Map 1:1 onto whatever part/primitive schema the Lab validator settles on. Materials become a shared table. `label` moves to the separate naming layer that ADAPTIVE_MORPHOLOGY_COMBAT §"Separate layers" (layer 4) describes. |
| Analysis output | Grips, features (kind, pos, outward normal, radius, sharpness, hardness, channel), covers, mass, COM, inertia samples, probes | Should become the **Lab validator's measured-affordance output** if it already computes these, so that game and Lab agree on one feature extractor. Thresholds (grasp radius, sharpness 0.25, clearances) are provisional constants in `object_analysis.gd`. |
| `boneshed.adaptive_body.v0` | Hands present, arm length, span and strength limits | Should be derived from the anatomy graph ([ANATOMY.md](ANATOMY.md)) and the equipment foundation's grip slots. `removes_hands` mirrors the foundation's "a handless body mod removes its grip". |
| `boneshed.adaptive_capabilities.v0` | `{hold, light[3], heavy, guard, ready_frame, rejections[]}` | This is the **legal move list** that a server/Echo validator would recompute from seed + versioned rules (AGENTS.md: never trust client results). Rejection codes are a first vocabulary for the Lab's validation-failure catalogue. |

Not done here, and needed before production:
- the shared-build/catalog integration (`build_catalog.gd` items still use fixed classes);
- persistence or serialization of instances beyond the descriptor itself;
- server validation;
- arbitrary mesh import;
- non-humanoid locomotion.

## 6. Known limitations (honest)

- **Feel is unproven.** Timings come from a formula plus authored keys and have not been tuned by playtest. Tiny
  numbers decide which archetype wins a score, so which light leads a chain can flip with small data changes.
- Five archetypes and three guard styles are a small vocabulary. Hook/pull, pommel strikes, grip shifts mid-combo and
  stance changes are not implemented. One hold per object is chosen, with no runtime grip shifting.
- Posing is procedural: rigid upper-body turn, IK arms, simple stepping legs with visible foot sliding during attack
  footwork. There are no authored animation clips, no wrist roll limits and no finger posing.
- The umbrella's "canopy" guard is a gameplay abstraction: soft cloth with steel ribs counted at half hardness.
- The awkward kiln weight can only shove, which deals no HP damage; its holder cannot win by damage. This is intended
  as a "limited viable actions" case, not a balanced item.
- Contact is swept capsules against a single body capsule. The shaft does not collide with bodies, and objects do not
  collide with each other. A thrust at point-blank range is handled by footwork stepping back, not by shaft contact.
- The AI is simple and seeded, not a tuned opponent.
- The solver costs about 0.1–0.5 s per object/body on this machine. The scene caches results by structure + body.
  Measured on llvmpipe/cloud CPU only, with no GPU benchmark.

## 7. Owner playtest guide

1. Run `bash scripts/tooling/play_adaptive_lab.sh`. Press **M** until the soul is *passive*. On each object (1–5),
   try LMB ×3 (rhythm: press late in each strike), MMB, a held RMB and Space.
   - Do the five objects feel like different things?
   - Is it readable which part of the object hurts? Glow and trails mark the live feature.
2. Press **F3** to see grip candidates (small green), chosen grips (large green) and contact features (red/amber).
   Check that what you see is what hits.
3. Press **G** on any object. The label changes; nothing else should.
4. Press **B** for the Marrow Arm. Watch the pole lose its alternating strikes and the kiln weight become unusable.
5. Set the soul to *aggressive* (M) and duel. Judge:
   - responsiveness of light/heavy;
   - the deflect window (RMB fresh press just before impact);
   - dodge;
   - posture break.
   Compare with the Melee Lab and the Visual Showcase.
6. Report which object feels most and least convincing, and whether authored keys (§2.2) read as weighty or floaty.

## 8. Suggested next small step

Owner feel test first. If the direction holds, the next small, separate PR could be one of:
- **(a)** authored key tuning and a fourth guard/hook archetype driven by real hook geometry;
- **(b)** a version-pinned shared feature-extractor contract with the Lab validator.

Not both at once.
