# Distinct keyword slots — 2026-10-20

Based on latest `main` **31ec237cf6617cf21685d4f62ad4a72654ee6386**. Normal
selection divides the existing 39 words into **12 environment/state adjectives,
12 character/quality adjectives and 15 place/concept nouns**: 2,160 combinations,
with no word shared between pools. [Full vocabulary and replay instructions](../../KEYWORD_GRAMMAR.md).

The session shell owns its catalog; this adds no global state, assets or dependencies.
All three legacy replay dropdowns offer every catalog word, preserving both the
original 16-word orders and addresses recorded with PR #30's shared adjective lists.
Repeated words remain invalid, as before. In normal selection, Hollow belongs only
to the quality slot; its semantic senses are unchanged for every address/order.

## Compatibility evidence

[Direct audit](compatibility-audit.json) confirms that every existing catalog entry
is identical after removing only `roles`. Every other runtime source, including
blueprint generation, streams, rules, layout, builder, combat, AI, build, anatomy and
character presentation, is byte-identical to the base revision. The
[source manifest](source-manifest.json) records the checked source hashes.

The new [baseline fixture](../../../scripts/qa/fixtures/keyword_slot_baseline.json)
was captured from unchanged main before edits ([capture log](logs/baseline-capture.log)).
It pins every previous grammatical address at seeds **0 / 1001 / 4294967295**:
**8,786 × 3 = 26,358** blueprint fingerprint comparisons. The existing original
16-word ordered-triple digests add **3,360 × 3 = 10,080** comparisons. These sets
partly overlap; they establish compatibility for two historical selection contracts.
Twelve old example identity/blueprint/layout records and four old expedition layout
fixtures remain pinned. All 16 golden worldgen files regenerate byte for byte.

Catalog validation rejects missing, malformed, unknown or multiple roles and empty
slot pools. Automated checks independently compare the actual visible menu words
for disjointness. Isolated mutations must fail when Frozen is assigned to both
adjective pools or when the selector's role filter is removed. Every catalog word
is also exercised in its own slot over 32 seeds, checking repeatability, stable
identity and at least 12 geographic module arrangements per address. Role metadata
alone cannot change generated blueprints.

## Executed checks

Use the [verified pinned engine](engine-verification.json):
**Godot 4.7.2.stable.official.ed1daf0bf**. The cached official archive matches the
repository SHA-512 pin and official cached manifest; its executable bytes match the
installed engine. Renders use Linux x86_64, GL Compatibility, Xvfb 1280×720,
Mesa llvmpipe and fixed 60 Hz simulation. This is software-rendered validation,
not a desktop GPU performance measurement or human playtest.

| Check | Result |
| --- | --- |
| Keyword grammar | **192 headless / 189 rendered**, zero failures; [headless](logs/grammar-headless.log), [rendered](logs/grammar-rendered.log) |
| Legacy blueprint fingerprints | **36,438** comparisons across the original and previous grammatical address sets; 12 pinned old example identity/blueprint/layout records also pass |
| Meanings and formulas | All **39** entries unchanged except roles; all other runtime sources match base |
| Overlap mutation | Catalog load exits **1**, with `library_valid` false ([log](logs/negative-vocabulary-overlap.log)) |
| Unfiltered selector mutation | Exits **1**, including both visible-menu overlap and role-filter assertions failing ([log](logs/negative-unfiltered-selector.log)) |
| Worldgen | **80** checks; all **16** golden files regenerate byte-identically ([run](logs/worldgen-run.log)) |
| Expedition | **743 headless / 751 rendered**, zero failures, **192** unique layouts; all four pinned layouts unchanged |
| Expedition camera | **9 headless / 12 rendered**, zero failures |
| Legal-input salvage/rematch | **1,763 ticks** in each mode; arrival → duel → salvage → equip → inherited attack → rematch victory; JSON traces equal ([hashes](playthrough-trace-verification.json)) |
| Expedition mutations | Seed independence and disabled collision fail the expected assertions and exit **1** ([run](logs/expedition-run.log)) |
| Native combat/build regression | **532** adapter / **118** combat / **63** adapter mutations / **8** encounters / **159 headless + 209 rendered** timing / **111** courtyard graphical checks; expected negatives also pass ([summary](native-summary.json)) |

After the full grammar runner, the rendered scenario was rechecked with a brief
frame wait before the legacy-menu capture so the newly shown panel is drawn before
saving. It again passed **189/189**, with identical generated example records.
No runtime code changed during this capture synchronization.

The first restricted-sandbox editor import could not open its local socket; reruns
with network/socket capability succeeded. The broader native runner completed its
headless stages, then hit the courtyard graphical stage's **180 s** deadline while
software-rendered suites were concurrent ([initial run](logs/native-initial-run.log)).
Only that stage and its remaining rendered timing check were resumed, with
`LP_NUM_THREADS=1` and a **1200 s** external deadline. Both resumed stages passed without failed assertions or engine errors. No gameplay
or regression-source changes were needed.

## Examples and captures

[Generated example records](examples.json) contain the address, seed, identity,
blueprint, layout, themes and module coordinates. Headless and rendered records
must be byte-identical. The first five addresses below are unchanged from earlier
evidence; Veiled Forsaken Dream illustrates a new legal pairing. The earlier
Veiled Sunken Dream remains pinned and playable through legacy replay.

| Address | Identity, both seeds | Layout, seed 1001 | Layout, seed 1002 |
| --- | --- | --- | --- |
| Ashen Silent Sanctuary | `46d73a6b` | `3537de9e` | `0f83fab0` |
| Moonlit Thorned Garden | `8b51a598` | `75e722ec` | `c2298172` |
| Weeping Forgotten Requiem | `442da094` | `79c1edd4` | `ee82a96b` |
| Frozen Gilded Citadel | `2f51a35c` | `160e688f` | `1c23c310` |
| Smoldering Pallid Necropolis | `6360d707` | `01021ae8` | `a29c335b` |
| Veiled Forsaken Dream | `d9bdd2dc` | `8282fa78` | `a0a6ef81` |

- [Normal selection](rendered/01_selection.png): all three role labels and controls
  fit the desktop viewport; the default Drowned Hollow Cathedral remains available.
- [Legacy selection](rendered/03_legacy_selection.png): Tempest Frozen Towering
  remains selectable in its recorded order, with seed 1001 and older-address labels.
- [Ashen Silent Sanctuary](rendered/02_sanctuary.png): the unchanged builder renders
  its existing causeway and atmospheric scenery after a native mouse launch.

## Reproduce and review

Use fresh output directories:

```sh
LP_NUM_THREADS=1 bash scripts/tooling/test_keyword_grammar.sh artifacts/slots-grammar-new
bash scripts/tooling/test_worldgen.sh artifacts/slots-worldgen-new
LP_NUM_THREADS=1 bash scripts/tooling/test_expedition.sh artifacts/slots-expedition-new
BONESHED_GRAPHICAL_TIMEOUT=1200 LP_NUM_THREADS=1 bash scripts/tooling/test.sh artifacts/slots-native-new
```

Human review: read the category lists and examples, launch a fresh world, replay
**Veiled Sunken Dream / 1001** and **Tempest Frozen Towering / 1001** using both
replay checkboxes, then turn seed replay off and confirm the three distinct lists
return. Exact positional weights, interpretation and geography remain provisional.
No export/input bindings changed; browser export, preview publication, anatomy and
standalone build suites were not run for this vocabulary-only change. The native
regression and expedition runners cover existing combat/build and salvage/rematch
behavior without editing those systems.

**Roadmap/status delta for Command Center:** distinct keyword pools implemented with
all-catalog legacy replay and automated overlap rejection. Review this focused PR
and vocabulary curation; human desktop acceptance remains open. Command Center owns
review, merging and roadmap reconciliation; `ROADMAP.md` is intentionally left to
the coordinator to avoid competing edits during Claude's equipment/salvage work.
No new worldgen formulas, geometry, combat mechanics or equipment changes are included.
