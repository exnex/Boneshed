# Three-Keyword World Blueprints — Design and Prototype

**Status: isolated prototype.** The high-level keyword identity-versus-seed-variation principle is confirmed in [DECISIONS.md](DECISIONS.md); individual algorithms, weights and content remain provisional.
The confirmed direction (see [DECISIONS.md](DECISIONS.md)) is only that three poetic,
.hack-inspired keywords and a fresh seed influence a world's resources, elemental
conditions, landforms, enemies and difficulty. Everything below — the vocabulary, the
axes, the weights, the rules and the formulas — is **Proposed** prototype work that
needs human review. No terrain, dungeon, enemy or loot is generated, and nothing here
touches combat, the courtyard scene or the browser export.

**Confirmed direction (2026-10-17):** The same three words should produce a recognizable world identity while allowing substantially different seeded maps, landmarks, encounters and discoveries. The present prototype deliberately varies only bounded parameters and featured themes; it does **not yet implement or demonstrate** that broader world realization. This gap is future work, not a failure of its deterministic blueprint contract.

The success criterion is narrow: show that three words plus a seed produce
**diverse, reproducible and meaningfully differentiated** blueprints that future
generators could consume.

| | |
| --- | --- |
| Generator | [`scripts/worldgen/blueprint_generator.gd`](../scripts/worldgen/blueprint_generator.gd) |
| Data loading / validation | [`scripts/worldgen/keyword_library.gd`](../scripts/worldgen/keyword_library.gd) |
| Hashing and random streams | [`scripts/worldgen/seed_stream.gd`](../scripts/worldgen/seed_stream.gd) |
| Prototype vocabulary (16 words) | [`data/worldgen/keywords.json`](../data/worldgen/keywords.json) |
| Rules, biomes, tuning | [`data/worldgen/rules.json`](../data/worldgen/rules.json) |
| Tests (80 checks) | [`scripts/qa/worldgen_tests.gd`](../scripts/qa/worldgen_tests.gd) |
| Demo | [`scripts/qa/worldgen_demo.gd`](../scripts/qa/worldgen_demo.gd) |
| Example output | [`docs/worldgen/examples/SUMMARY.md`](worldgen/examples/SUMMARY.md) and JSON beside it |

```sh
bash scripts/tooling/setup.sh          # once: pinned Godot 4.7.2 (checksum-verified)
bash scripts/tooling/test_worldgen.sh  # tests + regenerates examples and diffs them
```

## 1. What a keyword means

A keyword is data, not code. Each one has one or more **senses** (meanings). A sense
carries five kinds of influence, covering the candidate dimensions from the brief:

| Brief dimension | Representation in a sense |
| --- | --- |
| Environment / biome identity | Signed **axes** (below); biome is *derived* from axes, never assigned by a word |
| Terrain and architecture | Axes `elevation`, `enclosure`, `order` (wild↔built), `age` |
| Atmosphere / visual conditions | Axes `light`, `moisture`, `temperature`, `stillness`; plus short `atmosphere` descriptor phrases |
| Environmental hazards | Weighted `hazards` theme pool |
| Enemy / encounter themes | Weighted `encounters` theme pool (themes only — no enemies are defined) |
| Resource / discovery themes | Weighted `discoveries` theme pool (themes only — no items are defined) |
| Challenge characteristics | Derived from axes + hazard weight (visibility, ambush, density, traversal) |

The ten **axes** are signed, `-1..1`, each with named poles, e.g. `temperature`
frozen↔scorching, `sanctity` profane↔hallowed. Signed axes are what make
contradiction *detectable*: "frozen" and "smoldering" push the same axis in opposite
directions, which an unsigned tag bag cannot express.

Each sense also has **tags** (`cold`, `water`, `sacred`, `bone`, …) used for
interactions and for choosing between senses.

## 2. Architectures considered

| | A. Additive tag vector | B. Axes + senses + tag-pair rules (**chosen**) | C. Authored combination table / text grammar |
| --- | --- | --- | --- |
| Idea | Each word adds weights to tags; sum, normalize, read off parameters | Signed axes combined non-linearly; words have context-chosen senses; data rules fire on tag pairs from different words | Hand-write outcomes for known word pairs/triples, or template-fill descriptions |
| Interactions | None — pure stat bonuses (fails the brief) | Saturation, explicit tensions, emergent content from rules | Excellent where authored, absent elsewhere |
| Contradictions | Silently average to bland middle | Detected per axis; resolved as regional **patchwork** + conflict rules | Only where authored |
| Data cost per new word | ~1 entry | ~1 entry; rules are on *tags*, so they scale with tags, not word pairs | Grows with pairs (n²) or triples (n³) |
| Explainability | High | High: every output traces to a word, sense or rule id | High, but brittle |
| Risk | Same-feeling worlds | More moving parts to tune | Content explosion; a "giant database" |

**Why B:** it is the smallest model that satisfies "interactions matter, not merely
additive bonuses" while keeping data growth linear in vocabulary size. C remains
useful later as a thin layer of *authored exceptions* on top of B (e.g. a rare
hand-written world for one exact triple), which B's rule format already permits.
An LLM interpreter was excluded by scope (no paid AI services) and because it would
make output non-reproducible.

## 3. How a blueprint is built (implemented)

Pipeline, all in `blueprint_generator.gd`:

1. **Validate input** (§5). Any error returns no blueprint at all.
2. **Choose a sense for each word** from the company it keeps. A sense lists
   `resonates_with` tags; its score is the position-weighted count of those tags among
   the *other two* words' tags. Highest score wins; ties keep the first-listed
   (primary) sense. **The seed is never consulted**, so a word's meaning is stable for
   a combination. Examples: *hollow* beside *drowned* reads as **cavern**; beside
   *forgotten* and *profane* it reads as **emptied** (a place everyone left).
3. **Match interaction rules.** A rule such as `black_ice` requires tags `water` and
   `cold` supplied by **different** words — one word can never trigger a rule alone.
   Strength = mean position weight of the matched words. Rules are either `synergy`
   or `conflict` and add axis pushes, theme entries and atmosphere phrases that no
   single word has.
4. **Resolve axes non-additively.** Positive and negative pushes are combined
   separately as `1 − Π(1 − push)`: agreement amplifies but saturates before the pole;
   opposition is visible rather than cancelled. If both sides of an axis exceed the
   contest threshold (0.3), the axis becomes a **tension**: recorded with its poles,
   the dominant pole (or `balanced`) and a high `regional_variance`, resolved as
   `patchwork` — regions should alternate between the poles instead of averaging into
   lukewarm mush.
5. **Theme tables.** Hazard / encounter / discovery weights summed over words and
   rules, normalized, sorted. These are seed-independent.
6. **Biome ranking.** Nearest prototypes (by RMS distance on each biome's listed axes)
   give `primary` and `secondary` biome; secondary is the blending/patchwork partner.
7. **Seeded variation** (only here does the seed matter): axis jitter of at most
   ±0.08, the supporting cast of featured themes (the top theme is always featured,
   the rest are weighted picks), and atmosphere phrases (one from each triggered rule
   first, then weighted picks from the words).
8. **Generation parameters**: normalized 0..1 hints for terrain, structure,
   atmosphere and challenge, derived from the *jittered* axes. Formulas are
   monotonic placeholders, chosen to be explainable, not tuned.
9. **Stream seeds** for future generators and a fingerprint of the canonical JSON.

### Identity vs variation

The blueprint is split so "recognizable identity" is testable:

- `identity` — senses, axes, biome, tensions, interactions, theme tables. A function of
  the words and their order **only**. `identity_fingerprint` is identical for every
  seed (tested across 32 seeds × 6 combinations).
- `variation` — jittered axes, featured themes, atmosphere. Seeded and bounded.
- `generation`, `streams` — consumer-facing outputs.

### Keyword position

Position matters, modestly: weights are `[0.8, 0.9, 1.0]`, so the **last word is the
anchor**, as in English adjective–adjective–noun order and .hack-style addresses
("Hidden Forbidden Holy Ground"). Reordering keeps the same words, senses (usually)
and interactions but shifts emphasis — in *Profane Gilded Hallowed* the sanctity
conflict leans hallowed; in *Hallowed Gilded Profane* it leans profane. This is a
proposal; see §8.

## 4. Randomness and determinism (implemented)

- No `randi()`, `RandomNumberGenerator`, time or engine hash is used. Hashing is
  FNV-1a over UTF-8; the PRNG is Mulberry32, written with masked 32-bit arithmetic so
  output cannot change with a Godot upgrade or platform. Both are pinned to reference
  vectors computed by an independent Python implementation (and the published
  `mulberry32(0)` value).
- **Every consumer has its own named stream**, seeded from
  `namespace | words | seed | purpose`. Axis jitter, each theme pool, and atmosphere
  each draw from separate streams; a test asks for twice as many hazard picks and
  verifies jitter, encounters and atmosphere are byte-identical and the hazard list
  is extended, not reshuffled.
- The blueprint hands out `streams.{terrain, structure, encounters, hazards,
  discoveries, atmosphere}`: hex seeds for future generators. A terrain generator that
  changes how many numbers it draws therefore cannot alter encounter placement.
  Adding a domain does not change existing domain seeds.
- The words are part of every stream seed, so the same seed with different words
  yields unrelated layouts — the seed is not a "layout id" shared across addresses.
- Serialization: sorted-key JSON, floats rounded to 3 decimals with negative zero
  removed, and **no integers** (seeds and positions are strings) so a JSON
  parse → stringify round trip is byte-identical. The committed examples are golden
  fixtures and are regenerated and byte-compared by `test_worldgen.sh`.

## 5. Input handling (implemented)

| Input | Result |
| --- | --- |
| Not exactly three words | error `wrong_keyword_count` |
| Non-text entry | error `invalid_keyword_type` (with position) |
| Blank entry | error `empty_keyword` |
| Word not in vocabulary | error `unknown_keyword` (every one is reported) |
| Same word twice, including after normalization | error `duplicate_keyword` |
| Mixed case / surrounding spaces | accepted, warning `normalized_keyword`; identical blueprint to the clean form |
| Contradictory words | **not an error** — resolved as tensions + conflict rules |
| Broken data files | error `invalid_library`; the library validator reports axis ranges, unknown tags, weights, duplicate ids |

Errors never produce a partial blueprint.

## 6. The WorldBlueprint contract (schema 0.1.0)

```text
schema_version, data_version, provisional: true, address, fingerprint, identity_fingerprint
input      { keywords[3], world_seed (string) }
identity   { senses[3]{keyword, position, sense, gloss, resolution, scores},
             axes{10 axes: -1..1},
             biome{primary, secondary, ranking[3]{id, label, affinity}},
             tensions[]{axis, poles, dominant, strength, resolution: "patchwork"},
             interactions[]{id, kind, summary, strength, sources},
             theme_tables{hazards|encounters|discoveries: [{id, weight}] sum≈1} }
variation  { axes{axis: {value, regional_variance}}, featured{pool: [ids]}, atmosphere[3] }
generation { terrain{elevation_bias, relief, water_coverage, ice_coverage, vegetation,
                     architecture_density, ruin_level, subterranean_ratio, patchwork[]},
             structure{passage_tightness, verticality, interior_ratio},
             atmosphere{light_level, fog_density, precipitation, wind, color_temperature,
                        silence, corruption_tint},
             challenge{visibility, ambush_tendency, encounter_density, hazard_pressure,
                       traversal_difficulty} }      all 0..1
streams    { terrain, structure, encounters, hazards, discoveries, atmosphere: hex seed }
```

Theme ids (`black_ice`, `bone_wardens`, `grave_goods`, …) are **labels for future
lookup tables**, not definitions of enemies or items. `encounter_density` is held to a
provisional sparse band (0.15–0.55) to respect the desolate tone.

## 7. How a blueprint could drive real generation (proposed, not implemented)

Each future generator should read only the blueprint plus its own stream seed:

- **Terrain**: `elevation_bias`/`relief` → heightfield amplitude and octaves;
  `water_coverage`/`ice_coverage` → water table and freeze; `patchwork` axes with
  high `regional_variance` → region map where cells alternate between that axis's
  poles (e.g. frozen and scorched districts with steam where they meet), with
  `biome.primary`/`secondary` as the two region palettes.
- **Structure / dungeon**: `subterranean_ratio`, `interior_ratio`,
  `passage_tightness`, `verticality` → choice and sizing of curated room/corridor
  modules (consistent with AGENTS.md's curated-module-first stance). Tight, dark
  spaces matter for the camera and lock-on, so these values should be validated
  against combat readability before anything ships.
- **Encounters**: `encounter_density` → how many fights per area; `ambush_tendency` →
  placement relative to sightlines; featured encounter themes → lookup into a future
  curated enemy table. Density is a *budget*, not a spawn rate: Boneshed wants few,
  meaningful fights.
- **Hazards / discoveries**: theme tables become weighted selection over future
  curated hazard and reward definitions; `hazard_pressure` → how many are active.
- **Atmosphere**: `light_level`, `fog_density`, `color_temperature`, `precipitation`,
  `wind`, `silence` → environment, fog, particles, ambient audio; descriptor phrases
  → art/audio direction and the expedition's name card.
- **Difficulty / star ratings**: deliberately not modelled. The proposed 0–5 keyword
  star ratings are unapproved and should layer *on top* of the blueprint rather than be
  baked into it.

## 8. Decisions requiring human approval

1. **Architecture B** itself (axes + senses + tag-pair rules) as the direction.
2. **Word order**: should the last word be the anchor (`[0.8, 0.9, 1.0]`), should all
   positions be equal, or should positions have *roles* (e.g. condition / place /
   twist)? Roles would be a stronger, more "grammatical" design but constrain which
   words players can put where.
3. **Multiple meanings**: senses are chosen by context, ties keep the primary sense,
   and the seed never changes a meaning. Alternative: let the seed choose between
   close senses for more variety at the cost of identity.
4. **Duplicates**: currently rejected. Alternative: allow "Frozen Frozen Frozen" as an
   intensified world — attractive for .hack flavour, but needs its own rules.
5. **Contradictions as patchwork**: opposed words produce alternating regions rather
   than an average or a rejection. Is that the desired feel?
6. **Seed scope**: seed only adds bounded texture (±0.08 axes, supporting themes,
   phrases). Should seeds be allowed to swing identity more (e.g. pick the secondary
   biome as primary), matching "a fresh seed prevents identical layouts"?
7. **Vocabulary**: all 16 words, glosses, theme ids and weights are placeholders. The
   real vocabulary, its tone, whether players see words as free text or pick from a
   list, and how words are unlocked are open.
8. **Encounter density band** 0.15–0.55, and every formula in `_generation_parameters`.
9. **Data format**: JSON in `data/worldgen/` (diffable, editor-independent) vs Godot
   `Resource` files (inspector editing, typed). Whether `data/worldgen/` and
   `scripts/worldgen/` end up in the web export bundle was not checked; nothing in the
   game loads them, and the export configuration was intentionally left untouched.

## 9. Known limitations

- The biome table is coarse: prototypes list 2–4 axes each, and `silent_ruin` acts as a
  catch-all for quiet, dead combinations (4 of 14 examples). A real biome set needs
  design input, not more tuning here.
- Rules fire on tag *presence*; strength does not yet depend on how strongly each word
  expresses the tag.
- Senses with no resonance always fall back to the primary sense, so the second sense
  of *gilded* or *forgotten* only appears with specific company.
- Generation parameters are placeholder formulas; they are bounded and monotonic, not
  meaningful to play yet. Nothing has been seen in-engine as terrain.
- Theme ids have no definitions behind them; two words may name overlapping themes
  (e.g. `carrion_flocks` in *tempest* and *barren*), which is intended to merge, but
  synonyms with different ids would not merge.
- Determinism is proven within this engine build and against Python reference vectors;
  float formatting of the JSON relies on Godot's `JSON.stringify`, which is pinned by
  the golden examples but could change with an engine upgrade (the hashes and PRNG
  would not).
- Tests check structure, bounds and intended interactions. They cannot show that any
  combination is *evocative* or fun; that needs human reading of the examples.
