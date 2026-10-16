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


## Gate 1 implementation checkpoint — 2026-10-16

- **Implemented on main** (`4a15514b3d`, game PR #2): Godot 4.7.2 GL Compatibility third-person courtyard duel, movement, camera lock, player/enemy combat rules, guard/deflect, posture, dodge, enemy AI, reset, and recorded cloud tests (30 combat / 35 rendered-input checks; negative controls). This is a functional prototype, **not a passed fun/feel gate**.
- **Awaiting human review**: [draft PR #3](https://github.com/exnex/Boneshed/pull/3) documents Claude's independent replay and adversarial analysis and proposes three narrow correctness fixes with reported 33/37 passing assertions. It is not on `main` as of this checkpoint; do not refer to its fixes as merged until verified. The PR explicitly requests human desktop playtesting before merge.
- **Proposed next bounded implementation** (not a confirmed final design): deterministic enemy defensive response to player attacks plus limited resistance to interruption during heavy windups. Add a legal-input attack-mashing probe and tests showing this strategy no longer delivers a full-health win while skilled deflect/punish play still works. Preserve responsive player controls and record visible tells. Do this in a separate branch **after coordinating PR #3**.
- **Next evaluation gates**: shared capped windup tracking, guard/deflect spam exploit repair, readable close-range camera/telegraphs, and a human playtest session. These are candidate iterations, not fixed parameters or an authorization to change all combat balance at once.

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
