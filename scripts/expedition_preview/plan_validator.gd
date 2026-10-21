extends RefCounted
## Topology and geometry checks over a finished expedition plan, before any node
## is built. Returns error dictionaries; an empty array means the plan is valid.
## Tests also run these checks against deliberately broken plans.
const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const GUARDIAN_CLEAR_RADIUS := 5 # 11 x 11 cells (22 m) of unobstructed duel floor.

static func validate(plan: Dictionary) -> Array:
	var errors: Array = []
	_world(plan, errors)
	_dungeon(plan.dungeon, errors)
	for item: Dictionary in plan.get("loot", []):
		if item.area == "dungeon" and not _cells(plan.dungeon.tiles).has(_key(item.cell)):
			errors.append({"code": "dungeon_loot_off_floor", "id": item.id})
	return errors

static func _key(value: Variant) -> String:
	if value is Vector2i:
		return "%d,%d" % [value.x, value.y]
	return "%d,%d" % [int(value[0]), int(value[1])]

static func _cells(values: Array) -> Dictionary:
	var cells := {}
	for value: Variant in values:
		var cell: Array = value.cell if value is Dictionary else value
		cells[_key(cell)] = Vector2i(int(cell[0]), int(cell[1]))
	return cells

static func _flood(walkable: Dictionary, start: Vector2i) -> Dictionary:
	var reached := {}
	if not walkable.has(_key(start)):
		return reached
	reached[_key(start)] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for step: Vector2i in STEPS:
			var next := current + step
			var next_key := _key(next)
			if walkable.has(next_key) and not reached.has(next_key):
				reached[next_key] = true
				queue.append(next)
	return reached

static func _overlap(a: Array, b: Array) -> bool:
	# Positive-area intersection; touching faces are allowed.
	return minf(a[2], b[2]) - maxf(a[0], b[0]) > 0.001 and minf(a[3], b[3]) - maxf(a[1], b[1]) > 0.001

static func _cell_rect(cell: Vector2i, size: float) -> Array:
	return [(cell.x - 0.5) * size, (cell.y - 0.5) * size, (cell.x + 0.5) * size, (cell.y + 0.5) * size]

static func _solids(solids: Array, walkable: Dictionary, size: float, errors: Array, scope: String) -> void:
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			if _overlap(solids[i].rect, solids[j].rect):
				errors.append({"code": scope + "_solids_overlap", "a": i, "b": j})
		for cell: Vector2i in walkable.values():
			if _overlap(solids[i].rect, _cell_rect(cell, size)):
				errors.append({"code": scope + "_solid_on_walkable_floor", "solid": i, "cell": [cell.x, cell.y]})
				break

static func _world(plan: Dictionary, errors: Array) -> void:
	var world: Dictionary = plan.world
	var regions: Array = world.regions
	var size: float = world.cell
	# Region graph connectivity over bridges.
	var adjacency := {}
	for region: Dictionary in regions:
		adjacency[region.id] = []
	for bridge: Dictionary in world.bridges:
		adjacency[bridge.from].append(bridge.to)
		adjacency[bridge.to].append(bridge.from)
		if absi(int(bridge.from_level) - int(bridge.to_level)) > 2:
			errors.append({"code": "bridge_too_steep", "id": bridge.id})
	var seen := {regions[0].id: true}
	var queue: Array = [regions[0].id]
	while not queue.is_empty():
		for next: String in adjacency[queue.pop_back()]:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	if seen.size() != regions.size():
		errors.append({"code": "regions_disconnected", "reached": seen.size(), "regions": regions.size()})
	var tiles := _cells(world.tiles)
	var blocked := {}
	for cell_key: String in world.blocked:
		blocked[cell_key] = true
	var walkable := {}
	for cell_key: String in tiles:
		if not blocked.has(cell_key):
			walkable[cell_key] = tiles[cell_key]
	# Bridges meet walkable socket cells at both ends, on the bridge's own axis.
	var by_id := {}
	for region: Dictionary in regions:
		by_id[region.id] = region
	for bridge: Dictionary in world.bridges:
		var direction: Vector2i = DIRS[bridge.dir]
		for end: Array in [[bridge.from, direction], [bridge.to, -direction]]:
			var center: Array = by_id[end[0]].center
			for across in range(-1, 2):
				var socket: Vector2i = Vector2i(int(center[0]), int(center[1])) + end[1] * 3 + Vector2i(absi(direction.y), absi(direction.x)) * across
				var beyond: Vector2i = socket + end[1]
				if not walkable.has(_key(socket)) or not walkable.has(_key(beyond)):
					errors.append({"code": "bridge_socket_misaligned", "id": bridge.id, "region": end[0]})
	var descent: Dictionary = world.get("descent", {})
	if descent.is_empty():
		errors.append({"code": "missing_descent"})
	else:
		walkable.erase(_key(descent.cell)) # A destination, not a through-route.
	var reached := _flood(walkable, Vector2i(int(world.spawn[0]), int(world.spawn[1])))
	if reached.size() != walkable.size():
		errors.append({"code": "unreachable_world_floor", "reached": reached.size(), "walkable": walkable.size()})
	var targets: Array = [["extraction", world.extraction]]
	if not descent.is_empty():
		targets.append(["descent_approach", descent.approach])
	for site: Dictionary in world.sites:
		targets.append([site.id, site.cell])
		for x in range(-2, 3):
			for z in range(-2, 3):
				if not walkable.has(_key(Vector2i(int(site.cell[0]) + x, int(site.cell[1]) + z))):
					errors.append({"code": "site_not_clear", "id": site.id})
	for item: Dictionary in plan.get("loot", []):
		if item.area == "world":
			targets.append([item.id, item.cell])
	for target: Array in targets:
		if target[1].is_empty() or not reached.has(_key(target[1])):
			errors.append({"code": "unreachable_target", "id": target[0]})
	_solids(world.solids, walkable, size, errors, "world")

static func _dungeon(dungeon: Dictionary, errors: Array) -> void:
	var rooms: Array = dungeon.rooms
	var corridors: Array = dungeon.corridors
	var roles: Array = rooms.map(func(room: Dictionary) -> String: return room.role)
	for role: String in ["entry", "guardian", "reward", "cache"]:
		if roles.count(role) != 1:
			errors.append({"code": "dungeon_role_count", "role": role})
	var pieces: Array = []
	for room: Dictionary in rooms:
		pieces.append({"id": room.id, "rect": room.rect, "links": []})
	for corridor: Dictionary in corridors:
		pieces.append({"id": corridor.id, "rect": corridor.rect, "links": [corridor.from, corridor.to]})
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var a: Dictionary = pieces[i]
			var b: Dictionary = pieces[j]
			var linked: bool = b.id in a.links or a.id in b.links
			var ra: Array = a.rect
			var rb: Array = b.rect
			var gap_x := maxi(int(rb[0]) - int(ra[2]), int(ra[0]) - int(rb[2])) - 1
			var gap_z := maxi(int(rb[1]) - int(ra[3]), int(ra[1]) - int(rb[3])) - 1
			if gap_x < 0 and gap_z < 0:
				errors.append({"code": "dungeon_pieces_overlap", "a": a.id, "b": b.id})
			elif not linked and gap_x < 1 and gap_z < 1:
				errors.append({"code": "dungeon_pieces_touch_without_door", "a": a.id, "b": b.id})
	var tiles := _cells(dungeon.tiles)
	var blocked := _cells(dungeon.blocked)
	var walkable := {}
	for cell_key: String in tiles:
		if not blocked.has(cell_key):
			walkable[cell_key] = tiles[cell_key]
	# Door alignment: every corridor end opens onto three walkable room cells.
	var by_id := {}
	for room: Dictionary in rooms:
		by_id[room.id] = room
	for corridor: Dictionary in corridors:
		var direction: Vector2i = DIRS[corridor.dir]
		var rect: Array = corridor.rect
		for end: Array in [[corridor.from, -direction], [corridor.to, direction]]:
			var room: Dictionary = by_id[end[0]]
			var room_rect: Array = room.rect
			var opened := 0
			for x in range(int(rect[0]), int(rect[2]) + 1):
				for z in range(int(rect[1]), int(rect[3]) + 1):
					var inside: Vector2i = Vector2i(x, z) + end[1]
					if inside.x >= int(room_rect[0]) and inside.x <= int(room_rect[2]) and inside.y >= int(room_rect[1]) and inside.y <= int(room_rect[3]) and walkable.has(_key(inside)):
						opened += 1
			if opened != 3:
				errors.append({"code": "dungeon_door_misaligned", "corridor": corridor.id, "room": end[0], "open": opened})
	var spawn := Vector2i(int(dungeon.spawn[0]), int(dungeon.spawn[1]))
	var reached := _flood(walkable, spawn)
	if reached.size() != walkable.size():
		errors.append({"code": "unreachable_dungeon_floor", "reached": reached.size(), "walkable": walkable.size()})
	var targets: Array = [["return_portal", dungeon.return_portal], ["ascent_portal", dungeon.ascent_portal], ["guardian", dungeon.guardian.cell]]
	for pickup: Dictionary in dungeon.pickups:
		targets.append([pickup.id, pickup.cell])
	for target: Array in targets:
		if not reached.has(_key(target[1])):
			errors.append({"code": "unreachable_dungeon_target", "id": target[0]})
	# The guardian is a true chokepoint: removing its room cuts the reward off.
	var guardian_room: Dictionary = by_id.get(dungeon.guardian.room, {})
	var reward_room: Dictionary = {}
	for room: Dictionary in rooms:
		if room.role == "reward":
			reward_room = room
	if not guardian_room.is_empty() and not reward_room.is_empty():
		var without := walkable.duplicate()
		var g: Array = guardian_room.rect
		for x in range(int(g[0]), int(g[2]) + 1):
			for z in range(int(g[1]), int(g[3]) + 1):
				without.erase(_key(Vector2i(x, z)))
		var bypass := _flood(without, spawn)
		if bypass.has(_key(reward_room.center)):
			errors.append({"code": "reward_bypasses_guardian"})
		var center := Vector2i(int(dungeon.guardian.cell[0]), int(dungeon.guardian.cell[1]))
		for x in range(-GUARDIAN_CLEAR_RADIUS, GUARDIAN_CLEAR_RADIUS + 1):
			for z in range(-GUARDIAN_CLEAR_RADIUS, GUARDIAN_CLEAR_RADIUS + 1):
				if not walkable.has(_key(center + Vector2i(x, z))):
					errors.append({"code": "guardian_floor_obstructed", "cell": [center.x + x, center.y + z]})
	if dungeon.gates.size() != 2:
		errors.append({"code": "guardian_gate_count", "count": dungeon.gates.size()})
	_solids(dungeon.solids, walkable, float(dungeon.cell), errors, "dungeon")
