extends RefCounted
## Derives the lab's handling numbers from a resolved weapon view (`resolved.equipment.
## weapons[]`). The weapon is a rigid rod held at its grip, swung about a fixed
## shoulder pivot at the end of a fixed-length arm. Pure and deterministic.
##
##   r_com   = arm_reach + balance * length         (pivot → centre of mass, m)
##   inertia = mass * (r_com² + length² / 12) + arm_inertia     (kg·m²)
##   accel   = torque / inertia,  torque ×two_handed_torque_scale for two grips
##   speed   = min(accel · t, max_angular_speed)    (hand speed cap is the same for all)
## Heavier or tip-heavy weapons therefore accelerate, redirect, brake and shift guard
## more slowly, but carry more angular momentum (I·ω) into contact.

static func derive(weapon: Dictionary, t: Dictionary) -> Dictionary:
	var handling: Dictionary = weapon.handling
	var length := float(handling.length)
	var mass := float(handling.mass)
	var balance := float(handling.balance)
	var two_handed: bool = weapon.get("grip", "") == "two_handed"
	var r_com: float = t.arm_reach + balance * length
	var inertia: float = mass * (r_com * r_com + length * length / 12.0) + t.arm_inertia
	var torque: float = t.torque_one_handed * (t.two_handed_torque_scale if two_handed else 1.0)
	var accel := torque / inertia
	var inertia_ratio: float = t.guard_ref_inertia / inertia
	return {
		"item": str(weapon.get("item", "")),
		"class": str(weapon.get("class", "")),
		"two_handed": two_handed,
		"length": length,
		"mass": mass,
		"balance": balance,
		"inertia": inertia,
		"accel": accel,
		"max_speed": float(t.max_angular_speed),
		"brake": accel * t.brake_ratio,
		"reach": t.arm_reach + length,
		"thrust_accel": t.thrust_force * (t.two_handed_torque_scale if two_handed else 1.0) / (mass + t.arm_mass),
		"thrust_mass": mass + t.arm_mass,
		"guard_strength": pow(mass / t.guard_strength_ref_mass, t.guard_strength_mass_exponent) * (t.two_handed_guard_scale if two_handed else 1.0),
		"guard_shift": t.guard_shift_rate * sqrt(inertia_ratio),
		"turn_rate": deg_to_rad(t.attack_turn_rate_deg) * clampf(sqrt(inertia_ratio), 0.5, 1.25),
		"can_guard": bool(weapon.defense.guard),
		"can_deflect": bool(weapon.defense.deflect),
	}

## Seconds to rotate `angle` radians from rest under constant acceleration, speed-capped.
static func time_from_rest(angle: float, accel: float, max_speed: float) -> float:
	var to_cap := max_speed / accel
	var cap_angle := 0.5 * accel * to_cap * to_cap
	if angle <= cap_angle:
		return sqrt(2.0 * angle / accel)
	return to_cap + (angle - cap_angle) / max_speed

## Seconds for a rest-to-rest move (accelerate, then brake) of `angle` radians.
static func rest_to_rest(angle: float, accel: float, max_speed: float) -> float:
	return 2.0 * time_from_rest(angle * 0.5, accel, max_speed)
