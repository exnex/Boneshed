# First Expedition validation — 2026-10-19

Started from main `f5ddb49acdac4a79df349ec13d4c5a4cd1f8c10e`; rebased before PR onto
`79289f0e0962be5da51d8d4134039a44296ba47a`, which changes only coordination documentation.
The tested runtime/data sources are unchanged by that rebase. Implementation is the head
commit of `feat/first-expedition-slice` / its PR, not merged main. The PR handoff
records the exact commit. [Source hashes](source-manifest.json) bind the runtime,
data, scenes and test/tooling sources used here. [Engine verification](engine-verification.json)
records the official archive checksum and exact `4.7.2.stable.official.ed1daf0bf` pin.

Linux x86_64, GL Compatibility, Xvfb 1280×720, Mesa llvmpipe software rendering,
60 Hz fixed simulation. The host has a two-CPU quota. No physical keyboard/mouse,
desktop GPU, audio, high-refresh or human gameplay acceptance was tested.

## Executed checks

| Check | Result |
| --- | --- |
| Exact engine setup, editor import and default headless boot | Passed; official SHA-512 and version checked |
| Expedition generation / world / UI | 671 headless and 679 rendered assertions passed |
| Determinism and identity | 192 repeated address/seed fixtures; six addresses cover all 16 words; 32 seeds each preserve identity; each address produces at least 12 distinct module arrangements; four fixed golden fingerprints |
| Physics | 18 built fixtures: capsule sweeps + floor rays along routes, empty central 20 m arena, every perimeter edge solid, gate closes/opens physically |
| Generated-world camera / cleanup | 9 headless / 12 rendered assertions: open arena, gate/column obstruction, recovery, low parapets, retained preference and retry spawn; also queues a valid contact before returning and rejects engine/script errors after removal |
| Expedition legal-input loop | Passed in 1,459 physics ticks; arrival → reliquary → arena → defeat → F salvage → E equip → N rematch → Q inherited attack → second victory; exact headless/rendered trace equality |
| Expedition negative controls | Removing seed influence fails geographic diversity; disabling environment collision fails actual route/boundary checks; both isolated runs exit 1 as expected |
| Courtyard native runner | Passed: 532 adapter/build, 118 combat, 111 rendered checks; encounter/timing probes and expected negative/mutation runs retained |
| Build / anatomy / blueprint runners | Passed: 137 / 190 / 80 checks; all committed examples regenerate identically |
| Historical Marrow runner | Passed: 193 rule/progression checks, source mutations, pose negative control, rendered/input playthrough and exact trace equality |
| Historical zoom / presentation runners | Passed: 89/98 zoom and 319/326 presentation assertions (headless/rendered), including expected negative controls |
| Animation lab | Passed: 76 rule/clip checks, warp negative control and all five rendered sequences (overview, timing, move_attack, four_arm, closeup) |
| Web export / browser | Both exports audited; unchanged browser harness passed 27/27 checks on retry with a longer deadline; no fatal page/engine errors |

The existing build, anatomy and animation-lab assertions of the default entry scene
were updated to First Expedition. Their other checks remain intact; the courtyard
and salvage courtyard are still explicitly selected by their regression runners.
Fixtures that position actors or suspend AI are labeled as such. The expedition
playthrough reuses the existing legal-input bot and performs none of those writes.

The first browser attempt hit its fixed 600 s deadline during concurrent software
rendering. Both exports completed and were audited. The unchanged browser harness
was retried on those exports with a 1,800 s external deadline; its separate result
is recorded in the final manifest. No browser preview was published. Web retains
the salvage courtyard via the feature override and does not test expedition UI.

## Visual evidence and inspection

The PNGs are actual Godot renders, not generated illustrations. Representative
captures were opened and inspected, including:

- [Selection](rendered/01_selection.png), [pause menu](rendered/03_pause.png),
  [arrival](rendered/00_arrival.png), and [reliquary approach](rendered/00_reliquary.png):
  controls/address/seed are visible and the inlay connects the navigable rooms.
- [Drowned, seed 1001](rendered/04_drowned_overview.png) versus
  [seed 1002](rendered/07_drowned_overview.png): changed bend/spacing with the same
  water, roofed ruin and monumental silhouette language.
- [Frozen](rendered/05_frozen_overview.png) and
  [fire/ice reliquary](rendered/08_fire_ice_reliquary.png): ice panels/shards,
  separate scorched cracks, and bone ribs appear in geometry rather than only text.
- [Enemy lunge](rendered/02_enemy_lunge_telegraph.png),
  [victory](rendered/04_enemy_defeat.png), [equipped](rendered/06_augmentation_equipped.png)
  and [inherited lunge](rendered/07_first_inherited_lunge.png): existing combat and
  equipment presentation render in the generated arena with the expected prompts.
- [Open-arena camera](rendered/09_open_arena_camera.png),
  [gate obstruction](rendered/10_portcullis_camera.png) and
  [column obstruction](rendered/11_column_camera.png): collision retracts the view;
  it can crop feet below the selected zoom minimum. Close fighters still overlap
  visually in some attack frames. These remain human camera/readability watch items.

Inspection limits: abstract primitive architecture repeats heavily, floors remain
flat causeways above a void, water/ice/fire are decorative rather than physical,
and some themes are subtle. Screenshots establish visible composition and gross
framing, not that the address is evocative or the duel feels fair. No sound, real
terrain, authored character assets or human acceptance is claimed.

## Reproduce

```sh
bash scripts/tooling/setup.sh
LP_NUM_THREADS=1 bash scripts/tooling/test_expedition.sh artifacts/expedition-new
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test.sh artifacts/native-new
bash scripts/tooling/test_builds.sh artifacts/builds-new
bash scripts/tooling/test_anatomy.sh artifacts/anatomy-new
bash scripts/tooling/test_worldgen.sh artifacts/worldgen-new
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test_marrow.sh artifacts/marrow-new
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test_camera_zoom.sh artifacts/zoom-new
bash scripts/tooling/test_presentation.sh artifacts/presentation-new
bash scripts/tooling/test_animation_lab.sh artifacts/lab-new
bash scripts/tooling/test_web.sh artifacts/web-new
```

Use fresh output directories. `LP_NUM_THREADS=1` on the final expedition run reduces
software-renderer contention; it does not change layout or combat rules. Full local
traces and animation sequences remain under ignored `artifacts/`; curated captures,
assertion logs, summaries and trace hashes are committed here.

Proposed roadmap delta: review and merge the bounded integration, then request an
owner desktop playtest across two seeds and contrasting addresses. Retain the
complete-salvage-loop, close-camera, high-refresh and earlier combat watch items;
keep keyword design, extraction, authored-asset policy, Tower and backend open/deferred.
Command Center owns review, merging and roadmap reconciliation under main's latest
parallel-ownership update. This PR supplies the delta without editing ROADMAP.md or
combat animation/presentation resources. Three existing QA files change only their
assertion of the default entry scene, including the isolated animation lab's assertion.
