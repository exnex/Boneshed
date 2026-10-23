# Adaptive Combat Lab 2 — Research Lab objects, distinct procedural fighting styles

**Status: experimental, isolated, separately selectable scene, awaiting Command Center review and owner playtest.**
Lab 2 replaces Lab 1's combat motion, camera, HUD and body-modification demo inside the same isolated scene. It imports
the Research Lab's real generated objects. Every number, threshold, archetype key, input and data shape below is
**Proposed / provisional**. Automated tests show the pipeline is consistent, the Lab data is truly consumed and the moves
are measurably different. They do **not** show that combat feels good. That is the owner's call.

Engine: Godot **4.7.2.stable.official.ed1daf0bf**, checked by the tooling and verified by checksum in
`bash scripts/tooling/setup.sh`. Renderer: GL Compatibility, the project default and unchanged.

**Unchanged:** `project.godot` and its default scene (First Expedition), `export_presets.cfg`, the Pages workflow, the
directional expedition, Melee Lab, Visual Showcase, the animation lab, production combat, shared build data, and the other
browser routes. Two tooling scripts change, and only for this lab's own route:
- `export_web_adaptive.sh` adds the vendored bundle to the Web include filter;
- `smoke_web_adaptive.py` checks that the bundle verifies in the browser.

The showcase's rig, character builder, mesh kit, pose modifier and materials are reused **read-only**.

## 1. Play

```sh
bash scripts/tooling/setup.sh                          # once: verified Godot 4.7.2 + Xvfb
bash scripts/tooling/play_adaptive_lab.sh              # GL Compatibility
bash scripts/tooling/play_adaptive_lab.sh --forward    # Forward+ for this run only
bash scripts/tooling/play_adaptive_lab.sh -- --player=objects/umbrella.json --soul=objects/hinged.json --player-graft
```

In the editor, open `scenes/adaptive_combat_lab.tscn` and press **F6**. F5 still runs First Expedition. The browser route
is `/adaptive-combat/`; Command Center deploys it.

| Input (proposed) | Meaning |
| --- | --- |
| Click | Capture the mouse. **Esc** frees it. |
| Mouse / wheel | Orbit / zoom (smoothed, 2.2–7 m). The spring arm retracts in front of pillars. |
| Q / Tab | Optional lock-on. While locked, moving the mouse overrides tracking for 0.8 s. |
| WASD | Move, relative to the camera. Unlocked, you face where you move. |
| LMB / J | **Light**. Press again late in a strike to continue the object's combo. |
| MMB / F / K | **Heavy**. After a light, this is the **finisher** that continues from where that light ended. |
| RMB / L (hold) | **Guard**. A fresh press opens the object's deflect window. |
| Space | Dodge. Invulnerable from 0.04 to 0.3 s. |
| 1–6 / Shift+1–6 | Your / the soul's Lab object, in manifest order: umbrella, shovel, double-ended, organic, hinged, awkward. These are inspection names for the files only; nothing reads them. |
| O | Your object source: **Lab import** (default) or the v0 GDScript generator (comparison and fallback). In v0 mode, 1–5 pick recipes and V cycles seeds. |
| B / N | Toggle the illustrative **marrow graft** on you / on the soul. |
| G | Give your object a decoy name. Behaviour must not change. |
| M · R | Soul AI: aggressive / defensive / passive dummy · reset |
| H · F2 · F3 · F4 · F5 · F6 · T | Help · solver and stats panels · grip/contact overlay · slow motion · combat log · planned contact paths · trails |

**Default HUD.** It shows only:
- your health and posture, plus one line naming your object's mass, hold and move chain (bottom-left);
- the soul's health and posture (top-centre);
- the lock-on reticle;
- a faint "H help · F2 details" hint.

Every developer layer is hidden until you toggle it. Default HUD controls cover about 3 % of the screen (tested).

## 2. Research Lab integration (what the game really consumes)

**Source.** Research Lab [PR #67](https://github.com/exnex/ai-game-dev-lab/pull/67), merge commit
`64bc5124d7307a8e010212c7f686e1a8065b0cbe`. Lab main was rechecked at `49da8d1738…`, and its export files are unchanged since
then. Contract: **`lab.boneshed.object_export.v1`** (`urn:lab:boneshed:object-export:1`). Generator:
`lab.boneshed.object.sha256.v1` at source commit `43f2430…`.

The 18 files of `03-programming/boneshed-content/results/export-v1/` are vendored **byte-identical** in
`data/adaptive_lab/lab_export_v1/`:
- 6 objects;
- 9 invalid exports;
- `manifest.json`, `pack.json`, `schema.json`.

`data/adaptive_lab/lab_import_pin.json` pins the following:
- the manifest's SHA-256 (`fa8d3149…`);
- the catalog digest;
- the six generator source-file hashes;
- the records the Lab's own `object_export.py check` accepted at that commit (Python 3.13.16: 6 accepted, 9 rejected).

### 2.1 Import boundary — `lab_import.gd` + `strict_json.gd`

Each check in this table rejects the record outright. The game never uses part of a rejected record.

| Step | What is checked |
| --- | --- |
| Bundle | The manifest's raw SHA-256 equals the pin. Every file's raw SHA-256 equals its manifest entry. |
| Strict decode | Godot's JSON reads every number as binary64 and keeps the last of duplicated keys, so a game-side preflight decoder is used instead. Integers are kept exactly in 64 bits; overflow, floats, duplicate keys and trailing data are refused. |
| Schema | Closed field sets, types, ranges and enums of the export, the descriptor, materials, parts and grips. The seed must be a decimal **string**. |
| Lab structural rules | Unique ids, exact material id and revision, one root, existing parents, no cycles, anchors inside part and parent, overlapping attachments, cardinal joint axes, ordered limits, a round primitive's axis as its longest side, and `start < end` grip intervals on prismatic parts. |
| Descriptor digest | **Recomputed natively.** The game reimplements the Lab's canonical JSON (sorted keys, compact, ASCII, record arrays sorted by canonical bytes, integer vectors in order) and hashes it with SHA-256. All six equal the Lab's `descriptor_sha256`. |
| Physical block | **Recomputed natively**, with the Lab's exact integer formula (`objects.properties`: π approximations and Python floor division). The result matches mass, centre of mass, part volumes and the inertia proxy strings. |
| Provenance | Repository, generator commit, producer and the source cohort's hashes equal the pin. |
| Recipe authenticity | The game cannot re-run the Lab generator. A record's (id, digest) must therefore be one of the records the Lab's `check` accepted at the pinned commit. This is a transported trust decision, not a re-derivation. |

**Result:** all six objects are accepted. The nine invalid exports are rejected for their own reasons: forged mass, forged
provenance, forged recipe with a valid hash, missing material, missing parent, numeric seed, reversed grip, unknown field,
unknown version. A renamed or hand-edited export fails the digest check.

**Preserved** on each imported object:
- the full id, revision, decimal seed text and its exact integer;
- assembly, generator, source pack and catalog digest;
- name and description, as UI text;
- materials in SI and as the original integers;
- every part with its parent, joint, lock state, anchor, axis, limits and edge radius;
- every declared grip interval;
- the physical block, with the inertia strings kept;
- provenance, the raw file hash, the manifest hash, the Lab commit;
- the complete original decoded record.

**Conversion.** The Lab frame (+Y up, −Z forward) is Godot's frame, so only units change: mm → m, µm → m, mdeg → rad,
MPa → Pa, kPa → Pa, g → kg. Centres and anchors stay object-local; parent translations are never accumulated. Grip interval
endpoints follow the Lab reference projection exactly, to within 10⁻⁶ m (tested).

### 2.2 What the game consumes, and how faithfully

| Lab data | Used for | Status |
| --- | --- | --- |
| `box` parts | Exact mesh. Thin plates become two faces plus free edges; bars become free ends; broad plates become guard covers. | supported |
| `rod` parts | Exact elliptical-cylinder mesh; free axial ends become contacts. | circular: supported · elliptical: **approximated** (contact uses the larger radius) |
| `cone` parts | Exact elliptical-cone mesh. The tip is a **point** when width × 4 ≤ length (the Lab's own `point_thrust` rule). | supported (sharpness scalar is game-side) |
| `ellipsoid` parts | Exact scaled-sphere mesh; mass contact. | **approximated**: contact sphere of the largest semi-axis |
| `materials` | Mass is the Lab's per-part mass. Rigidity uses the Lab's `_rigid` rule (stiffness ≥ 1000 MPa, toughness ≥ 5000 kPa, no flex or unlocked hinge up the parent chain). Colour comes from `color_rgb`. | supported. A game-side **hardness** (log-stiffness) is used for damage and absorption. The Lab defines no hardness, so this is a game choice. |
| `edge_radius_um` | A cutting edge is a box ≤ 4 mm thick with an edge radius ≤ 250 µm (the Lab's `edge_sweep` rule). The shovel's 5 mm radius therefore makes its blade blunt. | supported |
| `joint` / `locked` / anchor / axis / limits | Fixed and locked parts are rigid. **Unlocked hinge / flex** parts are drawn under their own pivot and swing in presentation only, within the limits. They never get rigid contact, cover or grasp. | **approximated** (presentation-only dynamics) |
| `grips[]` intervals | The **only** grasp regions. Hand centres stay a palm half-width inside them. Hands may slide within them during thrusts (the object slides through the hands). | supported |
| Zero grips (awkward) | Imported and drawn, lying beside its owner. Never held. The fighter falls back to its own anatomy (fists, shoulder). | supported |
| Compliant canopy on rigid ribs | Guard cover, plus a posture-pushing face (a little blunt force through the ribs). Never cuts or pierces. | **approximated** (the Lab has no deployment parameters, so none are invented) |
| `physical.mass_g`, `center_of_mass_mm` | Reproduced exactly; point-mass samples carry the Lab per-part masses. | supported |
| `inertia_proxy_g_mm2` | Preserved as text and as converted floats. Timing and dynamics use the game's own point-sample inertia about the hands. | kept but **not** used for motion. The test reports both values; they rest on different assumptions (box envelope vs samples). |
| `name`, `description`, `assembly`, filename | HUD and provenance only. | never read by the solver, motion, rules or AI (source scan plus decoy swap tests) |

**Solver differences versus the Lab's experimental Python solver** (not ported):
- *Rigidity, edges, points and grip intervals:* the same rules on the same fields.
- *Contact:* swept capsules of features and the haft, versus the Lab's axial end points.
- *Guard:* thin broad boxes only; the Lab also counts shafts and bulbs ≥ 6000 mm² as block surfaces, and the game covers those with shaft guards.
- *Strength limits:* game body data, versus the Lab's measured hands.
- *Motion:* the game samples real IK motion; the Lab checks one static ready pose.

### 2.3 Fallback

The game's v0 GDScript generator (`object_generator.gd`, `boneshed.adaptive_object.v0`) stays selectable with **O**. It runs
through the same solver and motion, as a comparison and rollback. It is never used to reconstruct a Lab object.

## 3. Procedural fighting styles

### 3.1 Pipeline

```
Lab export ─► lab_import.gd (verify) ─► lab_analysis.gd ─┐        v0 generator ─► object_analysis.gd ─┐
                                                          ▼                                            ▼
                                 affordance_solver.gd: holds in grip intervals → physics per hold (inertia,
                                 swing/push load, wrist roll, heft, head) → archetypes granted by geometry →
                                 timing, damage, fitness → motion keys built + whole action validated →
                                 combo graph (light chain, neutral heavy, finisher per chain step), guard
                                          │ sampled by both ▼                        ▼
                     adaptive_fighter.gd (shared rules)                adaptive_actor.gd + adaptive_pose.gd
                     contact windows, haft, spacing footwork,          rig IK onto the slid grips, planted feet,
                     hook pull, modifiers                              hinge swing, glow/trails, overlays
```

### 3.2 Authored vocabulary (`motion_library.gd`)

There are 13 archetypes. Each is a set of keys per phase (windup / active / recovery). A key sets:
- the hold centre, for one-hand and two-hand holds;
- the strike direction;
- the leading-surface orientation;
- torso yaw, lean, roll and crouch;
- root travel;
- grip slide.

| Archetype | Path | Granted only when (measured) |
| --- | --- | --- |
| thrust / **lunge** (heavy) | Straight drive. The object slides through the hands; the lunge has a deep crouch and a 0.7 m+ committed step. | The object's leading point, end or edge along the hold axis faces forward, nothing broad sits within 6 cm behind it, and it is ahead of the lead hand. |
| sweep / **backhand** | Horizontal arc, right→left / left→right. | A rigid surface at the far end; inertia and wrist roll within the body's limits. |
| overhead | Raised chop, top→down. | Same as sweep. Preferred for mass toward the head (head × heft) and for off-axis mass. |
| rising | Low→high. | Same as sweep. |
| rear | The short end rises across. | Two hands, and a strikable feature ≥ 0.15 m behind the rear hand on the *short* end. |
| bash | Broad face pushed forward. | A face ≥ 6000 mm² whose normal lies along the hold axis. Drag slows it. |
| hook | Reach over, then pull back. On contact it **drags** the target. | A rigid protrusion near the far end, on **one side** of the hold line (a branch, not a symmetric canopy or blade). |
| **windmill** (heavy) | A full rotation: the lead end lands, then the rear end. Two contact windows. | Spread two-hand hold, swing load ≤ 0.25, strikable features at both ends. |
| shove | The shaft between spread hands pushed crosswise (posture only). | Spread two-hand hold. |
| jab / cross / **barge** | Fists and shoulder. | No legal hold (anatomy only). |

**Physics shaping.** The solver measures two quantities per hold and action:
- **heft** = max(inertia / limit, mass / limit), clamped to 0–1;
- **head** = how far the centre of mass sits toward the striking end.

`build()` uses them to shape the authored keys:
- **coil:** deeper windup and more trunk turn;
- **overshoot:** a swing carries past the target;
- **sag:** a heavy head drops low early in the recovery;
- **tempo:** heavy windups ease in slowly and actives accelerate; light ones snap.

The rules use heft too:
- chain and finisher input opens later in the recovery;
- a dodge can cancel the recovery later.

Broad surfaces moving face-first pay **drag**. Heavy variants coil deeper, step further and commit longer.

**Footwork.** Feet come from the keyed root travel: the lead foot arrives early, the rear foot follows late, and each
stride is capped at 0.3 m. So feet stay planted while the fighter travels.

**Combo graph.** The light chain is a walk:
1. open with the strike that starts best from the ready pose;
2. then repeatedly take the strike that continues best from where the previous one ended (exit/entry tags: right, left,
   high, low, centre), discounting immediate repeats;
3. special-structure strikes (bash, hook, rear end, windmill) get a small preference.

The neutral heavy prefers an archetype the chain does not already repeat. Each chain step has its own **finisher**: a
heavy whose entry continues from that step's exit.

### 3.3 What the solver derives for the six Lab objects (pilgrim body)

| Lab object (file) | Physics | Light chain | Heavy · finishers | Guard |
| --- | --- | --- | --- | --- |
| umbrella (1.99 kg, canopy 0.61 m² on metal ribs) | heft 0.65, head 0.85 | **canopy bash** → rib-tip sweep → rib-tip backhand (opposite rib) | overhead rib slam · after the bash: **heavy canopy bash** | **canopy cover** (wide arc) |
| shovel (2.12 kg, 3 mm blade, 5 mm edge radius = blunt) | heft 0.86, head 0.66 | blade-edge sweep → backhand (other edge) → sweep, i.e. pendulum chops | **overhead chop** | shaft cross guard |
| double-ended (0.49 kg, 1.1 m) | heft 0.04 | **rear-end strike → lead-end sweep → rear-end strike**, alternating ends | **windmill** (both ends, two hits) | shaft cross guard |
| organic (2.78 kg: tip cone, transverse branch, bulb) | heft 0.53, wrist roll 2.4 N·m | tip thrust → sweep → tip thrust | overhead (mace) · after a thrust: **hook** (pulls) | shaft cross guard |
| hinged (1.18 kg; organic tip; *unlocked* metal panel) | heft 0.17 | **tip thrust → tip thrust → butt strike** | **lunge** (≈1 m gap closer, pierce) | shaft cross guard |
| awkward (30.4 kg soft bulk, **zero grips**) | — | bare-handed jab → cross → jab | shoulder **barge** | forearm guard |

The awkward object lies beside its owner, since this body cannot hold it. The hinged panel visibly swings, but it never hits
and never guards. The umbrella cannot thrust: its crown nub sits 2 cm in front of the canopy (`thrust_blocked_by_broad_part_behind_tip`).

## 4. Heavy-attack misses: diagnosis

`scripts/qa/adaptive_lab_heavy_diagnostic_lab1.gd` runs against **Lab 1's own code** (`BONESHED_BASE_REF`, default
`origin/main`) in a disposable worktree. Each Lab 1 object fires one heavy at a passive target from 0.9 to 2.3 m, and every
tick of the active window logs the swept feature capsule's closest gap to the body.

Lab 1 result: **6 of 32 heavies whiff**. There are two causes:

1. **Footwork stepped away from close targets.** The double-ended pole at 0.9 m backstepped 0.37 m, and its lead cap passed
   0.12 m beyond the body.
2. **Heavies were chosen at light reach.** The gnarled root's heavy sweep reaches 1.35 m, shorter than its light chain.
   The AI launched heavies whenever the *light* reach covered the gap, and footwork could add only 0.37 m. The head then
   passed 6 to 65 cm short. At 6 cm a swing reads as contact on screen while the rules correctly say "miss".

A third pattern exists only in the new long objects, so Lab 1 had nothing to show: at point-blank the **shaft** visibly
passes through the target while only the far-end feature is tested.

**Fixes (no hitbox was enlarged):**
- Footwork is continuous. It travels so that the measured reach lands 0.12 m inside the target. Reach means the farthest
  body-centre distance that still touches, accounting for off-centre contact on a round body, with the authored travel at
  that same instant, for the **shortest** contact window of the action. The adjustment is complete when the first window
  opens.
- The AI chooses a heavy only within that heavy's own reach plus footwork.
- **Haft contact.** For swings, the visible shaft from the striking hand to the feature is a second capsule. It is tested
  only when the feature misses, and lands as a glancing blow (40 % damage, 60 % posture).
- Every attack that ends without contact logs a `whiff` event with its closest gap (F5 log; F6 draws the planned contact
  path over the scene).

Lab 2 result: every heavy of the five held Lab objects connects from 0.9 m out to its reach (tested at 0.2 m steps).
Out-of-reach heavies whiff with a reported gap. Heavies dodged inside the invulnerability frames are `evaded`.

## 5. Body modification: illustrative marrow graft

This replaces the Lab 1 "Marrow Arm". That prototype removed the hand, and the owner rejected it as an item concept. The
graft (`bodies.json → marrow_graft`) is **illustrative only**: the name and numbers are not approved.

- **Keeps the hand.** It gives the same holds and the same moves for every object (tested).
- **Benefit:** after 1.5 s without damage, +1.6 HP/s regeneration, shown as a green glow at the left hand.
- **Drawbacks:** ×1.25 damage taken, ×1.35 posture (stagger) damage taken, ×1.3 stagger time.
- Shared rules: the soul with the graft regenerates and suffers the same way.

The visual is bone ridges and marrow along the left forearm, skinned to it.

Genuine anatomy restrictions still exist. The test-only `handless_limb_example` removes a hand, and its grips become
illegal (`two_hand_requires_missing_hand`). Only a modification whose anatomy really lacks a grasping structure changes
what can be held.

## 6. Tests and evidence

```sh
bash scripts/tooling/test_adaptive_lab.sh                         # everything, incl. rendered evidence
BONESHED_SKIP_RENDER=1 bash scripts/tooling/test_adaptive_lab.sh  # headless parts only
BONESHED_LAB_REPO=../ai-game-dev-lab bash scripts/tooling/test_adaptive_lab.sh  # + the Lab's own check of the vendored bytes
bash scripts/tooling/export_web_adaptive.sh /tmp/web && python3 scripts/tooling/smoke_web_adaptive.py /tmp/web
```

`scripts/qa/adaptive_lab_tests.gd` holds the checks listed in the PR. The runner:
- replays them in a second process; `results.json` and a 20 s AI-vs-AI duel log must be byte-identical;
- applies six source mutations in a disposable copy; each must fail its named check:
  - the name changes strength,
  - contact is moved off the object,
  - the fist is moved off the grip,
  - heft is ignored,
  - grips are resampled from the whole rod instead of the declared intervals,
  - bang-bang footwork;
- runs the Lab 1 diagnostic against the base ref;
- renders the evidence.

Evidence lives in [evidence/adaptive-combat-lab-2/](evidence/adaptive-combat-lab-2/README.md).

## 7. Known limitations (honest)

- **Feel is unproven.** Keys, timings, damage and the selection weights are authored and formula-driven. None has been
  playtested. The selection weights (fitness, flow, special-structure preference, heavy contrast) are heuristics that
  decide which legal strike leads, and small data changes can reorder a chain.
- Posing is procedural: rigid trunk, two-bone IK arms, planted feet. There are no authored clips, finger poses or wrist
  limits. Feet can still slide a little when a stride is capped.
- Contact is swept capsules (feature plus haft) against one body capsule. Objects do not collide with each other, and the
  hinged panel has no contact at all.
- The umbrella canopy is the Lab's flat soft square, drawn as a thin board. Nothing deploys or folds, and drag is a simple
  area term.
- Recipe authenticity is transported from the Lab check (pinned digests), not re-derived in the game.
- The game's inertia (point samples) and the Lab's inertia proxy (box envelopes) differ by design. Only mass and centre of
  mass are required to agree.
- Solve cost is roughly 0.1–0.3 s per object and body on this cloud CPU (llvmpipe), so results are cached per structure and
  body. It is slower in the browser and not yet measured there. The rules tick costs about 0.2 ms.
- The AI is simple and seeded, not a tuned opponent.

## 8. Owner playtest guide

1. Open the scene (or `/adaptive-combat/` once deployed). Press **M** until the soul is *passive*. For **2** shovel,
   **1** umbrella, **3** double-ended and **5** hinged, do the same thing:
   - LMB three times (pressing late in each strike);
   - pause;
   - MMB;
   - then LMB followed by MMB, for the finisher.

   Do the windup poses, paths, which part hits, the combos and the recoveries look like different things?
2. Press **6**. The awkward object cannot be held: do bare hands read as a sensible "this thing is useless"?
3. Press **Q** and fight the *aggressive* soul with lock on, then unlocked. Is the free camera easy to control? Does the HUD
   stay out of the way?
4. Try heavies at close range and at the edge of reach. F6 shows the planned contact path and F5 logs `whiff` with the
   closest gap. Report any heavy that *looks* like contact but logs a whiff.
5. Press **B** for the graft. Take a hit, back off and watch the regeneration. Compare how far a hit staggers you with and
   without it.

## 9. Roadmap / status delta (for Command Center to reconcile)

`docs/ROADMAP.md` is a coordination file, so this PR does not edit it (AGENTS.md; the lab runner's isolation guard). The
proposed delta:

- **Implemented (experimental, isolated):**
  - the Research Lab export v1 (Lab `64bc512`) is vendored, verified and consumed: native digest and physical
    recomputation, strict decoding, 6 accepted / 9 rejected;
  - Lab objects drive meshes, grips, contacts, covers and physical inputs;
  - a 13-archetype vocabulary with physics shaping, combo graph, finishers, haft contact and continuous footwork;
  - orbit camera with optional lock-on;
  - minimal HUD with debug toggles;
  - heavy-miss diagnosis and fixes;
  - illustrative marrow graft with benefit and drawbacks;
  - Web route kept.
- **Not implemented:**
  - owner feel acceptance;
  - authored animation clips;
  - object–object collision;
  - canopy deployment;
  - re-deriving Lab recipes in the game;
  - shared-build/catalog integration;
  - classification and synergies (a separate future milestone);
  - browser performance measurement.
- **Next gate:** owner playtest of the five held Lab objects and the awkward one, using §8.
