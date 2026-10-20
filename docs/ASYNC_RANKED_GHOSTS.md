# Asynchronous ranked build-ghost system — owner concept, 2026-10-20

**Status:** Owner-described intended feature, name and many implementation rules unresolved. This doc distinguishes owner-confirmed concept details from recommendations and unanswered questions. It does **not** authorize implementation of ranked matchmaking, networking, persistence, inventories or a full visual behavior editor yet.

## Core loop (owner-confirmed concept)

1. Players acquire/change builds by adventuring, fighting and other acquisition sources. Equipment including armor and weapons can be kept in external inventories/storage. **Body modifications** are semi-permanent: they cannot simply be unequipped into storage; normally replacing one requires finding another compatible modification.
2. A player can **sacrifice the entire submitted character build** to create a fixed ranked ghost/snapshot. Submission removes the sacrificed build from regular play, resets its body's modifications, and enables a fresh build progression cycle. The exact fate of non-equipped items, storage, duplicates and progression currencies has **not** been specified.
3. Each player has **one currently active submitted ghost** in the ranked mode. Submitting another build **retires** the previous ghost; its historical ranked performance remains inspectable. Whether retired ghosts are challengeable or only historical is unconfirmed.
4. Two asymmetric ranked interactions:
   - **Offense:** player-controlled challenge against another player's AI-controlled ghost, gaining *offensive points* for wins.
   - **Defense:** when other players face their AI-controlled ghost and **lose**, the ghost's owner gains *defensive points*.
   At least one participant is AI controlled and the challenged ghost is always AI controlled. This is **asynchronous** competition, not synchronized human-vs-human PvP.
5. After submission, owners can edit their ghost's **behavior decision tree/policy**, but **cannot change its underlying submitted build**. Behavior options and tactics derive from the build's real equipment, anatomy, skills, weapon/grip capabilities and other actual legal actions. Build/equip UX must transparently disclose which ghost-tactic capabilities each choice grants, blocks or changes.
6. The player should be able to elect to use the submitted build in ranked attacks; **exact semantics of piloting a fixed snapshot after sacrifice** versus using a new/live character require clarification. Preserve this distinction explicitly rather than guessing.

## Proposed player-facing terminology (NOT confirmed names)

| Concept | Suggested label |
| --- | --- |
| Ranked mode | Tower of Memories (working prior name; owner says unnamed) |
| Ghost build | Echo |
| Submission/sacrifice | Imprint |
| Currently submitted record | Active Echo |
| Superseded record | Retired Echo |
| Behavior ruleset | Echo Tactics |
| Rule editor | Tactics Editor |
| Points earned for successful played attacks | Assault Points or Assault Rating (points vs rating algorithm undecided) |
| Points earned when an AI ghost defeats a human challenger | Defense Points or Defense Rating |
| Composite competition position | Tower Rank (formula unconfirmed) |

Keep language accessible. Name lock requires explicit owner approval.

## Architecture implications (recommendations; not yet authorized as implementation)

- **Combat action parity:** AI policies should output the same legal input-intents that human players use (directional attack, guard, parry, footwork, dodge and build-granted actions) through shared combat rules. AI must not read private intent or future inputs, and should have constrained reaction delay/perception.
- **Capability-driven behaviors:** derive editable action/condition types from resolved build/equipment and anatomy, including grip loss. Distinguish action unavailable, condition unsupported, and valid but strategically weak. Surface previews before submission.
- **Immutable snapshot vs mutable tactics:** versioned authenticated build record/snapshot is immutable; policy configuration has its own owner-authorized versioned revisions and validation. Keep retired builds and historic scores with snapshot/rules version identifiers. Consider replay/audit and server-authoritative result computation.
- **Economic reset:** explicit confirmation of irreversibly surrendered build, clear separation of equipped build from external stored inventory, legal reset of anatomy, anti-duplication and transactional inventory transfer. Do not prescribe what happens to other possessions without owner decision.
- **Tactics editor safety:** bounded priority tree / rule list with available conditions/actions, complexity/execution limits, deterministic fallback and logging/debug previews. Consider human-visible explanations of behavior and test-versus-training mode.
- **Ratings fairness:** ensure offensive and defensive participation have meaningful independent measures without incentivizing abusive farming of weak opponents or rewarding unbounded match volume. Outcome validation and matchmaking eligibility require future design.
- **Development priority:** current directional duel is a valuable foundation for future ghost AI. Study reusable intent/perception/capability contracts while improving the lab enemy, but do not turn the next milestone into backend or full ranked implementation without separate scope.

## Open owner decisions

1. **Ranked attacker avatar:** When playing offense, does the player directly control their **active frozen Echo** even though its gear/body were sacrificed in normal play? Or do they enter with their current live build and challenge the defending Echo?
2. **Sacrifice boundary:** Exactly what is lost on Imprint: equipped weapons and armor, all carried goods, body mods, skills/stats, all character progress? Do items left in storage remain untouched?
3. **Retired Echo eligibility:** Stats visible forever, but can retired builds still be challenged/viewed/replayed?
4. **Behavior edits:** Can owners change AI tactics anytime, including while an outstanding match is resolving? Should results pin a policy version at match creation?
5. **Scoring:** Are assault/defense values cumulative points, separate skill ratings, or both? How is rank calculated and are there seasons?
6. **Decision-tree expression:** Visual priority rules, hierarchical behavior trees or a constrained hybrid? What policy complexity/resource costs should be tradeoffs?
7. **Preserved character identity:** What survives a reset—account unlocks, learned recipes, currencies, global progression, or something else?
8. **Ghost challenge selection:** Matchmaking, opt-in queue, revenge/counter-challenges and farming limits remain undecided.

## Dependencies for later milestones

Shared anatomy/build capability resolver → legal player/AI combat intent + readable perception → behavior-policy evaluator + testing tools → immutable sacrifice transaction and reset semantics → persistent snapshot/policy records → fair asynchronous challenge execution, results and scoring → accessible tactics/leaderboard/history UX. None of these is claimed shipped.
