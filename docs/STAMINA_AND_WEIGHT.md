# Stamina, encumbrance and weapon expenditure — design foundation

**Date:** 2026-10-20. **Status:** owner-confirmed direction with implementation/balance recommendations separated below. None of the numeric costs, regen rates, or equipment formulas are approved.

## Owner-confirmed combat rules

- **Stamina is required as a core combat resource.**
- Both **dodges and dodge rolls consume stamina**.
- Build composition can modify how much stamina different evasion actions cost.
- **Attacks consume stamina**; exact expense varies with build characteristics.
- **Heavy armor slows characters**.
- **Heavy weapons swing more slowly and use more stamina per attack**.
- **Light weapons can permit fast barrages / repeated swings**, each generally less impactful than heavy attacks.
- Different physical builds are intended to have tangible movement/attack efficiency tradeoffs. Shared player/NPC/Echo legal action rules should ultimately honor the same stamina expenditure.

## Recommended mechanical shape (not decided)

**Keep stamina distinct from posture.** Stamina expresses exertion and action affordability; posture expresses defensive structural stability and pressure. Never conflate stamina exhaustion with automatic guard break unless separately approved.

**Combat affordability:** Each action declares a stamina cost or cost curve based on weapon equipment, movement type, body modifications, armor encumbrance and derived build stats. Evaluate cost before an action legally begins, charge exactly once on the agreed action phase, and prevent duplicate charges caused by buffered inputs, release events, interruptions or networking retries. Handling balance/cancel refunds remains open. The current lab's indefinite held attack chamber and indefinite held guard must not be silently broken: do not impose an arbitrary hold timeout or unapproved per-second holding drain.

**Attack profiles:** Use real resolved equipment metadata (reach, length, mass, balance, grip) plus derived exertion handling; faster light weapons can chain low-cost, low-impact hits and heavy weapons hit harder/slower at a higher stamina price. Avoid equating raw weapon damage with weight alone; posture and armor interaction need tests. Attack cost could differ by light/heavy/charged/feint actions if those are later introduced, but current confirmed rule is that attacks cost stamina.

**Evasion profiles:** Distinguish dodge/step and dodge roll, configurable stamina costs, travel/recovery and legality. Heavy armor slows movement; possible extra dodge expenditure, movement acceleration penalty and other tradeoffs remain **proposed**, not locked. Body modifications or mobility build traits may reduce relevant evasion costs; avoid universally free/i-frame-spammable evasions.

**Resource recovery:** Max stamina, regeneration, start delay after expenditure, active guarding drain, attacking while exhausted, running/sprinting/walking costs, exhaustion effects, negative stamina, between-round restoration and UI indicators are **open**. Suggest consistent user-visible refusal/queue feedback if resources are insufficient, and a recovery cadence that preserves responsive controls.

**Combat balance:** Compare e.g. fast dagger (high swing frequency, small hits), ordinary one-handed sword, slow greatsword (big commitment and impact) at equal build budgets. Assess sustained DPS, damage per stamina, hit/deflection time, posture cost, mobility pressure and counterplay. Armor protection vs speed/cost should be meaningful, not punitive with no defensive gain.

## AI and ranked Echo implications

- Derived stamina affordability must be available to every fighter through the **same combat action legality**, not privileged AI conditions. Perception of opponent stamina should use only genuinely visible cues or disclosed UI rules; never secretly read hidden exact values if humans cannot.
- Soul temperament and point-invested tactical graph can contain budgeted rules that conserve stamina, press an apparently fatigued opponent, reserve an evasion, avoid repeated unaffordable attacks, retreat to recover, and choose lighter or heavier actions.
- The frozen Echo snapshot must include derived stamina parameters from immutable build equipment/anatomy. Behavior edits may change policy priorities, not physically increase base stamina without a valid build capability.
- Optional entrance exam's 5 opponent ×3 kills /3 lives structure depends on **unresolved stamina/HP/posture restoration** across each round. Do not invent a recovery schedule before owner approval.

## Proposed development priority

1. A **small, isolated stamina/encumbrance experiment in the current directional melee lab** before complex Echo policy implementation. Expose configurable player/opponent stamina and light/heavy armament differences, plus readable HUD and deterministic QA.
2. Validate the owner-approved hold-to-release interaction, dodge/guard cancels, and no unintended costs from held stances. Test budget, insufficient stamina, no double spending, light barrage vs heavy swing, armor movement slowdown, and build-modified evasion cost.
3. Add perception/AI intent awareness after core legality is exercised, then use its stamina/action affordances in soul-tactic graph research. First Expedition production combat remains unchanged without explicit approval.

## Outstanding design choices for owner

- What is the distinction between a **dodge/quick-step** and **roll** in control scheme, invulnerability, travel/recovery and cost?
- Should guarding or holding a prepared attack cost stamina over time? Not owner-stated; default prototype should not charge continuously until tested.
- Which armor weight factors affect base movement speed versus dodge cost, i-frames, regeneration and protection?
- Can someone attempt an attack with insufficient stamina (weakened, delayed or rejected)? What happens at zero, and how quickly does stamina recharge?
- Do transformed limbs, injuries, shields or body proportions introduce explicit stamina efficiency/maximum bonuses and drawbacks?
- How does stamina reset between rounds/opponents in the optional Tower Trial?
- Should feints/cancels commit full, partial or no stamina cost? Evaluate exploits and avoid spam while preserving the owner's responsive guard/dodge cancel rule.
