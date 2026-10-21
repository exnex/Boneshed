# Expedition preview: procedural regions and dungeon

**Status: isolated prototype awaiting Command Center review and owner playtest.**
This is a separately selectable scene. It does not change the default scene
(`first_expedition.tscn`), the Web/Pages root, save formats, combat rules or
balance, the First Expedition, or the directional melee lab. Region/dungeon sizes,
counts, placements, extraction timing and the satchel are **provisional**; nothing
here approves an inventory, extraction or economy rule.

## Play

Godot **4.7.2.stable.official.ed1daf0bf**, GL Compatibility.

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/play_expedition_preview.sh
```

The selection screen is the First Expedition's (same lists, seed replay and older-
address replay), retitled **Expedition Preview**. Choose three words, then
**Begin expedition**. Fixed fixtures: **Drowned / Hollow / Cathedral, seed 1001**;
**Smoldering / Pallid / Necropolis, seed 7**; **Frozen / Gilded / Citadel, seed 1002**.

Loop: explore the surface → a corrupted soul keeps vigil on the way (duel; **F**
salvage, **E** equip) → find the **descent** (violet beam) → walk into its doorway →
cross the dungeon to the **guardian chamber** (both doors seal for the duel) →
release the guardian (doors open) → claim the **reliquary** in the vault → walk into
the **ascent** (gold ring, appears after victory) or back to the **return** ring at
the entrance → stand in the surface **extraction beacon** (pale gold beam) for 3 s.
An extraction summary lists finds and the build, with Replay / Return buttons.

Controls are the existing ones (WASD, mouse, Tab lock, LMB, C heavy, RMB guard,
Space dodge, Q inherited lunge, F/E salvage/equip, F1/F3, Esc menu). Pickups and
transitions need no key: walk onto them. **R** retries only a duel in progress or a
lost duel; **N** (rematch) is disabled here. The right-hand panel tracks the four
objectives and satchel count.

## Pipeline

All generation is pure data (`RefCounted`, ids/ints/floats/arrays only), separated
from rendering. `ExpeditionPlan.generate(words, seed)` returns `{ok, errors, warnings, plan}`.

| Stage | Owner | Seeded stream (never shared) | Output |
| --- | --- | --- | --- |
| 0. WorldBlueprint | `worldgen/blueprint_generator.gd` (unchanged) | existing domains | identity, generation params, theme tables, domain stream seeds |
| 1. Region graph | `expedition_plan.gd` `_world` | `…|regions|<terrain>` | 4–6 regions on a bounded macro grid (forward-biased growth, optional loop); roles: arrival, descent (deepest), extraction (far leaf), sentinel (on the route), optional vigil |
| 2. Region footprints | same | `…|region.<i>|<terrain>` per region | authored 7×7 templates, biome from the blueprint ranking, elevation level, tag-weighted landmark, cells, 12 m bridges (ramps between levels) |
| 3. Placements | same | `…|roles|<encounters>`, `…|loot|<discoveries>` | spawn, encounter sites (5×5 clear), descent doorway, extraction, discovery finds from the blueprint's theme table |
| 4. Dungeon | `dungeon_plan.gd` | `…|dungeon|<structure>|attempt.<n>` | topology first (entry → 1–3 fillers → guardian → reward, + side cache), then grid embedding of authored room modules |
| 5. Validation | `plan_validator.gd` | — | errors before any node exists; the shell refuses an invalid plan |
| 6. Build | `preview_builder.gd` | presentation-only decor/horizon streams | meshes and collision for exactly the validated solids |

Keyword identity: arrival biome is always the blueprint's primary biome; other
regions draw from its top-three ranking; landmark weights rise with the address's
semantic tags (cold → rime obelisks, fire → ember pyre, water → drowned basin, …);
encounter site themes and finds come from the blueprint's featured encounters and
discovery table; `relief` drives elevation changes, `encounter_density` an optional
second soul, `interior_ratio`/`passage_tightness` dungeon length. The plan embeds
`blueprint_fingerprint`; tests assert the blueprint is byte-for-byte the one the
existing generator produces, including for pre-grammar addresses.

**Dungeon rules.** Rooms are authored modules (`data/expedition_preview/modules.json`)
with odd dimensions so each side has a centred three-cell socket. A corridor runs
straight from a parent socket to the child's opposite socket, so doors are aligned
by construction. Every unrelated pair of pieces keeps at least one void cell between
them; walls are generated on every floor boundary edge, so a door exists only where
a corridor meets a room. An embedding that collides retries on a fresh named stream
(24 attempts); a fixed straight layout is the always-valid fallback (never needed in
the 144 test plans). Validation then checks: role counts, piece overlap/touching,
each corridor end opens onto three walkable room cells, every floor cell reachable,
targets reachable, **the reward is unreachable without crossing the guardian room**,
an unobstructed 22 m guardian floor, two guardian gates, and solid footprints off
the walkable floor. World validation checks region connectivity, ramp steepness,
bridge sockets, full floor reachability, reachable targets, 5×5 site clearance and
solid/floor separation.

## Reuse and the prototype adapter

`preview_expedition.gd` extends `courtyard.gd` exactly like `expedition.gd`. Reused
unchanged: `Fighter`/`Player`, `CombatState`, build adapter, `Swordsman` AI,
`DuelProgression` salvage/equip transactions, HUD, input map. The new pieces are
lifecycle only:

- **Encounter director.** Each generated site holds a dormant Swordsman of the
  existing build. Entering a site's 9 m radius hands the single existing duel
  progression to that site (`progression.begin(false)`), seals the guardian doors,
  and on victory clears the site. A new duel cannot start while salvage is
  unclaimed (prompt: *F*). An exterior soul disengages without healing if the player
  goes 17 m from its post. **Prototype rule:** each new encounter starts both
  fighters at full health; carry-over between encounters is undesigned. A released
  body no longer collides.
- **Transitions** are doorway moves of the player body only; health, posture and build
  carry over. The inactive area is hidden (keeps collision, costs no draw calls).
- **`prototype_satchel.gd`** records generated finds for the extraction summary. It has
  no value, carry limit, loss rule, stash or persistence and does not touch the build
  schema. The Marrow Arm remains a `DuelProgression` transaction.

## Architecture for scale (not implemented)

- **Streaming/chunks:** regions are independent nodes with their own `StaticBody3D`;
  the plan is serializable and region-indexed, so a streamer can build/free regions by
  slot. Macro slots are already a chunk grid.
- **Deterministic subregion seeds:** every region draws from `region.<i>` under the
  blueprint terrain seed; adding regions or stages cannot shift others' draws.
- **LOD / activation budgets:** area-level visibility toggling is the first hook; the
  per-region node split is where distance LOD and physics/AI activation would attach.
- **Biomes/elements, dungeon families, encounter director, resource populations:** all
  table-driven in `modules.json` and blueprint theme tables; the director is a site
  list with activation/leash data rather than hard-coded fights.
- **Save/resume:** a plan is reproducible from address + seed + `VERSION`; runtime
  state to persist would be site cleared flags, collected ids and area — not done.

## Validation

```sh
bash scripts/tooling/test_expedition_preview.sh artifacts/expedition-preview
```

The runner imports, boots the scene, runs the fixture suite headless and rendered,
runs the input-driven playthrough headless and rendered and asserts identical traces,
runs the loop on two contrasting addresses/seeds, and runs three source mutations
(seed removed from region growth; dungeon separation rule weakened; environment
collision disabled), each of which must fail its specific check. Results, captures
and measurements: [evidence](evidence/expedition-preview/README.md).

Automated success proves the specified reachability, determinism and geometry
invariants. It does **not** prove that exploration is interesting, that duels in
open regions feel fair, or that the camera is comfortable in corridors.

## Known shortcomings

- Placeholder geometry; regions are flat plateaus (elevation changes only on
  bridges), landmarks are primitive. No audio, minimap, or interior lighting design.
- One enemy type (the existing corrupted swordsman) for every encounter, reusing the
  existing salvage reward; the guardian therefore drops nothing new once the Marrow
  Arm is owned. Exterior duels have no gate; the Swordsman's direct steering can drift
  to parapets.
- Full-health reset per encounter; no death penalty beyond retrying the duel;
  extraction has no risk/decision weight yet.
- Dungeon has no ceiling (camera clearance) and only one family; room variety is
  seven modules. Region templates are five 7×7 shapes.
- Find/relic ids come from the blueprint discovery table and are display-only.
- Sizes are tuned for the existing 6 m camera; near-wall camera comfort not assessed.
- Standing beside the descent, its tall beam can fill part of the view.
- Every placeholder box is its own mesh: ~870 draw calls on the surface. Measured
  frame cost is in the [evidence](evidence/expedition-preview/README.md); static
  geometry merging per region is the first optimization before larger worlds.
- Not exported to Web; Web/Pages root untouched.

## Human playtest

1. `bash scripts/tooling/play_expedition_preview.sh`; replay **Drowned / Hollow /
   Cathedral, 1001**. Before reading the objective panel, say where you think the goal
   is. Note whether the violet descent beam and pale-gold extraction beam read as
   destinations from the arrival.
2. Fight the vigil soul in the open region; note any unfairness from parapets/edges.
   Salvage (F) and equip (E).
3. Enter the descent, walk to the guardian chamber, confirm both doors seal and the
   duel is readable in the chamber. After victory, take the reliquary and the side
   cache, then use the gold ascent ring.
4. Extract; check the summary. Then replay **Smoldering / Pallid / Necropolis, 7** and
   a fresh random seed; compare whether the worlds feel distinct and whether they
   feel like the address.
5. Record: time to find the descent, any place you got stuck or lost, camera problems
   in corridors/doorways, whether exploration felt worth it, and which of
   region variety / dungeon variety / encounters / rewards matters most next.
