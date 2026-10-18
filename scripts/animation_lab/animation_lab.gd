extends Node3D
## Isolated animation lab director. Builds a neutral stage, spawns lab characters and
## plays one scripted sequence chosen with `-- --sequence=<name>`, then quits. Meant for
## Movie Maker capture (scripts/tooling/test_animation_lab.sh) and manual viewing.
## Touches nothing in the courtyard, combat, AI, HUD or shared builds.

const LabCharacter := preload("res://scripts/animation_lab/lab_character.gd")
const LabActor := preload("res://scripts/animation_lab/lab_actor.gd")
const ClipLibrary := preload("res://scripts/animation_lab/clip_library.gd")
const TRAIL_SAMPLES := 14

## Each sequence: camera (position, look target), duration, time scale and actors with
## spawn x offsets, options and command lists.
const SEQUENCES := {
	"overview": {
		"title": "Overview: idle, footwork, telegraphed slash, guard impact, stagger, dodge",
		"camera": [Vector3(-2.7, 1.55, -3.0), Vector3(0.0, 0.95, -0.5)], "duration": 17.0, "speed": 1.0,
		"actors": [{"x": 0.0, "label": "", "options": {}, "commands": [
			{"at": 0.0, "do": "idle"},
			{"at": 1.5, "do": "move", "velocity": [0.0, 0.9]},
			{"at": 3.0, "do": "move", "velocity": [0.8, 0.0]},
			{"at": 4.5, "do": "move", "velocity": [-0.8, 0.0]},
			{"at": 6.0, "do": "move", "velocity": [0.0, -0.9]},
			{"at": 7.2, "do": "idle"},
			{"at": 8.0, "do": "attack", "timing": "courtyard_slash"},
			{"at": 9.6, "do": "attack", "timing": "swordsman_slash"},
			{"at": 11.6, "do": "guard", "raise": 0.12, "hold": 0.9, "lower": 0.35, "impact_at": 0.55},
			{"at": 13.2, "do": "stagger", "duration": 1.1},
			{"at": 14.7, "do": "dodge", "duration": 1.0},
			{"at": 15.8, "do": "idle"}]}]},
	"timing": {
		"title": "Same clip, three rule timings: source pacing | courtyard slash | corrupted swordsman",
		"camera": [Vector3(-0.9, 1.55, -4.9), Vector3(0.0, 1.0, 0.0)], "duration": 6.5, "speed": 1.0,
		"actors": [
			{"x": 1.9, "label": "source pacing", "options": {}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 0.6, "do": "attack", "timing": "source_pacing"}, {"at": 3.6, "do": "attack", "timing": "source_pacing"}]},
			{"x": 0.0, "label": "courtyard slash 0.34/0.16/0.45", "options": {}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 0.6, "do": "attack", "timing": "courtyard_slash"}, {"at": 3.6, "do": "attack", "timing": "courtyard_slash"}]},
			{"x": -1.9, "label": "swordsman 0.62/0.16/0.65", "options": {}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 0.6, "do": "attack", "timing": "swordsman_slash"}, {"at": 3.6, "do": "attack", "timing": "swordsman_slash"}]}]},
	"move_attack": {
		"title": "Attacking while moving 0.9 m/s, side view: full-body clip (far) vs upper/lower split (near)",
		"camera": [Vector3(0.0, 1.25, -5.4), Vector3(0.0, 0.85, 0.0)], "duration": 6.0, "speed": 1.0,
		"actors": [
			{"x": 2.7, "z": 1.6, "yaw": 1.5708, "label": "full body", "options": {}, "commands": [{"at": 0.0, "do": "move", "velocity": [0.0, 0.9]}, {"at": 0.8, "do": "attack", "timing": "swordsman_slash", "velocity": [0.0, 0.9]}, {"at": 3.4, "do": "attack", "timing": "swordsman_slash", "velocity": [0.0, 0.9]}]},
			{"x": 2.7, "z": -0.6, "yaw": 1.5708, "label": "upper/lower split", "options": {"split_lower_body": true}, "commands": [{"at": 0.0, "do": "move", "velocity": [0.0, 0.9]}, {"at": 0.8, "do": "attack", "timing": "swordsman_slash", "velocity": [0.0, 0.9]}, {"at": 3.4, "do": "attack", "timing": "swordsman_slash", "velocity": [0.0, 0.9]}]}]},
	"four_arm": {
		"title": "Rig family: humanoid (left) and four-armed variant (right) share every human clip",
		"camera": [Vector3(-1.3, 1.55, -3.6), Vector3(0.0, 1.0, 0.0)], "duration": 8.0, "speed": 1.0,
		"actors": [
			{"x": 0.9, "label": "humanoid", "options": {}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 1.0, "do": "move", "velocity": [0.0, 0.7]}, {"at": 2.6, "do": "idle"}, {"at": 3.0, "do": "attack", "timing": "swordsman_slash"}, {"at": 5.0, "do": "guard", "impact_at": 0.5}, {"at": 6.6, "do": "stagger", "duration": 1.1}]},
			{"x": -0.9, "label": "four arms: lower pair = guard module + IK", "options": {"extra_arms": true, "tint": Color("a99a8f")}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 1.0, "do": "move", "velocity": [0.0, 0.7]}, {"at": 2.6, "do": "idle"}, {"at": 3.0, "do": "attack", "timing": "swordsman_slash"}, {"at": 5.0, "do": "guard", "impact_at": 0.5}, {"at": 6.6, "do": "stagger", "duration": 1.1}]}]},
	"closeup": {
		"title": "Slash at quarter speed: grip, wrist and shoulder deformation",
		"camera": [Vector3(-1.7, 1.6, -1.9), Vector3(0.1, 1.15, -0.3)], "duration": 2.2, "speed": 0.25,
		"actors": [{"x": 0.0, "label": "", "options": {}, "commands": [{"at": 0.0, "do": "idle"}, {"at": 0.15, "do": "attack", "timing": "courtyard_slash"}]}]},
}

var sequence: Dictionary
var actors: Array = []
var trails: Array = []
var labels: Array = []
var hud: Label
var elapsed := 0.0
var failed := false

func _ready() -> void:
	var name := "overview"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sequence="):
			name = arg.get_slice("=", 1)
	if not SEQUENCES.has(name):
		_fail("Unknown sequence %s; choose one of %s" % [name, SEQUENCES.keys()])
		return
	sequence = SEQUENCES[name]
	_build_stage()
	for spec in sequence.actors:
		var character := LabCharacter.new()
		add_child(character)
		character.position = Vector3(spec.x, 0.0, spec.get("z", 0.0))
		character.rotation.y = spec.get("yaw", 0.0)
		var errors: PackedStringArray = character.setup(ClipLibrary.trial_dir(), spec.options)
		if not errors.is_empty():
			_fail("Animation lab setup failed: %s" % ", ".join(errors))
			return
		var actor := LabActor.new(character)
		actor.schedule(spec.commands)
		actors.append(actor)
		trails.append({"samples": [], "mesh": _trail_mesh()})
		var label := Label3D.new()
		label.text = spec.label
		label.font_size = 30
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(spec.x, 2.25, spec.get("z", 0.0))
		label.modulate = Color("e6e1d3")
		add_child(label)
		labels.append(label)
	print(JSON.stringify({"animation_lab": name, "actors": actors.size(), "strides": actors[0].character.stride_speeds}))

func _fail(message: String) -> void:
	failed = true
	push_error(message)
	get_tree().quit(1)

func _process(delta: float) -> void:
	if failed or sequence.is_empty():
		return
	var dt: float = delta * float(sequence.speed)
	for i in actors.size():
		var actor: LabActor = actors[i]
		actor.step(dt)
		labels[i].position = actor.character.position + Vector3(0.0, 2.25, 0.0)
		labels[i].text = "%s\n%s" % [sequence.actors[i].label, actor.section]
		labels[i].modulate = Color("ff6a3d") if actor.blade_live else Color("e6e1d3")
		_update_trail(trails[i], actor)
	hud.text = "%s\nrule time %.2fs" % [sequence.title, elapsed]
	elapsed += dt
	if elapsed >= float(sequence.duration):
		get_tree().quit()

func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("12161b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("6c7480")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, -0.6, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	floor_mesh.mesh = plane
	var checker := ShaderMaterial.new()
	checker.shader = Shader.new()
	# Half-metre checker so foot sliding is visible against the ground.
	checker.shader.code = "shader_type spatial;\nvarying vec3 world;\nvoid vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\nvoid fragment() {\n\tvec2 cell = floor(world.xz / 0.5);\n\tfloat c = mod(cell.x + cell.y, 2.0);\n\tALBEDO = mix(vec3(0.16, 0.17, 0.18), vec3(0.27, 0.27, 0.26), c);\n\tROUGHNESS = 0.95;\n}\n"
	floor_mesh.material_override = checker
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(sequence.camera[0], sequence.camera[1])
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color("e6e1d3"))
	layer.add_child(hud)

func _trail_mesh() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

## Swept blade ribbon. Orange while the rule window is live, pale during the windup and
## release so the telegraph arc is visible, absent otherwise.
func _update_trail(trail: Dictionary, actor: LabActor) -> void:
	var samples: Array = trail.samples
	var showing := actor.section in ["committed", "release", "active"]
	if showing:
		var points: Array = actor.character.blade_points()
		samples.append([points[0], points[1], actor.blade_live])
	elif not samples.is_empty():
		samples.pop_front()
	while samples.size() > TRAIL_SAMPLES:
		samples.pop_front()
	var mesh: ImmediateMesh = trail.mesh.mesh
	mesh.clear_surfaces()
	if samples.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in samples.size():
		var alpha := float(i + 1) / samples.size() * 0.75
		var colour := Color(1.0, 0.42, 0.18, alpha) if samples[i][2] else Color(0.85, 0.88, 0.95, alpha * 0.45)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(samples[i][0])
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(samples[i][1])
	mesh.surface_end()
