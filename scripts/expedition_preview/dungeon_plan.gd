extends RefCounted
## Room-and-connection dungeon: the topology (entry -> fillers -> guardian -> reward,
## plus a side cache) is chosen first, then embedded on a 2 m grid from authored
## room modules. Rooms and corridors keep a one-cell void between unrelated pieces,
## so walls never overlap and a door exists only where a corridor meets a socket.
## Failed embeddings retry on a fresh named stream; a fixed straight fallback is
## always valid. Validation runs on the result in plan_validator.gd.
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
## Footprint (cells, local x by local z) and solid size (metres) of each feature kind.
const FEATURES := {"pillar": {"cells": Vector2i(1, 1), "solid": Vector2(1.2, 1.2), "height": 5.0},
	"sarcophagus": {"cells": Vector2i(3, 1), "solid": Vector2(5.2, 1.4), "height": 1.1},
	"pedestal": {"cells": Vector2i(1, 1), "solid": Vector2(1.0, 1.0), "height": 1.0},
	"bone_pile": {"cells": Vector2i(1, 1), "solid": Vector2(1.4, 1.4), "height": 0.7}}

static func generate(seed_text: String, blueprint: Dictionary, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.dungeon
	var templates: Dictionary = {}
	for room: Dictionary in data.dungeon_rooms:
		templates[room.id] = room
	for attempt in int(config.attempts):
		var stream := Stream.new("%s|attempt.%d" % [seed_text, attempt])
		var layout := _attempt(stream, blueprint, config, data.dungeon_rooms, templates)
		if not layout.is_empty():
			return _finish(layout, config, attempt, false)
	var fallback := _layout(["antechamber", "pillar_hall", "guard_chamber", "reliquary_vault"],
		["N", "N", "N"], [2, 2, 2], {"room": 0, "dir": "E", "length": 2}, templates)
	return _finish(fallback, config, -1, true)

static func _attempt(stream: Stream, blueprint: Dictionary, config: Dictionary, rooms: Array, templates: Dictionary) -> Dictionary:
	var range_fillers: Array = config.filler_count
	var structure: Dictionary = blueprint.generation.structure
	var fillers := clampi(int(range_fillers[0]) + int(float(structure.interior_ratio) * 2.0 + stream.next_float() * 1.2),
		int(range_fillers[0]), int(range_fillers[1]))
	var filler_options: Array = []
	for room: Dictionary in rooms:
		if room.role == "filler":
			filler_options.append({"id": room.id, "weight": float(room.weight)})
	var chain: Array = ["antechamber"]
	for i in fillers:
		chain.append(filler_options[stream.pick_weighted(filler_options)].id)
	chain.append_array(["guard_chamber", "reliquary_vault"])
	var lengths_range: Array = config.corridor_length
	var dirs: Array = []
	var lengths: Array = []
	var travel := "N"
	for i in chain.size() - 1:
		# Forward-biased turns: a deliberate procession rather than a scattered maze.
		var options := [{"dir": travel, "weight": 1.3}, {"dir": _turn(travel, 1), "weight": 1.0}, {"dir": _turn(travel, -1), "weight": 1.0}]
		travel = options[stream.pick_weighted(options)].dir
		dirs.append(travel)
		var tight := float(structure.passage_tightness)
		lengths.append(clampi(int(lengths_range[0]) + int(stream.next_float() * (int(lengths_range[1]) - int(lengths_range[0]) + 1) * (0.6 + tight * 0.4)),
			int(lengths_range[0]), int(lengths_range[1])))
	var side := {"room": int(stream.next_u32() % (fillers + 1)), "dir": "E" if stream.next_u32() % 2 == 0 else "W",
		"length": int(lengths_range[0]) + int(stream.next_u32() % 2)}
	return _layout(chain, dirs, lengths, side, templates)

static func _turn(dir: String, step: int) -> String:
	var order := ["N", "E", "S", "W"]
	return order[posmod(order.find(dir) + step, 4)]

## Embeds the chain and one side cache. Returns {} when a piece would collide.
static func _layout(chain: Array, dirs: Array, lengths: Array, side: Dictionary, templates: Dictionary) -> Dictionary:
	var rooms: Array = []
	var corridors: Array = []
	rooms.append(_room("d0", templates[chain[0]], Vector2i.ZERO, "N"))
	for i in range(1, chain.size()):
		var placed := _attach(rooms, corridors, i - 1, templates[chain[i]], dirs[i - 1], lengths[i - 1], "d%d" % i)
		if not placed:
			return {}
	var parent: Dictionary = rooms[side.room]
	var side_dir: String = side.dir
	# Side branches turn off the travel axis of their room and never reuse a socket.
	if side_dir in parent.sockets or side_dir == OPPOSITE[parent.travel]:
		side_dir = OPPOSITE[side_dir]
	if side_dir in parent.sockets or side_dir == OPPOSITE[parent.travel]:
		return {}
	if not _attach(rooms, corridors, side.room, templates["ossuary_niche"], side_dir, side.length, "d%d" % rooms.size()):
		return {}
	return {"rooms": rooms, "corridors": corridors, "chain": chain}

static func _room(id: String, template: Dictionary, center: Vector2i, travel: String) -> Dictionary:
	var size := Vector2i(int(template.size[0]), int(template.size[1]))
	if travel in ["E", "W"]:
		size = Vector2i(size.y, size.x) # Long modules align their length with travel.
	var half := (size - Vector2i.ONE) / 2
	return {"id": id, "template": template.id, "role": template.role, "center": center, "size": size,
		"rect": Rect2i(center - half, size), "travel": travel, "sockets": {}, "features": template.features}

static func _attach(rooms: Array, corridors: Array, parent_index: int, template: Dictionary, dir: String, length: int, id: String) -> bool:
	var parent: Dictionary = rooms[parent_index]
	if dir in parent.sockets:
		return false
	var direction: Vector2i = DIRS[dir]
	var parent_half := _half_along(parent.size, dir)
	var probe := _room(id, template, Vector2i.ZERO, dir)
	var child_half := _half_along(probe.size, dir)
	var center: Vector2i = parent.center + direction * (parent_half + length + child_half + 1)
	var room := _room(id, template, center, dir)
	var start: Vector2i = parent.center + direction * (parent_half + 1)
	var end: Vector2i = parent.center + direction * (parent_half + length)
	var across := Vector2i(absi(direction.y), absi(direction.x))
	var corridor_rect := Rect2i(Vector2i(mini(start.x, end.x), mini(start.y, end.y)) - across, Vector2i(absi(end.x - start.x) + 1, absi(end.y - start.y) + 1) + across * 2)
	var corridor := {"id": "c%d" % corridors.size(), "from": parent.id, "to": id, "dir": dir, "rect": corridor_rect}
	# One void cell must separate unrelated pieces; connected pieces may only touch.
	for other: Dictionary in rooms:
		if room.rect.grow(1).intersects(other.rect) or (other.id != parent.id and corridor_rect.grow(1).intersects(other.rect)):
			return false
	for other: Dictionary in corridors:
		if room.rect.grow(1).intersects(other.rect) or corridor_rect.grow(1).intersects(other.rect):
			return false
	parent.sockets[dir] = id
	room.sockets[OPPOSITE[dir]] = parent.id
	rooms.append(room)
	corridors.append(corridor)
	return true

static func _half_along(size: Vector2i, dir: String) -> int:
	return (size.y - 1) / 2 if dir in ["N", "S"] else (size.x - 1) / 2

## Local feature/placement offsets: +x is the room's right, +z its back (entry side).
static func _local(room: Dictionary, at: Vector2i) -> Vector2i:
	var forward: Vector2i = DIRS[room.travel]
	var right := Vector2i(-forward.y, forward.x)
	return room.center + right * at.x - forward * at.y

static func _finish(layout: Dictionary, config: Dictionary, attempt: int, fallback: bool) -> Dictionary:
	var cell := float(config.cell)
	var tiles := {}
	var blocked := {}
	var solids: Array = []
	var rooms: Array = []
	var pickups: Array = []
	var by_role := {}
	for room: Dictionary in layout.rooms:
		var rect: Rect2i = room.rect
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				tiles["%d,%d" % [x, z]] = [x, z]
		for feature: Dictionary in room.features:
			var spec: Dictionary = FEATURES[feature.kind]
			var at := _local(room, Vector2i(int(feature.at[0]), int(feature.at[1])))
			var footprint: Vector2i = spec.cells
			var solid: Vector2 = spec.solid
			if room.travel in ["E", "W"]:
				footprint = Vector2i(footprint.y, footprint.x)
				solid = Vector2(solid.y, solid.x)
			var half := (footprint - Vector2i.ONE) / 2
			for x in range(at.x - half.x, at.x + half.x + 1):
				for z in range(at.y - half.y, at.y + half.y + 1):
					blocked["%d,%d" % [x, z]] = [x, z]
			var origin := Vector2(at) * cell
			solids.append({"room": room.id, "kind": feature.kind,
				"rect": [origin.x - solid.x * 0.5, origin.y - solid.y * 0.5, origin.x + solid.x * 0.5, origin.y + solid.y * 0.5],
				"height": float(spec.height)})
		by_role[room.role] = room
		rooms.append({"id": room.id, "template": room.template, "role": room.role, "center": [room.center.x, room.center.y],
			"rect": [rect.position.x, rect.position.y, rect.end.x - 1, rect.end.y - 1], "travel": room.travel,
			"sockets": room.sockets})
	var corridors: Array = []
	var gates: Array = []
	var guardian: Dictionary = by_role.guardian
	for corridor: Dictionary in layout.corridors:
		var rect: Rect2i = corridor.rect
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				tiles["%d,%d" % [x, z]] = [x, z]
		corridors.append({"id": corridor.id, "from": corridor.from, "to": corridor.to, "dir": corridor.dir,
			"rect": [rect.position.x, rect.position.y, rect.end.x - 1, rect.end.y - 1]})
		# The guardian's doors: the way in seals for the duel; the way on stays sealed until victory.
		var direction: Vector2i = DIRS[corridor.dir]
		if corridor.to == guardian.id:
			var boundary := Vector2(guardian.center) - Vector2(direction) * (_half_along(guardian.size, corridor.dir) + 0.5)
			gates.append({"id": "gate.guardian_entry", "center": [boundary.x * cell, boundary.y * cell], "axis": "x" if corridor.dir in ["N", "S"] else "z", "width": 3 * cell, "opens": "victory"})
		elif corridor.from == guardian.id:
			var boundary := Vector2(guardian.center) + Vector2(direction) * (_half_along(guardian.size, corridor.dir) + 0.5)
			gates.append({"id": "gate.guardian_exit", "center": [boundary.x * cell, boundary.y * cell], "axis": "x" if corridor.dir in ["N", "S"] else "z", "width": 3 * cell, "opens": "victory"})
	var entry: Dictionary = by_role.entry
	var reward: Dictionary = by_role.reward
	var cache: Dictionary = by_role.cache
	pickups.append({"id": "loot.vault.relic", "kind": "relic", "room": reward.id, "cell": _array(_local(reward, Vector2i(0, -1)))})
	pickups.append({"id": "loot.cache.0", "kind": "resource", "room": cache.id, "cell": _array(_local(cache, Vector2i(0, -1)))})
	var sorted_tiles: Array = tiles.values()
	sorted_tiles.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] if a[1] != b[1] else a[0] < b[0])
	var sorted_blocked: Array = blocked.values()
	sorted_blocked.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] if a[1] != b[1] else a[0] < b[0])
	var critical: Array = []
	for room: Dictionary in layout.rooms:
		if room.role != "cache":
			critical.append(room.id)
	return {"cell": cell, "origin": config.origin.duplicate(), "wall_height": float(config.wall_height), "attempt": attempt,
		"fallback": fallback, "rooms": rooms, "corridors": corridors, "tiles": sorted_tiles, "blocked": sorted_blocked,
		"solids": solids, "gates": gates, "critical_path": critical, "pickups": pickups,
		"spawn": _array(_local(entry, Vector2i(0, 1))), "return_portal": _array(_local(entry, Vector2i(0, 3))),
		"ascent_portal": _array(_local(reward, Vector2i(-3, 2))),
		"guardian": {"room": guardian.id, "cell": [guardian.center.x, guardian.center.y]}}

static func _array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]
