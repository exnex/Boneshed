# Equipment foundation — rendered evidence

Produced by `scripts/qa/equipment_capture.gd` (`bash scripts/tooling/test_equipment.sh`) with
Godot `4.7.2.stable.official.ed1daf0bf`, GL Compatibility, Mesa llvmpipe under Xvfb, 1280×720.
Each run reaches the equipped state through the real path: lethal contacts through the
production resolver → `acquire()` (salvage) → `equip()` → `_start_duel(true)` (next duel).
Fighters are then posed side by side, idle, facing +Z; the camera is moved, nothing else.

| Folder | Revision | Notes |
| --- | --- | --- |
| `before-main/` | `main` at `31ec237` (catalog 0.3.0), same script copied in | Later `main` commits (#35, #36) changed only keywords/docs, not equipment or visuals. |
| `after-branch/` | this branch, merged with `main` `495b270` | `placement.json` also includes `EquipmentLook.disagreements()` per fighter (all empty). |

Orientation: in a **front** shot the character's left is on the **screen right**; in a
**rear** shot it is on the screen left. Green = player (Pilgrim), red = corrupted swordsman.

| Shot | Before (main) | After (branch) |
| --- | --- | --- |
| `1_before_salvage_*` | Player sword only; enemy bone right, sword left | Player sword right; enemy bone left, sword right |
| `2_after_equip_*` | Both: bone right (`right_arm`), sword drawn left, `sword_hand_x = -0.48`, `marrow_root_x = +0.42` | Both: bone left (`arm_l`), sword right (`hand_r`), `sword_hand_x = +0.48`, `marrow_root_x = -0.42` |
| `3_lunge_drawback_front` | Legacy lunge draws back over the right shoulder | Same lunge, mirrored: left shoulder; sword stays right |
| `4_lunge_active_side` | — | Bone at full rule reach from the left side |

`compare_*.png` stack before (top) and after (bottom) at half size.
Renders show placement only; they say nothing about game feel or readability, which need
a human playtest.

## Regression run (head `b0a50c5`, merged with `main` `495b270`)

Pinned engine, Linux x86_64 cloud container, Mesa llvmpipe. All runners executed sequentially.

| Runner | Result | Time |
| --- | --- | --- |
| `test_builds.sh` | pass (205 checks; salvage example regenerates identically) | 9 s |
| `test_anatomy.sh` | pass (190 checks; anatomy example regenerates identically) | 8 s |
| `test_marrow.sh` | pass (212 checks, 8 mutations, pose + equipment negative controls, rendered input playthrough = headless trace) | 204 s |
| `test_equipment.sh` | pass (rendered placement + agreement, both fighters) | 8 s |
| `test_combat_motion.sh` | pass (63 checks + negative controls) | 128 s |
| `test_enemy_ai.sh` | pass | 947 s |
| `test_presentation.sh` | pass | 17 s |
| `test_expedition.sh` | pass | 218 s |
| `test_camera_zoom.sh` | pass | 110 s |
| `test_keyword_grammar.sh` | pass | 159 s |
| `test_worldgen.sh` | pass | 17 s |
| `test_animation_lab.sh` | pass | 244 s |
| `test.sh` | pass with `BONESHED_GRAPHICAL_TIMEOUT=900` (combat_builds 532, combat 118, graphical 111) | 373 s |

`test.sh` first failed only by **timeout** (exit 124) in the rendered `graphical` step at the
default 180 s, with no failed checks. The same step alone takes 284 s on unmodified `main`
(`495b270`) and 283 s on this branch in this container (both 111/111), so the limit is an
environment issue, not a regression. Not run: `test_web.sh` (no export/input change).
