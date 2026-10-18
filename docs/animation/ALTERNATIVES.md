# Animation sources, tools and runtime approaches — comparison

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). Checked **2026-10-18**.
Labels: **Verified** = run or read in primary source during this task; **Reported** =
vendor or community claim, not reproduced; **Hypothesis** = reasoned, untested.
Prices and terms move; re-check the vendor page before buying or shipping.

## 1. Where the motion comes from

| Source | What you get | Rights / cost (as found) | Export → Godot 4.7.2 | Human cleanup | Verdict for Boneshed |
| --- | --- | --- | --- | --- | --- |
| **Hand-keyed in Blender** (Rigify control rig → baked deform rig) | Exactly the poses, holds and arcs combat needs; full control of telegraph and recovery | Owned by us; Blender is GPL but its output is ours. Cost = animator time | glTF 2.0 via the bundled Khronos exporter (**Verified** indirectly: the trial asset was produced by *Khronos glTF Blender I/O 5.1.18* and imported cleanly) | It *is* the human work | **Primary source for every combat-critical clip** (attacks, guards, deflects, staggers, signature moves) |
| **CC0 libraries**: Mesh2Motion human set (includes Quaternius-derived clips), Quaternius Universal Animation Library 1/2 | 160+ generic clips on one 66-bone UE-style skeleton: locomotion, sword set, hits, deaths, dodges | CC0 claimed in README (Mesh2Motion: no LICENSE file at pinned commit); Quaternius pages state CC0 | **Verified**: runtime `GLTFDocument` load and editor import both work; no loop flags (no `-loop` names) | **Measured** defects: root translation in non-`_RM` attacks, end-frame pops (16–36 m/s), unmatched attack/recovery pairs (0.7 m seam), 6.7 cm strafe loop seams, ankle below floor in `Sword_Regular_B_Rec` | **Recommended for prototyping and as locomotion/reaction starting points** after cleanup; not as shipped combat attacks |
| **Mixamo** | Auto-rig + large mocap-derived library | Free with Adobe account; FAQ allows use in projects, forbids redistributing raw files; service reported in "maintenance mode" (**Reported**, secondary) | FBX → Blender → glTF; extra retarget step | Mocap-style, generic weight; not authored for sword timing | **Not recommended** as a foundation: unclear long-term availability, redistribution limits matter for a game with player-visible asset packs and Tower snapshots |
| **Mesh2Motion app** (fit skeleton to your mesh, pick clips) | Auto-rig of *our* mesh to its human/animal rigs + its CC0 clips | MIT code, CC0 art (README) | GLB/glTF only (README) | Skin-weight quality reported as variable (lab issue survey 2026-10-14) | **Good first trial** for rigging placeholder bodies; keep Blender for weights and fixes |
| **Commercial libraries** (e.g. Truebones, marketplace sword packs) | Higher-quality mocap sword sets | Per-pack EULAs; read each | Usually FBX | Retarget + timing edits | **Optional** later, per-pack legal review; never assume "royalty-free" covers redistribution |
| **Video-to-motion AI** (Move.ai, DeepMotion, Uthana, Rokoko Vision) | Fast rough body motion from video | DeepMotion free tier non-commercial; Move.ai from ~$18/seat/month; Uthana per-second (**Reported**, aggregators/vendor) | FBX/GLB/BVH (**Reported**) | Foot contact, hands and weapon interaction need heavy cleanup; no sword awareness | **Reference/blocking only**: useful to rough in a stagger or fall, never for the timing-critical blade arc |
| **Open video-to-mocap pipelines** (GVHMR/SMPL-X based: Motion2MixamoRig, mixamo-llm-mocap) | Same as above, self-hosted | SMPL-X body model gated; default non-commercial terms (lab review 2026-10-13) | via Blender | Same | **Rejected for production** until the SMPL-X rights chain is cleared |
| **Text/generative motion** (UniMate etc.) | Motion from prompts, some multi-topology | UniMate checkpoints **CC BY-NC 4.0** (lab review 2026-10-14) | Varies | Unknown | **Rejected** for commercial use; research watch only |
| **Physics-assisted authoring** (Cascadeur) | Keyframe tool with physics/balance assist; strong for weight and impacts | Free tier non-commercial and `.casc`-only export; Indie ~$8/mo (<$100k revenue), Pro ~$33/mo (**Reported**, pricing aggregators Aug 2026) | FBX/glTF on paid tiers (**Reported**) | Still hand-keyed, faster | **Worth a paid trial** for one attack if the animator wants it; not required |
| **Procedural only** (IK gaits, springs, code-driven poses — today's placeholders) | Infinite variety, zero clips | Ours | n/a | n/a | **Rejected as the main source** for humanoid combat: it is what Boneshed has now. **Kept as a layer** (IK, aim, secondary motion) |

## 2. Runtime approaches in Godot 4.7.2

| Approach | Verdict | Evidence |
| --- | --- | --- |
| `AnimationTree` (BlendTree + StateMachine + BlendSpace2D) over one `AnimationLibrary` | **Recommended** | Lab graph works under manual `advance()`; deterministic (trace reproducible to < 0.1 mm) |
| Plain `AnimationPlayer.play()` with crossfades | Fine for props/doors; insufficient for upper/lower layering and additive reactions | Layering needed: see foot-slip results |
| **Rule-driven clip time** (`TimeSeek` fed from phase + markers) | **Recommended for every combat action** | Contact marker lands within 9–11 ms of the first live tick (one 60 Hz tick is 16.7 ms) |
| Free-running clips with method-track / marker events deciding damage | **Rejected** for damage timing: animation would own gameplay timing and break the "rules own time" separation in AGENTS.md | — |
| Root motion via `AnimationMixer.get_root_motion_position()` | **Use with care**: correct when the clip free-plays; **sign-inverted** when driven by per-frame `TimeSeek` in 4.7.2 (Verified, tripwire test) | `observation_timeseek_root_motion_sign_inverted_in_4_7_2` |
| Root motion sampled from the authored root curve at rule time, applied by code | **Recommended** for dodges/lunges that need authored displacement | 1.156 m applied vs 1.156 m authored |
| Code-driven movement with in-place clips, playback rate matched to stride | **Recommended** default (precision combat, confirmed move-while-attacking) | Planted slip 0.085–0.13 m/s matched vs 0.77 m/s unmatched |
| `SkeletonIK3D` | **Rejected**: deprecated since 4.3 | Class reference |
| `TwoBoneIK3D` (4.6+) | **Recommended** for limb targets (feet, off-hand, extra limbs) | Lower-arm IK error 0.0 m in `BoneAttachment3D`; see the read-back caveat |
| `RetargetModifier3D` / import `BoneMap` + `SkeletonProfileHumanoid` | Use **within** the humanoid family only | Docs read; not exercised (the trial asset already shares one skeleton) |

## 3. Why not the obvious shortcuts

- **"Mixamo everything."** Generic clips have the wrong *timing language* for Sekiro-style
  reads. The trial slash's anticipation needed 3.8× compression to fit the 0.34 s
  courtyard windup. Its recovery needed 2.37×. No library clip arrived with a held, readable
  loaded pose. Availability and redistribution terms are a second risk.
- **"Retarget human clips onto any body."** The four-armed test shows that copying an
  arm chain's *local* rotations onto a structurally identical chain works only when the
  parent pose matches. With the torso in a different clip, the copied guard put the hands
  beside the hips. That is a 0.7 m miss, which IK had to correct. Non-identical chains are
  worse. See [TRANSFORMATIONS.md](TRANSFORMATIONS.md).
- **"Generate it with AI."** None of the reviewed generators understands a held weapon,
  a deflection window or a telegraph. Licences for the strongest research models are non-commercial.
