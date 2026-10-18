extends RefCounted
## Curated geometry contracts. Timings, damage and lunge dimensions come from the
## shared catalog. Sword dimensions stay fixed until its pose is authored for more.
const ENVIRONMENT_LAYER := 1
const FIGHTER_LAYER := 2
const SWORD_REACH := 2.35
const SWORD_WIDTH := 1.6
const MODULES := {"light": "module.slash_basic", "heavy": "module.slash_heavy", "special": "module.marrow_lunge"}
const SIGNATURE_KEYS := ["active", "guard_posture", "health_damage", "posture_damage", "reach", "recovery", "width", "windup"]

static func shape_supported(binding: String, reach: float, width: float) -> bool:
	if binding == "special":
		# Bounds of the curated extending-bone pose; tuning within them needs no code.
		return reach >= 2.4 and reach <= 4.0 and width >= 0.4 and width <= 1.2
	return reach == SWORD_REACH and width == SWORD_WIDTH

static func signature_errors(value: Variant) -> Array:
	if not value is Dictionary:
		return [{"code": "invalid_signature"}]
	var keys: Array = value.keys()
	keys.sort()
	if keys != SIGNATURE_KEYS:
		return [{"code": "invalid_signature_fields"}]
	for key: String in SIGNATURE_KEYS:
		var number: Variant = value[key]
		if not (number is int or number is float) or not is_finite(number) or number < 0.0:
			return [{"code": "invalid_signature_value", "field": key}]
	if value.windup <= 0.24 or value.active <= 0.0 or value.recovery <= 0.0:
		return [{"code": "unsupported_signature_timing"}]
	if not shape_supported("special", value.reach, value.width):
		return [{"code": "unsupported_signature_shape"}]
	return []
