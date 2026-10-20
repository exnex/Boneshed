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

## Confirmed camera zoom scope — 2026-10-19
- Extend PR #19's third-person camera with smooth mouse-wheel zoom, preserving
  orbit controls, lock-on framing/manual override and environmental obstruction.
- Keep the player's selected distance separate from collision-constrained actual
  distance; retain the selection through retry, defeat, salvage/equip and next duel.
  Persistence across game restarts is deferred.
- Keep third-person limits and one documented tuning owner. Exact limits,
  sensitivity and smoothing remain provisional pending human playtesting.
- Update F1 controls and provide automated/rendered evidence and playtest steps;
  no combat balance changes, camera redesign or browser-preview publication.

## Pending decisions
- Final platform targets and later desktop GPU rendering configuration.
- Exactly how skill/posture/deflection mechanics differ from inspiration.
- Tower AI modes, snapshot lifecycle, competition and rewards.
- Persistence, multiplayer/backend scope, trading authority and cheats.

## Confirmed owner direction — 2026-10-19 playtest

- Combined First Expedition plus combat-presentation build was played and liked; development should progress, with ongoing tuning and full validation still open.
- Three-keyword world names should form a coherent **adjective + adjective + noun** phrase, instead of a string of descriptors. Exact word taxonomy, sample vocabulary and mapping semantics remain open implementation choices; preserve deterministic address/seed behavior and reasonable compatibility.
- Long-term melee identity: **Last Oasis-inspired directional mouse-controlled attacks and blocks** and **Mordhau-like inertia/angle-dependent weapon handling**, tempered by the immediacy and skill expression of **Sekiro-like fast duels**. Weapon dimensions include reach (short/medium/long), weight (light/medium/heavy), class (blades/staves), grip (two-handed weapon guarding vs one-handed plus optional shield). Specific controls, collision authority, drag/accel limits, endurance and balance are unapproved and should be separately prototyped first.
- NPC combatants should fight for survival: reposition/retreat, dodge when threatened, counterattack after effective defense, and select appropriate moments for attack rather than simply blocking. AI must be readable and fair, not input-reading/omniscient. Exact behavior and tuning remain provisional.

## Owner design clarification — 2026-10-20

- **Three distinct keyword selection pools**, not just duplicate validation: slot 1 describes environmental/state condition, slot 2 describes quality/character, slot 3 is place/concept noun. Normal UI must not offer the same word in multiple slots. Grammar is adjective + adjective + noun. Preserve old recorded addresses and seed determinism through explicit legacy replay; exact vocabulary/meaning assignments remain provisional.
- **Salvage classification:** weapons replace/equip wielded weapons; body modifications change body parts/anatomy or capabilities. Body modifications must not be modeled merely as an additional weapon or obligatory stand-alone special-button attack. Both categories use the shared player/enemy build foundation. Marrow Arm is a **body modification**, while its legacy Marrow Lunge special attack is provisional and must not predetermine the upcoming directional/inertial melee system.
- **Observed discrepancy:** after equipping Marrow Arm, owner saw the part on the right rather than the expected left. Current catalog deliberately assigns `right_arm` and the visual swaps the sword to the left. Preferred near-term exemplar: a left-arm Marrow modification while the sword remains wielded in the right hand, with explicit attachment/mount rules. Preserve fair combat and existing salvage/rematch checks while correcting this; the final anatomy/weapon schema remains subject to prototyping.
- **Owner impression:** latest combined combat with survival-minded AI feels much better; keep it as the working baseline. Directional melee is the next distinct prototype, not an implicit part of this equipment fix.

## Owner-ranked ghost concept — 2026-10-20 (feature naming and details remain open)

- Planned asynchronous ranked build-versus-build mode with **no live simultaneous human PvP**; the challenged opponent is always a computer-controlled version of another player's submitted build.
- A player can **sacrifice a build to submit a fixed ghost snapshot**. Only one active submitted ghost per player; a new submission retires the previous ghost, whose historical ranked statistics remain inspectable.
- The owner can adjust that ghost's **AI behavior after submission**, using a decision-tree-like system, but **cannot change the frozen build**. Legal/available AI behavior capabilities depend on equipped items, skills and body anatomy; this must be previewable while constructing/equipping a build.
- Offensive points come from personally winning ranked challenges against others' AI ghosts. Defensive points come when challengers lose to one's AI ghost. Exact ranked aggregation/matchmaking/season policy remains undecided.
- Normal weapon/armor items can be kept in outside inventory/storage. Body modifications are semi-permanent, cannot simply be taken off and stored, and generally require a replacement to change. Sacrificing the current build into the ranked ghost **resets the live build's body modification state**, enabling a new cycle.
- **Confirmed:** in ranked offense, the human directly controls their **active submitted, frozen ghost build** after sacrificing it in ordinary progression. The defending opponent remains an AI-controlled ghost. The active adventuring build is not the offensive ranked avatar.
- The feature's name is **not decided**. Earlier `Tower of Memories` is a working concept label, not confirmed branding. Suggested `Echo / Imprint / Echo Tactics / Assault / Defense` names are proposals, not owner-approved.
- Full details and open decisions: [Asynchronous ranked ghost design](ASYNC_RANKED_GHOSTS.md). Design does not authorize building backend/inventories/ranked mode now; develop reusable intent/capability-based AI foundations in focused combat prototypes.

## Ranked ghost clarification and optional entrance exam — 2026-10-20

- **Ranked offensive avatar decided:** the human pilots their submitted frozen ghost in ranked offense. Its sacrificed equipment/body are no longer on their ordinary adventurer, but the ranked ghost remains playable in the ranked mode.
- **Optional entrance exam concept:** before submission, players may test their **current unsacrificed adventuring build** against a random sequence of progressively higher-ranked AI-controlled ghosts. The exam is not a prerequisite to submission. Initial candidate is **five successive 1v1 encounters, requiring three defeats of each opponent to clear its encounter (15 enemy defeats total)**, with **three lives shared across the entire run**. Each time player HP falls to zero, one life is lost. All three lost ends the run; this is intentionally punishing. A ten-encounter variant and rewards are proposals, not confirmed quantities/policies.
- **Important limitation:** human-controlled exam performance is not an accurate ceiling on an eventual AI-tactics-optimized ghost; communicate this to players. Do not convert this optional diagnostic into a gate that rejects unusual AI-first builds.
- See [async ranked design](ASYNC_RANKED_GHOSTS.md). Ranked implementation, backend/rewards, submission transaction and exam construction remain deferred pending separate scope.

## Owner soul-rooted Echo behavior direction — 2026-10-20

- **Soul acquisition is required before creating/submitting an Echo.** Different soul types establish starting AI temperament such as aggressive, defensive, balanced and potentially others.
- The submitted build supplies **tactics points** and capability-specific tactical nodes. Players invest a **limited budget** in modifying/adding conditional decisions. The tactical structure is **modular and procedurally generated based on soul and build**; player-visible cause-and-effect behavior and deep strategic tradeoffs are intended.
- This refines/supersedes the *generic empty programmable decision-tree* assumption. The frozen submitted physical build remains fixed; tactics investment remains editable after submission as already specified. Whether the installed soul itself is consumable/frozen, point formula, graph generation randomness, node economy, reallocation cost and UI presentation are not approved.
- See [Soulbound Tactics](SOULBOUND_TACTICS.md) for separated recommendations and owner questions. No soul-acquisition loop or tactics editor implementation is authorized by this design record.
