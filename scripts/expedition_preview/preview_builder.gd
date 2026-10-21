extends Node3D
## Presentation and collision for an expedition plan. Every solid in the plan is
## built exactly as validated; decoration added here never collides. Each region
## owns its node and StaticBody3D so a later streaming layer can activate, free or
## swap level of detail per region without rebuilding the others. No rules, input
## or global randomness: decoration draws from its own named presentation streams.
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const Modules = preload("res://scripts/combat/attack_modules.gd")
const PARAPET_HEIGHT := 1.3

var plan: Dictionary
var world_root: Node3D
var dungeon_root: Node3D
var world_environment: WorldEnvironment
var exterior: Environment
var interior: Environment
var sun: DirectionalLight3D
var gates: Dictionary = {}
var pickups: Dictionary = {}
var ascent_marker: Node3D
var _heights: Dictionary = {}
var _materials: Dictionary = {}
var _shared_box: BoxMesh

func _ready() -> void:
	var world: Dictionary = plan.world
	for tile: Dictionary in world.tiles:
		_heights[Plan.key(Plan.cell_of(tile.cell))] = _tile_height(tile)
	_environments()
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	for region: Dictionary in world.regions:
		_region(region)
	_bridges()
	_distant(world)
	dungeon_root = Node3D.new()
	dungeon_root.name = "Dungeon"
	var origin: Array = plan.dungeon.origin
	dungeon_root.position = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	add_child(dungeon_root)
	_dungeon()
	set_area("world")

# --- Public helpers for the controller and tests ----------------------------------

func world_point(cell: Array) -> Vector3:
	var size: float = plan.world.cell
	return Vector3(float(cell[0]) * size, float(_heights.get(Plan.key(Plan.cell_of(cell)), 0.0)), float(cell[1]) * size)

func dungeon_point(cell: Array) -> Vector3:
	var size: float = plan.dungeon.cell
	return dungeon_root.position + Vector3(float(cell[0]) * size, 0.0, float(cell[1]) * size)

func set_area(area: String) -> void:
	# Only the occupied area draws; the other keeps its collision but costs no draw calls.
	world_root.visible = area == "world"
	dungeon_root.visible = area == "dungeon"
	world_environment.environment = exterior if area == "world" else interior
	sun.light_energy = 0.7 if area == "world" else 0.18

func set_gate(id: String, closed: bool) -> void:
	var gate: StaticBody3D = gates[id]
	gate.visible = closed
	gate.collision_layer = Modules.ENVIRONMENT_LAYER if closed else 0

func gate_closed(id: String) -> bool:
	return gates[id].collision_layer != 0

func take_pickup(id: String) -> void:
	if pickups.has(id):
		pickups[id].queue_free()
		pickups.erase(id)

func show_ascent(shown: bool) -> void:
	ascent_marker.visible = shown

func stats() -> Dictionary:
	var counts := {"nodes": 0, "meshes": 0, "collision_shapes": 0, "lights": 0}
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		counts.nodes += 1
		counts.meshes += int(node is MeshInstance3D)
		counts.collision_shapes += int(node is CollisionShape3D)
		counts.lights += int(node is Light3D)
		stack.append_array(node.get_children())
	return counts

# --- World ----------------------------------------------------------------------

func _tile_height(tile: Dictionary) -> float:
	var world: Dictionary = plan.world
	var owner: String = tile.owner
	var step: float = world.level_height
	if owner.begins_with("r"):
		return float(world.regions[int(owner.substr(1))].level) * step
	var bridge: Dictionary = world.bridges[int(owner.substr(1))]
	var from: Dictionary = world.regions[int(String(bridge.from).substr(1))]
	var direction: Vector2i = Plan.DIRS[bridge.dir]
	var along := Vector2(Plan.cell_of(tile.cell) - Plan.cell_of(from.center)).dot(Vector2(direction))
	var t := (along - Plan.RADIUS - 0.5) / float(int(plan_slot()) - Plan.RADIUS * 2 - 1)
	return lerpf(float(bridge.from_level), float(bridge.to_level), clampf(t, 0.0, 1.0)) * step

func plan_slot() -> int:
	return int(Plan.modules().world.slot)

func _region(region: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Region_" + region.id
	world_root.add_child(node)
	var body := _body(node, "Collision_" + region.id)
	var palette: Dictionary = Plan.modules().biome_palettes[region.biome]
	var floor_material := _material(Color(palette.floor))
	var trim := _material(Color(palette.trim))
	var glow := _material(Color(palette.glow), true)
	var size: float = plan.world.cell
	var top := float(region.level) * float(plan.world.level_height)
	var center := Plan.cell_of(region.center)
	# Floor runs per row include blocked landmark cells, so landmarks stand on stone.
	var floor_cells := {}
	for value: Array in region.cells:
		floor_cells[Plan.key(Plan.cell_of(value))] = Plan.cell_of(value)
	for blocked_key: String in plan.world.blocked:
		var parts := blocked_key.split(",")
		var cell := Vector2i(parts[0].to_int(), parts[1].to_int())
		if absi(cell.x - center.x) <= Plan.RADIUS and absi(cell.y - center.y) <= Plan.RADIUS:
			floor_cells[blocked_key] = cell
	for run: Array in _runs(floor_cells.values()):
		var width := float(run[2] - run[1] + 1) * size
		var location := Vector3((run[1] + run[2]) * 0.5 * size, top, float(run[0]) * size)
		_box(node, body, location + Vector3.DOWN * 0.3, Vector3(width, 0.6, size), floor_material, true)
		# A noncolliding mesa beneath each run reads as a raised plateau over the void.
		_box(node, null, location + Vector3.DOWN * (0.6 + (top + 14.0) * 0.5), Vector3(width - 0.3, top + 14.0, size - 0.3), _material(Color(palette.floor).darkened(0.35)), false)
	_parapets(node, body, floor_cells, top, trim)
	for solid: Dictionary in plan.world.solids:
		if solid.region == region.id:
			_solid(node, body, solid, top, trim, glow)
	_decor(node, region, floor_cells, top, palette)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(center.x * size, top + 6.0, center.y * size)
	lamp.light_color = Color(palette.glow)
	lamp.light_energy = 1.4
	lamp.omni_range = 18.0
	node.add_child(lamp)
	for site: Dictionary in plan.world.sites:
		if site.region == region.id:
			var ring := TorusMesh.new()
			ring.inner_radius = 8.8
			ring.outer_radius = 8.95
			_mesh(node, ring, world_point(site.cell) + Vector3.UP * 0.03, Vector3(1, 0.03, 1), glow)
	var descent: Dictionary = plan.world.descent
	if descent.region == region.id:
		_descent(node, descent, top)
	if "extraction" in region.roles:
		_beacon(node, world_point(plan.world.extraction), Color("e8d9a0"), "Extraction")
	for item: Dictionary in plan.loot:
		if item.area == "world" and _in_region(item.cell, center):
			_pickup(node, item, world_point(item.cell))

func _in_region(cell: Array, center: Vector2i) -> bool:
	return absi(int(cell[0]) - center.x) <= Plan.RADIUS and absi(int(cell[1]) - center.y) <= Plan.RADIUS

## Merges cells into per-row runs: [z, x_start, x_end].
func _runs(cells: Array) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var runs: Array = []
	for cell: Vector2i in cells:
		if not runs.is_empty() and runs[-1][0] == cell.y and runs[-1][2] == cell.x - 1:
			runs[-1][2] = cell.x
		else:
			runs.append([cell.y, cell.x, cell.x])
	return runs

func _parapets(node: Node3D, body: StaticBody3D, floor_cells: Dictionary, top: float, material: Material) -> void:
	var size: float = plan.world.cell
	var open := {}
	for tile: Dictionary in plan.world.tiles:
		open[Plan.key(Plan.cell_of(tile.cell))] = true
	for cell_key: String in floor_cells:
		open[cell_key] = true
	# Collect boundary edges by side and line, then merge contiguous edges.
	var lines := {}
	for cell: Vector2i in floor_cells.values():
		for dir: String in Plan.DIR_ORDER:
			var step: Vector2i = Plan.DIRS[dir]
			if not open.has(Plan.key(cell + step)):
				var line_key := "%s|%d" % [dir, cell.y if step.y != 0 else cell.x]
				if not lines.has(line_key):
					lines[line_key] = []
				lines[line_key].append(cell.x if step.y != 0 else cell.y)
	var line_keys: Array = lines.keys()
	line_keys.sort()
	for line_key: String in line_keys:
		var parts := line_key.split("|")
		var step: Vector2i = Plan.DIRS[parts[0]]
		var fixed := parts[1].to_int()
		var values: Array = lines[line_key]
		values.sort()
		var start: int = values[0]
		for i in values.size():
			if i + 1 < values.size() and values[i + 1] == values[i] + 1:
				continue
			var end: int = values[i]
			var length := float(end - start + 1) * size
			var middle := (start + end) * 0.5 * size
			var edge := fixed * size + (step.y + step.x) * size * 0.5
			var location := Vector3(middle, top + PARAPET_HEIGHT * 0.5, edge) if step.y != 0 else Vector3(edge, top + PARAPET_HEIGHT * 0.5, middle)
			var extent := Vector3(length + 0.4, PARAPET_HEIGHT, 0.45) if step.y != 0 else Vector3(0.45, PARAPET_HEIGHT, length + 0.4)
			_box(node, body, location, extent, material, true)
			_box(node, null, location + Vector3.UP * 0.68, extent + Vector3(0.12, -PARAPET_HEIGHT + 0.12, 0.12), material, false)
			if i + 1 < values.size():
				start = values[i + 1]

func _bridges() -> void:
	var node := Node3D.new()
	node.name = "Bridges"
	world_root.add_child(node)
	var body := _body(node, "Collision_bridges")
	var world: Dictionary = plan.world
	var size: float = world.cell
	var step_height: float = world.level_height
	for bridge: Dictionary in world.bridges:
		var from: Dictionary = world.regions[int(String(bridge.from).substr(1))]
		var palette: Dictionary = Plan.modules().biome_palettes[from.biome]
		var direction: Vector2i = Plan.DIRS[bridge.dir]
		var origin := Vector2(Plan.cell_of(from.center)) * size
		var forward := Vector2(direction)
		var start_2d := origin + forward * (Plan.RADIUS + 0.5) * size
		var end_2d := origin + forward * (plan_slot() - Plan.RADIUS - 0.5) * size
		var start := Vector3(start_2d.x, float(bridge.from_level) * step_height, start_2d.y)
		var end := Vector3(end_2d.x, float(bridge.to_level) * step_height, end_2d.y)
		var basis := Basis.looking_at((end - start).normalized(), Vector3.UP)
		var length := start.distance_to(end)
		var middle := (start + end) * 0.5
		var deck := Transform3D(basis, middle - basis.y * 0.3)
		_oriented_box(node, body, deck, Vector3(size * 3.0, 0.6, length + 0.02), _material(Color(palette.floor)), true)
		var side := basis.x
		for sign_value: float in [-1.0, 1.0]:
			var rail := Transform3D(basis, middle + side * sign_value * (size * 1.5) + basis.y * PARAPET_HEIGHT * 0.5)
			_oriented_box(node, body, rail, Vector3(0.45, PARAPET_HEIGHT, length + 0.3), _material(Color(palette.trim)), true)
		# Supports read the span as a built causeway over the void, not floating tiles.
		for t: float in [0.25, 0.75]:
			var p := start.lerp(end, t)
			_box(node, null, p + Vector3.DOWN * 9.0, Vector3(2.0, 17.4, 2.0), _material(Color(palette.floor).darkened(0.4)), false)

func _solid(node: Node3D, body: StaticBody3D, solid: Dictionary, top: float, trim: Material, glow: Material) -> void:
	var rect: Array = solid.rect
	var footprint := Vector3(float(rect[2]) - float(rect[0]), 0.0, float(rect[3]) - float(rect[1]))
	var center := Vector3((float(rect[0]) + float(rect[2])) * 0.5, top, (float(rect[1]) + float(rect[3])) * 0.5)
	var height: float = solid.height
	match solid.kind:
		"column":
			_box(node, body, center + Vector3.UP * height * 0.5, Vector3(footprint.x, height, footprint.z), trim, true)
			_box(node, null, center + Vector3.UP * (height + 0.15), Vector3(footprint.x + 0.4, 0.3, footprint.z + 0.4), trim, false)
		"descent_post":
			_box(node, body, center + Vector3.UP * height * 0.5, Vector3(footprint.x, height, footprint.z), _material(Color("2a2430")), true)
		_:
			_landmark(node, body, solid.id, center, footprint, height, trim, glow)

func _landmark(node: Node3D, body: StaticBody3D, id: String, base: Vector3, footprint: Vector3, height: float, trim: Material, glow: Material) -> void:
	# The collision is the validated footprint block; visual flourishes stay inside it.
	var core_height := height
	match id:
		"drowned_basin", "rib_arch", "ember_pyre", "profane_altar", "gilded_idol":
			core_height = 1.4
		"toppled_colossus":
			core_height = 3.2
	_box(node, body, base + Vector3.UP * core_height * 0.5, Vector3(footprint.x, core_height, footprint.z), trim, true)
	# Rim landmarks stand beyond the parapet; a noncolliding plinth grounds them.
	_box(node, null, base + Vector3.DOWN * 7.0, Vector3(footprint.x + 1.0, 14.0, footprint.z + 1.0), _material(Color("1d262c")), false)
	var w := minf(footprint.x, footprint.z)
	match id:
		"broken_spire":
			var cap := _box(node, null, base + Vector3.UP * (height + 0.8), Vector3(w * 0.7, 1.6, w * 0.5), trim, false)
			cap.rotation.z = 0.35
		"rib_arch":
			for i in 4:
				var rib := _box(node, null, base + Vector3((i - 1.5) * w * 0.22, core_height + height * 0.35, 0), Vector3(0.45, height * 0.75, 0.6), _material(Color("bbb69e")), false)
				rib.rotation.z = (i - 1.5) * -0.28
		"drowned_basin":
			_box(node, null, base + Vector3.UP * (core_height + 0.02), Vector3(footprint.x - 0.8, 0.04, footprint.z - 0.8), _water(), false)
			_box(node, null, base + Vector3.UP * (core_height + height * 0.3), Vector3(0.9, height * 0.6, 0.9), trim, false)
		"rime_obelisks":
			for i in 3:
				var shard := _mesh(node, PrismMesh.new(), base + Vector3((i - 1) * w * 0.28, height * (0.35 + 0.1 * i), 0), Vector3(w * 0.25, height * (0.7 + 0.2 * i), w * 0.25), _material(Color("a9d4de")))
				shard.rotation.z = (i - 1) * 0.12
		"ember_pyre":
			_mesh(node, SphereMesh.new(), base + Vector3.UP * (core_height + 1.0), Vector3(w * 0.5, 1.6, w * 0.5), _material(Color("d76c32"), true))
		"thorn_thicket":
			for i in 5:
				var thorn := _mesh(node, CylinderMesh.new(), base + Vector3((i - 2) * w * 0.15, height * 0.4, (i % 2 - 0.5) * w * 0.3), Vector3(0.3, height * 0.4, 0.3), _material(Color("3f4a36")))
				thorn.rotation.z = (i - 2) * 0.32
		"gilded_idol":
			_box(node, null, base + Vector3.UP * (core_height + height * 0.3), Vector3(w * 0.35, height * 0.6, w * 0.3), _material(Color("c9a659")), false)
			_mesh(node, SphereMesh.new(), base + Vector3.UP * (core_height + height * 0.68), Vector3(w * 0.3, w * 0.3, w * 0.3), _material(Color("e2c47a"), true))
		"profane_altar":
			var spike := _mesh(node, PrismMesh.new(), base + Vector3.UP * (core_height + height * 0.35), Vector3(w * 0.4, height * 0.7, w * 0.4), _material(Color("4a2f4f")))
			spike.rotation.x = PI
			_mesh(node, SphereMesh.new(), base + Vector3.UP * (core_height + 0.4), Vector3(0.8, 0.8, 0.8), _material(Color("a571a5"), true))
		"toppled_colossus":
			_mesh(node, SphereMesh.new(), base + Vector3(w * 0.3, core_height + 1.2, 0), Vector3(2.2, 2.2, 2.2), trim)
		"storm_mast":
			_box(node, null, base + Vector3.UP * height * 0.75, Vector3(w * 0.9, 0.3, 0.3), trim, false)
			_mesh(node, SphereMesh.new(), base + Vector3.UP * (height + 0.3), Vector3(0.6, 0.6, 0.6), _material(Color("cfe0ff"), true))
		_:
			_mesh(node, SphereMesh.new(), base + Vector3.UP * (height + 0.4), Vector3(0.6, 0.6, 0.6), glow)

func _descent(node: Node3D, descent: Dictionary, top: float) -> void:
	var location := world_point(descent.cell)
	var forward := Vector3(Plan.DIRS[descent.facing].x, 0, Plan.DIRS[descent.facing].y)
	var side := Vector3(forward.z, 0, forward.x)
	var dark := _material(Color("2a2430"))
	var violet := _material(Color("9a7ad6"), true)
	# Lintel over the two validated posts, a dark stair slab and a tall beam that
	# can be seen from other regions: a discoverable destination, not a maze clue.
	_box(node, null, location + forward * 0.6 + Vector3.UP * 5.7, _across(side, 4.4, 0.6, 0.9), dark, false)
	_box(node, null, location + Vector3.UP * 0.02, Vector3(2.6, 0.03, 2.6), _material(Color("0d0b12")), false)
	_box(node, null, location + forward * 0.6 + Vector3.UP * 4.9, _across(side, 2.6, 0.12, 0.12), violet, false)
	var beam := _mesh(node, CylinderMesh.new(), location + Vector3.UP * 18.0, Vector3(0.35, 18.0, 0.35), violet)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = location + Vector3.UP * 2.5
	light.light_color = Color("9a7ad6")
	light.light_energy = 2.2
	light.omni_range = 9.0
	node.add_child(light)

## Box extents with `length` along `side` (a unit x or z axis).
func _across(side: Vector3, length: float, height: float, depth: float) -> Vector3:
	return Vector3(length, height, depth) if absf(side.x) > 0.5 else Vector3(depth, height, length)

func _beacon(node: Node3D, location: Vector3, color: Color, label: String, beam_height := 16.0) -> Node3D:
	var marker := Node3D.new()
	marker.name = label + "Beacon"
	node.add_child(marker)
	var material := _material(color, true)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.8
	ring.outer_radius = 3.0
	_mesh(marker, ring, location + Vector3.UP * 0.04, Vector3(1, 0.04, 1), material)
	var beam := _mesh(marker, CylinderMesh.new(), location + Vector3.UP * beam_height, Vector3(0.22, beam_height, 0.22), material)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = location + Vector3.UP * 2.0
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 8.0
	marker.add_child(light)
	return marker

func _pickup(node: Node3D, item: Dictionary, location: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = "Pickup_" + item.id
	node.add_child(marker)
	var relic: bool = item.kind == "relic"
	var gem := SphereMesh.new()
	gem.radial_segments = 4
	gem.rings = 2
	_mesh(marker, gem, location + Vector3.UP * (1.6 if relic else 0.7), Vector3(0.5, 0.8, 0.5) * (1.4 if relic else 1.0), _material(Color("f2e6b8") if relic else Color("8fd0c2"), true))
	_box(marker, null, location + Vector3.UP * 0.02, Vector3(1.4, 0.03, 1.4), _material(Color("6f6a55")), false)
	pickups[item.id] = marker

func _decor(node: Node3D, region: Dictionary, floor_cells: Dictionary, top: float, palette: Dictionary) -> void:
	# Elemental cues from identity tags and the region biome. Visual only: no hazards.
	var tags: Array = plan.identity.tags
	var stream := Stream.new("%s|decor|%s|%s|%d" % [plan.version, region.id, plan.blueprint_fingerprint, plan.seed])
	var biome: String = region.biome
	var kinds: Array = []
	if "water" in tags or biome in ["flooded_lowland", "sunken_city", "corrupted_fen", "storm_coast"]:
		kinds.append("water")
	if "cold" in tags or biome == "frozen_reach":
		kinds.append("ice")
	if "fire" in tags or biome == "ashfield":
		kinds.append("ember")
	if "bone" in tags or "death" in tags or biome == "catacomb":
		kinds.append("bone")
	if "wild" in tags or biome == "briar_wilds":
		kinds.append("moss")
	if kinds.is_empty():
		kinds.append("rubble")
	var size: float = plan.world.cell
	var cells: Array = []
	for value: Array in region.cells:
		cells.append(Plan.cell_of(value))
	for i in 5:
		var cell: Vector2i = cells[stream.next_u32() % cells.size()]
		var kind: String = kinds[stream.next_u32() % kinds.size()]
		var location := Vector3(cell.x * size, top + 0.02, cell.y * size)
		match kind:
			"water":
				_box(node, null, location, Vector3(3.0, 0.03, 3.0), _water(), false)
			"ice":
				_box(node, null, location, Vector3(3.2, 0.04, 2.6), _material(Color("91c8d2")), false)
			"ember":
				_box(node, null, location, Vector3(2.8, 0.03, 2.8), _material(Color("292a2c")), false)
				_box(node, null, location + Vector3.UP * 0.02, Vector3(0.12, 0.02, 2.6), _material(Color("d76c32"), true), false)
			"bone":
				_box(node, null, location + Vector3.UP * 0.05, Vector3(0.9, 0.12, 0.3), _material(Color("bbb69e")), false)
			"moss":
				_box(node, null, location, Vector3(3.0, 0.03, 3.0), _material(Color("3f5a3a")), false)
			_:
				_box(node, null, location + Vector3.UP * 0.06, Vector3(0.8, 0.14, 0.6), _material(Color(palette.trim).darkened(0.3)), false)

func _distant(world: Dictionary) -> void:
	# Silhouettes far outside the walk for a desolate horizon; no collision.
	var stream := Stream.new("%s|horizon|%s" % [plan.version, plan.blueprint_fingerprint])
	var size: float = world.cell
	var silhouette := _material(Color("1d262c"))
	for region: Dictionary in world.regions:
		var center := Vector3(float(region.center[0]) * size, 0, float(region.center[1]) * size)
		for i in 2:
			var angle := stream.next_float() * TAU
			var distance := 70.0 + stream.next_float() * 40.0
			var height := 18.0 + stream.next_float() * 20.0
			var p := center + Vector3(cos(angle), 0, sin(angle)) * distance
			var spire := _box(world_root, null, p + Vector3.UP * (height * 0.5 - 16.0), Vector3(4.0 + stream.next_float() * 4.0, height, 5.0), silhouette, false)
			spire.rotation.z = (stream.next_float() - 0.5) * 0.12

# --- Dungeon ------------------------------------------------------------------------

func _dungeon() -> void:
	var dungeon: Dictionary = plan.dungeon
	var body := _body(dungeon_root, "Collision_dungeon")
	var size: float = dungeon.cell
	var stone := _material(Color("2b2d31"))
	var wall := _material(Color("3a3a3f"))
	var trim := _material(Color("6b6656"))
	var cells: Array = dungeon.tiles.map(func(value: Array) -> Vector2i: return Vector2i(int(value[0]), int(value[1])))
	var open := {}
	for cell: Vector2i in cells:
		open[Plan.key(cell)] = true
	for run: Array in _runs(cells.duplicate()):
		var width := float(run[2] - run[1] + 1) * size
		_box(dungeon_root, body, Vector3((run[1] + run[2]) * 0.5 * size, -0.3, float(run[0]) * size), Vector3(width, 0.6, size), stone, true)
	# Walls on every floor boundary edge: doors exist only where corridors meet rooms.
	var height: float = dungeon.wall_height
	var lines := {}
	for cell: Vector2i in cells:
		for dir: String in Plan.DIR_ORDER:
			var step: Vector2i = Plan.DIRS[dir]
			if not open.has(Plan.key(cell + step)):
				var line_key := "%s|%d" % [dir, cell.y if step.y != 0 else cell.x]
				if not lines.has(line_key):
					lines[line_key] = []
				lines[line_key].append(cell.x if step.y != 0 else cell.y)
	var line_keys: Array = lines.keys()
	line_keys.sort()
	for line_key: String in line_keys:
		var parts := line_key.split("|")
		var step: Vector2i = Plan.DIRS[parts[0]]
		var fixed := parts[1].to_int()
		var values: Array = lines[line_key]
		values.sort()
		var start: int = values[0]
		for i in values.size():
			if i + 1 < values.size() and values[i + 1] == values[i] + 1:
				continue
			var end: int = values[i]
			var length := float(end - start + 1) * size
			var middle := (start + end) * 0.5 * size
			var edge := fixed * size + (step.y + step.x) * size * 0.5
			var location := Vector3(middle, height * 0.5, edge) if step.y != 0 else Vector3(edge, height * 0.5, middle)
			# Flush ends: no wall protrudes into a doorway to snag a passing capsule.
			var extent := Vector3(length, height, 0.5) if step.y != 0 else Vector3(0.5, height, length)
			_box(dungeon_root, body, location, extent, wall, true)
			if i + 1 < values.size():
				start = values[i + 1]
	for solid: Dictionary in dungeon.solids:
		var rect: Array = solid.rect
		var footprint := Vector3(float(rect[2]) - float(rect[0]), float(solid.height), float(rect[3]) - float(rect[1]))
		var center := Vector3((float(rect[0]) + float(rect[2])) * 0.5, footprint.y * 0.5, (float(rect[1]) + float(rect[3])) * 0.5)
		var material: Material = _material(Color("bbb69e")) if solid.kind == "bone_pile" else trim
		_box(dungeon_root, body, center, footprint, material, true)
	for room: Dictionary in dungeon.rooms:
		var light := OmniLight3D.new()
		light.position = Vector3(float(room.center[0]) * size, 3.6, float(room.center[1]) * size)
		light.light_color = Color("e2a868") if room.role != "guardian" else Color("c9837a")
		light.light_energy = 1.8 if room.role != "guardian" else 2.4
		light.omni_range = 12.0 if room.role != "guardian" else 20.0
		dungeon_root.add_child(light)
	var ring := TorusMesh.new()
	ring.inner_radius = 8.8
	ring.outer_radius = 8.95
	_mesh(dungeon_root, ring, _local(dungeon.guardian.cell) + Vector3.UP * 0.03, Vector3(1, 0.03, 1), _material(Color("c9837a"), true))
	for gate: Dictionary in dungeon.gates:
		_gate(gate, trim)
	# Short interior markers: a tall beam would stand between the camera and the player.
	_beacon(dungeon_root, _local(dungeon.return_portal), Color("9fc6dc"), "Return", 0.6)
	ascent_marker = _beacon(dungeon_root, _local(dungeon.ascent_portal), Color("e8d9a0"), "Ascent", 0.6)
	ascent_marker.visible = false
	for item: Dictionary in plan.loot:
		if item.area == "dungeon":
			_pickup(dungeon_root, item, _local(item.cell))

func _local(cell: Array) -> Vector3:
	var size: float = plan.dungeon.cell
	return Vector3(float(cell[0]) * size, 0.0, float(cell[1]) * size)

func _gate(gate: Dictionary, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = gate.id
	body.collision_mask = 0
	dungeon_root.add_child(body)
	var center := Vector3(float(gate.center[0]), 1.6, float(gate.center[1]))
	var width: float = gate.width
	var along_x: bool = gate.axis == "x"
	var extent := Vector3(width, 3.2, 0.4) if along_x else Vector3(0.4, 3.2, width)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extent
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	var bars := int(width) + 1
	for i in bars:
		var offset := -width * 0.5 + width * float(i) / float(bars - 1)
		_mesh(body, BoxMesh.new(), center + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset)), Vector3(0.16, 3.2, 0.3) if along_x else Vector3(0.3, 3.2, 0.16), material)
	_mesh(body, BoxMesh.new(), center + Vector3.UP * 1.6, extent + Vector3(0, -2.9, 0), material)
	gates[gate.id] = body
	set_gate(gate.id, false)

# --- Primitives ----------------------------------------------------------------------

func _environments() -> void:
	var atmosphere: Dictionary = plan.atmosphere
	var axes: Dictionary = plan.identity.axes
	var tint := Color("7db5c4") if float(axes.temperature) < 0.0 else Color("df9e64")
	exterior = Environment.new()
	exterior.background_mode = Environment.BG_COLOR
	exterior.background_color = Color("101c28").lerp(tint.darkened(0.8), 0.15)
	exterior.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	exterior.ambient_light_color = Color("a6becd").lerp(tint, 0.25)
	# Clamped like the First Expedition so telegraphs stay readable.
	exterior.ambient_light_energy = 0.3 + float(atmosphere.light_level) * 0.2
	exterior.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	exterior.fog_enabled = true
	exterior.fog_light_color = exterior.background_color.lightened(0.12)
	exterior.fog_density = 0.003 + float(atmosphere.fog_density) * 0.006
	interior = Environment.new()
	interior.background_mode = Environment.BG_COLOR
	interior.background_color = Color("07080b")
	interior.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	interior.ambient_light_color = Color("8a8f9c")
	interior.ambient_light_energy = 0.32
	interior.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	interior.fog_enabled = true
	interior.fog_light_color = Color("15161b")
	interior.fog_density = 0.012
	world_environment = WorldEnvironment.new()
	world_environment.environment = exterior
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("e3ddcc").lerp(tint, 0.15)
	sun.shadow_enabled = true
	add_child(sun)

func _body(parent: Node3D, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = Modules.ENVIRONMENT_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	return body

func _water() -> StandardMaterial3D:
	var material := _material(Color("1f4d5b"))
	material.metallic = 0.45
	material.roughness = 0.2
	return material

func _material(color: Color, emission := false) -> StandardMaterial3D:
	var cache_key := color.to_html() + ("e" if emission else "")
	if _materials.has(cache_key):
		return _materials[cache_key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	_materials[cache_key] = material
	return material

func _mesh(parent: Node3D, mesh: Mesh, location: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	instance.scale = size
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, body: StaticBody3D, location: Vector3, size: Vector3, material: Material, solid: bool) -> MeshInstance3D:
	return _oriented_box(parent, body, Transform3D(Basis.IDENTITY, location), size, material, solid)

func _oriented_box(parent: Node3D, body: StaticBody3D, transform_value: Transform3D, size: Vector3, material: Material, solid: bool) -> MeshInstance3D:
	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.transform = transform_value
		body.add_child(shape)
	var instance := MeshInstance3D.new()
	instance.mesh = _unit_box()
	instance.material_override = material
	instance.transform = transform_value.scaled_local(size)
	parent.add_child(instance)
	return instance

func _unit_box() -> BoxMesh:
	if _shared_box == null:
		_shared_box = BoxMesh.new()
	return _shared_box
