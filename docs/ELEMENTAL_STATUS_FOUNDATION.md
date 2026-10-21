# Elemental properties, status effects, resistances and evasion

**Recorded:** 2026-10-20. **Status:** owner-confirmed design direction. Example system structure below is proposed, not final balancing, element taxonomy or status rule approval. Coordinate with [stamina and weight](STAMINA_AND_WEIGHT.md), [soul-driven tactics](SOULBOUND_TACTICS.md) and [asynchronous ranked Echoes](ASYNC_RANKED_GHOSTS.md).

## Owner-confirmed vision
- Procedurally generated worlds have elemental types/conditions, as previously agreed in the three-keyword world system.
- **Armor, weapons and body modifications** can also have elemental properties and effects.
- Gear and modifications can inflict and/or interact with **status effects** including **poison, burn, stun, freeze, slow and paralysis**; the list is illustrative and may expand.
- **Resistances are strategically important**, including decisions between protective and evasive builds.
- A particularly light build may favor avoiding hits entirely instead of obtaining broad resistances.
- Complex interactions between status, equipment, physical movement, stamina and build composition are a planned source of build diversity. Player, NPC, Echo and optional Tower opponents must ultimately obey a consistent combat rulebook.

## Proposed system separation
1. **Elemental traits:** typed sources/defenses from keyword world conditions and resolved gear/anatomy. Do not assume each status maps one-to-one to a damage element. Some ailments may be physical, toxic, environmental or supernatural.
2. **Hit/contact and avoidance:** determine valid collision, guard/deflect/dodge outcome and whether an effect is permitted to apply **before** status calculation. Dodged attacks do not apply on-hit status unless a separately authored area/environmental mechanic applies; strong avoidance thus has meaningful identity.
3. **Damage/resistance:** physical/elemental channels with consistent ordered mitigation and bounded, understandable resistance. Specify penetration/vulnerability/stacking only after tests.
4. **Status application:** per-effect typed application, build-derived resistances, buildup, threshold, duration and immunity/recovery semantics. Avoid arbitrary stuns and paralysis that leave player helpless or inescapably chained. Statuses may have distinct rules; keep source attribution and reproducible logs.
5. **Status runtime:** independent deterministic update/lifecycle in shared combat math. Poison/burn as damage-over-time candidates; slow as movement/handling modifier; freeze/paralysis/stun as carefully constrained loss/impairment of actions. Exact distinctions are unresolved, not equivalently strong by definition.
6. **Cleansing/counters:** item/body/soul tactics may provide defensive options if physically available, but no particular cleanse mechanic is confirmed.
7. **Stamina/weight:** heavy armor protection versus slow movement and expenditure; light equipment enables mobility but exposure to ailments if struck. High resistance must have opportunity costs versus pure evasion. Stamina-affordability remains mandatory for attacks/dodges/rolls.

## Minimal prototype recommendation, not final roster
- Stage first in **isolated directional melee lab**, not default First Expedition: a small data-driven effects pipeline with 2 representative status examples (e.g. poison buildup/periodic harm and slow debuff) and 1 elemental equipment/environmental trait. Include one armor resistance variant and an evasive light profile. The examples are placeholders chosen for coverage; do not interpret as locking poison or slow as first production effects.
- Do not implement stun, paralysis and freeze as hard controls in first narrow pass. Document their distinct intended semantics, resistance/DR, interaction with stamina, PvE/PvP fairness and safeguards in research. Prototype only after non-disabling effects are mechanically validated.
- Reuse existing resolved equipment/build system and weapon handling rather than adding disconnected global perks. Author test fixtures/lab-only catalog entries with clear versioned schemas.
- Evaluate a **heavy resistant build** versus **light evasion build**, preserving player-held attack/guard input, existing stamina commitment/dodge timing rules and readable directional telegraphs. Ensure both are plausibly viable in distinct matchups.
- Status rules must be deterministic from authoritative events and explicit seeds if chance is involved, reproducible in headless fixtures at different physics ticks, and render clear telegraph/state/UI and explainable outcomes. No secret AI immunity, impossible one-hit chain stun or free status effects from missed swings.
- Test buildup/resistance, duration refresh/stacking policy, periodic effect clocks, immunity windows where applicable, mitigation order, dodge/deflect routing, error cases and recoverability. Exact numerical values remain provisional.

## Echo Tactics and Tower implications
- Frozen Echo Build carries equipment elements, status application sources, resistances, stamina/weight/mobility profile and legal counter-actions. The **soul** supplies initial AI temperament; budgeted tactics graph can choose when to pressure with ailments, avoid known hazard sources, manage stamina, protect weak resistances or evade rather than tank damage.
- Ability to observe an opponent's resistances/status must use public/visible information or uncertain learned inference; no perfect AI awareness of hidden exact resistance values.
- Procedurally generated tactical nodes depend on *actual* elemental and status capabilities: e.g. 'retreat while poisoned', 'apply toxin when weapon contact is legal', 'reposition outside an observed burn zone', not simply arbitrary damage multipliers.
- Optional pre-imprint Tower Exam should eventually expose at least some elemental/status matchups, and no unsupported free restoration between trials should be assumed. Do not implement it now.

## Open design choices
- Official **element taxonomy**, world environmental hazards, interaction table and status names.
- Status-specific buildup vs instant proc, stacking, cleanse, dispel, partial resistance, immunity, duration, diminishing returns.
- Which actions apply effects (on-hit, on-block, on-deflect, aura, environment, natural weapon), how damage and status interact.
- Whether stamina regeneration/maximum is affected by slow/freeze/poison and how exhaustion and debuffs combine.
- Whether light armor grants actual extra i-frames, or simply better speed, dodge travel and lower stamina costs. Avoid granting blanket invulnerability by weight alone.
- Heavy armor protective stats and opportunity costs; armor durability, elemental conversion and cross-element counters.
- Element/environmental progression rewards and content gating, exact status visibility to opponent AI, and ranked metagame limits.
