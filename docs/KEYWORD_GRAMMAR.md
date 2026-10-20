# Keyword address grammar

The owner confirmed **adjective + adjective + noun** addresses after playing First
Expedition. The desktop selector now offers 24 adjectives in each of the first two
slots and 16 place/concept nouns in the third. Adjectives must differ; a word cannot
appear twice. **Hollow** is both an adjective and a place noun. **Tempest** is a noun.

| Role | Available words |
| --- | --- |
| Adjectives | Ashen, Barren, Buried, Drowned, Forgotten, Forsaken, Frozen, Gilded, Hallowed, Hollow, Lightless, Moonlit, Pallid, Profane, Shattered, Silent, Smoldering, Sunken, Thorned, Towering, Veiled, Weeping, Windswept, Withered |
| Place/concept nouns | Cathedral, Chasm, Citadel, Dream, Garden, Hollow, Labyrinth, Marsh, Necropolis, Ossuary, Requiem, Sanctuary, Sepulcher, Shore, Spire, Tempest |

Examples include **Ashen Silent Sanctuary**, **Moonlit Thorned Garden**, **Weeping
Forgotten Requiem**, **Frozen Gilded Citadel**, **Smoldering Pallid Necropolis**, and
**Veiled Sunken Dream**. They cover ruined, wild, memorial, cold, fire/death and
uncertain/dreamlike themes. New words have individually authored semantic data using
the existing axes/tags/theme pools. Their effects and visual interpretation remain
provisional, and a concept noun does not promise a bespoke level type. Existing
curated causeways and abstract scenery are reused.

## Selection and replay

Use mouse-operated native dropdowns, or Tab to focus and Enter/arrows to select.
Lists scroll. Choose **Begin expedition** for a fresh entropy seed. For a recorded
address, enable **Replay an existing seed**, choose the words in their original
order and enter its seed (0–4294967295).

If an old address does not fit the new grammar, also enable **Replay an older
keyword order (original 16 words)**. All three slots then offer the original words,
with labels that explicitly identify older addresses. For example, **Tempest Frozen
Towering / 1001** and **Hallowed Gilded Profane / 1001** remain playable exactly as
recorded. Turning seed replay off restores grammatical selection. Existing restart
and return behavior, including salvage reset, is unchanged.

## Compatibility audit

| Surface | Result / policy |
| --- | --- |
| Original 16 keyword ids and effects | Preserved; no aliases, substitutions or sense changes |
| All 3,360 original valid ordered triples | Preserved in the generator and older-order replay UI; duplicates still rejected |
| Existing WorldBlueprint consumers | Schema `0.1.0`, semantic `data_version: prototype-0.1`, position weights, namespace, streams and formulas unchanged |
| Old golden blueprints | All 14 JSON examples plus index and summary regenerate byte for byte |
| First Expedition seed fixtures | All four pinned layout fingerprints unchanged, including Drowned Hollow Cathedral / 1001 (`1c1b4200`) |
| New selection | Filters by `roles`; it does not reorder, replace, or reinterpret words |
| Persisted saves | The slice has no disk-save system; a recorded address + seed needs no data migration |

The vocabulary extension is additive. `roles` and `legacy` are validated catalog
metadata; neither enters blueprints, identity hashes or stream seeds. The existing
semantic data version is deliberately retained to avoid changing every old
fingerprint just because selection metadata and additional words were added.
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

The grammar runner compares baseline fingerprints captured from `main 8025663`
**before editing** for every original ordered triple at seeds 0, 1001 and 4294967295
(10,080 comparisons). It exercises every vocabulary word across 32 seeds, comparing
entire repeated layouts, seed-independent identity and at least 12 geographic
arrangements per address. Six example addresses also test role metadata independence
and generate an evidence table with identity/blueprint/layout hashes for two seeds.
Native mouse launch, keyboard popup navigation, invalid/boundary seeds, duplicate
feedback, exact older-order replay, restart and restoring normal grammar are tested
headless and rendered. Removing the UI role filter must fail an isolated mutation.
The existing expedition runner adds 18 built new-vocabulary fixtures for route
capsule sweeps, floor rays, arena clearance, boundary/gate collision, alongside its
original fixtures and legal-input salvage/rematch trace comparison.

[Executed results and captures](evidence/keyword-grammar/README.md) record the checked
source hashes. Automated checks and software-rendered captures establish these
invariants; whether the vocabulary is evocative and the game feels good still needs
human reading and desktop playtesting. Command Center owns PR review and merging.
