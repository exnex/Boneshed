# PR #6 independent desktop validation

Validation starts from PR head `9d69f01d74cdf0681a66d7415334a693f4d6dd55`, based on
`d831cd82b54d168c218991e5cc4bf5f576c6487e` (merged PR #3).

Corrections: remove stale Android instructions; disable Godot touch-to-mouse
emulation; restore browser dodge coverage using the Space key; reject the removed
touch adapter in the packed-resource audit. Combat tuning and runtime combat,
fighter, player and enemy AI scripts remain identical to merged PR #3.

Environment: Godot `4.7.2.stable.official.ed1daf0bf`, Debian 13 Linux x86_64,
Chromium `154.0.8037.57`, Python Playwright `1.62.0`. Native rendering uses
Xvfb/Mesa llvmpipe; browser rendering uses headless Chromium ANGLE/SwiftShader
WebGL, 960×540. These are real rendered engines with scripted input, not a
human assessment of combat feel or a hardware GPU certification.

Historical evidence elsewhere is preserved. Pages publication is deferred until
review and merge; the current hosted build is not the artifact validated here.

## Executed checks and results

All runs were executed on October 17, 2026. Networking was enabled for engine
local sockets, Xvfb and the temporary loopback HTTP servers.

| Command | Result |
| --- | --- |
| `bash scripts/tooling/test.sh` | Initial restricted-sandbox import rejected: engine TCP sockets could not be created. No assertions ran. Log: `native/20261017T111714Z/import.log`. |
| `bash scripts/tooling/test.sh` (network enabled) | Import passed; combat 33/33; three negatives detected; graphical timeout exit 124 at 180 s, 35 passing checks and no failed assertions. Partial evidence: `native/20261017T111734Z/`. |
| `LP_NUM_THREADS=1 bash scripts/tooling/test.sh` | Same results: 35 passing graphical checks, no failed assertions, timeout exit 124 at 180 s. Partial evidence: `native/20261017T112043Z/`. |
| `BONESHED_GRAPHICAL_TIMEOUT=600 LP_NUM_THREADS=2 bash scripts/tooling/test.sh` | **PASS**, import exit 0, combat **33 passed / 0 failed**, graphical **37 passed / 0 failed**, all five captures produced. Full evidence: `native/20261017T112352Z/`, including `runs.json`. |
| `bash scripts/tooling/test_web.sh artifacts/desktop-browser-validation` | **PASS**, both exports/audits passed; Chromium **14 passed / 0 failed**, no skipped checks. See `browser.log`, `browser/checks.json`, `browser/console.json`, `browser/page-errors.json`. |
| `LP_NUM_THREADS=2 bash scripts/tooling/probe.sh artifacts/desktop-browser-probe` | **PASS** (processes and engine-log checks); **75 headless + 7 rendered measurements**. The probe measures behavior rather than asserting design decisions. See `probe/`. |
| `git diff --check`, `bash -n scripts/tooling/test.sh`, Python compile checks for browser/audit tooling | **PASS**. |

Final positive suites total **84 passing assertions, zero failures**. Negative
controls are deliberately separate: guard **30 passed / 3 failed**, deflect
**31 passed / 2 failed**, phase **30 passed / 3 failed**; each exited **1**, detected
its designated fault and satisfied the runner. Timeout runs are not counted as
passes. The optional `BONESHED_GRAPHICAL_TIMEOUT` override preserves the existing
180-second default and all assertions; this two-CPU software-rendering host needed
more wall time.

## Confirmed behavior and artifact audit

The production export boots in Chromium WebGL 2, uses a single thread without
isolation headers, captures the pointer on click and contains no QA bridge.
The separate QA export receives real browser W, mouse movement/LMB/RMB, Tab, R
and Space events: movement, orbit camera, lock-on, 18-point attack damage, held
guard with chip rather than deflection, timed deflection (100 player HP and 42
enemy posture), dodge travel and reset all pass.

`source-audit.json` records zero dangling resource paths, zero touch gameplay
scripts and zero touch-adapter or QA paths in the **17-resource production PCK**.
The removed adapter and UID, compact HUD, per-finger controls and joystick have
no remaining runtime references. Touch-to-mouse emulation is explicitly disabled
rather than restored to Godot's enabled default. Engine mobile-renderer defaults,
disabled mobile compression, browser `touch-action` CSS and generic engine touch
support are not touchscreen gameplay implementations.

The complete source diff was reviewed. Merged PR #3 is an ancestor; combat rules,
fighter, player, AI, native tests and adversarial probe are unchanged relative to
`d831cd8`. Regression checks `hit_does_not_shorten_recovery`,
`hit_does_not_shorten_stagger`, `idle_hit_stagger_unchanged`,
`dodge_out_of_run_keeps_distance` and `dodge_out_of_run_keeps_direction` pass.
The scripted native win remains **334 frames at 100 player HP**.

All five final native captures, all three browser captures, and all three probe
camera captures were visually inspected. Rendered geometry, combat HUD, windup,
deflection, posture break, defeat and dodge views are present; no touchscreen
buttons or virtual joystick appear. Browser captures:

- [Production desktop](browser/01_release_desktop.png)
- [Desktop deflection](browser/02_desktop_deflection.png)
- [Desktop dodge](browser/03_desktop_dodge.png)

## Outstanding issues and deployment handoff

No failing desktop gameplay regression remains. The native default timeout is too
short on this host; use the documented override. Browser logs contain two nonfatal
HTTP 404 resource messages (no URL recorded by the existing console observer),
zero page exceptions and zero fatal engine/WebAssembly errors. Native logs include
unsupported VSync/Fontconfig environment warnings; the complete suites pass.

Known pre-existing combat concerns in `COMBAT_REVIEW.md` remain: parry tapping,
attack stunlock, enemy obstacle handling and close-range camera/telegraph
occlusion. No balance, timing, AI or camera-feel changes were made. Human gameplay
feel and hardware GPU performance remain outside automated verification.

`release.manifest.json` records hashes and every packed path for the tested
production export; `qa.manifest.json` identifies the separate test build. The
unpublished `artifacts/desktop-browser-validation/release.zip` is ready for local
review. After review and merge, regenerate from latest `main` before publishing
with the existing tooling, then validate the hosted build. **No merge or GitHub
Pages publication was performed.**
