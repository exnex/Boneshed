extends "res://scripts/expedition/expedition_select.gd"
## Separately selectable shell for the expedition preview. Reuses the First
## Expedition keyword selection, seed replay, legacy-address support and pause menu
## unchanged; only the generated session and the extraction summary differ.
const Preview = preload("res://scripts/expedition_preview/preview_expedition.gd")
const PreviewPlan = preload("res://scripts/expedition_preview/expedition_plan.gd")

var preview: Preview
var summary_panel: PanelContainer
var summary_label: Label
var generation_ms := 0.0

func _ready() -> void:
	super._ready()
	# Retitle the shared selection screen without changing the First Expedition code.
	for label: Node in selection.find_children("*", "Label", true, false):
		if label.text == "First Expedition":
			label.text = "Expedition Preview"
		elif label.text.begins_with("Three words."):
			label.text = "Prototype: regions, a dungeon, its guardian, extraction."
	_build_summary()

func _input(event: InputEvent) -> void:
	if is_instance_valid(preview) and not summary_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func start_expedition(words: Array, seed_value: int) -> bool:
	var started := Time.get_ticks_usec()
	var generated := PreviewPlan.generate(words, seed_value)
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	if not generated.ok:
		error_label.text = "Choose three different supported keywords." if generated.plan.is_empty() else "Generation failed validation; try another seed."
		if not generated.plan.is_empty():
			push_warning("Expedition preview plan failed validation: " + JSON.stringify(generated.errors))
		return false
	_discard_expedition()
	last_request = {"words": words.duplicate(), "seed": seed_value}
	preview = Preview.new()
	preview.process_mode = Node.PROCESS_MODE_PAUSABLE
	preview.name = "ExpeditionPreview"
	preview.plan = generated.plan
	preview.builds_path = "res://data/builds/salvage_courtyard.json"
	preview.extracted.connect(_show_summary)
	add_child(preview)
	selection.hide()
	error_label.text = ""
	travel_card.text = "%s  /  %d  ·  expedition preview\nFind the descent · Esc expedition menu" % [generated.plan.address, seed_value]
	travel_card.show()
	set_paused(false)
	return true

func _discard_expedition() -> void:
	super._discard_expedition()
	summary_panel.hide()
	if is_instance_valid(preview):
		remove_child(preview)
		preview.queue_free()
		preview = null

func _build_summary() -> void:
	summary_panel = PanelContainer.new()
	summary_panel.name = "ExtractionSummary"
	summary_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	summary_panel.offset_left = -280
	summary_panel.offset_right = 280
	summary_panel.offset_top = -210
	summary_panel.offset_bottom = 210
	canvas.add_child(summary_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	summary_panel.add_child(box)
	_label(box, "Extracted", 28)
	summary_label = _label(box, "", 15)
	_button(box, "Replay this address + seed", restart_expedition)
	_button(box, "Return to keyword selection", return_to_selection)
	_label(box, "Prototype satchel: finds are reported, not saved or valued.", 13, Color("a4b8c0"))
	summary_panel.hide()

func _show_summary(summary: Dictionary) -> void:
	var finds: Array = summary.finds
	var lines := ["%s  /  %d" % [preview.plan.address, last_request.seed], "",
		"Finds (%d): %s" % [finds.size(), ", ".join(finds) if not finds.is_empty() else "none"],
		"Carried: " + (", ".join(summary.carried) if not summary.carried.is_empty() else "none"),
		"Equipped: " + ", ".join(summary.equipped.values())]
	summary_label.text = "\n".join(lines)
	# The summary replaces the duel HUD rather than drawing over it.
	preview.hud.visible = false
	preview.objective_label.visible = false
	get_tree().paused = true
	summary_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
