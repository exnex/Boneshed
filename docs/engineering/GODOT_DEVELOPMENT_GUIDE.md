# Godot Architecture and Development Guide — Boneshed

**Engine:** Godot 4.7.2 stable (`4.7.2.stable.official.ed1daf0bf`), GL Compatibility.
**Written:** 2026-10-18. Evidence tags (**[Official]**, **[Measured]**, **[Consensus]**,
**[Boneshed]**, **[Opinion]**) are defined in [GDSCRIPT_GUIDE.md](GDSCRIPT_GUIDE.md); sources are in
[SOURCES.md](SOURCES.md).

This guide is an engineering standard. Where it mentions combat behavior (input buffers,
tick resolution, Tower snapshots), it describes **how to build** such a feature if one is
approved. It doesn't approve the mechanic; [DECISIONS.md](../DECISIONS.md) does that.

---

## 1. Boneshed's layering (keep it)

The current code already has a sound shape. New features fit into it rather than around it.
**[Boneshed]**

```
 data/*.json  ──►  pure rules (RefCounted, JSON-shaped)  ──►  adapter  ──►  CombatState (typed, per actor)
 catalogs          build_rules / salvage / anatomy_rules       build_adapter       │ phases, health, posture
                   blueprint_generator                         (only bridge)       ▼
                                                                         Fighter (CharacterBody3D)
                                            Player (input)  ─┐           movement, hit queries
                                            Swordsman (AI)  ─┴─ intent ─► │
                                                                         ▼
                                                     presentation reads state: procedural poses, HUD
```

**Dependency direction is one way.** Data doesn't know about rules. Rules don't know about
nodes. Combat rules don't know about input, AI or visuals. Presentation *reads* rule state
and never writes it. Controllers (player input, AI) produce **intent** (`desired_move`,
`attack()`, `set_guard()`), and the rules decide whether it happens. The tests enforce some
of this already ("library scripts reference no combat, scene, AI or worldgen code").

| Question | Answer |
| --- | --- |
| Where does a new rule (e.g. a parry variant) go? | `CombatState` or a rules module it calls. Never in `Player` or `Swordsman` |
| Where does a new tunable number go? | Catalog data if it varies per build or ability. A named constant in its single owner if it's an engine or presentation constant |
| Where does new input go? | `Player`, translated to the same intent calls the AI uses |
| Where does a new enemy behavior go? | An AI controller script. It may read rule state but goes through the same rule calls as the player |
| Where does a new visual go? | Presentation code that reads phase and progress. It must not decide hit timing |

## 2. Scenes vs Nodes vs Resources vs RefCounted vs JSON

| Use | When | Boneshed example |
| --- | --- | --- |
| **Scene (`.tscn`)** | Reusable arrangement of nodes that designers or artists will edit: a fighter body, an arena, a hit-effect | `courtyard.tscn` (currently a script-only root) |
| **Node script** | Needs the tree: processing callbacks, transforms, physics, signals to scene objects | `Fighter`, `Player`, `Swordsman`, `Hud` |
| **RefCounted** | Logic or state with no tree needs; unit-testable headless | `CombatState`, `BuildRules`, `AnatomyRules`, `SeedStream` |
| **Resource (`.tres`)** | Editor-authored, inspector-friendly **trusted** content: materials, animation libraries, curated attack-module assets | None yet. Good fit for future animation and attack-module assets |
| **JSON + validator** | Data that must be language-neutral, diffable, server-checkable or loaded from **untrusted** sources: builds, bodies, salvage refs, Tower snapshots | `data/builds`, `data/anatomy`, `data/worldgen` |

**[Official]** Godot recommends lighter objects than `Node` for data ("RefCounted… useful in
the majority of cases where one needs data in a custom class"), and `Resource` mainly for
inspector compatibility and serialization. **[Boneshed]** Builds and bodies were deliberately
kept out of `.tres` because a resource file can reference or embed scripts. Loading player-
supplied resource files is widely treated as unsafe **[Consensus]**, and the class reference
explicitly warns that decoding objects "can contain code which gets executed" **[Official]**. See
[SHARED_BUILDS.md §2](../SHARED_BUILDS.md). That choice is sound. Don't "modernize" it into custom
`Resource` classes. An editor-only `Resource` authoring view that exports to the same JSON is
fine later.

**Contested [Opinion]:** much community advice says "use custom Resources for all game data".
That is good advice for single-player, trusted, inspector-authored content, and is the
wrong default for Boneshed's shared and persisted builds.

## 3. Composition, inheritance and scene structure

- **[Official]** "If at all possible, you should design scenes to have no dependencies." When a
  scene needs its environment, the **parent injects** it: a signal connection, a method
  call, a `Callable`, a node reference or a `NodePath`. Siblings don't find each other; the
  common owner wires them. `courtyard.gd` setting `player.opponent = enemy` is exactly this.
- **Script inheritance** one level deep for a true is-a relationship (`Fighter` base) is fine.
  Prefer **component nodes or plain objects** for capabilities that vary independently
  (an attack module, a locomotion module, a lock-on helper). **[Consensus]**
- **Scene inheritance** (inherited `.tscn`) suits art variants of one body. Keep the
  inherited layer shallow: community bug reports describe overrides lost or drifting when
  edited through "Editable Children" in nested instances. Make changes in the scene that
  owns the node, and expose `@export` properties instead of editing a child's children.
  **[Consensus]**, issue reports from several Godot 4 versions; not reproduced here.
- **Use `_get_configuration_warnings()`** on `@tool` components that require a sibling or
  child (e.g. an attack module needing a mount marker), so the editor shows the missing
  dependency. **[Official]**
- **Entry point.** One root (today `Courtyard`) creates and wires the encounter. Keep that
  single, readable place for start-up ordering. **[Official]** recommends a Main node.

### Initialization order

- `_init` → (added to tree) `_enter_tree` → children's `_ready` **before** the parent's `_ready`.
  `_ready` runs once per node lifetime. **[Official]**
- Boneshed's working pattern: **prepare all data first, then create nodes, then wire, then
  reset.** `courtyard._ready` validates both builds before creating any world, input map or
  fighter. That is why invalid data can't produce a half-configured fight. Follow it for
  every encounter or level loader. **[Boneshed]**
- Configure a node's data *before* `add_child` where it affects `_ready` (as
  `move_speed` is set before the fighters enter the tree). **[Boneshed]**

### Cleanup

- `queue_free()` frees at the end of the frame, along with all children. References to freed
  objects stay non-null but invalid; use `is_instance_valid()` for cross-object references.
  **[Official]**
- Disconnect signals that a long-lived object connected on a short-lived one only if the
  connection's *callable owner* outlives the target (see the GDScript guide §4).
- Encounter **reset** must restore every piece of mutable state. Boneshed has explicit
  `reset()` / `reset_at()` paths and a reset test from every state; extend both whenever
  you add state.

## 4. Autoloads

**[Official]** Godot warns that a global manager creates global state, global access ("no
longer an easy way to find the source of a bug") and global allocation. It recommends
keeping state inside scenes, using `class_name` + `static func` / `static var` for shared
helpers, and keeping autoloads for wide-scope systems that "manage their own information and
not invade the data of other objects" (quests, dialogue).

**Boneshed rule:** no autoload without a PR that states which state it owns, why a scene or
static helper can't own it, and how tests reset it. Plausible future candidates: settings and
key rebinding, an audio bus mixer front-end, and a session or network client. Combat state,
the current encounter, and "the player" are **not** candidates. **[Boneshed]**

**Event bus (contested [Opinion]).** An autoload of global signals reduces wiring but
makes emitters untraceable. Community experience is split. If one is ever added, limit it to
past-tense notifications with no state, and never route combat resolution through it.

## 5. Signals and event routing

- Use signals for **notifications upward and outward** (UI, audio, VFX, achievements,
  telemetry). Use **direct calls in a defined order** for simulation. **[Official]** style;
  **[Boneshed]** rule for combat.
- Today `Swordsman` reacts to being hit by polling `event_serial` and `last_result`. That's
  deterministic and explicit within the tick. A signal (`hit_received(result)`) would be
  equally deterministic, because emission is synchronous, and more conventional. Convert when
  a second listener (audio, VFX) appears, not before. **[Boneshed]**
- Result codes that cross modules (`"guard"`, `"deflected"`, `"evaded"`) should become an
  `enum` or `StringName` constants before more consumers compare them. See the audit.

## 6. Deterministic combat simulation

**What exists [Boneshed]:** `CombatState` is pure and typed. It advances by `delta` with
overshoot carried across phase boundaries (timing independent of frame rate). Hits are
resolved once per swing in a fixed player-first order, and the tests drive it at a fixed 60 Hz.
Encounter traces are compared byte for byte.

**Guidance for growing it:**

1. **One tick owner.** Order inside a physics tick should be explicit:
   *controllers produce intent → rules tick → movement (`move_and_slide`) → hit queries →
   resolution → presentation sync.* Today the order comes from tree order (parent
   `_physics_process` runs before children) plus `call_deferred` for resolution. That works
   and is tested, but it is implicit. When a third combatant or a projectile arrives, replace it
   with an explicit `step(delta)` called by the encounter, or set
   `process_physics_priority`. **[Official]** mechanisms; **[Boneshed]** recommendation.
2. **Fixed tick for rules.** Keep rule time in `_physics_process` at
   `physics_ticks_per_second = 60`. If Tower replays or server validation are approved, move
   rule timing to **integer ticks** (frames) rather than accumulated float seconds, so a replay
   is bit-exact across machines. **[Consensus]**
3. **No engine RNG in rules.** Any future randomness in combat (AI choice, crit) takes a
   seeded stream passed in, recorded with the encounter. **[Boneshed]**
4. **Tie rules are rules.** Simultaneous hits, same-tick inputs (dodge > guard > attack) and
   priority are documented and tested, and they're open design questions. Keep them in
   `CombatState` or the encounter resolver, never in node order.

## 7. Physics ticks, input and responsiveness

- **Input.** Continuous input (movement vector, held guard) can be polled in
  `_physics_process`. One-shot presses (attack, dodge) are polled with
  `is_action_just_pressed` today. Community reports describe dropped or duplicated presses
  when polling in physics on older 4.x versions, reportedly fixed in mid-2023 (not
  verified against the 4.7.2 source here). Boneshed's input tests inject events through
  `Input.parse_input_event` at 60 Hz, so they don't exercise high-refresh or low-FPS
  edges. **[Consensus]**, unverified for 4.7.2.
  If buffering is approved (proposed in [COMBAT_REVIEW.md §6.6](../COMBAT_REVIEW.md)),
  capture presses in `_unhandled_input` into a timestamped buffer that the rules consume per
  tick. That is the robust form whatever the polling semantics.
- **Camera / mouse** stays event-driven (`_unhandled_input`), as in `Player`. **[Official]** pattern.
- **Physics interpolation is off** (`physics/common/physics_interpolation = false`, the default),
  and `physics_jitter_fix = 0.5`. With 60 Hz ticks on a 144 Hz display, actor and camera
  motion update in 60 Hz steps. The official docs describe the resulting jitter, and also that
  interpolation adds input delay "in fast twitch games". **[Official]** Whether to enable it,
  and whether the camera should update in `_process`, is a **feel decision for a human
  playtest on a high-refresh monitor**. It's contested, so don't flip it in passing.
- **Physics engine is implicit.** `project.godot` doesn't set `physics/3d/physics_engine`, so it
  runs `DEFAULT`, which in 4.7 "is currently equivalent to GodotPhysics3D, but may change in
  future releases". New 4.6+ projects default to Jolt. **[Official]** Pin one explicitly before
  the next engine upgrade, and record the choice in DECISIONS.md. Switching to Jolt changes
  collision-margin and other behaviors; treat it as a migration with the full suite and a
  playtest, not as a setting tweak.

## 8. Animation, hit detection and synchronization

**Principle [Boneshed]:** the *rules timeline* owns windup, active and recovery. Animation
**follows** the rule phase; animation doesn't decide when a hit is active. This is the
frame-data approach common in action and fighting games. It suits Boneshed because timing
comes from shared, data-driven ability definitions that player and AI both execute.
**Contested [Opinion]:** many Godot projects instead author hit windows as `AnimationPlayer`
value tracks (enable a hitbox shape on frames N–M). That is deterministic too *if* the mixer
advances on physics ticks. It's a valid alternative for animation-first teams, but it would
move timing out of the build data, so it needs an owner decision here.

- When real animation arrives, drive it from rule state: set an `AnimationTree` blend/seek from
  `combat.phase` and normalized phase progress, with the mixer's
  `callback_mode_process = PHYSICS` (or `MANUAL` + `advance(delta)` from the tick owner). The
  4.7.2 default is `IDLE`, which advances animation on render frames and drifts from ticks.
  **[Official]** property and default.
- **Don't use method-call tracks to open or close hit windows.** Their timing depends on
  `callback_mode_method` (deferred by default) and frame rate. Community reports describe
  one-frame-late hitbox toggles. **[Official]** setting; **[Consensus]** reports.
- **Hit queries.** Today: an analytic oriented box plus one environment ray, evaluated on
  active ticks only. That's deterministic, cheap and tested; keep it until shapes must follow
  anatomy. Then prefer **direct space queries** (`PhysicsDirectSpaceState3D.intersect_shape`,
  `ShapeCast3D` forced updates) during active ticks over `Area3D` enter/exit signals, which
  report overlaps after the physics step and are harder to order. **[Consensus]**
- **Telegraph readability** is a test target. The timing suite captures rendered poses at
  windup, commit, release, active and recovery and checks the blade pose against the rule
  phase. Every new attack module gets the same captures and a human readability review.
- **One hit per swing**, attacker-side consumption (`hit_consumed`), and cancel-before-resolve
  are rule invariants. New modules must preserve them and add their own negative controls.

## 9. Character controllers and state machines

- `CharacterBody3D` + `move_and_slide()` in `_physics_process`. Horizontal velocity is
  integrated as one vector (a review fix), gravity applies off-floor, and dodge keeps only the
  aligned momentum. Preserve these fixes when refactoring.
- **State machines:** a typed `enum` + `match` in the owning class (as in `CombatState.Phase`)
  is the right size for one actor. A node-per-state framework adds lifecycle and indirection;
  consider it only when states need their own scene data (e.g. per-state VFX nodes) **and**
  several actors share it. **[Opinion]**, contested: both styles are common in shipped Godot games.
- AI state should be an `enum`, not free strings (`ai_state = "ATTACK FOOTWORK"` is fine as
  a debug label, but nothing should branch on it).

## 10. Enemy AI and navigation

- AI is a **controller**: it reads observable state (positions, the opponent's phase) and
  calls the same intent API as the player. It never edits rule fields directly. This keeps
  "shared builds" honest: an enemy can't do what the rules don't allow.
- Determinism: AI decisions that use randomness take a seeded stream (§6). Current AI is fully
  deterministic, which the adversarial probe depends on.
- Navigation: the courtyard needs none. For worldgen spaces, use `NavigationRegion3D` +
  `NavigationAgent3D`, with baked navmeshes per generated chunk, and give the agent's
  avoidance and path updates a fixed cadence. Treat the navmesh as a generated asset, keyed
  by the world seed. **[Official]** components; the plan is **[Boneshed]**, unvalidated.
- Fairness constraints belong in tests: the probe measures exploit strategies. Every new
  behavior gets a probe scenario, not just a positive test.

## 11. Ability execution modules (curated, not generated)

AGENTS.md requires curated attack modules before any generated attacks. A module is the unit
that turns a resolved ability into gameplay. **[Boneshed]** proposed contract, consistent with
the existing adapter:

- **Inputs:** the resolved ability's `effective` values and module id, and the wielder's
  resolved anatomy origin (later).
- **Owns:** its hit geometry, presentation pose or animation, telegraph and any special
  phase behavior, implemented once and used by **both** player and enemy.
- **Registration:** an explicit table from module id to implementation, checked at encounter
  preparation. The adapter already *fails* on unsupported modules rather than skipping them;
  keep that.
- **Doesn't own:** damage math, posture rules, cancel priority. Those stay shared in `CombatState`.
- **Tests per module:** phase timing captures, one-hit-per-swing, cancel behavior, a probe
  strategy, and parity tests between player and enemy wielders.

## 12. Boneshed-specific systems

**Shared player and enemy builds.** One catalog, one resolver, one adapter for both sides. A
form-specific exception is expressed as data (profile overrides, `guard_posture_overrides`),
never as `if is_player` in rules. A new stat is added in catalog, resolver, adapter **and**
an adapter test that changes the value and observes a runtime effect.

**Salvageable signature abilities.** A salvage reference points to the *same* item id and
fingerprints. It doesn't copy stats. Equipping it rebuilds the actor's `CombatState` from a
fresh resolution, between encounters. Rewards are **server-issued** in the real game; local
fingerprints detect staleness, not cheating.

**Extensible anatomy.** Gameplay anchors live on the core part. Limbs provide capabilities;
abilities require capabilities, never slots. Gameplay and visual fingerprints are separate,
so cosmetic changes can't alter combat identity. In Godot terms, a core part maps to a scene
with `Marker3D` sockets (or `BoneAttachment3D` on a humanoid `Skeleton3D`), and each part to
a small scene attached at a socket. Hurt and reach *classes* map to combat-owned shape tables.

**Extreme transformations and animation compatibility.** Apply transformations between
encounters, or behind an uninterruptible transition, and rebuild hurtboxes and modules from the
new resolved body. Use one curated animation module per part type over the shared
windup/active/recovery timeline. `SkeletonProfileHumanoid` retargeting is only for humanoid
cores and arms. Non-humanoid parts get authored animation or the 4.6+ modifier stack
(`TwoBoneIK3D`, `SplineIK3D`, `LookAtModifier3D`). **Don't build on `SkeletonIK3D`**:
it has been deprecated since at least 4.3, and AI Game Dev Lab found agents still generate it.
Review flags (asymmetry, non-baseline limb count, long reach) gate a form's use in combat
until a human approves its readability.

**Three-keyword world generation.** Identity depends only on the words; variation depends on
words plus seed; each downstream generator gets its **own** named stream seed. Adding a
generator domain must not change the others (already tested). Generated geometry will be a
large new surface. Keep generation as pure data (a blueprint, then a layout description)
that a separate builder turns into nodes, so layouts can be tested headless and compared by
fingerprint.

**Deterministic seeds and reproducible content.** Committed example outputs are regenerated
and byte-compared by the test runners. That is the project's regression detector for
content. An engine upgrade that changes number formatting or hashing will show up there;
investigate before regenerating.

**Asynchronous Tower of Memories snapshots** (design open). Engineering constraints that
already follow from the architecture:

- A snapshot is **id-only build + body + catalog version + AI-policy id/version**, never
  resolved stats and never engine objects.
- The server re-resolves snapshots with the same rules to validate them; the client's
  computed values are never trusted.
- If results must be verified, record **inputs per tick + seeds**, and replay them on a
  trusted host with integer-tick rules (§6).
- Old snapshots need **catalog migration or retirement rules** before the first public test.

**Security boundaries for online systems.** Never trust client-submitted rewards, inventory,
trades or Tower results (AGENTS.md). Parse network and save payloads only as JSON or primitive
`Variant`s. Never use `bytes_to_var_with_objects` or load `.tres`/`.res`/`.tscn` from player
data. Validate exact keys, types, ranges and catalog versions, as the existing strict loaders do.
Treat the web export as inspectable: no secrets in the client.

## 13. 3D production

**Rendering and profiling.** GL Compatibility is pinned for the cloud prototype; the desktop
GPU renderer is a pending decision. Measure on real desktop hardware with the Godot
profiler and monitors (`Performance.get_monitor` for draw calls, objects, physics time). The
cloud's llvmpipe numbers measure correctness only, never performance. **[Official]**,
**[Measured]**. Record budgets once art exists. Inventing them now would be guesswork.

**Collision architecture.** Name the physics layers in Project Settings
(`layer_names/3d_physics`) and use matching constants in code. Today `1 = world`,
`2 = fighters` appear as literals in three scripts. Hurt and hit volumes should get their own
layers when shape-based hit queries arrive, so queries can't hit the environment by accident.

**AnimationTree / AnimationPlayer / Skeleton3D.** Use one `AnimationTree` per character,
driven from rule phase (§8). Keep animation libraries as `.res`/`.tres` resources shared by all
users (read-only at runtime). Use `SkeletonModifier3D` subclasses for procedural layers, with
`_process_modification_with_delta()` (4.5+ signature). Write explicit values for modifier
properties instead of relying on defaults: AI Game Dev Lab found a `LookAtModifier3D.relative`
default change in a *patch* release. **[Official]** class references; **[Measured]** in the lab
(documentation diff, not a game test).

**Rigging and retargeting.** Godot 4 bone poses *include* the rest, and sharing animations
needs matching bone names **and** rests. Use the importer's `BoneMap` with
`SkeletonProfileHumanoid` for humanoids. **[Official]**

**Asset import.** Use glTF 2.0 (`.glb`) exported from an official Blender release; it is the
officially recommended format. Commit source `.blend` files (or reference them) and the
`.import` settings; never hand-edit `.godot/`. Third-party assets need explicit owner approval
and a license record (AGENTS.md). **[Official]**

**Meshes, materials, LOD and instancing.** Share materials between instances, and give a
material its own copy only when one instance must differ. Use automatic mesh LOD (generated
on import), visibility ranges and occlusion culling for worldgen-scale scenes, and
`MultiMeshInstance3D` for repeated props such as the courtyard's 144 floor tiles, *if* a
profile shows draw calls matter. Today every primitive gets a fresh `StandardMaterial3D`.
That's harmless at prototype scale; replace it when real assets land. **[Official]** features.

## 14. Quality assurance

Boneshed's QA practice is already stronger than most Godot projects': pinned engine with checksum
verification, external timeouts, fresh evidence directories, JSON-line results, **negative
controls that must fail**, source-mutation controls, byte-compared regenerated examples, rendered
captures under Xvfb, and an adversarial probe. **[Measured]** Keep all of it. The rules below
fill gaps.

| Layer | Tool here | Use for | Doesn't prove |
| --- | --- | --- | --- |
| Pure unit | `extends SceneTree` scripts on `RefCounted` rules | Rule invariants, validation codes, determinism | Scene wiring |
| Integration | Real `courtyard.tscn` instantiated headless | Data → adapter → runtime parity | Rendering |
| Scene / input | `graphical_test.gd` with `Input.parse_input_event` | Input → movement → hits through physics | Feel; high-refresh timing |
| Rendered | Xvfb + llvmpipe captures | Pose/phase agreement, framing, visible telegraphs | GPU performance, final visuals |
| Adversarial | `adversarial_probe.gd` | Exploit strategies with legal inputs | Fun |
| Human | Desktop playtest | Readability, fairness, responsiveness | Regression safety |

- **Positive and negative controls.** Every new check should have a known-bad variant that fails
  it (the existing `--negative=` flags). When a check can't fail, it isn't a check.
- **Make values observable.** A test that changes catalog data must *also* change the runtime
  value under test. A default that equals the data hides a dropped field
  ([evidence](../evidence/engineering-audit/README.md#3-adapter-field-name-mutation-does-any-test-notice-a-dropped-field)).
- **Input replay.** Record legal input per physics tick plus seeds to replay a playtest or
  bug report headlessly. This is the right foundation for Tower validation later.
- **Screenshots** prove a frame rendered with some content. They don't prove readability or feel,
  and llvmpipe output isn't a GPU reference. Use them for pose/phase agreement and gross
  regressions; don't pixel-diff across renderers or drivers.
- **Headless vs rendered.** Headless has no frames: `RenderingServer.frame_post_draw` never fires
  and screenshots are impossible. Keep rendered checks in their own runs. **[Measured]**
- **Human playtesting** is the only gate for feel. Reports must say what was played, on what
  hardware and refresh rate, and which build.
- **Engine-version changes.** An upgrade is its own PR: update the pin and checksum, run every
  suite, compare regenerated examples and the runtime trace, re-read the release notes for
  physics, animation, GDScript and JSON changes, and playtest. Unexplained fingerprint or trace
  diffs block the upgrade.
- **No test frameworks or plugins without approval.** GUT and GdUnit4 are mature options, but
  the current harness works with zero dependencies, and AGENTS.md requires approval for new
  dependencies. Propose one only when the harness becomes a bottleneck (e.g. mocking scene
  dependencies).

## 15. Editor-friendly organization

- Today almost everything is built in code (`courtyard.tscn` is one script node, and fighters
  build their own meshes). That's fine for a primitive prototype and makes the tests simple.
  It becomes a liability once artists or designers need to place things in the editor.
- The move to scenes should happen **per asset as it becomes real** (first real fighter model,
  first authored arena), not as a big-bang refactor. Keep the code-built fallback
  until the scene version passes the same tests.
- Directory layout stays by domain (`scripts/combat`, `scripts/builds`, …). Put a scene and
  its script side by side once scenes exist (`characters/fighter.tscn` + `fighter.gd`).
  **[Official]** project organization suggests grouping by feature.
- Input actions belong in `project.godot`'s `[input]` section once rebinding or settings are
  in scope. Today they are registered in code (`courtyard._setup_input`), which the tests rely on.

## 16. Contested areas (decide case by case)

| Topic | Positions | Boneshed default |
| --- | --- | --- |
| Custom `Resource` data vs JSON | Resources: editor ergonomics. JSON: safety, servers, diffs | JSON for shared/persisted data; Resources for trusted assets |
| Event-bus autoload | Less wiring vs untraceable emitters | None; past-tense notifications only if ever added |
| Node-per-state FSM vs enum + `match` | Editor visibility vs indirection | `enum` + `match` until states need their own nodes |
| Animation-authored vs rule-authored hit windows | Animator control vs data-driven timing | Rule-authored (§8) |
| Physics interpolation in a precision duel | Smoothness vs added input delay | Undecided; human playtest (audit F4) |
| Scene inheritance depth | Variant reuse vs fragile overrides | Shallow; prefer exported properties |
| Test framework (GUT, GdUnit4) vs custom harness | Features vs zero dependencies | Custom harness; propose a framework only with a concrete need |

## 17. Self-review notes (2026-10-18)

The guides were reviewed against the questions in the task brief before merging:

- **Godot-specific evidence** backs typing, autoload caution, scene dependency injection,
  resource sharing and copying, `assert` stripping, JSON number types, RNG notes, physics engine
  defaults, interpolation trade-offs, animation callback modes and import formats.
- **General engineering preference, not Godot evidence:** composition over deep inheritance,
  "abstraction after the second use", the module-registration contract, and integer ticks for
  replays. They're tagged **[Consensus]** or **[Boneshed]**.
- **Complexity risks deliberately avoided:** no recommendation to type the JSON layers through
  wrapper classes, no mandatory test framework, no preemptive scene migration, no blanket
  warnings-as-errors, no performance work without a profile.
- **Possible misreadings by agents:** "prefer `extends Fighter`" and "use enums for results"
  are *when touched* items, not a license to sweep the codebase. AGENTS.md says so explicitly.
- **Conflicts with existing architecture:** none intended. Where the guide differs from current
  code (explicit tick owner, presentation extraction), it names a trigger instead of
  demanding a refactor.
