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

## Pending decisions
- Final platform targets and later desktop GPU rendering configuration.
- Exactly how skill/posture/deflection mechanics differ from inspiration.
- Tower AI modes, snapshot lifecycle, competition and rewards.
- Persistence, multiplayer/backend scope, trading authority and cheats.
