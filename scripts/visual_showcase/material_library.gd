extends RefCounted
## Procedural materials for the visual showcase. Every texture is generated at runtime
## from FastNoiseLite and simple pattern maths (no imported images, no third-party
## assets). Materials are cached per process and shared by every user, so a material
## id costs one texture set however many meshes use it.
##
## Texture size is the quality knob: `set_texture_size` before the first request sets
## the base size and the size of large environment surfaces (stone_*). Generation is
## deterministic (fixed seeds per id) and costs seconds of CPU, so finished images are
## cached under user:// keyed by CACHE_VERSION, id and size (delete the folder to
## regenerate; bump CACHE_VERSION whenever a generator changes).

const SEED := 4711
const CACHE_VERSION := 6
const CACHE_DIR := "user://showcase_textures"

static var _cache: Dictionary = {}
static var _texture_size: int = 256
static var _environment_size: int = 512
static var use_disk_cache: bool = true
## Milliseconds spent generating (not loading) textures this process, for benchmarks.
static var generation_ms: int = 0

static func set_texture_size(size: int, environment_size := -1) -> void:
	var env := environment_size if environment_size > 0 else size * 2
	if size != _texture_size or env != _environment_size:
		_texture_size = size
		_environment_size = env
		_cache.clear()

static func texture_size() -> int:
	return _texture_size

static func clear() -> void:
	_cache.clear()

## Every material id this library can build (tests iterate it).
const IDS := ["stone_floor", "stone_wall", "stone_trim", "skin_pilgrim", "skin_corrupted", "cloth_dark", "cloth_robe",
	"cloth_tattered", "leather", "mail", "mail_rusted", "plate", "plate_rusted", "steel", "steel_dark", "bronze", "wood_grip",
	"bone", "marrow", "iron_black", "wax", "fire", "eye_glow", "banner", "earth"]

static func get_material(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var mat := _build(id)
	mat.resource_name = id
	_cache[id] = mat
	return mat

static func size_for(id: String) -> int:
	return _environment_size if id.begins_with("stone_") else _texture_size

static func _build(id: String) -> StandardMaterial3D:
	var s := size_for(id)
	_current_id = id
	match id:
		"stone_floor":
			return _textured(_flagstones.bind(s, Color("4a4741"), Color("2b2925")), 0.92, 0.0, 1.6, Vector3(1, 1, 1))
		"stone_wall":
			return _textured(_ashlar.bind(s, Color("57524a"), Color("2e2b27")), 0.9, 0.0, 1.8, Vector3(1, 1, 1))
		"stone_trim":
			return _textured(_weathered.bind(s, Color("6a645a"), Color("3a3631"), 11), 0.85, 0.0, 1.2, Vector3(1, 1, 1))
		"skin_pilgrim":
			var mat := _textured(_weathered.bind(s, Color("9a745e"), Color("6e4e3e"), 3, 0.25), 0.62, 0.0, 0.35, Vector3(2, 2, 1))
			mat.vertex_color_use_as_albedo = true
			return mat
		"skin_corrupted":
			var mat := _textured(_weathered.bind(s, Color("6d6a66"), Color("3b3937"), 5, 0.6), 0.75, 0.0, 0.9, Vector3(2, 2, 1))
			mat.emission_enabled = true
			mat.emission_texture = _veins_texture(s)
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mat.emission = Color("63d7c9")
			mat.emission_energy_multiplier = 1.6
			mat.vertex_color_use_as_albedo = true
			return mat
		"cloth_dark":
			return _textured(_weave.bind(s, Color("4d453b"), Color("2a2520")), 0.95, 0.0, 0.7, Vector3(4, 4, 1))
		"cloth_robe":
			return _textured(_weave.bind(s, Color("5e4a3e"), Color("33271f")), 0.95, 0.0, 0.7, Vector3(4, 4, 1))
		"cloth_tattered":
			var mat := _textured(_weave.bind(s, Color("4a504c"), Color("232726")), 0.95, 0.0, 0.7, Vector3(3, 3, 1))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			return mat
		"banner":
			var mat := _textured(_weave.bind(s, Color("5a1f1f"), Color("2c0f10")), 0.95, 0.0, 0.5, Vector3(2, 2, 1))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			return mat
		"leather":
			return _textured(_weathered.bind(s, Color("4e3627"), Color("2a1c14"), 17, 0.5), 0.7, 0.0, 0.8, Vector3(3, 3, 1))
		"mail":
			return _textured(_mail.bind(s, Color("9a9c98"), Color("343533")), 0.45, 0.55, 1.4, Vector3(10, 10, 1))
		"mail_rusted":
			return _textured(_mail.bind(s, Color("86644a"), Color("2e2018")), 0.65, 0.4, 1.4, Vector3(10, 10, 1))
		"plate":
			return _textured(_brushed.bind(s, Color("8e8b84"), Color("57554f")), 0.38, 0.6, 0.5, Vector3(2, 2, 1))
		"plate_rusted":
			return _textured(_rust.bind(s, Color("6a6258"), Color("7a4426")), 0.6, 0.45, 0.8, Vector3(2, 2, 1))
		"steel":
			return _textured(_brushed.bind(s, Color("d2d6d8"), Color("a4a8aa")), 0.3, 0.5, 0.25, Vector3(1, 6, 1))
		"steel_dark":
			return _textured(_brushed.bind(s, Color("85878a"), Color("54575a")), 0.4, 0.55, 0.35, Vector3(1, 6, 1))
		"bronze":
			return _textured(_brushed.bind(s, Color("a07a44"), Color("6a4e2a")), 0.4, 0.6, 0.3, Vector3(2, 2, 1))
		"wood_grip":
			return _textured(_wrap.bind(s, Color("3d2a1d"), Color("1d140e")), 0.75, 0.0, 0.9, Vector3(1, 1, 1))
		"bone":
			return _textured(_weathered.bind(s, Color("d6ccb2"), Color("9b8f72"), 23, 0.4), 0.7, 0.0, 0.7, Vector3(2, 2, 1))
		"marrow":
			var mat := _textured(_weathered.bind(s, Color("e3d8bc"), Color("8f8064"), 29, 0.5), 0.6, 0.0, 0.9, Vector3(2, 2, 1))
			mat.emission_enabled = true
			mat.emission_texture = _veins_texture(s)
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mat.emission = Color("ff6a3a")
			mat.emission_energy_multiplier = 1.4
			return mat
		"iron_black":
			return _textured(_rust.bind(s, Color("38352f"), Color("5a3320")), 0.7, 0.45, 0.6, Vector3(2, 2, 1))
		"earth":
			return _textured(_weathered.bind(s, Color("3b342b"), Color("201c17"), 31, 0.7), 0.97, 0.0, 1.2, Vector3(1, 1, 1))
		"wax":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("d9cdb0")
			mat.roughness = 0.5
			mat.emission_enabled = true
			mat.emission = Color("ffb35c")
			mat.emission_energy_multiplier = 0.25
			return mat
		"fire":
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1.0, 0.55, 0.18, 0.8)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			mat.vertex_color_use_as_albedo = true
			return mat
		"eye_glow":
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color("9ff5ea")
			mat.emission_enabled = true
			mat.emission = Color("63f0de")
			mat.emission_energy_multiplier = 4.0
			return mat
	push_error("Unknown showcase material: " + id)
	return StandardMaterial3D.new()

static var _current_id: String = ""

static func _cache_path(id: String, map: String, size: int) -> String:
	return "%s/v%d/%s_%d_%s.png" % [CACHE_DIR, CACHE_VERSION, id, size, map]

## Images for `id` from the disk cache, or {} when absent or disabled.
static func _cached(id: String, size: int) -> Dictionary:
	if not use_disk_cache:
		return {}
	var out := {}
	for map: String in ["albedo", "normal", "roughness"]:
		var path := _cache_path(id, map, size)
		if FileAccess.file_exists(path):
			out[map] = Image.load_from_file(path)
	return out if out.has("albedo") and out.has("normal") else {}

static func _store(id: String, size: int, images: Dictionary) -> void:
	if not use_disk_cache:
		return
	DirAccess.make_dir_recursive_absolute(_cache_path(id, "x", size).get_base_dir())
	for map: String in images:
		(images[map] as Image).save_png(_cache_path(id, map, size))

## A generator returns {albedo: Image, height: Image[, roughness: Image]}; normal and
## roughness maps derive from it. `make` only runs on a cache miss.
static func _textured(make: Callable, roughness: float, metallic: float, bump: float, uv_scale: Vector3) -> StandardMaterial3D:
	var id := _current_id
	var size := size_for(id)
	var images := _cached(id, size)
	if images.is_empty():
		var started := Time.get_ticks_msec()
		var set: Dictionary = (make as Callable).call()
		var normal: Image = (set.height as Image).duplicate()
		normal.bump_map_to_normal_map(bump * float(size) / 512.0 * 4.0)
		images = {"albedo": set.albedo, "normal": normal}
		if set.has("roughness"):
			images.roughness = set.roughness
		generation_ms += Time.get_ticks_msec() - started
		_store(id, size, images)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _texture(images.albedo)
	mat.normal_enabled = true
	mat.normal_texture = _texture(images.normal)
	mat.roughness = roughness
	if images.has("roughness"):
		mat.roughness_texture = _texture(images.roughness)
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness = 1.0
	mat.metallic = metallic
	mat.uv1_scale = uv_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

static func _texture(image: Image) -> ImageTexture:
	var copy := image.duplicate() as Image
	copy.generate_mipmaps()
	return ImageTexture.create_from_image(copy)

static func _noise(seed_offset: int, frequency: float, kind: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, octaves := 4) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = SEED + seed_offset
	noise.noise_type = kind
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise

## Seamless noise image as a float grid in 0..1.
static func _grid(noise: FastNoiseLite, size: int) -> PackedFloat32Array:
	var image := noise.get_seamless_image(size, size, false, false, 0.1, true)
	var out := PackedFloat32Array()
	out.resize(size * size)
	var data := image.get_data()
	var channels := data.size() / (size * size)
	for i in range(size * size):
		out[i] = data[i * channels] / 255.0
	return out

static func _images(size: int, albedo_of: Callable, height_of: Callable, rough_of: Callable = Callable()) -> Dictionary:
	var albedo := PackedByteArray()
	albedo.resize(size * size * 3)
	var height := PackedByteArray()
	height.resize(size * size * 3)
	var rough := PackedByteArray()
	if rough_of.is_valid():
		rough.resize(size * size * 3)
	for i in range(size * size):
		var c: Color = albedo_of.call(i)
		albedo[i * 3] = clampi(int(c.r * 255.0), 0, 255)
		albedo[i * 3 + 1] = clampi(int(c.g * 255.0), 0, 255)
		albedo[i * 3 + 2] = clampi(int(c.b * 255.0), 0, 255)
		var h := clampi(int(float(height_of.call(i)) * 255.0), 0, 255)
		height[i * 3] = h
		height[i * 3 + 1] = h
		height[i * 3 + 2] = h
		if rough_of.is_valid():
			var r := clampi(int(float(rough_of.call(i)) * 255.0), 0, 255)
			rough[i * 3] = r
			rough[i * 3 + 1] = r
			rough[i * 3 + 2] = r
	var out := {"albedo": Image.create_from_data(size, size, false, Image.FORMAT_RGB8, albedo),
		"height": Image.create_from_data(size, size, false, Image.FORMAT_RGB8, height)}
	if rough_of.is_valid():
		out.roughness = Image.create_from_data(size, size, false, Image.FORMAT_RGB8, rough)
	return out

## Irregular flagstones: cellular edges become grout; each cell gets its own tone.
static func _flagstones(size: int, light: Color, dark: Color) -> Dictionary:
	var cells := _noise(1, 4.0 / size, FastNoiseLite.TYPE_CELLULAR, 1)
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	var edge := _grid(cells, size)
	var ids := _noise(1, 4.0 / size, FastNoiseLite.TYPE_CELLULAR, 1)
	ids.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	ids.fractal_type = FastNoiseLite.FRACTAL_NONE
	var tone := _grid(ids, size)
	var grain := _grid(_noise(2, 24.0 / size), size)
	var stain := _grid(_noise(3, 3.0 / size), size)
	return _images(size, func(i: int) -> Color:
			var grout := smoothstep(0.02, 0.09, edge[i])
			var base := dark.lerp(light, 0.35 + 0.45 * tone[i] + 0.25 * (grain[i] - 0.5))
			base = base.darkened(0.35 * smoothstep(0.55, 0.85, stain[i]))
			return Color("1a1815").lerp(base, grout),
		func(i: int) -> float: return 0.15 + 0.65 * smoothstep(0.0, 0.12, edge[i]) + 0.2 * grain[i],
		func(i: int) -> float: return lerpf(0.98, 0.78, smoothstep(0.55, 0.85, stain[i])) - 0.08 * grain[i])

## Ashlar courses: staggered rectangular blocks with chipped, noisy edges.
static func _ashlar(size: int, light: Color, dark: Color) -> Dictionary:
	var grain := _grid(_noise(5, 20.0 / size), size)
	var wobble := _grid(_noise(6, 8.0 / size), size)
	var stain := _grid(_noise(7, 2.5 / size), size)
	var rows := 4
	var cols := 2
	return _images(size, func(i: int) -> Color:
			var e := _ashlar_edge(i, size, rows, cols, wobble[i])
			var block := _hash(int(float(i / size) / size * rows) * 31 + int((float(i % size) / size + (0.5 if (i / size * rows / size) % 2 else 0.0)) * cols))
			var base := dark.lerp(light, 0.3 + 0.4 * block + 0.3 * (grain[i] - 0.5))
			base = base.lerp(Color("2f3a2c"), 0.35 * smoothstep(0.6, 0.9, stain[i]))
			return Color("1c1a17").lerp(base, smoothstep(0.0, 0.05, e)),
		func(i: int) -> float: return 0.1 + 0.7 * smoothstep(0.0, 0.07, _ashlar_edge(i, size, rows, cols, wobble[i])) + 0.2 * grain[i],
		func(i: int) -> float: return 0.95 - 0.1 * grain[i])

static func _ashlar_edge(i: int, size: int, rows: int, cols: int, wobble: float) -> float:
	var v := float(i / size) / size * rows
	var row := int(v)
	var u := float(i % size) / size * cols + (0.5 if row % 2 else 0.0)
	var fu := fposmod(u, 1.0)
	var fv := v - row
	return minf(minf(fu, 1.0 - fu) / cols * 2.0, minf(fv, 1.0 - fv) / rows * 2.0) + (wobble - 0.5) * 0.03

static func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 1000) / 1000.0

static func _weathered(size: int, light: Color, dark: Color, seed_offset: int, contrast := 0.4) -> Dictionary:
	var coarse := _grid(_noise(seed_offset, 3.0 / size), size)
	var fine := _grid(_noise(seed_offset + 1, 28.0 / size), size)
	var pits := _grid(_noise(seed_offset + 2, 60.0 / size, FastNoiseLite.TYPE_CELLULAR, 1), size)
	return _images(size, func(i: int) -> Color:
			return dark.lerp(light, clampf(0.5 + contrast * (coarse[i] - 0.5) * 2.0 + 0.2 * (fine[i] - 0.5), 0.0, 1.0)),
		func(i: int) -> float: return 0.5 * fine[i] + 0.3 * coarse[i] + 0.2 * pits[i],
		func(i: int) -> float: return 0.6 + 0.35 * fine[i])

static func _veins_texture(size: int) -> ImageTexture:
	var cached := _cached("veins", size)
	if cached.has("albedo"):
		return _texture(cached.albedo)
	var started := Time.get_ticks_msec()
	var image := _veins(size)
	generation_ms += Time.get_ticks_msec() - started
	_store("veins", size, {"albedo": image, "normal": image})
	return _texture(image)

## Cracked veins (emission mask) for corrupted surfaces.
static func _veins(size: int) -> Image:
	var cells := _noise(41, 6.0 / size, FastNoiseLite.TYPE_CELLULAR, 2)
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var edge := _grid(cells, size)
	var mask := _grid(_noise(42, 2.5 / size), size)
	var data := PackedByteArray()
	data.resize(size * size * 3)
	for i in range(size * size):
		var v := (1.0 - smoothstep(0.0, 0.07, edge[i])) * smoothstep(0.32, 0.62, mask[i])
		var b := clampi(int(v * 255.0), 0, 255)
		data[i * 3] = b
		data[i * 3 + 1] = b
		data[i * 3 + 2] = b
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)

static func _weave(size: int, light: Color, dark: Color) -> Dictionary:
	var dirt := _grid(_noise(11, 4.0 / size), size)
	var fuzz := _grid(_noise(12, 64.0 / size), size)
	var threads := 48.0
	return _images(size, func(i: int) -> Color:
			var u := float(i % size) / size * threads
			var v := float(i / size) / size * threads
			var over := 0.5 + 0.5 * sin(u * TAU) * sin(v * TAU * 0.5 + (PI * 0.5 if int(u) % 2 else 0.0))
			return dark.lerp(light, 0.35 + 0.35 * over + 0.3 * (fuzz[i] - 0.5)).darkened(0.3 * dirt[i]),
		func(i: int) -> float:
			var u := float(i % size) / size * threads
			var v := float(i / size) / size * threads
			return 0.5 + 0.35 * sin(u * TAU) * sin(v * TAU * 0.5) + 0.15 * fuzz[i])

## Riveted mail rings: overlapping rings on a staggered lattice.
static func _mail(size: int, light: Color, dark: Color) -> Dictionary:
	var rust := _grid(_noise(13, 3.0 / size), size)
	var per := 16.0
	return _images(size, func(i: int) -> Color:
			var r := _ring(i, size, per)
			return dark.lerp(light, r).lerp(Color("5a3a24"), 0.5 * smoothstep(0.55, 0.85, rust[i]) * r),
		func(i: int) -> float: return _ring(i, size, per),
		func(i: int) -> float: return lerpf(0.9, 0.3, _ring(i, size, per)) + 0.3 * smoothstep(0.55, 0.85, rust[i]))

static func _ring(i: int, size: int, per: float) -> float:
	var u := float(i % size) / size * per
	var v := float(i / size) / size * per
	var row := int(v * 2.0)
	var cu := fposmod(u + (0.5 if row % 2 else 0.0), 1.0) - 0.5
	var cv := fposmod(v * 2.0, 1.0) - 0.5
	var d := sqrt(cu * cu + cv * cv * 0.6)
	return clampf(1.0 - absf(d - 0.33) / 0.1, 0.0, 1.0)

static func _brushed(size: int, light: Color, dark: Color) -> Dictionary:
	var streak := _noise(15, 1.0 / size)
	streak.frequency = 0.003
	var streaks := _grid(streak, size)
	var scratches := _grid(_noise(16, 90.0 / size), size)
	var grime := _grid(_noise(17, 3.0 / size), size)
	return _images(size, func(i: int) -> Color:
			var v := 0.55 + 0.25 * (streaks[(i % size) * size + i / size] - 0.5) + 0.2 * (scratches[i] - 0.5)
			return dark.lerp(light, clampf(v, 0.0, 1.0)).darkened(0.45 * smoothstep(0.55, 0.85, grime[i])),
		func(i: int) -> float: return 0.5 + 0.2 * (scratches[i] - 0.5),
		func(i: int) -> float: return 0.35 + 0.3 * smoothstep(0.55, 0.85, grime[i]) + 0.15 * scratches[i])

static func _rust(size: int, metal: Color, rust_color: Color) -> Dictionary:
	var patches := _grid(_noise(19, 5.0 / size), size)
	var fine := _grid(_noise(20, 50.0 / size), size)
	return _images(size, func(i: int) -> Color:
			var r := smoothstep(0.45, 0.7, patches[i] + 0.15 * (fine[i] - 0.5))
			return metal.lerp(rust_color, r).darkened(0.15 * fine[i]),
		func(i: int) -> float: return 0.4 + 0.4 * smoothstep(0.45, 0.7, patches[i]) * fine[i] + 0.2 * fine[i],
		func(i: int) -> float: return lerpf(0.45, 0.9, smoothstep(0.45, 0.7, patches[i])))

## Leather strip wrapped diagonally around a grip.
static func _wrap(size: int, light: Color, dark: Color) -> Dictionary:
	var fine := _grid(_noise(21, 40.0 / size), size)
	return _images(size, func(i: int) -> Color:
			var u := float(i % size) / size
			var v := float(i / size) / size
			var band := fposmod((u + v * 6.0) * 1.0, 1.0)
			return dark.lerp(light, smoothstep(0.0, 0.2, band) * smoothstep(1.0, 0.75, band) * 0.8 + 0.2 * fine[i]),
		func(i: int) -> float:
			var u := float(i % size) / size
			var v := float(i / size) / size
			var band := fposmod(u + v * 6.0, 1.0)
			return smoothstep(0.0, 0.2, band) * smoothstep(1.0, 0.75, band))
