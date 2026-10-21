extends "res://scripts/melee_lab/lab_visual.gd"
## Lab presentation (reads rules state only) plus the Marrow Arm: a bone-coloured
## left arm when the build equips it, and during the lunge the drawn weapon *is* the
## bone thrust segment the contact solver tests (its length is the swapped handling).

const BONE := Color("e6dcc0")

var bone_material: StandardMaterial3D
var lunging := false

func rebuild() -> void:
	super.rebuild()
	if arms.size() < 2:
		return
	if bone_material == null:
		bone_material = _material(BONE, true)
	arms[1].material_override = bone_material if actor.get("marrow_arm") else body_material

func sync(delta: float) -> void:
	var state = actor.state
	var now: bool = state.get("signature_active") == true
	if now != lunging:
		lunging = now
		rebuild()
	super.sync(delta)
	if not lunging:
		return
	# The bone limb, not the sword hand, drives the thrust.
	var grip: Vector3 = state.hand
	var start := Vector3(-0.3, 1.42, 0.0)
	arms[1].position = (start + grip) * 0.5
	arms[1].scale = Vector3(0.15, maxf(0.05, start.distance_to(grip)), 0.15)
	arms[1].quaternion = Quaternion(Vector3.UP, (grip - start).normalized())
	var glow := BONE.lerp(Color("ff4a2e"), 0.6) if state.is_live() else BONE
	blade_material.albedo_color = glow
	blade_material.emission = glow
	if label.text == DIRECTION_TEXT.thrust:
		label.text = "● MARROW LUNGE"
