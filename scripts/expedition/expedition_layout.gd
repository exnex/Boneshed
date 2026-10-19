extends RefCounted
## Pure, versioned layout consumer of WorldBlueprint. Curated footprints and wide
## connectors protect traversal/camera space; seeded routing never changes identity.
const Blueprint = preload("res://scripts/worldgen/blueprint_generator.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const VERSION := "first-expedition.1"
const CELL := 4.0
const ROUTES := ["procession", "crooked_pilgrimage", "offset_sanctum"]

static func generate(words: Array, seed_value: int) -> Dictionary:
	var generated := Blueprint.new().generate(words, seed_value)
	if not generated.ok:
		return generated
	var blueprint: Dictionary = generated.blueprint
	var stream := Stream.new(VERSION + "|" + blueprint.streams.structure)
	var route := int(stream.next_u32() % ROUTES.size())
	var mirror := -1 if stream.next_u32() % 2 == 0 else 1
	var spacing := 5 + int(stream.next_u32() % 2)
	var bend := (2 + int(stream.next_u32() % 3)) * mirror
	var middle_x := 0 if route == 0 else bend
	var arena_x := 0 if route == 1 else (bend if route == 2 else mirror * 2)
	var centers := [[0, 0], [middle_x, -spacing], [arena_x, -spacing * 2 - 2]]
	var modules: Array = []
	var cells: Dictionary = {}
	var path: Array = []
	for i in centers.size():
		var center: Array = centers[i]
		var radius := 3 if i == 2 else 2
		modules.append({"id": ["arrival", "reliquary", "soul_arena"][i], "center": center, "radius": radius})
		_carve(cells, int(center[0]) - radius, int(center[1]) - radius, radius * 2 + 1, radius * 2 + 1)
		if i > 0:
			var previous: Array = centers[i - 1]
			# Orthogonal, 12 m wide connectors overlap the room footprints.
			_carve(cells, mini(previous[0], center[0]) - 1, int(previous[1]) - 1, absi(center[0] - previous[0]) + 3, 3)
			_carve(cells, int(center[0]) - 1, mini(previous[1], center[1]) - 1, 3, absi(center[1] - previous[1]) + 3)
			path.append([center[0] * CELL, previous[1] * CELL])
		path.append([center[0] * CELL, center[1] * CELL])
	var tiles: Array = cells.values()
	tiles.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] if a[1] != b[1] else a[0] < b[0])
	var edges: Array = []
	for tile: Array in tiles:
		for offset: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			if not cells.has(_key(tile[0] + offset[0], tile[1] + offset[1])):
				edges.append([tile[0], tile[1], offset[0], offset[1]])
	var tags: Array = []
	# The seed-independent senses carry semantic tags; no second keyword algorithm.
	var library: Blueprint.Library = Blueprint.Library.new()
	library.load_files()
	for sense: Dictionary in blueprint.identity.senses:
		for definition: Dictionary in library.keywords[sense.keyword].senses:
			if definition.id == sense.sense:
				for tag: String in definition.tags:
					if tag not in tags:
						tags.append(tag)
	tags.sort()
	var layout := {"version": VERSION, "blueprint": blueprint, "route": ROUTES[route],
		"modules": modules, "tiles": tiles, "edges": edges, "path": path,
		"spawn": [0.0, CELL], "arena": [arena_x * CELL, (-spacing * 2 - 2) * CELL],
		"identity": {"axes": blueprint.identity.axes, "tags": tags}}
	layout["fingerprint"] = Stream.hex32(Stream.hash32(Blueprint.canonical_json(layout)))
	return {"ok": true, "errors": [], "warnings": generated.warnings, "layout": layout}

static func _key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]

static func _carve(cells: Dictionary, x: int, z: int, width: int, depth: int) -> void:
	for ix in range(x, x + width):
		for iz in range(z, z + depth):
			cells[_key(ix, iz)] = [ix, iz]
