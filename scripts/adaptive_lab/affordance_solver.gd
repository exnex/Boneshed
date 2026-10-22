extends RefCounted
## Object + body → capability set. The only inputs are the measured analysis of the
## object's structure (object_analysis.gd) and the body descriptor (body_plans.gd).
## The descriptor's label is never read here; tests swap it and compare outputs.
##
## Steps:
##   1. holds: one-hand and two-hand placements on measured grip candidates, legal for
##      the body's existing hands, grip span, carried mass and static torque;
##   2. actions per hold: each authored archetype is granted only when a measured
##      contact feature satisfies its geometric requirement (a thrust needs a feature
##      that is the object's furthest point along the hold axis and faces forward; a
##      swing needs a feature whose surface can lead the swing; alternating ends need
##      strikable features beyond both hands of a spread hold; …) and the body can
##      control the inertia;
##   3. timing, damage and posture from mass, inertia, sharpness and hardness;
##   4. motion validation (motion_library.gd): every chosen action is sampled and
##      rejected when a grip leaves the arm's reach or the object passes through the
##      wielder's body;
##   5. input mapping: light chain, heavy and guard for the best-scoring hold.
## Everything rejected is reported with a reason code, so missing moves are explained.

const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const SCHEMA := "boneshed.adaptive_capabilities.v0"
const GRAVITY := 9.81
const LIGHT_WINDUP_MAX := 0.42
const SPREAD_MIN := 0.3
## Base damage per channel (provisional lab numbers; HP and posture are 100).
const BASE_DAMAGE := {"pierce": 13.0, "cut": 15.0, "blunt": 10.0}
const POSTURE_RATIO := {"pierce": 0.7, "cut": 0.8, "blunt": 1.3}
const HOLDS_VALIDATED := 6

static func solve(descriptor: Dictionary, body: Dictionary) -> Dictionary:
	var an := Analysis.analyse(descriptor)
	var rejections: Array = []
	var holds := _holds(an, body, rejections)
	var ranked: Array = []
	for hold: Dictionary in holds:
		var candidates := _candidates(hold, an, body)
		ranked.append({"hold": hold, "candidates": candidates, "score": _rough_score(candidates)})
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score or (x.score == y.score and x.hold.id < y.hold.id))
	var best: Dictionary = {}
	for entry: Dictionary in ranked.slice(0, HOLDS_VALIDATED):
		var mapped := _map_inputs(entry.hold, entry.candidates, an, descriptor.parts, body)
		if best.is_empty() or mapped.score > best.score:
			best = mapped
	var out := {
		"schema": SCHEMA,
		"object_fingerprint": _structure_hash(descriptor),
		"body": {"id": body.id, "modifications": body.modifications, "hands": body.hands},
		"mass": snappedf(an.mass, 0.001),
		"extent": snappedf(an.extent, 0.001),
		"grip_candidates": an.grips.size(),
		"holds_considered": holds.size(),
		"usable": not best.is_empty() and (best.light.size() > 0 or best.heavy != null or best.guard != null),
		"hold": best.get("hold", null),
		"light": best.get("light", []),
		"heavy": best.get("heavy", null),
		"guard": best.get("guard", null),
		"ready_frame": best.get("ready_frame", null),
		"rejections": rejections + best.get("rejections", []),
		"features": _feature_summary(an),
	}
	if not out.usable:
		out.rejections.append({"code": "object_unusable_for_body", "detail": "no legal hold with any action"})
	return out

## Structure-only hash, recomputed here so the solver needs nothing but structure.
static func _structure_hash(descriptor: Dictionary) -> String:
	return JSON.stringify({"parts": descriptor.parts, "recipe": descriptor.recipe, "seed": descriptor.seed,
		"generator_version": descriptor.generator_version}, "", true).sha256_text().substr(0, 16)

static func _feature_summary(an: Dictionary) -> Array:
	var out: Array = []
	for f: Dictionary in an.features:
		out.append({"id": f.id, "kind": f.kind, "channel": f.channel, "sharpness": f.sharpness})
	return out

# --- Holds -------------------------------------------------------------------------

static func _lead_hand(body: Dictionary) -> String:
	for hand: String in ["hand_r", "hand_l"]:
		if hand in body.hands:
			return hand
	return ""

static func _holds(an: Dictionary, body: Dictionary, rejections: Array) -> Array:
	var holds: Array = []
	var grips: Array = an.grips
	if grips.is_empty():
		rejections.append({"code": "no_graspable_region", "detail": "no rod of graspable diameter with hand clearance"})
		return holds
	var lead := _lead_hand(body)
	if lead == "":
		rejections.append({"code": "no_hands", "detail": "body has no grasping hand"})
		return holds
	var mass: float = an.mass
	var com: Vector3 = an.com
	var probes: Array = an.probes
	var counts := {"torque_one": 0, "mass_one": 0, "span": 0, "torque_two": 0, "mass_two": 0}
	# One hand: every candidate.
	for g: Dictionary in grips:
		var point: Vector3 = g.point
		var torque := mass * GRAVITY * point.distance_to(com)
		if mass > float(body.one_hand_mass):
			counts.mass_one += 1
			continue
		if torque > float(body.one_hand_torque):
			counts.torque_one += 1
			continue
		var axis: Vector3 = g.axis
		if (com - point).dot(axis) < 0.0 or ((com - point).length() < 0.05 and Analysis.reach_along(an, point, -axis) > Analysis.reach_along(an, point, axis)):
			axis = -axis
		holds.append({"id": "1h:%s@%.2f" % [g.part, g.s], "hands": [lead], "grips": {lead: point}, "tangents": {lead: g.axis},
			"center": point, "axis": axis, "span": 0.0, "spread": false, "torque": snappedf(torque, 0.01), "probes": probes})
	# Two hands: pairs on a coarser lattice, both orders (which hand leads).
	if "hand_r" in body.hands and "hand_l" in body.hands:
		var coarse: Array = []
		for i in range(grips.size()):
			if i % 2 == 0:
				coarse.append(grips[i])
		for i in range(coarse.size()):
			for j in range(coarse.size()):
				if i == j:
					continue
				var front: Dictionary = coarse[i]
				var back: Dictionary = coarse[j]
				var span := (front.point as Vector3).distance_to(back.point)
				if span < float(body.min_grip_span) or span > float(body.max_grip_span):
					if span > float(body.max_grip_span) and i < j:
						counts.span += 1
					continue
				var center: Vector3 = ((front.point as Vector3) + (back.point as Vector3)) * 0.5
				var torque := mass * GRAVITY * maxf(0.0, center.distance_to(com) - span * 0.5)
				if mass > float(body.two_hand_mass):
					counts.mass_two += 1
					continue
				if torque > float(body.two_hand_torque):
					counts.torque_two += 1
					continue
				var axis := ((front.point as Vector3) - (back.point as Vector3)).normalized()
				holds.append({"id": "2h:%s@%.2f>%s@%.2f" % [back.part, back.s, front.part, front.s], "hands": ["hand_r", "hand_l"],
					"grips": {"hand_r": front.point, "hand_l": back.point}, "tangents": {"hand_r": front.axis, "hand_l": back.axis},
					"center": center, "axis": axis, "span": snappedf(span, 0.001), "spread": span >= SPREAD_MIN, "torque": snappedf(torque, 0.01), "probes": probes})
	elif grips.size() > 1:
		rejections.append({"code": "two_hand_requires_missing_hand", "detail": "body lacks a second grasping hand (%s)" % ", ".join(body.modifications)})
	for code: String in counts:
		if counts[code] > 0:
			var names := {"torque_one": "static_torque_exceeds_one_hand", "mass_one": "mass_exceeds_one_hand", "span": "grip_span_exceeds_anatomy",
				"torque_two": "static_torque_exceeds_two_hands", "mass_two": "mass_exceeds_two_hands"}
			rejections.append({"code": names[code], "detail": "%d placements" % counts[code]})
	return holds

# --- Actions -----------------------------------------------------------------------

static func _inertia_cap(hold: Dictionary, body: Dictionary) -> float:
	return float(body.two_hand_inertia if hold.hands.size() == 2 else body.one_hand_inertia)

static func _mass_cap(hold: Dictionary, body: Dictionary) -> float:
	return float(body.two_hand_mass if hold.hands.size() == 2 else body.one_hand_mass)

## Every geometrically and physically feasible (archetype, feature) for one hold,
## with timing and damage. Rejected archetypes get a reason.
static func _candidates(hold: Dictionary, an: Dictionary, body: Dictionary) -> Dictionary:
	var c: Vector3 = hold.center
	var axis: Vector3 = hold.axis
	var inertia := Analysis.inertia_about(an, c)
	var swing_load := inertia / _inertia_cap(hold, body)
	var push_load := float(an.mass) / _mass_cap(hold, body)
	# Mass hanging off the handle line twists the wrists during a swing.
	var off: Vector3 = (an.com as Vector3) - c
	var lateral := (off - axis * off.dot(axis)).length()
	var roll := float(an.mass) * GRAVITY * lateral
	var roll_cap := float(body.two_hand_roll if hold.hands.size() == 2 else body.one_hand_roll)
	var out: Array = []
	var why := {}
	for f: Dictionary in an.features:
		var r: Vector3 = (f.pos as Vector3) - c
		var d := r.length()
		if d < 0.05:
			continue
		var a := r / d
		var along := axis.dot(a)
		var facing: float = (f.normal as Vector3).dot(a)
		var furthest := Analysis.reach_along(an, c, a)
		# Thrust: the feature is the leading point along the hold axis and faces forward.
		if d >= 0.25 and along >= 0.88 and (f.omni or facing >= 0.75) and furthest <= d + float(f.radius) + 0.04:
			if hold.hands.size() == 2 and ((f.pos as Vector3) - (hold.grips.hand_r as Vector3)).dot(axis) <= 0.0:
				why.thrust = "feature_behind_lead_hand"
			elif push_load > 1.0:
				why.thrust = "mass_exceeds_thrust_control"
			else:
				for heavy: bool in [false, true]:
					out.append(_action("thrust", f, a, hold, an, body, push_load, inertia, d, heavy))
		elif not why.has("thrust"):
			why.thrust = "no_forward_facing_distal_feature"
		# Swings: the feature's surface can lead a swing and sits at the far end.
		if d >= 0.3 and along >= 0.2 and (f.omni or absf(facing) <= 0.5) and d >= 0.6 * furthest:
			if swing_load > 1.0:
				why.sweep = "inertia_exceeds_%s" % ("two_hands" if hold.hands.size() == 2 else "one_hand")
				why.overhead = why.sweep
			elif roll > roll_cap:
				why.sweep = "roll_torque_exceeds_wrists (%.1f > %.1f N·m)" % [roll, roll_cap]
				why.overhead = why.sweep
			else:
				for arche: String in ["sweep", "overhead"]:
					for heavy: bool in [false, true]:
						out.append(_action(arche, f, a, hold, an, body, swing_load, inertia, d, heavy))
		elif not why.has("sweep"):
			why.sweep = "no_leading_surface_at_far_end"
			why.overhead = why.sweep
	# Alternating ends: strikable features beyond both hands of a spread hold.
	if hold.spread:
		var lead_side: Array = []
		var rear_side: Array = []
		for f: Dictionary in an.features:
			if ((f.pos as Vector3) - (hold.grips.hand_r as Vector3)).dot(axis) >= 0.25:
				lead_side.append(f)
			if ((f.pos as Vector3) - (hold.grips.hand_l as Vector3)).dot(-axis) >= 0.25:
				rear_side.append(f)
		if lead_side.is_empty() or rear_side.is_empty():
			why.alternate = "no_strikable_feature_beyond_rear_hand"
		elif swing_load > 1.0:
			why.alternate = "inertia_exceeds_two_hands"
		elif roll > roll_cap:
			why.alternate = "roll_torque_exceeds_wrists"
		else:
			var f1: Dictionary = _furthest(lead_side, c)
			var f2: Dictionary = _furthest(rear_side, c)
			var lead_action := _action("alternate", f1, ((f1.pos as Vector3) - c).normalized(), hold, an, body, swing_load, inertia,
				(f1.pos as Vector3).distance_to(c), false)
			var rear_action := _action("alternate", f2, ((f2.pos as Vector3) - c).normalized(), hold, an, body, swing_load, inertia,
				(f2.pos as Vector3).distance_to(c), false)
			rear_action.rear = true
			rear_action.id += ":rear"
			out.append(lead_action)
			out.append(rear_action)
	else:
		why.alternate = "requires_spread_two_hand_hold"
	# Shove: the shaft between spread hands, or the nearest broad surface.
	var shove := _shove(hold, an, body, push_load, inertia)
	if shove.is_empty():
		why.shove = "no_pushing_surface_near_hands"
	elif push_load > 1.0:
		why.shove = "mass_exceeds_push_control"
	else:
		out.append(shove)
	return {"actions": out, "why": why, "swing_load": swing_load, "push_load": push_load, "inertia": inertia}

static func _furthest(features: Array, c: Vector3) -> Dictionary:
	var best: Dictionary = features[0]
	for f: Dictionary in features:
		if (f.pos as Vector3).distance_to(c) > (best.pos as Vector3).distance_to(c) + 0.0001:
			best = f
	return best

static func _shove(hold: Dictionary, an: Dictionary, body: Dictionary, load: float, inertia: float) -> Dictionary:
	var c: Vector3 = hold.center
	if hold.spread:
		var lead: Vector3 = hold.grips.hand_r
		var rear: Vector3 = hold.grips.hand_l
		var shaft := {"id": "hold_shaft", "part": "hold", "kind": "shaft", "pos": c, "normal": Vector3.ZERO, "radius": 0.04,
			"half_extent": (lead - rear) * 0.4, "sharpness": 0.0, "hardness": 0.4, "area": 0.0, "omni": true, "channel": "blunt"}
		return _action("shove", shaft, hold.axis, hold, an, body, load, inertia, 0.0, false)
	var best: Dictionary = {}
	for f: Dictionary in an.features:
		if f.kind in ["face", "mass", "end"] and (f.pos as Vector3).distance_to(c) <= 0.5 and ((f.pos as Vector3) - c).dot(hold.axis) >= -0.05:
			if best.is_empty() or (f.pos as Vector3).distance_to(c) < (best.pos as Vector3).distance_to(c):
				best = f
	if best.is_empty():
		return {}
	return _action("shove", best, ((best.pos as Vector3) - c).normalized(), hold, an, body, load, inertia, (best.pos as Vector3).distance_to(c), false)

## A perpendicular reference for the object's roll: the feature's own leading normal
## for swings, otherwise the first plate/cover normal, otherwise any perpendicular.
static func _roll_reference(arche: String, f: Dictionary, a: Vector3, an: Dictionary) -> Vector3:
	var candidates: Array = []
	if arche in ["sweep", "overhead", "alternate"] and not f.omni:
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

static func _action(arche: String, f: Dictionary, a: Vector3, hold: Dictionary, an: Dictionary, body: Dictionary, load: float,
		inertia: float, d: float, heavy: bool) -> Dictionary:
	var timing: Array = Motion.ARCHETYPES[arche].timing
	# Whatever the motion, the whole mass is accelerated; rotations also pay inertia.
	var mass_load := float(an.mass) / _mass_cap(hold, body)
	load = maxf(load, mass_load)
	var k := 0.85 + 0.75 * clampf(load, 0.0, 1.0)
	var windup: float = float(timing[0]) * k * (Motion.HEAVY_TIMING[0] if heavy else 1.0)
	var active: float = float(timing[1]) * (0.9 + 0.25 * load) * (Motion.HEAVY_TIMING[1] if heavy else 1.0)
	var recovery: float = float(timing[2]) * k * (Motion.HEAVY_TIMING[2] if heavy else 1.0)
	var channel: String = f.channel
	var damage := 0.0
	var posture := 0.0
	if arche == "shove":
		posture = 16.0 * (0.8 + 0.3 * sqrt(float(an.mass)))
	else:
		var impact: float
		if arche == "thrust":
			# Straight-line drive: the body pushes the whole object.
			impact = 0.55 + 0.2 * sqrt(minf(float(an.mass), 6.0))
		else:
			# Rotational strike: mass felt at the feature, faster with a longer lever.
			var effective := clampf(inertia / maxf(d * d, 0.04), 0.2, 8.0)
			impact = (0.6 + 0.3 * sqrt(effective)) * clampf(0.75 + 0.3 * d, 0.8, 1.25)
		var edge := 0.55 + 0.9 * float(f.sharpness) if channel != "blunt" else 1.0
		var hard := 0.5 + 0.5 * float(f.hardness)
		damage = float(BASE_DAMAGE[channel]) * impact * edge * hard * (1.75 if heavy else 1.0) * (0.85 if arche == "alternate" else 1.0)
		posture = damage * float(POSTURE_RATIO[channel])
	var n_local := _roll_reference(arche, f, a, an)
	var reach_factor := clampf(0.6 + 0.5 * d, 0.6, 1.4)
	var light_score := (damage + 0.35 * posture) / (windup + 0.4 * recovery + 0.2) * reach_factor
	var heavy_score := (damage + 0.5 * posture) * reach_factor / (1.0 + 0.5 * windup) * (0.85 if arche == "thrust" else 1.0)
	return {"id": "%s%s:%s" % [arche, ":heavy" if heavy else "", f.id], "archetype": arche, "heavy": heavy, "rear": false,
		"feature": f, "channel": channel, "hold": hold, "a_local": a, "n_local": n_local,
		"windup": snappedf(windup, 0.001), "active": snappedf(active, 0.001), "recovery": snappedf(recovery, 0.001),
		"damage": snappedf(damage, 0.01), "posture": snappedf(posture, 0.01), "load": snappedf(load, 0.001),
		"score": light_score if not heavy else heavy_score}

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
	return best_light + best_heavy * 0.5 + archetypes.size() * 4.0

# --- Validation and input mapping --------------------------------------------------

static func _map_inputs(hold: Dictionary, candidates: Dictionary, an: Dictionary, parts: Array, body: Dictionary) -> Dictionary:
	var rejections: Array = []
	var actions: Array = candidates.actions.duplicate()
	actions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score or (x.score == y.score and x.id < y.id))
	var lights: Array = []
	for act: Dictionary in actions:
		if not act.heavy and act.windup <= LIGHT_WINDUP_MAX:
			lights.append(act)
	# The ready pose holds the object as the best light action starts.
	var frame := {"a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true}, hold.axis, an)}
	if not lights.is_empty():
		frame = {"a_local": lights[0].a_local, "n_local": lights[0].n_local}
	var validated := {}
	var valid := func(act: Dictionary) -> bool:
		if not validated.has(act.id):
			act.ready_frame = frame
			var check := Motion.validate(act, body)
			act.reach = snappedf(check.reach, 0.001)
			validated[act.id] = check
			if not check.ok:
				rejections.append({"code": "object_passes_through_body" if check.penetration > Motion.PENETRATION_LIMIT else "grip_unreachable_in_motion",
					"detail": "%s (penetration %.3f m, reach excess %.3f m)" % [act.id, check.penetration, check.reach_excess]})
		return validated[act.id].ok
	var light: Array = []
	var lead_alt: Dictionary = {}
	var rear_alt: Dictionary = {}
	for act: Dictionary in lights:
		if act.archetype == "alternate" and valid.call(act):
			if act.rear and rear_alt.is_empty():
				rear_alt = act
			elif not act.rear and lead_alt.is_empty():
				lead_alt = act
	if not lead_alt.is_empty() and not rear_alt.is_empty():
		light = [lead_alt, rear_alt, lead_alt]
	else:
		var first: Dictionary = {}
		var second: Dictionary = {}
		for act: Dictionary in lights:
			if act.archetype == "alternate" or not valid.call(act):
				continue
			if first.is_empty():
				first = act
			elif second.is_empty() and act.archetype != first.archetype:
				second = act
		if not first.is_empty():
			light = [first, second if not second.is_empty() else first, first]
	var heavy: Variant = null
	for act: Dictionary in actions:
		if act.heavy and valid.call(act):
			heavy = act
			break
	if light.is_empty():
		rejections.append({"code": "no_light_action", "detail": _why(candidates.why)})
	if heavy == null:
		rejections.append({"code": "no_heavy_action", "detail": _why(candidates.why)})
	for arche: String in candidates.why:
		if not candidates.actions.any(func(act: Dictionary) -> bool: return act.archetype == arche):
			rejections.append({"code": "%s_rejected" % arche, "detail": candidates.why[arche]})
	var guard: Variant = _guard(hold, an, parts, body, candidates.swing_load)
	var score := 0.0
	for act: Dictionary in light:
		score += act.score / 3.0
	if heavy != null:
		score += float(heavy.score) * 0.5
	if guard != null:
		score += float(guard.score) * 8.0
	var kinds := {}
	for act: Dictionary in light:
		kinds[act.archetype] = true
	score += kinds.size() * 4.0
	return {"hold": hold, "light": light, "heavy": heavy, "guard": guard, "ready_frame": frame, "rejections": rejections, "score": score}

static func _why(why: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in why:
		parts.append("%s: %s" % [k, why[k]])
	return "; ".join(parts)

## Guard: a deployable cover, a broad plate/lump, or the object's shaft. Coverage,
## absorption and the deflect window follow the guarding surface's size and hardness.
static func _guard(hold: Dictionary, an: Dictionary, parts: Array, body: Dictionary, load: float) -> Variant:
	var c: Vector3 = hold.center
	var options: Array = []
	for cover: Dictionary in an.covers:
		var a: Vector3 = ((cover.center as Vector3) - c)
		if a.length() < 0.08 or a.normalized().dot(hold.axis) < 0.2:
			continue
		a = a.normalized()
		var hardness: float = cover.hardness
		if cover.deploy:
			options.append({"kind": "deploy_cover", "part": cover.part, "a_local": a, "n_local": _roll_reference("thrust", {"omni": true}, a, an),
				"c": Vector3(0.2, 1.12, -0.3), "d": Vector3(0.05, 0.3, -1.0), "r": Vector3.UP, "yaw": 0.1,
				"arc": clampf(atan(float(cover.radius) / 0.45), 0.3, 1.2), "absorb": 0.3 + 0.6 * hardness, "deflect": 0.05 + 0.15 * hardness,
				"cover_radius": cover.radius})
		else:
			var n: Vector3 = cover.normal
			options.append({"kind": "surface_cover", "part": cover.part, "a_local": a, "n_local": n,
				"c": Vector3(0.18, 1.08, -0.34), "d": Vector3(-0.15, 0.8, -0.35), "r": Vector3.FORWARD, "yaw": 0.1,
				"arc": clampf(0.35 + 4.0 * float(cover.area), 0.5, 1.1), "absorb": 0.45 + 0.45 * hardness, "deflect": 0.08 + 0.1 * hardness,
				"cover_radius": 0.0})
	var shaft_hardness := 0.4
	if hold.hands.size() == 2:
		options.append({"kind": "cross_guard", "part": "hold", "a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true}, hold.axis, an),
			"c": Vector3(0.02, 1.28, -0.38), "d": Vector3(0.95, 0.35, -0.05), "r": Vector3.FORWARD, "yaw": 0.0,
			"arc": 0.95, "absorb": 0.55 + 0.4 * shaft_hardness, "deflect": 0.14, "cover_radius": 0.0})
	else:
		options.append({"kind": "upright_guard", "part": "hold", "a_local": hold.axis, "n_local": _roll_reference("thrust", {"omni": true}, hold.axis, an),
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
