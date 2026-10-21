extends RefCounted
## Pure, versioned expedition-preview pipeline over the existing WorldBlueprint:
## blueprint -> region graph -> region footprints -> placements -> dungeon -> validation.
## Output is ids, ints, floats and arrays only, so builders, tests and a later
## save/stream layer consume one plan. Every stage owns a named seeded stream
## derived from blueprint streams plus a stage/region id, so adding a stage or
## region cannot shift another's draws. Sizes and counts are provisional data.
const Blueprint = preload("res://scripts/worldgen/blueprint_generator.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const Dungeon = preload("res://scripts/expedition_preview/dungeon_plan.gd")
const Validator = preload("res://scripts/expedition_preview/plan_validator.gd")
const VERSION := "expedition-preview.1"
const MODULES_PATH := "res://data/expedition_preview/modules.json"
const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
const DIR_ORDER := ["N", "E", "S", "W"]
const SLOT_BOUNDS := Rect2i(-2, -4, 5, 6) # Macro slots x in [-2, 2], z in [-4, 1].
const RADIUS := 3 # Region templates are 7 x 7 cells.

static var _modules: Dictionary = {}

static func modules() -> Dictionary:
	if _modules.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODULES_PATH))
		assert(parsed is Dictionary, "expedition preview modules failed to load")
		_modules = parsed
	return _modules

## Returns {"ok", "errors", "warnings", "plan"}. Invalid words produce no plan; a
## plan that fails validation is reported, never silently built.
static func generate(words: Array, seed_value: int) -> Dictionary:
	var generated := Blueprint.new().generate(words, seed_value)
	if not generated.ok:
		return {"ok": false, "errors": generated.errors, "warnings": generated.warnings, "plan": {}}
	var blueprint: Dictionary = generated.blueprint
	var data := modules()
	var tags := identity_tags(blueprint)
	var plan := {"version": VERSION, "address": blueprint.address, "seed": seed_value,
		"blueprint_fingerprint": blueprint.fingerprint,
		"identity": {"tags": tags, "biome": blueprint.identity.biome.primary,
			"axes": blueprint.identity.axes, "identity_fingerprint": blueprint.identity_fingerprint},
		"atmosphere": blueprint.generation.atmosphere}
	plan["world"] = _world(blueprint, tags, data)
	plan["dungeon"] = Dungeon.generate(VERSION + "|dungeon|" + blueprint.streams.structure, blueprint, data)
	_place_loot(plan, blueprint)
	_finalize(plan.world)
	var errors := Validator.validate(plan)
	plan["fingerprint"] = Stream.hex32(Stream.hash32(Blueprint.canonical_json(plan)))
	return {"ok": errors.is_empty(), "errors": errors, "warnings": generated.warnings, "plan": plan}

## Seed-independent semantic tags of the resolved senses (no second keyword algorithm).
static func identity_tags(blueprint: Dictionary) -> Array:
	var library := Blueprint.Library.new()
	library.load_files()
	var tags: Array = []
	for sense: Dictionary in blueprint.identity.senses:
		for definition: Dictionary in library.keywords[sense.keyword].senses:
			if definition.id == sense.sense:
				for tag: String in definition.tags:
					if tag not in tags:
						tags.append(tag)
	tags.sort()
	return tags

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell_of(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

# --- Stage 1: macro region graph -------------------------------------------------

static func _world(blueprint: Dictionary, tags: Array, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.world
	var generation: Dictionary = blueprint.generation
	var graph_stream := Stream.new(VERSION + "|regions|" + blueprint.streams.terrain)
	var bounds: Array = config.region_count
	# Open, unenclosed identities spread wider; enclosed ones stay compact.
	var openness := clampf((1.0 - float(blueprint.identity.axes.enclosure)) * 0.5, 0.0, 1.0)
	var count := clampi(int(bounds[0]) + int(graph_stream.next_u32() % 2) + int(openness > 0.6), int(bounds[0]), int(bounds[1]))
	var slots: Array[Vector2i] = [Vector2i.ZERO]
	var depth: Array[int] = [0]
	var parents: Array[int] = [-1]
	var edges: Array = []
	var occupied := {key(Vector2i.ZERO): 0}
	while slots.size() < count:
		var candidates: Array = []
		for i in slots.size():
			for dir: String in DIR_ORDER:
				var next: Vector2i = slots[i] + DIRS[dir]
				if SLOT_BOUNDS.has_point(next) and not occupied.has(key(next)):
					# Favour depth and forward (north) growth: a readable outward journey.
					candidates.append({"from": i, "dir": dir, "weight": 1.0 + depth[i] * 1.5 + (1.0 if dir == "N" else 0.0)})
		var pick: Dictionary = candidates[graph_stream.pick_weighted(candidates)]
		var slot: Vector2i = slots[pick.from] + DIRS[pick.dir]
		occupied[key(slot)] = slots.size()
		edges.append([pick.from, slots.size(), pick.dir])
		depth.append(depth[pick.from] + 1)
		parents.append(pick.from)
		slots.append(slot)
	# One optional loop keeps the graph from always being a tree.
	var loops: Array = []
	for i in slots.size():
		for dir: String in ["E", "S"]:
			var other: int = occupied.get(key(slots[i] + DIRS[dir]), -1)
			if other >= 0 and not _connected(edges, i, other):
				loops.append([i, other, dir])
	if not loops.is_empty() and graph_stream.next_float() < 0.45:
		edges.append(loops[graph_stream.next_u32() % loops.size()])
	var adjacency := _adjacency(slots.size(), edges)
	var distance := _graph_distances(adjacency, 0)
	# --- Roles ---------------------------------------------------------------------
	var role_stream := Stream.new(VERSION + "|roles|" + blueprint.streams.encounters)
	var deepest: Array[int] = []
	var max_depth: int = distance.max()
	for i in slots.size():
		if distance[i] == max_depth:
			deepest.append(i)
	var dungeon_region: int = deepest[role_stream.next_u32() % deepest.size()]
	var from_dungeon := _graph_distances(adjacency, dungeon_region)
	var extraction_region := 0
	var best := -1
	for i in slots.size():
		if i == 0 or i == dungeon_region:
			continue
		# Prefer a separate leaf far from the descent so extraction is a second journey.
		var score: int = from_dungeon[i] * 2 + int(adjacency[i].size() == 1)
		if score > best:
			best = score
			extraction_region = i
	var route := _path(adjacency, 0, dungeon_region)
	var sentinel_candidates: Array = route.slice(1, route.size() - 1)
	if sentinel_candidates.is_empty():
		sentinel_candidates = [dungeon_region]
	var sentinel: int = sentinel_candidates[role_stream.next_u32() % sentinel_candidates.size()]
	var site_regions: Array = [sentinel]
	if float(generation.challenge.encounter_density) > 0.5:
		var optional: Array = []
		for i in slots.size():
			if i not in [0, sentinel, extraction_region]:
				optional.append(i)
		if not optional.is_empty():
			site_regions.append(optional[role_stream.next_u32() % optional.size()])
	# --- Stage 2: region footprints -------------------------------------------------
	var templates: Array = data.region_templates
	var used_templates := {}
	var used_landmarks := {}
	var ranking: Array = blueprint.identity.biome.ranking
	var regions: Array = []
	var tiles := {}
	var blocked := {}
	var solids: Array = []
	var slot_size := int(config.slot)
	var levels: Array[int] = []
	levels.resize(slots.size())
	for i in slots.size():
		var region_stream := Stream.new("%s|region.%d|%s" % [VERSION, i, blueprint.streams.terrain])
		var sockets := {}
		for edge: Array in edges:
			if edge[0] == i:
				sockets[edge[2]] = edge[1]
			elif edge[1] == i:
				sockets[OPPOSITE[edge[2]]] = edge[0]
		var options: Array = []
		for template: Dictionary in templates:
			if i in site_regions and not _site_capable(template.rows):
				continue
			options.append({"id": template.id, "rows": template.rows,
				"weight": float(template.weight) * pow(0.35, used_templates.get(template.id, 0))})
		var template: Dictionary = options[region_stream.pick_weighted(options)]
		used_templates[template.id] = used_templates.get(template.id, 0) + 1
		var biome_weights: Array = []
		for rank in ranking.size():
			biome_weights.append({"weight": [1.0, 0.6, 0.3][rank] if i > 0 else float(rank == 0)})
		var biome: String = ranking[region_stream.pick_weighted(biome_weights)].id
		if parents[i] < 0:
			levels[i] = 0
		else:
			var change := region_stream.next_float() < 0.15 + float(generation.terrain.relief) * 0.9
			var step := (1 if region_stream.next_u32() % 2 == 0 else -1) if change else 0
			levels[i] = clampi(levels[parents[i]] + step, 0, int(config.max_level))
		var landmark_options: Array = []
		for landmark: Dictionary in data.landmarks:
			var matches := 0
			for tag: String in landmark.tags:
				matches += int(tag in tags)
			landmark_options.append({"id": landmark.id, "weight": (float(landmark.weight) + matches * 1.5) * (0.08 if used_landmarks.has(landmark.id) else 1.0)})
		var landmark: String = landmark_options[region_stream.pick_weighted(landmark_options)].id
		used_landmarks[landmark] = true
		var center := slots[i] * slot_size
		var region_cells: Array = []
		for row in template.rows.size():
			var line: String = template.rows[row]
			for column in line.length():
				var cell := center + Vector2i(column - RADIUS, row - RADIUS)
				if line[column] == "#":
					tiles[key(cell)] = {"cell": [cell.x, cell.y], "owner": "r%d" % i}
					region_cells.append([cell.x, cell.y])
				elif line[column] == "P":
					blocked[key(cell)] = true
		var roles: Array = []
		if i == 0:
			roles.append("arrival")
		if i == dungeon_region:
			roles.append("descent")
		if i == extraction_region:
			roles.append("extraction")
		if i in site_regions:
			roles.append("sentinel" if i == sentinel else "vigil")
		regions.append({"id": "r%d" % i, "slot": [slots[i].x, slots[i].y], "center": [center.x, center.y],
			"template": template.id, "biome": biome, "level": levels[i], "landmark": landmark,
			"sockets": sockets, "roles": roles, "cells": region_cells, "depth": distance[i]})
		_landmark_solids(regions[i], template.rows, solids, region_stream)
	var bridges: Array = []
	for b in edges.size():
		var edge: Array = edges[b]
		var dir: Vector2i = DIRS[edge[2]]
		var start: Vector2i = slots[edge[0]] * slot_size
		var cells: Array = []
		for along in range(RADIUS + 1, slot_size - RADIUS):
			for across in range(-1, 2):
				var cell := start + dir * along + Vector2i(dir.y, dir.x) * across
				tiles[key(cell)] = {"cell": [cell.x, cell.y], "owner": "b%d" % b}
				cells.append([cell.x, cell.y])
		bridges.append({"id": "b%d" % b, "from": "r%d" % edge[0], "to": "r%d" % edge[1], "dir": edge[2],
			"from_level": levels[edge[0]], "to_level": levels[edge[1]], "cells": cells,
			"loop": b >= slots.size() - 1})
	var world := {"cell": float(config.cell), "level_height": float(config.level_height), "regions": regions,
		"bridges": bridges, "blocked": blocked, "solids": solids, "tiles": tiles, "reserved": {}}
	# --- Stage 3: placements ---------------------------------------------------------
	for region: Dictionary in regions:
		_reserve_sockets(world, region)
	var arrival: Dictionary = regions[0]
	world["spawn"] = _open_cell(world, arrival, cell_of(arrival.center) + Vector2i(0, 2))
	_reserve(world, cell_of(world.spawn), 1)
	var sites: Array = []
	var themes: Array = blueprint.variation.featured.encounters
	for index in site_regions.size():
		var region: Dictionary = regions[site_regions[index]]
		var site_cell := _site_cell(world, region)
		_reserve(world, site_cell, 2)
		sites.append({"id": "site.%s" % region.id, "kind": "exterior", "region": region.id,
			"cell": [site_cell.x, site_cell.y], "theme": themes[index % themes.size()] if not themes.is_empty() else "wanderers",
			"required": index == 0})
	world["sites"] = sites
	var descent_region: Dictionary = regions[dungeon_region]
	world["descent"] = _descent(world, descent_region, solids)
	var extraction_target: Dictionary = regions[extraction_region]
	world["extraction"] = _open_cell(world, extraction_target, cell_of(extraction_target.center))
	_reserve(world, cell_of(world.extraction), 1)
	world["route"] = route.map(func(index: int) -> String: return "r%d" % index)
	return world

## Lookup dictionaries become sorted arrays: a stable fingerprint and serialization order.
static func _finalize(world: Dictionary) -> void:
	var sorted_tiles: Array = world.tiles.values()
	sorted_tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.cell[1] < b.cell[1] if a.cell[1] != b.cell[1] else a.cell[0] < b.cell[0])
	world.tiles = sorted_tiles
	for field: String in ["reserved", "blocked"]:
		var keys: Array = world[field].keys()
		keys.sort()
		world[field] = keys

static func _connected(edges: Array, a: int, b: int) -> bool:
	for edge: Array in edges:
		if (edge[0] == a and edge[1] == b) or (edge[0] == b and edge[1] == a):
			return true
	return false

static func _adjacency(count: int, edges: Array) -> Array:
	var adjacency: Array = []
	for i in count:
		adjacency.append([])
	for edge: Array in edges:
		adjacency[edge[0]].append(edge[1])
		adjacency[edge[1]].append(edge[0])
	return adjacency

static func _graph_distances(adjacency: Array, start: int) -> Array:
	var distance: Array = []
	distance.resize(adjacency.size())
	distance.fill(-1)
	distance[start] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in adjacency[current]:
			if distance[next] < 0:
				distance[next] = distance[current] + 1
				queue.append(next)
	return distance

static func _path(adjacency: Array, start: int, goal: int) -> Array:
	var parent := {start: -1}
	var queue: Array = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in adjacency[current]:
			if not parent.has(next):
				parent[next] = current
				queue.append(next)
	var path: Array = []
	var node := goal
	while node >= 0:
		path.push_front(node)
		node = parent[node]
	return path

static func _site_capable(rows: Array) -> bool:
	return rows[RADIUS].substr(1, 5) == "#####" and _window_open(rows, RADIUS, RADIUS)

static func _window_open(rows: Array, row: int, column: int) -> bool:
	for r in range(row - 2, row + 3):
		for c in range(column - 2, column + 3):
			if r < 0 or c < 0 or r >= rows.size() or c >= rows[r].length() or rows[r][c] != "#":
				return false
	return true

# --- Stage 2 helpers -------------------------------------------------------------

static func _landmark_solids(region: Dictionary, rows: Array, solids: Array, stream: Stream) -> void:
	var cell := 4.0
	var center := Vector2(region.center[0], region.center[1]) * cell
	var height := 7.0 + stream.next_float() * 5.0 + float(region.level) * 1.5
	# Template P-blocks are solid in-region landmarks or columns; each fills only
	# its own blocked cells, minus a margin, so it never intrudes on walkable tiles.
	var block_cells: Array = []
	for row in rows.size():
		for column in rows[row].length():
			if rows[row][column] == "P":
				block_cells.append(Vector2(column - RADIUS, row - RADIUS))
	if block_cells.size() >= 9:
		solids.append({"region": region.id, "kind": "landmark", "id": region.landmark,
			"rect": _rect(center, Vector2(cell * 3.0 - 1.2, cell * 3.0 - 1.2)), "height": height})
	else:
		for offset: Vector2 in block_cells:
			solids.append({"region": region.id, "kind": "column", "id": "column",
				"rect": _rect(center + offset * cell, Vector2(1.6, 1.6)), "height": 5.0 + float(region.level) * 0.5})
		# Otherwise the landmark rises beyond a side that has no bridge, off the walk.
		for dir: String in DIR_ORDER:
			if not region.sockets.has(dir):
				var direction := Vector2(DIRS[dir])
				solids.append({"region": region.id, "kind": "landmark", "id": region.landmark,
					"rect": _rect(center + direction * (RADIUS * cell + cell * 0.5 + 7.0), Vector2(8.0, 8.0)), "height": height + 3.0})
				break

static func _rect(center: Vector2, size: Vector2) -> Array:
	return [center.x - size.x * 0.5, center.y - size.y * 0.5, center.x + size.x * 0.5, center.y + size.y * 0.5]

static func _reserve(world: Dictionary, cell: Vector2i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			world.reserved[key(cell + Vector2i(x, z))] = true

static func _reserve_sockets(world: Dictionary, region: Dictionary) -> void:
	var center := cell_of(region.center)
	for dir: String in region.sockets:
		var direction: Vector2i = DIRS[dir]
		for depth_index in range(RADIUS - 1, RADIUS + 1):
			for across in range(-1, 2):
				world.reserved[key(center + direction * depth_index + Vector2i(direction.y, direction.x) * across)] = true

static func _walkable(world: Dictionary, cell: Vector2i) -> bool:
	return world.tiles.has(key(cell)) and not world.blocked.has(key(cell))

static func _open_cell(world: Dictionary, region: Dictionary, preferred: Vector2i) -> Array:
	var best: Array = []
	var best_distance := INF
	for value: Array in region.cells:
		var cell := cell_of(value)
		if not _walkable(world, cell) or world.reserved.has(key(cell)):
			continue
		var d := Vector2(cell - preferred).length()
		if d < best_distance:
			best_distance = d
			best = [cell.x, cell.y]
	return best

static func _site_cell(world: Dictionary, region: Dictionary) -> Vector2i:
	var center := cell_of(region.center)
	var best := center
	var best_distance := INF
	for value: Array in region.cells:
		var cell := cell_of(value)
		var open := true
		for x in range(-2, 3):
			for z in range(-2, 3):
				open = open and _walkable(world, cell + Vector2i(x, z))
		var d := Vector2(cell - center).length()
		if open and d < best_distance:
			best = cell
			best_distance = d
	return best

static func _descent(world: Dictionary, region: Dictionary, solids: Array) -> Dictionary:
	# The descent sits on the region's rim, as far as possible from where the
	# journey arrives, and is entered from the inward neighbour cell.
	var center := cell_of(region.center)
	var arrival := center
	for dir: String in region.sockets:
		if region.sockets[dir] < int(region.id.substr(1)):
			arrival = center + DIRS[dir] * RADIUS
	var best: Dictionary = {}
	var best_score := -INF
	for value: Array in region.cells:
		var cell := cell_of(value)
		if world.reserved.has(key(cell)) or not _walkable(world, cell):
			continue
		for dir: String in DIR_ORDER:
			var inward: Vector2i = cell - DIRS[dir]
			if _walkable(world, cell + DIRS[dir]) or not _walkable(world, inward) or world.reserved.has(key(inward)):
				continue
			var score := Vector2(cell - arrival).length() - Vector2(cell - center).length() * 0.2
			if score > best_score:
				best_score = score
				best = {"region": region.id, "cell": [cell.x, cell.y], "approach": [inward.x, inward.y], "facing": dir}
	if best.is_empty():
		return best
	_reserve(world, cell_of(best.approach), 0)
	world.reserved[key(cell_of(best.cell))] = true
	# Two arch posts stand inside the descent cell, beside the 2.6 m opening.
	var cell_size := 4.0
	var origin := Vector2(best.cell[0], best.cell[1]) * cell_size
	var forward := Vector2(DIRS[best.facing])
	var side := Vector2(forward.y, forward.x)
	for sign_value: float in [-1.0, 1.0]:
		solids.append({"region": region.id, "kind": "descent_post", "id": "descent_post",
			"rect": _rect(origin + side * sign_value * 1.65 + forward * 0.6, Vector2(0.6, 0.6)), "height": 5.5})
	return best

# --- Stage 3: loot -----------------------------------------------------------------

static func _place_loot(plan: Dictionary, blueprint: Dictionary) -> void:
	var world: Dictionary = plan.world
	var stream := Stream.new(VERSION + "|loot|" + blueprint.streams.discoveries)
	var table: Array = blueprint.identity.theme_tables.discoveries
	var loot: Array = []
	for region: Dictionary in world.regions:
		if "arrival" in region.roles:
			continue
		var count := 1 + int(stream.next_float() < 0.4)
		var candidates: Array = []
		for value: Array in region.cells:
			var cell := cell_of(value)
			if _walkable(world, cell) and not world.reserved.has(key(cell)):
				candidates.append(cell)
		for n in count:
			if candidates.is_empty():
				break
			# Prefer rims and corners: small rewards for looking around a region.
			var center := cell_of(region.center)
			var weighted: Array = []
			for cell: Vector2i in candidates:
				weighted.append({"weight": 0.2 + Vector2(cell - center).length_squared()})
			var cell: Vector2i = candidates[stream.pick_weighted(weighted)]
			candidates.erase(cell)
			var item: String = table[stream.pick_weighted(table)].id if not table.is_empty() else "remnant"
			loot.append({"id": "loot.%s.%d" % [region.id, n], "item": "discovery." + item, "area": "world",
				"cell": [cell.x, cell.y], "kind": "resource"})
			world.reserved[key(cell)] = true
	var dungeon: Dictionary = plan.dungeon
	var featured: Array = blueprint.variation.featured.discoveries
	for entry: Dictionary in dungeon.pickups:
		var item: String = featured[0] if entry.kind == "relic" and not featured.is_empty() else table[stream.pick_weighted(table)].id
		loot.append({"id": entry.id, "item": ("relic." if entry.kind == "relic" else "discovery.") + item,
			"area": "dungeon", "cell": entry.cell, "kind": entry.kind})
	plan["loot"] = loot
