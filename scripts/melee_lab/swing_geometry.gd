extends RefCounted
## Directions, arcs and weapon poses in a fighter's local frame (forward -Z, right +X,
## up +Y). Pure and deterministic; rules and presentation both read these poses, so
## the drawn weapon is the hit segment.
##
## Attack directions are named for the swing's travel. The aim cursor marks where the
## blade is *chambered*: cursor right chambers on the right and cuts right-to-left.
## A swing is a great-circle arc b(θ) = cos θ·F + sin θ·D, where D is the chamber
## direction in the frontal plane: θ = start (behind the chamber side) → 0 (straight
## ahead) → end (across the body). A thrust keeps the blade on F and extends the hand.

const FORWARD := Vector3(0.0, 0.0, -1.0)
const RIGHT := Vector3(1.0, 0.0, 0.0)
const UP := Vector3(0.0, 1.0, 0.0)
const THRUST := "thrust"
## Chamber angle in the frontal plane (degrees from the fighter's right, counter-clockwise).
const SWINGS := {"right_to_left": 0.0, "diag_right": 45.0, "overhead": 90.0, "diag_left": 135.0, "left_to_right": 180.0}
const DIRECTIONS := ["right_to_left", "diag_right", "overhead", "diag_left", "left_to_right", "thrust"]
## The natural follow-up: the blade ends on the side the next cut starts from.
const FOLLOW_UP := {"": "right_to_left", "right_to_left": "left_to_right", "left_to_right": "right_to_left",
	"diag_right": "diag_left", "diag_left": "diag_right", "overhead": "right_to_left", "thrust": "right_to_left"}
## Guard sectors share the cursor layout: the cursor points at the side to cover.
const GUARDS := {"right": 0.0, "high_right": 45.0, "high": 90.0, "high_left": 135.0, "left": 180.0}
const CENTER_GUARD := "center"

## Cursor (x right, y up, |c| ≤ 1) → sector angle, or "" inside the deadzone.
## Down (−135°..−45°) is the thrust / centre sector; lower sides fold onto horizontal.
static func _sector(cursor: Vector2, deadzone: float) -> float:
	if cursor.length() < deadzone:
		return NAN
	var angle := rad_to_deg(atan2(cursor.y, cursor.x))
	if angle < -45.0 and angle > -135.0:
		return -90.0
	if angle < 0.0:
		angle = 0.0 if angle >= -45.0 else 180.0
	return snappedf(angle, 45.0)

static func classify_attack(cursor: Vector2, deadzone: float) -> String:
	var sector := _sector(cursor, deadzone)
	if is_nan(sector):
		return ""
	if sector == -90.0:
		return THRUST
	for name: String in SWINGS:
		if is_equal_approx(SWINGS[name], sector):
			return name
	return ""

static func classify_guard(cursor: Vector2, deadzone: float) -> String:
	var sector := _sector(cursor, deadzone)
	if is_nan(sector):
		return ""
	if sector == -90.0:
		return CENTER_GUARD
	for name: String in GUARDS:
		if is_equal_approx(GUARDS[name], sector):
			return name
	return ""

## Unit cursor-space vector of a guard sector (centre points down).
static func guard_vector(guard: String) -> Vector2:
	if guard == CENTER_GUARD:
		return Vector2(0.0, -1.0)
	var angle := deg_to_rad(float(GUARDS.get(guard, 90.0)))
	return Vector2(cos(angle), sin(angle))

## Chamber direction of a swing in cursor space; thrust is centre.
static func chamber_vector(direction: String) -> Vector2:
	if direction == THRUST:
		return Vector2(0.0, -1.0)
	var angle := deg_to_rad(float(SWINGS.get(direction, 0.0)))
	return Vector2(cos(angle), sin(angle))

static func frontal(v: Vector2) -> Vector3:
	return RIGHT * v.x + UP * v.y

static func family(direction: String) -> String:
	if direction == THRUST:
		return "thrust"
	if direction == "overhead":
		return "overhead"
	return "diagonal" if direction.begins_with("diag") else "horizontal"

static func pivot(t: Dictionary) -> Vector3:
	return UP * t.pivot_height

static func swing_dir(direction: String, theta: float) -> Vector3:
	return (FORWARD * cos(theta) + frontal(chamber_vector(direction)) * sin(theta)).normalized()

static func swing_start(t: Dictionary) -> float:
	return deg_to_rad(t.swing_start_deg)

static func swing_live(t: Dictionary) -> float:
	return deg_to_rad(t.swing_live_deg)

## Horizontal cuts sweep across the body; downward cuts stop before the ground.
static func swing_end(direction: String, t: Dictionary) -> float:
	var rise := maxf(0.0, chamber_vector(direction).y)
	return deg_to_rad(lerpf(t.swing_end_horizontal_deg, t.swing_end_overhead_deg, rise))

## A pose is {hand, dir} in local space; the weapon runs hand → hand + dir·length.
static func swing_pose(direction: String, theta: float, t: Dictionary) -> Dictionary:
	var dir := swing_dir(direction, theta)
	return {"hand": pivot(t) + dir * t.arm_reach, "dir": dir}

static func thrust_pose(extension: float, t: Dictionary) -> Dictionary:
	return {"hand": pivot(t) + FORWARD * (0.25 + extension) + RIGHT * 0.08, "dir": FORWARD}

static func chamber_pose(direction: String, t: Dictionary) -> Dictionary:
	if direction == THRUST:
		return thrust_pose(0.0, t)
	return swing_pose(direction, swing_start(t), t)

static func rest_pose(t: Dictionary) -> Dictionary:
	return {"hand": pivot(t) + FORWARD * 0.35 + RIGHT * 0.22 - UP * 0.2, "dir": (FORWARD * 0.8 + UP * 0.6).normalized()}

## The weapon is held across the covered side: hand pushed toward the sector and
## forward, blade perpendicular to the sector (pointing upward), hand shifted back
## along the blade so the covered span is centred on that side.
static func guard_pose(guard: String, t: Dictionary) -> Dictionary:
	if guard == CENTER_GUARD:
		return {"hand": pivot(t) + FORWARD * 0.5 - UP * 0.25, "dir": (UP * 0.9 + FORWARD * 0.3).normalized()}
	var g := guard_vector(guard)
	var p := Vector2(-g.y, g.x)
	if p.y < -0.001 or (absf(p.y) <= 0.001 and p.x > 0.0):
		p = -p
	var dir := (frontal(p) * 0.95 + FORWARD * 0.2).normalized()
	var hand := pivot(t) + FORWARD * 0.45 + frontal(g) * 0.5 - dir * 0.45
	return {"hand": hand, "dir": dir}

static func tip(pose: Dictionary, length: float) -> Vector3:
	return pose.hand + pose.dir * length
