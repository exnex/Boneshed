extends RefCounted
## Turns a resolved build's `equipment` view into what the placeholder body shows:
## which hand holds the weapon and which limbs a body modification replaced.
## Presentation reads only this; it never infers anatomy from abilities or combat
## state, so the visible body cannot disagree with the equipped build.

const Rules = preload("res://scripts/combat/combat_state.gd")
const SIDES := {"right": 1.0, "left": -1.0}
## Curated placeholder visuals per body-modification item. A body modification
## without an entry keeps the natural limb mesh (and fails the agreement test).
const BODY_MOD_VISUALS := {"item.marrow_arm": "marrow"}

## {"weapon_side", "replaced", "marrow_side"}: weapon_side is +1 right / -1 left;
## replaced maps "left"/"right" to the replacing item ("" = natural limb);
## marrow_side is the Marrow Arm's side, or 0 when absent.
static func describe(equipment: Dictionary) -> Dictionary:
	var look := {"weapon_side": 1.0, "replaced": {"left": "", "right": ""}, "marrow_side": 0.0}
	for part: Dictionary in equipment.get("body", []):
		if part.item != "" and SIDES.has(part.side):
			look.replaced[part.side] = part.item
			if BODY_MOD_VISUALS.get(part.item, "") == "marrow":
				look.marrow_side = SIDES[part.side]
	for weapon: Dictionary in equipment.get("weapons", []):
		if not weapon.natural and SIDES.has(weapon.side):
			look.weapon_side = SIDES[weapon.side]
			break
	return look

## Empty when every resolved fact is visible on the fighter: weapon in the resolved
## hand, replaced limbs hidden with their curated visual attached on the same side,
## natural limbs shown. Used by tests and rendered QA.
static func disagreements(actor: Fighter) -> Array:
	var problems := []
	var look := describe(actor.equipment)
	var shoulder_side := signf(actor.sword_arm.position.x) if actor.sword_arm.visible else 0.0
	var weapon_hand := signf(actor.sword_pivot.position.x)
	# Rest, guard and recoil poses keep the grip on its own side of the body centre.
	if actor.combat.phase in [Rules.Phase.IDLE, Rules.Phase.STAGGER] and weapon_hand != look.weapon_side:
		problems.append({"code": "weapon_hand_side", "expected": look.weapon_side, "actual": weapon_hand})
	if shoulder_side != look.weapon_side:
		problems.append({"code": "weapon_arm_side", "expected": look.weapon_side, "actual": shoulder_side})
	var off_side: String = "left" if look.weapon_side > 0.0 else "right"
	var off_replaced: bool = look.replaced[off_side] != ""
	if actor.free_arm.visible == off_replaced:
		problems.append({"code": "off_arm_visibility", "replaced": off_replaced, "visible": actor.free_arm.visible})
	for side: String in look.replaced:
		var item: String = look.replaced[side]
		if item != "" and not BODY_MOD_VISUALS.has(item):
			problems.append({"code": "body_mod_without_visual", "item": item})
	if actor.marrow_pivot.visible != (look.marrow_side != 0.0):
		problems.append({"code": "marrow_visibility", "expected": look.marrow_side != 0.0})
	elif actor.marrow_pivot.visible and signf(actor.marrow_pivot.position.x) != look.marrow_side:
		problems.append({"code": "marrow_side", "expected": look.marrow_side, "actual": signf(actor.marrow_pivot.position.x)})
	return problems
