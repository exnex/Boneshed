# Evidence — melee lab combat resources (stamina, weight, status)

Generated on the Linux x86_64 cloud image with Godot **4.7.2.stable.official.ed1daf0bf**,
GL Compatibility, llvmpipe under Xvfb, `--fixed-fps 60`, 2026-10-21, by
`bash scripts/tooling/test_melee_lab.sh` (which writes a fresh directory; copy here by
hand). Placeholder bodies and HUD: the clips show that the rules produce the intended,
readable outcomes, **not that stamina, the roll or the statuses feel good.** No human has
played this build. Design and numbers: [MELEE_LAB_COMBAT_RESOURCES.md](../../MELEE_LAB_COMBAT_RESOURCES.md).

| File | Contents |
| --- | --- |
| `runner.log` | Full runner output: parse check, original suite + replay + 2 negative controls, resources suite + replay + 2 negative controls, rendered clips, isolation guard |
| `resources_checks.log` | The 73 resource checks, one JSON line each (contact events filtered out) |
| `resources_results.json` | Measured values: per-build costs, affordability matrix, feint numbers, 10 s barrage, single-hit damage, mitigation, walking/dodge/roll travel, poison by tick rate, slow timing, routing table outcomes, AI stamina/slow behaviour, legality sequence |
| `original_checks_summary.log` | The original suite's summary line (86 checks) |
| `negative_free-feints.log`, `negative_block-applies-status.log` | Failing check lines of the new negative controls (each fails exactly its named check) |
| `clips.json` | Every rendered clip, the contacts it produced, its asserted outcome and verification |
| `sheet_*.jpg`, `clip_*.mp4` | Contact sheets and 30 fps clips (every 2nd physics tick, so 2× slow motion) of the 9 new clips |
| `browser_lab_boot.png` | The exported lab (lab as main scene in a scratch copy, exactly as the Pages workflow does) booted in headless Chromium after pressing F2 and cycling builds: HUD stamina bar with cost ticks, status bars, build line, F2 build table |

| New clip | Shows | Asserted |
| --- | --- | --- |
| `stamina_barrage_evasive` | Venom Knife + cloth chaining cuts as fast as allowed for 5 s; stamina bar and cost ticks | ≥ 7 cuts |
| `stamina_barrage_resistant` | Greatsword + plate, same 5 s: slower, costlier, runs low | fewer cuts than evasive; stamina near/below one attack's cost |
| `stamina_refused_attack` | Two presses with half an attack's stamina: red bar, `NOT ENOUGH STAMINA`, `NO STAMINA` label, nothing happens | 2 refusals, 0 swings |
| `dodge_step_vs_roll` | Balanced build: Space step right, Shift roll left (`ROLL` → `ROLL · open`) | ledger `[dodge, roll]` |
| `poison_venom_knife_hits` | Venom Knife cuts into an unguarded dummy: poison bar fills, `POISONED`, green tint, periodic ticks | hits; ≥ 2 poison ticks |
| `slow_greatsword_hits` | Greatsword overheads into a mail-wearing dummy until `SLOWED` (blue tint); the dummy then walks slowly | hits; slow activated |
| `dodge_avoids_venom` | The opponent's venom cut is dodged | `evaded`; player poison buildup 0 |
| `block_stops_venom` | The same cut blocked by an aligned guard | `block`; player poison buildup 0 |
| `ai_duel_evasive_vs_resistant` | The resistant opponent in attack mode against a static guard, paying its own costs | contacts; 0 AI stamina refusals |

The 14 original clips (telegraphs, block, deflect, bad angle, guard break, thrust, clash,
weapon comparisons, cancels, AI duel, real-input aim) were re-rendered and passed in the
same run; their files are in [`../directional-melee-lab/`](../directional-melee-lab/README.md)
and were not replaced.

## Other suites run on this branch

| Command | Result |
| --- | --- |
| `bash scripts/tooling/test_melee_lab.sh` | passed (see `runner.log`) |
| `bash scripts/tooling/test_builds.sh` | passed: 205 checks, 2 example files regenerate identically |
| `bash scripts/tooling/test_equipment.sh` | passed: rendered equipment placement agrees with resolved builds |
| Lab Web export (`export_web.sh` on a scratch copy with the lab as main scene) + `smoke_web_preview.py` | passed: 127 audited packed resources including `data/melee_lab/combat_resources.json`; real-browser boot smoke passed; console shows no lab initialization or script errors |

Not run: `test.sh` (the long graphical production suite), First Expedition, enemy AI,
worldgen, keyword, marrow, anatomy, animation and camera suites. This branch changes no
production file (the runner's isolation guard checks it), so they exercise unchanged code.
