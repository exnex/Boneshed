# Melee lab combat resources — stamina, weight, status and resistance (experimental)

**Status: experimental prototype in the isolated directional melee lab. Every number, rule
and control below is Proposed for the owner's next browser playtest; nothing here is
Confirmed beyond the owner-confirmed directions it implements** (stamina is a core
resource; attacks, dodges and rolls cost build-dependent stamina; heavy armor slows;
heavy weapons swing slower and cost more; light weapons allow fast, weaker barrages;
equipment can carry elemental/status properties; resistance versus evasion matters —
[STAMINA_AND_WEIGHT.md](STAMINA_AND_WEIGHT.md),
[ELEMENTAL_STATUS_FOUNDATION.md](ELEMENTAL_STATUS_FOUNDATION.md)).
First Expedition, the default scene, production combat, the shared build catalog and the
Pages root are unchanged. Engine: Godot **4.7.2.stable.official.ed1daf0bf**.
Built 2026-10-21 on top of [the directional melee lab](DIRECTIONAL_MELEE_LAB.md).

Poison and slow are **representative examples chosen for pipeline coverage, not an
approved status roster or element taxonomy.** Stun, freeze and paralysis are not
implemented; the effect validator rejects any kind other than damage-over-time and
bounded impairment.

| Section | |
| --- | --- |
| [1. What changed for the player](#1-what-changed-for-the-player) | Controls, HUD, profiles |
| [2. Stamina rules](#2-stamina-rules) | Charge points, refusals, recovery, feints |
| [3. Equipment, weight and mobility](#3-equipment-weight-and-mobility) | Formulas, the three profiles, measured differences |
| [4. Status pipeline](#4-status-pipeline) | Stages, routing table, poison and slow |
| [5. Shared legality and AI](#5-shared-legality-and-ai) | Same rules for both fighters, Echo seam |
| [6. Data schemas and tunables](#6-data-schemas-and-tunables) | Every new value and file |
| [7. Tests and evidence](#7-tests-and-evidence) | Commands, results, clips |
| [8. Known problems and deferred mechanics](#8-known-problems-and-deferred-mechanics) | |
| [9. Browser playtest](#9-browser-playtest) | Checklist |
| [10. Recommended next step](#10-recommended-next-step) | |

## 1. What changed for the player

All existing controls are unchanged: LMB hold chambers indefinitely, LMB release swings,
RMB hold keeps the directional guard, a fresh RMB press deflects and cancels, mouse
direction picks attack and guard sides, Space dodges and cancels.

| New input | Action |
| --- | --- |
| **Shift** | **Dodge roll** (new, experimental). Space keeps the existing quick dodge step for comparison |
| `[` `]` · `,` `.` | Cycle your / the opponent's **build** (now including the three profiles below; the original unarmored weapon loadouts stay in the cycle) |
| **V** | Toggle the *toxic miasma* world condition (ambient poison buildup on both fighters) |

| HUD element | Meaning |
| --- | --- |
| Green bar under health/posture | Stamina. Tick marks show *your build's* costs: white = attack, blue = dodge, violet = roll |
| Bar flashes red + `NOT ENOUGH STAMINA: attack needs 27, have 12` | An action was refused (nothing happened, nothing was charged) |
| Small coloured bars `poison`, `slow` (+ `res 60%`) | Status buildup toward its threshold and the fighter's resistance |
| `POISON 4.2s` / `SLOW 2.1s` / `slow immune 1.5s` | Active effect with time left / post-expiry immunity |
| Label over a fighter: `POISONED`, `SLOWED`, `EXHAUSTED`, `NO STAMINA`, `ROLL`, `ROLL · open` | Visible state; `ROLL · open` = the roll's vulnerable tail. Body tint: green = poisoned, blue = slowed |
| Line under the title: `Build: … armor 9.0 kg · move 4.90 m/s · attack 13.4 · dodge 20.3 · roll 33.0 · regen 25.5/s · mitigation 15%` | Your build's numbers |
| **F2** table | Handling of both weapons plus a build comparison row per fighter: armor mass, current move speed, attack/dodge/roll cost, regen, mitigation, poison/slow resistance, on-hit sources |

Both fighters' stamina bars and status displays are visible. That is a **disclosed UI rule
chosen for the playtest**; whether an opponent's exact stamina should be visible in
production is open. The lab AI does not read either (§5).

The lab now starts with the **Balanced** profile for both fighters. The original
unarmored *Notched Sword* loadout is one `[` away and moves exactly as before.

## 2. Stamina rules

Owned by [`stamina_pool.gd`](../scripts/melee_lab/stamina_pool.gd) (the pool) and
[`duelist_state.gd`](../scripts/melee_lab/duelist_state.gd) (when to charge). Rendering,
input and AI never change stamina.

| Rule | Behaviour |
| --- | --- |
| **Affordable** | `stamina ≥ cost`. An exact match is affordable and leaves 0 |
| **Unaffordable** | Refused: the action does not start, nothing is charged, `last_refusal` records action/cost/stamina, the HUD shows it. Never partial, never queued, never "weakened" |
| **Attack charge point** | Once, when the windup legally starts. A buffered attack (pressed during recovery) is charged when the buffer becomes a windup; an expired or cleared buffer costs nothing |
| **What never charges** | Release events, repeated presses during a windup, redirecting the chamber, holding the chamber, holding the guard, guarding, blocking, deflecting |
| **Dodge / roll charge point** | Once, when the evasion starts. The shared cooldown prevents chains |
| **Feint refund** | A *voluntary* cancel of an **unreleased** windup (fresh guard press, dodge, roll) refunds `feint_refund` (50 %) of the attack's cost. When a dodge/roll cancels an unreleased windup, the refund counts toward that evasion's affordability |
| **No refund** | Cancelling after release (released windup, swing, recovery), and interruptions (hit stagger, guard break, death) |
| **Recovery** | `regen` per second, starting `stamina_regen_delay` (0.6 s) after the last charge, or `stamina_empty_regen_delay` (1.2 s) if that charge emptied the pool. Capped at capacity |
| **Holding** | The held chamber and the held guard neither drain stamina nor slow recovery. Two scales (`stamina_regen_hold_scale`, `stamina_regen_guard_scale`) exist so the owner can try it, but both default to 1.0 (no effect) because neither is approved |
| **Exhaustion** | Only the longer recovery delay after emptying. Guard, block and deflect stay available at 0 stamina (tested). Stamina is not posture: running out never breaks the guard |

Why charge at windup start rather than at release: charging at release would make
press-then-guard-cancel free, i.e. unlimited free feints. Charging up front and refunding
half on an unreleased cancel makes every feint cost something (measured: back-to-back
windup→guard cancels with no rest run dry after 36 feints and are then refused), while a
held chamber is never drained and the guard/dodge cancels stay instant.

The only new decision the player faces at the moment of input is affordability; there is
no added input delay. The opening cut, follow-ups, buffer, redirect and cancel timings are
those of the existing lab (its 86 checks pass unchanged).

## 3. Equipment, weight and mobility

Every cost below comes from equipped items through one function,
`combat_resources.gd::derive(handling, striking_item, armor_ids, data, tuning)`: the
weapon's *derived inertia* from the existing handling model (length, mass, balance,
grip), the summed **armor mass**, and armor/trait data. There are no class bonuses; two
fighters with the same equipment get identical numbers whatever their role (tested).

```
attack_cost   = attack_cost_base + attack_cost_per_inertia · I + attack_cost_per_armor_kg · armor_kg
dodge_cost    = dodge_cost · (1 + evasion_cost_per_armor_kg · armor_kg)        (roll likewise)
move_scale    = max(armor_min_move_scale, 1 − armor_move_penalty_per_kg · armor_kg)
evasion_speed = max(armor_min_move_scale, 1 − armor_evasion_speed_penalty_per_kg · armor_kg)
regen         = stamina_regen · max(0.25, 1 − armor_regen_penalty_per_kg · armor_kg)
mitigation    = 1 − Π(1 − armor.mitigation)        (≤ 0.75; physical damage only)
resistance[e] = 1 − Π(1 − armor.resistances[e])    (≤ 0.9; scales buildup)
```

Swing speed, momentum, damage and guard strength are unchanged: they already come from
the weapon physics (heavier weapons accelerate and recover more slowly and hit harder).

| Profile | Weapon (inertia) | Armor | Attack | Dodge | Roll | Regen | Move | Mitig. | Resist P/S | On-hit source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Evasive** | Venom Knife (0.73 kg·m²) | Cloth wraps 2.5 kg | 7.8 | 17.2 | 28.0 | 27.3/s | ×0.97 | 5 % | 0 / 0 % | poison 35 |
| **Balanced** | Notched Sword (2.13) | Mail shirt 9 kg | 13.4 | 20.3 | 33.0 | 25.5/s | ×0.89 | 15 % | 25 / 25 % | — |
| **Resistant** | Greatsword (5.63) | Bog-iron plate 20 kg | 26.7 | 25.6 | 41.6 | 22.4/s | ×0.76 | 30 % | 60 / 60 % | slow 55 |
| Sword (unarmored, original) | Notched Sword | — | 12.4 | 16.0 | 26.0 | 28.0/s | ×1.00 | 0 % | 0 / 0 % | — |

Capacity is 100 for everyone (no stamina stat exists in the shared catalog; see §6).

Measured in the deterministic suite ([evidence](evidence/melee-lab-combat-resources/README.md)):

| Measurement | Evasive | Balanced | Resistant |
| --- | --- | --- | --- |
| Cuts in 10 s, chaining as fast as allowed, from full | **15** (never ran dry) | 12 (dry at 7.3 s) | **8** (dry at 3.3 s) |
| One clean cut on an unarmored target | 11.5 dmg | 19.7 | **32.1** |
| Damage per stamina of that cut | 1.48 | 1.48 | 1.20 |
| The same sword cut received | 18.7 dmg | 16.8 | 13.8 |
| Walk distance in 1 s (unarmored sword: 5.07 m) | 4.93 m | 4.57 m | 3.94 m |
| Dodge step travel / roll travel | 2.10 / 4.02 m | 2.00 / 3.73 m | 1.79 / 3.23 m |
| Venom-knife hits until poisoned (≈1 s apart) | — | — | 10 (unarmored: 4) |

**Dodge step vs dodge roll (both experimental).** The existing step is unchanged:
0.3 s, fully invulnerable, 0.65 s cooldown. The roll (Shift) lasts 0.6 s at 8 m/s:
invulnerable for its first 0.3 s, then a vulnerable 0.3 s tail (`ROLL · open`; a hit
there lands and applies status — tested), 0.8 s cooldown, about 1.6× the step's stamina.
It buys distance (≈1.9× the step) for stamina and a punishable tail. Armor weight raises
both costs and shortens both distances; it never grants or removes invulnerability time
(no blanket i-frames by weight).

## 4. Status pipeline

```
contact_solver.resolve ──► 1 physical outcome + damage × (1 − mitigation)
                          2 routing: attacker's on-hit sources × routing[outcome]
duelist_state.receive_status ──► 3 resistance: × (1 − resistance[effect])
status_effects.add_buildup   ──► 4 buildup → threshold → activation (or refresh/ignore)
status_effects.tick          ──► 5 duration, periodic ticks / impairment scales
                                 6 expiry (+ immunity window)
lab_hud / lab_visual         ──► 7 bars, timers, labels, tint (read-only)
world condition (arena)      ──► ambient buildup per second → 3…7 (no routing: not a hit)
```

**Sources** are data, attached to equipment: `traits[<catalog item id>].status_sources`
for the *striking* item (a held weapon now; a natural-weapon body mod would use the same
key), armor supplies resistances, and `world_conditions[]` supply ambient sources.

**Routing table** (`combat_resources.json → routing`, validated):

| Outcome | Scale | Why |
| --- | --- | --- |
| hit | 1.0 | Body contact |
| misaligned (bad angle) | 0.5 | The blade slid off the guard into the body for half damage; half buildup |
| block, deflect | 0 | The weapon stopped it before the body |
| guard_break | 0 | The guard collapsed but the blow did not reach the body; the follow-up hit applies normally |
| clash | 0 | Blades only |
| evaded (dodge/roll i-frames) | **0, enforced** | Data validation rejects anything else, and the code ignores it anyway |
| miss (no contact) | — | Produces no contact, so nothing is routed |
| world condition | — | Not routed: ambient, not avoidable by evading, still resisted by armor |

**Poison** (damage over time): threshold 100, buildup decays 6/s while inactive, 6 s
duration, 3 damage every 1 s (6 ticks = 18 total, identical at 30/60/120 Hz), cannot kill
(stops at 1 health; `can_kill` flag), re-reaching the threshold while active *refreshes*
the duration without stacking. Ignores armor mitigation (it was already resisted at
buildup).

**Slow** (bounded impairment): threshold 100, decays 10/s, 3 s, locomotion and dodge/roll
travel ×0.65, handling ×0.8 (swing acceleration, braking, guard shift, turn rate and
thrust acceleration; the hand-speed cap, deflect window and timings are untouched),
no buildup while active, then 2 s immunity so it cannot be chained. Handling is restored
exactly on expiry (tested). Measured: a slowed sword cut reaches contact 0.47 s vs
0.45 s — the slow is felt mostly in movement, guard shifts and turning, not swing speed.

**Resistance vs evasion.** The evasive build cannot resist anything (cloth: 0 %) but
pays the least for dodges and rolls and moves fastest; the resistant build needs ~2.5×
the venom hits to be poisoned, mitigates 30 % physical damage and shrugs off the miasma
(its resisted ambient rate is below poison's decay), but moves 24 % slower and pays 50 %
more per evasion.

## 5. Shared legality and AI

- Player and lab opponent use the same `duelist_state.gd`, the same `derive`, the same
  stamina pool and status runtime. Identical builds driven through the same action
  sequence produce byte-identical charge/refusal logs (tested).
- `state.legal_actions()` reports what is legal *right now* with this build's real costs:
  `attack`, `dodge`, `roll` (affordability, phase, cooldown, feint refund) and `guard`.
  It never promises an attack that would then be refused (tested over 300 ticks).
- `state.self_view()` gives a fighter its *own* stamina, health, posture, statuses and
  legal actions — the seam a future Echo policy needs. It is self-knowledge only.
- **Lab opponent** ([`lab_opponent.gd`](../scripts/melee_lab/lab_opponent.gd)): asks
  `legal_actions()` before pressing and keeps a reserve (`ai_stamina_margin`, 6); below
  cost + margin it logs `conserve`, backs off by `ai_recover_spacing` (1.2 m) and resumes
  (`recovered`) once regenerated. With regeneration starved to 3/s it made 5 attacks in
  20 s with **0 refused attempts**. When *it* is slowed it keeps `ai_slowed_spacing`
  (0.4 m) more distance and waits ×1.5 longer between attacks (measured: 5 vs 7 attacks
  in 8 s, mean spacing 2.6 vs 2.2 m). It still sees only the player's drawn cues after
  its reaction delay; a test fails if its source reads the player's stamina, status or
  resources. It still never dodges or rolls (deliberately deferred).

## 6. Data schemas and tunables

**Files**

| File | Schema | Holds |
| --- | --- | --- |
| [`data/melee_lab/combat_resources.json`](../data/melee_lab/combat_resources.json) | `boneshed.melee_lab_combat_resources.v0` | `effects`, `routing`, `armor[]`, `traits{item id}`, `world_conditions[]` |
| [`data/melee_lab/weapons.json`](../data/melee_lab/weapons.json) | `boneshed.melee_lab_weapons.v0` (extended) | New `item.lab_venom_knife`; loadouts may now list `armor: [ids]`; three profile loadouts |
| [`data/melee_lab/tuning.json`](../data/melee_lab/tuning.json) | `boneshed.melee_lab_tuning.v0` | The numbers below |

```jsonc
// effects.<id>
{"kind": "damage_over_time" | "impairment", "label", "color",
 "threshold", "decay_per_second", "duration", "immunity_after",      // ≥ 0; threshold, duration > 0
 "while_active": "refresh" | "ignore",
 // damage_over_time: "tick_interval" (> 0), "tick_damage", "can_kill" (bool)
 // impairment:       "move_scale", "handling_scale" (both in (0, 1]: no hard control)
}
// armor[]
{"id": "armor.*", "name", "slot", "mass" (kg ≥ 0), "mitigation" (0..0.75),
 "resistances": {"<effect>": 0..0.9}}                 // 1.0 (immunity) is rejected
// traits.<catalog item id>  (must exist in the combined catalog)
{"element": "", "status_sources": [{"effect", "route": "on_hit", "buildup" (> 0)}]}
// world_conditions[]
{"id": "world.*", "label", "status_sources": [{"effect", "route": "ambient", "buildup_per_second" (> 0)}]}
// routing: one 0..1 scale per contact outcome; "evaded" must be 0
```

Validation runs inside the existing lab adapter (`lab_loadout.gd`) after the shared
catalog validation; loadout armor ids must exist and occupy distinct slots.

**Schema gap (documented, not redesigned).** The shared build catalog
(`boneshed.build_catalog.v1`) has no armor category or armor slots, no element/status
fields on items, no stamina capacity/regen stats and no resistances. Its strict key
validation means those fields cannot be added to lab items without changing
`scripts/builds/`. The lab therefore keeps them in a sidecar keyed by catalog item ids and
resolves armor *beside* `BuildRules.resolve`. Promoting armor/traits/stamina into the
shared catalog is a production design task for the coordinator.

**New tuning values** (all provisional; restart the scene after editing):

| Key | Default | Meaning |
| --- | --- | --- |
| `stamina_max` | 100 | Capacity (everyone) |
| `stamina_regen` | 28 /s | Recovery rate before armor |
| `stamina_regen_delay` / `stamina_empty_regen_delay` | 0.6 s / 1.2 s | Delay after a charge / after emptying |
| `stamina_regen_hold_scale` / `stamina_regen_guard_scale` | 1.0 / 1.0 | Recovery × while holding a chamber / guarding (1 = no effect; unapproved to change) |
| `attack_cost_base`, `attack_cost_per_inertia`, `attack_cost_per_armor_kg` | 5, 3.5 /kg·m², 0.1 /kg | Attack cost |
| `feint_refund` | 0.5 | Refund fraction for a voluntary cancel of an unreleased windup |
| `dodge_cost`, `roll_cost` | 16, 26 | Base evasion costs |
| `evasion_cost_per_armor_kg` | 0.03 | Evasion cost × (1 + this · kg) |
| `armor_move_penalty_per_kg`, `armor_evasion_speed_penalty_per_kg`, `armor_min_move_scale` | 0.012, 0.012, 0.6 | Mobility |
| `armor_regen_penalty_per_kg` | 0.01 | Recovery × (1 − this · kg), ≥ 0.25 |
| `roll_duration`, `roll_invulnerable`, `roll_speed`, `roll_cooldown` | 0.6 s, 0.3 s, 8 m/s, 0.8 s | Dodge roll |
| `ai_stamina_margin`, `ai_recover_spacing` | 6, 1.2 m | AI reserve and back-off |
| `ai_slowed_spacing`, `ai_slowed_cooldown_scale` | 0.4 m, ×1.5 | AI reaction to its own slow |

## 7. Tests and evidence

```sh
bash scripts/tooling/setup.sh          # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/test_melee_lab.sh # ≈ 6 min on the cloud image (llvmpipe)
```

The runner parse-checks every lab script, runs the original **86 checks** and the new
**73 resource checks** ([`melee_lab_resources_tests.gd`](../scripts/qa/melee_lab_resources_tests.gd)),
each twice in separate processes with byte-identical `results.json`, four negative
controls that must fail their named checks (`no-substeps`, `omniscient`, and new:
`free-feints` → `feint_spam_is_bounded_by_stamina`; `block-applies-status` →
`blocked_attack_applies_no_status`), renders **23 clips** (9 new) that each assert their
outcome, and fails if the branch touched protected production/coordination files.

Resource check groups: data load, validation and schema rejection (4), costs by build (8),
affordability at full/exact/just-below/low, repeated refusals and free defence at zero (4),
single charging under repeated presses/releases/redirects, stray releases, buffering,
same-moment evasions and 30/60/120 Hz (6), recovery delay/rate/cap, empty delay, no drain
while holding a chamber or guard (5), feint refund/no-refund/interrupt/boundary/spam (5),
light vs heavy economy and armor mitigation (4), poison/slow lifecycle, tick-rate
independence, refresh, resistance, decay, immunity, world condition (11), routing for
hit/bad angle/block/deflect/dodge/roll/roll tail/miss/clash/guard break (11), shared
legality (2), real scene: default profile, measured walking and evasion travel, real
clicks and keys, refused click keeps the camera, arena status log (8), AI stamina,
recovery, own-slow reaction, no reads of player resources, replay (5).

Evidence: [`docs/evidence/melee-lab-combat-resources/`](evidence/melee-lab-combat-resources/README.md).

## 8. Known problems and deferred mechanics

- **No human has played this.** Nothing here shows that stamina feels good, that the
  numbers are fair, or that the roll is worth having next to the step.
- Refusal is strict. A player who presses LMB with too little stamina gets nothing until
  pressing again (no queued attack, no weak attack). This is the most likely thing to feel
  bad; alternatives (queue until affordable, weakened attack, allow negative) are open.
- A held chamber was already paid for, so holding it while stamina recovers is free and
  neutral; a held chamber cannot be "upgraded". Redirects are free.
- Slow's handling impairment barely changes swing timing (speed cap dominates).
- Poison can't kill (a placeholder safeguard) and ignores mitigation; burn/elements
  interplay, cleansing, partial immunity and diminishing returns are not implemented.
- Only the striking weapon's traits apply on hit; armor/body on-hit or reactive sources,
  elemental damage channels, penetration and vulnerability are not modelled.
- The AI does not dodge, roll, feint, read the player's stamina or exploit statuses; it
  only stays legal and conserves. That is the next milestone's seam, not done here.
- Blocking costs posture, not stamina; deflects cost nothing. Untested whether that is
  enough pressure on turtling.
- Between-round restoration: `R` resets everything. Tower/round rules are not touched.
- Stun, freeze and paralysis: not implemented, rejected by validation.

## 9. Browser playtest

URL after merge and deployment: <https://exnex.github.io/Boneshed/melee-lab/> (click the
canvas to capture the mouse; Esc frees it).

1. **Feel check first.** With the default Balanced build, hold LMB for several seconds:
   does the chamber still hold indefinitely with the stamina bar *not* draining? Hold RMB:
   same? Tap-chain cuts, guard-cancel, dodge-cancel: anything later or heavier than before?
   Press `[` until *Notched Sword (1H)* to compare with the original unarmored sword.
2. **Stamina.** Chain cuts into the dummy (M → dummy) until the bar runs out. Is the red
   refusal readable? Does the recovery delay feel fair or sluggish?
3. **Builds.** Try *Evasive*, *Balanced* and *Resistant* (`[` `]`, numbers on the HUD
   line and F2). Is the speed/cost/impact difference obvious within a minute? Is the
   greatsword build fun or just slow?
4. **Dodge vs roll.** Space vs Shift. Is the roll worth its cost and its open tail?
   Is Shift a comfortable key?
5. **Statuses.** As Evasive, poison the dummy (watch its poison bar fill, then
   `POISONED` ticks). As Resistant, slow it. Set the opponent to Evasive (`.`) in attack
   mode and dodge its venom cuts: nothing should build up. Block them: nothing either.
6. **Resistance vs evasion.** Duel (M → duel) as Evasive against a Resistant opponent and
   the reverse. Is each build plausibly viable?
7. **Miasma (V).** Is an environmental source understandable next to on-hit sources?
8. **AI.** Does the opponent ever look like it cheats stamina, or stall stupidly when
   tired? Does it read as backing off to recover?
9. Note any number you want changed (costs, regen, delay, feint refund, roll i-frames).

## 10. Recommended next step

**Resource-aware lab AI intents (Stage 1 continuation):** give the lab opponent a small,
data-configured intent layer over `legal_actions()`/`self_view()` — choose light vs heavy
commitment by its own stamina, reserve an evasion, retreat to recover, and a legal dodge
or roll reaction to drawn telegraphs after the same reaction delay — with 2–3 profiles
treated as sample soul temperaments, and only *visible* opponent cues (exhaustion label,
status tint) as perception. Gate it on the owner's playtest of this milestone's numbers.
