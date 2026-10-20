# Keyword grammar validation — 2026-10-19

Based on latest `main 8025663d90f72f70e2b4ccda2259854212805851` (PR #29). The
[source manifest](source-manifest.json) records SHA-256 hashes of runtime/data,
scenes and QA/tooling sources. [Engine verification](engine-verification.json)
compares the installed binary with the official cached archive and its SHA-512 pin:
**Godot 4.7.2.stable.official.ed1daf0bf**. Linux x86_64, GL Compatibility, Xvfb
1280×720, Mesa llvmpipe software rendering, 60 Hz fixed simulation.

## Executed results

| Check | Result |
| --- | --- |
| Grammar runner | **88 headless / 88 rendered**, no failures; [headless log](logs/grammar-headless.log), [rendered log](logs/grammar-rendered.log) |
| Old-address compatibility | All **3,360** valid original ordered triples at **0 / 1001 / 4294967295** preserve the pre-change canonical-blueprint fingerprint digest (10,080 cases); [baseline captured before editing](logs/legacy-baseline.log) |
| New vocabulary / replay | All **39** words exercised over **32 seeds** each: full repeated layouts byte-identical, stable identity, at least 12 module arrangements for each address |
| Grammar independence | Replacing every grammatical role with noun leaves generated example blueprints identical; grammar adds no generation formula |
| Selector mutation | Removing role filtering fails four UI regressions and exits 1 as expected; [negative control](logs/negative-unfiltered-selector.log) |
| Blueprint runner | **80** checks; all **9,139** unordered vocabulary triples within contract; all **16** old example files regenerate byte-identically (14 blueprints, index, summary) |
| Expedition runner | **743 headless / 751 rendered**; all four old golden layout fingerprints unchanged; [headless](expedition-headless-summary.json), [rendered](expedition-rendered-summary.json) |
| New-vocabulary physics | **36 built fixtures** total, including 18 new: capsule sweeps/floor rays along route, clear arena, solid perimeter, gate closes/opens physically |
| Expedition camera | **9 headless / 12 rendered** checks; obstruction, recovery, reset and cleanup retained |
| Expedition legal-input loop | **1,459 ticks** in both modes; arrival → arena → victory → salvage → equip → inherited attack → rematch victory; input/combat/progression trace SHA-256 identical ([headless](playthrough-headless-summary.json), [rendered](playthrough-rendered-summary.json)) |
| Expedition mutations | Seed independence and disabled collision both fail the expected regressions and exit 1 |
| Native combat/build/render checks | **532** adapter, **118** combat, **63** adapter mutations, 8 encounter regressions, **159 / 209** timing and **111** rendered checks, including expected negatives; [summary](native-summary.json) |
| Shared builds / anatomy | **137 / 190** checks passed; committed examples regenerate identically |

The grammar tests exercise native keyboard popup navigation, mouse launch, menu
bounds, role filtering, adjective duplicates, invalid/boundary seeds, older-order
selection/restart, and returning to grammatical selection when seed replay is off.
Mouse events are transformed from canvas coordinates to window pixels, including
Godot's headless dummy window; this was necessary to test the same UI in both modes.

[Direct source/data audit](compatibility-audit.json) also checks every original
keyword entry for exact equality after removing only `roles`/`legacy` metadata,
and verifies the generator, stream, rules, layout, builder, combat sources and
committed golden examples against the base revision.

After the suites, a text-only duplicate message clarification was checked directly
for both repeated adjectives and **Hollow Drowned Hollow** ([log](logs/duplicate-feedback.log));
validation and generation behavior are unchanged.

The initial `test.sh` passed all checks before its courtyard graphical stage, then
hit that stage's default **180 s** deadline while software-rendered suites were
running concurrently. Only that stage and the remaining rendered timing check were
resumed, using `LP_NUM_THREADS=1` and a **1200 s** external deadline. Both completed
without failed assertions or engine errors. No game/test source fix was required.

## Generated examples

[Full generated records](examples.json) include keywords/themes, seed, blueprint
fingerprint, identity fingerprint, module coordinates and layout fingerprint. The
headless and rendered files are byte-identical.

| Address | Identity (both seeds) | Layout, seed 1001 | Layout, seed 1002 |
| --- | --- | --- | --- |
| Ashen Silent Sanctuary | `46d73a6b` | `3537de9e` | `0f83fab0` |
| Moonlit Thorned Garden | `8b51a598` | `75e722ec` | `c2298172` |
| Weeping Forgotten Requiem | `442da094` | `79c1edd4` | `ee82a96b` |
| Frozen Gilded Citadel | `2f51a35c` | `160e688f` | `1c23c310` |
| Smoldering Pallid Necropolis | `6360d707` | `01021ae8` | `a29c335b` |
| Veiled Sunken Dream | `4363fc43` | `abacd7d9` | `264cbe12` |

Five pairs change module coordinates. Frozen Gilded Citadel repeats its module
arrangement for this pair; its seed-dependent blueprint/scenery still differs.
The existing bounded route families can repeat. The 32-seed coverage separately
checks geographic variety for every vocabulary word; a different layout hash alone
is not treated as proof of different geography.

## Captures inspected

- [Normal selection](rendered/01_selection.png): labeled adjective/adjective/noun
  dropdowns, seed replay, older-order option and Begin remain visible at 1280×720.
- [Older-order selection](rendered/03_legacy_selection.png): **Tempest Frozen
  Towering / 1001** is available in exact original order, with explicit older-address
  labels and seed replay enabled.
- [Ashen Silent Sanctuary arrival](rendered/02_sanctuary.png): the chosen name/seed
  are visible in the game; the existing builder renders its ruined approach,
  pale lighting and warm seams without a new noun-specific geometry algorithm.

These are actual engine renders. No physical keyboard/mouse, desktop GPU performance,
high-refresh behavior, audio or human game-feel acceptance is claimed. Semantics
and vocabulary quality still need human review. New nouns reuse the bounded modules
and existing visual themes rather than promising bespoke locations.

## Reproduce / handoff

Use fresh evidence directories:

```sh
bash scripts/tooling/test_worldgen.sh artifacts/worldgen-new
bash scripts/tooling/test_keyword_grammar.sh artifacts/grammar-new
LP_NUM_THREADS=1 bash scripts/tooling/test_expedition.sh artifacts/expedition-new
BONESHED_GRAPHICAL_TIMEOUT=1200 LP_NUM_THREADS=1 bash scripts/tooling/test.sh artifacts/native-new
bash scripts/tooling/test_builds.sh artifacts/builds-new
bash scripts/tooling/test_anatomy.sh artifacts/anatomy-new
```

No browser export or preview publication was requested or performed. Web still
selects the previous salvage courtyard; no export/input bindings changed and the
worldgen JSON remains covered by the existing export filter. `test_web.sh` was not
run. Enemy AI, combat presentation and weapon mechanics are unchanged. No new
assets, dependencies, autoloads or persistent state were added. The session shell
owns its keyword catalog; restart/return behavior is retained.

**Proposed roadmap/status delta for Command Center:** keyword grammar and curated
selection implemented with exact old-address replay; original generator semantics
and legacy fixtures retained. Review this focused PR, then request human reading of
the six examples and a desktop playtest using a fresh seed and an older address.
Command Center owns review/merge and roadmap reconciliation; `ROADMAP.md` was left
for the coordinator to avoid parallel edits with Claude's enemy-survival task.
Broader generation semantics, keyword rarity/unlocks, combat-direction research,
web refresh and human feel/performance acceptance remain open as previously recorded.
