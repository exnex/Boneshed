# Evidence — directional melee lab

Generated on the Linux x86_64 cloud image with Godot **4.7.2.stable.official.ed1daf0bf**,
GL Compatibility, llvmpipe (LLVM 20.1.2) under Xvfb, `--fixed-fps 60`, 2026-10-20.
Reproduce: `bash scripts/tooling/test_melee_lab.sh` (writes a fresh `artifacts/melee-lab-*`
directory). Placeholder bodies and poses: the clips show readability of telegraphs,
trajectories and outcomes, not animation quality, and **nothing here shows game feel.**

| File | Contents |
| --- | --- |
| `runner.log` | Output of `test_melee_lab.sh`: parse check, checks, cross-process replay, negative controls, rendered clips, isolation |
| `checks.log` | 77 deterministic checks, one JSON line each, plus every contact event |
| `results.json` | Measured values: swing profiles, direction-change cost, guard raise times, alignment matrix, reach, AI fairness timings, AI direction counts |
| `negative_no-substeps.log` | Contact without swept substeps: `fast_blade_cannot_tunnel_through_guard` fails as required |
| `negative_omniscient.log` | AI with zero reaction delay: `ai_guard_waits_for_reaction_delay` and `late_redirect_is_seen_only_after_delay` fail as required |
| `rendered.log`, `clips.json` | Rendered capture; each clip lists the contact events it produced and the outcome it had to produce |
| `sheet_*.jpg`, `clip_*.mp4` | Contact sheets (every n-th captured frame) and 30 fps clips (every 2nd physics tick, so 2× slow motion) |

| Clip | Shows | Asserted outcome |
| --- | --- | --- |
| `telegraph_all_directions` | Opponent cuts right→left, left→right, overhead, high right, high left, thrust; colour-coded arcs, chamber poses, intent labels | hits |
| `block_aligned` | Player right→left into a settled left guard (hitboxes on) | block |
| `deflect_timed_press` | Same, guard freshly pressed ≈ 0.07 s before contact | deflect |
| `wrong_side_guard_hit` | Guard held on the right; the cut arrives on the left | hit (guard bypassed) |
| `bad_angle_misaligned` | Overhead onto a centre guard (hitboxes on) | misaligned |
| `guard_break_heavy_vs_light` | Greatsword overhead into a long-knife high guard | guard break |
| `thrust_vs_center_guard` | Thrust into a centre guard | block |
| `clash_crossing_blades` | Two live cuts sweeping across each other | clash |
| `weapon_compare_knife/sword/greatsword` | Opening cut then flowing follow-up into the air, trails on: preparation, arc speed, recovery per weapon | — |
| `cancel_guard_and_dodge` | Windup cancelled by a fresh guard; a swing cancelled by a dodge | — |
| `ai_duel` | Seven seconds of the opponent's duel mode against a static high guard | — |
| `player_view_input_aim` | Real LMB + mouse-flick events through the player camera and HUD cursor: tap starts a follow-up, flick up redirects to an overhead | hit |

Existing regression suites run on this branch are recorded in `regressions.md`.
