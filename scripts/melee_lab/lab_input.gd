extends RefCounted
## The lab's complete input map, in one place. Actions are prefixed `lab_` and added
## at runtime only when absent, so production actions and project.godot are untouched.
## To rebind, edit this table (or rebind the lab_* actions in Project Settings).

const KEYS := {
	"lab_move_forward": KEY_W, "lab_move_back": KEY_S, "lab_move_left": KEY_A, "lab_move_right": KEY_D,
	"lab_dodge": KEY_SPACE, "lab_roll": KEY_SHIFT, "lab_lock_on": KEY_TAB, "lab_reset": KEY_R, "lab_release_mouse": KEY_ESCAPE,
	"lab_help": KEY_F1, "lab_tuning": KEY_F2, "lab_debug": KEY_F3, "lab_slow_motion": KEY_F4,
	"lab_trails": KEY_T, "lab_arcs": KEY_Y, "lab_labels": KEY_U,
	"lab_player_weapon_next": KEY_BRACKETRIGHT, "lab_player_weapon_prev": KEY_BRACKETLEFT,
	"lab_opponent_weapon_next": KEY_PERIOD, "lab_opponent_weapon_prev": KEY_COMMA,
	"lab_opponent_mode": KEY_M, "lab_dummy_guard": KEY_G, "lab_world_condition": KEY_V,
}
const MOUSE := {"lab_attack": MOUSE_BUTTON_LEFT, "lab_guard": MOUSE_BUTTON_RIGHT}

static func install() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, event)
	for action: String in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE[action]
			InputMap.action_add_event(action, event)

static func key_name(action: String) -> String:
	if MOUSE.has(action):
		return "LMB" if MOUSE[action] == MOUSE_BUTTON_LEFT else "RMB"
	return OS.get_keycode_string(KEYS[action])
