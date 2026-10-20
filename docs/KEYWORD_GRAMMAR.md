# Keyword address grammar

The owner confirmed **adjective + adjective + noun** addresses and, after native
playtesting, distinct curated vocabularies for all three slots. Normal selection
now offers **12 environment/state adjectives**, **12 character/quality adjectives**,
and **15 place/concept nouns**. Each word belongs to exactly one selectable slot:
all **2,160** combinations contain three different words.

| Slot | Role | Available words |
| --- | --- | --- |
| 1 | Environment / state adjective | Ashen, Buried, Drowned, Frozen, Lightless, Moonlit, Smoldering, Sunken, Veiled, Weeping, Windswept, Withered |
| 2 | Character / quality adjective | Barren, Forgotten, Forsaken, Gilded, Hallowed, Hollow, Pallid, Profane, Shattered, Silent, Thorned, Towering |
| 3 | Place / concept noun | Cathedral, Chasm, Citadel, Dream, Garden, Labyrinth, Marsh, Necropolis, Ossuary, Requiem, Sanctuary, Sepulcher, Shore, Spire, Tempest |

Examples include **Ashen Silent Sanctuary**, **Moonlit Thorned Garden**, **Weeping
Forgotten Requiem**, **Frozen Gilded Citadel**, **Smoldering Pallid Necropolis**, and
**Veiled Forsaken Dream**. Other combinations include **Buried Hallowed Sepulcher**,
**Windswept Shattered Spire**, **Sunken Profane Cathedral**, and **Withered Towering
Garden**. They cover ruined, wild, memorial, cold, fire/death and
uncertain/dreamlike themes. All 39 existing words retain their individually authored
semantic data using the existing axes/tags/theme pools. Their effects and visual interpretation remain
provisional, and a concept noun does not promise a bespoke level type. Existing
curated causeways and abstract scenery are reused.

## Selection and replay

Use mouse-operated native dropdowns, or Tab to focus and Enter/arrows to select.
Lists scroll. Choose **Begin expedition** for a fresh entropy seed. For a recorded
address, enable **Replay an existing seed**, choose the words in their original
order and enter its seed (0–4294967295).

If a recorded address does not fit the new slot lists, also enable **Replay an
older address (all words, any order)**. All three slots then offer all 39 catalog
words, with labels identifying older addresses. This includes both the original
16-word addresses and those recorded under the previous shared-adjective selector.
For example, **Tempest Frozen Towering / 1001**, **Veiled Sunken Dream / 1001**, and
**Frozen Barren Hollow / 1001** remain playable exactly as recorded. **Hollow** is now
selectable only as a quality in normal mode; its original senses, including its
place reading in older addresses, are unchanged. Repeated words remain invalid.
Turning seed replay off restores grammatical selection. Existing restart and return
behavior, including salvage reset, is unchanged.

## Compatibility audit

| Surface | Result / policy |
| --- | --- |
| All 39 keyword ids and effects | Preserved; only `roles` metadata changes; no aliases, substitutions or sense changes |
| All 3,360 original valid ordered triples | Preserved in the generator and older-address replay UI; duplicates still rejected |
| All 8,786 previous grammatical addresses | Preserved through expanded replay, including words introduced in PR #30 |
| Existing WorldBlueprint consumers | Schema `0.1.0`, semantic `data_version: prototype-0.1`, position weights, namespace, streams and formulas unchanged |
| Old golden blueprints | All 14 JSON examples plus index and summary regenerate byte for byte |
| First Expedition seed fixtures | All four pinned layout fingerprints unchanged, including Drowned Hollow Cathedral / 1001 (`1c1b4200`) |
| New selection | Filters by one of `environment_adjective`, `quality_adjective`, `noun`; filters are independent of current selections |
| Persisted saves | The slice has no disk-save system; a recorded address + seed needs no data migration |

The vocabulary is unchanged. `roles` must be a one-element array naming one of the
three slot roles; multi-role entries (overlap), unknown roles, malformed roles, and
empty slot pools fail catalog validation. `legacy` remains the validated historical
marker for membership in the original 16-word vocabulary; replay now uses the
complete catalog rather than that marker. Neither enters blueprints, identity
hashes or stream seeds. The existing semantic data version is deliberately retained
to avoid changing old fingerprints when selection metadata changes.
Low-level `Blueprint.generate` and `Layout.generate` keep their permissive ordered
input contract for existing consumers/fixtures. `Library.is_grammatical` is the
normal-selection boundary; `keywords_for_slot` supplies the UI options. Changing
roles alone cannot alter generation (regression tested).

**Migration:** no address/seed is migrated or invalidated. The visible change is
where off-grammar old addresses are selected: the explicit older-order replay mode.
Such orders no longer appear in fresh-world dropdowns. Old documentation examples
remain historical regression fixtures, including three-descriptor combinations.

This does **not** approve new slot-specific generation formulas: no first-slot
weather rule, second-slot danger budget, noun-specific layout algorithm, difficulty
rating, enemy behavior, loot system or change to contradiction handling is added.
The pre-existing positional weights remain provisional. Identity still depends on
words and order; named random streams vary the blueprint and curated geography.

## Regression evidence

Run the exact pinned Godot `4.7.2.stable.official.ed1daf0bf`:

```sh
bash scripts/tooling/test_worldgen.sh artifacts/worldgen-new
bash scripts/tooling/test_keyword_grammar.sh artifacts/grammar-new
bash scripts/tooling/test_expedition.sh artifacts/expedition-new
```

The grammar runner checks a SHA-256 baseline of every catalog field except `roles`,
captured from **main `31ec237` before editing**. This guards all 39 original meanings
and ids. It also compares baseline blueprint fingerprints for every previous valid
grammar address at seeds 0, 1001 and 4294967295 (**26,358 comparisons**) in addition
to the original ordered-triple baseline (**10,080 comparisons**). The 12 historical
example identity/blueprint/layout hashes remain fixed; all four original expedition
layout fixtures and all 16 golden worldgen files remain unchanged.

Every word is exercised in its assigned slot across 32 seeds, comparing repeated
layouts, seed-independent identity and at least 12 geographic arrangements per
address. Tests check pairwise disjointness of both catalog lists and actual visible
menus, malformed and overlapping role metadata, all catalog words in all replay
slots, and old-role replay through the UI. Native mouse launch, keyboard popup
navigation, invalid/boundary seeds, wrong-slot rejection, restart and restoration of
normal selection are tested headless and rendered. Isolated mutations removing the
UI filter or assigning Frozen to both adjective pools must fail.

[Executed results and captures](evidence/keyword-distinct-slots/README.md) record
source hashes, examples, and the exact commands. The existing expedition runner adds
physics, traversal, camera and legal-input salvage/rematch regression checks.
Automated checks establish replay and selection invariants; vocabulary appeal and
desktop feel still need human evaluation. Command Center owns PR review and merging.
