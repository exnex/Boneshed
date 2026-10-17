# Desktop browser preview

**Play:** https://exnex.github.io/Boneshed/

Boneshed is a **desktop-first game**. The WebAssembly preview is an optional keyboard-and-mouse testing build, **not a mobile or touchscreen game**. Touch joystick, touch combat buttons, touch camera drag, phone HUD and mobile-specific QA have been deliberately removed. No jump feature is implied.

## Controls

WASD move; mouse orbit; left click attack; right click hold guard/tap deflect; Space dodge; Tab lock target; R reset; Escape release pointer capture; F3 show attack volumes. Click the canvas to capture the mouse. Use a desktop browser with WebGL 2.

## Export and hosting

Use pinned Godot **4.7.2.stable.official.ed1daf0bf** and GL Compatibility.

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/setup_web.sh
bash scripts/tooling/export_web.sh artifacts/my-web-build
bash scripts/tooling/test.sh
bash scripts/tooling/test_web.sh artifacts/my-browser-check
```

Use fresh, empty output paths. The Web export is single-threaded and does not require COOP/COEP headers. `export_web.sh` generates the deployable site, ZIP and audited resource manifest. The production export excludes source, tooling and QA scripts; compiled gameplay logic is still inspectable in principle and should not be treated as DRM.

GitHub Pages is configured to serve the exported static assets from `preview/browser-courtyard`. To publish a new export:

```sh
bash scripts/tooling/publish_web_preview.sh artifacts/my-web-build
```

Publishing the new asset branch is separate from merging source into `main`. **Merging this source PR alone does not update the existing hosted preview**; the hosted URL may continue showing the older touch-enabled build until the refreshed export is published. Do not claim the hosted version is updated until checked in a real browser.

## Validation scope

The desktop Web QA build retains browser boot, pointer lock, keyboard movement, attack, camera, target lock, reset, guard and timed deflection checks. The desktop browser suite must be rerun following removal of mobile cases. Native Godot combat and graphical suites, their negative controls, and the adversarial probe remain required. Historical mobile test evidence remains in `docs/evidence/web-preview/` solely as a historical record, **not** evidence of ongoing mobile support.

## Human gameplay notes

On October 16 the owner found lock-on and dodging promising but combat still early. Enemy swing-release timing was not sufficiently telegraphed, and repeated parry input lacked an apparent cost. These belong to separate combat iterations. There is no plan to prioritize mobile touch UX.
