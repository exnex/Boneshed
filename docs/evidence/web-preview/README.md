# Browser-preview validation

All final checks executed with Godot **4.7.2.stable.official.ed1daf0bf**.
The official single-threaded templates passed the pinned SHA-512 check.

| Check | Result |
| --- | --- |
| Headless import | Passed |
| Existing combat suite | 30 passed, 0 failed |
| Existing native graphical suite | 35 passed, 0 failed |
| Three injected-fault controls | Expected exit 1; guard/deflection/phase assertions detected the faults |
| Production and QA Web exports | Passed |
| Real Chromium/WebGL browser suite | 35 passed, 0 failed |
| Browser page/fatal engine errors | None |
| Native screenshot comparison | All 5 byte-identical to original milestone-1 evidence |
| Public artifact audit | 19 production PCK entries; no docs, tooling, original source files, or QA scripts |
| Pages-branch upload and repeat | Uploaded; repeat correctly reports identical export already current |
| Pages enablement | Blocked: GitHub integration API returns 403 |
| Deployed playable site / physical Android phone | Not verified |

The browser suite used Chromium **154.0.8037.57**, Python Playwright **1.62.0**,
headless SwiftShader/WebGL 2, and Android touch emulation at 844×390 and 915×412.
It exercised desktop pointer capture, keyboard movement, camera, attack damage,
lock and reset; touch joystick, camera, attack damage, dodge, lock and reset;
held guard versus newly raised deflection; simultaneous touches, independent
finger release, cancellation, keyboard/mouse takeover, and landscape resizing.
Both actual production and QA exports booted. The production builds had no QA bridge.

The QA-only bridge arranges deterministic positions and incoming attacks; actual
input comes from browser keyboard/mouse or CDP touch events. For the fresh-deflection
fixture, an incoming attack activates 0.08 simulation seconds after guard input.
The unchanged native suite separately covers complete enemy windups and live duels.

Earlier validation caught compatibility mouse events incorrectly switching off
the touch overlay; that adapter defect was fixed. Driver diagnosis also corrected
which finger Chromium's touch-end event released. Final assertions explicitly
check that releasing the camera finger does not release guard. A run that overlapped
the native and browser renderers exhausted its time budget; the final recorded
suites ran sequentially and exited 0. No combat assertions or timings were changed.

## Inspected browser captures

- [Desktop release](browser/01_release_desktop.png): original HUD and running duel.
- [Phone deflection](browser/02_phone_deflection.png): full player health, enemy
  posture pressure, deflection text, held guard, and edge controls.
- [Resized phone layout](browser/03_phone_landscape.png): expanded landscape canvas
  and controls inside the 915×412 viewport.
- [Phone production release](browser/04_release_phone.png): real release build
  with touch overlay and active enemy, without fixtures.

`browser/checks.json`, console and page-error records, and `native/` contain the
underlying outcomes. `verification.json` records tool versions and the release ZIP
hash. The two export manifests list every packed resource and output-file hash.
`desktop-capture-comparison.json` records the original/native screenshot hashes.

## Deployment state

Only the production export was uploaded to `preview/browser-courtyard`, commit
`52fd703fdb1f7f35c3f709c511d21509316fefc8`. Its files match the tested release
byte-for-byte. The source repository remains private. `deployment.json` records
the Pages API denial. There is **no verified playable URL yet**.

Owner action: **Settings → Pages → Deploy from a branch → preview/browser-courtyard
→ / (root) → Save**. After deployment, verify the URL GitHub displays on a physical
Android phone. If private-repository Pages is unavailable, upload the production
ZIP to an itch.io HTML project as described in `docs/WEB_PREVIEW.md`.

Reproduce with `bash scripts/tooling/test.sh`, then
`bash scripts/tooling/test_web.sh artifacts/new-web-check`. Test physical-phone
performance, browser chrome/rotation, comfort, and timing feel by hand; emulation
does not establish those results. PR #3 and combat-rule/AI/fighter files are unchanged.
