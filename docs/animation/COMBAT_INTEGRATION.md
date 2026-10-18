# Weapon/body collision model and the minimum integration contract

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). **Research and
proposal only. No live courtyard, combat, camera, player, AI or HUD file was changed.**

## 1. Today

`Fighter.valid_attack_target()` uses one rule-owned oriented box in front of the attacker
(`attack_range` × `attack_width` + 0.35 m target radius, ±1.5 m vertical) and an
environment ray. `resolve_attack()` runs only in `Phase.ACTIVE`, and at most once per swing
(`hit_consumed`). Guarding is a facing dot product against `guard_arc_cos`. Presentation
(`fighter_visual.gd`) reads phase and `remaining` and never decides hits. This is the right
authority model; keep it.

## 2. Collision options

| Model | Fidelity to the visible blade | Determinism / server replay | Tunnelling risk | Cost | Verdict |
| --- | --- | --- | --- | --- | --- |
| Rule box (current) | Low: the hit can land where no blade is | Exact | None | Trivial | **Keep as the authority** until a baked trace is validated |
| **Baked blade trace** (blade base/tip sampled from the authored clip at rule time, stored as data, swept against target capsules) | High for the authored motion | Exact: pure data and maths (lab trace reproducible to < 0.1 mm) | Low if baked at ≥ 60 Hz and swept (lab: 10/10 poles) | Bake per (clip, timing) pair; tiny data | **Recommended next authority** |
| Live weapon-edge sweep from the posed skeleton each tick | Highest, including blends and IK | Depends on animation state, blends and frame rate; not server-replayable | Point sampling at 30 Hz hit **0 of 10** thin poles; linear sweep at 30 Hz hit 9 of 10 | Per-tick queries | **Presentation and debug only** (sparks, trails, clash VFX) |
| Bone-following hurtboxes (capsules on `BoneAttachment3D`s) | High for limbs and big parts | Replayable only if poses come from data | — | Several shapes per fighter | **Later**, for parts with hurt classes (ANATOMY.md). The core hurtbox stays a capsule on the core anchor |
| Physics `ShapeCast3D` / `Area3D` on the blade | High | Physics-tick-bound; overlap-only areas tunnel | High without sub-steps | Medium | **Not recommended** for authority |

**Tunnelling:** the trial slash's tip peaks at **47 m/s**. At 30 Hz that is about 1.6 m per
tick. Measured on the real slash with poles placed *between* 60 Hz samples on the true arc:
- point sampling at 30 Hz: **0/10** hits;
- linear sweep between 30 Hz samples: **9/10** (the chord cuts inside the curved arc);
- linear sweep over the **60 Hz baked trace**: **10/10**.

Sweep a densely evaluated trace (evaluate the clip at sub-steps, which is cheap from data)
rather than interpolating sparse poses linearly.

## 3. Damage timing stays authoritative

1. Rules own the clock. `CombatState` decides when a swing is in `active`.
2. Presentation maps rule time onto clip time through markers
   ([`phase_warp.gd`](../../scripts/animation_lab/phase_warp.gd)), so the clip's `contact`
   pose lands on the first live tick (measured: 9–11 ms, under one 60 Hz tick).
3. Contact *geometry* comes from data: the baked trace for that clip at that timing, in
   attacker-local space, gated by the rule window (`live`). The visual pose never decides
   damage. If IK, blending or hit-pause moves the rendered blade, damage is unchanged.
4. Hit-stop, flinches and clash VFX are applied *after* resolution, from the rule result.
5. Animation markers and method tracks may trigger **cosmetic** events (whoosh, footstep,
   spark), never damage.

## 4. Minimum integration contract for Codex (proposed, not approved)

Each step is its own PR, and each keeps the existing tests green.

**Step A — presentation only, no rule change.**
- Add `AnimatedFighterVisual`, a peer of `fighter_visual.gd`, selected by data. It reads
  only what the primitive visual reads: `combat.phase`, `combat.remaining`,
  `combat.attack_stage()`, the timing of the current attack (`windup_duration()`, active,
  recovery, `commitment_duration`, `release_duration`), `guarding`, the last result,
  the event serial and the facing.
- It calls `PhaseWarp.rule_time_from_phase(phase, remaining, timing)` and then
  `PhaseWarp.sample(markers, timing, t)`, and seeks the action clip. Locomotion comes from
  the planar velocity, with playback rate = speed ÷ stride.
- **Never** writes `CombatState`, never calls `resolve_attack`, never moves the body.
- Acceptance: the existing combat and graphical suites still pass unchanged. A new test
  asserts the contact marker is on the first `ACTIVE` tick for every attack module.
  Rendered evidence is produced with the lab's director pattern.

**Step B — baked traces as data, validated against the box.**
- An editor/QA tool bakes `data/traces/<module>.<timing>.json` (lab format:
  `t`, `live`, `base`, `tip` in attacker-local metres).
- In shadow mode, combat evaluates the trace sweep **alongside** the box and logs any
  disagreement. The box still decides.
- Acceptance: the disagreement rate across the courtyard probe suites is reported. A human
  decides whether to switch.

**Step C — switch authority (only after human approval).**
- `valid_attack_target` uses the swept trace against the target's core capsule (and part
  hurtboxes once anatomy is integrated). Keep the LOS ray and one hit per swing.
- Tower and server validation re-run the same trace, which is pure data.

**Interfaces Codex needs from the animation side:** per attack module, a clip name,
`markers` (six names), the blade base/tip offsets, and the baked trace per timing. Per
fighter, a stride table and a list of clip names.

**What Codex must not need:** AnimationTree internals, bone names (except via the
manifest), or root motion from the mixer.

## 5. Known engine behaviours that shape the contract (Godot 4.7.2, lab-verified)

- `AnimationMixer.get_root_motion_position()` returned the **opposite sign** when the clip
  was driven by a per-frame `AnimationNodeTimeSeek` plus `advance(delta)`; magnitude was
  correct. Free play gave the correct sign. Rules should read authored root curves as data.
  Not root-caused; a tripwire test will flag a behaviour change on engine upgrade.
- `SkeletonModifier3D` output (IK) is visible through `BoneAttachment3D` and
  `skeleton_updated`, but not through `get_bone_global_pose()` outside the update. Weapon or
  hurtbox readers must choose deliberately.
- `MeshInstance3D.new()` has an empty `skeleton` path. Code-built skinned parts must set it.
