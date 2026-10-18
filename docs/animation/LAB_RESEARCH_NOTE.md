# Research note for AI Game Dev Lab: melee character animation pipeline on Godot 4.7.2

**Prepared in the Boneshed repository for later inclusion in
[exnex/ai-game-dev-lab](https://github.com/exnex/ai-game-dev-lab). Not copied there; this
task did not edit the lab repository.** Suggested home: `11-research-watch/` plus a row in
`13-technology-index/animation-and-retargeting.md`. Labels follow the lab's AGENTS.md
(**Verified**, **Promising**, **Experimental**, **Deprecated**, **Unknown**).

- **Tested:** 2026-10-18. Godot `4.7.2.stable.official.ed1daf0bf`, Linux x86_64, GL
  Compatibility, llvmpipe under Xvfb, Movie Maker capture at 30 fps.
- **Source:** Boneshed branch `claude/brave-davinci-ldzas4`,
  `scripts/animation_lab/`, `scripts/qa/animation_lab_tests.gd`.
- **Trial asset:** Mesh2Motion `human-base-animations.glb` and `human-addon-animations.glb`
  @ `653a9698f5f315523072f1c3ff3496100401317b`. CC0 is claimed in the README; the repo has no LICENSE file.

## Engine-general findings

| # | Finding | Label | Evidence |
| --- | --- | --- | --- |
| 1 | Driving action clips from **rule time through named markers** (piecewise time warp + `AnimationNodeTimeSeek`) lands the contact pose within one 60 Hz tick of the rule's active window (9.4 ms) | **Verified** | `contact_marker_on_first_live_tick` |
| 2 | **Warp ratio** (clip seconds ÷ rule seconds per section) is a cheap, automatable measure of whether a library clip fits a game's timing. Generic sword clips needed 3.8× compression in their anticipation for a 0.34 s windup | **Verified** (measurement); 0.67–1.5 acceptable band is **Experimental** | `warp_ratios` metric |
| 3 | Under per-frame `TimeSeek` + `AnimationTree.advance(delta)`, `get_root_motion_position()` returns the **opposite sign** with correct magnitude. Free play is correct. Sampling the authored root curve as data avoids it | **Verified** in 4.7.2; cause **Unknown** | `observation_timeseek_root_motion_sign_inverted_in_4_7_2` |
| 4 | `SkeletonModifier3D` output (e.g. `TwoBoneIK3D`) is visible via `BoneAttachment3D` / `skeleton_updated` but **not** via `get_bone_global_pose()` outside the update | **Verified** | `observation_get_bone_global_pose_excludes_modifier_output` |
| 5 | `MeshInstance3D.new()` has an empty `skeleton` NodePath; a code-built skinned mesh stays in rest pose until it is set (`".."`) | **Verified** | `extra_limb_mesh_bound_to_skeleton`; rendered before/after |
| 6 | glTF clips may key **non-bone node** transforms (here the `Armature` object). Played additively, that moved the whole model 0.58 m. Strip non-bone tracks at import (Godot's "Remove Tracks: Except Bone Transform") | **Verified** | `library_keeps_only_bone_tracks`, `additive_flinch_keeps_body_grounded` |
| 7 | Additive conversion "rest ∘ (first⁻¹ ∘ key)" for rotations and "rest + (key − first)" for positions is neutral at frame 0 under `OneShot` ADD | **Verified** | `additive_layer_neutral_at_first_frame` |
| 8 | Appending bones with `Skeleton3D.add_bone()` at runtime leaves existing clips bit-for-bit on shared bones | **Verified** | `shared_bones_play_human_clip_identically` |
| 9 | Copying an arm chain's **local** rotations onto a duplicate chain under a different parent misses badly when the parents' poses differ (≈0.7 m); `TwoBoneIK3D` targets fix it | **Verified** | `lower_hands_held_in_front_of_torso` |
| 10 | Melee tunnelling: a 47 m/s blade tip sampled at 30 Hz hit 0/10 thin poles by point tests and 9/10 by linear sweeps between samples (chord error). A sweep over a 60 Hz evaluated trace hit 10/10 | **Verified** (one clip) | `thin_pole_trials` |
| 11 | Matching locomotion playback rate to the clip's measured stride cuts planted-foot slip from 0.77 to 0.085–0.13 m/s; the residual needs foot IK | **Verified** (one walk cycle) | `planted_foot_slip_mps` |
| 12 | Attacking while moving with a full-body clip skates the feet at 1.4 m/s; an upper-body bone filter on the action blend reduces it to 0.09 m/s | **Verified** | `upper_lower_split_reduces_slide_while_attacking` |
| 13 | Unit tests passed while a render showed the body jumping on impact (finding 6). **Rendered review is a required gate** for animation work, not optional evidence | **Verified** (process lesson) | Boneshed evidence README |
| 14 | Runtime `GLTFDocument.append_from_file` + `generate_scene` produces the same node layout and track paths as editor import for a Blender 5.1-exported GLB | **Verified** (one asset) | Lab load path |
| 15 | Blender timeline markers do not travel through glTF; keep combat markers in a sidecar manifest and write them with `Animation.add_marker` at import | **Promising** (glTF spec has no marker concept; Blender behaviour not re-tested here) | — |

## Process pattern worth reusing

- **Defect ledger in data:** declare known clip defects in the manifest, and make tests
  assert that the ledger matches measurements (no silent fixes, no stale claims).
- **Negative control** that shifts a marker by 0.1 s must fail exactly the alignment and
  telegraph checks.
- **Pinned evaluation assets outside the repository** (URL + commit + SHA-256), fetched by
  script, so licence approval is not needed just to evaluate.
- **Director scene + Movie Maker + ffmpeg** gives reproducible MP4s and contact sheets from
  a headless cloud box (about 3 minutes for five sequences on 4 vCPU llvmpipe).

## Not established

Feel and readability in play; desktop GPU cost; editor-import retargeting (`BoneMap`);
Blender-side authoring; any non-humanoid family; how general findings 3 and 4 are across
engine versions.
