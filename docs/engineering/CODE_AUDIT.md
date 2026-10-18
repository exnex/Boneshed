# Code Audit — Boneshed `main` at `3dbcc08` (2026-10-18)

**Scope:** every tracked `scripts/**/*.gd`, `scenes/courtyard.tscn`, `project.godot`,
`export_presets.cfg`, the tooling scripts, and the existing design and evidence documents,
reviewed against [GDSCRIPT_GUIDE.md](GDSCRIPT_GUIDE.md) and
[GODOT_DEVELOPMENT_GUIDE.md](GODOT_DEVELOPMENT_GUIDE.md).
**Method:** reading the code, plus four experiments in a scratch copy
([evidence](../evidence/engineering-audit/README.md)). **No gameplay code, data, scene or
project setting was changed.**

**Severity scale.** *Critical:* wrong behavior or a security hole now. *High:* likely to cause
a real defect in planned work. *Medium:* a structural risk that will cost time or correctness as
Boneshed grows. *Low:* hygiene and consistency.

**Overall assessment.** The codebase is small (~3,300 production lines), coherent and
well tested for a prototype. **No Critical or High findings in the reviewed startup path.**
The main risks are
silent string-keyed plumbing at module boundaries, implicit engine and ordering
choices, and a presentation layer that will have to move when real assets arrive. Earlier
agent-written code shouldn't be assumed correct, but most of this code's architectural
choices hold up against official Godot guidance.

---

## 1. Patterns implemented well (keep them)

| Pattern | Where | Why it's right |
| --- | --- | --- |
| Rules separated from nodes, input, AI and visuals | `combat/combat_state.gd` (typed `RefCounted`, no scene access) | Testable headless; both actors share one rule set; presentation reads phase and doesn't drive timing |
| Phase-duration accounting | `CombatState.tick` carries overshoot across phases | Preserves elapsed phase time; a large step can still skip the active hit sample |
| Hit invariants in the rules | `hit_consumed`, cancel-before-resolve in `_cancel_attack` | One hit per swing; a cancelled swing can't land late |
| Transactional preparation, fail-fast startup | `build_adapter.prepare_encounter`, `courtyard._ready` | Invalid data can't create a half-configured fight (tested via expected-failure subprocess) |
| All-or-nothing pure operations | `build_rules.equip/unequip/carry`, `anatomy_rules.transform` | The input is never mutated; errors return the original value |
| Strict JSON, ids only, no object deserialization | build, body and salvage loaders | Matches the official RCE warning for object decoding; server-checkable; the right base for the Tower |
| Frozen shared definitions | `_freeze` + `make_read_only()` in both catalogs | No consumer can corrupt a definition shared by player and enemy |
| Content fingerprints, separate gameplay/visual fingerprints | catalogs, `anatomy_rules.resolve` | Detect content mismatch, not authenticity; cosmetic changes can't alter combat identity |
| Engine-independent seeded streams, one per consumer | `worldgen/seed_stream.gd`, `blueprint_generator` | Reproducible across engine upgrades; adding a domain doesn't shift others (tested) |
| Deterministic output ordering | `catalog.slot_order`, `_sorted(...)` everywhere hashing or comparison happens | Doesn't depend on dictionary insertion order |
| No autoloads; parent wires dependencies | `courtyard.gd` sets `opponent`, configs, HUD `arena` | The official "call down" / dependency-injection pattern |
| Validation, isolation and QA tooling | `scripts/tooling/*`, `scripts/qa/*` | Checksum-pinned engine, external timeouts, fresh evidence dirs, **negative and mutation controls that must fail**, byte-regenerated examples, rendered captures, adversarial probe |
| Provisional status written at the value | file headers, tuning tables | Agents can't mistake tuning for approved design |

## 2. Findings

### F1 — Silent adapter assignments and default-masked coverage — **Fixed (was Medium)**

- **Original finding:** `Object.set()` silently ignored misspelled combat property names;
  8 of 20 source mutations passed the old integration suite because defaults matched data.
  This was a regression/coverage gap, not a demonstrated player-controlled exploit.
  [Original experiments](../evidence/engineering-audit/README.md#3-adapter-field-name-mutation-does-any-test-notice-a-dropped-field).
- **Fix:** `create_state()` validates the complete configuration (exact names, presence,
  numeric types, finiteness, supported ranges and incoming defense bindings), checks all
  target properties and their runtime types, then uses 20 explicit assignments on a typed
  `CombatState`. No dynamic `Object.set()` remains. Health resets after configuration.
- **Atomic preparation:** state construction now returns `{ok, errors, state}`; failure has
  `state: null`. `prepare_encounter()` constructs both actors before returning success and
  includes actor-specific `state_errors` on failure, with empty configs, resolutions and
  states. The courtyard attaches these prepared states only after preparation succeeds.
  Invalid second-actor state data exits 1 before creating input bindings, world or fighters.
- **Coverage:** 532 integration checks include changed, non-default inputs for all 20 fields
  in both profiles, both direct resolved-build construction and the real catalog-to-scene
  path, missing/renamed keys, invalid values, defense dictionary isolation and a behavioral
  `deflect_window = 0.11` check. The native runner also executes 63 isolated source mutation
  controls: 20 omitted assignments, 20 misspelled assignment targets, 20 renamed runtime
  properties, a mistyped runtime property, a translation-key typo and omitted resolver
  profile overrides.
  [Fix evidence and remaining limits](../evidence/combat-adapter-hardening/README.md).
- **Intentional dynamic data:** resolved JSON and the temporary configuration remain
  dictionaries to preserve the shared-build boundary. Generated attack keys are checked
  against the complete combat schema before use. `guard_posture_overrides` remains a
  dictionary because it is a sparse map of incoming `light`/`heavy` bindings to costs,
  rather than Object properties; its names and values are validated and it is deep-copied
  for each state. No dynamic property assignment is needed.
- **Remaining risks:** Godot 4.7.2 can defer even typed member-write checks until execution;
  typed syntax alone is not a compile-time guarantee. Property/type preflight protects
  runtime contract changes, while deliberate assignment typos are required to emit engine
  errors in the mutation controls. New parameters must update the schema, explicit mapping
  and value-changing matrix together. The adapter remains a startup boundary for freshly
  resolved builds, not an untrusted snapshot loader or a live re-equipping API. Human feel
  and cross-platform replay equivalence are not established by these automated checks.

### F2 — 3D physics engine is implicit — **Medium**

- **Where:** `project.godot` has no `physics/3d/physics_engine`.
- **Observed:** the project runs `DEFAULT`, which the 4.7.2 class reference says "is currently
  equivalent to GodotPhysics3D, but may change in future releases. Select an explicit
  implementation if you want to ensure that your project stays on the same engine." Projects
  created in 4.6+ default to Jolt.
- **If ignored:** a future engine upgrade could change collision, `move_and_slide` and shape-
  margin behavior with no diff in the repository.
- **Remediation:** the owner chooses: pin `GodotPhysics3D` (no behavior change today) or plan a
  separate Jolt migration PR with the full suite and a playtest. Record the choice in DECISIONS.md.
- **Scope / risk:** one line; none if pinned to the current engine.
- **When:** a small dedicated PR soon, and before any engine upgrade. Needs an owner decision.

### F3 — Per-tick resolution order depends on tree order plus `call_deferred` — **Medium**

- **Where:** `courtyard.gd` `_physics_process` → `_resolve_duel.call_deferred()`; fighters'
  `_physics_process` runs after the parent's by tree order.
- **Observed:** the comment documents the intent ("resolve after both actors tick/move"), and
  the runtime trace tests pin the result. But the order comes from node placement and the
  deferred-call flush, not from code that states it.
- **If ignored:** adding a projectile, a third fighter, or a node under a different parent can
  reorder rule ticks, movement and resolution without any code in the combat path changing.
- **Remediation:** when the next simulation participant arrives, have the encounter call
  `controller intent → combat.tick → move → resolve` explicitly (or set
  `process_physics_priority`), and keep the trace test.
- **Scope / risk:** moderate (touches the actor tick); the existing trace fixture makes it safe.
- **When:** deferred, until a third combatant or first projectile is added.

### F4 — 60 Hz rule and camera updates without physics interpolation on high-refresh displays — **Medium (unmeasured)**

- **Where:** `project.godot` (`physics_ticks_per_second=60`; interpolation default `false`);
  `player.gd` updates the camera pivot in `_physics_process`.
- **Observed:** official docs describe stepped motion when ticks don't match the refresh rate,
  and also the input delay that interpolation adds in fast games. The combat review already
  asks whether the deflect window feels right at 144 Hz.
- **Evidence:** official physics-interpolation docs. **Not measured** on hardware in this audit.
- **If ignored:** possible camera and actor judder on 120–240 Hz monitors, read by players as
  "unresponsive", which bears on the core precision-duel pillar.
- **Remediation:** a human playtest on a high-refresh monitor comparing interpolation on/off,
  and camera in `_process` vs `_physics_process`. Treat it as a feel decision. Don't toggle the
  setting without that playtest.
- **When:** defer to the next human playtest session. Needs a human decision.

### F5 — Cross-module result and event codes are free strings — **Low**

- **Where:** `CombatState.receive()` returns `last_event.to_lower()` (`"hit"`, `"guard"`,
  `"deflected"`, `"evaded"`, `"punish"`, `"defeated"`); `fighter.resolve_attack` adds `"invalid"` and
  `"out_of_range"`; consumers compare literals in `swordsman.gd:23` (`== "guard"`),
  `fighter.gd:212–214` and `courtyard.gd` `_resolve_duel`.
- **If ignored:** a typo in a comparison silently disables behavior. For example, the
  swordsman's counter after a blocked hit would stop firing with no error. The risk grows with
  every listener (VFX, audio, salvage triggers).
- **Remediation:** a `CombatState.Result` enum (or `StringName` constants) returned alongside the
  display text.
- **Scope / risk:** small, mechanical; covered by existing tests.
- **When:** when touched, at the latest when a second consumer (audio/VFX) is added.

### F6 — Duplicated sword geometry constants — **Low**

- **Where:** `build_adapter.gd` requires `attack.reach == 2.35 and attack.width == 1.6`;
  `fighter.gd` exports `attack_range := 2.35`, `attack_width := 1.6`.
- **If ignored:** editing one copy makes the adapter reject valid data, or accept data the
  fighter doesn't use.
- **Remediation:** one owner for the curated sword module's geometry (the module table proposed
  in the Development Guide §11), read by both.
- **When:** in the Marrow Lunge module PR, which must add a second geometry anyway.

### F7 — Collision layers are numeric literals in three scripts — **Low**

- **Where:** `fighter.gd:33–34` (layer 2, mask 3), `fighter.gd:124` (ray mask 1),
  `player.gd:24` (spring mask 1), `courtyard.gd:109–110`.
- **Remediation:** name layers in Project Settings (`layer_names/3d_physics`) and add shared constants.
- **When:** when touched; before shape-based hit and hurt volumes add more layers.

### F8 — `Fighter` mixes movement, hit validation and ~110 lines of procedural presentation — **Medium (deferred)**

- **Where:** `fighter.gd` `_ready` (mesh construction) and `_update_visual`; `resolve_attack`
  calls the opponent's private `_update_visual(0.0)`.
- **Observed:** correct and tested today; the presentation already reads rule phase only.
  But a real model with `AnimationTree`, anatomy-driven parts and per-module poses will all land
  in this file.
- **If ignored:** the first art or anatomy PR becomes a large, hard-to-review edit of the
  movement and hit-detection script.
- **Remediation:** when the first real character asset or second attack pose arrives, extract a
  presentation node (`FighterVisual`) that reads `combat` state, with a public sync call replacing
  the private cross-object call. Keep hit validation in `Fighter`.
- **Scope / risk:** moderate; the timing suite's pose/phase captures guard the regression.
- **When:** deferred until that asset or pose PR. Don't do it speculatively.

### F9 — Base `Fighter.reset_at` reads global player input — **Low**

- **Where:** `fighter.gd:145` (`Input.is_action_pressed("guard") if is_player else false`).
- **Observed:** a shared base class queries global input to seed rule state, which is the
  player controller's job.
- **Remediation:** `Player.reset_at` passes the held-guard flag; the base takes a parameter.
- **When:** when touched.

### F10 — HUD phase labels are a hand-maintained parallel array — **Low**

- **Where:** `hud.gd:55–56`.
- **Observed:** labels are indexed by `Phase` value. Adding or reordering a phase shifts every
  label after it, with no error.
- **Remediation:** a dictionary keyed by `CombatState.Phase` (keeping the intentional "RECOIL"
  label for `STAGGER`).
- **When:** when a phase is added.

### F11 — Rules layers are dynamically typed (844 static-typing reports) — **Low**

- **Where:** mainly `anatomy_rules.gd` (235), `blueprint_generator.gd` (152), `build_rules.gd`
  (97), `anatomy_catalog.gd` (96), `build_catalog.gd` (70). Member references such as
  `var catalog`, `var resolver` and `var library` are untyped.
- **Observed:** this is largely inherent to validated JSON `Dictionary` data, and the rules have
  strong validation tests. The four actor/rule scripts have 12 reports; the adapter has
  another 28 (40 across combat/characters/AI). Reports are not distinct bugs.
- **Remediation:** type member references where duck typing isn't deliberate
  (`build_projection.gd` is deliberately duck-typed), and type locals created from `Variant`
  at the boundary. Optionally enable `UNTYPED_DECLARATION = Warn` for
  `scripts/combat|characters|ai` via `directory_rules`. Don't add typed wrapper classes
  over all JSON.
- **When:** when touched; the warning setting is an optional, separate PR.

### F12 — Fingerprints depend on engine float-to-text formatting — **Low (deferred)**

- **Where:** `Catalog.digest()` and `canonical_json()` (both catalogs); `anatomy_rules` fingerprints.
- **Observed:** canonical JSON goes through `JSON.stringify`, which prints reliable digits only
  (`0.1 + 0.2` → `0.3`) and whose formatting is an engine detail. The regenerated-example tests
  will detect a change on upgrade, which is good.
- **If ignored:** once salvage refs or Tower snapshots persist, an engine upgrade could
  invalidate every stored fingerprint at once.
- **Remediation:** before persistence ships, store gameplay numbers as quantized integers, or
  fingerprint a project-owned encoding, and write migration rules.
- **When:** defer until persistence or the Tower is approved.

### F13 — Rule time is accumulated float seconds — **Low (deferred)**

- **Where:** `CombatState.tick(delta)`.
- **Observed:** deterministic on one binary at a fixed tick; not guaranteed bit-identical
  across platforms or compilers.
- **Remediation:** if server-validated Tower replays are approved, evaluate integer rule
  timers together with authoritative simulation and cross-platform replay tests. Integer
  timers alone cannot make floating-point movement or engine physics deterministic.
- **When:** defer until Tower validation is designed.

### F14 — Anatomy catalog cannot be loaded twice on one instance — **Low (reproduced)**

- **Where:** `anatomy_catalog.gd:67–73` clears tables previously frozen by `_freeze`.
- **Observed:** `var c = Catalog.new(); c.load_file(); c.load_file()` returns `true`, then
  `false`, with four read-only dictionary errors and duplicate-id validation errors. Existing
  fixtures create fresh catalogs, so their passing tests do not cover reload.
- **Remediation:** when reload is needed, replace the tables with fresh containers and test
  valid → valid and valid → invalid loads with explicit invalidation. For now use a fresh
  catalog per load. This does not block current one-shot startup or this documentation PR.
- **Evidence:** [independent review](../evidence/engineering-review/README.md#additional-source-probes).
- **When:** before reusing an instance for reload; no gameplay change in PR #14.

### Considered and not raised

- **Building the courtyard and fighters in code instead of scenes:** appropriate for primitive
  geometry and test simplicity. Addressed as a migration path (Development Guide §15), not a defect.
- **Per-primitive materials, 144 individual floor tiles:** unmeasured, and irrelevant at
  this scale. Not a finding without a profile.
- **Small array literals in per-tick `in` checks:** no evidence of cost. Not worth changing.
- **Tests writing internal rule fields** (`p.combat.phase = ACTIVE`) in isolated fixtures:
  documented fixture shortcuts. The full encounters use real input and AI.
- **Exact test-count assertions in runners** (`passed == 118`): intentional, so tests can't
  silently disappear.
- **QA scripts loaded from the main scene by string path under `--qa` / `web_qa`:** gated by
  flags and export filters; acceptable.

## 3. Prioritized technical-debt backlog

Only items supported by findings above. Each is a separate, small PR unless noted.

| # | Item | Finding | Severity | Trigger / timing | Size |
| --- | --- | --- | --- | --- | --- |
| 1 | Adapter fields validated, explicitly assigned and covered by non-default/mutation checks | F1 | Fixed | Completed; retain coverage when adding parameters | S |
| 2 | Pin the 3D physics engine explicitly; record it in DECISIONS.md | F2 | Medium | Soon; before any engine upgrade; **owner decision** | XS |
| 3 | Single owner for curated module geometry; named collision layers | F6, F7 | Low | With the Marrow Lunge module PR | S |
| 4 | High-refresh playtest: interpolation and camera update mode | F4 | Medium | Next human playtest; **human decision** | — |
| 5 | Result enum for combat outcomes | F5 | Low | Before audio/VFX listeners | S |
| 6 | Extract fighter presentation node | F8, (F9) | Medium | First real character asset or second attack pose | M |
| 7 | Explicit per-tick encounter step | F3 | Medium | Third combatant or first projectile | M |
| 8 | Type rule-layer member references; optional scoped typing warnings | F11 | Low | When touched / optional | S |
| 9 | Stable fingerprints, replay-validation design, migrations | F12, F13 | Low | When persistence or the Tower is approved | M |
| 10 | Fresh anatomy catalog tables on reload; reload regression tests | F14 | Low | Before reusing a catalog instance for reload | S |

## 4. Limitations of this audit

- Rendering and performance were not profiled. llvmpipe frame times do not predict desktop
  GPU performance; a scoped CPU experiment would need its own measurements and limitations.
- Desktop feel, high-refresh behavior and browser input were not tested by a human.
- `test_web.sh` was not run.
- Historical input and scene-inheritance reports do not establish a current engine bug.
  The independent review checked 4.7.2 input semantics; physical devices and human feel
  remain untested. See the [independent evidence](../evidence/engineering-review/README.md).
