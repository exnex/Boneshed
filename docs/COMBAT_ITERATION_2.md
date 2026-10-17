# Combat iteration 2 — reading, deflection, and defense

This implements the requested courtyard iteration against `d4622d6` (latest main
fetched at preparation). PR #3 is merged at `d831cd8`; its recovery/stagger floor
and both dodge/movement fixes are preserved. No open PRs were returned during
preparation. The keyword generator/data and desktop camera/dodge controls are unchanged.

**Confirmed scope:** improve this duel's attack communication and remove the two
reported input-spam exploits. **Proposed tuning:** every number and defensive choice
below is an evaluation parameter, not an approved permanent rule. **Open:** whether
the resulting duel is readable, fair, and enjoyable to a person.

## Attack communication

Both actors use the same phase-driven procedural pose. The sword arm follows the
hand, the torso loads into the attack, and the blade rises above the body silhouette.
The heavy loads higher than the basic. There are five observable stages:

| Stage | Pose and rule |
| --- | --- |
| Early windup | Arm/blade rise and torso turns; no hit |
| Commitment | Distinct held, raised sword; final 0.24 s of windup |
| Release | Blade moves from the loaded pose into forward reach in the last 0.08 s; no hit |
| Active | Blade is already extended on the first damaging tick, then sweeps across the front |
| Recovery | Arm and torso slowly return to rest; no hit and no guarding |

Release is a subdivision of WINDUP, so existing total attack durations and phase
overshoot behavior stay intact. Hit resolution still reads shared rules; animation
does not enable damage. The first active blade tip reaches approximately 2.35 m,
matching the existing forward box's reach. Debug volumes remain available with F3.
The central windup text and whole-body windup tint were removed; the body and
weapon carry the cue. No trails, new particle effects, or external assets were added.

The captured fixed-step basic first becomes active at tick 38 (0.633 s), and the
heavy at tick 51 (0.850 s). These are 60 Hz quantized samples of 0.62/0.85 s windups.
Evidence includes every tick's actual blade transform and hit result, five stage
PNGs per attack, and 30 fps rendered sequences around release/contact/recovery.
The timing fixture holds guard so contact can resolve without truncating the swing;
HUD/debug volumes are hidden for these body/weapon captures.

## Deflection discipline

A fresh guard press starts the existing **0.16 s** window only when idle and rearmed.
Each press starts/restarts **0.32 s** of settling before another unsuccessful attempt
can open a window. Re-pressing while settling still raises a normal guard immediately;
it never disables movement, attack, dodge, or block. The guard pose's wrists sit
slightly lower while a suppressed re-press settles.

An actual deflection clears settling, allowing the next deliberately timed press.
One raise earns at most one deflection. Continuing to hold it blocks with chip and
posture pressure. Input history is sampled even during attacks/staggers/dodges:
holding through recovery or encounter reset cannot create a new perfect window.

Guard/deflect protect the front hemisphere, including the side boundary (facing dot
incoming direction **>= 0**, nominal ±90°). The scene computes this direction from
positions and passes the scalar to the shared rules. Rear attacks deal normal hits.

A block preserves the attacker's remaining active motion and natural recovery.
A deflection staggers for at least **remaining active + configured recovery**
(minimum 0.35 s), or breaks posture. This gives a real punish opportunity and keeps
a successful deflection from shortening the attacker's natural commitment.

## Restrained enemy defense

When idle and threatened by an unconsumed, in-range player windup/swing, the swordsman
raises a visible guard. This AI policy only blocks; it does not generate accidental
perfect deflections. After contact, it lowers guard and starts the **existing 0.85 s
heavy** in response, including when already within weapon reach but outside its
preferred standing distance. There is no instant counter hit or random selection.

The braced swordsman's configured block posture cost is **10 basic / 15 heavy**,
versus the player's existing **28 / 42**. Health chip remains 12% for both, and
deflecting either form's attack still applies 42 posture. This explicit form tuning
keeps blind attacks on the guard from breaking it before the response can matter;
it does not create a second damage/defense implementation. Human testing must assess
whether this defensive asymmetry is understandable and appropriately restrained.

Only heavy attacks resist ordinary hit interruption during the final **0.24 s**
and their **0.16 s** active phase. They still take full health/posture damage.
Earlier heavy windup and all basic windups remain interruptible; deflection, posture
break, and death override resistance. Recovery, stagger, and break remain punishable
and cannot raise AI guard. The rule is shared by player/enemy CombatState.

## Before/after measurements

Same default-start legal-input adversarial strategies, pinned engine, 60 Hz:

| Strategy | Unchanged main | Iteration 2 |
| --- | --- | --- |
| Attack only, alternating press/release | Player wins at 100 HP in 7.12 s; 6/6 enemy windups interrupted | Player loses in 10.43 s; enemy 37.36 HP; 4 guards, 4 heavy responses, zero windup interruptions |
| Guard 9 ticks on / 1 off; attack when enemy broken | Player wins at 100 HP in 11.82 s, 5 deflections | Player loses in 26.23 s; zero deflections; 9 blocks, posture breaks and punishes |
| Hold guard forever | Player loses in 24.83 s | Player loses in 26.23 s |
| Native graphical deflect/punish bot | Player wins at 100 HP in 334 ticks | Player wins at 100 HP in 418 ticks |
| Timed rear guard press | Deflection, 100 HP | Normal hit, 82 HP |
| Long-held rear guard | Block, 97.84 HP | Normal hit, 82 HP |

The added encounter gates also test attack-only input at 1.2, 1.85, and 2.2 m,
alternating every 2 or 5 ticks: all six lose at 8.50/8.70 s, enemy 37.36 HP.
The skilled gate wins untouched in 418 ticks with three deflections and a break.

These are deterministic fixtures, not a claim that every possible spam cadence is
defeated. Sidestepping then punishing still wins untouched (14.65 s); backstepping
then punishing also wins untouched (18.28 s). Windup tracking, lunges, and camera
changes were outside this iteration. These remaining spacing strategies deserve
human assessment before expanding the combat design.

## Validation

```sh
bash scripts/tooling/setup.sh
BONESHED_GRAPHICAL_TIMEOUT=600 bash scripts/tooling/test.sh artifacts/iteration2-native
bash scripts/tooling/probe.sh artifacts/iteration2-probe
bash scripts/tooling/test_web.sh artifacts/iteration2-web
```

Use new output directories. All tooling checks the exact engine build
`4.7.2.stable.official.ed1daf0bf`. Native rendered tests use Xvfb/Mesa llvmpipe;
desktop browser tests use real Chromium/WebGL with keyboard/mouse. No touch adapter
or touchscreen gameplay was restored. The production export excludes QA code.

The native runner now includes 60 shared-rule checks, 8 live encounter gates,
headless and rendered timing checks, and the existing 37 graphical/input checks.
Negative controls deliberately break guard mitigation, deflection timing, windup
activation, rearm protection, rear protection, committed-heavy resistance, AI defense,
and visible weapon timing. Each must exit 1 and fail its designated assertion.

The baseline native run passed 33 combat / 37 graphical checks and all three
original negative controls; the baseline desktop browser passed 14 checks. A first
baseline run hit the 180 s graphical timeout under concurrent software rendering;
an isolated unchanged-main rerun with a 600 s limit passed. Initial sandboxed runs
could not open editor/X11 sockets; final runs enabled the required networking/sockets.
There are no skipped checks in the successful runs. Full results, state samples,
negative controls, captures, and limitations are indexed in
[the evidence directory](evidence/combat-iteration-2/README.md).

## Human desktop playtest checklist

- Run a few duels with F3 volumes off. Identify early windup, the raised commitment,
  release, contact, and recovery from the body/sword. Compare basic versus heavy.
- Read an attack, tap guard near release, and land a punish. Repeat without relying
  on posture-break text; test at 60 and high refresh rates.
- Raise guard early and hold it. Confirm a useful block with chip/posture pressure.
  Try rapid guard taps, then pause briefly and time one fresh tap; assess the settling
  delay and its small wrist-pose cue.
- Turn away from an attack. Confirm rear damage and assess the frontal boundary.
- Mash light attacks, watch the guard/heavy answer, then try stopping to deflect or
  dodge it. Hit the heavy early versus after its raised commitment; assess fairness.
- Confirm lock-on and dodges still feel familiar. Check close range and corners:
  the player's body can still obscure the enemy torso/contact point even though the
  raised sword is clearer. Report any unreadable release or apparently invisible hit.

Automation verifies these rules and outcomes. It does not establish fun, readability
to a new player, latency tolerance, or final balance. The hit shape remains the
prototype's forward box plus obstacle ray, not a swept blade collision mesh. The
duel remains a primitive, silent prototype requiring human desktop playtesting.
