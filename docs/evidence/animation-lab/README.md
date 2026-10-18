# Animation lab evidence

Produced by `bash scripts/tooling/test_animation_lab.sh` on 2026-10-18. Godot
`4.7.2.stable.official.ed1daf0bf`, Linux x86_64, GL Compatibility, **llvmpipe software
rendering** under Xvfb, Movie Maker at a fixed 30 fps, encoded with the system ffmpeg 6.1.1
(H.264, CRF 26). Trial asset: Mesh2Motion @ `653a969`, SHA-256 verified, not committed.
See [ANIMATION_PIPELINE.md](../../ANIMATION_PIPELINE.md) for the analysis.

Rendered frames reflect llvmpipe output, not a desktop GPU. These are desk-review clips,
**not playtests**.

| Clip | Contact sheet | What to look at |
| --- | --- | --- |
| [overview.mp4](overview.mp4) (17 s) | [overview_sheet.png](overview_sheet.png) | Idle → four-direction footwork → slash at courtyard timing (8.0 s) → slash at swordsman timing (9.6 s) → guard with additive impact (11.6 s) → stagger (13.2 s) → root-motion dodge (14.7 s). The trail is pale during windup/release and orange during the rule-live window |
| [timing.mp4](timing.mp4) (6.5 s) | [timing_sheet.png](timing_sheet.png) | One clip at three rule timings, left to right: source pacing, courtyard slash, swordsman. Labels turn orange while the rule window is live |
| [move_attack.mp4](move_attack.mp4) (6 s) | [move_attack_sheet.png](move_attack_sheet.png) | Side view against a 0.5 m checker. Far actor: full-body attack while moving (feet skate). Near actor: upper/lower split (legs keep walking) |
| [four_arm.mp4](four_arm.mp4) (8 s) | [four_arm_sheet.png](four_arm_sheet.png) | Humanoid (left, cream) and four-armed variant (right, grey) on identical clips. The lower pair holds a guard via TwoBoneIK3D; it is hard to see from this front angle |
| [closeup.mp4](closeup.mp4) (2.2 s rule time at ¼ speed) | [closeup_sheet.png](closeup_sheet.png) | Grip, wrist and shoulder deformation through the slash |

| File | Content |
| --- | --- |
| [animation_lab_metrics.json](animation_lab_metrics.json) | Warp ratios, alignment, slip, strides, seams, root motion, tunnelling trials, IK error, source audit |
| [baked_slash_trace.json](baked_slash_trace.json) | 60 Hz blade base/tip trace of the courtyard slash in attacker-local metres, with the rule `live` flag |
| [animation_lab_tests.log](animation_lab_tests.log) | One JSON line per check (76 passed, 0 failed) |
| [negative_warp.log](negative_warp.log) | Negative control: contact marker shifted 0.1 s. Expected exit 1, failing exactly `contact_marker_on_first_live_tick` and `blade_not_in_front_before_rule_window` |
| [runs.json](runs.json) | Exit codes of every step |

## Defect caught only by rendering

The first full render showed the body jumping about 0.58 m at the guard impact. The cause was
a position track on the `Armature` *node* inside the `Hit_Chest` clip, applied additively.
Every unit test had passed. The import now strips non-bone tracks, and three checks guard
it: `library_keeps_only_bone_tracks`, `source_audit_finds_armature_track_in_hit_chest`
and `additive_flinch_keeps_body_grounded`. The four-armed variant's limbs also first rendered
frozen in T-pose (empty `MeshInstance3D.skeleton`), which is now guarded by
`extra_limb_mesh_bound_to_skeleton`.
