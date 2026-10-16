# Combat review evidence

Evidence for [`../../COMBAT_REVIEW.md`](../../COMBAT_REVIEW.md). Engine
`4.7.2.stable.official.ed1daf0bf` (official archive, SHA-512 verified), Linux x86_64,
Xvfb + Mesa llvmpipe (LLVM 20.1.2), GL Compatibility, 60 Hz physics, `--fixed-fps 60`.
The milestone-1 evidence in `../milestone-1/` is preserved unchanged.

| Folder | Code | Contents |
| --- | --- | --- |
| `baseline/` | Unmodified `main` (`4a15514`) | Independent rerun of Codex's suites: 30/0 combat, 35/0 graphical, negatives 3/2/3 failed as expected |
| `before-fix/` | `main` + new regression tests only | The four new checks fail on the original rules: `hit_does_not_shorten_recovery`, `hit_does_not_shorten_stagger` (combat 31/2), `dodge_out_of_run_keeps_distance`, `dodge_out_of_run_keeps_direction` (graphical 35/2). The runner stops at the first failing suite, so the graphical log was produced with the runner's exact command |
| `after-fix/` | This branch | Full `test.sh` run: 33/0 combat, 37/0 graphical, negatives still 3/2/3, `runs.json` exit codes |
| `probe/` | Both | `probe-original-code.json` (fighter/rules from `main`) and `probe-after-fixes.json`: adversarial measurements, see the review. `rendered/` holds three Xvfb camera captures and their records |

## Screenshot reproducibility

The five gameplay checkpoints from the baseline run, the after-fix run and Codex's
`../milestone-1/` captures are byte-identical:

| Capture | MD5 (all three runs) |
| --- | --- |
| `01_initial_courtyard.png` | `28fd03ab…` |
| `02_enemy_windup.png` | `fba2d0e3…` |
| `03_successful_deflection.png` | `eb2bb49c…` |
| `04_posture_break.png` | `470e5d07…` |
| `05_enemy_defeat.png` | `c000e184…` |

They are therefore not duplicated here. The new captures are:

- `probe/rendered/probe_close_range_windup_occlusion.png`: locked at 1.85 m during an
  enemy windup. The player's body covers the enemy torso and the windup ground box.
- `probe/rendered/probe_cornered_camera.png`: player locked in a corner. The spring arm
  is at 1.04 m and the player's body fills the left of the frame.
- `probe/rendered/probe_enemy_between_camera_and_player.png`: free camera with the
  enemy behind the player. The view stays usable.

The only engine warning in any log is the expected Xvfb VSync message. No `ERROR` lines.
