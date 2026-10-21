extends "res://scripts/expedition_preview/preview_shell.gd"
## Separately selectable shell for the directional expedition. Reuses the preview's
## keyword selection, seed replay, legacy addresses, pause menu and extraction summary
## layout; only the session it starts differs (directional_expedition.gd). The
## preview, First Expedition and melee lab scenes are unchanged.
const Directional = preload("res://scripts/directional_expedition/directional_expedition.gd")

var session: Directional

func _ready() -> void:
	super._ready()
	for label: Node in selection.find_children("*", "Label", true, false):
		if label.text == "Expedition Preview":
			label.text = "Directional Expedition"
		elif label.text.begins_with("Prototype:"):
			label.text = "Experimental: the generated expedition with directional melee combat."
		elif label.text.begins_with("WASD move"):
			label.text = "WASD move · LMB hold+flick+release cut · RMB guard · Space/Shift evade · F1 help · Esc menu"

func _input(event: InputEvent) -> void:
	if is_instance_valid(session) and not summary_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func start_expedition(words: Array, seed_value: int) -> bool:
	var started := Time.get_ticks_usec()
	var generated := PreviewPlan.generate(words, seed_value)
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	if not generated.ok:
		error_label.text = "Choose three different supported keywords." if generated.plan.is_empty() else "Generation failed validation; try another seed."
		return false
	_discard_expedition()
	last_request = {"words": words.duplicate(), "seed": seed_value}
	session = Directional.new()
	session.process_mode = Node.PROCESS_MODE_PAUSABLE
	session.name = "DirectionalExpedition"
	session.plan = generated.plan
	session.extracted.connect(_show_summary)
	add_child(session)
	selection.hide()
	error_label.text = ""
	# The session HUD shows the address, seed and menu key; the shared travel card would overlap it.
	travel_card.hide()
	set_paused(false)
	return true

func set_paused(value: bool) -> void:
	super.set_paused(value)
	if DisplayServer.get_name() == "headless" or "--qa" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _discard_expedition() -> void:
	super._discard_expedition()
	if is_instance_valid(session):
		remove_child(session)
		session.queue_free()
		session = null

func _show_summary(summary: Dictionary) -> void:
	var finds: Array = summary.finds
	var lines := ["%s  /  %d" % [session.plan.address, last_request.seed], "",
		"Finds (%d): %s" % [finds.size(), ", ".join(finds) if not finds.is_empty() else "none"],
		"Carried: " + (", ".join(summary.carried) if not summary.carried.is_empty() else "none"),
		"Equipped: " + ", ".join(summary.equipped.values()),
		"Souls released: %d / %d" % [session.sites.filter(func(site: Dictionary) -> bool: return site.cleared).size(), session.sites.size()]]
	summary_label.text = "\n".join(lines)
	session.hud.visible = false
	get_tree().paused = true
	summary_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
