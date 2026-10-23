extends RefCounted
## Corrupted-soul controller. It only produces the same intent the player's input
## produces ({move, light, heavy, guard, dodge}); the shared fighter rules decide what
## each intent can do with the soul's object and body. Decisions use one seeded
## stream, so a duel replays identically.
##
## Modes: "aggressive" (approach, light chains, occasional heavy, reactive guard),
## "defensive" (keeps distance, guards and tries to deflect more), "passive" (stands
## still: a training dummy).

const MODES := ["aggressive", "defensive", "passive"]

var rng := RandomNumberGenerator.new()
var mode := "aggressive"
var cooldown := 0.6
var chain_left := 0
var react_serial := -1
var guard_plan := ""
var guard_press_at := 0.0
var strafe := 1.0
var strafe_timer := 0.0

func _init(seed: int) -> void:
	rng.seed = seed

func intent(me: RefCounted, foe: RefCounted, dt: float) -> Dictionary:
	var out := {"move": Vector3.ZERO, "light": false, "heavy": false, "guard": false, "dodge": false}
	if mode == "passive" or me.state == "dead" or foe.state == "dead":
		return out
	cooldown -= dt
	strafe_timer -= dt
	if strafe_timer <= 0.0:
		strafe = -strafe if rng.randf() < 0.5 else strafe
		strafe_timer = rng.randf_range(1.0, 2.2)
	var to: Vector3 = foe.position - me.position
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var reach: float = me.light_reach()
	# React to a telegraphed attack the soul can see coming.
	if foe.state == "attack" and foe.pose.get("phase", "") == "windup" and dist < float(foe.light_reach()) + 0.8:
		if react_serial != foe.attack_serial:
			react_serial = foe.attack_serial
			var guard_p := 0.75 if mode == "defensive" else 0.45
			var roll := rng.randf()
			if roll < guard_p and me.caps.get("guard") != null:
				guard_plan = "deflect" if rng.randf() < 0.45 else "block"
				# Aim the fresh press just before the active window to deflect.
				guard_press_at = float(foe.action.windup) - 0.07
			elif roll < guard_p + 0.15:
				guard_plan = "dodge"
			else:
				guard_plan = ""
	elif foe.state != "attack":
		guard_plan = ""
	if guard_plan == "block" or (guard_plan == "deflect" and foe.state == "attack" and float(foe.state_time) >= guard_press_at):
		out.guard = true
		return out
	if guard_plan == "dodge" and foe.state == "attack" and foe.pose.get("phase", "") == "windup":
		out.dodge = true
		out.move = -dir + dir.cross(Vector3.UP) * strafe
		guard_plan = ""
		return out
	if guard_plan == "deflect":
		return out
	# Offense.
	var desired := reach * (1.2 if mode == "defensive" else 0.85)
	if me.state == "attack":
		if chain_left > 0 and float(me.state_time) > float(me.action.windup):
			out.light = true
			chain_left -= 1
		return out
	if me.state != "idle":
		return out
	if dist > desired + 0.15:
		out.move = dir + dir.cross(Vector3.UP) * strafe * 0.3
	elif dist < desired - 0.6:
		out.move = -dir * 0.6
	else:
		out.move = dir.cross(Vector3.UP) * strafe * 0.4
	if dist <= reach * 0.95 and cooldown <= 0.0:
		var heavy_p := 0.15 if mode == "defensive" else 0.3
		var heavy: Variant = me.caps.get("heavy")
		# A heavy is chosen only when its own reach (plus footwork) covers the gap —
		# Lab 1 chose heavies at light reach, and short heavies whiffed.
		var heavy_reach: float = float(heavy.get("reach", 0.0)) + maxf(0.0, float(heavy.get("root_contact", 0.0))) + 0.3 if heavy != null else 0.0
		if heavy != null and dist <= heavy_reach and rng.randf() < heavy_p:
			out.heavy = true
			chain_left = 0
		else:
			out.light = true
			chain_left = rng.randi_range(0, 2) if mode == "aggressive" else 0
		cooldown = rng.randf_range(0.7, 1.5) if mode == "aggressive" else rng.randf_range(1.4, 2.4)
	return out
