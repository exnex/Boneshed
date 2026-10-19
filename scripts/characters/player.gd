extends "res://scripts/characters/fighter.gd"

@export var mouse_sensitivity := 0.003
@export_group("Camera Zoom (provisional)")
## Arm lengths in metres, measured from the existing shoulder pivot. 3.25 keeps
## the player in frame across the current pitch range; 6.0 preserves default framing.
@export var camera_distance := 6.0
@export var camera_min_distance := 3.25
@export var camera_max_distance := 7.5
@export var camera_zoom_step := 0.65 # Metres per wheel step (scaled by event.factor).
@export var camera_zoom_speed := 12.0 # Exponential response in s^-1; ~95% in 0.25 s.
@export_group("")
@export var shoulder_offset := 1.2 # Provisional duel framing; leaves both weapons visible.
## Player-owned session preference. Collision only changes spring.get_hit_length();
## neither encounter reset nor combat/equipment state replacement clears zoom.
var preferred_camera_distance := 6.0
var yaw := 0.0
var pitch := -0.32
var locked := false
var camera_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var input_enabled := true
var manual_orbit_time := 0.0

func _ready() -> void:
	is_player = true
	body_color = Color("527f75")
	super._ready()
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(shoulder_offset, 1.6, 0.0)
	add_child(camera_pivot)
	spring = SpringArm3D.new()
	preferred_camera_distance = clampf(camera_distance, camera_min_distance, camera_max_distance)
	spring.spring_length = preferred_camera_distance
	spring.margin = 0.25
	spring.collision_mask = AttackModules.ENVIRONMENT_LAYER
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.2
	spring.shape = camera_shape
	camera_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.08
	camera.current = true
	spring.add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		var zoom_direction := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_direction = -1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_direction = 1.0
		if zoom_direction != 0.0:
			preferred_camera_distance = clampf(preferred_camera_distance + zoom_direction * camera_zoom_step * event.factor, camera_min_distance, camera_max_distance)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative)
	if event.is_action_pressed("lock_on"):
		locked = not locked
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("attack"):
		if event is InputEventMouseButton:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func rotate_camera(relative: Vector2) -> void:
	yaw -= relative.x * mouse_sensitivity
	pitch = clampf(pitch - relative.y * mouse_sensitivity, -0.75, -0.12 if locked else 0.15)
	manual_orbit_time = 0.7

func _physics_process(delta: float) -> void:
	# Smooth the requested arm length, never the collision-constrained hit length.
	# The existing swept sphere can retract immediately to keep walls out of view.
	spring.spring_length = lerpf(spring.spring_length, preferred_camera_distance, 1.0 - exp(-camera_zoom_speed * delta))
	manual_orbit_time = maxf(0.0, manual_orbit_time - delta)
	if locked:
		pitch = move_toward(pitch, minf(pitch, -0.12), delta * 0.7)
	if input_enabled:
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		desired_move = Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, yaw)
		if locked and is_instance_valid(opponent) and opponent.combat.phase != Rules.Phase.DEAD:
			var toward := opponent.global_position - global_position
			toward.y = 0.0
			turn_toward(toward, delta)
			if manual_orbit_time <= 0.0:
				# Frame the actual target, independently of attack steering. A small
				# oblique view separates silhouettes without orbiting on contact.
				var target_yaw := atan2(-toward.x, -toward.z) + 0.12
				var turn := angle_difference(yaw, target_yaw) * (1.0 - exp(-5.0 * delta))
				yaw += clampf(turn, -2.6 * delta, 2.6 * delta)
		elif desired_move.length_squared() > 0.01 and combat.phase in [Rules.Phase.IDLE, Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			turn_toward(desired_move, delta)
		combat.set_guard(Input.is_action_pressed("guard"))
		if Input.is_action_just_pressed("signature"):
			combat.attack_special()
		if Input.is_action_just_pressed("heavy_attack"):
			combat.attack(true)
		if Input.is_action_just_pressed("attack"):
			combat.attack()
		if Input.is_action_just_pressed("dodge"):
			try_dodge(desired_move)
	camera_pivot.rotation = Vector3(pitch, yaw, 0.0)
	# Check the shoulder anchor too: the arm alone cannot detect a wall that
	# separates the player from an anchor already on its far side.
	var anchor := global_position + Vector3.UP * 1.8
	var offset := Vector3(shoulder_offset, 0.0, 0.0).rotated(Vector3.UP, yaw)
	var query := PhysicsRayQueryParameters3D.create(anchor, anchor + offset, AttackModules.ENVIRONMENT_LAYER)
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		offset = obstruction.position + obstruction.normal * 0.25 - anchor
	camera_pivot.position = Vector3.UP * 1.8 + offset
	super._physics_process(delta)

func reset_at(point: Vector3, guard_held := false) -> void:
	super.reset_at(point, Input.is_action_pressed("guard"))
	# Keep preferred zoom and its interpolation through all session encounters.
	yaw = 0.0
	pitch = -0.32
	manual_orbit_time = 0.0
	locked = false
	facing = Vector3.FORWARD
