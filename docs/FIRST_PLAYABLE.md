# First playable: claim the Marrow Arm

**Equipment foundation (catalog 0.4.0):** see [EQUIPMENT_FOUNDATION.md](EQUIPMENT_FOUNDATION.md).
Marrow Arm is now a left-arm body modification (`arm_l`); the sword stays in the right hand
(`hand_r`). Build slots are `hand_r`/`hand_l` grips on `arm_r`/`arm_l` body slots; text below
that names `main_hand`/`left_arm`/`right_arm` or a left-hand sword describes catalog 0.3.0.

The isolated salvage entry point is `scenes/salvage_courtyard.tscn`. The desktop
project now opens [First Expedition](FIRST_EXPEDITION.md), which reuses this loop.
The isolated scene uses the same
courtyard, fighters, build resolver and combat rules as the ordinary duel. Its enemy
build equips Marrow Arm. `scenes/courtyard.tscn` remains the ordinary, unaugmented
duel and the historical regression fixture.

## Human playtest

Open `project.godot` in Godot **4.7.2.stable.official.ed1daf0bf** and press **F5**
(Run Project) for the expedition, or F6 with the salvage courtyard open for this
isolated duel. On the configured Linux x86_64 environment, the checksum-verified
tooling also launches it with:

```sh
bash scripts/tooling/setup.sh
source scripts/tooling/env.sh
"$GODOT_BIN" --path "$REPO_ROOT" res://scenes/salvage_courtyard.tscn
```

1. The encounter starts immediately. Move into the circle with **WASD**; **mouse**
   orbits and **Tab** locks the swordsman. **LMB** strikes, **C** uses the ordinary
   heavy attack, **RMB** guards (tap near contact to deflect), **Space** dodges.
2. Watch for **Marrow Lunge**: the ivory left arm draws back horizontally, its
   amber bone forks frame the shoulder, then the bone extends in a straight thrust.
   This differs from the sword heavy's overhead raise. The body and weapon carry the cue; the normal HUD has no phase narration.
   Deflect the contact or dodge; punish the recovery. The first attack is a lunge,
   and it returns every four initiated attacks unless the enemy is countering a block.
3. Defeat the enemy. The prompt changes to **SOUL RELEASED · F to salvage Marrow
   Arm**. Press **F**. The arm now appears in your build's carried inventory; you
   still cannot use its attack.
4. Read the inspection card: a left-arm body modification (the sword stays in your
   right hand; the bone arm has no hand), plus the legacy Q lunge — a long, narrow
   thrust with slow recovery; standard deflection timing. Press **E** to equip it.
   The ivory arm appears on your right, with the sword presented on your left.
5. Press **N** to begin the next duel with your newly resolved equipment. Press
   **Tab** to lock again. **Q** executes Marrow Lunge; the HUD announces your
   inherited power. Light/heavy attacks, guard, deflection and dodge remain available.
6. **F1** opens/closes the control reference; **F3** toggles developer volumes (off by default).
   **R** retries the current duel with acquired inventory and equipped items retained.
   An unclaimed victory reward is discarded by R: win again to salvage it. N advances
   the duel number after an equipped victory. You can win or lose subsequent duels.
7. **Esc** releases the mouse; click to capture it again. Closing/reopening the game
   starts a fresh session. There is no disk save or full inventory menu in this milestone.

Start with ordinary sword attacks; use deflection and posture breaks to create openings.
No developer commands, test flags or file edits are needed for this loop.

## Provisional tuning

Confirmed direction is shared combat, readable defense, and inherited enemy power.
The task authorizes this first playable implementation. These numbers and equipment
choices are **provisional**, rather than permanent balance decisions:

| Marrow Lunge value | Initial value / behavior |
| --- | --- |
| Windup | 0.70 s (42 ticks at 60 Hz) |
| Committed telegraph / release | final 0.24 s / final 0.08 s of windup |
| Active / recovery | 0.20 s / 0.80 s |
| Health / hit posture / blocked posture | 26 / 18 / 45 |
| Forward reach / width | 3.4 / 0.9 units; existing 0.35 target capsule-radius allowance |
| Defense | normal frontal guard, 12% chip, 0.16 s deflection, existing dodge invulnerability |
| Interruptibility | no heavy-attack poise; can be interrupted before contact |
| Cancels / movement | existing immediate guard/dodge cancels; existing movement and 270°/s attack steering |
| Tradeoff | narrower aim and longer recovery than a light attack; excludes two-handed grips |
| AI | opening lunge, then every fourth initiated attack; blocked-hit counters remain heavy |
| Input | Q signature, C heavy, F salvage, E equip, N next duel |

Timing, damage, pressure and shape live in `data/builds/catalog.json`; both actors
resolve that one ability definition. The curated bone pose supports reach 2.4–4.0 and
width 0.4–1.2; data outside that range fails preparation. The ordinary sword modules
retain their single shared geometry contract. No stamina/resource system was added.
Catalog **0.3.0** invalidates stale references; examples and the anatomy projection's
build-version pin are regenerated. The old Marrow Arm deflection penalty is removed.

## Ownership and transitions

`DuelProgression` belongs to one courtyard. It stores id-only builds, a stage
(`DUEL`, `VICTORY`, `FALLEN`), an encounter generation and pending verified references.
There are no autoloads or disk persistence. Fighters and progression refer to the same
prepared combat states. Inventory/equipment remains exclusively in the validated builds.

The encounter resolves player contact, then enemy contact using the existing tie rule.
Only a **DEFEATED result from an actual player contact**, together with the registered
enemy's zero health/dead phase and a living player, opens victory. Merely assigning
DEAD, pressing reset, or invoking the salvage input cannot generate a reward. Rewards
use `Salvage.rewards`, acquisition uses `Salvage.acquire`, equipment uses `BuildRules.equip`.
Duplicate ownership is rejected at the session claim boundary. This is local encounter
authority, not protection against a modified client; server rewards remain future work.

Equipping prepares both candidate builds before replacing inventory/equipment. Failure
leaves the previous build and live fighter intact. The player receives the prepared state
between encounters; the defeated enemy stays dead until N/R. N/R freshly resolve and
attach both states. Reset drops pending rewards and resets combat/AI while preserving
owned/equipped items. Neither input is a victory shortcut.

The optional validated runtime `signature` configuration contains the eight effective
attack values. It is deep-copied and frozen per combat state. No controller contains
an ability-granted flag or a second damage implementation. `attack_binding` is the one
mutable attack selection; the legacy `heavy` property is derived from it.

## Presentation and anatomy boundary

`fighter_visual.gd` contains the extracted sword poses and a curated extending-bone
pose. It reads phase/progress; it cannot determine hit timing. `Fighter` retains its public
pose node references and the old QA sync alias so existing timing instrumentation still
inspects actual transforms. Runtime callers use the public `sync_visual()` boundary.
The lunge uses the same analytic forward volume and obstacle ray as the sword, with its
validated reach/width. Named environment/fighter layers replace touched numeric masks.

The ivory bar/forks and mirrored sword are a **temporary visual projection of the shared
build's equipped Marrow Arm**, not an anatomy graph, extra limb, new equipment database,
or modified hurtbox. Movement/camera anchors and the existing capsule are unchanged.
The isolated anatomy library is not read during combat. Future anatomy integration should
replace these visual attachment points with its capability-resolved `bone_tip`/`grip`
origins, while continuing to resolve stats/abilities through the same build adapter.

## Verification

```sh
BONESHED_GRAPHICAL_TIMEOUT=900 bash scripts/tooling/test.sh artifacts/native-fresh
bash scripts/tooling/test_builds.sh artifacts/builds-fresh
bash scripts/tooling/test_anatomy.sh artifacts/anatomy-fresh
bash scripts/tooling/test_worldgen.sh artifacts/worldgen-fresh
bash scripts/tooling/test_web.sh artifacts/web-fresh
BONESHED_GRAPHICAL_TIMEOUT=900 bash scripts/tooling/test_marrow.sh artifacts/marrow-fresh
```

The native graphical runner explicitly selects the original courtyard scene; its
ordinary-combat trace and strategy checks remain intact. The new runner loads the
**shipped playable scene** and uses physical-key/mouse `InputEvent`s, with AI active and
without editing positions, health, combat state, inventory or rewards. Its bot reads attack
timing to select inputs. It captures eight milestones, two 30 fps attack sequences and
per-physics-tick phase/pose/input traces; headless and rendered traces must match exactly.
Separate rule fixtures cover damage/posture, block/deflect/dodge, both wielders' reach,
cancellation in all attack phases, one contact, invalid data, victory gating, duplicate
claims, equip rollback, second-duel loss/win, and reset. Negative controls mutate victory
authority, duplicate ownership, lunge damage, hit consumption, and the actual bone-mesh pose (headless negative control, rendered positive).

See [executed evidence and limitations](evidence/first-playable/README.md). Automated
success establishes the loop's reachability and specified rules. **No human has yet
validated fun, readability, physical-device timing, high-refresh feel or balance.**

## Combat presentation follow-up

[Iteration 3](COMBAT_PRESENTATION_3.md) replaces the original poses and cleans up
the HUD/camera. The evidence below records the first-playable implementation before
that presentation slice; use the iteration 3 instructions and comparisons for current
readability evaluation.

## Known limitations and next playtest

- Primitive geometry and a telescoping bone, rather than a production character animation.
  The player's body can partially occlude close-range windups; orbit/lock behavior needs
  human assessment. The HUD telegraph supplements the pose but cannot prove readability.
- No sound, save file, unequip menu, arbitrary anatomy or additional enemy content.
- Recovery can be canceled into defense, consistently with the confirmed combat rule;
  whether that leaves enough commitment is a human tuning question.
- Existing player-first resolution, float rule timers, analytic hit volumes, implicit physics
  engine selection and 60 Hz camera behavior remain; no unrelated engine migration.
- llvmpipe timings are test-host observations, not desktop GPU performance measurements.

For the first human session, ask a new player to follow only the controls above. Record
whether they recognize and defend the lunge without prompting, understand acquired versus
equipped, find Q after N, and deliberately choose a sword attack versus the new thrust.
Also try guard/dodge cancels and R before salvage, after acquisition, and after equipping.
