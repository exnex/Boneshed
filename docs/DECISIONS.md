# Boneshed — Decision Log

Keep approved direction separate from brainstorms. Amend this document only when user decisions change.

## Confirmed direction — 2026-10-15
- Project is named **Boneshed**, distinct from an older Boneshed concept.
- Central appeal is **Sekiro-inspired skill-based combat** against corrupted souls being released.
- Game atmosphere: empty, desolate, haunting procedural worlds.
- Player and enemy forms share core build mechanics: skills, items, stats and potentially body modifications; some enemy forms can have extreme stats balanced with disadvantages.
- Progression from world expeditions enables stronger or different builds.
- World generation: three poetic .hack-inspired keywords; modifiers influence world resources, elemental conditions, landforms, enemies and difficulty; a fresh random seed prevents identical addresses from forcing identical layouts.
- Defeated enemies may yield their visible signature augments/abilities, body parts, gear and materials.
- Tower of Memories: player-cached builds become AI-operated encounters for other players to fight actively and asynchronously.
- No creature collection or creature autobattler.

## Confirmed keyword-world principle — 2026-10-17
- **Recognizable identity, unpredictable worlds (option B):** the same three-word address consistently establishes a recognizable thematic identity, atmosphere and broad content expectations, but a fresh seed can produce substantially different geography, landmarks, traversal layouts, dungeon structures, encounter arrangements and discoveries. Players should not know the entire expedition from its words alone.
- This is a **design goal**, not approval of the current generator's exact word ordering, position weights, seed jitter, sample words, duplicate handling, biome mapping, encounter-density formulas or contradiction-resolution implementation.
- Preserve deterministic replay for a given address plus seed and sufficient constraints for readable, fair precision combat. Variation should not mean arbitrary semantic identity changes.

## Confirmed augmentation direction — 2026-10-17
- **Extreme bodily transformations are allowed, with gameplay constraints (option B).** Salvaged body augmentations may substantially change anatomy, proportions, silhouette, limb count and fighting style; characters need not stay conventionally humanoid.
- Such transformations must retain readable attacks and hitboxes, reliable controls, fair combat and equipment/animation compatibility. The exact anatomy-slot taxonomy, degree of modularity, movement exceptions, transformation costs and allowed builds are **not yet decided**.
- This does not approve a fully modular, unrestricted body-reconstruction system or the prototype Marrow Arm's numerical penalties.

## Proposed, not locked
- Lootable bodies as actual inventories.
- Extraction-style expedition carry limits, loss on defeat, limited stash.
- Procedural augments from curated attack modules; damaged parts may require repair.
- Player marketplace, resource sinks, community challenges and leaderboards.
- Three keyword star ratings (0–5) affecting potential or risk rather than guaranteed quality.
- First milestone design and test criteria.

## Confirmed Milestone 1 implementation scope
- Use Godot **4.7.2 stable**, exact build `4.7.2.stable.official.ed1daf0bf`, with
  GL Compatibility for the Linux cloud prototype. The engine archive must pass
  official checksum verification.
- Implement one primitive third-person courtyard duel and automated/headless plus
  rendered validation. The prototype's specific health, posture, deflection, dodge,
  and attack timing rules remain provisional and require human evaluation.
- Salvageable augmentations are deferred until after assessment of this duel.

## Confirmed combat direction — 2026-10-17
- Player attacks must allow movement through windup, swing and recovery.
- The NPC must also move while attacking, and moving players must be able to turn
  during their attacks. Steering rate and AI footwork remain provisional tuning.
- Exact movement speed during attacks remains provisional tuning.
- Dodging must grant invulnerability and cancel an attack immediately; a fresh
  guard press must also cancel into defense during windup, swing or recovery.
  Invulnerability duration, cooldown and defense tuning remain provisional.

## Confirmed first-playable task scope — 2026-10-18
- Implement the shared Marrow Lunge module for the corrupted swordsman and player,
  then legitimate victory → salvage Marrow Arm → inspect/equip → use it in a second duel.
- Provide ordinary desktop controls and a minimal HUD/equipment interaction; use the
  existing build/salvage validation. No full inventory, arbitrary anatomy integration,
  resource economy, new world/enemy content, or preview publication.
- Preserve core defense responsiveness: the earlier fixture's reduced deflection
  window is not approved and is removed from the playable augment.
- Exact attack numbers, input choices, compatibility restrictions and visual projection
  remain provisional; automated validation does not settle human game feel.

## Pending decisions
- Final platform targets and later desktop GPU rendering configuration.
- Exactly how skill/posture/deflection mechanics differ from inspiration.
- Tower AI modes, snapshot lifecycle, competition and rewards.
- Persistence, multiplayer/backend scope, trading authority and cheats.
