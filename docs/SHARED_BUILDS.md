# Shared Builds and Salvage — Design and Prototype

**Status: isolated Gate 2 foundation. Nothing here is a confirmed game mechanic.**
The confirmed direction ([DECISIONS.md](DECISIONS.md)) is only that player and enemy
forms share core build mechanics, that enemy forms may pair extreme stats with
disadvantages, and that defeated enemies may yield their signature augments/abilities.
Every stat, slot, value, restriction, rule and schema below is **Proposed**. Nothing
is wired into the courtyard, combat rules, AI, input, scene or browser export.

The success criterion is narrow: show that an enemy-owned signature ability becomes
part of a player build **through the same underlying definition**, with a visible
tradeoff, deterministically, without an inventory or persistence system.

| | |
| --- | --- |
| Catalog loader / validator | [`scripts/builds/build_catalog.gd`](../scripts/builds/build_catalog.gd) |
| Build validate / resolve / equip / serialize | [`scripts/builds/build_rules.gd`](../scripts/builds/build_rules.gd) |
| Salvage references | [`scripts/builds/salvage.gd`](../scripts/builds/salvage.gd) |
| Provisional curated data | [`data/builds/catalog.json`](../data/builds/catalog.json) |
| Salvage flow fixture | [`scripts/qa/salvage_flow_fixture.gd`](../scripts/qa/salvage_flow_fixture.gd) |
| Tests (137 checks) | [`scripts/qa/build_tests.gd`](../scripts/qa/build_tests.gd) |
| Demo / example output | [`scripts/qa/salvage_demo.gd`](../scripts/qa/salvage_demo.gd) → [`docs/salvage/examples/SUMMARY.md`](salvage/examples/SUMMARY.md) and `flow.json` |

```sh
bash scripts/tooling/setup.sh         # once: pinned Godot 4.7.2 (checksum-verified)
bash scripts/tooling/test_builds.sh   # tests + regenerates the example and diffs it
```

## 1. The contract

Three layers, each with one job:

1. **Catalog** (data, read-only once loaded). Definitions with stable dotted ids:
   - `stats` — id, range, and whether `higher` or `lower` is better.
   - `slots` — `main_hand` (weapons), `left_arm` / `right_arm` (augments).
   - `bindings` — `light`, `heavy`, `special`: which input an ability would occupy.
   - `profiles` — base stat blocks (a body/form), e.g. `profile.duelist`,
     `profile.corrupted_swordsman`.
   - `abilities` — what an attack *is*: binding, timing, hit values, required tags,
     a curated `module` id (future animation/attack module) and a `telegraph` note.
   - `items` — weapons and augments: slots they fit, tags they provide / require /
     exclude, abilities they grant, stat modifiers, `salvageable`.
2. **Build** (save data). Only ids:
   ```json
   {"schema": "boneshed.build.v0", "build_id": "...", "catalog_version": "0.1.0",
    "profile": "profile.duelist", "equipped": {"main_hand": "item.notched_sword"}, "carried": []}
   ```
   The player and every enemy use this identical shape. `carried` is the minimum
   needed to hold a salvaged item before equipping; it is **not** an inventory.
3. **Resolved build** (derived, never saved). Final stats with per-stat sources,
   abilities with their definition fingerprint and **effective** values for this
   wielder, tags, explicit tradeoffs, and a fingerprint of the whole result.

### Ownership and identity

- No definition names an owner; owner-like keys (`owner`, `controller`, `faction`,
  `player_only`, `enemy_only`) are rejected by validation anywhere in the catalog.
- Abilities are never stored on a build. They are derived from equipped items, so
  there is only one place an ability can come from.
- An ability's **identity** is its id plus a fingerprint (SHA-256 prefix of its
  canonical JSON). The wielder changes only `effective` values: the corrupted soul's
  `windup_scale` 1.5 makes its Marrow Lunge windup 1.05 s; the player's is 0.7 s.
  The definition and fingerprint are the same object in both builds.

### Validation (all deterministic, errors in catalog slot order)

| Rule | Error code |
| --- | --- |
| Exact keys, schema, id format, catalog version, known profile/slots/items | `unknown_key`, `missing_key`, `unsupported_schema`, `invalid_build_id`, `catalog_version_mismatch`, `unknown_profile`, `unknown_slot`, `unknown_item`, … |
| Item category matches slot, and the item lists that slot | `wrong_slot` |
| An item's `requires_tags` provided by the build | `missing_required_tag` |
| An item's `excludes_tags` not provided by another item | `excluded_tag` (e.g. Marrow Arm vs a two-handed grip) |
| Each ability granted once | `duplicate_ability` |
| One ability per binding | `binding_conflict` |
| An ability's `requires_tags` provided by the build | `missing_ability_requirement` |

Catalog validation additionally rejects unknown keys, bad ranges, unknown references,
neutral modifiers, ability requirements no item can satisfy, and — as a provisional
rule — **any augment without at least one explicit disadvantage**, so an augment can
never be a pure upgrade.

### Stats and tradeoffs

Stats resolve in a fixed order: profile base → sum of `add` modifiers → product of
`mul` modifiers → clamp to the stat range → round to 4 decimals. Tradeoffs are
**derived** from data (granted abilities and beneficial modifiers are advantages;
harmful modifiers and excluded tags are disadvantages), so they cannot drift from
what the item does.

`profile.duelist` and the sword's two attacks reproduce the current courtyard player
values. `profile.corrupted_swordsman` only approximates the courtyard enemy (see §6).

## 2. Architectures compared

| | A. Godot `Resource` subclasses (`.tres`) | B. JSON catalog + pure `RefCounted` rules (**chosen**) | C. Ability `Node` components on fighters |
| --- | --- | --- | --- |
| Idea | `AbilityDef`, `ItemDef`, `BuildDef` as typed `Resource` scripts edited in the inspector | Plain data file of definitions; builds are id-only dictionaries; stateless rule scripts validate and resolve | Each ability is a child node with its own logic attached to the player or enemy scene |
| Editor ergonomics | Best: inspector, typed exports, drag-and-drop | Text editing; no inspector (could add a tool later) | Good for designers, scene-centric |
| Shared identity | Shared by reference — accidental mutation of a loaded resource leaks to every user unless `duplicate()` is disciplined | Definitions frozen read-only; identity is id + content fingerprint | Ability lives *in* an owner's scene; identity bound to that owner |
| Save/load safety | Loading `.tres`/`.res` from untrusted save data can instantiate scripts/objects — unsafe for Tower snapshots or shared builds | Saves are id-only JSON; strict loader rejects unknown keys and object-shaped values | Saving scene state is heavy and engine-coupled |
| Server/Tower fit | Engine format; a server would need Godot or a converter | Language-neutral JSON; a server can validate the same schema | Poor |
| Testing | Needs resource loading; fine headless | Pure functions; trivially deterministic | Needs scene tree; harder to isolate |
| Risk | Mutation and unsafe-load footguns | Less editor-friendly; string ids can typo (mitigated by strict validation) | Recreates a second, per-owner ability system — exactly what salvage must avoid |

**Why B:** it makes the two hard requirements structural rather than disciplinary —
ownership cannot be encoded, and saves cannot carry code. It matches the existing
worldgen prototype's conventions (data JSON, `RefCounted` library, JSON-line tests,
regenerated examples). A could later be added as an **editor-only authoring view**
that exports to the same JSON; C is the wrong layer for definitions but is roughly
how the combat runtime may *execute* a resolved ability (§5).

## 3. Salvage flow (implemented)

1. Construct `player.fixture` (`profile.duelist` + Notched Sword).
2. Construct `soul.marrow_swordsman` (`profile.corrupted_swordsman` + Notched Sword +
   Marrow Arm). Same item definitions, same validator.
3. `Salvage.victory_fixture(...)` produces an `encounter_result` record. **This is a
   test fixture; no combat is simulated.**
4. `rewards(result)` returns one reference per salvageable equipped item. Defeat,
   self-defeat and invalid defeated builds yield nothing. The sword is not salvageable.
5. `acquire(build, ref)` re-verifies the reference against the catalog (schema,
   version, item exists and is salvageable, item and ability fingerprints, ref id) and
   adds the **item id** to `carried`. `equip()` validates the result.
6. `resolve()` recalculates the build.
7. `diff()` shows: `+ability.marrow_lunge` (reach 3.4 vs 2.35, 45 guard posture), and
   `deflect_window 0.16 → 0.11`, plus the exclusion of two-handed grips.

A salvage reference holds ids and fingerprints only — no stats, timing or modifiers —
so salvage cannot become a second ability system. See the
[generated summary](salvage/examples/SUMMARY.md).

**Security note:** `ref_id` and fingerprints detect tampering and stale definitions;
they are **not** an authorization mechanism (anyone can recompute them). Per
AGENTS.md, real rewards must be issued, recorded and claimed server-side. This
prototype cannot prevent claiming a valid reference twice.

## 4. Tests

`scripts/qa/build_tests.gd`, 137 checks, all deterministic (no randomness is used):

- **Catalog**: valid, small, deeply read-only, fingerprints stable across instances;
  16 malformed catalogs each rejected with the specific error.
- **Player/enemy compatibility**: same build and resolved schema; shared weapon gives
  the same ability fingerprint; enemy form shows exceptional posture with slow
  movement; an enemy augment fits a player profile.
- **Identity**: signature fingerprint equal in catalog, enemy, reference and player;
  the flow does not mutate the definition; wielder changes effective values only;
  no owner field.
- **Build validation**: 11 malformed builds each rejected; none resolve.
- **Invalid combinations**: wrong slot/category, two-handed grip vs Marrow Arm,
  unmet augment requirement; a rejected equip returns the build unchanged.
- **Duplicates/conflicts**: duplicate signature ability, binding conflict, error
  order independent of insertion order.
- **Equip/unequip**: carried requirement, unknown/occupied/empty slot, input never
  mutated, round trip restores the exact build, unequip removes granted abilities,
  unequip blocked while another item depends on it.
- **Stats/tradeoffs**: exact courtyard-matching player values, exact augment delta,
  add-then-mul order, clamping, traceable stat sources, slot-order independence.
- **Salvage**: deterministic refs, encounter-scoped ids, seven tamper cases rejected,
  stale reference rejected after a definition change, acquire → equip → ability.
- **Serialization**: JSON round trips, exact canonical text, malformed / non-object /
  extra-field / object-shaped input rejected, references survive JSON.
- **Reproducibility/isolation**: two catalog instances produce byte-identical flows
  matching the committed example; library scripts reference no combat, scene, AI or
  worldgen code; main scene unchanged.

Test-only definitions (a two-handed greatsword, a left-arm marrow copy, a hook arm, a
brace, a crush arm) live inside the test script, not in the shipped catalog.

## 5. Gate 2 integration plan (not started; each step its own PR)

Coordinate with the combat-readability/deflection work first; steps 2–4 touch combat.

1. **Approve or amend** the decisions in §7 and the catalog values.
2. **Adapter, read-only**: a small function `apply_resolved(resolved, CombatState)`
   that copies `max_health`, `max_posture`, `deflect_window`, `guard_chip`, posture
   recovery and per-binding attack timing/damage onto a `CombatState`. Prove with a
   test that the duelist profile reproduces current combat values exactly, so the
   adapter changes nothing until data does. `CombatState` currently hardcodes damage
   (18/32), the 12/s posture recovery, the 18 posture on hit and the 1.5× heavy guard
   multiplier; these must become per-attack/per-actor fields first — a combat-file change to
   schedule with the combat owner.
3. **Curated attack module** for `module.marrow_lunge`: a primitive procedural pose
   and a longer, narrower hit volume (reach 3.4, width 0.9) using the existing
   windup/active/recovery phases and amber/red previews. No generated attacks.
4. **Enemy uses it**: the swordsman's heavy slot in its attack cycle is replaced or
   joined by the lunge, configured from its resolved build. Requires playtesting for
   readability of the telegraph.
5. **Courtyard flow**: on victory, call `rewards()`, show a minimal "salvage Marrow
   Arm?" prompt, `acquire` + `equip`, rebuild the player's `CombatState`, bind
   `special` to an input, and start a second duel. Human playtest: does the reduced
   deflection window make the lunge a real choice?
6. Later, separately: server-issued rewards, persistence, Tower snapshots (resolved
   builds are already JSON and deterministic, which helps).

## 6. Known limitations

- Values are placeholders; nothing is balanced or playtested. No assertion is made
  that the lunge or the tradeoff feels good.
- The corrupted swordsman profile approximates the courtyard enemy with
  `windup_scale` 1.5 / `recovery_scale` 1.4 (courtyard: basic 0.62 s windup, 0.65 s
  recovery, heavy windup unchanged at 0.85 s). Scales cannot express "basic slower,
  heavy unchanged"; see decision 5.
- Items have no instance state (durability, damage, repair). Two copies of an item
  are the same id.
- `carried` has no limit, stash, extraction or loss rules.
- No skill that exists without a carrier item; see decision 1.
- Stats affect timing only through two global scales; damage is per ability only.

## 7. Decisions requiring human approval

1. **Abilities only come from items/augments** (no free-floating learned skills).
   Simplest single source of truth; salvaging a "skill" would need a carrier item.
2. **Bindings**: `light` / `heavy` / `special`, one ability each. A salvaged
   signature goes on a new `special` input rather than replacing light/heavy.
3. **Body slots**: only `main_hand`, `left_arm`, `right_arm` for now, and whether
   asymmetric parts (Marrow Arm is right-arm only) are desirable.
4. **Augments must carry an explicit disadvantage** (enforced by catalog validation).
5. **Wielder timing model**: global `windup_scale`/`recovery_scale` stats vs.
   per-ability overrides from the profile. Affects how enemy forms are expressed.
6. **Marrow Arm tradeoff**: deflection window −0.05 s and no two-handed grips. Is a
   defensive cost the right kind of tradeoff for an offensive augment?
7. **Ordinary gear not salvageable** in this prototype (`salvageable: false` on the
   sword). Confirmed vision allows gear salvage later.
8. **Duplicate grants are errors**, not silently merged.
9. **Effective values exclude damage scaling**: wielder stats change timing, not
   damage, for now.
10. **Data format**: JSON catalog with string ids vs. Godot Resources (§2).
