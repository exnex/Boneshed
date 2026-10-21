# Directional expedition — procedural expedition played with directional melee

**Status: experimental, separately selectable integration scene awaiting Command Center
review and owner playtest.** Owner authorization: [NEXT_DEVELOPMENT_PLAN.md — "Owner
authorization: directional combat in procedural expedition", 2026-10-21](NEXT_DEVELOPMENT_PLAN.md).
It does **not** change the default scene (`first_expedition.tscn`), the Web/Pages root,
the [expedition preview](EXPEDITION_PREVIEW.md), the [directional melee lab](DIRECTIONAL_MELEE_LAB.md)
or production combat. Every number, encounter assignment and mapping below is
provisional; nothing here approves a balance, inventory, extraction or economy rule.

Engine: Godot **4.7.2.stable.official.ed1daf0bf** (checked by the tooling), GL
Compatibility, Linux x86_64. Built 2026-10-21.

| Section | |
| --- | --- |
| [1. Play](#1-play) | Commands, browser path, controls |
| [2. What is integrated](#2-what-is-integrated) | Which system decides what |
| [3. Architecture](#3-architecture) | Files, step order, isolation |
| [4. Builds, encounters and the Marrow Lunge](#4-builds-encounters-and-the-marrow-lunge) | Shared data → directional fighters |
| [5. Preserved expedition behaviour](#5-preserved-expedition-behaviour) | What carried over unchanged, what adapted |
| [6. Tests and evidence](#6-tests-and-evidence) | Commands, results |
| [7. Known issues and limitations](#7-known-issues-and-limitations) | |
| [8. Owner playtest guide](#8-owner-playtest-guide) | |

## 1. Play

```sh
bash scripts/tooling/setup.sh                      # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/play_directional_expedition.sh
```

In the editor, open `scenes/directional_expedition.tscn` and press **F6**; **F5** still
runs First Expedition. The selection screen is the preview's (same keyword lists, seed
replay, older-address replay), retitled **Directional Expedition**. Fixed fixtures:
**Drowned / Hollow / Cathedral, seed 1001**; **Smoldering / Pallid / Necropolis, 7**;
**Frozen / Gilded / Citadel, 1002**.

**Browser (after merge only):** the existing Pages workflow now also exports this
scene from a disposable copy (`scripts/tooling/export_web_directional.sh`), smoke-tests
it in Chromium and publishes it at **`/directional-expedition/`** beside the unchanged
root game and `/melee-lab/`. Nothing is published from this branch; the hosted path
exists only once Command Center merges and the workflow succeeds.

### Controls

The melee lab's approved controls, unchanged (they come from the same
`lab_player.gd`/`lab_input.gd`), plus the expedition keys. F1 shows them in game.

| Input | Action |
| --- | --- |
| WASD · mouse | Move (camera-relative) · orbit the camera |
| **LMB press / hold + mouse / release** | Start a cut immediately; while held the mouse moves the aim cursor (right, up-right, up, up-left, left = chamber side; down = thrust) and the chamber is held **indefinitely**; release commits. A tap is the natural follow-up cut. Changing to another side re-chambers through the **forward neutral** pose |
| **RMB hold + mouse** | Directional guard toward the mouse side (down = centre); held until released. A **fresh press** opens the deflect window and cancels an attack (an unreleased windup refunds half its stamina) |
| **Space · Shift** | Dodge step · dodge roll (both cost stamina; roll travels further with a vulnerable tail) |
| **Q hold / release** | Marrow Lunge, once the Marrow Arm is salvaged and equipped (§4) |
| Tab | Lock-on (engaged automatically when a soul rises) |
| F · E | Salvage the released soul · equip the Marrow Arm |
| R | Retry a duel in progress or a lost duel (full health, current build) |
| F1 · F2 · F3 · T · Y · U | Help · handling table · hitboxes · trails · telegraph arcs · intent labels |
| Esc | Expedition menu (resume, restart address + seed, return to selection) |

Pickups, the descent, portals and the extraction beacon need no key: walk onto them.

## 2. What is integrated

| Concern | Decided by (all fighters) | Old expedition used |
| --- | --- | --- |
| Attack direction, chamber, release, re-chamber, cancels | `melee_lab/duelist_state.gd` via `lab_player.gd` (player) and `lab_opponent.gd` (souls) | `CombatState` light/heavy timers |
| Contact (which blade touched what, when) | `melee_lab/contact_solver.gd` swept segments | `Fighter.valid_attack_target` box query |
| Damage, posture, stagger, deflect, block, bad angle, guard break, clash, evade | `contact_solver.gd` momentum model and armor mitigation | `CombatState.receive` |
| Weapon reach, mass, inertia, timing, guard strength | `weapon_handling.gd` from `resolved.equipment.weapons` (shared catalog) | fixed `SWORD_REACH` module |
| Stamina (attacks, dodge, roll, lunge), recovery, refusals | `duelist_state.gd` + `stamina_pool.gd`; costs from `combat_resources.gd derive` | none |
| Armor weight → speed, evasion cost/speed, regen; mitigation; resistances | `combat_resources.gd derive` | none |
| Poison, slow (buildup on routed contact, resistance, ticks, decay, immunity) | `status_effects.gd` through `receive_status` | none |
| Soul AI | `lab_opponent.gd` "duel": delayed (0.22 s) perception of drawn cues, `legal_actions()` before every press | `swordsman.gd` |
| Encounter outcome → salvage | `directional_progression.gd`: only a resolved lethal *contact* (hit / bad angle) that leaves the soul dead wins | `DuelProgression.record_contact` on `CombatState.DEFEATED` |

There is no `Fighter`, `CombatState`, `Swordsman`, `DuelProgression` or courtyard
adapter in the scene (tested), so no fighter carries a second HP/posture model and no
old rule resolves a hit behind the new visuals.

## 3. Architecture

```
scenes/directional_expedition.tscn → directional_shell.gd (extends preview_shell.gd: selection, pause, summary)
  └ directional_expedition.gd  (session: world, director, pickups, transitions, extraction, fixed step)
      ├ preview_builder.gd / expedition_plan.gd / prototype_satchel.gd   (preview, unchanged)
      ├ directional_adapter.gd     shared catalog + lab items + shared builds → fighter views
      ├ directional_progression.gd builds, stage, salvage/equip transactions (directional state)
      ├ expedition_player.gd       extends lab_player.gd   (+ Q lunge, doorway teleport)
      ├ expedition_opponent.gd     extends lab_opponent.gd (+ legal lunge use, post)
      │    both use expedition_state.gd (extends duelist_state.gd: + lunge) and
      │    expedition_visual.gd (extends lab_visual.gd: + bone arm/lunge)
      └ expedition_hud.gd          extends lab_hud.gd      (+ objectives, prompts, salvage card)
```

**Step order each physics tick** (the lab's, plus the expedition lifecycle first):
hotkeys → encounter director → pickups → transitions → extraction → player controller →
engaged soul controller → player rules + movement → soul rules + movement → contact
for the player's blade, then the soul's → status events → loss check. Dormant souls are
never controlled, stepped or resolved (tested: their rules clock stays at 0).

**Isolation.** No melee lab, expedition preview or production game script, scene or data
file was edited. Shared files touched: `scripts/qa/melee_lab_tests.gd` (allowlist below),
`.github/workflows/publish-web.yml` and `scripts/tooling/publish_web_dual.sh` (optional
third Pages path), `README.md`. The melee lab's
isolation test (`no_production_file_references_the_lab`) now names this integration as
its one authorized consumer (`LAB_CONSUMERS` in `scripts/qa/melee_lab_tests.gd`); every
other script and scene must still not reference the lab, and a new check asserts that
no script or scene outside the integration references it.

## 4. Builds, encounters and the Marrow Lunge

**Fighters come from the shared data.** The player is the shared
`data/builds/salvage_courtyard.json` player build; souls use its enemy build (profile
`profile.corrupted_swordsman`, 2.7 m/s) with per-encounter equipment. Builds are
first validated against the unmodified shared catalog, then resolved by
`build_rules.gd` against the shared catalog with the lab weapon items appended in
memory (exactly the lab's `lab_loadout.gd` path). Shared grip rules still apply (a
two-handed greatsword beside the handless Marrow Arm is rejected — tested). The shared
catalog has no armor category yet, so lab armor ids come from
`data/directional_expedition/encounters.json`, validated by `combat_resources.gd`.

| Fighter | Weapon / body | Armor | Effect on rules (derived, not authored) |
| --- | --- | --- | --- |
| Pilgrim (player) | Notched Sword (shared) | Mail shirt | attack 13.3, dodge 20.3, roll 33.0 stamina; 4.91 m/s; 15 % mitigation; 25 % poison/slow resistance |
| Exterior soul 1 (route sentinel) | Venom Knife + **Marrow Arm** | Cloth wraps | fast, short (1.45 m), cheap attacks; poison 35 buildup on hit |
| Exterior soul 2 (optional vigil, if the address generates one) | Notched Sword + **Marrow Arm** | Mail shirt | the classic corrupted swordsman |
| Guardian | Greatsword (two-handed) | Bog-iron plate | slow, heavy (73 kg·m²/s momentum — a block is overwhelmed, it must be deflected or evaded), slow buildup 55 on hit, 30 % mitigation, 60 % resistances, slower movement and costlier evasion |

Exterior souls cycle through the list by site order, so the sentinel on the route
always carries the salvageable Marrow Arm. Each soul's AI stream is seeded from the
plan fingerprint and site id: the same address + seed + inputs replays exactly.

**Marrow Lunge mapping.** The salvaged arm still grants the shared
`ability.marrow_lunge`. In directional rules it is an ordinary **thrust by the bone
limb**: `expedition_state.gd` swaps the state's handling and tuning to the bone's for
the duration of that one thrust, so the same windup floor, hold-to-release, contact
solver, guard/deflect/evade, stamina ledger and status routing apply.

| Lunge parameter | Source |
| --- | --- |
| Tip reach 3.4 m | shared ability `reach` |
| Readable windup floor 0.7 s | shared ability `windup` |
| Recovery 0.8 s | shared ability `recovery` (thrust retract) |
| Damage 26, posture 18 at reference momentum | shared ability `health_damage`, `posture_damage` |
| Bone mass 1.2 kg, balance 0.5 | integration data (placeholder) |
| Stamina 1.5 × the build's attack cost (20.0 for the pilgrim) | integration data (placeholder) |

The bone cannot guard or deflect, cannot be redirected into a sword cut, and its
handling is restored when the thrust ends for any reason (finished, cancelled,
interrupted, killed — tested). Souls whose build has the arm may open with it from
beyond sword reach through the same `legal_actions()` and cost (40 % chance per
opportunity, provisional).

## 5. Preserved expedition behaviour

Unchanged code paths (reused, not copied): keyword selection, seed replay and older
addresses (`expedition_select.gd` via `preview_shell.gd`); plan generation and
validation; world/dungeon building; gates; pickups and satchel; extraction summary.

Adapted to the new rules, same rules as the preview:

- Entering a site's 9 m radius engages its soul (guardian doors seal); a new duel cannot
  start while salvage is unclaimed. Leaving an exterior soul's 17 m leash disengages it
  **without healing** either fighter (tested). R retries a duel in progress or a lost one.
- **Prototype rule kept:** each new encounter starts both fighters from their current
  builds at full health, posture and stamina with no statuses. Transitions carry
  everything over (doorway moves only).
- Victory requires a resolved lethal contact; a debug write of death grants nothing
  (tested). F salvages the Marrow Arm reference (catalog-verified), E equips it after a
  finished duel, the equipped build remains a valid shared build, and Q then lunges.
- The guardian's victory opens both gates and the ascent; the reliquary and side cache
  are behind it; extraction lists finds, carried and equipped items and souls released.

## 6. Tests and evidence

```sh
bash scripts/tooling/test_directional_expedition.sh artifacts/directional-expedition
```

Runs, in order: import; parse check of every integration script; scene boot; the
fixture suite (`directional_expedition_tests.gd`, **94 checks**) and its replay in a
second process (results byte-identical); the input-driven playthrough headless and
rendered (traces identical) and replayed in a second process (trace and contact log
byte-identical); the same loop on three more addresses/seeds; contact sheets and MP4s
of both rendered duels; and four mutations in disposable copies, each of which must
fail its named check:

| Mutation | Must fail |
| --- | --- |
| Contact resolution removed from the controller | `cut_right_to_left_vs_guard_left_is_block`, `lethal_contact_releases_soul` |
| A second stamina charge added to `press_attack` | `lmb_press_charges_attack_once` |
| AI reaction delay set to 0 (omniscient) | `soul_sees_windup_only_after_reaction_delay` |
| Status routed on block | `guarded_poison_attack_applies_no_status` |

The fixture suite covers: shared build → fighter resolution and derived costs; lunge
rules (cost, floor, reach, restore, refund); scene composition (no legacy nodes, one
rules state class); directional geometry through real mouse input (cut vs matching
guard blocks, vs the opposite side hits, 45° neighbour blocks, out of reach never
connects; hit damage equals the momentum model × armor); stamina through real keys
(one charge per press, held chamber has no drain and waits indefinitely, neutral
re-chamber, feint refund, dodge/roll charged once, exhaustion refused not overdrawn, Q
without the arm does nothing); status (guarded attacks route nothing, hits apply
buildup after the soul's resistance, poison ticks on souls and cannot release them);
AI (perception delay, legality, derived costs, no player-state reads); encounters
(leash without healing, dormancy, gates, heavy guardian); progression integrity;
plan and duel determinism; and that First Expedition, the expedition preview and the
melee lab scenes still boot and run.

The playthrough bot uses only InputEvents (WASD, LMB/RMB, mouse motion, Space, Shift,
Q, F, E, R) and reads only visible cues (soul phase, drawn chamber direction, blade
angle/speed, guard side, outcome labels). It wins by holding the guard on the visible
side and re-pressing just before contact (deflection), then cutting into the opening.
That proves the loop is reachable with the new rules, **not** that the duels are fair
or fun for a human.

Results, captures and clips: [evidence](evidence/directional-expedition/README.md).

## 7. Known issues and limitations

- **Lab geometry, pre-existing:** the thrust line passes exactly blade + guard radius
  (0.08 m) beside the centre-guard blade, so *thrust vs centre guard* is decided by float
  rounding (the lab's rules-only exchange reports a block; in the expedition fixture it
  is a hit). Reported with a test that measures it; not changed here because the lab's
  rules are approved as-is. Suggested lab fix: a slightly wider centre guard or a
  smaller thrust lateral offset.
- A venom knife's short centre guard does not cover a sword thrust at 2 m (same cause).
- Presentation is the lab's capsule fighters and placeholder level; the Marrow Lunge is
  drawn as a pale bone segment from the grip (the sword mesh is hidden during it).
- One soul per exterior site, three loadouts; most fixture addresses generate only the
  sentinel, so the second exterior variant is rarely seen. No new enemy types.
- Full-health reset per encounter, no death penalty beyond retrying, no carry-over of
  statuses between encounters (prototype rule inherited from the preview).
- No world conditions (the lab's toxic miasma is not mapped to keywords); no shield.
- Souls steer directly; exterior duels have no gate and footwork can drift to parapets.
- The lab camera has no zoom and no shoulder-anchor wall check; corridor camera
  comfort is unassessed.
- The bot's deflection timing is near-perfect; human difficulty is unmeasured.
- llvmpipe rendering only; no GPU, physical mouse, audio or human playtest was run.

## 8. Owner playtest guide

1. `bash scripts/tooling/play_directional_expedition.sh` (or `/directional-expedition/`
   once merged and published). Replay **Drowned / Hollow / Cathedral, 1001**. Read F1.
2. Walk the surface: does camera-relative movement with the lab camera feel right
   outside duels? Try a held chamber, a re-chamber across sides and a dodge/roll while
   exploring, and watch the stamina bar and its cost ticks.
3. Approach the venom-edged sentinel. Block with RMB aimed at the side it chambers
   (its blade colour and arc show the side); try fresh-press deflections; let it hit you
   once and watch poison build on your bar. Does the knife feel fast but weak?
4. Win, press **F**, then **E**. Hold **Q** to chamber the Marrow Lunge and release it.
   Is the 0.7 s bone thrust readable and worth its stamina?
5. Enter the descent; dodge and roll in the first corridor. Fight the iron guardian:
   does blocking its greatsword break your guard (it should), do deflections and
   evasions feel like the answer, and does its slow buildup read? Note whether its
   plate makes it feel slow but tough.
6. Take the reliquary and side cache, ascend, extract. Then try **Smoldering / Pallid /
   Necropolis, 7** and a fresh seed.
7. Record: anything that felt unfair, unreadable or sluggish (especially camera in
   corridors and the guardian's tempo), whether stamina ever blocked an action you
   expected to work, and whether this should replace the preview's combat.
