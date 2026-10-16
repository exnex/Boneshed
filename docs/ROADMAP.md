# Boneshed — Lean Prototype Roadmap

This is a dependency order, **not** a delivery schedule.

## Gate 0 — Foundation
- Confirm Godot stable version and project platform assumptions.
- Establish project structure, headless boot check, shared combat data contracts, and test conventions.
- Write no complex world/economy systems at this stage.

## Gate 1 — One excellent duel
- Prototype third-person movement, camera, target lock, basic attack, deflection, posture and a readable enemy.
- Test feel at intended frame rates; telegraphs, timing and hit detection must be consistent.
- Iterate with actual playtesting, not just automated pass/fail.

## Gate 2 — Take the enemy's power
- Configure the player and opponent through one shared build/data model.
- Give the opponent one signature arm/ability.
- On victory, loot the augment; equip it and use it in a second duel.
- Demonstrate a meaningful tradeoff rather than a pure stat upgrade.

## Gate 3 — Compact expedition
- One small atmospheric world with combat-focused traversal and one meaningful encounter/dungeon space.
- Test a minimal three-word generator with varied seed and replayable test fixtures.
- Prototype carrying/extraction choices without live server economy.

## Later, only after fun validation
- Broader build library, dungeon/world diversity, Tower of Memories snapshot simulation and validation.
- Server inventory and marketplace, events, progression and rankings as supporting systems.

## Quality gates
- Combat readability and responsiveness
- One enemy genuinely worth rematching
- Salvaged ability changes fighting choices
- Procedural worlds vary encounters, not just scenery
- Clear explicit tests, known limitations and recorded decisions
