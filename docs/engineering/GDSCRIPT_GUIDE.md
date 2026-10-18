# GDScript Engineering Guide — Boneshed

**Engine:** Godot 4.7.2 stable (`4.7.2.stable.official.ed1daf0bf`). **Written:** 2026-10-18.
**Status:** approved engineering *standard* once merged. It governs how code is written,
not which mechanics exist; gameplay rules stay in [DECISIONS.md](../DECISIONS.md).

Each recommendation carries an evidence tag. Sources and their quality are listed in
[SOURCES.md](SOURCES.md).

| Tag | Meaning |
| --- | --- |
| **[Official]** | Godot 4.7 documentation or the class reference at tag `4.7.2-stable` |
| **[Measured]** | Reproduced in this repository or in AI Game Dev Lab, with a recorded experiment |
| **[Consensus]** | Broad engineering or Godot-community practice from several independent sources |
| **[Boneshed]** | A project-specific choice, justified by Boneshed's architecture or goals |
| **[Opinion]** | Reasonable but contested. Use judgment and don't enforce it |

**Rules vs. defaults.** Items marked **MUST** are enforced in review. Everything else is a
default: deviate when you have a reason, and write the reason in the PR.

---

## 1. Static typing

**MUST: type every member variable, parameter and return value you add or modify in runtime
gameplay code** (`scripts/combat`, `scripts/characters`, `scripts/ai`, future controllers and
modules). This doesn't require retrofitting untouched lines.
**[Official]** Typed code catches errors at parse time, improves autocompletion, and "improves
performance by using optimized opcodes when operand/argument types are known at compile
time." **[Measured]** In AI Game Dev Lab's Signal Yard fixture, resetting an untyped `Variant`
from `0.0` to `0` turned it into an `int`, and a tween then quantized a door animation to
0→1 in one frame. A `: float` declaration would have stopped that.

```gdscript
# Preferred
var remaining: float = 0.0          # or: var remaining := 0.0
func receive(attacker: CombatState, facing_dot: float = 1.0) -> String:

# Discouraged: type changes silently on reassignment
var remaining = 0.0
remaining = 0                        # now an int
```

- `:=` inference is fine when the right-hand side's type is obvious from the line
  (`var speed := 5.5`, `var state := CombatState.new()`). Write the type out when the value
  comes from a `Variant` source (`Dictionary` access, `get()`, JSON, `get_node()`): there
  `:=` infers `Variant` or fails. **[Official]**
- Mark the typed boundary where `Variant` data enters, and convert there:
  `var damage: float = float(attack.health_damage)`.
- Typed arrays and dictionaries (`Array[Fighter]`, `Dictionary[StringName, float]`) are
  available. Nested typed collections such as `Array[Array[int]]` are **not** supported in
  4.7. **[Official]** Use them for runtime collections. Don't force them onto JSON-shaped
  data that is validated as a whole.
- **JSON-shaped rules code is exempt in part.** The build, anatomy and worldgen layers
  deliberately manipulate JSON-shaped `Dictionary` data (see the Development Guide, §2).
  There, type the *function signatures* and locals you create, and leave dictionary field
  access dynamic. Validation functions, not the type system, own correctness in those
  layers. **[Boneshed]**
- Performance is a secondary reason for typing. Typed opcodes are measurably faster in
  microbenchmarks (an engine PR reported >40% on synthetic loops), but nobody has measured
  a frame-time gain in Boneshed. Don't cite speed as the reason for a typing PR. **[Official]
  mechanism, [Opinion] magnitude.**

**Warnings.** Godot 4.7 can warn on `UNTYPED_DECLARATION`, `INFERRED_DECLARATION` and
`UNSAFE_*`, scoped per directory by `debug/gdscript/warnings/directory_rules`. **[Official]**
They are off today. A census found 844 reports in production scripts, almost all in the
JSON rules layers; the combat path has 12. See the
[evidence](../evidence/engineering-audit/README.md#4-static-typing-warning-census). Enabling
`UNTYPED_DECLARATION = Warn` for the runtime directories is a proposed backlog item
([CODE_AUDIT.md](CODE_AUDIT.md)), not something to switch on as a side effect of an
unrelated PR.

## 2. Classes, scripts and references

- **`class_name` for types other code names**: rule objects, fighters, modules. Use
  `preload()` constants for script-private helpers, test fixtures, or scripts that would
  pollute the global namespace. Pick one way of naming a class in a file. Don't use
  `CombatState` and a `Rules` alias for the same script in one function. **[Official]
  mechanism, [Boneshed] convention.**
- **Prefer `extends Fighter` over `extends "res://…/fighter.gd"`** when a `class_name`
  exists. Path strings break silently when a file moves. **[Consensus]**
- **Composition over deep inheritance.** One level of `extends` from a shared base
  (`Fighter` → `Player` / `Swordsman`) is fine. A third level, or a base class that grows
  `if is_player` branches, is the signal to extract a component or pass a strategy object.
  **[Consensus]** Godot's docs frame this as small, loosely coupled scenes. **[Official]**
- **Duck typing across module boundaries is a deliberate tool, not a default.**
  `build_projection.gd` reads the build catalog duck-typed so the anatomy core has no
  dependency on `scripts/builds`. That is a documented decoupling choice. Elsewhere,
  prefer a typed reference.
- **Inner classes** are fine for small private value types. Split them into a file once
  another script needs them.

**Where Godot practice differs from textbook OOP** **[Official]** (Godot "interfaces" and
scene-organization docs):

- There are no interfaces. Capability checks use `is SomeClass`, groups, or `has_method()`.
  `has_method()` duck typing is idiomatic Godot, but it's still a string lookup. Keep it at
  loose boundaries, not inside one module.
- Composition is mostly **tree composition**: child nodes and sub-scenes, not injected
  service objects. A component is usually a child node, configured by its owner.
- "Private" is only a leading-underscore convention, not enforced. Tests in this repository read
  rule fields directly; that's accepted for fixtures.
- The observer pattern is built in (signals). Don't hand-roll listener lists.
- Design patterns that need many tiny classes (visitor, abstract factory) usually cost more
  in GDScript than they save. Prefer data tables and plain functions.

## 3. Naming, layout and documentation

Follow the [official style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html)
**[Official]**: `snake_case` files, functions and variables; `PascalCase` classes, nodes and
enum names; `CONSTANT_CASE` constants and enum members; past-tense signal names
(`attack_resolved`, `posture_broken`); a leading underscore for private members.
The code order is: signals, enums, constants, static variables, `@export`, other variables,
`@onready`, virtual callbacks (`_init`, `_ready`, `_process`, `_physics_process`), public
methods, private methods.

- Units go in the name or a comment where they aren't obvious (`attack_turn_speed`
  is degrees per second; durations are seconds). **[Boneshed]** existing convention.
- Use `##` doc comments for intent, invariants and "why", as the rules files already do
  (`## Transaction boundary: both actors must resolve…`). Don't narrate what the next line
  obviously does. **[Consensus]**
- Mark provisional tuning *as provisional* where the value lives, not in a distant doc.
  **[Boneshed]**

## 4. Signals versus direct calls

**[Official]** guidance (Scene Organization) is "call down, signal up": a parent configures and
calls its children; a child reports what happened through a signal and doesn't know who
listens. Signals "respond to behavior", they don't start it.

| Situation | Use |
| --- | --- |
| Owner tells a child to act (`courtyard` → `fighter.reset_at`) | Direct method call |
| Child reports an event to whoever cares (fighter hit, enemy defeated, UI update) | Signal, past-tense name |
| Siblings must interact (player ↔ enemy) | The common owner wires references or mediates |
| Outcome must be resolved in a defined order within one tick | Explicit call from one orchestrator, **not** signals |
| Many unrelated systems react to rare global events (achievement, save) | Possibly an autoload event bus. See §4 of the Development Guide |

- Signal emission is synchronous. Handlers run in connection order, inside the emitter's
  call. Don't put combat-resolution order inside signal handlers; it hides ordering in
  `connect()` calls. **[Official]** semantics, **[Boneshed]** rule.
- Lambdas capture local variables **by value, once**. Reassigning the outer variable later
  doesn't affect the lambda. Godot 4.7 warns (`CONFUSABLE_CAPTURE_REASSIGNMENT`).
  **[Official]**
- "If the callable's object is freed, the connection will be lost." **[Official]** A lambda's
  object is the instance that created it, so a lambda can still fire after the *captured*
  nodes it uses have been freed. Guard captured references with `is_instance_valid()`, or
  connect a method on the real receiver instead. **[Official]** behavior; **[Consensus]** practice.

## 5. Errors, validation and nullability

Boneshed's established pattern **[Boneshed]**, which is good and should be kept:

- **Validate at boundaries, trust inside.** Catalogs, builds, bodies, encounter files and
  (later) network or Tower payloads are validated completely on entry, returning
  `{"ok", "errors", …}` with stable error codes. Internal pure functions then assume valid
  input.
- **All-or-nothing.** An operation that fails returns the original value unchanged, never a
  partial result (`build_rules.equip`, `anatomy_rules.transform`,
  `build_adapter.prepare_encounter`).
- **Fail loudly at startup.** `courtyard.gd` refuses to build a world from an invalid
  encounter (`push_error` + exit 1). There is no silent fallback to defaults.

Language rules:

- Reserve `assert()` for programmer errors in debug. **Asserts are stripped from release
  builds** **[Official]**, so never put validation or side effects inside one.
- `push_error()` / `push_warning()` for runtime problems a developer must see. The test
  runners treat `ERROR:` lines as failures, so an unexpected `push_error` will fail CI.
  That is intended.
- **`Object.set(name, value)` with an unknown property is a silent no-op.** No error or
  warning is printed. **[Measured]** ([evidence §2](../evidence/engineering-audit/README.md#2-silent-objectset-with-an-unknown-property)).
  String-keyed `set()`/`get()` must be paired with an explicit existence check
  (`name in object`) or replaced with typed assignments.
- **Freed objects.** A variable holding a freed `Object` or `Node` isn't `null`. Accessing it
  is a runtime error. Use `is_instance_valid(x)` where the referent can be freed by someone
  else (an opponent, a projectile, a pooled effect). **[Official]** `Fighter` already does
  this for `opponent`.
- `queue_free()` deletes at the end of the frame, so the node is still accessible until
  then. Check `is_queued_for_deletion()` where that matters. **[Official]**
- `await` on a node that may be freed mid-wait resumes against invalid state. Re-check
  `is_instance_valid(self)` after awaits in long coroutines. **[Consensus]**

## 6. Copying versus sharing mutable data

**[Official]** `Array`, `Dictionary`, packed arrays and all `Object`s (including `Resource`)
are passed **by reference**. Everything else is passed by value.

- **Loaded resources are shared.** `load()`/`preload()` return the *same* cached instance
  every time, and scene instances share sub-resources (meshes, materials). Mutating a
  loaded resource at runtime mutates it for every user. Use `duplicate()` (or
  `resource_local_to_scene`) for per-instance state. **[Official]**
- `Resource.duplicate()` is **shallow** by default. Nested arrays, dictionaries and
  sub-resources stay shared. `duplicate(true)` deep-copies arrays and dictionaries, but in
  4.7 only *local* sub-resources. Use `duplicate_deep()` with an explicit mode when you need
  more. **[Official]**
- **Freeze shared definitions.** The catalogs call `make_read_only()` recursively on loaded
  definitions, so a consumer that tries to mutate a shared ability fails instead of
  corrupting every wielder. Keep this pattern for any shared definition table. **[Boneshed]**
- Copy at the point of mutation, not defensively everywhere:
  `var effective: Dictionary = ability.timing.duplicate(true)` before merging overrides is
  correct. `duplicate(true)` on every read wastes allocations and hides ownership.
- `for x in array` gives a copy of value types. Assigning to `x` doesn't change the
  array. **[Official]**

## 7. Allocation, per-frame code and performance

**MUST: profile before optimizing, and state the measurement in the PR.** **[Official]**: "the
most important tool for optimization is the ability to measure performance." Use the Godot
profiler and monitors on representative scenes. The cloud runs on llvmpipe, so software-
rendered frame times **are not representative** of desktop GPUs. **[Measured]**

Defaults that cost nothing and avoid known traps:

- Cache node references in `@onready` or `_ready`. Don't call `get_node()` / `$Path`
  inside `_physics_process` loops. **[Consensus]**
- Do game rules in `_physics_process` (fixed 60 Hz here), and visuals that only need to look
  smooth in `_process`. **[Official]**
- Don't build strings for HUD or logging every frame in hot paths without need. Heavy
  `print()` in per-frame code is a real cost. **[Consensus]**
- `RefCounted` frees deterministically when its count reaches zero; there is no tracing GC.
  **Reference cycles leak.** Break them with `weakref()` or by making one side a plain
  `Object`/`Node` with explicit ownership. **[Official]**
- Allocation in GDScript means `Variant` construction plus ref-count traffic, not GC pauses.
  A small array literal in a per-tick check (`phase in [A, B, C]`) is fine at Boneshed's
  scale. Don't rewrite it without a profile showing it matters. **[Opinion]** (unmeasured either way)

Escalation order when a profile *does* show a hotspot: algorithmic fix → cache or avoid
work → typed code → servers/`MultiMesh` for many objects → GDExtension. Moving to C++ or C#
is an architecture decision for the human owner. **[Official]** options; order **[Consensus]**.

## 8. Loading resources

- `preload()` for a fixed dependency known at parse time: scripts, small scenes, the data
  the scene always needs. It loads with the script and fails at parse time when the path is
  wrong. **[Official]**
- `load()` for optional or late content. Use `ResourceLoader.load_threaded_request()` for
  large content during play. **[Official]**
- Don't `preload` into an `@export` default (the docs explain why it is wasted).
  **[Official]**
- **Exported builds don't contain arbitrary files.** Non-resource data such as JSON has to
  be listed in the export preset `include_filter`, as `data/builds/*.json` is today. Adding a
  new runtime JSON file means updating `export_presets.cfg` and re-running the web test.
  **[Measured]** in this repo's existing export configuration.

## 9. Determinism and randomness

- **Separate seeded streams per consumer.** One shared RNG means adding a draw in one
  system shifts every other system's results. `seed_stream.gd` already does this (one named
  stream per purpose). **[Boneshed]**, **[Consensus]**.
- `RandomNumberGenerator` is reproducible for a given seed. The docs warn that it "does not
  have an avalanche effect" (hash external seeds), and `state` must only be restored from a
  saved `state`. **[Official]** The docs don't promise the same sequence across engine
  versions. Boneshed's worldgen therefore uses its own Mulberry32/FNV-1a so blueprints
  survive engine upgrades. That trade-off is justified for **persisted or shared** content
  (world addresses, Tower snapshots). For throwaway effects (spark jitter), the engine RNG is
  fine. **[Boneshed]**
- Never call the global `randf()` / `randi()` in rules or generation code; their seed is
  process-global. **[Consensus]**
- **Floats.** IEEE `+ − × ÷` and `sqrt` are deterministic on one binary and platform.
  Transcendental functions (`sin`, `pow`, `exp`) and different compilers or CPUs can differ
  in the last bits. For anything compared across machines (Tower validation, server checks),
  use quantized values (ticks, fixed decimals) and round before hashing, as the rules code
  already does with `PRECISION := 10000.0`. **[Consensus]**
- **Dictionary order** is insertion order. **[Official]** Outputs that are hashed or
  compared must iterate in an explicit sorted or catalog order, as the rules code does
  (`catalog.slot_order`, `_sorted(...)`). Never depend on incidental insertion order.

## 10. Serialization and versioning

- **Save data is ids plus primitives only.** Never save or load `Resource`/`Object` graphs
  (`.tres`, `var_to_bytes_with_objects`) from untrusted sources: "Deserialized object can
  contain code which gets executed… remote code execution." **[Official]** This is why
  Boneshed builds and bodies are strict JSON. **[Boneshed]**
- **JSON turns every number into `float`** **[Official]**, **[Measured]**. Cast explicitly
  (`int(x)`) when a field is semantically an integer. Validate that it was integral.
- Every persisted document carries `schema` and a catalog version, as builds, bodies and
  salvage refs already do. A loader rejects unknown versions instead of guessing.
  **[Boneshed]**
- When the first real persistence lands, add **explicit migration functions**
  (`v0 → v1`) with fixture files from each old version, tested to load into the current
  schema. Rejecting stale data is fine for prototypes, but rejecting players' saves is not.
  **[Consensus]**
- Content fingerprints use canonical JSON. Its float text depends on the engine's number
  formatting, so treat a fingerprint change after an engine upgrade as **expected
  invalidation to investigate**, not as a test to "fix" by regenerating blindly.
  **[Measured]** default `JSON.stringify` prints `0.1 + 0.2` as `0.3`.

## 11. Common GDScript footguns

| Footgun | Symptom | Avoid by |
| --- | --- | --- |
| Untyped variable changes type on reassignment | Integer math, quantized tweens | Static types (§1) |
| `Object.set("typo", v)` | Silently ignored | Typed assignment, or check `name in obj` |
| Mutating a loaded `Resource` | Change appears on every instance | `duplicate()` at the mutation point |
| Shallow `duplicate()` | Nested dictionary still shared | `duplicate(true)` / `duplicate_deep()` |
| `assert()` with side effects | Behavior differs in release | Asserts only check, never act |
| `_ready()` order | Children are ready *before* parents. An autoload's `_ready` runs before the main scene exists | Parents configure children after the children are ready. Don't reach for the main scene from an autoload's `_ready` |
| `_ready()` runs once | A node removed and re-added doesn't re-run it | `request_ready()` or explicit `reset()` |
| `await RenderingServer.frame_post_draw` under `--headless` | Hangs forever | Skip capture when `DisplayServer.get_name() == "headless"` **[Measured]** in the lab |
| Script error in a `--script` SceneTree run | Process keeps running instead of exiting | External `timeout` on every engine command **[Measured]** in the lab |
| New `class_name` added outside the editor | "Identifier not declared" | Run `--editor --import` to refresh the class cache **[Consensus]** |
| Agent writes a Godot 3 or pre-4.6 API (`yield`, `SkeletonIK3D`, `_process_modification()`) | Deprecated or wrong code | Check the 4.7.2 class reference |

## 12. Patterns AI agents commonly get wrong

These come from code review of agent-written Godot code, in this repository and in AI Game
Dev Lab. Each one is a review question, not a ban.

1. **Autoload for everything.** A `GameManager` or `CombatManager` singleton holding
   state that belongs to a scene. *Ask:* would two courtyards in one tree break? If yes, it
   isn't global. Boneshed has **zero** autoloads today, which is correct for its size.
2. **Oversized scripts.** One script doing input, physics, AI, animation and UI.
   `fighter.gd` (243 lines) already mixes movement, hit validation and ~100 lines of
   procedural visuals. Split *when the next feature lands there*, not speculatively.
   Line count alone isn't the test; the test is whether one change forces unrelated edits.
3. **String-keyed lookups without validation.** `get("field")`, `has_method("x")`,
   `call("name")`, magic event strings (`"guard"`, `"deflected"`), `get_node("../../X")`.
   Each typo fails silently or late. Prefer enums, constants, typed references, or a
   validated id table.
4. **Duplicate state.** The same fact stored in two places, e.g. a `is_attacking` bool
   beside `phase == WINDUP`. Derive it instead. Boneshed derives abilities from items for
   exactly this reason.
5. **Abstraction before the second use.** Generic `AbilitySystem`, `StateMachine`,
   `EventBus` or `ServiceLocator` frameworks built for one enemy. Write the concrete thing;
   extract when the second real case arrives and differs.
6. **Hardcoded tuning scattered across scripts.** Speeds, layers and timings as literals in
   several files. Gameplay numbers belong in data or one owner. Collision layers belong in
   named project layers plus constants.
7. **False lifecycle assumptions.** Accessing children in `_init`, assuming `_ready` order
   between siblings, assuming `queue_free` is immediate, reading physics state in `_process`
   and expecting tick alignment.
8. **Tests that restate the implementation.** Asserting that a constant equals itself, or
   that a value equals what the same code just computed. A useful test fails for a plausible
   bug: write the **negative control** and confirm it fails (this repo's runners already do).
   The [adapter mutation experiment](../evidence/engineering-audit/README.md#3-adapter-field-name-mutation-does-any-test-notice-a-dropped-field)
   shows how a test can pass while a whole category of bug goes undetected.
9. **Claiming verification that didn't happen.** "Tested" when only `--check-only` ran,
   or "feels responsive" from headless runs. Report exactly what ran.
10. **Outdated or invented API.** Code from Godot 3 or early 4.x, or plausible-sounding
    methods that don't exist. Check the class reference for 4.7.2.

## 13. Avoiding unnecessary complexity

- Solve today's requirement in the simplest form that keeps the established boundaries
  (rules ↔ presentation ↔ control). **[Boneshed]**
- A pure function in a `RefCounted` file is usually simpler than a `Node` with lifecycle.
  Use a `Node` when you need the tree: processing, transforms, signals to scene objects,
  or editor placement.
- Don't add configuration knobs nobody has asked to tune.
- When in doubt, write the concrete version and note the extraction point in a comment.
