# Boneshed — Game Vision (working design)

## Player promise
**Meet a formidable corrupted soul. Learn its moves. Release it. Claim a piece of its power. Become a different fighter.**

Boneshed is a new game that reuses the name of an older, distinct Boneshed idea. Its core is skill-based combat and build progression—not collecting creatures or managing an economy.

## Pillars — confirmed direction
1. **Precision duels:** third-person, Sekiro-inspired combat, emphasizing readable attacks, deflections, posture pressure, aggression, and mastery.
2. **Corrupted souls:** enemies inhabit atmospheric, desolate worlds; defeating them is framed as releasing them.
3. **Shared builds:** player and enemies use the same fundamental stats, skills, items, and combat-resolution rules. Enemy forms may have exceptional stats paired with explicit weaknesses/tradeoffs.
4. **Salvage and transformation:** foes may carry equipment, materials, skills, and distinctive body augments. A memorable enemy attack may become a usable player augment after defeat.
5. **Keyword expeditions:** three poetic, .hack-inspired words and optional resource-consuming modifiers influence a world; each expedition gets its own random seed. Worlds and dungeons must be engaging rather than endless repetitive terrain.
6. **Tower of Memories:** a player can cache a build for others to challenge. The challenger controls their own character against an AI-operated snapshot, asynchronously. Full rules remain open.

## Expedition loop (proposed, subject to prototyping)
Choose three words → enter an unpredictable desolate world → fight corrupted souls → salvage parts/gear → decide what to carry and when to extract → improve build → challenge harder worlds or the Tower.

## Desired tone
Sparse, haunted, melancholy; a beautiful but mostly empty-feeling world, punctuated by meaningful enemy encounters. The old Boneshed theme—that pursuit of power changes the body and raises questions of humanity—is an inspiration, not a requirement to recreate its descent through Hell.

## Supporting possibilities, not the core
Player-to-player marketplace, tradeable loot/augments, rarer world phenomena, community events, leaderboard records, and limited expedition capacity. Prior brainstorming did not finalize their implementation or balancing.

## Non-goals
No creature collecting or creature autobattling. No mandatory crafting empire, homestead, MMO-scale open world, or generalized survival mechanics. Avoid bloating the early game with economy systems.

## Critical open questions
- Exact combat controls, posture/deathblow rules, camera, and enemy AI architecture
- Death/loss rules and whether unextracted inventory is recoverable
- Body slots, augmentation compatibility, acquisition and repair logic
- Keyword grammar, weights, rarity and generation constraints
- Tower snapshot AI and validation/anti-cheat
- Final platform targets and desktop GPU rendering configuration (the Milestone 1
  cloud prototype pins Godot 4.7.2 with GL Compatibility)

## First fun test
A single ruined courtyard; one responsive player; one readable corrupted swordsman with a distinctive move; defeat, salvage, equip, and use that move in a second duel. If this is not fun, do not expand content.
