# Browser and Android testing preview

This is a testing convenience for the existing courtyard duel. It is **not** a
decision to release Boneshed on web or mobile. Combat timing, balance, dodge,
health/posture, fighter integration, and enemy AI are unchanged by this feature.
It branches from `main`; Claude's open combat-correctness PR #3 is not incorporated
or modified. The original prototype's known combat limitations therefore still apply.

## Playing

**Play: https://exnex.github.io/Boneshed/**

The owner made the repository public and enabled branch-based Pages hosting.
The deployed production export was verified in real Chromium with desktop and
phone-emulated landscape viewports. A human also tested the deployed build in a physical phone browser on 2026-10-16: the game was operable, but the touch buttons were not comfortably spaced. This is a known **low-priority testing-UI limitation**, not an Android release requirement. Desktop remains the target platform.
The source repository is now public as well as the exported game assets.

Compiled game logic and assets are inherently downloadable in any browser build.
The export excludes repository documents, original source files, test scripts,
tooling, Git metadata, and credentials. This is not source-code obfuscation or DRM.

On Android, use a current Chrome-compatible browser with WebGL 2 enabled. Turn the
phone sideways. The left stick moves relative to the camera; drag a free area of
the view to orbit. Attack, Guard, Dodge, Lock, and Reset sit along the edges. Hold
Guard to block, or raise it just before impact to try a deflection. Multiple fingers
can move, look, and use buttons simultaneously. Lock toggles target tracking.

Touch controls appear on touch devices or the first touch, and disappear when a
physical keyboard or mouse is used. Desktop WASD, mouse orbit, LMB attack, RMB
guard/deflection, Space dodge, Tab lock, R reset, Escape release, and F3 debug
bindings are retained. Click the canvas to capture the mouse in a browser. Escape
releases it. The game does not request mouse capture during browser startup or
touch-button actions. Browser focus restrictions still apply.

## Reproduce the export

Use exactly Godot **4.7.2.stable.official.ed1daf0bf**:

```sh
cd /workspace/Boneshed
bash scripts/tooling/setup.sh
bash scripts/tooling/setup_web.sh
bash scripts/tooling/export_web.sh artifacts/my-web-build
```

Choose a new, empty output directory for each export. `setup_web.sh` verifies the
official export-template bundle against its release SHA-512 manifest and pinned
checksum, then installs only the two single-threaded web templates. The official
bundle download contains all platforms (about 1.2 GB); it is cached outside the
repository and reused. No third-party game dependency is added.

The `Web` preset uses GL Compatibility, WebAssembly, no threads, no GDExtension,
no service worker, and no PWA cache. It needs no COOP/COEP headers or backend.
Canvas sizing follows the browser viewport; wider landscape screens expand the
logical canvas rather than clipping it. Mobile texture-import support is enabled
for export, without changing the scene's materials or content.

Outputs are `artifacts/my-web-build/` (the site), `artifacts/my-web-build.zip`
(ready-to-upload HTML5 ZIP with `index.html` at its root), and
`artifacts/my-web-build.manifest.json` (file sizes, hashes, and audited PCK paths).
Do not serve the whole repository. `file://` is not a supported WebAssembly host.

## GitHub Pages: publishing and updates

`scripts/tooling/publish_web_preview.sh` uploads an audited production export to
`preview/browser-courtyard`. It keeps that branch independent of `main` and of the
feature PR; only exported assets are included. It never changes repository
visibility, merges code, replaces an unrelated branch, or enables Pages itself.

```sh
bash scripts/tooling/publish_web_preview.sh artifacts/my-web-build
```

**The owner has already enabled GitHub Pages and the hosted URL above works.** For another repository without Pages enabled, the owner needs to do this once:

1. Open repository **Settings → Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**.
3. Select **preview/browser-courtyard**, **/ (root)**, and **Save**.
4. Wait for the Pages deployment, then open the URL GitHub displays on the phone.

Publish only the export branch, not `main` or the source checkout.
For a private repository, Pages availability depends on the account plan and
organization policy. During initial setup the GitHub integration's Pages API request returned `403 Resource not accessible by integration`. The owner subsequently enabled Pages successfully through repository settings. The 403 was an API permission restriction, not an export failure.

For an update, export to a new directory and rerun the publisher. It adds a normal
commit to the asset branch and pushes without force; the feature working tree stays
on its own branch. Pages will deploy the new asset commit after initial setup.

If private-repository Pages is unavailable, create an itch.io project, choose
**HTML**, upload the ready ZIP, mark **This file will be played in the browser**,
enable mobile-friendly/fullscreen embedding, and publish or share its restricted
testing page. No Godot installation is required for the tester. No itch.io account
credentials were available in this task, so that deployment is an owner action.

## Validation

```sh
bash scripts/tooling/test.sh
bash scripts/tooling/test_web.sh artifacts/my-browser-check
```

The existing suite must still pass. Web tooling requires Python 3.11 or newer.
Browser testing uses the preinstalled Python
Playwright package (validated with 1.62.0) and Chromium (`CHROMIUM_BIN` can select an
installed executable). These are test tools, not game dependencies. On a separate
test machine, install Playwright in a virtual environment and provide Chromium.
Run the native and browser suites sequentially in the four-CPU cloud environment;
overlapping software renderers can exhaust the native runner's time budget.

The web runner exports both the production `Web` preset and a separate `Web QA`
preset, starts temporary local HTTP servers for those directories only, and drives
real Chromium/WebGL. The QA build adds a state bridge and deterministic fixtures;
the production artifact audit and browser check ensure that it has no QA bridge or
fixture scripts. Only the production ZIP should be published.

Tests send actual browser keyboard/mouse events and Chromium multi-touch events
through the exported input adapter. They verify mouse capture, movement, camera,
attack damage, lock, guard chip versus timed deflection, simultaneous touches,
release/cancel cleanup, dodge, reset, landscape resizing, and switching back to
desktop inputs. State-based waits avoid mistaking slow software rendering for
missing input. The fresh-deflection fixture schedules an incoming active window
0.08 simulation seconds after a real guard press; the held-guard case uses an
already-held input. It does not change the combat rule's deflection window. The
unchanged native graphical suite separately exercises the enemy's complete attack
windup and the live winning/losing encounters.

The runner has a ten-minute overall browser timeout and 15-second per-state waits,
records assertions and browser console errors,
and captures desktop and phone screenshots. Android emulation exercises viewport,
touch events, and browser execution, but it does not measure a physical Android
phone's GPU, battery use, browser chrome, comfort, latency, or game feel. Those
checks require human testing on the final hosted site.

## Implementation boundaries

- `scripts/ui/touch_controls.gd` owns per-finger roles and translates them to the
  existing Godot actions. Guard emits one press and one release; dragging another
  finger cannot re-arm it. Touch cancellation, focus loss, and viewport changes
  release owned inputs. Browser compatibility mouse events are ignored while
  fingers are down and for 500 ms after touch; keyboard takeover is immediate.
- `player.gd` shares the original orbit calculation with touch drags; only physical
  mouse clicks request pointer lock.
- The HUD retains its desktop layout; touch mode uses compact health/posture bars
  and edge controls to leave the center free.
- `CombatState`, `Fighter`, `Swordsman`, and the existing test suites are unchanged.
- The export uses compiled GDScript; excluded QA code is loaded dynamically only
  when the matching QA command-line flag or export feature is present.

The hosted URL above was verified after the owner enabled Pages.

Final cloud results: **30 combat, 35 native graphical, and 35 browser checks
passed**, with all three fault controls detected. Four browser captures were
inspected; all five native captures match the original prototype byte-for-byte.
See [the committed evidence](evidence/web-preview/README.md) for logs, manifests,
screenshots, and the completed Pages setup. The later native graphical recheck timed out after 180 seconds without a failed assertion before timeout; the previously completed 35-check native pass is retained as earlier evidence, not a claim that the recheck passed.

## Human feedback (2026-10-16)

The owner played the deployed browser preview on desktop and a physical phone. Lock-on worked well and dodge felt nice; overall combat remained too early-stage to judge conclusively. Phone control spacing was uncomfortable, but this does **not** establish a mobile platform requirement. Enemy swing-release/impact telegraph readability and repeatable parry-tapping without enough downside were flagged for **separate combat iterations**; neither is introduced by this browser feature. The hosted preview is based on pre-PR #3 combat code and does not validate PR #3's unmerged movement fixes. Jumping is not yet implemented and remains outside this web-preview scope.
