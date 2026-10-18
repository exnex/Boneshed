# Character animation pipeline — research, recommendation and isolated lab

**Status: research and isolated prototype. Nothing here is a confirmed mechanic or an
approved asset policy.** No courtyard, combat, camera, player, AI, HUD or shared-build file
was changed. Engine: Godot **4.7.2.stable.official.ed1daf0bf** (checked with
`--version`), GL Compatibility, Linux x86_64, llvmpipe software rendering. Researched and
built 2026-10-18.

| Document | Contents |
| --- | --- |
| This page | Recommendation, the lab, measured results, visual evaluation, verified behaviours, what remains untested |
| [Alternatives](animation/ALTERNATIVES.md) | Animation sources and tools (authored, libraries, Mixamo, Mesh2Motion, mocap, AI, Cascadeur, procedural) and Godot runtime approaches |
| [Workflow and standards](animation/WORKFLOW_AND_STANDARDS.md) | Concept → Blender → Godot steps, skeleton, marker and animation standards |
| [Transformations](animation/TRANSFORMATIONS.md) | Extra or missing limbs, asymmetry, nonhuman bodies |
| [Combat integration](animation/COMBAT_INTEGRATION.md) | Weapon/body collision model, authoritative damage timing, minimum contract for Codex |
| [Asset and licensing checklist](animation/ASSET_LICENSING_CHECKLIST.md) | Rights chain, sources reviewed |
| [Backlog](animation/BACKLOG.md) | Small, testable milestones |
| [Reusable research note](animation/LAB_RESEARCH_NOTE.md) | Engine-general findings formatted for later inclusion in AI Game Dev Lab (not copied there) |
| [Evidence](evidence/animation-lab/README.md) | Rendered clips, contact sheets, metrics, baked trace, logs |

## 1. Recommendation

**Hand-authored combat animation in Blender on one standard skeleton per body family,
imported as glTF through a data manifest. A Godot `AnimationTree` plays it, *timed by the
combat rules*, with procedural layers only where they fix something specific.**

1. **Source of motion.** Every combat-critical clip is hand-keyed by a human animator:
   attacks, guards, deflect impacts, staggers, posture breaks and signature moves. CC0
   library clips (Mesh2Motion, Quaternius) are used for prototyping and as cleanup starting
   points for locomotion, hits and deaths, *after* approval to vendor them. Video and AI
   motion are reference only.
2. **Rig.** Rigify (or similar) control rig → clean deform rig with UE-style humanoid names
   (`pelvis`, `spine_01..03`, `upperarm_l`…). That auto-maps to Godot's
   `SkeletonProfileHumanoid`. Extra limbs are *appended* chains.
3. **Export/import.** glTF 2.0 `.glb`. A manifest (`clip_manifest.json`) records loop flags,
   root policy, combat markers and known defects. An import step applies it: strip
   non-bone tracks, flatten the root of in-place clips, embed markers, convert additive clips.
4. **Runtime.** `AnimationTree`: locomotion `BlendSpace2D` (rate matched to stride) → stance
   layer → action state machine whose clips are **seeked to rule time through markers**
   (phase warp) → optional extra-limb layer → additive hit layer.
5. **Movement.** Code-driven by default. Root motion only where displacement *is* the
   move (dodge, lunge, knockback), read **as data from the authored root curve** at rule time.
6. **Procedural layers.** `TwoBoneIK3D` for foot lock, off-hand grips and extra limbs, plus
   look-at. No procedural generation of attacks.
7. **Damage.** Rules own the clock. The geometry comes from a **baked blade trace** (data),
   swept at ≥ 60 Hz. The rendered pose never decides a hit.

**Why:** it is the only option the lab could show to be *both* visually credible (authored
weight, arcs and follow-through) and compatible with deterministic, rule-owned precision
combat. Library clips proved the visual leap from today's rigid primitives. They also proved
that generic timing does not fit Boneshed's telegraphs without re-authoring (§4).

**Rejected:** procedural-only animation (today's placeholders); Mixamo as a foundation
(availability, no raw redistribution); AI/video motion for combat clips (no weapon
awareness; rights chains); universal retargeting across body plans; animation-driven
damage events; `SkeletonIK3D` (deprecated). Details in [Alternatives](animation/ALTERNATIVES.md).

## 2. The isolated lab

```sh
bash scripts/tooling/setup.sh                 # pinned Godot 4.7.2 (checksum-verified)
bash scripts/tooling/test_animation_lab.sh    # fetch trial asset, 76 checks, negative control, 5 rendered clips
# Watch one sequence (needs a display):
godot --path . res://scenes/animation_lab.tscn -- --sequence=overview   # or timing, move_attack, four_arm, closeup
```

| File | Role |
| --- | --- |
| [`scenes/animation_lab.tscn`](../scenes/animation_lab.tscn), [`animation_lab.gd`](../scripts/animation_lab/animation_lab.gd) | Director: stage, camera, five scripted sequences, blade trails, labels |
| [`lab_character.gd`](../scripts/animation_lab/lab_character.gd) | One animated swordsman: AnimationTree graph, weapon socket, root motion as data, optional upper/lower split, optional extra arms + IK |
| [`lab_actor.gd`](../scripts/animation_lab/lab_actor.gd) | Stand-in for CombatState: owns the clock, resolves timing from the build catalog (read-only), drives clip time |
| [`phase_warp.gd`](../scripts/animation_lab/phase_warp.gd) | Pure: rule phase → clip time through markers; warp ratios; rule time from `(phase, remaining)` |
| [`weapon_trace.gd`](../scripts/animation_lab/weapon_trace.gd) | Pure: segment distance, swept blade vs capsule, rule-window gating, baked-trace export |
| [`clip_library.gd`](../scripts/animation_lab/clip_library.gd) | Import step: verify, load glTF, apply the manifest |
| [`extra_limbs.gd`](../scripts/animation_lab/extra_limbs.gd) | Appends a lower arm pair, skins procedural geometry, builds a pose module |
| [`data/animation_lab/`](../data/animation_lab/) | `trial_asset.json` (pinned source, SHA-256, licence evidence), `clip_manifest.json` (clips, markers, timings, defect ledger) |
| [`scripts/qa/animation_lab_tests.gd`](../scripts/qa/animation_lab_tests.gd) | 76 deterministic checks plus metrics; `--negative=warp` control |
| [`fetch_animation_trial.sh`](../scripts/tooling/fetch_animation_trial.sh), [`test_animation_lab.sh`](../scripts/tooling/test_animation_lab.sh) | Fetch and verify the asset outside the checkout; full run with Movie Maker capture and ffmpeg encoding |

**Trial asset.** Mesh2Motion `human-base-animations.glb` and `human-addon-animations.glb`
at commit `653a969`. This is a 66-bone skinned mannequin with sword, locomotion,
hit and dodge clips, exported by Khronos glTF Blender I/O 5.1.18, with CC0 claimed in the README.
It is downloaded to `/workspace/tools/animation-trial/` and SHA-256-verified. It is
**never committed, shipped or read by the game**. Vendoring it needs approval (AGENTS.md). The longsword is
primitive geometry built in code.

**Sequences** (all rendered, see [evidence](evidence/animation-lab/README.md)):
`overview` (idle, footwork in four directions, two telegraphed slashes at courtyard and
swordsman timing, guard with an additive impact, stagger, root-motion dodge),
`timing` (one clip at three rule timings side by side), `move_attack` (full-body vs
upper/lower split while moving), `four_arm` (humanoid vs four-armed variant on the same
clips), `closeup` (quarter speed, grip and deformation).

## 3. Measured results (Godot 4.7.2, headless, deterministic)

| Measure | Result | Meaning |
| --- | --- | --- |
| Contact-marker alignment | **9.4 ms** between the clip's `contact` pose and the first live rule tick | Rule-driven timing works; damage timing never depends on animation |
| Negative control (contact marker shifted 0.1 s) | Fails exactly the alignment and telegraph checks | The tests detect a mis-timed clip |
| Warp ratios, courtyard slash 0.34/0.16/0.45 | early **3.8×**, committed 0.44×, release 0.41×, active 0.94×, recovery **2.37×** | The library clip's pacing does not fit Boneshed timing; it needs re-authoring |
| Warp ratios, swordsman 0.62/0.16/0.65 | early 1.0×, committed 0.44×, release 0.41×, active 0.94×, recovery 1.64× | Longer windups fit far better |
| Blade before the rule window | 0 ticks in the forward hemisphere; ≥ 80 % of live ticks in front | Telegraph proxy: the blade is not dangerous-looking before it is dangerous |
| Weapon grip | Attachment vs hand-pose maths < 2 mm; blade length constant | `BoneAttachment3D` grip is rigid and stable |
| Thin-pole tunnelling (poles between 60 Hz samples on the true arc) | point @30 Hz **0/10**, linear sweep @30 Hz **9/10**, sweep of 60 Hz baked trace **10/10** | Sweep a densely evaluated trace |
| Slash tip speed | peak **47 m/s**; lowest tip 0.16 m above the floor | Fast enough to tunnel; the follow-through nearly hits the floor |
| Planted-foot slip, walking | 0.085 m/s matched at 0.9 m/s; 0.13 at 1.5 m/s; **0.77** unmatched | Rate matching is needed; the residual needs foot-lock IK |
| Planted-foot slip, attacking while moving 0.9 m/s | full-body **1.41 m/s** vs upper/lower split **0.09 m/s** | Confirmed move-while-attacking requires the upper/lower split |
| Stride speed of trial cycles | walk 0.78, back 0.96, strafe 0.81 / 0.56 m/s | Courtyard runs at 5.5 m/s (player) and 2.7 m/s (swordsman); real cycles are needed at those speeds |
| Root-motion dodge | 1.156 m applied vs 1.156 m authored, backwards | Root curve as data works |
| Additive flinch | Neutral at frame 0; hand moves 0.08 m mid-reaction; pelvis 0.009 m | Additive layer over guard or idle works after stripping non-bone tracks |
| Four-armed variant | Shared bones identical to the humanoid (< 0.1 mm); IK lower hands on target (0.0 m via attachment) | Appending limbs keeps family clips |
| Trace reproducibility | Two runs identical (< 0.1 mm) | Deterministic enough for data baking |

**Defects found in the trial clips** (now in the manifest's `known_defects` ledger, which
tests keep honest): 6.7 cm loop seams on both strafes; an Armature-object position track
in `Hit_Chest`; a hitch at the top of the slash windup; root translation in
non-`_RM` attacks (`Sword_Regular_A` moves 0.36 m); end-frame pops of 16–36 m/s in several
sword clips; attack/recovery clip pairs that do not join (0.7 m gap); ankle 0.08 m below
the floor in `Sword_Regular_B_Rec`; no loop flags on export.

## 4. Visual evaluation (critical)

Judged from the rendered clips and frame sheets in [evidence](evidence/animation-lab/README.md).
This is a desk review of renders, **not a playtest**. Nothing here claims combat feels good.

| Criterion | Assessment | Must be fixed by hand |
| --- | --- | --- |
| Weight transfer | **Much better than the primitives.** The slash crouches, loads the back foot and drives through the hips. At courtyard timing the early windup plays 3.8× fast and reads as a twitch, not a wind-up | Re-author the anticipation at the real windup length |
| Foot sliding | Visible light skating on matched locomotion; **severe skating** when the full-body attack plays while moving; nearly none with the upper/lower split | Foot-lock IK; locomotion cycles at play speeds |
| Limb deformation | The mannequin's shoulders and elbows hold up in the close-up; no candy-wrapper twist was noticed. The procedural extra arms are crude tubes with a visible seam at the torso | Real meshes and weights for parts; twist bones |
| Weapon grip stability | Rigid and stable. The grip *orientation* is an estimate: the idle holds the blade out sideways at hip height, which looks odd. Library hands are not posed around this handle | Prop bone `weapon_r`; per-weapon grip poses |
| Telegraph readability | Blade raised overhead and behind, clearly different from guard. **No held "loaded" pose** and a small hitch at the top. The rule-time slowdown of release (0.41×) creates a brief hang that may *help* reading; unverified | Author a ≥ 4-frame hold at `loaded` |
| Striking arc | A clear high-right to low-left diagonal with a big readable trail. The follow-through drives the tip to 0.16 m above the floor | Raise the follow-through |
| Transition quality | Crossfades of 0.04–0.25 s are clean between idle, attack and guard. The stagger entry (0.04 s) snaps. The strafe loop pops every cycle. The additive guard-impact flinch is now *too subtle* to read at duel distance (hand moves 0.08 m). **The impact first rendered with the whole body jumping 0.58 m**: the non-bone track bug, fixed and tested, which unit tests alone had missed | Authored transitions for stagger and break; clean loops |
| Silhouette readability | A good human silhouette; the thin sword is hard to see at distance in the timing shot. The extra arms clutter the belly area | Weapon thickness and value contrast; part silhouette review |
| Code-driven precision combat | Good: rules own time, clips follow (9 ms), root motion is data, damage geometry can be baked. Move-while-attacking needs the split | — |

Overall verdict: the **workflow** is credible, and its important parts are demonstrated and
tested. The **trial clips are not production quality** for Boneshed. Their structure is
right; their timing language, loops and grip are not. Production quality depends on human
animation work, listed in [Backlog](animation/BACKLOG.md) A3–A5.

## 5. Verified engine behaviour vs. hypotheses

**Verified in this lab (tests, Godot 4.7.2):** runtime `GLTFDocument` loading of the trial
assets; `Animation.add_marker`; `AnimationTree` manual `advance()`; `TimeSeek` driving under a
state machine; `AnimationNodeOneShot` ADD mix with a converted additive clip;
`AnimationNodeBlend2` bone filters for upper/lower splitting; `Skeleton3D.add_bone` at runtime
without disturbing existing clips; `TwoBoneIK3D` with target and pole nodes;
`BoneAttachment3D` following animated and IK-modified bones.

**Surprising behaviour (verified, with tripwire tests):**
1. `get_root_motion_position()` is **sign-inverted** under per-frame `TimeSeek` +
   `advance(delta)`, with correct magnitude. Not root-caused.
2. `SkeletonModifier3D` (IK) output is **not** returned by `get_bone_global_pose()` outside
   the skeleton update; `BoneAttachment3D` and `skeleton_updated` see it.
3. `MeshInstance3D.new()` has an empty `skeleton` path, so code-built skinned parts render in rest pose.
4. Library clips can key **non-bone** node transforms; an additive layer then moves the whole model.

**Hypotheses / community practice (not tested here):** Rigify → game-rig add-ons export
cleanly to Godot (vendor claims); editor-import `BoneMap` retargeting of third-party
humanoid clips; `BoneTwistDisperser3D` for forearm twist; Cascadeur's value for combat
keys; desktop GPU performance.

## 6. Estimated complexity (rough, uncalibrated)

| Work | Estimate | Who |
| --- | --- | --- |
| Editor import script + clip QA runner (A1, A2) | 2–4 days | Claude |
| Presentation-only animated fighter in the courtyard (contract Step A) | 3–6 days | Codex |
| Baked traces + shadow mode (Steps B) | 3–5 days | Claude + Codex |
| Custom humanoid character: model, rig, weights | 1–2 weeks | Human artist |
| Production humanoid combat set (~20 clips: idle, 2-speed 4-way locomotion, light/heavy attack, guard, deflect, flinch, stagger, break, dodge, death) | 4–8 weeks part-time | Human animator |
| Each new part module (e.g. Marrow Arm lunge) | 2–5 days | Animator + Claude |
| Each new body family (full locomotion/reaction set) | 3–6 weeks | Animator |

## 7. What remains untested

Human playtest and feel; editor-import path (the lab loads glTF at runtime); Blender
authoring and export (Blender could not be downloaded in the cloud sandbox); the Quaternius
packs; Mixamo; any AI/video tool; `BoneMap` retargeting; foot-lock IK; two-handed grip IK;
desktop GPU and frame-time cost; web export; network/Tower replay of traces; any non-humanoid
body family; four-armed *attacks*; runtime part removal; integration with the live
courtyard.
