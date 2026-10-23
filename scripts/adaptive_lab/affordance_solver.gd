extends RefCounted
## Object + body → capability set (v2). The only inputs are the measured analysis of
## the object's structure — Research Lab imports (lab_analysis.gd) or the game's v0
## comparison descriptors (object_analysis.gd) — and the body descriptor
## (body_plans.gd). Names, labels, file names and Lab assembly numbers are never read
## (tests swap them and scan the sources).
##
## Steps:
##   1. holds: one- and two-hand placements inside the declared grip intervals, legal
##      for the body's existing hands, grip span, carried mass and static torque. Each
##      hold knows how far the object can slide through the hands (`slide_room`);
##   2. physics per hold: inertia about the hands, swing/push load against the body's
##      limits, wrist roll torque, `heft` and `head` (how far the mass sits toward the
##      striking end);
##   3. archetypes per hold, each granted only when a measured feature satisfies its
##      geometric requirement (table in docs/ADAPTIVE_COMBAT_LAB.md §2.1);
##   4. timing, damage, posture and a physics fitness that ranks archetypes (a heavy
##      head favours chops, a sharp light point favours thrusts, a broad face moving
##      face-first pays drag, …); motion keys are built and the whole action sampled:
##      grips out of reach or the object passing through the wielder rejects it;
##   5. a combo graph: a light chain chosen for flow (each strike starts where the
##      previous one ended), variety and score; a neutral heavy; and per chain step a
##      heavy finisher that continues from where that step ended.
## Without a usable hold the body fights with its own anatomy (fists, shoulder).
## Everything rejected is reported with a reason code.

const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")
const LabAnalysis = preload("res://scripts/adaptive_lab/lab_analysis.gd")
const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const StrictJson = preload("res://scripts/adaptive_lab/strict_json.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const SCHEMA := "boneshed.adaptive_capabilities.v1"
const GRAVITY := 9.81
const LIGHT_WINDUP_MAX := 0.45
const SPREAD_MIN := 0.28
const REAR_CLEARANCE := 0.15
const HEAVY_TIMING := [1.5, 1.1, 1.3]
## Base damage per channel (provisional lab numbers; HP and posture are 100).
const BASE_DAMAGE := {"pierce": 13.0, "cut": 15.0, "blunt": 10.0}
const POSTURE_RATIO := {"pierce": 0.7, "cut": 0.8, "blunt": 1.3}
const HOLDS_VALIDATED := 3
const SWINGS := ["sweep", "backhand", "overhead", "rising"]
## Archetypes that need special structure (a broad face, a one-sided protrusion, a
## second strikable end): an object that has one shows it in its move set.
const SPECIAL := ["bash", "hook", "rear", "windmill"]
## A continuous two-ended rotation needs a light, long object (swing load ≤ this).
const WINDMILL_LOAD := 0.25

static func analyse(obj: Dictionary) -> Dictionary:
	if obj.get("schema") == Imp.CONTRACT:
		return LabAnalysis.analyse(obj)
	return Analysis.analyse(obj)

## Structure-only fingerprint: the Lab's own physical digest input (materials, parts,
## grips — no name or description) for imports; the v0 recipe/seed/parts otherwise.
static func structure_hash(obj: Dictionary) -> String:
	if obj.get("schema") == Imp.CONTRACT:
		var d: Dictionary = obj.original.descriptor
		return Imp.sha256_text(StrictJson.canonical({"materials": d.materials, "parts": d.parts, "grips": d.grips})).substr(0, 16)
	return JSON.stringify({"parts": obj.parts, "recipe": obj.recipe, "seed": obj.seed,
		"generator_version": obj.generator_version}, "", true).sha256_text().substr(0, 16)

static func solve(obj: Dictionary, body: Dictionary) -> Dictionary:
	var an := analyse(obj)
	var rejections: Array = []
	var holds := _holds(an, body, rejections)
	var ranked: Array = []
	for hold: Dictionary in holds:
		var phys := _physics(hold, an, body)
		var candidates := _candidates(hold, phys, an, body)
		ranked.append({"hold": hold, "phys": phys, "candidates": candidates, "score": _rough_score(candidates)})
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score or (x.score == y.score and x.hold.id < y.hold.id))
	var best: Dictionary = {}
	for entry: Dictionary in ranked.slice(0, HOLDS_VALIDATED):
		var mapped := _map_inputs(entry.hold, entry.phys, entry.candidates, an, body)
		if best.is_empty() or mapped.score > best.score:
			best = mapped
	var unarmed := false
	if best.is_empty() or (best.light.is_empty() and best.heavy == null):
		if not best.is_empty():
			rejections.append_array(best.rejections)
		rejections.append({"code": "object_not_wieldable", "detail": "no legal hold with an attack; fighting with the body's own anatomy"})
		best = _unarmed(body)
		unarmed = true
	var out := {
		"schema": SCHEMA,
		"object_fingerprint": structure_hash(obj),
		"object_source": an.get("source", "v0"),
		"body": {"id": body.id, "modifications": body.modifications, "hands": body.hands},
		"mass": snappedf(an.mass, 0.001),
		"extent": snappedf(an.extent, 0.001),
		"grip_candidates": (an.intervals as Array).size(),
		"holds_considered": holds.size(),
		"unarmed": unarmed,
		"usable": not best.light.is_empty() or best.heavy != null or best.guard != null,
		"hold": best.get("hold", null),
		"light": best.get("light", []),
		"heavy": best.get("heavy", null),
		"heavy_after": best.get("heavy_after", []),
		"guard": best.get("guard", null),
		"ready_frame": best.get("ready_frame", null),
		"physics": best.get("physics", {}),
		"rejections": rejections + (best.get("rejections", []) if not unarmed else []),
		"features": _feature_summary(an),
	}
	return out

static func _feature_summary(an: Dictionary) -> Array:
	var out: Array = []
	for f: Dictionary in an.features:
		out.append({"id": f.id, "kind": f.kind, "channel": f.channel, "sharpness": f.sharpness, "soft": f.get("soft", false)})
	return out

# --- Holds -------------------------------------------------------------------------

static func _lead_hand(body: Dictionary) -> String:
	for hand: String in ["hand_r", "hand_l"]:
		if hand in body.hands:
			return hand
	return ""

## Hand-centre samples along an interval: both ends and the middle.
static func _interval_samples(iv: Dictionary) -> Array:
	var lo: Vector3 = iv.lo
	var hi: Vector3 = iv.hi
	if lo.distance_to(hi) < 0.01:
		return [{"point": lo.lerp(hi, 0.5), "t": 0.5}]
	return [{"point": lo, "t": 0.0}, {"point": lo.lerp(hi, 0.5), "t": 0.5}, {"point": hi, "t": 1.0}]

## How far (m) the object can slide back (x) and forward (y) through the hands along
## the hold axis while every hand stays inside its interval.
static func slide_room(grips: Dictionary, intervals: Dictionary, axis: Vector3) -> Vector2:
	var back := 0.18
	var fwd := 0.18
	for hand: String in grips:
		var iv: Dictionary = intervals[hand]
		var lo: Vector3 = iv.lo
		var hi: Vector3 = iv.hi
		var length := lo.distance_to(hi)
		if length < 0.005:
			return Vector2.ZERO
		var u := (hi - lo) / length
		var k := axis.dot(u)
		if absf(k) < 0.9:
			return Vector2.ZERO
		var q := ((grips[hand] as Vector3) - lo).dot(u)
		# New param q − δ·k must stay in [0, length].
		var b0 := q / k
		var b1 := (q - length) / k
		fwd = minf(fwd, maxf(0.0, maxf(b0, b1)))
		back = minf(back, maxf(0.0, -minf(b0, b1)))
	return Vector2(snappedf(back, 0.0001), snappedf(fwd, 0.0001))

static func _holds(an: Dictionary, body: Dictionary, rejections: Array) -> Array:
	var holds: Array = []
	var intervals: Array = []
	for iv: Dictionary in an.intervals:
		if iv.usable:
			intervals.append(iv)
		else:
			rejections.append({"code": "grip_interval_unusable", "detail": "%s: %s" % [iv.id, ", ".join(iv.reasons)]})
	if intervals.is_empty():
		rejections.append({"code": "no_graspable_region", "detail": "no usable declared grip interval"})
		return holds
	var lead := _lead_hand(body)
	if lead == "":
		rejections.append({"code": "no_hands", "detail": "body has no grasping hand"})
		return holds
	var mass: float = an.mass
	var com: Vector3 = an.com
	var counts := {"torque_one": 0, "mass_one": 0, "span": 0, "torque_two": 0, "mass_two": 0}
	for iv: Dictionary in intervals:
		for sample: Dictionary in _interval_samples(iv):
			var point: Vector3 = sample.point
			var torque := mass * GRAVITY * point.distance_to(com)
			if mass > float(body.one_hand_mass):
				counts.mass_one += 1
				continue
			if torque > float(body.one_hand_torque):
				counts.torque_one += 1
				continue
			var axis: Vector3 = iv.axis
			if (com - point).dot(axis) < 0.0 or ((com - point).length() < 0.05 and _reach_along(an, point, -axis) > _reach_along(an, point, axis)):
				axis = -axis
			var grips := {lead: point}
			var ivs := {lead: iv}
			holds.append({"id": "1h:%s@%.2f" % [iv.id, sample.t], "hands": [lead], "grips": grips, "tangents": {lead: iv.axis},
				"intervals": ivs, "center": point, "axis": axis, "span": 0.0, "spread": false, "torque": snappedf(torque, 0.01),
				"probes": an.probes, "slide_room": slide_room(grips, ivs, axis)})
	if "hand_r" in body.hands and "hand_l" in body.hands:
		for front_iv: Dictionary in intervals:
			for back_iv: Dictionary in intervals:
				for fs: Dictionary in _interval_samples(front_iv):
					for bs: Dictionary in _interval_samples(back_iv):
						if front_iv.id == back_iv.id and fs.t <= bs.t:
							continue
						var front: Vector3 = fs.point
						var back: Vector3 = bs.point
						var span := front.distance_to(back)
						if span < float(body.min_grip_span):
							continue
						if span > float(body.max_grip_span):
							counts.span += 1
							continue
						var center := (front + back) * 0.5
						var torque := mass * GRAVITY * maxf(0.0, center.distance_to(com) - span * 0.5)
						if mass > float(body.two_hand_mass):
							counts.mass_two += 1
							continue
						if torque > float(body.two_hand_torque):
							counts.torque_two += 1
							continue
						var axis := (front - back).normalized()
						var grips := {"hand_r": front, "hand_l": back}
						var ivs := {"hand_r": front_iv, "hand_l": back_iv}
						holds.append({"id": "2h:%s@%.2f>%s@%.2f" % [back_iv.id, bs.t, front_iv.id, fs.t], "hands": ["hand_r", "hand_l"],
							"grips": grips, "tangents": {"hand_r": front_iv.axis, "hand_l": back_iv.axis}, "intervals": ivs,
							"center": center, "axis": axis, "span": snappedf(span, 0.001), "spread": span >= SPREAD_MIN,
							"torque": snappedf(torque, 0.01), "probes": an.probes, "slide_room": slide_room(grips, ivs, axis)})
	elif intervals.size() > 1 or (intervals[0].lo as Vector3).distance_to(intervals[0].hi) > 0.1:
		rejections.append({"code": "two_hand_requires_missing_hand", "detail": "body lacks a second grasping hand (%s)" % ", ".join(body.modifications)})
	var names := {"torque_one": "static_torque_exceeds_one_hand", "mass_one": "mass_exceeds_one_hand", "span": "grip_span_exceeds_anatomy",
		"torque_two": "static_torque_exceeds_two_hands", "mass_two": "mass_exceeds_two_hands"}
	for code: String in counts:
		if counts[code] > 0:
			rejections.append({"code": names[code], "detail": "%d placements" % counts[code]})
	return holds

static func _reach_along(an: Dictionary, origin: Vector3, dir: Vector3) -> float:
	var best := -INF
	for p: Vector3 in an.points:
		best = maxf(best, (p - origin).dot(dir))
	return best

# --- Physics -----------------------------------------------------------------------

static func _inertia_cap(hold: Dictionary, body: Dictionary) -> float:
	return float(body.two_hand_inertia if hold.hands.size() == 2 else body.one_hand_inertia)

static func _mass_cap(hold: Dictionary, body: Dictionary) -> float:
	return float(body.two_hand_mass if hold.hands.size() == 2 else body.one_hand_mass)

static func _physics(hold: Dictionary, an: Dictionary, body: Dictionary) -> Dictionary:
	var c: Vector3 = hold.center
	var axis: Vector3 = hold.axis
	var inertia := 0.0
	for s: Array in an.samples:
		inertia += float(s[1]) * (s[0] as Vector3).distance_squared_to(c)
	var swing_load := inertia / _inertia_cap(hold, body)
	var push_load := float(an.mass) / _mass_cap(hold, body)
	var off: Vector3 = (an.com as Vector3) - c
	var lateral := (off - axis * off.dot(axis)).length()
	var roll := float(an.mass) * GRAVITY * lateral
	var roll_cap := float(body.two_hand_roll if hold.hands.size() == 2 else body.one_hand_roll)
	var far := _reach_along(an, c, axis)
	var near := -_reach_along(an, c, -axis)
	var head := clampf(off.dot(axis) / maxf(far, 0.1), 0.0, 1.0)
	return {"inertia": snappedf(inertia, 0.0001), "swing_load": snappedf(swing_load, 0.0001), "push_load": snappedf(push_load, 0.0001),
		"roll": snappedf(roll, 0.001), "roll_cap": roll_cap, "far": far, "near": near, "head": snappedf(head, 0.0001),
		"heft": snappedf(clampf(maxf(swing_load, push_load), 0.0, 1.0), 0.0001)}

# --- Candidates --------------------------------------------------------------------

static func _rel(f: Dictionary, hold: Dictionary) -> Dictionary:
	var r: Vector3 = (f.pos as Vector3) - (hold.center as Vector3)
	var axis: Vector3 = hold.axis
	var along := r.dot(axis)
	var lateral := r - axis * along
	return {"r": r, "d": r.length(), "along": along, "lateral": lateral.length(), "lateral_vec": lateral}

## The side of a shaft end or point strikes in a swing: a short capsule along the part.
static func _side_contact(f: Dictionary) -> Dictionary:
	var g := f.duplicate()
	var n: Vector3 = f.normal
	g.id = str(f.id) + "_side"
	g.kind = "side"
	g.pos = (f.pos as Vector3) - n * 0.06
	g.half_extent = n * 0.06
	g.radius = maxf(float(f.radius), 0.03)
	g.channel = "blunt"
	g.sharpness = 0.0
	return g

static func _candidates(hold: Dictionary, phys: Dictionary, an: Dictionary, body: Dictionary) -> Dictionary:
	var c: Vector3 = hold.center
	var axis: Vector3 = hold.axis
	var out: Array = []
	var why := {}
	var two: bool = hold.hands.size() == 2
	var swing_ok: bool = phys.swing_load <= 1.0 and phys.roll <= phys.roll_cap
	var swing_why := "" if swing_ok else ("inertia_exceeds_%s" % ("two_hands" if two else "one_hand") if phys.swing_load > 1.0 else
		"roll_torque_exceeds_wrists (%.1f > %.1f N·m)" % [phys.roll, phys.roll_cap])
	var lead_along := 0.0
	var rear_along := 0.0
	if two:
		lead_along = ((hold.grips.hand_r as Vector3) - c).dot(axis)
		rear_along = ((hold.grips.hand_l as Vector3) - c).dot(axis)
	var back_room: float = (hold.slide_room as Vector2).x
	var rear_features: Array = []
	for f: Dictionary in an.features:
		var g := _rel(f, hold)
		if g.d < 0.05:
			continue
		var a: Vector3 = (g.r as Vector3) / g.d
		var facing: float = (f.normal as Vector3).dot(axis)
		var soft: bool = f.get("soft", false)
		# Thrust / lunge: the leading point of the object along the hold axis.
		if not soft and f.kind in ["point", "end", "mass", "edge"] and g.along >= 0.25 and g.lateral <= 0.1 + float(f.radius) \
				and (f.omni or facing >= 0.7):
			var blocker := _thrust_blocker(f, g, hold, an)
			if blocker != "":
				why.thrust = blocker
			elif two and ((f.pos as Vector3) - (hold.grips.hand_r as Vector3)).dot(axis) <= 0.0:
				why.thrust = "feature_behind_lead_hand"
			elif phys.push_load > 1.0:
				why.thrust = "mass_exceeds_thrust_control"
			else:
				out.append(_action("thrust", f, a, hold, phys, an, body, false))
				out.append(_action("lunge", f, a, hold, phys, an, body, true))
		elif not why.has("thrust"):
			why.thrust = "no_forward_leading_point"
		# Swings: a rigid surface at the far end.
		if not soft and g.along >= 0.3 and g.d >= 0.6 * float(phys.far) and (f.kind in ["end", "point", "mass"] or absf(facing) <= 0.5):
			if not swing_ok:
				why.sweep = swing_why
			else:
				var lead_f: Dictionary = _side_contact(f) if f.kind in ["end", "point"] else f
				for arche: String in SWINGS:
					for heavy: bool in [false, true]:
						out.append(_action(arche, lead_f, a, hold, phys, an, body, heavy))
		elif not why.has("sweep"):
			why.sweep = "no_rigid_surface_at_far_end"
		# Bash: a broad face presented along the hold axis.
		if f.kind == "face" and facing >= 0.7 and g.along >= 0.25 and float(f.area) >= LabAnalysis.BLOCK_AREA:
			var disc := f.duplicate()
			disc.radius = clampf(sqrt(float(f.area) / PI) * 0.75, 0.08, 0.35)
			for heavy: bool in [false, true]:
				out.append(_action("bash", disc, a, hold, phys, an, body, heavy))
		# Rear-end candidates: beyond the rear hand.
		# (Only the short end: an object held backwards is not a rear strike.)
		if two and not soft and f.kind in ["end", "point", "mass", "edge"] and g.along <= rear_along - REAR_CLEARANCE + back_room \
				and -float(g.along) <= float(phys.far):
			rear_features.append(f)
	if not out.any(func(x: Dictionary) -> bool: return x.archetype == "bash"):
		why.bash = "no_broad_face_along_hold_axis"
	# Rear strike (and, for light long spread holds, the two-ended windmill).
	if rear_features.is_empty():
		why.rear = "no_strikable_feature_beyond_rear_hand" if two else "requires_two_hands"
	elif not swing_ok:
		why.rear = swing_why
	else:
		var rf: Dictionary = rear_features[0]
		for f: Dictionary in rear_features:
			if ((f.pos as Vector3) - c).dot(axis) < ((rf.pos as Vector3) - c).dot(axis):
				rf = f
		var rear_contact: Dictionary = _side_contact(rf) if rf.kind in ["end", "point"] else rf
		var a_rear: Vector3 = ((rf.pos as Vector3) - c).normalized()
		for heavy: bool in [false, true]:
			var act := _action("rear", rear_contact, a_rear, hold, phys, an, body, heavy)
			out.append(act)
		# Windmill: both ends strike in one rotation.
		var leads: Array = out.filter(func(x: Dictionary) -> bool: return x.archetype == "sweep" and not x.heavy)
		if hold.spread and phys.swing_load <= WINDMILL_LOAD and not leads.is_empty():
			var lead_act: Dictionary = leads[0]
			var mill := _action("windmill", lead_act.feature, lead_act.a_local, hold, phys, an, body, true)
			mill.rear_feature = rear_contact
			out.append(mill)
		elif not hold.spread:
			why.windmill = "requires_spread_two_hand_hold"
		else:
			why.windmill = "inertia_too_high_for_windmill (%.2f > %.2f)" % [phys.swing_load, WINDMILL_LOAD]
	# Hook: a one-sided rigid transverse protrusion near the far end.
	var hook := _hook_feature(hold, phys, an)
	if hook.is_empty():
		why.hook = "no_one_sided_transverse_protrusion"
	elif not swing_ok:
		why.hook = swing_why
	else:
		var a_hook: Vector3 = ((hook.pos as Vector3) - c).normalized()
		for heavy: bool in [false, true]:
			out.append(_action("hook", hook, a_hook, hold, phys, an, body, heavy))
	# Shove: the shaft between spread hands.
	if hold.spread:
		var lead_p: Vector3 = hold.grips.hand_r
		var rear_p: Vector3 = hold.grips.hand_l
		var shaft := {"id": "hold_shaft", "part": "hold", "kind": "shaft", "pos": c, "normal": Vector3.ZERO, "radius": 0.04,
			"half_extent": (lead_p - rear_p) * 0.4, "sharpness": 0.0, "hardness": 0.4, "area": 0.0, "omni": true, "channel": "blunt",
			"soft": false}
		if phys.push_load <= 1.0:
			out.append(_action("shove", shaft, axis, hold, phys, an, body, false))
			out.append(_action("shove", shaft, axis, hold, phys, an, body, true))
	else:
		why.shove = "requires_spread_two_hand_hold"
	return {"actions": out, "why": why, "head": phys.head}

## A thrust is blocked when another part sits laterally wider than the feature yet
## less than 6 cm behind it (an umbrella's canopy behind its crown nub).
static func _thrust_blocker(f: Dictionary, g: Dictionary, hold: Dictionary, an: Dictionary) -> String:
	var c: Vector3 = hold.center
	var axis: Vector3 = hold.axis
	var line: Vector3 = (f.pos as Vector3) - axis * float(g.along)
	var h: Vector3 = f.get("half_extent", Vector3.ZERO)
	var h_len := h.length()
	for p: Vector3 in an.points:
		var along := (p - c).dot(axis)
		var off := (p - line) - axis * (p - line).dot(axis)
		if h_len > 0.001:
			# Lateral distance from the feature's own segment (an edge's full width).
			var along_h := clampf(off.dot(h / h_len), -h_len, h_len)
			off -= h / h_len * along_h
		var lateral := off.length()
		if lateral > float(f.radius) + 0.03 and along > float(g.along) - 0.06:
			return "thrust_blocked_by_broad_part_behind_tip"
	return ""

## Hook protrusion from the imported parts: rigid points away from the hold line near
## the far end, all on one side of it (a branch, not a symmetric canopy or blade).
static func _hook_feature(hold: Dictionary, phys: Dictionary, an: Dictionary) -> Dictionary:
	if an.get("source", "v0") != "lab":
		return {}
	var c: Vector3 = hold.center
	var axis: Vector3 = hold.axis
	var grip_parts := {}
	for hand: String in hold.intervals:
		grip_parts[hold.intervals[hand].part] = true
	var pts: Array = []
	var mean_dir := Vector3.ZERO
	for p: Dictionary in an.parts:
		if not p.rigid or grip_parts.has(p.id):
			continue
		for q: Vector3 in LabAnalysis._surface_points(p):
			var r := q - c
			var along := r.dot(axis)
			var lat := r - axis * along
			if along >= 0.5 * float(phys.far) and lat.length() >= 0.06:
				pts.append([q, lat, along])
				mean_dir += lat.normalized()
	if pts.size() < 2:
		return {}
	mean_dir = mean_dir.normalized() if mean_dir.length() > 0.001 else Vector3.ZERO
	if mean_dir == Vector3.ZERO:
		return {}
	var max_lat := 0.0
	var along_sum := 0.0
	for e: Array in pts:
		if (e[1] as Vector3).normalized().dot(mean_dir) < 0.5:
			return {}
		max_lat = maxf(max_lat, (e[1] as Vector3).length())
		along_sum += float(e[2])
	var along_mean := along_sum / pts.size()
	var crook := c + axis * along_mean + mean_dir * max_lat * 0.5
	return {"id": "hook_crook", "part": "protrusion", "kind": "hook", "pos": crook, "normal": -axis, "radius": 0.06,
		"half_extent": mean_dir * max_lat * 0.4, "sharpness": 0.0, "hardness": 0.7, "area": 0.0, "omni": false,
		"channel": "blunt", "soft": false, "hook_dir": mean_dir}

## A perpendicular reference for the object's roll: the feature's own leading normal
## for swings, the hook direction for hooks, else a cover normal or any perpendicular.
static func _roll_reference(arche: String, f: Dictionary, a: Vector3, an: Dictionary) -> Vector3:
	var candidates: Array = []
	if arche == "hook" and f.has("hook_dir"):
		candidates.append(f.hook_dir)
	if arche in SWINGS or arche in ["rear", "windmill"]:
		if f.kind in ["edge", "face"]:
			candidates.append(f.normal)
	for cover: Dictionary in an.covers:
		candidates.append(cover.normal)
	candidates.append(Vector3.BACK)
	candidates.append(Vector3.RIGHT)
	for n: Vector3 in candidates:
		var p := n - a * n.dot(a)
		if p.length() > 0.2:
			return p.normalized()
	return Vector3.UP

## Air drag of broad surfaces moving face-first: presented area along the travel.
static func _drag(arche: String, a: Vector3, n_local: Vector3, an: Dictionary) -> float:
	var travel := a if arche in ["bash", "thrust", "lunge", "shove"] else n_local
	var area := 0.0
	for cover: Dictionary in an.covers:
		area += float(cover.area) * absf((cover.normal as Vector3).dot(travel))
	return clampf(area * 1.2, 0.0, 0.7)

static func _action(arche: String, f: Dictionary, a: Vector3, hold: Dictionary, phys: Dictionary, an: Dictionary, body: Dictionary,
		heavy: bool) -> Dictionary:
	var spec := Motion.archetype(arche)
	var timing: Array = spec.timing
	var load := maxf(float(phys.swing_load) if arche in SWINGS or arche in ["rear", "windmill", "hook"] else float(phys.push_load), float(phys.push_load))
	var k := 0.85 + 0.75 * clampf(load, 0.0, 1.0)
	var n_local := _roll_reference(arche, f, a, an)
	var drag := _drag(arche, a, n_local, an)
	var hm: Array = [1.0, 1.0, 1.0] if arche in ["lunge", "windmill"] or not heavy else HEAVY_TIMING
	var windup: float = float(timing[0]) * k * float(hm[0]) * (1.0 + 0.5 * drag)
	var active: float = float(timing[1]) * (0.9 + 0.25 * load) * float(hm[1]) * (1.0 + drag)
	var recovery: float = float(timing[2]) * k * float(hm[2])
	var channel: String = f.channel
	var mass: float = an.mass
	var inertia: float = phys.inertia
	var d := ((f.pos as Vector3) - (hold.center as Vector3)).length()
	var damage := 0.0
	var posture := 0.0
	var soft: bool = f.get("soft", false)
	if arche == "shove" or (arche == "bash" and soft):
		posture = (16.0 if arche == "shove" else 22.0) * (0.8 + 0.3 * sqrt(mass)) * (1.4 if heavy else 1.0)
		if soft:
			# The rigid ribs behind a compliant canopy still land a little blunt force.
			damage = BASE_DAMAGE.blunt * 0.3 * (0.55 + 0.2 * sqrt(minf(mass, 6.0))) * (1.75 if heavy else 1.0)
	else:
		var impact: float
		if arche in ["thrust", "lunge", "bash"]:
			impact = 0.55 + 0.2 * sqrt(minf(mass, 6.0))
		else:
			var effective := clampf(inertia / maxf(d * d, 0.04), 0.2, 8.0)
			# Mass concentrated toward the striking end carries the swing's momentum.
			impact = (0.6 + 0.3 * sqrt(effective)) * clampf(0.75 + 0.3 * d, 0.8, 1.25) * (1.0 + 0.5 * float(phys.head) * float(phys.heft))
		var edge := 0.55 + 0.9 * float(f.sharpness) if channel != "blunt" else 1.0
		var hard := 0.5 + 0.5 * float(f.hardness)
		damage = float(BASE_DAMAGE[channel]) * impact * edge * hard * (1.75 if heavy else 1.0)
		if arche in ["thrust", "lunge"] and channel != "pierce":
			# A blunt end or edge spreads a straight poke over its whole face.
			damage *= 0.7
		posture = damage * float(POSTURE_RATIO[channel])
		if f.kind == "face":
			damage *= 0.75
			posture *= 1.4
		if arche == "hook":
			damage *= 0.4
			posture += 12.0
		if arche == "windmill":
			damage *= 0.8
	var head: float = phys.head
	var heft: float = phys.heft
	var sharp := float(f.sharpness) if channel == "pierce" else 0.0
	# Off-axis mass twists a thrust out of line but adds to a chop (wrist roll load).
	var offset := clampf(float(phys.roll) / maxf(float(phys.roll_cap), 0.001), 0.0, 1.0)
	var fitness: float = {
		"thrust": (1.0 + 0.9 * sharp) * (1.15 - 0.6 * head * heft) * (1.0 - 0.8 * offset) * (1.0 if sharp > 0.0 else 0.75),
		"lunge": (1.0 + 0.9 * sharp) * (1.1 - 0.5 * head * heft) * (1.0 - 0.8 * offset),
		"sweep": 1.0 + 0.3 * head, "backhand": 0.95 + 0.25 * head, "overhead": 0.8 + 1.4 * head * heft + 1.2 * offset,
		"rising": 0.8 + 0.2 * head, "rear": 1.05, "bash": 0.95 + (0.65 if soft else 0.0), "hook": 1.4, "windmill": 1.4, "shove": 0.55,
	}[arche]
	var reach_factor := clampf(0.6 + 0.5 * d, 0.6, 1.4)
	var light_score := (damage + 0.35 * posture) / (windup + 0.4 * recovery + 0.2) * reach_factor * fitness
	# A committed heavy is judged on guard-breaking posture as much as on damage.
	var heavy_score := (damage + 0.8 * posture) * reach_factor / (1.0 + 0.5 * windup) * fitness
	var act := {"id": "%s%s:%s" % [arche, ":heavy" if heavy else "", f.id], "archetype": arche, "heavy": heavy,
		"rear": arche == "rear", "feature": f, "channel": channel, "hold": hold, "a_local": a, "n_local": n_local,
		"windup": snappedf(windup, 0.001), "active": snappedf(active, 0.001), "recovery": snappedf(recovery, 0.001),
		"damage": snappedf(damage, 0.01), "posture": snappedf(posture, 0.01), "load": snappedf(load, 0.001), "drag": snappedf(drag, 0.001),
		"heft": heft, "head": head, "pull": (0.5 if heavy else 0.35) if arche == "hook" else 0.0,
		"entry": spec.entry, "exit": spec.exit, "fitness": snappedf(fitness, 0.001),
		"score": light_score if not heavy else heavy_score}
	if spec.get("heavy_only", false) and not heavy:
		act.score = -1.0
	# Haft: in a rotational strike the visible shaft between the striking hand and the
	# feature also sweeps through space. It is tested only when the feature itself
	# misses (point-blank), as a weaker glancing blow — the drawn geometry, not a
	# larger hitbox.
	if (arche in SWINGS or arche == "rear") and hold.hands.size() > 0:
		var hand: String = "hand_l" if arche == "rear" and hold.hands.size() == 2 else str(hold.hands[0])
		var from: Vector3 = hold.grips[hand]
		var to: Vector3 = (f.pos as Vector3) - ((f.pos as Vector3) - from).normalized() * (float(f.radius) + 0.02)
		if from.distance_to(to) > 0.15:
			var from_end := from + (to - from).normalized() * 0.08
			act.haft = {"id": "haft", "part": "haft", "kind": "haft", "pos": (from_end + to) * 0.5, "half_extent": (to - from_end) * 0.5,
				"radius": maxf(float((hold.intervals[hand] as Dictionary).radius), 0.015) + 0.01, "channel": "blunt", "normal": Vector3.ZERO}
	return act

static func _finish_action(act: Dictionary, body: Dictionary) -> void:
	act.keys = Motion.build(act, body) if not act.get("unarmed", false) else Motion.build_unarmed(act)
	act.erase("windows_abs")
	act.windows_abs = Motion.windows(act)
	if not act.get("unarmed", false):
		act.ready_key = Motion.pose_key(Motion.ready_pose(act.hold, act.ready_frame, body), act.hold)

static func _rough_score(candidates: Dictionary) -> float:
	var best_light := 0.0
	var best_heavy := 0.0
	var archetypes := {}
	for act: Dictionary in candidates.actions:
		archetypes[act.archetype] = true
		if act.heavy:
			best_heavy = maxf(best_heavy, act.score)
		elif act.windup <= LIGHT_WINDUP_MAX:
			best_light = maxf(best_light, act.score)
	return best_light + best_heavy * 0.5 + archetypes.size() * 4.0 + 6.0 * float(candidates.get("head", 0.0))

# --- Validation, combo graph, input mapping ----------------------------------------

## Flow between strikes: the next one starts where the previous one ended.
static func flow(exit_tag: String, entry_tag: String) -> float:
	if exit_tag == entry_tag:
		return 1.0
	if exit_tag == "center" or entry_tag == "center":
		return 0.4
	return 0.0

static func _map_inputs(hold: Dictionary, phys: Dictionary, candidates: Dictionary, an: Dictionary, body: Dictionary) -> Dictionary:
	var rejections: Array = []
	var actions: Array = candidates.actions.duplicate()
	actions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score or (x.score == y.score and x.id < y.id))
	var frame := {"a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true, "kind": "end"}, hold.axis, an)}
	for act: Dictionary in actions:
		if not act.heavy and act.windup <= LIGHT_WINDUP_MAX:
			frame = {"a_local": act.a_local, "n_local": act.n_local}
			break
	var validated := {}
	var valid := func(act: Dictionary) -> bool:
		if not validated.has(act.id):
			act.ready_frame = frame
			_finish_action(act, body)
			var check := Motion.validate(act, body)
			act.reach = snappedf(check.reach, 0.001)
			act.reach_root = snappedf(check.reach_root, 0.001)
			act.reach_windows = check.reach_windows
			act.root_contact = snappedf(Motion.root_at(act.keys, float(act.windows_abs[0].t0 + act.windows_abs[0].t1) * 0.5), 0.001)
			act.contact_band = [snappedf(check.contact_low, 0.001), snappedf(check.contact_high, 0.001)]
			validated[act.id] = check
			if not check.ok:
				rejections.append({"code": "object_passes_through_body" if check.penetration > Motion.PENETRATION_LIMIT else "grip_unreachable_in_motion",
					"detail": "%s (penetration %.3f m, reach excess %.3f m)" % [act.id, check.penetration, check.reach_excess]})
		return validated[act.id].ok
	# Light candidates: best variant per (archetype, feature), validated.
	var lights: Array = []
	for act: Dictionary in actions:
		if act.heavy or act.windup > LIGHT_WINDUP_MAX or act.score < 0.0:
			continue
		if lights.size() >= 10:
			break
		if valid.call(act):
			lights.append(act)
	var light := _best_chain(lights)
	# The heavy contrasts with the light chain: an archetype family the chain already
	# repeats ranks lower (a thrust chain finishes with a chop if the object has one).
	var families := {}
	for act: Dictionary in light:
		families[_family(act.archetype)] = int(families.get(_family(act.archetype), 0)) + 1
	var heavy_pool: Array = []
	for act: Dictionary in actions:
		if act.heavy:
			var ranked := act.duplicate()
			ranked.rank = float(act.score) * (0.8 if int(families.get(_family(act.archetype), 0)) >= 2 else 1.0) \
				* (1.35 if act.archetype in SPECIAL else 1.0)
			heavy_pool.append([ranked.rank, act])
	heavy_pool.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[1].id < y[1].id))
	var heavies: Array = []
	for entry: Array in heavy_pool:
		if heavies.size() < 6 and valid.call(entry[1]):
			heavies.append(entry[1])
	var heavy: Variant = heavies[0] if not heavies.is_empty() else null
	var heavy_after: Array = []
	for step: Dictionary in light:
		var best_follow: Variant = heavy
		for h: Dictionary in heavies:
			if flow(step.exit, h.entry) >= 1.0 and float(h.score) >= 0.6 * float(heavy.score):
				best_follow = h
				break
		heavy_after.append(best_follow)
	if light.is_empty():
		rejections.append({"code": "no_light_action", "detail": _why(candidates.why)})
	if heavy == null:
		rejections.append({"code": "no_heavy_action", "detail": _why(candidates.why)})
	for arche: String in candidates.why:
		if not candidates.actions.any(func(act: Dictionary) -> bool: return act.archetype == arche):
			rejections.append({"code": "%s_rejected" % arche, "detail": candidates.why[arche]})
	var guard: Variant = _guard(hold, an, body, float(phys.swing_load))
	var score := 0.0
	var kinds := {}
	for act: Dictionary in light:
		score += float(act.score) / light.size()
		kinds[act.archetype] = true
	if heavy != null:
		score += float(heavy.score) * 0.5
	if guard != null:
		score += float(guard.score) * 8.0
	score += kinds.size() * 4.0
	# Prefer holds that put the mass toward the striking end (not the object backwards).
	score += 6.0 * float(phys.head)
	return {"hold": hold, "light": light, "heavy": heavy, "heavy_after": heavy_after, "guard": guard, "ready_frame": frame,
		"rejections": rejections, "score": score, "physics": phys}

## Light chain as a walk on the combo graph: open with the strike that starts best
## from the ready pose, then repeatedly take the strike that continues best from where
## the previous one ended (flow), discounting immediate repeats. 3 strikes, 4 when the
## object is fast. Special-structure strikes (a canopy bash, a hook, the second end)
## get a small preference so the object's structure shows.
static func _best_chain(lights: Array) -> Array:
	if lights.is_empty():
		return []
	if lights.size() == 1:
		return [lights[0], lights[0], lights[0]]
	var fast := true
	for act: Dictionary in lights.slice(0, 4):
		fast = fast and float(act.windup) <= 0.22
	var length := 4 if fast else 3
	var top: float = 0.001
	for act: Dictionary in lights:
		top = maxf(top, float(act.score))
	var chain: Array = []
	var exit_tag := "center"
	for i in range(length):
		var best: Dictionary = {}
		var best_value := -INF
		for act: Dictionary in lights:
			var value := float(act.score) / top * _flow_factor(flow(exit_tag, act.entry)) * (1.15 if act.archetype in SPECIAL else 1.0)
			if not chain.is_empty():
				var prev: Dictionary = chain[chain.size() - 1]
				if prev.archetype == act.archetype:
					var twice: bool = chain.size() >= 2 and (chain[chain.size() - 2] as Dictionary).archetype == act.archetype
					value *= 0.3 if twice else (0.5 if prev.feature.id == act.feature.id else 0.55)
				elif prev.feature.id != act.feature.id and prev.feature.get("part", "") == act.feature.get("part", ""):
					# A return swing leads with the other edge of the same part.
					value *= 1.05
			if value > best_value + 1e-9 or (absf(value - best_value) <= 1e-9 and str(act.id) < str(best.get("id", "~"))):
				best_value = value
				best = act
		chain.append(best)
		exit_tag = best.exit
	return chain

static func _flow_factor(f: float) -> float:
	return 1.0 if f >= 1.0 else (0.75 if f > 0.0 else 0.5)

static func _family(arche: String) -> String:
	return "thrust" if arche in ["thrust", "lunge"] else ("swing" if arche in ["sweep", "backhand"] else arche)

static func _why(why: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in why:
		parts.append("%s: %s" % [k, why[k]])
	return "; ".join(parts)

# --- Unarmed -------------------------------------------------------------------------

static func _unarmed(body: Dictionary) -> Dictionary:
	var hold := {"id": "unarmed", "unarmed": true, "hands": [], "grips": {}, "tangents": {}, "intervals": {}, "center": Vector3.ZERO,
		"axis": Vector3.FORWARD, "span": 0.0, "spread": false, "torque": 0.0, "probes": [], "slide_room": Vector2.ZERO}
	var fist := {"id": "fist", "part": "body", "kind": "fist", "pos": Vector3.ZERO, "normal": Vector3.FORWARD, "radius": 0.06,
		"half_extent": Vector3.ZERO, "sharpness": 0.0, "hardness": 0.3, "area": 0.0, "omni": true, "channel": "blunt", "soft": false}
	var shoulder_f := fist.duplicate()
	shoulder_f.id = "shoulder"
	shoulder_f.radius = 0.13
	var light: Array = []
	var specs := []
	if "hand_l" in body.hands:
		specs.append(["jab", fist, 4.5, 4.0])
	if "hand_r" in body.hands:
		specs.append(["cross", fist, 6.0, 6.0])
	for s: Array in specs:
		light.append(_unarmed_action(s[0], s[1], s[2], s[3], hold, body, false))
	var heavy := _unarmed_action("barge", shoulder_f, 3.0, 24.0, hold, body, true)
	var chain: Array = []
	if light.size() == 2:
		chain = [light[0], light[1], light[0]]
	elif light.size() == 1:
		chain = [light[0], light[0], light[0]]
	var guard: Variant = null
	if not body.hands.is_empty():
		guard = {"kind": "forearm_guard", "part": "body", "hold": hold, "arc": 0.7, "absorb": 0.25, "deflect": 0.08, "cover_radius": 0.0,
			"score": 0.0}
	return {"hold": hold, "light": chain, "heavy": heavy, "heavy_after": chain.map(func(_x: Variant) -> Variant: return heavy),
		"guard": guard, "ready_frame": {"a_local": Vector3.FORWARD, "n_local": Vector3.UP}, "rejections": [], "score": 0.0,
		"physics": {"inertia": 0.0, "swing_load": 0.0, "push_load": 0.0, "heft": 0.0, "head": 0.0, "roll": 0.0}}

static func _unarmed_action(arche: String, f: Dictionary, damage: float, posture: float, hold: Dictionary, body: Dictionary, heavy: bool) -> Dictionary:
	var spec := Motion.archetype(arche)
	var act := {"id": "%s:%s" % [arche, f.id], "archetype": arche, "heavy": heavy, "rear": false, "unarmed": true, "feature": f,
		"channel": "blunt", "hold": hold, "a_local": Vector3.FORWARD, "n_local": Vector3.UP,
		"windup": spec.timing[0], "active": spec.timing[1], "recovery": spec.timing[2], "damage": damage, "posture": posture,
		"load": 0.0, "drag": 0.0, "heft": 0.0, "head": 0.0, "pull": 0.0, "entry": spec.entry, "exit": spec.exit, "fitness": 1.0, "score": damage,
		"ready_frame": {"a_local": Vector3.FORWARD, "n_local": Vector3.UP}}
	_finish_action(act, body)
	var check := Motion.validate(act, body)
	act.reach = snappedf(check.reach, 0.001)
	act.reach_root = snappedf(check.reach_root, 0.001)
	act.root_contact = snappedf(Motion.root_at(act.keys, float(act.windows_abs[0].t0 + act.windows_abs[0].t1) * 0.5), 0.001)
	act.contact_band = [snappedf(check.contact_low, 0.001), snappedf(check.contact_high, 0.001)]
	return act

# --- Guard ---------------------------------------------------------------------------

## Guard: a broad cover (plate or canopy), or the object's shaft. Coverage, absorption
## and the deflect window follow the guarding surface's size and hardness.
static func _guard(hold: Dictionary, an: Dictionary, body: Dictionary, load: float) -> Variant:
	var c: Vector3 = hold.center
	var options: Array = []
	for cover: Dictionary in an.covers:
		var a: Vector3 = ((cover.center as Vector3) - c)
		if a.length() < 0.08 or a.normalized().dot(hold.axis) < 0.2:
			continue
		a = a.normalized()
		var hardness: float = cover.hardness
		var faces_axis := absf((cover.normal as Vector3).dot(a)) >= 0.7
		if cover.get("deploy", false) or faces_axis:
			# A canopy (or deployed membrane) whose face points along the shaft: aimed at the attacker.
			options.append({"kind": "deploy_cover" if cover.get("deploy", false) else "canopy_cover", "part": cover.part, "a_local": a,
				"n_local": _roll_reference("thrust", {"omni": true, "kind": "end"}, a, an),
				"c": Vector3(0.2, 1.12, -0.3), "d": Vector3(0.05, 0.3, -1.0), "r": Vector3.UP, "yaw": 0.1,
				"arc": clampf(0.5 + atan(float(cover.radius) / 0.3), 0.3, 1.4), "absorb": 0.3 + 0.6 * hardness, "deflect": 0.05 + 0.15 * hardness,
				"cover_radius": cover.radius})
		else:
			var n: Vector3 = cover.normal
			options.append({"kind": "surface_cover", "part": cover.part, "a_local": a, "n_local": n,
				"c": Vector3(0.18, 1.08, -0.34), "d": Vector3(-0.15, 0.8, -0.35), "r": Vector3.FORWARD, "yaw": 0.1,
				"arc": clampf(0.35 + 4.0 * float(cover.area), 0.5, 1.1), "absorb": 0.45 + 0.45 * hardness, "deflect": 0.08 + 0.1 * hardness,
				"cover_radius": 0.0})
	var shaft_hardness := 0.4
	if hold.hands.size() == 2:
		options.append({"kind": "cross_guard", "part": "hold", "a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true, "kind": "end"}, hold.axis, an),
			"c": Vector3(0.02, 1.28, -0.38), "d": Vector3(0.95, 0.35, -0.05), "r": Vector3.FORWARD, "yaw": 0.0,
			"arc": 0.95, "absorb": 0.55 + 0.4 * shaft_hardness, "deflect": 0.14, "cover_radius": 0.0})
	else:
		options.append({"kind": "upright_guard", "part": "hold", "a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true, "kind": "end"}, hold.axis, an),
			"c": Vector3(0.2, 1.16, -0.34), "d": Vector3(-0.35, 0.9, -0.3), "r": Vector3.FORWARD, "yaw": 0.1,
			"arc": 0.75, "absorb": 0.45 + 0.4 * shaft_hardness, "deflect": 0.15, "cover_radius": 0.0})
	var best: Variant = null
	for g: Dictionary in options:
		g.hold = hold
		g.deflect = snappedf(float(g.deflect) * clampf(1.2 - 0.6 * load, 0.4, 1.0), 0.001)
		g.absorb = snappedf(minf(float(g.absorb), 0.9), 0.001)
		g.arc = snappedf(float(g.arc), 0.001)
		g.score = float(g.arc) + float(g.absorb) + 2.0 * float(g.deflect)
		var pose := Motion.guard_pose(g, body)
		if pose.reach_excess > Motion.REACH_LIMIT or pose.penetration > Motion.PENETRATION_LIMIT:
			continue
		if best == null or g.score > best.score:
			best = g
	return best
