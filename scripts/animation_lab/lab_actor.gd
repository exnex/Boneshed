extends RefCounted
## Stand-in for the rule side of combat in the animation lab. Owns a tiny command
## timeline (move, attack, guard, stagger, dodge) and the authoritative clock, then tells a
## LabCharacter which clip time to show. CombatState plays this role in a real
## integration; this class exists so the lab never imports or edits combat code.

const PhaseWarp := preload("res://scripts/animation_lab/phase_warp.gd")
const LabCharacter := preload("res://scripts/animation_lab/lab_character.gd")
const ClipLibrary := preload("res://scripts/animation_lab/clip_library.gd")
const BUILD_CATALOG := "res://data/builds/catalog.json"

var character: LabCharacter
var manifest: Dictionary
var commands: Array = []
var command: Dictionary = {}
var command_time := 0.0
var clock := 0.0
var velocity := Vector2.ZERO
var section := "idle"
var blade_live := false
var timing: Dictionary = {}

func _init(target: LabCharacter) -> void:
	character = target
	manifest = ClipLibrary.load_json(ClipLibrary.MANIFEST_PATH)

## Resolves a named timing from the manifest. Catalog-backed timings read windup, active
## and recovery from the shared build catalog (read-only) plus profile overrides; the
## commitment/release split mirrors CombatState's constants.
static func resolve_timing(manifest_data: Dictionary, name: String) -> Dictionary:
	var spec: Dictionary = manifest_data.timings[name]
	if not spec.has("from_build_catalog"):
		return spec.duplicate()
	var catalog := ClipLibrary.load_json(BUILD_CATALOG)
	var result := {"commitment": spec.commitment, "release": spec.release}
	for ability in catalog.abilities:
		if ability.id == spec.from_build_catalog:
			result.merge(ability.timing, true)
	for profile in catalog.profiles:
		if profile.id == spec.get("profile", ""):
			result.merge(profile.get("ability_overrides", {}).get(spec.from_build_catalog, {}), true)
	return result

## Commands: {"at": seconds, "do": "move"|"attack"|"guard"|"stagger"|"dodge"|"idle", ...}.
func schedule(list: Array) -> void:
	commands = list.duplicate(true)
	commands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)

func step(delta: float) -> void:
	while not commands.is_empty() and float(commands[0].at) <= clock:
		_start(commands.pop_front())
	_apply(delta)
	character.step(delta)
	clock += delta
	command_time += delta

func _start(next: Dictionary) -> void:
	command = next
	command_time = 0.0
	match str(next.do):
		"attack":
			timing = resolve_timing(manifest, next.timing)
			character.begin_action("slash", next.get("fade", 0.06))
		"guard":
			character.begin_action("guard", 0.08)
		"stagger":
			character.begin_action("stagger", 0.04)
		"dodge":
			character.begin_action("dodge_back", 0.05)
		_:
			if not character.action.is_empty():
				character.end_action(next.get("fade", 0.25))
	velocity = Vector2(next.get("velocity", [0.0, 0.0])[0], next.get("velocity", [0.0, 0.0])[1])

func _apply(delta: float) -> void:
	var kind := str(command.get("do", "idle"))
	section = kind
	blade_live = false
	match kind:
		"attack":
			var markers: Dictionary = manifest.clips.slash.markers
			var sample := PhaseWarp.sample(markers, timing, command_time)
			section = sample.section
			blade_live = section == "active"
			character.drive_action(sample.clip_time)
			if command_time >= PhaseWarp.total_duration(timing):
				_start({"at": clock, "do": "idle", "velocity": [velocity.x, velocity.y]})
		"guard":
			var raise: float = command.get("raise", 0.12)
			var hold: float = command.get("hold", 0.8)
			var lower: float = command.get("lower", 0.35)
			var knots := PackedVector2Array([Vector2(0, 0), Vector2(raise, 0.15), Vector2(raise + hold, 0.65), Vector2(raise + hold + lower, 1.2)])
			character.drive_action(PhaseWarp.piecewise(knots, command_time))
			if command.has("impact_at") and command_time >= float(command.impact_at) and not command.get("impact_fired", false):
				command["impact_fired"] = true
				character.flinch()
			section = "guard" if command_time < raise + hold else "lower"
			if command_time >= raise + hold + lower:
				_start({"at": clock, "do": "idle"})
		"stagger", "dodge":
			var duration: float = command.get("duration", 1.0)
			var clip: Animation = character.tree.get_animation("stagger" if kind == "stagger" else "dodge_back")
			character.drive_action(minf(command_time / duration, 1.0) * clip.length)
			if command_time >= duration:
				_start({"at": clock, "do": "idle"})
	character.set_locomotion(velocity)
	character.set_blade_live(blade_live)
	# Code-driven movement: rules move the body; animation only follows.
	var world := character.global_basis * Vector3(velocity.x, 0.0, -velocity.y)
	character.global_position += world * delta
