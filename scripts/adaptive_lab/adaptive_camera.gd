extends Node3D
## Third-person orbit camera for the Adaptive Combat Lab. Same proven structure as the
## production player camera (scripts/characters/player.gd): a pivot at the shoulder,
## a SpringArm3D with a swept sphere for wall/pillar collision, mouse orbit, smoothed
## wheel zoom that never smooths the collision-shortened length, and optional lock-on
## with a short manual override. Nothing here is shared with or changes that camera.
##
## Unlocked, the camera never turns by itself: movement is relative to its yaw and the
## fighter faces where it moves. Locked, the camera frames the target unless the mouse
## moved within MANUAL_OVERRIDE seconds.

const MOUSE_SENSITIVITY := 0.0028
const MIN_DISTANCE := 2.2
const MAX_DISTANCE := 7.0
const ZOOM_STEP := 0.55
const ZOOM_SPEED := 12.0
const MANUAL_OVERRIDE := 0.8
const LOCK_TURN := 5.0
const PITCH_MIN := -1.05
const PITCH_MAX := 0.35
const SHOULDER := Vector3(0.45, 1.65, 0.0)

var yaw := 0.0
var pitch := -0.3
var preferred_distance := 4.2
var locked := false
var manual_time := 0.0
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D

func _ready() -> void:
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.name = "Spring"
	spring.spring_length = preferred_distance
	spring.margin = 0.2
	spring.collision_mask = 1
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	spring.shape = shape
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.06
	camera.current = true
	spring.add_child(camera)

## Mouse motion (only while captured) orbits; the wheel zooms. Returns true if used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit((event as InputEventMouseMotion).relative)
		return true
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var dir := 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = -1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = 1.0
		if dir != 0.0:
			zoom(dir * maxf(mb.factor, 1.0))
			return true
	return false

func orbit(relative: Vector2) -> void:
	yaw -= relative.x * MOUSE_SENSITIVITY
	pitch = clampf(pitch - relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	manual_time = MANUAL_OVERRIDE

func zoom(steps: float) -> void:
	preferred_distance = clampf(preferred_distance + steps * ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)

func toggle_lock() -> void:
	locked = not locked
	manual_time = 0.0

## Per frame. `focus` is the player's position; `target` the opponent's.
func update(delta: float, focus: Vector3, target: Vector3, target_alive: bool) -> void:
	if locked and not target_alive:
		locked = false
	manual_time = maxf(0.0, manual_time - delta)
	if locked and manual_time <= 0.0:
		var to := target - focus
		to.y = 0.0
		if to.length() > 0.3:
			var desired := atan2(-to.x, -to.z) + 0.15
			yaw += clampf(angle_difference(yaw, desired) * (1.0 - exp(-LOCK_TURN * delta)), -3.0 * delta, 3.0 * delta)
			# Keep both fighters in view: look slightly down toward the target.
			pitch = move_toward(pitch, clampf(pitch, -0.55, -0.12), delta * 0.8)
	spring.spring_length = lerpf(spring.spring_length, preferred_distance, 1.0 - exp(-ZOOM_SPEED * delta)) if delta > 0.0 else preferred_distance
	position = focus
	pivot.position = Basis(Vector3.UP, yaw) * SHOULDER
	pivot.rotation = Vector3(pitch, yaw, 0.0)

## Camera-relative movement basis (horizontal).
func move_basis() -> Basis:
	return Basis(Vector3.UP, yaw)

func reset(facing_yaw: float) -> void:
	yaw = facing_yaw
	pitch = -0.3
	manual_time = 0.0
