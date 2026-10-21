extends "res://scripts/melee_lab/lab_player.gd"
## The melee lab's player controller, unchanged in its approved controls (click,
## flick, release; held chambers; held directional guard; fresh-press deflect; Space
## step; Shift roll), placed in the expedition. Additions only:
##   Q held / released — the salvaged Marrow Arm's lunge: a directional thrust with the
##                       same hold-to-release rule (see expedition_state.gd).
##   teleport          — doorway transitions move the body without resetting rules state.
## Without an opponent (exploration) the body faces the camera, as the lab does with
## lock-on off; movement is camera-relative either way.

const ExpeditionState = preload("res://scripts/directional_expedition/expedition_state.gd")
const ExpeditionVisual = preload("res://scripts/directional_expedition/expedition_visual.gd")
const ExpeditionDuelist = preload("res://scripts/directional_expedition/expedition_duelist.gd")

var marrow_arm := false

func _ready() -> void:
	super._ready()
	visual = ExpeditionDuelist.swap_visual(self, visual, ExpeditionVisual)

## Same derivation as the lab (lab_duelist.equip), with the expedition rules state.
func equip(lab_tuning: Dictionary, resolved: Dictionary) -> void:
	super.equip(lab_tuning, resolved)
	state = ExpeditionDuelist.state_for(lab_tuning, state, resolved, ExpeditionState)
	marrow_arm = ExpeditionDuelist.has_marrow_arm(resolved)
	if is_instance_valid(visual):
		visual.rebuild()

func control(delta: float) -> void:
	super.control(delta)
	if not input_enabled:
		return
	if Input.is_action_just_pressed("signature") and not Input.is_action_pressed("lab_guard"):
		if state.press_signature():
			aim_owner = ""
	if state.signature_active and state.phase == State.Phase.WINDUP and not state.released and not Input.is_action_pressed("signature"):
		state.release_attack()

## A doorway move: position, facing and camera only. Health, posture, stamina and
## statuses carry over.
func teleport(point: Vector3, yaw_value: float) -> void:
	position = point
	velocity = Vector3.ZERO
	desired_move = Vector3.ZERO
	facing = Vector3.FORWARD.rotated(Vector3.UP, yaw_value)
	camera_yaw = yaw_value
	prev_xform = xform()
