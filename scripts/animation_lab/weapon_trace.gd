extends RefCounted
## Blade-versus-capsule contact tests for research. Pure math, deterministic, no physics
## server. A blade is the segment base→tip; a target is a capsule (segment + radius).
## Not wired into combat: the courtyard keeps its own rule-owned hit volumes.

## Closest distance between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9).
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()

static func blade_touches(base: Vector3, tip: Vector3, capsule_a: Vector3, capsule_b: Vector3, radius: float) -> bool:
	return segment_distance(base, tip, capsule_a, capsule_b) <= radius

## Sweeps the blade between two sampled poses. Interpolates `substeps` intermediate blade
## segments plus the two edge paths (base and tip), so a fast arc cannot skip a thin target.
## Linear interpolation approximates the arc; the chord error is bounded by substeps.
static func sweep_touches(prev_base: Vector3, prev_tip: Vector3, base: Vector3, tip: Vector3,
		capsule_a: Vector3, capsule_b: Vector3, radius: float, substeps: int) -> bool:
	if segment_distance(prev_tip, tip, capsule_a, capsule_b) <= radius or segment_distance(prev_base, base, capsule_a, capsule_b) <= radius:
		return true
	for i in range(substeps + 1):
		var w := float(i) / float(substeps)
		if blade_touches(prev_base.lerp(base, w), prev_tip.lerp(tip, w), capsule_a, capsule_b, radius):
			return true
	return false

## Number of substeps so consecutive interpolated tip positions are at most `spacing` apart.
static func substeps_for(prev_tip: Vector3, tip: Vector3, spacing: float) -> int:
	return maxi(1, ceili(prev_tip.distance_to(tip) / maxf(spacing, 1e-4)))

## First sample index whose (swept or point) test touches the capsule, or -1.
## `samples` is an Array of {"t", "base", "tip", "live"}; only samples with live == true count,
## which is how rule-owned timing gates contact regardless of the visual pose.
static func first_contact(samples: Array, capsule_a: Vector3, capsule_b: Vector3, radius: float, swept: bool, spacing := 0.05) -> int:
	for i in samples.size():
		var sample: Dictionary = samples[i]
		if not sample.live:
			continue
		if not swept or i == 0:
			if blade_touches(sample.base, sample.tip, capsule_a, capsule_b, radius):
				return i
			continue
		var previous: Dictionary = samples[i - 1]
		var steps := substeps_for(previous.tip, sample.tip, spacing)
		if sweep_touches(previous.base, previous.tip, sample.base, sample.tip, capsule_a, capsule_b, radius, steps):
			return i
	return -1

## JSON-ready copy of samples (character-local metres, rule seconds) for a baked trace.
static func to_data(samples: Array) -> Array:
	var rows := []
	for sample in samples:
		rows.append({"t": snappedf(sample.t, 0.0001), "live": sample.live,
			"base": [snappedf(sample.base.x, 0.0001), snappedf(sample.base.y, 0.0001), snappedf(sample.base.z, 0.0001)],
			"tip": [snappedf(sample.tip.x, 0.0001), snappedf(sample.tip.y, 0.0001), snappedf(sample.tip.z, 0.0001)]})
	return rows
