extends RefCounted
## Maps authoritative rule time onto an authored clip through named markers.
## Rules own timing; the clip is only re-timed section by section so its key poses
## land exactly on rule boundaries. Pure functions: no nodes, no engine state.

## Clip markers, in clip seconds, that bound the five sections below.
const MARKERS := ["start", "loaded", "release", "contact", "active_end", "recovered"]
## Rule sections, in order. Durations come from the rule timing dictionary.
const SECTIONS := ["early", "committed", "release", "active", "recovery"]

## Rule-section durations from combat-style timing. `commitment` and `release` are the
## final portions of the windup, matching CombatState.attack_stage().
static func section_durations(timing: Dictionary) -> PackedFloat64Array:
	var windup: float = timing.windup
	var commitment: float = timing.commitment
	var release: float = timing.release
	return PackedFloat64Array([windup - commitment, commitment - release, release, float(timing.active), float(timing.recovery)])

## Empty when valid; otherwise human-readable problems.
static func validate(markers: Dictionary, timing: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for name in MARKERS:
		if not markers.has(name):
			errors.append("missing marker %s" % name)
	if not errors.is_empty():
		return errors
	for i in range(1, MARKERS.size()):
		if float(markers[MARKERS[i]]) <= float(markers[MARKERS[i - 1]]):
			errors.append("marker %s must follow %s" % [MARKERS[i], MARKERS[i - 1]])
	for key in ["windup", "commitment", "release", "active", "recovery"]:
		if not timing.has(key) or float(timing[key]) <= 0.0:
			errors.append("timing %s must be positive" % key)
	if errors.is_empty() and not (float(timing.windup) > float(timing.commitment) and float(timing.commitment) > float(timing.release)):
		errors.append("timing needs windup > commitment > release")
	return errors

static func total_duration(timing: Dictionary) -> float:
	var total := 0.0
	for d in section_durations(timing):
		total += d
	return total

## Section name and the clip time for `rule_time` seconds after the attack started.
## Past the end, holds the `recovered` marker.
static func sample(markers: Dictionary, timing: Dictionary, rule_time: float) -> Dictionary:
	var durations := section_durations(timing)
	var elapsed := maxf(rule_time, 0.0)
	for i in SECTIONS.size():
		if elapsed < durations[i] or i == SECTIONS.size() - 1:
			var progress := clampf(elapsed / durations[i], 0.0, 1.0)
			var from: float = markers[MARKERS[i]]
			var to: float = markers[MARKERS[i + 1]]
			return {"section": SECTIONS[i], "progress": progress, "clip_time": lerpf(from, to, progress)}
		elapsed -= durations[i]
	return {}

## Playback-rate multiplier per section (clip seconds per rule second). Values far
## from 1.0 mean the authored pacing does not match the rules and needs re-authoring.
static func warp_ratios(markers: Dictionary, timing: Dictionary) -> Dictionary:
	var durations := section_durations(timing)
	var ratios := {}
	for i in SECTIONS.size():
		ratios[SECTIONS[i]] = (float(markers[MARKERS[i + 1]]) - float(markers[MARKERS[i]])) / durations[i]
	return ratios

## Rule time elapsed since the attack began, rebuilt from a CombatState-style phase
## name and its `remaining` seconds. This is the only input live combat would supply.
static func rule_time_from_phase(phase: String, remaining: float, timing: Dictionary) -> float:
	match phase:
		"windup":
			return float(timing.windup) - remaining
		"active":
			return float(timing.windup) + float(timing.active) - remaining
		"recovery":
			return float(timing.windup) + float(timing.active) + float(timing.recovery) - remaining
	return 0.0

## Generic piecewise-linear map for non-attack actions (guard raise/hold/lower). Knots
## are (rule_time, clip_time) pairs with strictly increasing rule times.
static func piecewise(knots: PackedVector2Array, rule_time: float) -> float:
	if rule_time <= knots[0].x:
		return knots[0].y
	for i in range(1, knots.size()):
		if rule_time <= knots[i].x:
			return lerpf(knots[i - 1].y, knots[i].y, (rule_time - knots[i - 1].x) / (knots[i].x - knots[i - 1].x))
	return knots[knots.size() - 1].y
