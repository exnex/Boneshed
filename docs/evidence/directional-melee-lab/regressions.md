# Existing regression suites on this branch

Run 2026-10-20 on the cloud image (Godot 4.7.2.stable.official.ed1daf0bf, llvmpipe,
Xvfb) with the lab files present. The lab changes no production file, so these confirm
that adding it leaves the current game intact; they say nothing about the lab itself.

| Runner | Result | Time |
| --- | --- | --- |
| `bash scripts/tooling/test.sh` | **First run failed:** the `graphical` step hit its default 180 s timeout on this slow software renderer (its log shows every check up to the timeout passing). **Re-run with `BONESHED_GRAPHICAL_TIMEOUT=900` (the runner's own override): all checks passed** — 532 combat-build, 118 combat, 111 graphical checks, all negative controls, timing headless/rendered | 262 s / re-run |
| `bash scripts/tooling/test_builds.sh` | Passed: 205 checks, example files regenerate identically | 8 s |
| `bash scripts/tooling/test_expedition.sh` | Passed: determinism, identity, collision, traversal, selection, pause, restart, salvage/rematch | 204 s |
| `bash scripts/tooling/test_marrow.sh` | Passed: lunge, progression, mutations, pose/equipment negatives, rendered input trace | 124 s |
| `bash scripts/tooling/test_keyword_grammar.sh` | Passed: grammar, vocabulary, old-address compatibility, seeded replay, selection | 151 s |
| `bash scripts/tooling/test_worldgen.sh` | Passed: 80 checks, examples regenerate identically | 17 s |
| `bash scripts/tooling/test_enemy_ai.sh` | Passed: 28 AI checks, cross-process replay, negative controls, rendered clips | 890 s |

Not run: `test_web.sh` / web export (needs export templates; the lab does not touch
export settings or the publishing workflow), `test_anatomy.sh`, `test_animation_lab.sh`,
`test_camera_zoom.sh`, `test_combat_motion.sh`, `test_equipment.sh`,
`test_presentation.sh` (unrelated isolated systems; no shared file changed).
