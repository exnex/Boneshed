# Equipment foundation: weapons, grips and body modifications

**Status: implemented foundation, catalog 0.4.0. Names, classes and handling numbers are
provisional.** This milestone corrects the Marrow Arm (left-arm body modification; the
ordinary sword stays in the right hand) and gives the shared build contract a clear
distinction between **weapons** and **body modifications**. It does not implement
directional melee, inertia, new hit detection, an inventory or a modular anatomy engine.

Owner direction this follows ([DECISIONS.md](DECISIONS.md), 2026-10-20): weapons replace or
equip wielded weapons; body modifications change body parts or capabilities and are not
merely another weapon or an obligatory special-button attack; both use the shared
player/enemy build foundation; Marrow Arm is a body modification and its Marrow Lunge is
provisional.

## 1. Architecture

One rule set, two item categories, two slot kinds. Everything is catalog data; nothing is
special-cased by item id in the rules.

```
body slot (anatomical part)            grip slot (a hand on a limb)
  arm_r  ── carries ──► hand_r  ◄── pair ──►  hand_l ◄── carries ── arm_l
    ▲                      ▲                     ▲                     ▲
 body_mod             weapon (1 or 2 grips)   weapon / shield       body_mod
 (replaces the arm)                                               (Marrow Arm: no hand)
```

| Concept | Where it lives | Meaning |
| --- | --- | --- |
| **Body slot** (`kind: body`) | `slots[]` with `part` and `side` | An anatomical part. Empty = the natural part. Accepts only `body_mod` items whose `anatomy.part` matches. |
| **Grip slot** (`kind: grip`) | `slots[]` with `limb`, optional `pair`, `side` | A hand carried by a body slot. Exists only while that limb has a hand. Accepts only `weapon` items. |
| **Weapon** (`category: weapon`) | `items[].weapon` | Physical profile: `class`, `grip` (`one_handed`/`two_handed`), `reach`, `weight`, `handling` {length m, mass kg, balance 0–1 from grip}, `defense` {guard, deflect}. Grants its attacks (`grants`). |
| **Body modification** (`category: body_mod`) | `items[].anatomy` | `part` replaced, `grip` (does the new limb have a hand?), optional explicit `natural_weapon` (same physical profile, no grip). Grants **no** attack by default. |
| **Legacy ability** | `legacy_abilities[]` | The only abilities a body modification may grant, and the only ones allowed on the `special` (Q) binding. Today: `ability.marrow_lunge`. |
| **Equipment view** | `resolved.equipment` (derived) | Body parts and whether each keeps a grip; every grip, whether it exists and what holds it; every weapon (including natural weapons) with side, occupied grips and physical profile; weapon vs body capabilities. |

**Why this shape.** It keeps the existing build format (`equipped` maps one slot to one
item), so saves, salvage references and the adapter keep working, while making the
anatomy explicit enough to answer the questions directional melee will ask: *which hand
holds what, how long and heavy is it, can it block, where does the strike start*. Grips
belong to limbs, so replacing a limb is what removes a hand — a handless Marrow Arm needs
no special "excludes two-handed" tag; the two-handed weapon simply cannot find its pair.
Pairs and limbs are data, so a body with four hands is four grip slots (tested), not a new
rule. The isolated anatomy graph ([ANATOMY.md](ANATOMY.md)) already uses the same node
names (`arm_l`, `arm_r`, `arm_r/grip`), so a later integration maps one-to-one.

**Rejected alternatives.** A separate `wielded` list with explicit grip arrays (cleaner for
two-handers, but a new build schema, migration of every fixture and salvage reference for
no gameplay gain today). Making body modifications a kind of weapon (exactly the coupling
the owner asked to remove). Integrating the anatomy graph now (larger than this milestone;
see §6).

## 2. Rules (deterministic, slot order, atomic)

| Rule | Error code |
| --- | --- |
| Item category must match slot kind, slot in `fits_slots`; body mods must match the part | `wrong_slot` |
| A weapon's grip (and a two-hander's pair) must exist: its limb is natural or a body mod with `grip: true` | `grip_unavailable` (names the blocking body mod) |
| A two-handed weapon's pair grip must be empty | `grip_occupied` |
| Existing tag requirements/exclusions, duplicate abilities, binding conflicts | unchanged |

`equip`, `unequip` and the new `replace` (atomic swap; the previous item goes to
`carried`) all validate the whole build and return the input unchanged on failure. So
equipping Marrow Arm onto an arm whose hand holds a weapon is rejected, never silently
displacing the weapon. A two-handed weapon is stored once, in the grip it is held from.

Catalog validation (`build_catalog.gd`) additionally enforces: grips name a body-slot limb;
pairs are mutual and on different limbs; two-handed weapons only fit paired grips; weapon
and natural-weapon profiles use catalog class names and sane handling numbers; a natural
weapon must use class `natural` and a held weapon must not; body mods may grant only
legacy abilities; weapons may not grant legacy abilities; only legacy abilities use the
`special` binding; a body modification still needs at least one explicit disadvantage
(a handless limb counts: `removes_grip`).

## 3. Marrow Arm and the playable loop

| | Catalog 0.3.0 (main before this PR) | Catalog 0.4.0 |
| --- | --- | --- |
| Marrow Arm | `augment` in `right_arm`, `excludes_tags: [grip.two_handed]` | `body_mod` in `arm_l`, `anatomy: {part: arm, grip: false}` |
| Sword | `main_hand`; drawn in the **left** hand whenever the fighter had a special attack | `hand_r`; drawn where the build says (right) |
| Handedness source | `CombatState.signature` (an ability) | `resolved.equipment` via `Fighter.equipment` → `EquipmentLook` |
| Marrow Lunge | granted by the arm | still granted, but as a catalog-declared **legacy** ability; Q unchanged |

Defeat → salvage (F) → equip (E, now into `arm_l`) → next duel (N) → Q lunge all work as
before for both actors, through the same item rules. Damage, timing, posture, reach, AI and
controls are unchanged; the lunge's curated key track is mirrored exactly (the bone draws
back over the left shoulder; the sword stays in the right hand). The HUD card now says
"left arm body modification" and labels Q as legacy.

## 4. Data-format changes and compatibility

- `boneshed.build_catalog.v1`, catalog `0.4.0`: new slot shape (`kind`, `side`, `limb`,
  `pair` / `part`), `equipment_classes`, `legacy_abilities`, item `weapon` / `anatomy`
  blocks, category `augment` → `body_mod`, Marrow telegraph text mentions the left arm.
- Build format `boneshed.build.v0` is **unchanged in shape**; slot ids change:
  `main_hand → hand_r`, `left_arm → arm_l`, `right_arm → arm_r`.
- `boneshed.resolved_build.v1`: adds `equipment`. Fingerprints change.
- **Recorded builds**: `scripts/builds/build_migration.gd` upgrades catalog-0.3.0 builds
  (renames slots; a body mod that no longer fits its renamed slot moves to the single
  same-part slot it fits, reported as `relocated`). The 0.3.0 courtyard builds from main
  are kept as a fixture and migrate byte-for-byte to the new `data/builds/*.json`.
- **Salvage references** pin the catalog version and fingerprints, so 0.3.0 references are
  rejected (`catalog_version_mismatch`), as with every earlier catalog change. No
  persistence exists, so nothing live is lost.
- Anatomy prototype: `build_catalog_version` 0.4.0; `body.marrow_replacement` now replaces
  `arm_l` and keeps the sword in `arm_r/grip`; the projection maps grips by side.
  Regenerated examples.

## 5. What directional melee can read now

From `resolved.equipment.weapons[]`: which grip(s) and side the weapon is held from (attack
origin), `reach` and `weight` classes, `handling.length`, `handling.mass`,
`handling.balance` (for inertia/moment), `grip` (one- vs two-handed guard), `class`
(blade/staff/shield/natural), and `defense.guard` / `defense.deflect`. From `body[]` and
`grips[]`: which limbs exist, which are replaced, which hands are free (e.g. for a shield).
No combat code reads these values yet; `attack_modules.gd` still owns the sword's fixed
2.35 m hit volume. Natural weapons appear in the same list with `natural: true` and no grips.

## 6. Known limitations and deferred capabilities

- One humanoid body plan in the shipped catalog. Extra limbs are representable as extra
  slots (tested with a four-armed fixture catalog) but there is no per-profile body plan
  and no body mod that *adds* slots; the anatomy graph remains isolated.
- Only arms are modifiable (`body_parts: [arm]`); legs, torso, head are deferred.
- No "versatile" (one-or-two-handed) grip, off-hand-only weapon class, grip strength, or
  body-mod effects on *how* a weapon is held (only *whether* a hand exists).
- Handling numbers and class names are placeholders; no balance is implied.
- Presentation: the heavy attack's key poses still bring the off hand toward the hilt;
  with a Marrow Arm that hand is hidden, but a two-handed-looking swing on a one-handed
  sword is pre-existing placeholder animation. Body-mod visuals are curated per item
  (`EquipmentLook.BODY_MOD_VISUALS`); an item without one fails the agreement check.
- Legacy Marrow Lunge remains on Q for the playable loop; it is isolated, not removed.
- Equip never displaces a held weapon automatically; the UI has no unequip flow.

## 7. Open questions for the owner

1. Should Marrow Arm be declared a **natural weapon** (class `natural`, long reach) so the
   directional system can strike with the bone itself, replacing the legacy Q lunge?
2. When a body modification would remove a hand that holds a weapon, should equipping
   **reject** (current) or **displace** the weapon to carried (the anatomy prototype's rule)?
3. Is `hand_r`/`hand_l` handedness fixed per body, or should a build choose its primary
   hand (left-handed fighters)? The data allows either; attacks currently assume one sword.
4. Are shields weapons (current: `weapon` with class `shield`) or a separate category?
5. Which other parts should be modifiable next (legs for movement, torso for posture)?

## 8. Tests and evidence

- `scripts/qa/build_tests.gd` (205 checks): catalog semantics and 30+ malformed catalogs;
  grip availability, pairs, occupancy, shield + one-hander, dual one-handers; weapon vs
  anatomical replacement; natural weapons and the legacy isolation; a four-armed fixture;
  0.3.0 migration; player/enemy parity.
- `scripts/qa/marrow_tests.gd` (211): placement and handedness for both actors, visual
  agreement after salvage/equip/rematch, lunge pose (bone left, sword right) for every
  defense, same item rules for player and enemy.
- `scripts/qa/marrow_playthrough.gd`: input-driven loop with agreement checks plus a new
  `--negative=equipment-side` control; `marrow_mutations.py` adds four presentation/rules
  mutations that must be caught.
- `scripts/qa/equipment_capture.gd`: rendered front/rear/lunge close-ups after the real
  victory → salvage → equip → next-duel path; runs unchanged on older revisions for
  before/after comparisons and writes `placement.json`.
