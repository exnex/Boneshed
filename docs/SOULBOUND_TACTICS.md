# Soulbound Tactics — soul-shaped programmable Echo behavior (design concept)

**Recorded:** 2026-10-20. **Feature/name status:** Proposed label only; owner has not selected a final name. **Scope:** owner-stated direction plus concrete design recommendations, explicitly separated. This is NOT an implemented feature and does not authorize replacing existing combat, online ranked systems or a final visual skill tree.

## Owner-confirmed direction

- Acquiring **a soul is a prerequisite to creating/submitting an Echo**. How souls are found, consumed, inventoried, traded or bound is still undecided.
- Souls have **different types** that establish the Echo's **initial AI temperament/default behavior**. Examples from owner: aggressive, defensive, balanced, with more possible types.
- Sacrificed build's items, skills, anatomy and capabilities shape the available **build-specific tactical nodes** and supply **points** for tactical investment; exact point calculation, sources, caps and anti-exploit balancing are undecided.
- Behavior customization is **limited by a point budget**; players invest to change default decisions and add conditional behaviors.
- The intended interface is a **modular, procedurally generated behavior/decision tree** driven by **soul + build**, with meaningful **cause-and-effect actions** and deep strategy, inspired in part by complex ARPG passive trees such as Path of Exile, but needing a more suitable logic representation.
- Earlier confirmed rules remain: one active Echo; sacrifice freezes the submitted build and resets the normal-world form; AI tactics may be changed after imprint but its frozen physical build may not; human pilots their own frozen Echo offensively, others face its AI defensively. Tower exam is optional and pre-imprint (five candidate opponents, three wins per opponent, three shared lives).

## Recommended model: Body + Soul + Mind

1. **Body (immutable after imprint):** resolved equipment, anatomy, item capabilities, skills, physical stats, grip rules, weapon handling. Generates available conditions/actions, synergy nodes and a bounded investment **capacity**.
2. **Soul (locked at imprint, if consumed/bound):** starting decision preferences/temperament, characteristic paths, perhaps unique rules or tradeoffs. Soul type must be materially different without being a simple linear power ranking.
3. **Mind (mutable after imprint):** a versioned, budget-limited policy graph, invested nodes/links/parameters, rule priorities and fallback. Validate every edit against frozen Body + Soul.

This is not a generic tree of passive buffs: points change **which observable situation leads to what legal combat intent**, not raw damage or secret perception. Separately track innate temperament and player override cost.

## Proposed procedural graph architecture

**Generate a deterministic graph from a canonical immutable seed** derived at imprint from soul identity/version + resolved build capability IDs + a persisted authored/random seed + generation rules version. Same ghost should retain the same tree topology throughout its lifetime (unless a separately approved policy migration occurs). Players must preview the generated tree **before irreversible submission**; randomness cannot obscure consequences of build decisions. Display what each item unlocks, blocks, grants and costs, including grip loss from anatomy changes.

Proposed typed nodes:
- **Observation/trigger:** readable enemy chamber, enemy weapon contact, own low posture, enemy outside preferred reach, recent whiff, observed guard side. Must be legally observed and timestamped; hidden button state/future releases excluded.
- **Condition:** distance band, posture threshold, opponent visibly recovering, line of sight, weapon ready, own recent history; boolean/finite comparisons.
- **Selector/priority:** ordered choices, fallback, limited weighted tie-resolution, interrupt precedence, wait/cooldown gates. Explicit owner-visible priorities.
- **Action:** approach, strafe, retreat, prepare chosen directional attack, release, raise/shift/lower guard, attempt timed defense, dodge, build-granted natural/skill attack. Every action is an input **intent**, resolved by ordinary combat legality.
- **Memory/sequence:** bounded short-lived observations, prior commitment, short combo/sequence, abandon after timeout/failure, cooldown; no hidden opponent intent or unlimited loops.
- **Link/synergy (optional):** connections to other nodes, conditional route, compact modifiers that alter trigger thresholds or behavior timing; avoid passive power inflation.

Architecture needn't be a literal runtime tree. Prefer a compiled finite acyclic/safely bounded **policy graph** with explicit priority, fallback and fixed-step evaluation; UI can present soul-rooted constellation/pathways. Reject invalid edges, recursive unbounded loops, unreachable rules and actions unavailable under the frozen build. Costs apply to unlocked behavior nodes, edges, priority slots or complexity bandwidth (precise economy TBD).

### Illustrative graph (not approved exact nodes)

`Sentinel soul → threat observed → [can block?] → align held guard → [enemy whiffs AND in greatsword reach?] → release prepared counter; else reposition`.

Different builds:
- Two-handed greatsword: wider reach/heavier braking enables counterspacing/big-hit rules but prevents off-hand shield logic.
- Shield + 1H weapon: coverage and guard-pressure routes, fewer grip-free options.
- Handless left Marrow Arm: shield tactics unavailable; only explicitly declared natural weapon/ability nodes are available, not automatically gained because it's a body mod.
- Light dagger: short-reach, evade/flank/punish options become prominent.

Different souls applied to the *same* physical build should open different viable starting patterns. Different physical builds with the *same* soul should generate notably different tactical opportunities.

## Balance and constraints (proposed)

- **Depth through opportunity cost**, not solely more points = better AI. Item/build-derived budget must be normalized/capped; powerful gear already grants combat power and shouldn't also grant strictly more universally useful tactics without a tradeoff. Offer multiple viable routes rather than always buying every best node.
- Some soul paths can be expensive to depart from, but avoid hard-locking viable defensive reactions; give every ghost safe legal fallbacks. No universally optimal 'brain' or mandatory type.
- Strategy comes from anticipation, conditional counters, specialization, timing, positioning, opponent adaptation to observable behavior and vulnerability tradeoffs. No omniscience, frame-perfect reflex from holding guard, private input access, guaranteed parry or action cancel outside legal window.
- The editor should show **why** a rule would run, what will happen if it cannot, budget spent/available, unreachable/exclusive path explanations, and a preview of simulated behavior before spending or committing.
- Tests should compare matched physical builds across different soul types and spend configurations; synthetic outcome metrics can inform balancing but cannot certify fun or infer real PvP fairness.
- For asynchronous competitive results, freeze/pin specific policy version at match creation; policy may be edited between matches without mutating snapshot identity. Version souls, generator, compiler and combat rules separately for historic replay.

## Preview and UX concept (proposed)

Three anchored regions on one canvas: **Soul core** (instinct), **Build branches** (generated from actual capabilities), **Decision pathways** (conditions, priorities, action outcomes). Make edge arrows show `WHEN / IF / THEN / ELSE`; avoid Path-of-Exile-like opaque sprawling geometry obscuring execution order. Separate projected behavior from merely-unlocked nodes. Tooltip names should express combat outcomes, not fake AI magic. Budget/cost changes visible before activation, and include a quick sparring simulator with annotated decisions.

Suggested provisional terms: **Soul**, **Temperament** or **Instinct**, **Tactic Points** or **Thought**, **Tactical Constellation** or **Mindweave**, **Doctrine** for the committed arrangement. The overall mode/Echo terminology remains undecided.

## Critical open questions to return to owner

1. Is **one soul consumed per Echo**, and are souls itemized/tradable? Is soul bound/frozen into Echo at imprint? Could acquiring a replacement soul change the current Echo's temperament without resubmission (conflicts with frozen build; recommend no)?
2. Can soul types change **point budget** or primarily initial topology/discounts/default habits? How is point capacity actually derived from build without rewarding the already-strongest builds twice?
3. Does 'procedural' imply deterministic graph generation tied to a soul+build, different random seeds for otherwise identical builds, or player-selected variants? Must preview and avoid post-imprint reroll exploits.
4. Is switching investments **free, paid, or limited** after submission? Earlier rule permits behavior edits; resource/time/competition restrictions unknown.
5. How much complexity should be visible at first vs expandable for advanced players? Priorities, rule groups, gating and explainability should be tested.
6. Are souls acquired in regular adventures, by defeating specific entities, via rare rewards or a mix? The chosen loop affects rarity, economy and build access.
7. What survives retiring a Ghost: completed soul, saved doctrine template, capability research, player unlocks?
8. How to score/build distinctiveness and protect ranked integrity when new soul/tactics versions release.

## Development impact — modify the planned next round carefully

Previously proposed Stage 1 **Claude game AI styles** and **Codex research policy contract** remain useful but must now use *soul temperament as configuration input* and *capability-conditioned policy intents* rather than presenting a universal editable generic priority list as the final Ghost design. Small bounded prototypes only. Stage 2 changes from flat tactics editor to **offline soul+build-generated tactical graph proof of concept** with preview and budget validation, before any major UI. Avoid full ARPG node atlas, world loot, ranked or backend implementation until owner tests design.

AI design target for next research: compare (a) identical equipment with aggressive vs defensive soul, (b) same soul with dagger vs two-hander, (c) same soul/build at different limited point allocations, while preserving visible cause→decision→legal action logs.

## Stamina-affordance addition — 2026-10-20

- Owner requires stamina-consuming attacks and dodge/roll actions whose costs depend on build; heavy weapons swing slower and cost more, light weapons can sustain weaker barrages, heavy armor reduces speed. See [STAMINA_AND_WEIGHT.md](STAMINA_AND_WEIGHT.md).
- Generated soul/build policy actions must pass the same **stamina affordability** checks as player actions. Potential investment decisions include conserving a dodge reserve, retreating to regenerate and choosing lower-cost swings. Exact stamina observation precision for opponent AI is undecided; no private exact stamina data without equivalent player-visible information.
- Tactic nodes should *choose* legal resource-constrained actions, not bypass physical stamina cost or grant fictitious max-stamina points absent explicit legitimate build capability. Include stamina consumption and failed-action reasons in policy test traces.
