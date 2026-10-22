# Adaptive Combat Lab 1 — evidence

Produced by `bash scripts/tooling/test_adaptive_lab.sh` on Godot 4.7.2.stable.official.ed1daf0bf, GL Compatibility,
**llvmpipe software rendering** (cloud Linux, Xvfb). These are rendered captures of scripted inputs, not a playtest and
not a GPU benchmark. Design: [../../ADAPTIVE_COMBAT_LAB.md](../../ADAPTIVE_COMBAT_LAB.md).

| File | Shows |
| --- | --- |
| `results.json` | 56/56 checks; byte-identical in a second process (replay) |
| `duel_log.json` | 20 s seeded AI-vs-AI event log (identical across processes) |
| `metrics.json` | Worst solver time and rules tick cost on this CPU (scoped, llvmpipe machine) |
| `clip_inputs_<recipe>.mp4` + `sheet_clip_inputs_<recipe>.jpg` | The **same inputs** (light ×3, heavy, held guard, move) on each of the five structures |
| `clip_body_mod_two_hands.mp4` / `clip_body_mod_marrow_arm.mp4` | The pole with two hands (alternating ends) vs with the handless Marrow Arm (one-hand thrusts) |
| `clip_umbrella_guard.mp4` | The soul attacks; the umbrella-like object deploys its generated canopy as guard |
| `clip_duel.mp4` | AI vs AI (pole vs organic root), follow camera, shared rules |
| `still_<recipe>_{ready,light_contact,heavy_loaded,guard}[_overlay].jpg` | Side view of each pose; `_overlay` adds grip candidates (small green), chosen grips (large green), contact features (red = pierce/cut, amber = blunt), active capsule and body capsule |
| `still_<recipe>_hud.jpg` | HUD: derived hold, light/heavy/guard, and reasons for moves not granted |
| `still_<recipe>_marrow_*.jpg` | Same objects for the Marrow Arm body (the kiln weight lies on the floor: unusable) |
| `still_label_swap_{original,relabelled}.jpg` | The umbrella-like structure labelled "Bone spear of the drowned": identical fingerprint, hold and thrust |

Mutation runs (not stored here; runner log): a label read in the solver, a contact capsule offset 5 cm, a fist 5 cm off
its grip, and weight-ignoring timing each fail their named checks.
