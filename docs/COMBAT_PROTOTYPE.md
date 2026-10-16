# Courtyard combat prototype

This milestone is an evaluation build of one duel. Movement, attack timing, chip damage,
posture, dodge invulnerability, and the punish multiplier are **provisional**. They do
not settle the open final-game combat decisions in `DECISIONS.md`.

## Run

Use exactly **Godot 4.7.2 stable**, full build `4.7.2.stable.official.ed1daf0bf`.
The default engine on this cloud image is older; use the project scripts.

```sh
cd /workspace/Boneshed
bash scripts/tooling/setup.sh
bash scripts/tooling/play.sh
```

Setup verifies the official Linux x86_64 archive against its official SHA-512 manifest
and the pinned checksum in the script. It keeps tools and XDG config/cache/data in
`/workspace/tools`, outside the checkout. Set `BONESHED_TOOLS` for another writable
location or `GODOT_BIN` for an existing exact-build executable. No game assets or
third-party game dependencies are required. In the Debian 13 cloud image, setup can
extract the signed Debian Xvfb package without root; Mesa, Xauth, and Xvfb's shared
libraries are prerequisites supplied by the image. On another distribution, install
the distribution's Xvfb, Xauth, and Mesa packages normally.

GL Compatibility is the default. For later hardware comparison, the engine renderer
can be selected explicitly: `bash scripts/tooling/play.sh --rendering-method forward_plus`.
Hardware rendering has not been validated in this cloud task. On a desktop, open
`project.godot` with the pinned editor or use `play.sh`. The cloud tests use Xvfb and
do not provide a streamed play session.

## Controls

| Input | Action |
| --- | --- |
| WASD | Move relative to the orbit camera |
| Mouse | Orbit; pitch is clamped |
| Tab | Toggle enemy lock and camera tracking |
| Left mouse | Light attack; also capture the mouse after Escape |
| Right mouse | Hold guard; newly raised guard has a timed deflection window |
| Space | Short dodge in the movement direction, or backward when standing still |
| R | Reset either a living, won, or lost encounter |
| Escape | Release the mouse |
| F3 | Toggle visible attack volumes |

The amber ground box previews a windup; the red box is the active attack volume.
A cyan burst marks a deflection. The gold overhead ring and full posture bar mark a
broken enemy. Attacks must intersect the forward box, be in their active phase, and
have an unobstructed physics ray to the target. A swing can resolve against its
opponent only once. The preview box is enabled by default for this evaluation build.

## Small architecture

- `scenes/courtyard.tscn` / `scripts/courtyard.gd`: procedural stone courtyard,
  lighting, collision, input bindings, encounter reset, and fixed-order hit resolution.
- `scripts/combat/combat_state.gd`: shared rules with no scene, AI, or rendering access.
  Both actors use the same attack, guard, deflection, posture, dodge, and damage rules.
- `scripts/characters/fighter.gd`: `CharacterBody3D` movement, physics-world hit
  validation, procedural humanoid and sword animation, debug volumes, and feedback.
- `scripts/characters/player.gd`: input, camera-relative motion, lock-on, and a
  sphere-shaped `SpringArm3D` that checks world geometry.
- `scripts/ai/swordsman.gd`: deterministic detection, approach, distance maintenance,
  and a two-basic/one-heavy attack cycle. The heading commits at attack start.
- `scripts/hud.gd`: live health/posture/state readouts and controls.
- `scripts/qa/`: isolated combat tests and an in-scene graphical/input test driver.

The actors move and advance rules at 60 physics ticks per second. Attack windup,
active, and recovery transitions carry time overshoot across phase boundaries.
Presentation reads the rule phase; rendered sword poses do not drive hit timing.
Deferred resolution occurs after actor physics, with a documented player-first tie
rule for simultaneous active attacks. This priority is provisional.

## Tuning

All durations below are seconds. Public rule parameters live in `CombatState`; the
enemy configures its own windup/recovery in `_ready`. Movement and camera settings
are exported on the actor scripts for inspector iteration.

| Parameter | Current value |
| --- | --- |
| Player/basic enemy windup | 0.34 / 0.62 |
| Heavy windup | 0.85 |
| Active window | 0.16 |
| Player/enemy recovery | 0.45 / 0.65 |
| Deflection window after raising guard | 0.16 |
| Basic/heavy health damage | 18 / 32 |
| Guard chip | 12% of incoming health damage |
| Guard posture pressure | 28 basic, 42 heavy |
| Deflection posture pressure on attacker | 42 |
| Break threshold / vulnerability | 100 posture / 2.2 seconds |
| Damage against broken target | 2×; hits do not extend the break |
| Dodge duration / cooldown | 0.30 / 0.65 |
| Posture recovery delay / rate | 1.5 seconds / 12 per second when idle and unguarded |
| Player move / dodge speed | 5.5 / 11 world units per second |
| Acceleration / braking | 32 / 70 units per second squared |
| Hit box length / width | 2.35 / 1.6, with 0.35 target capsule radius |

Guarding slows movement and cannot cancel an attack. Deflection has no chip damage
and staggers the attacker unless its posture breaks. Holding guard past the window
blocks with chip damage and posture cost. Dodge grants evasion for its entire short
phase, with a cooldown. A broken actor cannot act until the vulnerability expires.

Correctness fixes from the [combat review](COMBAT_REVIEW.md) (no tuning values changed):
a hit staggers for 0.24 s but never shortens a recovery or stagger already in progress;
a dodge keeps only the momentum that points along its direction; and horizontal
acceleration is applied as one vector, so diagonal movement no longer accelerates
faster than axis-aligned movement.

## Validation and evidence

```sh
bash scripts/tooling/test.sh
# Or specify a new, empty directory:
bash scripts/tooling/test.sh artifacts/my-run
```

The runner checks the exact engine version, imports the project, executes combat
assertions, and launches real GL Compatibility rendering through Xvfb/Mesa llvmpipe.
External timeouts protect every engine run. Engine errors, a missing summary, a
wrong exit status, missing screenshots, or no substantive checks fail the runner.
Each run uses a fresh directory, so old outputs cannot satisfy current checks.

The three negative runs deliberately inject defects into guard mitigation, the
deflection window, and attack phase. Each must exit 1 and fail its specific expected
assertion; these are expected failures, reported separately from passing checks.

The graphical suite feeds action and mouse events through Godot's input API, checks
movement/stopping, camera orbit/lock/wall avoidance, grounded actors, AI approach and
attacks, shape/range/obstacle rejection, held guard versus timed deflection, three
deflections producing a break, punish damage, dodge movement, live enemy defeat,
player death, and complete encounter reset. Isolated spatial cases use explicit
fixtures; the final winning and losing encounters use the active enemy state machine.

Curated logs, state records, and five inspected captures are stored in
[`evidence/milestone-1/`](evidence/milestone-1/). The screenshot records include actor
positions, phases, health, and posture frozen at capture time. `runs.json` records
the underlying process exit statuses.

After the combat review the suites contain **33 combat and 37 graphical assertions**
(all passing; negatives unchanged), and `bash scripts/tooling/probe.sh` records
adversarial measurements (exploit strategies, timing windows, camera framing). See
[`evidence/combat-review/`](evidence/combat-review/README.md).

Milestone 1 recorded result: headless import succeeded, **30 combat assertions and 35
graphical assertions passed**. All three negative controls exited 1 as required
(guard: 3 failed assertions; deflection: 2; phase: 3). No required check failed or
was skipped in the final run. The scripted win took 334 simulation frames; the
player remained at 100 health. The losing encounter also reached player death
and reset correctly. The only graphical driver warning was unsupported VSync
switching under Xvfb; rendering used Mesa llvmpipe successfully.

## Human evaluation still needed

This is a primitive, silent, single-opponent prototype. Automated input proves the
encounter can execute and be won; it does not prove the duel is enjoyable, balanced,
or accessible. Test attack interruption/stunlock, response latency, camera framing,
telegraph readability, deflection generosity, dodge invulnerability, and break damage
by hand at desktop frame rates. Guard currently protects all directions; there is no
guard-direction rule. The active volume is a forward box rather than a blade sweep.
There is no buffered attack queue, audio, animation asset, salvage, inventory,
progression, backend, multiplayer, or procedural world generation.

Assess this duel before implementing the next milestone's salvageable augment.
