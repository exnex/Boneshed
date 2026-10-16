# Milestone 1 validation evidence

Boneshed now has a runnable Godot 4.7.2 courtyard duel: camera-relative movement,
orbit/lock camera, light attacks, guard/timed deflection, dodge, health/posture,
punish windows, deterministic swordsman AI, death, and reset. Rules are shared
between both actors; all specific combat mechanics remain provisional.

## Results

| Run | Actual exit | Result |
| --- | --- | --- |
| Headless import | 0 | Clean script/project import |
| Combat rules | 0 | 30 passed, 0 failed |
| Negative: guard mitigation disabled | 1 | Expected failure detected; 3 assertions failed |
| Negative: deflection window removed | 1 | Expected failure detected; 2 assertions failed |
| Negative: windup made active | 1 | Expected failure detected; 3 assertions failed |
| Xvfb GL Compatibility gameplay | 0 | 35 passed, 0 failed |

The graphical run used Mesa llvmpipe, simulated input, real physics-world spatial
validation, a live-AI winning encounter, and a losing encounter/reset. No required
checks were skipped. See `runs.json` for process outcomes, `graphical.json` for
per-check results and captured actor states, and the logs for full output.
`engine-verification.json` records the verified official archive and checksum.

## Inspected captures

- [Initial courtyard](01_initial_courtyard.png): both grounded actors and full health.
- [Enemy windup](02_enemy_windup.png): amber preview box, sword pose, and windup HUD.
- [Successful deflection](03_successful_deflection.png): cyan feedback, full player
  health, enemy recoil and 42 posture.
- [Posture break](04_posture_break.png): enemy at 100 posture, gold marker, punish HUD.
- [Enemy defeat](05_enemy_defeat.png): zero enemy health, fallen pose, victory HUD.

All five images were visually inspected against their frozen state records.
An initial braking defect and one-frame death-pose lag were fixed before this run.
VSync switching is unsupported by the Xvfb driver; this warning did not prevent
rendering. There were no engine/script errors in the final logs.

## Review and next step

Implementation files live in `scenes/`, `scripts/combat/`, `scripts/characters/`,
`scripts/ai/`, `scripts/qa/`, and `scripts/tooling/`. The root `project.godot` pins
the GL Compatibility feature set; tooling rejects other engine builds. The README
and `docs/COMBAT_PROTOTYPE.md` cover setup, controls, timing, and limitations.

Human review should focus on interruption/stunlock, camera framing, telegraph
readability, deflection timing, dodge invulnerability, and punish damage. Primitive
visuals are silent, guard is omnidirectional, and hit validation uses a forward box.
Automated success does not establish enjoyable or balanced combat. Evaluate this
duel before implementing salvage. No inventory, backend, multiplayer, Tower, or
world-generation systems are included.

Reproduce from the repository root with `bash scripts/tooling/setup.sh` followed by
`bash scripts/tooling/test.sh`. Keep the PR in draft for ChatGPT and Claude review;
do not merge without human review.
