extends RefCounted
## The Adaptive Combat Lab's input map. Actions are prefixed `alab_` and added at
## runtime only when absent, so project.godot and every other scene's input are
## untouched. Proposed traditional action-game layout (subject to owner feel test).

const KEYS := {
	"alab_move_forward": [KEY_W], "alab_move_back": [KEY_S], "alab_move_left": [KEY_A], "alab_move_right": [KEY_D],
	"alab_light": [KEY_J], "alab_heavy": [KEY_F, KEY_K], "alab_guard": [KEY_L], "alab_dodge": [KEY_SPACE],
}
const MOUSE := {"alab_light": MOUSE_BUTTON_LEFT, "alab_guard": MOUSE_BUTTON_RIGHT, "alab_heavy": MOUSE_BUTTON_MIDDLE}

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

## Intent from the real input state (call from _physics_process).
static func read(camera_yaw: float) -> Dictionary:
	var raw := Vector2(Input.get_axis("alab_move_left", "alab_move_right"), Input.get_axis("alab_move_forward", "alab_move_back"))
	var move := Basis(Vector3.UP, camera_yaw) * Vector3(raw.x, 0.0, raw.y)
	return {
		"move": move,
		"light": Input.is_action_just_pressed("alab_light"),
		"heavy": Input.is_action_just_pressed("alab_heavy"),
		"guard": Input.is_action_pressed("alab_guard"),
		"dodge": Input.is_action_just_pressed("alab_dodge"),
	}
