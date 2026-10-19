# First Expedition vertical slice

**Confirmed task:** connect the three-keyword blueprint to a small desktop expedition
and the existing corrupted-soul duel. The owner considers the current combat good
enough to continue development. This does not settle combat balance, salvage-loop
acceptance, or the provisional keyword algorithms.

## Play

Use **Godot 4.7.2.stable.official.ed1daf0bf**, GL Compatibility. The existing setup
verifies the official archive against both the release manifest and pinned SHA-512.

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/play.sh
```

F5 opens `scenes/first_expedition.tscn`. Choose three different supported words and
**Begin expedition**. New expeditions use four bytes from Godot's `Crypto` entropy
source. To reproduce a world, select its three words in the same order, enable
**Replay an existing seed**, and enter its displayed seed (0–4294967295).
For a fixed fixture, use **Drowned / Hollow / Cathedral, seed 1001**.

Follow the floor inlay through the empty reliquary toward the ring. WASD moves,
mouse orbits, wheel zooms, Tab locks, LMB attacks, C uses heavy, RMB guards/tap-deflects,
and Space dodges. The soul waits until you enter the arena; the entrance portcullis
closes behind you. It opens on victory. Fight and release the same Marrow Arm
swordsman as the salvage courtyard: **F** salvages, **E** equips, **N** rematches,
**Q** uses the inherited Marrow Lunge. F1/F3 retain controls/diagnostics.

**R** retries with current equipment. Before reaching the arena it restarts at the
arrival; after reaching it, retries and rematches start in the arena. Zoom selection
survives these transitions. **Esc** pauses and opens a mouse-operated menu with
Resume, Restart this address + seed, and Return to keyword selection. Restart and
return clear this expedition's salvage. Restart replays the same geometry from the
arrival. A new expedition starts with the initial build and default zoom; no disk save.

The original regression scenes remain directly runnable:

```sh
source scripts/tooling/env.sh
"$GODOT_BIN" --path "$REPO_ROOT" res://scenes/courtyard.tscn
"$GODOT_BIN" --path "$REPO_ROOT" res://scenes/salvage_courtyard.tscn
```

The existing **Web/Web QA** presets deliberately retain the salvage courtyard via
the `.web` main-scene override. This slice targets desktop; no preview is published.
The export filters include the now-runtime worldgen JSON. Browser regression checks
continue to exercise the prior courtyard input/zoom flow.

## Implementation boundaries

- `expedition_layout.gd` is a pure, versioned WorldBlueprint consumer. Three curated
  footprints (arrival, reliquary, arena), three routing families, mirrored bends and
  spacing variation produce one bounded causeway. Floors occupy a 4 m grid; corridors
  are 12 m wide; the arena is 28 m across, with a clear central 20 m square. These
  dimensions, route families and encounter placement are **provisional**.
- Identity derives from the existing seed-independent axes and resolved sense tags.
  Word ordering, duplicate rejection, senses and blueprint formulas are unchanged.
  A named structure stream chooses geography. Independent terrain/atmosphere streams
  choose architectural breakage and distant silhouettes. The layout fingerprint
  includes the blueprint and generator version. It identifies generated data, not
  pixel output or a cross-platform physics replay.
- `world_builder.gd` creates primitive meshes, shared materials and environment
  collision. Elevation/built tags change monumental geometry; enclosure chooses a
  roof over the reliquary; ruin level breaks architecture. Water/cold/fire/bone/wild/
  wealth/profane cues affect channels, shards, cracks, ribs, thorns and trim. Opposed
  fire/cold tags use visibly separate sides. Light and fog are clamped to protect
  telegraphs. Water, ice and fire are visual themes, **not hazards or new mechanics**.
  Wide routes reserve clearance by omitting interfering solid scenery.
- `expedition.gd` inherits the existing courtyard controller and overrides only world
  construction, spawn/reset locations, encounter activation, gate lifecycle and the
  exploration prompt. `Fighter`, `CombatState`, build adapter, enemy AI, attack modules,
  `DuelProgression`, HUD and salvage/equip/rematch transactions are reused unchanged.
  The arena gate confines the direct-steering enemy to open geometry, avoiding a
  second AI/navigation system.
- `expedition_select.gd` owns the current scene and request. Its UI processes while
  paused; the expedition explicitly uses `PROCESS_MODE_PAUSABLE`. Removing an
  expedition destroys its world, fighters and progression together. No autoload,
  persistent inventory, backend, economy or new asset/dependency is introduced.
  A removed/queued expedition ignores deferred contact resolution, so returning
  during an attack cannot query a discarded physics world or produce a late reward.

## Validation and limits

Run `bash scripts/tooling/test_expedition.sh artifacts/expedition-fresh` in addition
to the existing test runners. The new runner checks golden fingerprints, repeated
generation, identity across 32 seeds for each of six addresses covering all 16 words,
seeded geographic diversity, connected floor coverage, actual capsule sweeps/floor
rays, arena clearance and every boundary edge for 18 built fixtures. It also checks
the gate's physical opening/closing, seed/duplicate UI feedback, keyboard activation,
pause, retry/zoom, restart and return. Isolated seed and collision mutations must fail.
Controlled generated-world camera fixtures also check open-arena distance, gate
and column obstruction, recovery, low-parapet visibility and retry zoom retention.

The expedition playthrough extends the existing Marrow playthrough bot. It enters
through the shipped selection screen, walks the actual approach with physical-key
events, activates the soul, wins, salvages/equips, and wins the second duel using
the inherited attack. It never writes positions, combat state, AI, inventory or rewards.
Headless and rendered combat/input traces must match. Controlled physics/reset/camera
fixtures in the other test are explicitly separate from that legal-input run.

See [executed results, captures and inspection notes](evidence/first-expedition/README.md).
Automated success proves specified reachability and invariants, **not human gameplay
acceptance, readability, fairness or desktop GPU performance**.

Known limits: three simple footprints and a fixed encounter order; flat causeways
over a void rather than terrain; abstract keyword cues with substantial reuse of
architecture; no sound, authored animation, discoveries or extraction decisions.
The same address can produce repeated routing families. All 16 words are supported,
but not every ordered combination or desktop GPU has been physically tested. The
existing analytic combat hit volumes, player-first resolution and 60 Hz camera
remain. Near-wall/close-contact camera comfort still needs human assessment.
Collision can retract the camera below the selected minimum and crop the player's
feet, as in the existing courtyard camera; avoiding geometry takes precedence.

## Proposed next step

Command Center reviews this PR and owns merges/roadmap reconciliation under the
parallel-ownership handoff. Proposed roadmap delta: mark Gate 3's bounded integration
implemented after merge, keep human expedition/full-salvage-loop acceptance open,
and preserve the earlier combat, high-refresh, animation-policy and keyword-design
watch items. This slice does not modify combat animation/presentation resources.

Have the owner play seed 1001 and a fresh seed, then a cold/fire contrast. Record
whether the route and soul destination are clear, atmosphere feels sparse rather
than unfinished, keywords remain recognizable, the portcullis is understandable,
and F/E/N/Q plus R/Esc are discoverable. Rank that feedback before adding more
modules or reconsidering keyword semantics. Extraction, Tower and backend remain deferred.
