# Extensible Anatomy and Transformation — Design and Prototype

**Current playable milestone:** [First playable guide](FIRST_PLAYABLE.md). Catalog
0.3.0 integrates Marrow Lunge and victory → salvage → equip → next duel into the normal
entry scene. Marrow Arm preserves the 0.16 s deflection window; its former −0.05 s
fixture penalty is removed. The sections below record this foundation's original
scope/proposals. The anatomy graph remains isolated; only its build-version pin and
regenerated examples change.


**Status: isolated foundation. Nothing here is a confirmed game mechanic.**
The confirmed direction ([DECISIONS.md](DECISIONS.md), 2026-10-17) is only that extreme
bodily transformations are allowed **provided** attacks and hitboxes stay readable,
controls stay reliable, combat stays fair and equipment/animation stay compatible.
Every part, socket, capability, class, limit, proportion range and requirement below is
**Proposed**. Nothing is wired into the courtyard, combat rules, AI, input, scenes, the
shared-build implementation or its catalog. The shared build catalog (currently
`0.2.0`, which since PR #13 also drives live courtyard combat through
`scripts/combat/build_adapter.gd`) is read, never edited; live combat never reads anatomy.

| | |
| --- | --- |
| Catalog loader / validator | [`scripts/anatomy/anatomy_catalog.gd`](../scripts/anatomy/anatomy_catalog.gd) |
| Body validate / resolve / requirements / transform / serialize | [`scripts/anatomy/anatomy_rules.gd`](../scripts/anatomy/anatomy_rules.gd) |
| Proposed adapter to shared builds and combat (read-only) | [`scripts/anatomy/build_projection.gd`](../scripts/anatomy/build_projection.gd) |
| Provisional parts, equipment, requirements | [`data/anatomy/catalog.json`](../data/anatomy/catalog.json) |
| Four example bodies | [`data/anatomy/example_bodies.json`](../data/anatomy/example_bodies.json) |
| Transformations and rejected cases | [`scripts/qa/anatomy_fixture.gd`](../scripts/qa/anatomy_fixture.gd) |
| Tests (190 checks) | [`scripts/qa/anatomy_tests.gd`](../scripts/qa/anatomy_tests.gd) |
| Generated example | [`docs/anatomy/examples/SUMMARY.md`](anatomy/examples/SUMMARY.md) and `flow.json` |

```sh
bash scripts/tooling/setup.sh          # once: pinned Godot 4.7.2 (checksum-verified)
bash scripts/tooling/test_anatomy.sh   # tests + regenerates the example and diffs it
```

## 1. Architectures compared

The question is not "how do we model a human" but "what must stay fixed so that a
four-armed or lopsided fighter is still a fair Sekiro-style opponent".

| | A. Fixed skeletal attachment slots | B. Hierarchical modular body graph | C. Hybrid: stable gameplay anchors + constrained graph (**recommended**) |
| --- | --- | --- | --- |
| Idea | One shared humanoid `Skeleton3D`; augments replace or attach to named bones (`right_arm`, `back`) via `BoneAttachment3D` | Body is a tree of parts joined at typed sockets; any part may carry sockets, so structure is open-ended | A `core` part owns every gameplay anchor (movement root, camera focus, facing, core hurtbox). Limbs form a socket tree beneath it, but only through typed, curated sockets with tags, exclusions and engineering limits |
| Godot fit | Excellent: one skeleton, `SkeletonProfileHumanoid` retargeting, one `AnimationTree` | Possible but costly: per-part scenes on `Marker3D` sockets, no single skeleton to retarget onto, many small `AnimationPlayer`s to coordinate | Good: core scene with stable markers; each part is a small curated scene attached at a socket marker; a per-part **curated animation module** layers onto a shared core timeline |
| Animation complexity | Lowest for humanoids; extra limbs have no bones to animate | Highest: arbitrary topologies need generated or IK-driven motion | Bounded: one module per part type, authored by hand; the core timeline (windup/active/recovery) is shared |
| Procedural transformation | Swap within fixed slots only; cannot add a limb | Unlimited | Add/remove/replace parts at declared sockets; new body plans come from new core parts, not arbitrary growth |
| Equipment | Simple (hand bones) | Ambiguous: what is a "hand" on an arbitrary graph? | Equipment mounts on named **mount points** with types (`grip`, `light_grip`); two-handed items need a declared socket **pair** |
| Combat readability | Excellent (everything looks human) | Weak: silhouette and telegraph origin are unpredictable | Kept by rules: one facing, front-only guards, every striking part declares a visible attack origin, extreme parts raise **review flags** |
| Hit detection | Fixed capsules per bone | Must derive volumes from geometry | Each part names a hurt/reach **class**; volume sizes stay in one tunable table, not per-body geometry |
| Performance | Best | Graph walks plus many nodes per fighter | A fighter is ~5–8 parts; resolution is O(nodes + mounts) and runs only when the body changes, never per frame |
| Development cost | Lowest now, but blocks the confirmed direction (no extra limbs) | Highest; effectively a creature engine | Moderate: small data model now; content cost scales with curated parts/modules, which is the same constraint AGENTS.md already sets for salvaged attacks |

**Recommendation: C.** It is the smallest model that can represent two, four or six arms,
a replacement arm, lopsided proportions and different locomotion **without** changing the
schema, while keeping the combat reference frame (movement, camera, facing, core hurtbox)
fixed to the core. B's open structure is kept as the data shape (a tree with typed
sockets) but constrained: no part may become a root, socket types and pair groups are
curated, depth and node count have engineering guard rails, and no animation is derived
from geometry. A remains available as the *internal* implementation of a core part: a
humanoid core may well be a single `Skeleton3D` whose sockets are bone attachments.

Not recommended now: an unrestricted procedural creature engine (IK-generated gaits,
geometry-derived hitboxes). Nothing in the confirmed direction requires it, and it would
make telegraphs and hitboxes unpredictable, which the direction explicitly protects.

## 2. Data model (implemented)

### Catalog (`boneshed.anatomy_catalog.v0`, read-only once loaded)

- `required_anchors` — `movement_root`, `camera_focus`, `facing`, `core_hurtbox`. Every
  `core` part must carry exactly these; no other part may carry any.
- `socket_types` (`shoulder`, `great_shoulder`, `neck`, `hips`, `tail`) and `mount_types`
  (`grip`, `light_grip`).
- `capabilities` — the vocabulary abilities depend on (`grasp`, `grasp.light`,
  `guard.parry`, `limb.marrow`, `strike.crush`, `locomotion.biped`, `wield.blade`, …).
- `classes` — ordered hurt (`small` … `large`) and reach (`none` … `long`) classes.
  **Names only**; sizes are deliberately not decided.
- `animation_modules` — curated module ids with a kind (core, limb, locomotion, …).
- `parts` — each has `kind`, `attaches_to` (socket types), offered `sockets` (id, type,
  side, pair group), `mounts`, `provides` (capabilities), `tags` / `requires_tags` /
  `excludes_tags`, `proportions` (id, min, default, max, **domain** gameplay|visual), one
  `animation_module`, an optional `build_item` link, and **separate** `gameplay`
  (`hurt_class`, `reach_class`, `attack_origin`, `guard`) and `visual` objects.
- `equipment` — mount types accepted, `mount_count`, `paired`, capabilities provided /
  required, part tags excluded, optional `build_item` link, `fixture` flag.
- `requirements` — keyed by shared-build ability ids (and clearly marked `probe.*`
  fixtures): `all` = capabilities with a minimum provider count, `none` = capabilities
  that must be absent. **No requirement names a slot.**

Catalog validation also enforces readability rules: guards are `front` or `none` (one
facing per body; no rear or omni guard in v0); any part that can strike or hold
equipment declares an `attack_origin`; visual metadata may not contain gameplay keys;
paired equipment needs exactly two mounts; every requirement is satisfiable by some part
or equipment; owner-like keys are rejected as in the build catalog.

### Body (`boneshed.anatomy.v0`, save data, ids only)

```json
{"schema": "boneshed.anatomy.v0", "body_id": "body.marrow_replacement", "catalog_version": "0.1.0",
 "nodes": [
   {"id": "torso", "part": "part.humanoid_torso", "parent": "", "socket": "", "proportions": {}},
   {"id": "arm_r", "part": "part.marrow_arm", "parent": "torso", "socket": "shoulder_r", "proportions": {}},
   …],
 "equipment": [{"item": "equip.notched_sword", "mounts": ["arm_l/grip"]}]}
```

Node ids are stable anatomical identifiers chosen by the body (`arm_lower_l`,
`arm_great`); they survive part replacement, so a transformation can say "replace
`arm_r`" and equipment, abilities and future animation state can keep referring to it.
Mount references are `node/mount`.

### Validation (deterministic; errors in sorted node order)

| Rule | Error code |
| --- | --- |
| Exact keys, schema, ids, catalog version, known parts, numeric proportions | `unknown_key`, `missing_key`, `unsupported_schema`, `invalid_body_id`, `catalog_version_mismatch`, `invalid_nodes`, `invalid_node`, `invalid_node_id`, `unknown_part`, `invalid_proportions`, `invalid_equipment` |
| Unique identifiers | `duplicate_node_id` |
| Exactly one root, it is a core, cores only at the root | `no_root`, `multiple_roots`, `root_not_core`, `root_has_socket`, `core_not_root` |
| Parent exists, no cycles, every node reachable | `unknown_parent`, `cycle`, `disconnected` |
| Socket exists on the parent, accepts the part's type, one part per socket | `unknown_socket`, `incompatible_socket`, `socket_occupied` |
| Body-wide tag requirements and exclusions | `missing_required_tag`, `excluded_tag` |
| Proportions known for the part and within its range | `unknown_proportion`, `proportion_out_of_range` |
| Exactly one locomotion provider | `locomotion_count` |
| Engineering guard rails (not body limits) | `too_many_nodes`, `too_deep` |
| Equipment: known, right mount count and types, mounts free, pairs mirrored, part tags allowed, capabilities present | `unknown_equipment`, `mount_count`, `unknown_mount`, `wrong_mount_type`, `mount_in_use`, `unpaired_mounts`, `equipment_excluded`, `equipment_missing_capability` |

### Resolved body (derived, never saved)

`anchors` (all on the core node), and a `gameplay` section — tags, capabilities with their
providing nodes, the locomotion provider and module, per-node hurt/reach class, attack
origin, guard and gameplay-domain proportions (defaults filled in), mount occupancy,
equipment, animation modules, silhouette counts, asymmetry and **review flags** — plus a
separate `visual` section. Two fingerprints: `gameplay_fingerprint` (anchors + gameplay)
and `fingerprint` (everything). Tests prove a visual-only edit — a material hint in the
catalog, or a body's `bulk` proportion — changes `fingerprint` but not
`gameplay_fingerprint`, while a gameplay proportion (`length`) changes both. That gives a
Tower snapshot or server a clean thing to validate.

Review flags are information, not penalties: `asymmetric_silhouette`,
`non_baseline_count` (e.g. 4 arms vs. a baseline of 2), `non_baseline_locomotion`,
`review_reach`, `review_hurtbox`. They mark forms that need curated readability work
before they can appear in combat.

### Requirements (capabilities, not slots)

`check_requirement(resolved, id)` returns met/missing/excluded, the nodes that satisfy
each term, and the **attack origin**: the first provider's node, its declared origin point
and its animation module. `attack.slash` needs one `wield.blade` provider — so it
originates at whichever arm holds the sword (`arm_r/grip` for the humanoid, `arm_l/grip`
once the right arm is a Marrow Arm). `ability.marrow_lunge` needs `limb.marrow` and
originates at `arm_r/bone_tip`. Equipment capabilities are credited to the node of their
first mount.

### Transformations

`transform(body, ops)` applies `attach`, `detach` (removes the subtree), `replace` (keeps
the node id and children whose sockets still fit; resets proportions to the new part's
defaults), `set_proportion`, `mount` and `unmount` **atomically**: if any op or the final
validation fails, the original body is returned unchanged with the errors. After each
structural op, equipment whose mounts disappeared or stopped fitting is **displaced** —
removed and recorded with reasons — never left invalid and never destroyed. The report
also gives the net equipment and parts released/added so the build layer knows what moves
to and from `carried`.

## 3. Examples (fixtures, not character classes)

Generated in [`docs/anatomy/examples/SUMMARY.md`](anatomy/examples/SUMMARY.md):

1. **`body.humanoid_fighter`** — humanoid torso, head, two arms, biped legs, sword in
   `arm_r/grip`. No review flags. Projects losslessly to today's `player.fixture` build.
2. **`body.marrow_replacement`** — `arm_r` replaced by the handless Marrow Arm
   (`limb.marrow`, `strike.thrust`, long reach). The sword moves to `arm_l`. Unlocks
   `ability.marrow_lunge`; blocks `probe.two_handed_grip` (no second grip and an explicit
   `none: limb.marrow`). Projects losslessly to today's `soul.marrow_swordsman` build.
3. **`body.four_armed`** — spined torso adds a lower shoulder pair. Upper arms: full
   `grip`, `grasp`. Lower auxiliary arms: `light_grip`, `grasp.light`, short reach, need the
   `frame.augmented_spine` tag. Sword upper-right, fixture buckler lower-left. Four parry
   providers satisfy `probe.multi_parry`; the greatsword cannot span an upper and a lower
   arm (`wrong_mount_type`, `unpaired_mounts`).
4. **`body.carapace_brute`** — lopsided core with an oversized right `great_shoulder`
   carapace arm (crush, heavy guard, large hurt class), one human left arm with the sword,
   a counterweight tail, digitigrade legs, raised height. Flags: asymmetric, long reach,
   large hurtboxes, non-baseline locomotion, extra tail.

Transformations demonstrated: humanoid → corrupted arm (sword displaced, then remounted
left); corrupted arm → humanoid (Marrow Arm released to `carried`); humanoid →
two-handed grip → corrupted (greatsword displaced because its pair is broken); humanoid
→ four-armed (core replaced, all children kept); four-armed → brute (three arms removed
with their equipment displaced, sword remounted). The four transformations that target an
example reproduce its nodes and equipment exactly. Eight invalid transformations are
rejected with the body unchanged.

## 4. Proposed combat contract

`BuildProjection.combat_view(resolved, ability_ids)` is the single object combat would
read. It is a proposal; no combat code reads it.

| Concern | Contract |
| --- | --- |
| Movement and camera | `anchors.movement_root` and `anchors.camera_focus` are always the core node. Limbs, tails and proportions never move them. A lopsided head is visual only. Locomotion comes from exactly one part, as a curated module with the **same root-motion contract** (speed tuning stays in shared builds). |
| Attack origins / weapon points | Each ability's origin is resolved from capabilities: provider node + declared origin point (`grip`, `bone_tip`, `knuckle_plate`) + that part's animation module. Weapons attach at mount points, never at inferred bones. |
| Defensive facing and guard | One `facing` anchor on the core. Parts may only guard `front` or `none` — the existing `guard_arc_cos` front-hemisphere rule stays valid for every body. Extra arms add parry *capability*, not extra guard directions. |
| Silhouette and telegraphs | Every striking/holding part must declare an attack origin. Each curated module owns its own telegraph (as `ability.telegraph` does today). `asymmetric_silhouette`, `non_baseline_count` and `review_reach` flag forms whose telegraphs need a readability pass before use. |
| Collision volumes and reach | Per-part hurt and reach **classes**. One table (not yet written; owned by combat) would map classes to capsule sizes; the shared-build ability still owns exact `reach`/`width`. Gameplay proportions (e.g. arm `length`) are reported for combat to apply within narrow ranges; visual proportions never affect hit volumes. |
| Animation | Curated modules per part type layered over the shared windup/active/recovery timeline. No retargeting onto non-humanoid geometry, no generated animation. `SkeletonProfileHumanoid` retargeting stays an option *inside* humanoid core/arm modules only. |
| Transformation transitions | Combat should apply a transformation only between encounters (or behind a dedicated, uninterruptible transition), rebuild hurtboxes/abilities from the new resolved body, and diff modules via `diff()` to load/unload animation layers. |
| Equipment conflicts | Resolved before combat: displaced items move to `carried` (`build_item_changes`). Combat never sees an item on a mount that does not exist. |
| Extreme forms | Review flags gate them: e.g. require human approval of a curated module, cap reach/hurt class combinations, or restrict to enemy-only content until playtested. Which restrictions apply is **not decided**. |

### Relationship to shared builds

The anatomy core has **no dependency** on `scripts/builds`; only `build_projection.gd`
reads the build catalog (duck-typed, never preloaded, never written). Today's slots are a
lossy projection of a body: `legacy_slots()` maps equipment with a `build_item` to its
build slot and side-mounted parts with a `build_item` (the Marrow Arm) to
`left_arm`/`right_arm`. Tests prove the humanoid and Marrow bodies project to exactly the
current `player.fixture` and `soul.marrow_swordsman` loadouts, that the humanoid body
projects to the loadout of **both** live courtyard actors in `data/builds/courtyard.json`
(read as data only), and that every projection validates with the **unchanged**
`build_rules.gd`. `build_catalog_version` in the anatomy catalog pins the build catalog it
was checked against; a mismatch makes every projection non-lossless and fails the tests,
so build-catalog revisions cannot silently drift from anatomy. Four-armed and brute bodies report
their anatomy-only nodes as lossy. Every shared-build ability (`attack.slash`,
`attack.heavy_slash`, `ability.marrow_lunge`) already has a capability requirement.

Proposed later integration (each its own PR, coordinated with Codex's live-combat work):

1. Approve or amend §7 decisions.
2. Add an optional `anatomy` body (or body id) beside a build; stats and abilities still
   resolve through shared builds (`build_rules.resolve`) and still reach combat only
   through the existing `build_adapter.gd`, never a second resolver. Abilities are
   additionally gated by `check_requirement`. The legacy slots become derived.
3. Map hurt/reach classes to volumes in combat-owned data; apply `combat_view` attack
   origins to the existing hit volume code.
4. Curated module for one non-baseline part (see the next step).

## 5. Tests and executed results

`scripts/qa/anatomy_tests.gd`, 190 checks, deterministic (no randomness):

- **Catalog**: valid, small, deeply frozen, stable fingerprints; a visual-only catalog
  edit keeps gameplay fingerprints; cores carry all anchors; 18 malformed catalogs each
  rejected (rear guard, striker without origin, gameplay key in visual metadata,
  unsatisfiable requirement, owner key, fractional count, …).
- **Examples**: four valid bodies, anchors on the core, single locomotion provider.
- **Shape**: 12 malformed bodies rejected with the specific code.
- **Graph**: two-node and self cycles (reported once with members), disconnected root
  limb, missing parent, rootless body, duplicate ids, socket on root, second core,
  unknown/incompatible/occupied sockets, non-core root, node and depth guard rails, a
  nested (forearm-on-arm) limb, error order independent of node order, no input mutation.
- **Compatibility**: auxiliary arms require the augmented spine; carapace arm requires the
  great shoulder and lopsided frame; corruption lineages exclude each other only when both
  are present.
- **Asymmetry / extra limbs**: asymmetry per example; gameplay vs. visual proportions with
  defaults; review flags on the brute, none on the humanoid; four arms with differing
  capabilities; a **six-armed** test body with no schema change; a one-armed body; two
  locomotion providers rejected.
- **Equipment**: mount occupancy; unknown item, wrong type, unknown mount, mount in use,
  mount count, unpaired mounts; paired two-handed grip; tag exclusion; capability
  requirement unmet/met.
- **Requirements**: met sets per example; origins follow the sword and the Marrow Arm;
  missing counts; exclusion-only failure; unknown requirement; no slot names;
  every shared-build ability covered.
- **Transformations**: fixture flow; every result valid and matching its expected
  example; eight rejections atomic; no input mutation; displacement with reasons; net
  released/required; two-handed grip lost with one hand; core replacement keeps only
  compatible children; subtree detach displaces nested equipment; late failure rolls back
  everything; eight malformed ops; determinism.
- **Build contract**: humanoid and Marrow bodies equal today's player and soul loadouts;
  every projection validates with the unchanged build rules; lossy extra limbs; build-item
  changes for corrupt and revert; combat view anchors, locomotion module, attack origins
  and modules, hurt classes; all `build_item` links exist.
- **Serialization**: JSON round trips, exact canonical text, order independence, malformed
  / non-object / extra-field / object-shaped input rejected, visual vs. gameplay
  fingerprints, explicit default equals implicit default.
- **Reproducibility / isolation**: identical flows across catalog instances; matches the
  committed example; resolved fingerprint reproducible; core scripts reference no builds,
  combat, scenes, AI, worldgen or legacy slot names; adapter has no combat references;
  main scene unchanged.

**Mutation check** (the suite was run against deliberately broken copies of the library;
each mutation was caught): disabling cycle detection (4 checks fail), pairing (4),
equipment displacement (5), tag exclusion (1), socket-type compatibility (5), the
locomotion rule (2), including visual data in the gameplay fingerprint (2), allowing a
rear guard (1).

Executed results for this change are listed in the PR description (Godot
`4.7.2.stable.official.ed1daf0bf`, headless, Linux x86_64).

## 6. Risks and performance

- **Content cost** is the real constraint: each new part type needs a curated module,
  telegraph and hit-volume review. The model makes this explicit rather than hiding it.
- **Combinatorics**: parts × equipment × abilities grows quickly. Mitigation: typed
  sockets and tags keep combinations small; review flags identify the ones needing work;
  tests enumerate fixtures, not all combinations.
- **Readability can still fail** at the presentation layer (an oversized arm hiding a
  sword windup). Data cannot prove readability; it needs playtesting.
- **Two sources of truth** until integration: shared builds still own slots. The
  projection makes the drift testable, and the legacy slot names live in one adapter file.
- **String ids** can typo; strict validation mitigates as in the build catalog.
- **Node-id stability** matters for saves and Tower snapshots; renaming an id is a
  migration.
- **Performance**: validation and resolution are O(n²) in the worst case over ≤ 24 nodes
  (child scans), negligible, and should run only on change. Runtime cost is in scene
  nodes: each part would add a mesh, a hurt area and possibly an `AnimationPlayer`; a
  6–8 part fighter in GL Compatibility is expected to be fine but is **unmeasured**.
- **Not authorization**: fingerprints detect drift and tampering, not cheating; rewards
  and Tower snapshots still need server validation.

## 7. Decisions requiring human approval

1. **Architecture C** (core-owned anchors + constrained socket tree + curated modules).
2. **One facing, front-only guards** for every body in v0. Rear/omni guards would need a
   separate combat rule.
3. **Exactly one locomotion provider** per body; locomotion changes swap curated modules
   with the same root-motion contract.
4. **Capabilities as the ability gate**, with counts and exclusions; and whether
   capabilities from equipment credit the first mount's limb.
5. **Hurt/reach as named classes**, sizes owned by combat data (sizes not decided).
6. **Review flags** for asymmetry, limb count, locomotion, long reach and large
   hurtboxes — and what each flag actually restricts. No mandatory numeric penalties are
   implied by this prototype.
7. **Displace, never destroy** equipment on transformation; displaced items go to
   `carried`.
8. **Replacing a part resets its proportions**, and keeps only children whose sockets fit.
9. **Engineering guard rails** (24 nodes, depth 6) as provisional sanity limits, not
   design body limits.
10. **Legacy slots become a derived view** once integration starts (owned by the build
    contract; coordinate with Codex).
11. Fixture content (`part.spined_torso`, `part.auxiliary_arm`, `part.carapace_arm`,
    `part.lopsided_torso`, tail, digitigrade legs, fixture greatsword/buckler, `probe.*`
    requirements) is **architectural only** — not approved enemies, loot or abilities.

## 8. Next smallest step toward visualizing one transformation

A standalone, non-courtyard viewer scene (`scenes/anatomy_viewer.tscn`) that builds
primitive meshes from a resolved body: a capsule per part sized by hurt class, a
`Marker3D` per socket and mount, a small arrow at the core `facing` anchor, and coloured
spheres at attack origins. A single key toggles `body.humanoid_fighter` ↔
`body.marrow_replacement` by calling `transform()`, and a headless rendered test
screenshots both states and asserts that the core anchor markers have identical
transforms before and after. No combat, input bindings or animation — just proof that
one transformation is visible and that the combat reference frame does not move.
