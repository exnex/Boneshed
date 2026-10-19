extends Node3D
## Presentation/collision only. All composition is derived from the layout and its
## blueprint. No combat rules, random global state, imported assets or terrain noise.
const Layout = preload("res://scripts/expedition/expedition_layout.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const Modules = preload("res://scripts/combat/attack_modules.gd")

var layout: Dictionary
var stone: StandardMaterial3D
var trim: StandardMaterial3D
var accent: StandardMaterial3D
var glow: StandardMaterial3D
var water: StandardMaterial3D
var ice: StandardMaterial3D
var ember: StandardMaterial3D
var bone: StandardMaterial3D
var collision: StaticBody3D
var arena_gate: StaticBody3D

func _ready() -> void:
	var axes: Dictionary = layout.identity.axes
	var tags: Array = layout.identity.tags
	var atmosphere: Dictionary = layout.blueprint.generation.atmosphere
	var cold := Color("728e9c").lerp(Color("70524b"), (float(axes.temperature) + 1.0) * 0.5)
	stone = _material(Color("303e46").lerp(cold, 0.3))
	trim = _material(cold.lightened(0.14))
	var tint := Color("7db5c4") if float(axes.temperature) < 0.0 else Color("df9e64")
	if "wealth" in tags:
		tint = Color("d4b56d")
	if "profane" in tags:
		tint = tint.lerp(Color("a571a5"), 0.55)
	if "water" in tags:
		tint = tint.lerp(Color("6eabb2"), 0.8)
	accent = _material(tint.darkened(0.25))
	glow = _material(tint, true)
	water = _material(Color("1f4d5b"))
	water.metallic = 0.45
	water.roughness = 0.2
	ice = _material(Color("91c8d2"))
	ember = _material(Color("d76c32"), true)
	bone = _material(Color("bbb69e"))
	collision = StaticBody3D.new()
	collision.name = "WorldCollision"
	collision.collision_layer = Modules.ENVIRONMENT_LAYER
	collision.collision_mask = 0
	add_child(collision)
	_environment(atmosphere, tint)
	var stream := Stream.new(Layout.VERSION + "|" + layout.blueprint.streams.terrain)
	for tile: Array in layout.tiles:
		var center := Vector3(tile[0] * Layout.CELL, -0.3, tile[1] * Layout.CELL)
		_box(center, Vector3(Layout.CELL, 0.6, Layout.CELL), stone, true)
		_box(center + Vector3(0.0, 0.306, 0.0), Vector3(3.93, 0.012, 3.93), trim if stream.next_float() > 0.86 else stone)
	for edge: Array in layout.edges:
		var point := Vector3(edge[0] * Layout.CELL + edge[2] * 2.0, 0.65, edge[1] * Layout.CELL + edge[3] * 2.0)
		var size := Vector3(0.45, 1.3, Layout.CELL + 0.4) if edge[2] != 0 else Vector3(Layout.CELL + 0.4, 1.3, 0.45)
		_box(point, size, stone, true)
		_box(point + Vector3.UP * 0.68, Vector3(size.x + 0.12, 0.12, size.z + 0.12), trim)
	for module: Dictionary in layout.modules:
		_landmark(module, axes, tags, stream)
	_distant_ruins(axes)
	# A thin, noncolliding inlay points through each bend, without a quest system.
	for i in range(1, layout.path.size()):
		var start := point(layout.path[i - 1])
		var end := point(layout.path[i])
		var size := (end - start).abs() + Vector3(0.14, 0.015, 0.14)
		_box((start + end) * 0.5 + Vector3.UP * 0.018, size, accent)
	var ring := TorusMesh.new()
	ring.inner_radius = 8.8
	ring.outer_radius = 8.9
	_mesh(ring, point(layout.arena) + Vector3.UP * 0.026, Vector3(1, 0.025, 1), accent)

func _distant_ruins(axes: Dictionary) -> void:
	# Silhouettes below/beyond the bounded causeway create a desolate horizon.
	# They have no collision and cannot intrude on traversal or camera clearance.
	var stream := Stream.new(Layout.VERSION + "|" + layout.blueprint.streams.atmosphere)
	var silhouette := _material(stone.albedo_color.darkened(0.45))
	for module: Dictionary in layout.modules:
		var center := Vector3(module.center[0] * Layout.CELL, 0, module.center[1] * Layout.CELL)
		for sign_value in [-1.0, 1.0]:
			for i in range(3):
				var height := 16.0 + stream.next_float() * 14.0 + maxf(0, float(axes.elevation)) * 12.0
				var p := center + Vector3(sign_value * (28.0 + stream.next_float() * 24.0), height * 0.5 - 18.0, (i - 1) * 14.0)
				var spire := _box(p, Vector3(4.0 + stream.next_float() * 4, height, 5.0), silhouette)
				spire.rotation.z = sign_value * (0.03 + float(layout.blueprint.generation.atmosphere.wind) * 0.1)
				_box(p + Vector3(0, height * 0.4, 0), Vector3(9, 1, 7), silhouette)

func _landmark(module: Dictionary, axes: Dictionary, tags: Array, stream: Stream) -> void:
	var center := Vector3(module.center[0] * Layout.CELL, 0.0, module.center[1] * Layout.CELL)
	var arena: bool = module.id == "soul_arena"
	var side := 12.0 if arena else 8.0
	var height := 4.5 + (float(axes.elevation) + 1.0) * 3.0
	var ruin: float = layout.blueprint.generation.terrain.ruin_level
	if "built" in tags or "sacred" in tags:
		height += 2.0
	for sign_value in [-1.0, 1.0]:
		for z in [-6.0, 6.0]:
			var base := center + Vector3(sign_value * side, 0.0, z)
			var h := height * (1.0 - ruin * (0.1 + stream.next_float() * 0.4))
			if not _solid_prop(base + Vector3.UP * h * 0.5, Vector3(0.9, h, 1.2), trim):
				continue
			_box(base + Vector3.UP * (h + 0.15), Vector3(1.35, 0.3, 1.65), accent)
			if "bone" in tags:
				var rib := _box(base + Vector3(-sign_value * 0.8, h * 0.7, 0.0), Vector3(0.55, h * 0.7, 0.7), bone)
				rib.rotation.z = sign_value * -0.45
			elif "thorn" in tags or "wild" in tags:
				var thorn := _mesh(CylinderMesh.new(), base + Vector3(-sign_value, 1.8, 0), Vector3(0.25, 2, 0.25), stone)
				thorn.rotation.z = sign_value * 0.65
			# Side channels stay away from the route and are purely atmospheric.
			if "water" in tags:
				_box(base + Vector3(-sign_value * 1.5, 0.025, 0), Vector3(1.5, 0.03, 3.6), water)
			if "cold" in tags and ("fire" not in tags or sign_value < 0):
				_box(base + Vector3(-sign_value * 1.5, 0.045, 0), Vector3(1.5, 0.04, 3.6), ice)
				var shard := _mesh(PrismMesh.new(), base + Vector3(-sign_value * 0.8, 0.7, 1.5), Vector3(0.6, 1.4, 0.6), ice)
				shard.rotation.z = sign_value * 0.25
			if "fire" in tags and ("cold" not in tags or sign_value > 0):
				_box(base + Vector3(-sign_value * 1.5, 0.04, 0), Vector3(1.5, 0.04, 3.6), _material(Color("292a2c")))
				for crack in [-0.5, 0.3]:
					_box(base + Vector3(-sign_value * 1.5 + crack, 0.07, 0), Vector3(0.1, 0.025, 3.4), ember)
		# Gate shoulders frame the exit but leave 14+ m of open camera space.
		var gate := center + Vector3(sign_value * side, height * 0.8, -6)
		var beam := _box(gate + Vector3(-sign_value * 1.0, 0.0, 0), Vector3(3.2 - ruin * 1.4, 0.6, 1.4), trim)
		beam.rotation.z = sign_value * 0.32
		var beacon := center + Vector3(sign_value * (side - 1.0), 1.5, 0.0)
		if not _solid_prop(beacon - Vector3.UP * 0.75, Vector3(0.55, 1.5, 0.55), stone):
			continue
		_mesh(SphereMesh.new(), beacon + Vector3.UP * 0.4, Vector3(0.25, 0.6, 0.25), glow)
		var lamp := OmniLight3D.new()
		lamp.position = beacon + Vector3.UP
		lamp.light_color = glow.albedo_color
		lamp.light_energy = 2.4
		lamp.omni_range = 8.0
		add_child(lamp)
	if module.id == "reliquary":
		# A ruined, empty reliquary at the side: a visual destination, no loot system.
		_solid_prop(center + Vector3(6.5, 0.35, 0), Vector3(1.4, 0.7, 3.0), trim)
		_solid_prop(center + Vector3(6.5, 1.0, 0), Vector3(0.8, 0.6, 2.4), accent)
		if float(axes.enclosure) > 0.2:
			_box(center + Vector3(0, height + 1, 0), Vector3(17, 0.5, 10), stone)

func _solid_prop(location: Vector3, size: Vector3, material: Material) -> bool:
	# Connector bends can cross a room's side. Omit solid scenery from the reserved
	# route rather than letting a decorative column obstruct traversal or the camera.
	for i in range(1, layout.path.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(Vector2(location.x, location.z), Vector2(layout.path[i - 1][0], layout.path[i - 1][1]), Vector2(layout.path[i][0], layout.path[i][1]))
		if nearest.distance_to(Vector2(location.x, location.z)) < 3.0 + maxf(size.x, size.z) * 0.5:
			return false
	_box(location, size, material, true)
	return true

func set_arena_sealed(sealed: bool) -> void:
	if sealed == is_instance_valid(arena_gate):
		return
	if not sealed:
		remove_child(arena_gate)
		arena_gate.queue_free()
		arena_gate = null
		return
	# A visible portcullis at the arena's entrance keeps the existing direct-steer
	# enemy in open duel geometry. It opens after victory; no navigation/AI fork.
	arena_gate = StaticBody3D.new()
	arena_gate.name = "ArenaPortcullis"
	arena_gate.collision_layer = Modules.ENVIRONMENT_LAYER
	arena_gate.collision_mask = 0
	var center := point(layout.arena) + Vector3(0, 1.5, 14)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 3.0, 0.4)
	collider.shape = box
	collider.position = center
	arena_gate.add_child(collider)
	add_child(arena_gate)
	for x in range(-5, 6):
		var bar := _box(center + Vector3(x, 0, 0), Vector3(0.16, 3, 0.3), accent)
		bar.reparent(arena_gate)
	var rail := _box(center + Vector3(0, 1.5, 0), Vector3(12, 0.3, 0.4), trim)
	rail.reparent(arena_gate)

func _environment(atmosphere: Dictionary, tint: Color) -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101c28").lerp(tint.darkened(0.8), 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a6becd").lerp(tint, 0.25)
	# Floor brightness and fog are clamped for the existing telegraphs.
	environment.ambient_light_energy = 0.25 + float(atmosphere.light_level) * 0.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = environment.background_color.lightened(0.12)
	environment.fog_density = 0.003 + float(atmosphere.fog_density) * 0.006
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("e3ddcc").lerp(tint, 0.15)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)

static func point(coordinates: Array) -> Vector3:
	return Vector3(float(coordinates[0]), 0.0, float(coordinates[1]))

func _material(color: Color, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material

func _mesh(mesh: Mesh, location: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	instance.scale = size
	add_child(instance)
	return instance

func _box(location: Vector3, size: Vector3, material: Material, solid := false) -> MeshInstance3D:
	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = location
		collision.add_child(shape)
	return _mesh(BoxMesh.new(), location, size, material)
