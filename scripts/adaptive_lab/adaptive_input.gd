extends RefCounted
## The Adaptive Combat Lab's input map. Actions are prefixed `alab_` and added at
## runtime only when absent, so project.godot and every other scene's input are
## untouched. Proposed traditional action-game layout (subject to owner feel test).

const KEYS := {
	"alab_move_forward": [KEY_W], "alab_move_back": [KEY_S], "alab_move_left": [KEY_A], "alab_move_right": [KEY_D],
	"alab_light": [KEY_J], "alab_heavy": [KEY_F, KEY_K], "alab_guard": [KEY_L], "alab_dodge": [KEY_SPACE],
	"alab_lock": [KEY_Q, KEY_TAB],
}
const MOUSE := {"alab_light": MOUSE_BUTTON_LEFT, "alab_guard": MOUSE_BUTTON_RIGHT, "alab_heavy": MOUSE_BUTTON_MIDDLE}
## Unlocked attacks turn toward an opponent this close and this far off the aim.
const SOFT_AIM_RANGE := 4.0
const SOFT_AIM_ANGLE := 0.95

static func install() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in KEYS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)
	for action: String in MOUSE:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

## Raw intent from the real input state (call from _physics_process): movement is
## relative to the camera's yaw.
static func read(camera_basis: Basis) -> Dictionary:
	var raw := Vector2(Input.get_axis("alab_move_left", "alab_move_right"), Input.get_axis("alab_move_forward", "alab_move_back"))
	return {
		"move": camera_basis * Vector3(raw.x, 0.0, raw.y),
		"light": Input.is_action_just_pressed("alab_light"),
		"heavy": Input.is_action_just_pressed("alab_heavy"),
		"guard": Input.is_action_pressed("alab_guard"),
		"dodge": Input.is_action_just_pressed("alab_dodge"),
	}

## Facing for an intent. Locked: none (the rules face the opponent). Unlocked: where
## the player moves, else where they already face; an attack starting near the
## opponent's direction turns onto them (soft aim) — the camera itself never turns.
static func facing(intent: Dictionary, locked: bool, me_pos: Vector3, me_forward: Vector3, foe_pos: Vector3) -> Variant:
	if locked:
		return null
	var move: Vector3 = intent.get("move", Vector3.ZERO)
	var aim := move if move.length() > 0.1 else me_forward
	if intent.get("light", false) or intent.get("heavy", false):
		var to := foe_pos - me_pos
		to.y = 0.0
		if to.length() <= SOFT_AIM_RANGE and to.length() > 0.05 and aim.angle_to(to) <= SOFT_AIM_ANGLE:
			return to.normalized()
	return aim
