# Combat prototype — independent review and adversarial playtest

Reviewer: Claude (Claude Code), 2026-10-16. Subject: the Milestone 1 courtyard duel merged in
PR #2 (`4a15514`). Engine: Godot **4.7.2.stable.official.ed1daf0bf**. The official archive
was verified against the release SHA-512 manifest and the pinned hash. Linux x86_64 cloud
container, Xvfb + Mesa llvmpipe (LLVM 20.1.2), GL Compatibility.

This review is automated and adversarial. It measures what the rules and AI do. It does
**not** establish that the duel is fun, and nothing here replaces human playtesting at
desktop frame rates. The user's own report ("plays okay, combat very rudimentary") fits
the measurements: the systems work, but they are shallow and several are exploitable.

Labels follow `AGENTS.md`. **Bug** means objectively incorrect or inconsistent with the
documented rule. **Exploit** means a reproducible dominant strategy. **Design** means a
subjective proposal. All tuning values remain provisional.

---

## 1. Summary

**Correctness.** The core rule engine is sound. Phase timing is independent of step size.
One hit is allowed per swing. Hit validation is real (oriented box plus physics ray).
Reset is robust in every state tried, and output is deterministic: all five rendered
checkpoints are byte-identical to Codex's evidence. I found and fixed **three
correctness bugs**, all in hit-stagger and movement integration.

**Combat quality.** The duel cannot yet support a skill-expression claim. Five different
strategies that ignore the intended deflect-and-punish loop beat the swordsman at full
health. Two need no reading of telegraphs at all:

| Strategy (live AI, scripted input) | Result | Player HP | Time |
| --- | --- | --- | --- |
| **Mash attack, never defend** | Win. All 6 enemy attacks were interrupted in windup | **100** | 7.1 s |
| **Toggle guard 9 ticks on / 1 off, attack when broken** | Win, with no timing knowledge | **100** | 11.8 s |
| Sidestep during windup, then punish | Win. 0 of 6 enemy attacks connected | 100 | 14.6 s |
| Backstep during windup, then punish | Win | 100 | 15.5 s |
| Codex's deflect bot (reference) | Win | 100 | 5.6 s |
| Hold guard forever | Loss (guard broken after 4 blocks) | 0 | 24.8 s |
| Stand still | Loss | 0 | 11.1 s |
| Dodge whenever ready, no attacks | Loss (3 evades, 4 hits) | 0 | 20.2 s |

Passive play correctly loses. Aggressive play with no defence wins most easily, and
that inverts the Sekiro-inspired goal. The root causes are structural, not tuning noise
(Section 5).

## 2. Reproduction of Codex's results

Run on unmodified `main` code (`docs/evidence/combat-review/baseline/`):

| Check | Codex reported | Reproduced |
| --- | --- | --- |
| Headless import | exit 0 | exit 0 |
| Combat assertions | 30 pass, 0 fail | **30 / 0** |
| Graphical/input assertions | 35 pass, 0 fail | **35 / 0** |
| Negative: guard | exit 1, 3 failed | exit 1. `guard_mitigates_damage`, `broken_target_takes_double_damage`, `break_recovers` |
| Negative: deflect | exit 1, 2 failed | exit 1. `timed_deflection`, `deflection_pressures_attacker` |
| Negative: phase | exit 1, 3 failed | exit 1. `windup_cannot_damage`, `active_damage`, `one_hit_per_swing` |
| Rendered checkpoints | 5 | 5. **Byte-identical PNGs** (MD5 in the evidence README) |
| Scripted win length | 334 frames | 334 frames |
| Engine warnings | VSync unsupported under Xvfb | Same single warning. No `ERROR` lines |

I inspected all five screenshots against their frozen state records. They agree with
the rules state (phase, HP, posture). The `02_enemy_windup` capture also shows a framing
problem (Section 4.5): the player's body covers most of the enemy and its windup box.

**Coverage gaps in the original suites.** Neither suite exercises: hits during
recovery, simultaneous attacks, attack facing while locked, dodge after movement,
guard spam, guard from behind, AI pathing, or any adversarial win condition. The
negative controls show that the assertions can fail. They do not show that the
assertions cover the risky paths.

## 3. Bugs fixed in this branch

Each fix has a regression test. The test **failed on the original code** and passes after
the fix. Logs are in `docs/evidence/combat-review/before-fix/` and `after-fix/`.

### 3.1 A hit shortened the target's recovery (rules)

`CombatState.receive` always set an unguarded, non-broken target to `STAGGER` for
0.24 s. A target hit early in its 0.65 s recovery therefore became actionable *sooner*
than if it had been left alone. Measured in the scene: an enemy that whiffed was locked
out for 39 ticks, but only **17 ticks when the player punished it**. Punishing a whiff
rewarded the whiffer. The same happened with a hit during the 0.35 s deflection stagger.

Fix: the hit-stagger lasts `max(0.24, remaining lockout)` when the target is already
in `RECOVERY` or `STAGGER`. A hit from `IDLE` or during windup is unchanged (0.24 s).
Tests: `hit_does_not_shorten_recovery` and `hit_does_not_shorten_stagger` (both failed
before), plus `idle_hit_stagger_unchanged` (guards existing behavior).

### 3.2 Dodge distance and direction depended on prior movement (fighter)

The dodge accelerates at 32 u/s² from the *current* velocity. A dodge opposite to a run
had to cancel 5.5 u/s first. Measured in the scene, through action input:

| Case | Travel along dodge axis during i-frames (before → after) |
| --- | --- |
| From standstill | 1.66 m → 1.66 m (unchanged) |
| **Back-dodge out of a forward run** | **0.45 m → 1.67 m** |
| Side-dodge out of a forward run | 2.12 m along, with **0.94 m drift toward the run direction** → 1.67 m, no drift |

The dodge is the player's emergency tool, so a 73% distance loss that depends on
history is a reliability bug. Fix: at dodge start, keep only the velocity component
that points along the dodge direction. Forward dodges out of a run keep their momentum
(as before). Standstill dodges are bit-for-bit unchanged.

### 3.3 Horizontal acceleration was per-axis, which biased movement toward world diagonals (fighter)

`velocity.x` and `velocity.z` were each passed through `move_toward` separately. On a
world diagonal the acceleration was therefore up to √2× faster (45 instead of 32 u/s²).
Paths also curved, because one axis saturates before the other. A standstill
camera-relative back-dodge at a 27° camera yaw went 2.06 m along a line 9° off its input
direction. The same dodge along a world axis went 1.66 m. Dodge length therefore depended
on where the camera pointed. Fix: integrate horizontal velocity as one `Vector2`.
Axis-aligned motion is unchanged, which is why every original assertion and screenshot
is identical. **Gameplay impact (documented, not tuning):** diagonal starts/stops now use
the same 32/70 u/s² as straight ones.

Tests: `dodge_out_of_run_keeps_distance` and `dodge_out_of_run_keeps_direction`. Both
use a yawed camera, real action input, and the live physics scene. Both failed before.

**Totals after fixes:** 33 combat assertions and 37 graphical assertions pass. All three
negative controls still fail exactly as before (3/2/3). The scripted win still takes
334 frames, and the screenshots are unchanged.

## 4. Adversarial findings (not changed; see Section 6 for proposals)

All numbers come from `scripts/qa/adversarial_probe.gd`. The probe drives the real
courtyard scene with `InputEventAction` input at 60 Hz. It runs headless (about 30 s),
and its camera cases are also rendered under Xvfb. Raw data:
`docs/evidence/combat-review/probe/`. Frame counts are physics ticks (1/60 s).

### 4.1 Dodge

| Question | Measured behavior | Label |
| --- | --- | --- |
| I-frames throughout dodge too generous? | The evade window is **18 ticks (0.30 s)**, exactly 2× the deflect window (9 ticks). Invulnerability starts on the first tick. There is no recovery: the player can attack or guard the tick after the dodge ends. | Design (Section 6.1) |
| Evasion outside intended timing? | A **backstep dodge pressed at any point in the last 24 ticks of the windup** avoids the hit purely by spacing (`no_contact`). The enemy never lunges or tracks. | Exploit |
| Still physically collidable? | Yes. The minimum centre distance to the enemy was 0.700 m (= 2 × capsule radius) in every case. No phasing. | Confirmed OK |
| Through walls/pillars? | No. It stops at the capsule radius against walls, corners and pillars. At 0.18 m per tick against 0.8–1.1 m geometry there is no tunnelling risk at this speed. | Confirmed OK |
| Slide around enemy? | At ≥0.3 m lateral offset, holding forward through and after the dodge slides the player around the enemy capsule and **past it**. This is body sliding, not overlap. | Design note |
| Dodge spam | Dodging whenever ready evaded 3 attacks, took 4 hits (8 attacks total) and lost. The cooldown (0.65 s from start) limits i-frame uptime to 46%. | OK |
| Cornered | A sideways dodge along a wall escaped 2.3 m. Damage was still evaded, because i-frames don't depend on travel. | OK |
| Momentum and direction | Bugs, fixed (Sections 3.2 and 3.3). | Fixed |
| Post-dodge slide | The player keeps sliding about 0.5 m for 8 ticks after i-frames end. They can act during the slide, but they are not invulnerable. | Design note |
| Multiple enemies | Not testable: the prototype has one enemy. | Open |

### 4.2 Guard and deflection

| Question | Measured behavior | Label |
| --- | --- | --- |
| Deflect from behind | **Deflected** with the player's back turned. Guard is omnidirectional (already documented). | Design |
| Rapid toggling | Guard 9 ticks on, 1 off: **15 deflects, 2 hits over 40 s** without reading any telegraph. Adding "attack when broken" wins at 100 HP. Each fresh press opens a full 0.15 s window, with no spam penalty. | **Exploit** |
| Hold vs. timed press | Holding gives a block: 12% chip, 28 or 42 posture. Hold-forever loses in 24.8 s (broken after 4 blocks; posture never regenerates while guarding). | OK, as designed |
| Pre-held guard | Guard pressed once during the player's own attack and held: when the player returns to `IDLE`, the guard rises with a **fresh deflect window** and deflected an attack. Reset was measured too. Stagger and dodge share the same code path (`set_guard`). The docs say "newly raised guard", which is ambiguous here. | Open decision |
| Punish window inversion | From the tick a swing would connect, a whiff leaves the attacker locked out for about 0.80 s (remaining active plus 0.65 s recovery). After being **blocked** it gets 0.65 s of recovery. After being **deflected** it is staggered for only **0.35 s**. Blocking gives a longer punish window than a perfect deflect. AI cooldown currently hides this. | Design (should be fixed) |
| Posture accumulation | Enemy posture only recovers after 1.5 s of `IDLE`. The AI cycle never idles that long, so **enemy posture never regenerates** during a fight: three deflects always break. | Design |
| Attack/guard conflict | Attack is ignored while guard is held. Releasing guard and attacking on the same tick works. There is no input buffer: an attack pressed 5 ticks before recovery ends is dropped. | Design (input buffer) |

### 4.3 Attacks and hit detection

| Question | Measured behavior | Label |
| --- | --- | --- |
| Hits during windup | Always interrupt and cancel the attack: no poise or hyper-armor. Player windup (0.34 s) is shorter than enemy windup (0.62 or 0.85 s), so the player always wins a race. → **stunlock**, Section 5. | **Exploit** |
| Hits during recovery | Shortened recovery. Fixed (Section 3.1). | Fixed |
| Simultaneous attacks | Player-first tie rule. With both actives starting on the same tick, **the player hits and the enemy's swing is cancelled**: trades never happen. A one-tick lead decides every exchange. | Design (documented provisional) |
| Facing changes during attack | While locked, the player's facing (and hitbox) re-aims at the enemy **every tick of windup and active**. An enemy relocated behind the player mid-windup was still hit. Unlocked players and the AI commit heading at attack start. This asymmetry contradicts the shared-rules principle. | Design (shared tracking rule) |
| Range consistency | The lateral test includes the 0.35 m target radius but forward reach does not. A target at 2.50 m whose capsule visibly overlaps the 2.35 m box is a miss. A target at lateral 1.10 m is a hit. Side-by-side bodies (target centre behind the attacker origin) always miss. | Bug-ish (phantom miss); proposal |
| Near obstacles | A single centre-to-centre ray. A target half visible beside a pillar is **unhittable** when the pillar covers its centreline. | Design |
| Tick rates | Rules carry overshoot correctly. Effective deflect window: 0.133 s at 30 Hz, 0.150 s at 60 Hz, 0.158 s at 120/240 Hz (tick quantisation; `guard_age` is incremented before resolution). Dodge distance 1.98–2.10 m. Below about 7 Hz an attack could skip `ACTIVE` entirely; that is not reachable at the pinned 60 Hz. | Low |

### 4.4 Enemy AI

| Question | Measured behavior | Label |
| --- | --- | --- |
| Predictable loops | A fixed basic–basic–heavy cycle with a 0.65 s cooldown. The cooldown only ticks in `IDLE`. No reaction to player attacks. The enemy never guards, deflects, dodges or retreats. | **Exploit** (Section 5) |
| Stationary / guard-spamming player | Stationary player loses in 11 s. Hold-guard loses in 25 s. Guard toggling + punish wins at 100 HP. | See above |
| Stuck states | Player behind a pillar: the enemy walks into the pillar and stays in `APPROACH` for 10 s+ without attacking. Same behind the low block. Behind a brazier, the enemy reaches attack distance and **swings into the brazier forever**, because the line-of-sight ray blocks every hit. | Bug (AI; no steering) |
| Turning | An idle enemy turns 180° in one tick: there is no turn rate, so flanking is impossible except during windup, when heading is frozen (so sidestepping is trivial). | Design |
| Posture break | The AI is inert while broken. Afterwards it reuses its leftover attack cooldown, not a rule. | Design note |
| Death | Both actors stop correctly. Lock-on stays engaged on a dead enemy. | Minor |

### 4.5 Camera and controls

| Question | Measured behavior | Label |
| --- | --- | --- |
| Close-range framing | Locked at 1.85, 3 and 5 m, the enemy's chest projects **within the player's silhouette** (17–33 px off-centre vs a 37 px half-width at 720p). The windup ground box is under the player's body. Telegraph readability currently relies on body tint and HUD text. See `probe_close_range_windup_occlusion.png`. | Design (high value) |
| Cornered | The spring arm collapses to 1.04 m. The player's body covers roughly the left 40% of the screen (`probe_cornered_camera.png`). No clipping into walls. | Design |
| Clipping | The spring arm ignores characters (mask 1). With the enemy between the camera and the player, the view stays usable in the tested pose (`probe_enemy_between_camera_and_player.png`). | OK |
| Lock-on | Acquired **through a pillar**. No range or line-of-sight check. Remains `LOCKED` after the enemy dies. Yaw lerp (8/s) competes with mouse input while locked. | Minor |
| Mouse capture | After Escape, the click that recaptures the mouse **also starts an attack**. | Minor bug (not fixed; a headless-safe fix needs care) |
| Rapid inputs | No dropped or duplicated actions in any probe. Guard is sampled per physics tick, so a tap shorter than 16 ms could be missed. | OK |

### 4.6 Reset and state

Reset was tested during enemy `ACTIVE`, player `DODGE`, deflection stagger, enemy
`BROKEN`, enemy dead, player dead, and with 10 consecutive reset presses during an
attack. Every case restored positions, health, posture, phases and visual pose on the
**same tick**, with no residual hits. Courtyard physics runs before the actors and hit
resolution is deferred, so ordering is safe. One quirk: guard held through a reset
opens a fresh deflect window on the first tick (same cause as "pre-held guard").

## 5. Why the duel is exploitable (root causes)

1. **Every hit interrupts every windup.** The player's 0.34 s windup beats the enemy's
   0.62 s. To land an attack, the enemy needs its 0.65 s idle cooldown plus its windup
   (≥1.27 s). Between player hits, it is out of stagger for only about 0.71 s (a 0.95 s
   player cycle minus a 0.24 s stagger). Mashing therefore cancels every enemy
   attack: 6 of 6 in the probe.
2. **The enemy has no defence.** Offence is free, so the posture system is optional.
   The player never needs to deflect.
3. **The enemy has no tracking or lunge.** Heading freezes at windup start, so a
   0.2 s strafe or a 0.1 s backstep beats every attack, the heavy included.
4. **Deflection has no spam cost and works in every direction**, so it can be
   automated by toggling.
5. **The reward ladder is inverted.** A whiff locks the attacker out longer than a
   block, and a block longer than a deflect.

None of these is fixed by retuning numbers alone. They need small rule and AI changes,
which are Proposed below and need approval.

## 6. Recommendations (Proposed — not implemented)

### 6.1 Dodge collisions and invulnerability: the design question

**Evaluation of current behavior.** Ordinary dodges already keep physical collision
with the enemy and level geometry: there is no overlap and no tunnelling. I-frames
affect damage only, and do not depend on travel. Being cornered still lets the player
evade damage in place. This already matches the provisional preference, except that
invulnerability covers 100% of the dodge.

**Recommendation (agrees with the provisional preference):**

- Keep body collision for ordinary dodges against enemies and geometry. Phasing should be
  a deliberate, readable property of a special ability (a salvage-augment candidate),
  because passing through a body changes spacing in ways the opponent can't read.
- Keep the capsule slide. Dodging at an off-centre angle can carry the player around
  the enemy's body. That gives skilled players repositioning while keeping bodies solid.
  If it proves too strong, reduce the tangential slide rather than adding phasing.
- I-frames should never depend on displacement. Against a wall the dodge still evades
  (current behavior, keep it), but the wall costs the player the spacing.
- **Partial invulnerability with a short recovery.** Suggested starting values at 60 Hz:

| Parameter | Current | Proposed | Rationale |
| --- | --- | --- | --- |
| Total dodge | 0.30 s | 0.36 s (22 ticks) | Room for a recovery tail without making the dodge feel slower |
| I-frames | 0–0.30 s (18 ticks) | **0–0.18 s (11 ticks)** | Slightly more lenient than the 0.15 s deflect window, because a dodge earns no posture. Removes the current 2× advantage. No startup, for responsiveness |
| Dodge recovery | none | last 0.10 s: can't attack or dodge; can guard | Makes an early dodge punishable and gives the dodge commitment |
| Distance | ≈2.0 m (ramped) | ≈2.0 m, fast-start/ease-out profile (about 9 u/s falling to walk speed) | Keeps the distance the user playtested. Removes the 0.34 s ramp that never reaches the configured 11 u/s |
| Cooldown | 0.65 s from start | 0.25 s after recovery | Replaces an invisible cooldown with visible commitment |

  Tradeoff: shorter i-frames raise skill demand and make missed timings feel
  punishing. Validate by hand, first with the windup preview box on, then off.
- Pair this with **enemy tracking or lunge** (Section 6.4). Otherwise spacing alone
  evades everything, and i-frame timing never matters.

### 6.2 Deflection and guard

- Keep the deflect window at about 0.15 s (9 ticks). Measure it in ticks so 30 Hz and 120 Hz agree.
- **Spam protection** (pick one): (a) a guard press within 0.30 s of the previous
  *non-deflecting* press gets a 0.05 s window; or (b) releasing guard without a
  deflect blocks re-raising for 0.20 s. Either makes the 9/1 toggle lose.
- **Fresh press required** for a deflect window. A guard that rises automatically from a
  held button is a block only. (Open: it is a feel decision.)
- **Frontal arc**: guard and deflect only within ±90° of facing. Hits from behind land.
- **Fix the reward ladder**: a block should not extend the attacker's recovery (it
  continues its normal recovery). A deflect should stagger for at least the attacker's
  normal remaining recovery, *or* deflect should give no punish window at all and pay
  out only in posture (closer to Sekiro). Decide which.

### 6.3 Posture

- Let enemy posture regenerate in any non-attacking, non-broken phase after 1.0 s
  without pressure, scaled by remaining health. Then breaking requires sustained
  pressure instead of three deflects spread across the whole fight.
- Break payoff: today a 2.2 s break at 2× damage lets the player land 2–3 hits
  (72–108 damage), which is nearly a kill from full health. Consider one guaranteed
  heavy punish (deathblow-like) per break, or cap break damage to the first hit.
  This is a design decision for the user.

### 6.4 Attacks and hit detection

- **Shared tracking rule** for both actors: facing tracks the target during windup at
  a capped turn rate (start around 270°/s), then commits for the active phase. This
  removes the player's 180° homing and the enemy's zero tracking.
- Optional per-attack lunge (for example 0.6–1.0 m during active), so backstepping must be timed.
- **Poise/interrupt rule**: heavy windups (and possibly the last third of any windup)
  resist interruption. Alternatively, interrupting requires a posture threshold.
- Trades: resolve simultaneous actives from a snapshot, so both hits land (or use explicit
  priority, such as heavy beats basic), instead of player-first.
- Hit shape: test the target capsule against the box (forward ≤ range + radius) and
  shorten `attack_range` by the radius, so effective reach stays similar and the
  visual box matches. Cast three rays (centre and ±radius) for obstacle checks.

### 6.5 Enemy AI

- A defensive layer is the single highest-value change. When `IDLE` or `MEASURE` and
  the player starts a windup in range, guard (and deflect every Nth hit, deterministic).
  Each blocked hit builds player-applied posture as today.
- Turn rate of about 360°/s when idle.
- Simple obstacle steering (or keep the duel ring free of obstructions). Don't attack
  when the line of sight to the player is blocked.
- Reset the attack cooldown on stagger or break, so the AI's rhythm is a rule rather
  than a leftover value.

### 6.6 Camera and input

- Shoulder offset of about 1.3, slightly higher pivot. When locked, frame the midpoint
  between player and enemy, so the enemy torso and windup are never behind the player.
- Lock-on: maximum range and line-of-sight check on acquire. Release on death.
- An input buffer of about 0.12 s for attack, dodge and guard presses during non-idle phases.
- Ignore the attack press that recaptures the mouse.

## 7. Prioritized next iteration

Ordered by value to combat depth per unit of work. Items 1–3 should come before any
salvaged ability, because an augment layered on an exploitable base can't be evaluated.

1. **Enemy defence and poise** (Sections 6.5 and 6.4). Removes the mash-to-win stunlock and
   makes offence a decision.
2. **Shared windup tracking plus optional lunge** (Section 6.4). Removes trivial sidestep and
   backstep and the player's homing hitbox.
3. **Deflect spam protection, frontal arc, reward-ladder fix** (Section 6.2). Makes the
   deflection the skill reward it is meant to be.
4. **Partial dodge i-frames and recovery** (Section 6.1), tuned by hand.
5. **Close-range camera framing** (Section 6.6). Telegraph readability is a gate-1 requirement.
6. Input buffer; trade resolution; enemy posture regeneration.
7. AI obstacle handling; hit-shape consistency; lock-on validity; mouse-recapture click.

**Suggested next small task:** implement item 1 alone, as a deterministic guard response
plus heavy-windup poise. Gate it with the probe's `mash_attack_only` strategy, which
must stop winning at full health. Then have the user playtest it before item 2.

## 8. What human playtesting must answer

The automated work cannot judge these. Each needs desktop frame rate, a mouse, and
several attempts:

- Can a first-time player read basic vs. heavy windups without the amber box (F3 off)?
- Does the 0.15 s deflect window feel fair or stingy at 60 Hz? At 144 Hz?
- Does the post-fix dodge feel the same as before from standstill, and more reliable
  out of a run? (Only the out-of-run behavior changed.)
- Does camera framing at duel range hide the enemy's sword arm?
- After the stunlock fix, do players reach for deflection, or still prefer spacing?

## 9. Reproduce

```sh
bash scripts/tooling/setup.sh            # verifies and installs Godot 4.7.2
bash scripts/tooling/test.sh             # import, combat, 3 negatives, rendered suite
bash scripts/tooling/probe.sh            # adversarial measurements (headless + 3 renders)
```

Set `BONESHED_TOOLS` when `/workspace` isn't writable (this review used a scratch
path). Evidence index: [`evidence/combat-review/README.md`](evidence/combat-review/README.md).
