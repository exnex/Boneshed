# Generated Object Classification and Kinship Synergies

**Status:** owner-confirmed design direction 2026-10-22, implementation proposed and balance unapproved.

## Player promise

Procedurally generated objects, armor and body modifications should have **classifier trees**. The closer and more meaningful their relationships, the more they may amplify compatible existing benefits or contribute to set/threshold bonuses. A traditional predefined set name should not be necessary: different and surprising generated items can genuinely belong together.

## Classification model

Prefer **multiple independently meaningful axes** (a multi-parent taxonomy / directed acyclic graph, not one exclusive item-type enum). Candidate axes:

- **Structure and morphology:** shaft, branching frame, ribbed canopy, plate, membranous skin, deployable folding linkage, etc.
- **Material and tissue:** metal, wood, bone, living root, chitin, fabric, composites with measured constituent proportions.
- **Function and combat affordance:** coverage, gripping, piercing, blunt impact, structural support, shielding, regeneration-related capabilities where explicitly provided.
- **Biological origin and lineage:** living plant, decayed plant, animal bone, crafted remnant; physical provenance must be validated.
- **World/provenance:** origin biome, faction, corruption source and artifact lineage where reliably generated.
- **Elemental/supernatural affinity:** only when the actual generated definition confers those effects, with explicit rules.

A generated umbrella can belong to multiple axes at once; its name is not proof of membership. Taxonomy should be derived from structured object/body data and authenticated provenance, with multiple parent nodes if useful. Separately store a versioned rule/taxonomy ID and the reason each classification was assigned.

## Synergy evaluation (proposed, not approved formulas)

1. Compute relatedness **per relevant axis**, e.g. common ancestors, graph-distance/path specificity, material composition fractions, or validated effect affinity. Avoid one global ambiguous percentage that treats material similarity as equivalent to lineage.
2. Eligible **amplification:** related items with complementary real capabilities strengthen an existing effect within capped bounds (e.g. living root armor + regenerative biological augmentation could improve that augmentation's recovery). Relatedness alone cannot create arbitrary powers without a defined effect rule.
3. Eligible **threshold/set bonuses:** a sufficient collection of strongly related distinct equipped items or body parts can activate a clearly defined ability or modifier. Not restricted to hand-authored named sets. A deliberate legendary set remains possible under the same system.
4. **Tradeoffs and diminishing returns:** synergy should not nullify every drawback; prevent trivial stacking and prevent spamming cheap near-identical objects for maximum bonus. Respect slots, actual functional contribution and opportunity costs.
5. **Explainability:** inspect screen should show matching axes, nearest meaningful common ancestors, participating equipped pieces, contribution, active amplification/bonus and relevant drawbacks.
6. **Player/AI/Echo parity:** identical classification and effects resolution for all actors, deterministic under frozen generated recipes, taxonomy version and equipped snapshot. Never derive ranked bonuses from client-provided free-form labels.
7. **Balance:** rare structure/material/affinity combinations should produce surprising, comprehensible builds without reducing procedural novelty to hunting one optimal tag family. Cross-family hybrid synergies may be valuable; avoid guaranteeing all related equipment combinations are powerful.

## Illustrative example, not approved items

A character with living root armor, a woody branch implement and a regenerative arm augmentation may receive meaningful botanical-relatedness contributions. That could **amplify** the arm's already-present HP regeneration, or cross a capped affinity threshold for a named defensive effect, but neither should be automatically awarded just because each contains the word 'root'. Bone augmentation plus bone tool can instead share material lineage. Two unrelated objects could share a protective-cover function with a smaller functional synergy.

## Prototype gate

Implement a small, deterministic **classification and synergy rules testbed** over existing object-first schemas in the Research Lab before game adoption:

- Derive overlapping ancestry on 12-20 generated fixtures, covering multi-material composites, a deployable canopy, organic armor, body augmentations and deliberately unrelated/partial-match items.
- Test exact lineage vs broad relation, cross-axis similarity, composition fractions, mixed positives and negatives, renamed/relabelled invariance, taxonomy version pinning and rejected contradictory lineage metadata.
- Implement two illustrative effects: capped gradual amplification of a preexisting trait and a threshold unlock requiring several distinct, meaningfully related functional pieces. Show anti-duplicate and anti-overstack behavior and explainable trace.
- Keep classification data independent from actual action/animation affordance legality; a relationship must not grant weapon thrust or a missing hand.
- No production numbers, permanent ontology, UI or item-list expansion until owner reviews the testbed.

See also [Adaptive Morphology Combat](ADAPTIVE_MORPHOLOGY_COMBAT.md). This is an architecture/design decision, **not** implemented in Boneshed.
