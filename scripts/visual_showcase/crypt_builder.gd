extends RefCounted
## Assembles the showcase crypt from data/visual_showcase/crypt_layout.json: modular
## pieces (crypt_kit.gd) merged into one static mesh, box collision on the environment
## layer (as the lab arena), lights from piece sockets, fog, fire and dust effects, and
## the environment for the chosen quality preset. A generator could emit the same
## layout file; nothing here is specific to this room except the data.
##
## Returns {"mesh": MeshInstance3D, "triangles", "pieces", "lights": Array[Light3D],
##   "fx": Callable(point, color, outcome), "animate": Callable(delta), "environment"}.

const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")
const Kit = preload("res://scripts/visual_showcase/crypt_kit.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const LAYOUT_PATH := "res://data/visual_showcase/crypt_layout.json"
const LAYOUT_SCHEMA := "boneshed.crypt_layout.v0"
const ENVIRONMENT_LAYER := 1
const PIECES := ["floor_tile", "wall", "doorway", "pillar", "arcade", "rib", "ceiling", "dais", "sarcophagus", "brazier",
	"candles", "fallen_column", "rubble", "bones", "banner", "chain", "sconce"]

static func load_layout(path := LAYOUT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["missing crypt layout"]}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var errors: Array[String] = []
	if not data is Dictionary or data.get("schema") != LAYOUT_SCHEMA or not data.get("pieces") is Array:
		return {"ok": false, "errors": ["invalid crypt layout"]}
	for piece: Variant in data.pieces:
		if not piece is Dictionary or not piece.get("piece") in PIECES or not piece.get("at") is Array or (piece.at as Array).size() != 2:
			errors.append("invalid piece: " + str(piece))
		elif not (piece.get("rot") is float or piece.get("rot") is int) or not (piece.get("seed") is float or piece.get("seed") is int):
			errors.append("piece needs numeric rot and seed: " + str(piece))
	return {"ok": errors.is_empty(), "errors": errors, "data": data}

static func piece_transform(piece: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(piece.rot))), Vector3(float(piece.at[0]), float(piece.get("y", 0.0)), float(piece.at[1])))

## Builds geometry and collision only (no lights/fx): for tests and benchmarks.
static func build_geometry(layout: Dictionary) -> Dictionary:
	var kit := MeshKit.new(false)
	var collision: Array = []
	var sockets: Array = []
	for piece: Dictionary in layout.pieces:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(piece.seed) * 7919 + 17
		var xf := piece_transform(piece)
		kit.base = xf
		var out := build_piece(str(piece.piece), kit, rng, str(piece.get("variant", "plain")))
		for entry: Array in out.get("collision", []):
			collision.append([xf * (entry[0] as Transform3D), entry[1]])
		var piece_sockets: Dictionary = out.get("sockets", {})
		for key: String in piece_sockets:
			var value: Variant = piece_sockets[key]
			if value is Array:
				for point: Vector3 in value:
					sockets.append({"kind": key, "piece": piece.piece, "point": xf * point})
			else:
				sockets.append({"kind": key, "piece": piece.piece, "point": xf * (value as Vector3)})
	kit.base = Transform3D.IDENTITY
	return {"kit": kit, "collision": collision, "sockets": sockets}

static func build_piece(kind: String, kit: MeshKit, rng: RandomNumberGenerator, variant: String) -> Dictionary:
	match kind:
		"floor_tile":
			return Kit.floor_tile(kit, rng, variant)
		"wall":
			return Kit.wall(kit, rng, variant)
		"doorway":
			return Kit.doorway(kit, rng, variant)
		"pillar":
			return Kit.pillar(kit, rng, variant)
		"arcade":
			return Kit.arcade(kit, rng, variant)
		"rib":
			return Kit.rib(kit, rng, variant)
		"ceiling":
			return Kit.ceiling(kit, rng, variant)
		"dais":
			return Kit.dais(kit, rng, variant)
		"sarcophagus":
			return Kit.sarcophagus(kit, rng, variant)
		"brazier":
			return Kit.brazier(kit, rng, variant)
		"candles":
			return Kit.candles(kit, rng, variant)
		"fallen_column":
			return Kit.fallen_column(kit, rng, variant)
		"rubble":
			return Kit.rubble(kit, rng, variant)
		"bones":
			return Kit.bones(kit, rng, variant)
		"banner":
			return Kit.banner(kit, rng, variant)
		"chain":
			return Kit.chain(kit, rng, variant)
		"sconce":
			return Kit.sconce(kit, rng, variant)
	push_error("Unknown crypt piece: " + kind)
	return {}

static func build(parent: Node3D, quality: Dictionary) -> Dictionary:
	var loaded := load_layout()
	if not loaded.ok:
		push_error("Crypt layout invalid: " + JSON.stringify(loaded.errors))
		return {}
	var layout: Dictionary = loaded.data
	var geometry := build_geometry(layout)
	var kit: MeshKit = geometry.kit
	var room := Node3D.new()
	room.name = "Crypt"
	parent.add_child(room)
	var mesh := MeshInstance3D.new()
	mesh.name = "Architecture"
	mesh.mesh = kit.commit()
	room.add_child(mesh)
	for entry: Array in geometry.collision:
		var body := StaticBody3D.new()
		body.collision_layer = ENVIRONMENT_LAYER
		body.collision_mask = 0
		body.transform = entry[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[1]
		shape.shape = box
		body.add_child(shape)
		room.add_child(body)
	var lights: Array[Light3D] = []
	var flames: Array[Dictionary] = []
	var environment := _environment(room, quality, layout)
	lights.append(_moon(room, quality, layout))
	# Moonlight bouncing off the lit floor: a soft, shadowless cold fill on the duel.
	var bounce := OmniLight3D.new()
	bounce.name = "MoonBounce"
	bounce.light_color = Color("8ea4d8")
	bounce.light_energy = 1.5
	bounce.omni_range = 10.0
	bounce.omni_attenuation = 1.2
	bounce.position = Vector3(0.4, 2.2, 1.0)
	bounce.light_specular = 0.3
	room.add_child(bounce)
	lights.append(bounce)
	var shadows_left := int(quality.positional_shadows)
	for socket: Dictionary in geometry.sockets:
		match socket.kind:
			"fire":
				var is_brazier: bool = socket.piece == "brazier"
				if not is_brazier and not quality.torches:
					continue
				var light := OmniLight3D.new()
				light.light_color = Color("ff9a4a") if is_brazier else Color("ffad66")
				light.light_energy = 2.6 if is_brazier else 1.1
				light.omni_range = 9.0 if is_brazier else 5.5
				light.omni_attenuation = 1.4
				light.position = socket.point + Vector3(0.0, 0.25, 0.0)
				light.shadow_enabled = is_brazier and shadows_left > 0
				light.light_volumetric_fog_energy = 1.5
				if light.shadow_enabled:
					shadows_left -= 1
				room.add_child(light)
				lights.append(light)
				var fire := _fire(socket.point, 1.0 if is_brazier else 0.45, quality)
				room.add_child(fire)
				flames.append({"light": light, "base": light.light_energy, "phase": float(flames.size()) * 1.7})
			"flames":
				var flame := _candle_flame(socket.point)
				room.add_child(flame)
	var fog_cards: Array[MeshInstance3D] = []
	if quality.fog_cards:
		fog_cards = _fog_cards(room)
		room.add_child(_shaft(layout))
	var dust := _dust(layout, quality)
	room.add_child(dust)
	var sparks := _SparkPool.new(room, quality)
	var clock := [0.0]
	var animate := func(delta: float) -> void:
		clock[0] += delta
		var t: float = clock[0]
		for f: Dictionary in flames:
			var light: OmniLight3D = f.light
			var ph: float = f.phase
			light.light_energy = f.base * (0.86 + 0.1 * sin(t * 9.0 + ph) + 0.06 * sin(t * 23.0 + ph * 2.3) + 0.04 * sin(t * 3.1 + ph))
		for i in range(fog_cards.size()):
			var mat := fog_cards[i].material_override as StandardMaterial3D
			mat.uv1_offset = Vector3(t * 0.008 * (1.0 + i * 0.3), t * 0.004, 0.0)
	var fx := func(point: Vector3, color: Color, outcome: String) -> void:
		sparks.burst(point, color, outcome)
	return {"mesh": mesh, "room": room, "triangles": kit.triangle_count, "pieces": layout.pieces.size(), "lights": lights,
		"fx": fx, "animate": animate, "environment": environment, "collision_boxes": geometry.collision.size()}

static func _environment(room: Node3D, quality: Dictionary, layout: Dictionary) -> Environment:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("06080b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a4a5e")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.06
	env.glow_enabled = quality.glow
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("1d2633")
	env.fog_density = 0.018
	env.fog_height = 0.9
	env.fog_height_density = 0.25
	env.fog_sky_affect = 0.0
	if quality.renderer == "forward_plus":
		env.ssao_enabled = quality.ssao
		env.ssao_radius = 1.4
		env.ssao_intensity = 2.2
		env.ssil_enabled = quality.ssil
		env.ssil_radius = 4.0
		env.volumetric_fog_enabled = quality.volumetric_fog
		env.volumetric_fog_density = 0.028
		env.volumetric_fog_albedo = Color("aab4c4")
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_length = 32.0
		env.volumetric_fog_ambient_inject = 0.15
		if quality.volumetric_fog:
			env.fog_density = 0.006
	world.environment = env
	room.add_child(world)
	return env

static func _moon(room: Node3D, quality: Dictionary, layout: Dictionary) -> DirectionalLight3D:
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	var d: Array = layout.get("moon", {}).get("direction", [0.24, -0.93, 0.28])
	var direction := Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
	moon.basis = Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK)
	moon.light_color = Color(str(layout.get("moon", {}).get("color", "b8c8ff")))
	moon.light_energy = float(layout.get("moon", {}).get("energy", 1.6))
	moon.shadow_enabled = true
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 36.0
	moon.light_volumetric_fog_energy = 2.5
	RenderingServer.directional_shadow_atlas_set_size(int(quality.directional_shadow), true)
	room.add_child(moon)
	return moon

static func _flame_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	return quad

static var _dot: ImageTexture

static func _soft_dot() -> ImageTexture:
	if _dot != null:
		return _dot
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(image)
	return _dot

static func _fire(point: Vector3, scale: float, quality: Dictionary) -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.position = point
	fire.amount = int(28 * scale * float(quality.particles)) + 6
	fire.lifetime = 0.7
	fire.mesh = _flame_mesh(0.22 * scale)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.14 * scale
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.gravity = Vector3(0.0, 1.6, 0.0)
	fire.initial_velocity_min = 0.2
	fire.initial_velocity_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.9))
	ramp.set_color(1, Color(0.6, 0.1, 0.02, 0.0))
	ramp.add_point(0.4, Color(1.0, 0.45, 0.12, 0.7))
	fire.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	fire.scale_amount_curve = curve
	return fire

static func _candle_flame(point: Vector3) -> MeshInstance3D:
	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _soft_dot()
	mat.albedo_color = Color(1.0, 0.7, 0.35, 1.0)
	quad.material = mat
	flame.mesh = quad
	flame.position = point
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return flame

## Low-lying mist: large additive noise cards near the floor (Compatibility path).
static func _fog_cards(room: Node3D) -> Array[MeshInstance3D]:
	var noise := FastNoiseLite.new()
	noise.seed = 9031
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var image := noise.get_seamless_image(128, 128)
	image.convert(Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var v := image.get_pixel(x, y).r
			image.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.35) * 1.6, 0.0, 1.0)))
	var texture := ImageTexture.create_from_image(image)
	var cards: Array[MeshInstance3D] = []
	for entry: Array in [[Vector3(0, 0.25, -2), 22.0, 0.10], [Vector3(0, 0.6, -4), 20.0, 0.07], [Vector3(-3, 1.1, 0), 16.0, 0.045]]:
		var card := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(entry[1], entry[1])
		card.mesh = plane
		card.position = entry[0]
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = texture
		mat.albedo_color = Color(0.55, 0.62, 0.72, entry[2])
		mat.uv1_scale = Vector3(2.0, 2.0, 1.0)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
		card.material_override = mat
		room.add_child(card)
		cards.append(card)
	return cards

## Fake god-ray: an additive tapered column under the ceiling opening (Compatibility path).
static func _shaft(layout: Dictionary) -> MeshInstance3D:
	var d: Array = layout.get("moon", {}).get("direction", [0.24, -0.93, 0.28])
	var direction := Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
	var top := Vector3(-2.0, 9.3, -2.0)
	var bottom := top + direction * (top.y / -direction.y)
	var kit := MeshKit.new(false)
	var basis := MeshKit.basis_from_y((top - bottom).normalized())
	var rings: Array = []
	for entry: Array in [[0.0, 1.5], [1.0, 1.35]]:
		rings.append({"c": bottom.lerp(top, entry[0]), "x": basis.x, "z": basis.z, "rx": entry[1], "rz": entry[1]})
	kit.loft("fire", rings, 16, false, false)
	var shaft := MeshInstance3D.new()
	shaft.name = "MoonShaft"
	var arrays := kit.commit()
	shaft.mesh = arrays
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.55, 0.65, 0.9, 0.03)
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.0
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.5
	mat.distance_fade_max_distance = 3.0
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shaft

## Dust motes drifting in the moon shaft.
static func _dust(layout: Dictionary, quality: Dictionary) -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = int(140 * float(quality.particles))
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.position = Vector3(0.0, 3.5, 0.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(2.0, 3.2, 2.0)
	dust.gravity = Vector3(0.0, -0.02, 0.0)
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	dust.spread = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.018)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.75, 0.82, 1.0, 0.35)
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	dust.mesh = quad
	return dust

## Pooled one-shot spark bursts at contact points (presentation of contact reports).
class _SparkPool:
	var pool: Array[CPUParticles3D] = []
	var next := 0

	func _init(room: Node3D, quality: Dictionary) -> void:
		for i in range(6):
			var p := CPUParticles3D.new()
			p.one_shot = true
			p.emitting = false
			p.amount = int(24 * float(quality.particles)) + 8
			p.lifetime = 0.45
			p.explosiveness = 0.95
			p.direction = Vector3.UP
			p.spread = 180.0
			p.gravity = Vector3(0.0, -7.0, 0.0)
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.0
			var quad := QuadMesh.new()
			quad.size = Vector2(0.025, 0.025)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.vertex_color_use_as_albedo = true
			quad.material = mat
			p.mesh = quad
			room.add_child(p)
			pool.append(p)

	func burst(point: Vector3, color: Color, outcome: String) -> void:
		var p := pool[next]
		next = (next + 1) % pool.size()
		p.global_position = point
		p.color = color * (3.0 if outcome in ["deflect", "clash", "block", "guard_break"] else 1.6)
		p.initial_velocity_max = 5.0 if outcome == "deflect" else 3.0
		p.restart()
