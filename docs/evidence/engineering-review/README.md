# Independent engineering review — PR #14

Reviewed by Codex on 2026-10-18, independently of the author, at PR head
`ba17e2a09645e0f8033dae5bdbddb1fdebc26824` (runtime source equals `main` at `3dbcc08`).
Corrections in this review change documentation only. No gameplay refactor or settings change.

## Findings and merge assessment

Classifications apply to the original PR. Blocking documentation findings below are corrected
by the accompanying changes. **Ready to merge as documentation after these corrections**;
no merge performed. Gameplay follow-ups F1 and F14 remain open and do not block these guides.

| Classification | Finding | Disposition |
| --- | --- | --- |
| Blocking | A post-`await` `is_instance_valid(self)` cannot protect a freed coroutine owner. The code after the await is not reached in the reproduced case. | Replaced with owner/captured-reference/cancellation guidance; probe below. |
| Blocking | Integer rule timers do not make floating-point movement, engine physics or an entire Tower replay bit-exact across machines. | Removed the guarantee; require an authoritative replay design and platform verification before relying on it. |
| Blocking | `AGENTS.md` calls unmerged standards approved, while the checklist introduces extra permission gates and universal mutation requirements absent from the guide's MUST rules. | Explicit proposed-until-merge status; checklist scoped to the task; approval retained for third-party assets/dependencies under existing instructions. |
| Recommended improvement | `get_node()` is incorrectly listed as a Variant source; signals are described as always synchronous; stale inheritance paths are said to fail silently. | Corrected against reference and executable probes. |
| Recommended improvement | The >40% VM benchmark is not an isolated gain from type annotations; a blanket profiling mandate penalizes ordinary simplifications. | Corrected citation; require evidence for performance claims and substantial performance-driven rewrites. llvmpipe cannot predict desktop GPU performance, but scoped CPU measurements remain possible. |
| Recommended improvement | Copy guidance omits storage-property/constructor limits and conflates internal resources with scene-local duplication; capture-by-value can still share mutable contents. | Clarified Resource versus container copying and lambda aliasing. |
| Recommended improvement | Historical input/animation reports become stronger architectural prescriptions than the evidence supports. Navigation chunking and one AnimationTree per actor are premature defaults. | Document supported physics polling; make animation/navigation choices conditional and retain rule-owned hit timing as a Boneshed preference. |
| Recommended improvement | Missing pitfalls: UI-handled events do not gate global Input polling, interpolation reset after teleport, cast-to-null, physics-query access windows, navigation synchronization, UID sidecars, and bounded untrusted payloads. | Added concise, relevant cautions; no new systems implemented. |
| Recommended improvement | F1's 8/20 mutation result is real, but does not demonstrate an exploit or prove that every suite misses every mutation. Anatomy reload also fails and was omitted. | Reproduced 20 integration mutations; clarified F1 and added F14 with a narrow follow-up trigger. |
| Optional | The two guides are too long for daily cover-to-cover reading (originally 792 lines combined). | Checklist remains the entry point; read relevant sections only. Removed redundant self-review prose. Further pruning into topic references can wait for actual use. |

The layering and JSON/shared-data choices are reasonable for the current source. A typed
runtime declaration rule is useful for agents **with** inference, explicit Variant boundaries
and justified duck typing; it must not trigger wrapper hierarchies or unrelated rewrites.
No evidence justifies adopting a global event bus, component framework, Jolt migration,
integer-tick rewrite or scene migration as part of this PR.

## Engine and official evidence

Used **Godot `4.7.2.stable.official.ed1daf0bf`** at
`/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64`, never the `godot`
command on PATH (which was 4.6.3). Re-fetched the official release SHA-512 list and matched
the installed engine archive:

```text
9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65  Godot_v4.7.2-stable_linux.x86_64.zip
```

Checked official source, rather than relying on the original author's interpretation:

- [Resource](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Resource.xml),
  [Object](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Object.xml),
  [Node](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Node.xml):
  copying, deferred connections, lifetime, typed node lookup and interpolation reset.
- [Input reference](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Input.xml)
  and [implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/core/input/input.cpp):
  physics-tick versus render-frame press tracking. Synthetic 30/240 FPS experiments below
  agree; this does not prove every physical-device edge case.
- [ProjectSettings](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/ProjectSettings.xml),
  [AnimationMixer](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/AnimationMixer.xml),
  [NavigationAgent3D](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/NavigationAgent3D.xml),
  [SkeletonModifier3D](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/SkeletonModifier3D.xml):
  DEFAULT physics backend, interpolation/warning defaults, animation callback modes,
  navigation synchronization and `_process_modification_with_delta`.
- [GDScript basics](https://github.com/godotengine/godot-docs/blob/9adca4c1c729/tutorials/scripting/gdscript/gdscript_basics.rst),
  [static typing](https://github.com/godotengine/godot-docs/blob/9adca4c1c729/tutorials/scripting/gdscript/static_typing.rst)
  and [scene organization](https://github.com/godotengine/godot-docs/blob/9adca4c1c729/tutorials/best_practices/scene_organization.rst).
- [VM PR #70838](https://github.com/godotengine/godot/pull/70838): read the benchmark and
  comparison directly; its >40% compares VM revisions, and its typed example also changes
  `Array` to `PackedInt32Array`.

The published [4.7 Resource page](https://docs.godotengine.org/en/4.7/classes/class_resource.html)
was reachable during this review. The original author's blocked access is historical;
not every published or community URL was checked. External AI Game Dev Lab fixtures were not
inspected and are not claimed as independent verification. Subsequent URL checks returned
403 for some published/docs/community requests despite the earlier successful Resource
request; inaccessible URLs are not counted as verified or as proven broken.

## Lifetime and API probe

Save the following as `work/api_probe.gd` in a scratch checkout (`work/.gdignore` keeps the
editor from importing scratch assets), then run with the exact engine:

```sh
source scripts/tooling/env.sh
check_godot
timeout 15 "$GODOT_BIN" --headless --path . --script work/api_probe.gd
```

```gdscript
extends SceneTree
class TestState extends RefCounted:
	var damage := 32.0
class Receiver extends Node:
	func wait_for_timer(tree: SceneTree, label: String) -> void:
		print(label + "_started")
		await tree.create_timer(0.04).timeout
		print(label + "_resumed")
		print("self_valid=", is_instance_valid(self))
class Emitter extends RefCounted:
	signal fired
class Box extends Resource:
	@export var payload: Array = []
	@export var child: Resource
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var state := TestState.new()
	state.set("damgae", 99.0)
	print("silent_set=", state.damage, ",member_exists=", "damgae" in state)
	var holder := Node.new()
	holder.name = "Holder"
	root.add_child(holder)
	var inferred := root.get_node("Holder")
	print("get_node_inferred=", inferred is Node)
	var box := Box.new()
	box.payload = [[1]]
	box.child = Resource.new()
	box.child.resource_path = "res://external.tres"
	var copy := box.duplicate(true) as Box
	copy.payload[0][0] = 7
	print("resource_deep_nested_array=", box.payload[0][0], ",external_shared=", copy.child == box.child)
	var array: Array = [1]
	var callback := func(): print("lambda_shared_array=", array[0])
	array[0] = 9
	callback.call()
	var emitter := Emitter.new()
	emitter.fired.connect(func(): print("signal_default"))
	emitter.fired.connect(func(): print("signal_deferred"), CONNECT_DEFERRED)
	emitter.fired.emit()
	print("after_emit")
	print("json_integer_is_float=", typeof(JSON.parse_string("1")) == TYPE_FLOAT)
	print("json_float_text=", JSON.stringify(0.1 + 0.2))
	print("physics_engine_setting=", ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("physics_server=", PhysicsServer3D.get_class())
	var gone := Receiver.new()
	root.add_child(gone)
	gone.wait_for_timer(self, "freed_owner")
	gone.free()
	await create_timer(0.10).timeout
	print("surviving_owner_await_done")
	holder.free()
	quit()
```

Observed (exit 0, no engine/script errors):

```text
silent_set=32.0,member_exists=false
get_node_inferred=true
resource_deep_nested_array=1,external_shared=true
lambda_shared_array=9
signal_default
after_emit
json_integer_is_float=true
json_float_text=0.3
physics_engine_setting=DEFAULT
physics_server=PhysicsServer3D
freed_owner_started
signal_deferred
surviving_owner_await_done
```

`freed_owner_resumed` and its self-check never print. The surviving SceneTree's timer
continues. Resource copying preserves the original nested array but shares the child with
an external resource path, consistent with `DEEP_DUPLICATE_INTERNAL`.

A separate headless probe confirms that process frames continue while no post-draw signal
arrives during the timed interval (exit 0, observed `headless_frames=17,post_draws=0`):

```gdscript
extends SceneTree
var post_draws := 0
func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(func(): post_draws += 1)
	run.call_deferred()
func run() -> void:
	await create_timer(0.1).timeout
	print("headless_frames=", Engine.get_process_frames(), ",post_draws=", post_draws)
	quit(int(post_draws != 0))
```

## Adapter mutations and warning census

For each field below, use a **fresh archive of the reviewed head**, import it once, replace
only `state.set(field, ` with
`state.set(field + ("_typo" if field == "FIELD" else ""), `, then run
`res://scripts/qa/combat_build_tests.gd` with the pinned engine and a timeout. Restore the
adapter before the next field. Parse the JSON summary and inspect engine errors and exit
status, rather than counting grep matches (a crash could otherwise look like zero failures).
The adapter file in the working PR was never mutated.

| Mutated field | Failed integration checks | Exit |
| --- | --- | --- |
| `max_health` | 2 | 1 |
| `max_posture` | 0 | 0 |
| `deflect_window` | 0 | 0 |
| `guard_chip` | 0 | 0 |
| `posture_recovery_rate` | 1 | 1 |
| `posture_recovery_delay` | 0 | 0 |
| `deflect_posture` | 1 | 1 |
| `guard_posture_overrides` | 2 | 1 |
| `attack_windup` | 3 | 1 |
| `heavy_windup` | 0 | 0 |
| `light_active_duration` | 2 | 1 |
| `heavy_active_duration` | 0 | 0 |
| `light_recovery_duration` | 3 | 1 |
| `heavy_recovery_duration` | 2 | 1 |
| `light_damage` | 1 | 1 |
| `heavy_damage` | 1 | 1 |
| `light_hit_posture` | 1 | 1 |
| `heavy_hit_posture` | 0 | 0 |
| `light_guard_posture` | 1 | 1 |
| `heavy_guard_posture` | 0 | 0 |

Exactly **8/20** mutations pass; none emits an engine error. This matches the original
report. A separate probe passes a prepared player config with `deflect_window = 0.11`
through the unmodified `create_state`; the resulting state is `0.11`. No current stat loss
or player-controlled property-name exploit was demonstrated. Each mutation ran the
integration suite, **not every suite**. F1's proposed error check must also propagate failure
through the existing `CombatState`-returning API; it is not safely described as just ten lines.

Repeated the warning census in the scratch archive by setting these five warnings to `2`
(Error) under `[debug]`: `untyped_declaration`, `unsafe_property_access`,
`unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`. For each tracked `.gd` script,
ran `--headless --check-only --script res://PATH` and counted `SCRIPT ERROR: Parse Error:`
reports. Results: **2,558 total / 844 production**, matching the original census. The four
actor/rule scripts contribute 12; **the adapter contributes another 28**. Counts are
diagnostics, may repeat dependency errors and are not distinct defects or a mandate to type
all JSON access.

## Additional source probes

Run these as `--script` files with the same command above. The first intentionally produces
engine errors: they are the result being reproduced, not a passing baseline suite.

```gdscript
extends SceneTree
const Catalog = preload("res://scripts/anatomy/anatomy_catalog.gd")
func _initialize() -> void:
	var catalog := Catalog.new()
	print("first_load=", catalog.load_file())
	print("second_load=", catalog.load_file())
	print("reported_errors=", catalog.errors)
	quit()
```

Observed: `first_load=true`, `second_load=false`, four `Dictionary is in read-only state`
errors at `anatomy_catalog.gd:70`, then duplicate-id errors in `catalog.errors`. New catalog
instances work; repeated loads on a single instance do not. This is F14, deferred until
reload is used.

```gdscript
extends SceneTree
const Rules = preload("res://scripts/combat/combat_state.gd")
func _initialize() -> void:
	for step: float in [1.0 / 60.0, 0.6]:
		var state := Rules.new()
		state.attack()
		var active_samples := 0
		for i in range(int(round(0.6 / step))):
			state.tick(step)
			active_samples += int(state.phase == Rules.Phase.ACTIVE)
		print("step=", step, ",active_samples=", active_samples)
	quit()
```

Observed: 10 active samples at 1/60 second, zero at 0.6 seconds. Phase overshoot preserves
elapsed time but cannot guarantee a sampled hit when a step spans an entire active window.
This is a limit on the original audit's step-size claim, not a reproduced 60 Hz gameplay bug.

Save the input probe below and run twice, adding `--fixed-fps 30` and `--fixed-fps 240`
before `--script`. Each exits 0 and prints `physics_press_seen,held=false` followed by
`physics_press_count=1`, despite press and release occurring between physics samples.

```gdscript
extends SceneTree
class Poller extends Node:
	var ticks := 0
	var injected := false
	var seen := 0
	func _ready() -> void:
		InputMap.add_action("review_probe")
	func _process(_delta: float) -> void:
		if not injected and ticks >= 2:
			injected = true
			for pressed: bool in [true, false]:
				var event := InputEventAction.new()
				event.action = "review_probe"
				event.pressed = pressed
				Input.parse_input_event(event)
	func _physics_process(_delta: float) -> void:
		ticks += 1
		if Input.is_action_just_pressed("review_probe"):
			seen += 1
			print("physics_press_seen,held=", Input.is_action_pressed("review_probe"))
		if injected and ticks > 8:
			print("physics_press_count=", seen)
			get_tree().quit(int(seen != 1))
func _initialize() -> void:
	root.add_child.call_deferred(Poller.new())
```

## Validation and remaining uncertainty

All runners used the exact engine through `scripts/tooling/env.sh`:

| Check | Independent result |
| --- | --- |
| `test.sh` with `BONESHED_GRAPHICAL_TIMEOUT=900` | All 16 subprocesses at expected exits: 76 integration checks, 118 combat checks, encounter regressions, 111 graphical checks plus five PNGs, headless/rendered timing, and all nine negative controls. Rendered timing: 209 checks. |
| `test_builds.sh` | 137 checks; two examples byte-identical. |
| `test_worldgen.sh` | 80 checks; sixteen examples byte-identical. |
| `test_anatomy.sh` | 190 checks; two examples byte-identical. |
| Final `--headless --editor --import` | Exit 0; no engine/script errors. |
| Documentation paths/anchors and fenced blocks | 11 Markdown files, 58 relative links/anchors, zero broken; fences balanced. |
| External source URLs | 37 checked, including the replacement pinned physics-query source; 27 responded 200, ten requests were denied with 403. Pinned GitHub source references were accessible; denied requests are not verified. |
| `git diff --check` and change scope | Clean whitespace; tracked changes are Markdown only. |

The initial import attempt under a socket-restricted sandbox logged TCP-listen errors.
Rerunning with network/socket access permitted passed; those initial environment errors are
not a project failure. Rendered runs used Xvfb and llvmpipe (LLVM 19.1.7); their frame times
are not desktop GPU performance evidence. `test_web.sh` was not run because runtime,
exports and input implementation are unchanged.

No human playtest, supported-platform replay comparison, Jolt migration, physical-input
latency measurement, or GPU performance profile was performed. Historical scene-inheritance
and animation/Area timing reports were not reproduced as engine bugs. Resource-copy and
coroutine experiments cover the shown cases, not every loader/cache/cancellation scenario.
