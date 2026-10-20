# Enemy survival AI evidence

Generated with `bash scripts/tooling/test_enemy_ai.sh` on branch `feat/enemy-survival-ai`
(base `main` `8025663`), Godot 4.7.2.stable.official.ed1daf0bf, headless plus Xvfb/llvmpipe
renders. Renders show the player's own third-person camera with a caption naming the
enemy's intent, both phases and the latest decision. **Pictures and bots are not a playtest.**

| File | What it is |
| --- | --- |
| `checks.log` | 28 headless checks: player styles, fairness, variety, omniscience probes, determinism, lunge reach |
| `negative_omniscient.log`, `negative_spam.log` | Negative controls: zero reaction delay, and no repetition limits. Each fails its named checks |
| `results.json` | Per-style duel summaries (winner, health, answers, counters, dodges, intents) |
| `trace_<style>.json` | The enemy's full decision trace for each scripted style (seed 20261020) |
| `replay_trace_seed_*.json` | Same-seed and different-seed replay traces |
| `clips.json` | Trigger tick and frame range of each rendered clip |
| `sheet_<clip>.jpg` | Contact sheet (every 4th tick) of each clip |
| `clip_<clip>.mp4` | The same frames at 30 fps (every 2nd tick, so roughly real time) |
| `compare_styles.gd`, `before_after_*.jsonl` | Before/after harness and its output for the original and new AI |

Clips: `block_then_counter`, `evade_then_reset`, `feint_baits_dodge`, `turtle_break_punish`,
`posture_retreat`, `backstep_out_of_reach`, `whiff_read_spacing`, `lunge_from_range`.

A second process reran all checks and produced byte-identical trace and result files.
