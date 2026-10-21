extends RefCounted
## Modular ruined-crypt pieces for the visual showcase, built for later procedural
## assembly. Conventions (shared by every piece):
##   - Grid unit CELL = 4 m. A piece's pivot is the floor centre of its footprint; local
##     −Z faces into the room (walls) or along the piece's length (arcades, fallen
##     columns). Rotation is a yaw in 90° steps from the layout.
##   - Geometry is appended to one shared static MeshKit, so a room costs one draw call
##     per material however many pieces it has. Materials are material_library ids.
##   - Each piece returns its collision boxes (local Transform3D + size) and optional
##     sockets (lights, fx points) in local space; the builder transforms them.
##   - Randomness comes only from the RandomNumberGenerator passed in (seeded per piece
##     by the layout), so the same layout always produces the same room.

const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")
const CELL := 4.0
const WALL_HEIGHT := 7.5
const WALL_THICK := 0.9

static func _box(kit: MeshKit, xf: Transform3D, size: Vector3, material: String, rng: RandomNumberGenerator, uv := 0.5) -> void:
	kit.box(material, xf, size, {}, uv, Vector2(rng.randf(), rng.randf()))

## Irregular chipped stone block: a box whose corners are jittered (still one convex
## hexahedron, flat-shaded).
static func _chunk(kit: MeshKit, xf: Transform3D, size: Vector3, material: String, rng: RandomNumberGenerator, jitter := 0.12) -> void:
	var b := Basis(Vector3(rng.randf_range(-1, 1), 1, rng.randf_range(-1, 1)).normalized(), rng.randf_range(-jitter, jitter))
	kit.box(material, xf * Transform3D(b, Vector3.ZERO), size * Vector3(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1)), {}, 0.5,
		Vector2(rng.randf(), rng.randf()))

## --- Floors --------------------------------------------------------------------------------

## 4×4 m of individual flagstones with gaps, slight height and tilt variation (≤ 1.5 cm,
## so feet and collision stay at y = 0), some cracked into halves. `broken` drops
## stones near one edge to expose earth and rubble.
static func floor_tile(kit: MeshKit, rng: RandomNumberGenerator, variant: String) -> Dictionary:
	kit.box("earth", Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.0)), Vector3(CELL, 0.1, CELL), {}, 0.25)
	var rows := 4
	var z := -CELL * 0.5
	for r in range(rows):
		var depth := CELL / rows
		var x := -CELL * 0.5
		var offset := rng.randf_range(0.0, 0.6) if r % 2 else 0.0
		var widths: Array[float] = []
		var remaining := CELL + offset
		while remaining > 0.3:
			var w := minf(remaining, rng.randf_range(0.7, 1.3))
			widths.append(w)
			remaining -= w
		x -= offset
		for w: float in widths:
			var cx := x + w * 0.5
			x += w
			if cx < -CELL * 0.5 + 0.1 or cx > CELL * 0.5 - 0.1:
				continue
			var cw := minf(w, CELL * 0.5 - absf(cx) + w * 0.5) - 0.025
			if variant == "broken" and z > CELL * 0.1 and rng.randf() < 0.45:
				_rubble_scatter(kit, rng, Vector3(cx, 0.0, z + depth * 0.5), 3, 0.18)
				continue
			var h := rng.randf_range(-0.012, 0.004)
			var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.006, 0.006)) * Basis(Vector3.BACK, rng.randf_range(-0.006, 0.006))
			var centre := Vector3(cx, -0.04 + h, z + depth * 0.5)
			if rng.randf() < 0.18:
				# Cracked slab: two halves with a hairline gap.
				var split := rng.randf_range(0.35, 0.65)
				_box(kit, Transform3D(tilt, centre + Vector3(-cw * (1.0 - split) * 0.5, 0.0, 0.0)), Vector3(cw * split - 0.01, 0.08, depth - 0.03), "stone_trim", rng, 0.6)
				_box(kit, Transform3D(tilt, centre + Vector3(cw * split * 0.5, -0.004, 0.0)), Vector3(cw * (1.0 - split) - 0.01, 0.08, depth - 0.03), "stone_trim", rng, 0.6)
			else:
				_box(kit, Transform3D(tilt, centre), Vector3(cw, 0.08, depth - 0.03), "stone_trim", rng, 0.6)
		z += depth
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 0.0)), Vector3(CELL, 0.6, CELL)]]}

## --- Walls -------------------------------------------------------------------------------

## A 4 m wall segment facing −Z: plinth, ashlar body with protruding and missing
## blocks, string course and cornice. Variants: plain, niche (ossuary alcove with
## skulls), broken (collapsed top with rubble at its foot).
static func wall(kit: MeshKit, rng: RandomNumberGenerator, variant: String) -> Dictionary:
	var height := WALL_HEIGHT
	if variant == "broken":
		height = rng.randf_range(3.6, 4.6)
	var z := 0.0
	var face := z - WALL_THICK * 0.5
	if variant == "niche":
		# Body with a recessed arched alcove.
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(-1.45, height * 0.5, z)), Vector3(1.1, height, WALL_THICK), "stone_wall", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(1.45, height * 0.5, z)), Vector3(1.1, height, WALL_THICK), "stone_wall", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, z)), Vector3(1.8, 1.0, WALL_THICK), "stone_wall", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, (height + 3.4) * 0.5, z)), Vector3(1.8, height - 3.4, WALL_THICK), "stone_wall", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, z + 0.32)), Vector3(1.8, 2.4, 0.26), "stone_wall", rng)
		arch_ring(kit, rng, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, face + 0.15)), 0.9, 0.22, 0.3, 9)
		# Shelves of skulls and long bones.
		for shelf: float in [1.05, 1.85, 2.65]:
			_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, shelf - 0.04, z - 0.08)), Vector3(1.8, 0.08, 0.5), "stone_trim", rng)
			var x := -0.75
			while x < 0.75:
				if rng.randf() < 0.75:
					skull(kit, rng, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), Vector3(x, shelf + 0.1, z - 0.12)), 0.85)
				else:
					kit.tube("bone", Vector3(x - 0.12, shelf + 0.03, z - 0.1), Vector3(x + 0.12, shelf + 0.04, z - 0.2), 0.022, 0.02, {}, 6)
				x += rng.randf_range(0.2, 0.28)
	else:
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, z)), Vector3(CELL, height, WALL_THICK), "stone_wall", rng)
	# Plinth and string course.
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, face - 0.12)), Vector3(CELL, 0.6, 0.26), "stone_trim", rng)
	if height > 4.0:
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.9, face - 0.08)), Vector3(CELL, 0.22, 0.18), "stone_trim", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, height - 0.15, face - 0.15)), Vector3(CELL, 0.3, 0.32), "stone_trim", rng)
	# Weathering: protruding and sunken blocks, moss-dark stains are in the texture.
	for i in range(rng.randi_range(5, 9)):
		var bx := rng.randf_range(-1.6, 1.6)
		var by := rng.randf_range(0.8, height - 0.6)
		if variant == "niche" and absf(bx) < 1.1 and by < 3.6:
			continue
		var w := rng.randf_range(0.5, 1.0)
		_chunk(kit, Transform3D(Basis.IDENTITY, Vector3(bx, by, face - 0.03)), Vector3(w, 0.48, 0.14), "stone_wall", rng, 0.04)
	if variant == "broken":
		# Jagged top: stepped broken courses, fallen blocks at the foot.
		var x := -CELL * 0.5
		while x < CELL * 0.5:
			var w := rng.randf_range(0.4, 0.9)
			var h := rng.randf_range(0.2, 1.4)
			_chunk(kit, Transform3D(Basis.IDENTITY, Vector3(x + w * 0.5, height + h * 0.5 - 0.1, z)), Vector3(w, h, WALL_THICK * 0.9), "stone_wall", rng, 0.08)
			x += w
		_rubble_scatter(kit, rng, Vector3(0.0, 0.0, face - 0.9), 14, 0.35)
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, WALL_HEIGHT * 0.5, z)), Vector3(CELL, WALL_HEIGHT, WALL_THICK)]]}

## An 8 m entrance wall facing −Z: a 3 m arched doorway with a half-raised portcullis
## and darkness beyond.
static func doorway(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var face := -WALL_THICK * 0.5
	for side: float in [-1.0, 1.0]:
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(side * 2.75, WALL_HEIGHT * 0.5, 0.0)), Vector3(2.5, WALL_HEIGHT, WALL_THICK), "stone_wall", rng)
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(side * 2.75, 0.3, face - 0.12)), Vector3(2.5, 0.6, 0.26), "stone_trim", rng)
		# Jamb columns.
		pillar(kit, rng, "plain", Transform3D(Basis.IDENTITY, Vector3(side * 1.75, 0.0, face - 0.25)), 0.26, 3.4)
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, (WALL_HEIGHT + 4.9) * 0.5, 0.0)), Vector3(3.0, WALL_HEIGHT - 4.9, WALL_THICK), "stone_wall", rng)
	arch_ring(kit, rng, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.4, face - 0.05)), 1.5, 0.35, 0.5, 11)
	# Spandrel infill between the arch and the lintel course.
	for side: float in [-1.0, 1.0]:
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(side * 1.1, 4.4, 0.0)), Vector3(0.8, 1.2, WALL_THICK * 0.8), "stone_wall", rng)
	# Portcullis: iron grid raised to 2.3 m.
	for i in range(7):
		var x := -1.2 + i * 0.4
		kit.box("iron_black", Transform3D(Basis.IDENTITY, Vector3(x, 3.6, 0.0)), Vector3(0.05, 2.6, 0.05), {})
		kit.tube("iron_black", Vector3(x, 2.3, 0.0), Vector3(x, 2.1, 0.0), 0.03, 0.002, {}, 5)
	for y: float in [2.6, 3.4, 4.2]:
		kit.box("iron_black", Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.03)), Vector3(2.7, 0.05, 0.05), {})
	# Void beyond the door and a sill.
	kit.box("iron_black", Transform3D(Basis.IDENTITY, Vector3(0.0, 2.4, 1.6)), Vector3(3.2, 4.8, 0.2), {})
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0)), Vector3(3.0, 0.08, WALL_THICK + 0.2), "stone_trim", rng)
	return {"collision": [
		[Transform3D(Basis.IDENTITY, Vector3(-2.75, WALL_HEIGHT * 0.5, 0.0)), Vector3(2.5, WALL_HEIGHT, WALL_THICK)],
		[Transform3D(Basis.IDENTITY, Vector3(2.75, WALL_HEIGHT * 0.5, 0.0)), Vector3(2.5, WALL_HEIGHT, WALL_THICK)],
		[Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.3)), Vector3(3.0, 3.0, 0.3)]]}

## --- Columns, arches, ribs ---------------------------------------------------------------

## Clustered pier: square base, octagonal shaft with four engaged colonnettes, capital.
## Variant "broken" snaps the shaft at a random height and drops its drum nearby.
static func pillar(kit: MeshKit, rng: RandomNumberGenerator, variant: String, xf := Transform3D.IDENTITY, radius := 0.36, height := 5.0) -> Dictionary:
	var top := height
	if variant == "broken":
		top = rng.randf_range(1.6, 2.8)
	_box(kit, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)), Vector3(radius * 2.7, 0.5, radius * 2.7), "stone_trim", rng)
	_box(kit, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.58, 0.0)), Vector3(radius * 2.4, 0.16, radius * 2.4), "stone_trim", rng)
	var rings: Array = []
	var steps := 6
	for i in range(steps + 1):
		var y := lerpf(0.66, top - (0.0 if variant == "broken" else 0.5), float(i) / steps)
		var chip := 1.0 - (0.08 * rng.randf() if i > 0 and i < steps else 0.0)
		rings.append({"c": xf * Vector3(0.0, y, 0.0), "x": xf.basis.x, "z": xf.basis.z, "rx": radius * chip, "rz": radius * chip,
			"shape": func(a: float) -> float: return 1.0 / cos(fposmod(a, TAU / 8.0) - TAU / 16.0) * 0.96})
	kit.loft("stone_trim", rings, 8, false, variant == "broken", false, 0.5)
	for k in range(4):
		var a := TAU * k / 4.0 + TAU / 16.0
		var off := Vector3(cos(a), 0.0, sin(a)) * radius * 1.02
		kit.tube("stone_trim", xf * (off + Vector3(0.0, 0.66, 0.0)), xf * (off + Vector3(0.0, top - (0.1 if variant == "broken" else 0.5), 0.0)),
			radius * 0.3, radius * 0.3, {}, 8, true)
	if variant != "broken":
		_box(kit, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, top - 0.38, 0.0)), Vector3(radius * 2.6, 0.24, radius * 2.6), "stone_trim", rng)
		_box(kit, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, top - 0.12, 0.0)), Vector3(radius * 3.0, 0.24, radius * 3.0), "stone_trim", rng)
	else:
		_rubble_scatter(kit, rng, (xf * Vector3(0.6, 0.0, 0.4)), 8, 0.3)
		_chunk(kit, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.0, radius * 0.9, -0.6)), Vector3(radius * 1.8, 0.9, radius * 1.8), "stone_trim", rng, 0.1)
	return {"collision": [[xf * Transform3D(Basis.IDENTITY, Vector3(0.0, top * 0.5, 0.0)), Vector3(radius * 2.4, top, radius * 2.4)]],
		"sockets": {"sconce": xf * Vector3(0.0, 2.6, -radius * 1.35)}}

## A semicircular ring of wedge voussoirs in xf's XY plane (span 2·radius).
static func arch_ring(kit: MeshKit, rng: RandomNumberGenerator, xf: Transform3D, radius: float, thickness: float, depth: float, stones: int) -> void:
	for i in range(stones):
		var a0 := PI * float(i) / stones
		var a1 := PI * float(i + 1) / stones
		var mid := (a0 + a1) * 0.5
		var r := radius + thickness * 0.5
		var centre := Vector3(cos(mid) * r, sin(mid) * r, 0.0)
		var arc := 2.0 * r * sin((a1 - a0) * 0.5)
		var b := Basis(Vector3.BACK, mid - PI * 0.5)
		var sink := rng.randf_range(-0.015, 0.02)
		_box(kit, xf * Transform3D(b, centre + Vector3(0.0, -sink, 0.0)), Vector3(arc - 0.012, thickness, depth), "stone_trim", rng, 0.6)

## Arcade arch between two columns CELL apart along local −Z, springing at `spring`.
static func arcade(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 4.6, 0.0))
	arch_ring(kit, rng, xf, CELL * 0.5 - 0.45, 0.4, 0.55, 13)
	# Wall above the arch up to the clerestory.
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 7.2, 0.0)), Vector3(0.55, 1.6, CELL), "stone_wall", rng)
	return {"collision": []}

## Transverse rib across the nave (span along local X).
static func rib(kit: MeshKit, rng: RandomNumberGenerator, variant: String) -> Dictionary:
	var span := float(variant.to_float()) if variant.is_valid_float() else 9.2
	arch_ring(kit, rng, Transform3D(Basis.IDENTITY, Vector3(0.0, 4.9, 0.0)), span * 0.5 - 0.35, 0.36, 0.45, 19)
	return {"collision": []}

## Ceiling slab 4×4 m at the vault height; "open" leaves a ragged hole (the moon shaft).
static func ceiling(kit: MeshKit, rng: RandomNumberGenerator, variant: String) -> Dictionary:
	var y := 9.6
	if variant == "open":
		for side: Vector3 in [Vector3(-1.6, 0, 0), Vector3(1.6, 0, 0)]:
			_box(kit, Transform3D(Basis.IDENTITY, Vector3(side.x, y, 0.0)), Vector3(0.8, 0.6, CELL), "stone_wall", rng)
		for side: float in [-1.0, 1.0]:
			_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, y, side * 1.6)), Vector3(CELL - 1.6, 0.6, 0.8), "stone_wall", rng)
		for i in range(10):
			var a := TAU * i / 10.0
			_chunk(kit, Transform3D(Basis.IDENTITY, Vector3(cos(a) * 1.15, y - 0.25, sin(a) * 1.15)), Vector3(0.5, 0.4, 0.5), "stone_wall", rng, 0.3)
	else:
		_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)), Vector3(CELL, 0.6, CELL), "stone_wall", rng)
	return {"collision": []}

## --- Furniture and props -----------------------------------------------------------------

## Three-step dais (8 m wide, 3 m deep, rising toward +Z... local −Z faces the room).
static func dais(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var collision: Array = []
	for i in range(3):
		var depth := 3.0 - i * 0.8
		var y := 0.18 * (i + 1)
		var centre := Vector3(0.0, y * 0.5, 0.0 + i * 0.4)
		var x := -4.0
		while x < 4.0:
			var w := rng.randf_range(0.9, 1.4)
			w = minf(w, 4.0 - x)
			_box(kit, Transform3D(Basis.IDENTITY, Vector3(x + w * 0.5, centre.y, centre.z)), Vector3(w - 0.02, y, depth), "stone_trim", rng)
			x += w
		collision.append([Transform3D(Basis.IDENTITY, centre), Vector3(8.0, y, depth)])
	return {"collision": collision}

## Sarcophagus with a carved lid effigy (a shrouded figure).
static func sarcophagus(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3(1.1, 1.0, 2.3), "stone_trim", rng)
	_box(kit, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.08, 0.0)), Vector3(1.3, 0.16, 2.5), "stone_trim", rng)
	# Lid slightly ajar.
	var lid := Transform3D(Basis(Vector3.UP, 0.08), Vector3(0.12, 1.08, 0.05))
	_box(kit, lid, Vector3(1.25, 0.16, 2.45), "stone_trim", rng)
	# Effigy: body, head, folded hands.
	kit.blob("stone_trim", lid * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.16, 0.15)), Vector3(0.3, 0.12, 0.85), {}, 14, 8, 2.4)
	kit.blob("stone_trim", lid * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -0.82)), Vector3(0.13, 0.12, 0.14), {}, 12, 8)
	kit.blob("stone_trim", lid * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.28, -0.25)), Vector3(0.12, 0.06, 0.12), {}, 10, 6)
	# Carved side panels: shallow quatrefoil bosses.
	for z: float in [-0.7, 0.0, 0.7]:
		for side: float in [-1.0, 1.0]:
			kit.blob("stone_trim", Transform3D(Basis.IDENTITY, Vector3(side * 0.56, 0.55, z)), Vector3(0.03, 0.18, 0.18), {}, 10, 6)
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)), Vector3(1.3, 1.2, 2.5)]]}

## Iron brazier on a tripod with a fire light socket.
static func brazier(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	for k in range(3):
		var a := TAU * k / 3.0
		kit.tube("iron_black", Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32), Vector3(cos(a) * 0.12, 0.85, sin(a) * 0.12), 0.025, 0.02, {}, 6)
	var bowl: Array = []
	for entry: Array in [[0.85, 0.12], [0.92, 0.3], [1.08, 0.38], [1.1, 0.4]]:
		bowl.append({"c": Vector3(0.0, entry[0], 0.0), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": entry[1], "rz": entry[1]})
	kit.loft("iron_black", bowl, 14, true, false)
	# Coals.
	for i in range(9):
		kit.blob("iron_black", Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.22, 0.22), 1.06, rng.randf_range(-0.22, 0.22))), Vector3(0.07, 0.04, 0.06), {}, 6, 4)
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0)), Vector3(0.6, 1.1, 0.6)]],
		"sockets": {"fire": Vector3(0.0, 1.2, 0.0)}}

## A cluster of melted candles (emissive wax; flames are fx sockets).
static func candles(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var flames: Array = []
	for i in range(rng.randi_range(5, 9)):
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.08, 0.32)
		var r := rng.randf_range(0.022, 0.04)
		kit.tube("wax", p, p + Vector3(0.0, h, 0.0), r * 1.3, r, {}, 7)
		kit.blob("wax", Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.01, 0.0)), Vector3(r * 2.4, 0.015, r * 2.4), {}, 8, 4)
		flames.append(p + Vector3(0.0, h + 0.03, 0.0))
	return {"collision": [], "sockets": {"flames": flames}}

static func skull(kit: MeshKit, rng: RandomNumberGenerator, xf: Transform3D, scale := 1.0) -> void:
	kit.blob("bone", xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)), Vector3(0.075, 0.085, 0.095) * scale, {}, 10, 7, 2.0,
		func(u: Vector3) -> float:
			var m := 1.0
			if u.z < -0.5:
				for ex: float in [-0.4, 0.4]:
					m *= 1.0 - 0.25 * exp(-(pow((u.x - ex) / 0.2, 2.0) + pow((u.y - 0.0) / 0.2, 2.0)))
			if u.y < -0.3 and u.z < 0.0:
				m *= 0.85
			return m)
	kit.blob("bone", xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, -0.035) * scale), Vector3(0.05, 0.025, 0.05) * scale, {}, 8, 4)

static func _rubble_scatter(kit: MeshKit, rng: RandomNumberGenerator, centre: Vector3, count: int, size: float) -> void:
	for i in range(count):
		var p := centre + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * size * 3.0
		var s := size * rng.randf_range(0.3, 1.0)
		_chunk(kit, Transform3D(Basis.IDENTITY, p + Vector3(0.0, s * 0.3, 0.0)), Vector3(s, s * 0.7, s * 0.9), "stone_wall" if rng.randf() < 0.5 else "stone_trim", rng, 0.4)

static func rubble(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	_rubble_scatter(kit, rng, Vector3.ZERO, 22, 0.32)
	for i in range(5):
		_chunk(kit, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.6, 0.6), 0.25 + i * 0.12, rng.randf_range(-0.5, 0.5))), Vector3(0.7, 0.4, 0.5), "stone_wall", rng, 0.35)
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0)), Vector3(1.6, 0.8, 1.4)]]}

static func bones(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	for i in range(rng.randi_range(4, 7)):
		var p := Vector3(rng.randf_range(-0.8, 0.8), 0.02, rng.randf_range(-0.6, 0.6))
		var a := rng.randf_range(0.0, TAU)
		var d := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.18, 0.3)
		kit.tube("bone", p - d, p + d, 0.02, 0.018, {}, 6)
		kit.blob("bone", Transform3D(Basis.IDENTITY, p + d), Vector3(0.03, 0.025, 0.03), {}, 6, 4)
	for i in range(rng.randi_range(1, 3)):
		skull(kit, rng, Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)),
			Vector3(rng.randf_range(-0.6, 0.6), 0.07, rng.randf_range(-0.5, 0.5))))
	return {"collision": []}

## Fallen column lying along local −Z.
static func fallen_column(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var drums := 4
	for i in range(drums):
		var z := -1.6 + i * 1.05
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(rng.randf_range(-0.08, 0.08), 0.33, z))
		var rings: Array = []
		for end: float in [-0.48, 0.48]:
			rings.append({"c": xf * Vector3(0.0, end, 0.0), "x": xf.basis.x, "z": xf.basis.z, "rx": 0.34, "rz": 0.34,
				"shape": func(a: float) -> float: return 1.0 / cos(fposmod(a, TAU / 8.0) - TAU / 16.0) * 0.96})
		kit.loft("stone_trim", rings, 8, true, true)
	_rubble_scatter(kit, rng, Vector3(0.3, 0.0, 1.8), 6, 0.25)
	return {"collision": [[Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0)), Vector3(0.8, 0.7, 4.2)]]}

## Tattered banner hanging from 4.2 m (cloth both sides), with an iron rod.
static func banner(kit: MeshKit, rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	kit.tube("iron_black", Vector3(-0.55, 4.2, 0.0), Vector3(0.55, 4.2, 0.0), 0.02, 0.02, {}, 6)
	var rings: Array = []
	var steps := 7
	for i in range(steps + 1):
		var t := float(i) / steps
		var y := 4.18 - t * 2.4
		var sway := sin(t * 2.5 + rng.randf()) * 0.04 * t
		rings.append({"c": Vector3(0.0, y, sway), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": 0.5 - 0.06 * t, "rz": 0.012})
	var hem := (rings[steps] as Dictionary).duplicate()
	hem.c = (hem.c as Vector3) - Vector3(0.0, 0.35, 0.0)
	hem.shape = func(a: float) -> float: return 0.45 + 0.55 * absf(sin(a * 4.0 + 0.7))
	rings.append(hem)
	kit.loft("banner", rings, 12, false, false)
	return {"collision": []}

## A hanging chain of alternating links from height `top` down 2.4 m.
static func chain(kit: MeshKit, _rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	var y := 8.0
	var i := 0
	while y > 3.6:
		var b := Basis(Vector3.UP, PI * 0.5 * (i % 2))
		var xf := Transform3D(b, Vector3(0.0, y, 0.0))
		var rings: Array = []
		for k in range(9):
			var a := TAU * k / 8.0
			rings.append({"c": xf * Vector3(cos(a) * 0.04, sin(a) * 0.07, 0.0), "x": b * Vector3(0, 0, 1), "z": b * Vector3(cos(a), sin(a), 0).normalized(), "rx": 0.011, "rz": 0.011})
		kit.loft("iron_black", rings, 5, false, false)
		y -= 0.11
		i += 1
	return {"collision": []}

## Wall sconce bracket (the torch flame is a light socket).
static func sconce(kit: MeshKit, _rng: RandomNumberGenerator, _variant: String) -> Dictionary:
	kit.box("iron_black", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.05)), Vector3(0.12, 0.25, 0.04), {})
	kit.tube("iron_black", Vector3(0.0, -0.05, 0.05), Vector3(0.0, 0.12, -0.18), 0.02, 0.02, {}, 6)
	kit.tube("wood_grip", Vector3(0.0, 0.05, -0.16), Vector3(0.0, 0.32, -0.2), 0.03, 0.035, {}, 7)
	return {"collision": [], "sockets": {"fire": Vector3(0.0, 0.4, -0.2)}}
