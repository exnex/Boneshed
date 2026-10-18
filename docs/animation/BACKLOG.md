# Animation backlog — small, testable milestones

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). Each item is one PR,
with a named test or rendered artifact as its acceptance check. Owners are suggestions.
Items touching combat, actors, AI, HUD or the courtyard belong to Codex. **Nothing here is
approved.** Order follows dependency and risk.

| # | Milestone | Owner | Acceptance check | Size |
| --- | --- | --- | --- | --- |
| A0 | **Decide** the asset policy: may CC0 library clips be vendored (Mesh2Motion/Quaternius) for prototyping? Who authors production clips (human animator, contractor, Cascadeur trial)? | Human | Decision in DECISIONS.md | — |
| A1 | Editor import path: `EditorScenePostImport` script that applies `clip_manifest.json` (loops, root policy, markers, additive) to an imported `.glb`, replacing the lab's runtime conversion | Claude | Same 72 lab checks pass against the editor-imported library | S |
| A2 | Clip QA as a standalone runner: end-frame pop detector, loop seam, root drift, foot-below-floor and warp-ratio report for every manifest clip | Claude | Report flags the known trial defects (pops, strafe seams, `Sword_Regular_B_Rec` ankle at −0.08 m) | S |
| A3 | **Author one production-quality light slash** in Blender on the family rig, to the 0.34/0.16/0.45 timing, with a ≥ 4-frame hold at `loaded` | Human animator | Warp ratios all in 0.67–1.5; telegraph checks pass; human review of the close-up render | M |
| A4 | Authored guard, deflect impact (additive) and posture-break stagger to rule timings | Human animator | Lab overview render; additive neutral at frame 0 | M |
| A5 | Locomotion at play speeds: lock-on strafe/forward/back at ~2.7 and 5.5 m/s (current courtyard speeds) | Human animator | Planted slip < 0.1 m/s at both speeds | M |
| A6 | Foot-lock `TwoBoneIK3D` on legs during contact, to remove residual slide | Claude | Matched-walk slip drops below 0.03 m/s; no knee pops in render | S |
| A7 | Off-hand IK to the weapon's secondary grip for two-handed weapons | Claude | Hand-to-grip error < 1 cm via `BoneAttachment3D` across the clip | S |
| B1 | `AnimatedFighterVisual` behind a data flag (presentation only, contract Step A) | Codex | Existing suites unchanged; contact marker on the first ACTIVE tick for every module | M |
| B2 | Bake traces for every attack module and timing; QA tool writes `data/traces/` | Claude | Byte-identical re-bake; trace sweep agrees with the rule box in shadow mode | S |
| B3 | Shadow-mode trace evaluation in combat, logging disagreements (contract Step B) | Codex | Disagreement report across probe suites | S |
| B4 | Switch authority to traces (contract Step C), only after human approval | Codex | Combat suites updated deliberately; human playtest | M |
| C1 | Marrow Arm part: skinned to the humanoid arm chain, plus the curated `anim.arm_marrow` lunge module | Human + Claude | Lunge telegraph checks; render | M |
| C2 | Four-arm attack choreography: lower pair parry/strike layer modules (authored, not copied) | Human animator | Render plus readability review | L |
| C3 | Runtime part add/remove with module load/unload and filter rebuild | Claude | Add → remove → add leaves shared-bone clips identical; no leaked nodes | S |
| D1 | Hit-pause and clash presentation from rule results (cosmetic) | Codex | Visual only; rule timing unchanged | S |
| D2 | Death and knockdown set with root-motion data | Human animator | Root curve applied as data; no floor penetration | M |
