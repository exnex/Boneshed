# Enemy survival AI: the corrupted swordsman fights to survive

**Status: implemented on `feat/enemy-survival-ai`, provisional, not human-validated.**
Base `main` `8025663`. Engine **Godot 4.7.2.stable.official.ed1daf0bf** (pinned SHA-512
setup, `--version` checked), GL Compatibility, llvmpipe under Xvfb for renders.
This implements the confirmed 2026-10-19 NPC direction in [DECISIONS.md](DECISIONS.md):
*reposition/retreat, dodge when threatened, counterattack after effective defense, pick
attack moments, stay readable and fair, no input-reading or omniscience.* Every weight,
delay and distance below is **proposed tuning**. Automated runs and renders do not show
that the duel feels good; a human playtest is still required.

**Unchanged:** player controls, combat rules (`combat_state.gd`), attack damage and
timings, deflection, dodge, posture, builds/catalog, keyword/worldgen/expedition files,
scenes. The enemy still never deflects (guard is raised with `allow_deflect = false`, as
before). No Last Oasis-style directional combat. No new assets or dependencies.

## What the enemy does now

| Situation (as the enemy sees it) | Before | Now |
| --- | --- | --- |
| A player windup that can reach it | Raise guard at once, every time | After a reaction delay, commit to **one** answer for that swing: **guard**, **evade** (dodge back-and-sideways, timed to the blade) or **backstep** (only if walking out of reach is visibly possible). Weighted by attack kind, own posture, recent hits, dodge cooldown and what it did last. |
| A blocked hit | Heavy counter, always | Counter if it can **win the timing race** against the opponent's quickest reply. Light if it lands first, heavy if it reaches its poised commitment first; heavy against a flurry. Chance drops after its counters get deflected or blocked. |
| A missed player swing (whiff) | Nothing special | Recognised (no contact felt during that swing). Punished only when the race is winnable, e.g. a whiffed Marrow Lunge with its 0.8 s recovery. Otherwise it is traced as `counter_skip` and the enemy repositions. |
| Posture break on the player | Next ordinary attack | Immediate heavy punish. |
| Player turtles behind guard | Ordinary cycle | More heavies while guard has visibly been held > 1 s, then punishes the break. |
| A player swing that would land during its own windup or recovery | Takes the hit | Sometimes cancels into guard (the same fresh-guard cancel the player has): 50 % in the uncommitted early windup, 45 % in recovery, at most once per stage and once per 2.5 s. A heavy that will be poised before contact is never aborted. |
| A player flurry (≥ 2.5 recent swings) | Guard, heavy counter | Holds ordinary attacks that would be interrupted (≤ 1.5 s), prefers block → poised heavy counter, evades less. |
| Player walking into reach | Waits until 1.85 m | **Intercepts**: starts a light swing timed so the blade arrives as the player crosses into reach (reads visible closing speed). |
| Player holding just outside sword reach (with Marrow Arm) | Approaches | Approaches; 40 % chance per ready window to use the lunge's reach from 2.45–3.1 m. |
| Posture ≥ 55 % (or health < 40 % right after a hit) | Keeps fighting | **Retreats** to just outside the player's visible reach while circling, for at most 2.8 s, then re-engages; another retreat waits 4 s. Wall-aware. |
| Between attacks | Stands still | **Circles** at preferred range, switching side every 1–2.2 s (seeded) or at walls. |
| Out-of-range swings | — | Ignored (no answer, no dodge). |

## Fairness: what the AI can and cannot know

`scripts/ai/opponent_perception.gd` is the whole perception surface. Each tick it
records a whitelisted snapshot and delivers it only once it is **0.18 s old**:

- rule phase and rule time (the key poses are sampled from exactly these), attack kind
  (light/heavy/lunge silhouettes differ), the attack's public frame data (phase lengths,
  the opponent's quickest windup), blade/bone reach, guard and dodge stance, HUD
  health/posture bars and facing.
- **Never**: input or actions, `desired_move`, `hit_consumed`, cooldowns, deflect timers,
  AI state. Tests check the snapshot keys and scan both AI scripts for those reads.
- Body positions and velocity are read live: people track bodies continuously; reaction
  time governs discrete action onsets. Contacts on its own body/blade are *felt* at once.

Bounded reaction and commitment:

- Answers come no earlier than 11 ticks (0.18 s) after the windup starts, plus a seeded
  0–0.06 s hesitation. A player light (0.34 s windup) still leaves time to guard or dodge.
- **One committed answer per perceived swing.** An evade that cannot dodge does not fall
  back to guard; a backstep commits. **Feints can bait the dodge** (shown in tests and the
  `feint_baits_dodge` clip), which is the intended counterplay to a reactive opponent.
- The enemy keeps its existing exploitable windows: deflection still staggers it, and its
  0.65 s recovery is still punishable most of the time.

## Variety and anti-spam

- Each consecutive repeat of the same answer multiplies its weight by 0.5;
  dodges are capped at 2 in a row. Across the scripted styles no answer repeats more than
  3 times running.
- Dodges stay a minority (in the shipped run, 13 of 85 player swings; the test bound is ≤ 50 %).
- Counters only follow an opening (block, whiff, break) within 0.9 s.
- Attack spacing jitters between 0.8× and 1.6× the 0.65 s interval.
- All randomness uses one `RandomNumberGenerator` seeded from `ai_seed` on every
  encounter reset, so a duel replays exactly. Each decision is appended to
  `Swordsman.trace` (tick, time, decision, cue, weights, roll).

## Architecture

```
Player input ─► Player ─┐                         ┌─ CombatState (unchanged rules)
                        ├─ intent calls ─► Fighter┤
Swordsman ──────────────┘   set_guard / try_dodge  └─ move_and_slide
   ▲  attack / attack_special / desired_move
   └─ OpponentPerception.observe(opponent) → delayed whitelisted snapshot
```

- [`scripts/ai/opponent_perception.gd`](../scripts/ai/opponent_perception.gd) (new,
  `RefCounted`): delay buffer, swing counting, whiff detection, contact/exposure estimates.
  Reusable by any future AI controller; not tied to the swordsman.
- [`scripts/ai/swordsman.gd`](../scripts/ai/swordsman.gd): decisions, a typed `Intent`
  enum (the `ai_state` string stays as a debug label; existing fixtures read it) and
  `Answer` enum. Tuning is grouped under the exported **Survival AI (provisional)** group.
- [`scripts/hud.gd`](../scripts/hud.gd): F3 debug line now also shows `AI <intent>`.
- [`scripts/qa/marrow_playthrough.gd`](../scripts/qa/marrow_playthrough.gd): the legal-input
  bot now retries its inherited lunge until one connects (the enemy may now dodge it). The
  check it guards is unchanged.

## Evidence

Run `bash scripts/tooling/test_enemy_ai.sh [new-empty-dir]`. It runs 28 checks, compares
traces from a second process byte-for-byte, runs two negative controls and renders 8
decision clips with contact sheets. Curated output is in
[`docs/evidence/enemy-survival-ai/`](evidence/enemy-survival-ai/README.md).

Scripted player styles (legal `InputEvent`s only), new AI vs the original AI on `main`,
both scenes, same harness. Winner, seconds, remaining health, enemy hits taken, enemy dodges:

| Scene | Style | Original AI | New AI |
| --- | --- | --- | --- |
| courtyard | masher (attack every other tick) | enemy · 8.5 s · E 37 · 3 hits · 0 dodges | enemy · 13.2 s · E 37 · 3 hits · 1 dodge |
| courtyard | aggressive (chase + attack) | enemy · 8.7 s · E 37 · 3 · 0 | enemy · 9.6 s · E 55 · 2 · 2 |
| courtyard | guard held forever | enemy · 25.1 s | enemy · 19.2 s |
| courtyard | passive | enemy · 9.9 s | enemy · 9.3 s |
| courtyard | kiting retreat | enemy · 15.8 s | enemy · 16.3 s |
| courtyard | skilled deflect + punish | **player** · 7.0 s · P 100 | **player** · 9.7 s · P 100 |
| courtyard | hit-and-run spacer | enemy · 12.6 s · E 80 · 1 · 0 | enemy · 19.6 s · E 62 · 2 · 2 |
| courtyard | feinter (cancelled swings) | enemy · 12.2 s · E 100 | enemy · 18.3 s · E 100 · 3 baited dodges |
| salvage | masher | enemy · 8.5 s · E 37 · 3 · 0 | enemy · 20.0 s · E 22 · 4 · 3 |
| salvage | aggressive | enemy · 8.7 s · E 37 | enemy · 9.6 s · E 55 |
| salvage | guard held forever | enemy · 25.6 s | enemy · 17.1 s |
| salvage | hit-and-run spacer | enemy · 10.3 s · E 98 · 0 · 0 | enemy · 17.8 s · E 64 · 2 · 1 |
| salvage | skilled deflect + punish | **player** · 7.1 s · P 100 | **player** · 10.3 s · P 100 |

Read these as behavior evidence from one seed per style, not balance data.

## Limitations and uncertain balance choices

- **Harder in some ways, softer in others.** The new enemy survives flurries better and
  breaks turtles faster, but against hit-and-run and (with the Marrow Arm) mashing it
  takes *more* damage than the old guard-everything enemy, because it spends time
  evading and circling. Whether that is better duelling or just noisier is a human call.
- **Whiff punishes are rare with sword attacks.** The enemy's slow profile (0.62 s light
  windup, 0.65 s recovery) loses almost every race against a player light (0.34 s), so
  most whiffs are traced as `counter_skip`. Faster punishes would need a profile/timing
  change, which this task did not allow.
- **Recovery guard-cancel** uses a shared, confirmed rule, but it narrows the player's
  punish window on the enemy's recovery to about half the time. Watch this in playtests;
  `recovery_guard_chance = 0` restores the old exposure.
- **Reaction delay 0.18 s** plus 0–0.06 s hesitation is a guess at a trained human.
  The enemy reads windup progress precisely once visible; it has no aim error.
- **Frame data is assumed known** (like a practiced player). It never predicts *which*
  attack comes next.
- **Live body tracking.** Position/velocity are not delayed.
- **Retreat is bounded but not smart pathfinding.** Wall checks are single raycasts; no
  navigation mesh. In the expedition arena it has only been exercised by the existing
  playthrough bot.
- **Determinism.** Same seed + same inputs gives byte-identical traces in separate
  processes. Within one process, a replay after a scene reload showed identical decisions
  with up to 2.6 mm body-position drift (physics contact resolution); the test allows 1 cm.
- **Bots are not people.** Scripted styles show reachability and bounds. The skilled bot
  deflects with exact rule timing.
- Code audit **F5** (free-string result codes) is still open; `"punish"` has no constant in
  `CombatState` and rules files were out of scope.

## Human playtest checklist

1. Press F3 to see `AI <intent>` next to the enemy phase.
2. Attack repeatedly: does the enemy mix block/dodge readably and punish with heavy counters?
3. Feint (attack, then guard immediately): can you bait a dodge, then punish it?
4. Hold guard: does the heavy pressure feel fair?
5. Hit and step out: does the enemy's interception feel readable or psychic?
6. Get its posture high: does the retreat read as survival, and does it come back?
7. Punish its recovery: does the occasional recovery guard-cancel feel fair or frustrating?
