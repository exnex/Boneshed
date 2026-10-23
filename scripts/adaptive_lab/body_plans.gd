extends RefCounted
## Body descriptors for the Adaptive Combat Lab: proportions (the showcase rig's
## presets), which hands exist after body modifications, and provisional strength
## limits. The affordance solver and motion read only this dictionary, so a body
## modification changes grips and moves by changing data, never by a special case.

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const DATA_PATH := "res://data/adaptive_lab/bodies.json"
const SCHEMA := "boneshed.adaptive_body.v0"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		assert(parsed is Dictionary, "Adaptive lab body data failed to parse")
		_data = parsed
	return _data

## body id ("pilgrim" / "corrupted") + modification ids → body descriptor. A
## modification's combat effects are data (`modifiers`), read by the shared rules for
## either fighter; it removes a hand only when its anatomy has none.
static func build(body_id: String, modifications: Array = []) -> Dictionary:
	var base: Dictionary = data().bodies[body_id]
	var proportions: Dictionary = Rig.CORRUPTED if base.proportions == "corrupted" else Rig.PILGRIM
	var hands: Array = (base.hands as Array).duplicate()
	var replaced: Array = []
	var mods: Array = []
	var modifiers := {}
	var visuals: Array = []
	for mod_id: String in modifications:
		var mod: Dictionary = data().modifications[mod_id]
		mods.append(mod_id)
		if str(mod.replaces) != "":
			replaced.append(mod.replaces)
		visuals.append(mod.visual)
		# Anatomy decides grips: only a limb that really lacks a hand removes it.
		for hand: String in mod.removes_hands:
			hands.erase(hand)
		for key: String in mod.modifiers:
			var value := float(mod.modifiers[key])
			if key.ends_with("_mult"):
				modifiers[key] = float(modifiers.get(key, 1.0)) * value
			elif key.ends_with("_delay_s"):
				modifiers[key] = maxf(float(modifiers.get(key, 0.0)), value)
			else:
				modifiers[key] = float(modifiers.get(key, 0.0)) + value
	var j := Rig.joints(proportions)
	var arm := Rig.bone_length(proportions, "upperarm_r") + Rig.bone_length(proportions, "lowerarm_r")
	return {
		"schema": SCHEMA,
		"id": body_id,
		"modifications": mods,
		"replaced_parts": replaced,
		"modifiers": modifiers,
		"visuals": visuals,
		"proportions": proportions,
		"hands": hands,
		"arm_length": arm,
		"shoulder_r": j.upperarm_r,
		"shoulder_l": j.upperarm_l,
		"shoulder_height": (j.upperarm_r as Vector3).y,
		"pelvis_height": (j.pelvis as Vector3).y,
		"stature": (j.head_top as Vector3).y,
		# Two hands on one object can be at most this far apart (provisional: arms
		# reaching forward from both shoulders, elbows slightly bent).
		"max_grip_span": snappedf(arm * 1.45, 0.001),
		"min_grip_span": 0.085,
		"one_hand_inertia": float(base.one_hand_inertia),
		"two_hand_inertia": float(base.two_hand_inertia),
		"one_hand_torque": float(base.one_hand_torque),
		"two_hand_torque": float(base.two_hand_torque),
		"one_hand_mass": float(base.one_hand_mass),
		"two_hand_mass": float(base.two_hand_mass),
		# Wrist roll: torque the hands can resist when the mass sits off the handle line.
		"one_hand_roll": float(base.one_hand_roll),
		"two_hand_roll": float(base.two_hand_roll),
	}

static func has_hand(body: Dictionary, hand: String) -> bool:
	return hand in body.hands
