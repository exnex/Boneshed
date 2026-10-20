extends Node
## Scene-owned session shell: selection -> expedition -> pause/selection. Returning
## destroys the whole session; retry/rematch inside it retains the existing builds.
const Generator = preload("res://scripts/expedition/expedition_layout.gd")
const Expedition = preload("res://scripts/expedition/expedition.gd")
const Library = preload("res://scripts/worldgen/keyword_library.gd")

var expedition: Expedition
var selection: PanelContainer
var pause_panel: PanelContainer
var travel_card: Label
var error_label: Label
var seed_edit: LineEdit
var replay_check: CheckBox
var legacy_check: CheckBox
var begin_button: Button
var choices: Array[OptionButton] = []
var slot_labels: Array[Label] = []
var library := Library.new()
var last_request: Dictionary = {}
var canvas: CanvasLayer

func _ready() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 2 # Keep the session menu above the inherited encounter HUD.
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_build_selection()
	_build_pause()
	travel_card = Label.new()
	travel_card.position = Vector2(32, 104)
	travel_card.add_theme_font_size_override("font_size", 14)
	travel_card.add_theme_color_override("font_color", Color("c6c9ba"))
	canvas.add_child(travel_card)
	travel_card.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if is_instance_valid(expedition) and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func _build_selection() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("101b23")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(backdrop)
	selection = PanelContainer.new()
	selection.name = "ExpeditionSelection"
	selection.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	selection.offset_left = -350
	selection.offset_right = 350
	selection.offset_top = -300
	selection.offset_bottom = 300
	canvas.add_child(selection)
	# Backdrop belongs to selection's lifetime/visibility, without intercepting input.
	selection.visibility_changed.connect(func() -> void: backdrop.visible = selection.visible)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	selection.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_label(box, "B O N E S H E D", 18, Color("d4bd8d"))
	_label(box, "First Expedition", 36)
	_label(box, "Three words. An empty world. One soul to release.", 18)
	_label(box, "Name a place: environment + quality + noun", 15, Color("a4b8c0"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	if not library.load_files():
		_label(box, "Keyword library unavailable: " + "; ".join(library.errors), 16)
		return
	for i in 3:
		var column := VBoxContainer.new()
		row.add_child(column)
		slot_labels.append(_label(column, "", 14, Color("a4b8c0")))
		var choice := OptionButton.new()
		choice.custom_minimum_size = Vector2(195, 42)
		choice.get_popup().max_size.y = 360
		column.add_child(choice)
		choices.append(choice)
	_populate_choices(false)
	replay_check = CheckBox.new()
	replay_check.text = "Replay an existing seed"
	box.add_child(replay_check)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Seed (0–4294967295)"
	seed_edit.max_length = 10
	seed_edit.editable = false
	box.add_child(seed_edit)
	legacy_check = CheckBox.new()
	legacy_check.text = "Replay an older address (all words, any order)"
	legacy_check.disabled = true
	box.add_child(legacy_check)
	legacy_check.toggled.connect(_populate_choices)
	replay_check.toggled.connect(func(enabled: bool) -> void:
		seed_edit.editable = enabled
		legacy_check.disabled = not enabled
		if not enabled:
			legacy_check.button_pressed = false)
	_label(box, "New expeditions use a fresh seed. Keep the address + seed to return.", 14, Color("a4b8c0"))
	error_label = _label(box, "", 15, Color("e6a29a"))
	error_label.custom_minimum_size.y = 24
	begin_button = _button(box, "Begin expedition", _begin_selection)
	_label(box, "WASD move · Mouse orbit · Tab lock · F1 controls · Esc menu", 14, Color("a4b8c0"))

func _populate_choices(legacy: bool) -> void:
	var defaults := ["drowned", "hollow", "cathedral"]
	for slot in choices.size():
		var choice := choices[slot]
		var previous: String = choice.get_item_text(choice.selected).to_lower() if choice.selected >= 0 else defaults[slot]
		var ids := library.keywords_for_slot(slot, legacy)
		choice.clear()
		for id: String in ids:
			choice.add_item(id.capitalize())
		choice.select(ids.find(previous) if previous in ids else ids.find(defaults[slot]))
		slot_labels[slot].text = "Word %d (older address)" % (slot + 1) if legacy else ["Environment / state", "Character / quality", "Place / concept noun"][slot]
	if is_instance_valid(error_label):
		error_label.text = ""

func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.name = "ExpeditionMenu"
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -230
	pause_panel.offset_right = 230
	pause_panel.offset_top = -150
	pause_panel.offset_bottom = 150
	canvas.add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	pause_panel.add_child(box)
	_label(box, "Expedition paused", 28)
	_button(box, "Resume", func() -> void: set_paused(false))
	_button(box, "Restart this address + seed", restart_expedition)
	_button(box, "Return to keyword selection", return_to_selection)
	_label(box, "Restart / return clears this expedition's salvage.", 14, Color("a4b8c0"))
	pause_panel.hide()

func _begin_selection() -> void:
	var words: Array = []
	for choice: OptionButton in choices:
		words.append(choice.get_item_text(choice.selected).to_lower())
	if not legacy_check.button_pressed and not library.is_grammatical(words):
		error_label.text = "Choose an environment, a quality and a noun from their own lists."
		return
	var seed_value := 0
	if replay_check.button_pressed:
		var entered := seed_edit.text.strip_edges()
		if entered.is_empty() or not entered.is_valid_int() or entered.to_int() < 0 or entered.to_int() > 4294967295:
			error_label.text = "Enter a whole seed from 0 to 4294967295."
			return
		seed_value = entered.to_int()
	else:
		# Entropy is used only at the new-instance boundary, never in generation.
		var bytes := Crypto.new().generate_random_bytes(4)
		if bytes.size() != 4:
			error_label.text = "Could not create a seed. Try again or use replay."
			return
		seed_value = bytes.decode_u32(0)
	start_expedition(words, seed_value)

func start_expedition(words: Array, seed_value: int) -> bool:
	var generated := Generator.generate(words, seed_value)
	if not generated.ok:
		error_label.text = "Choose three different supported keywords."
		return false
	_discard_expedition()
	last_request = {"words": words.duplicate(), "seed": seed_value}
	expedition = Expedition.new()
	expedition.process_mode = Node.PROCESS_MODE_PAUSABLE
	expedition.name = "FirstExpedition"
	expedition.layout = generated.layout
	expedition.builds_path = "res://data/builds/salvage_courtyard.json"
	add_child(expedition)
	selection.hide()
	error_label.text = ""
	travel_card.text = "%s  /  %d\nReach the ring · Esc expedition menu" % [generated.layout.blueprint.address, seed_value]
	travel_card.show()
	set_paused(false)
	return true

func set_paused(value: bool) -> void:
	get_tree().paused = value
	pause_panel.visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	# Pause consumes Esc before Player sees it; release held defense/motion on resume.
	_release_actions()

func restart_expedition() -> void:
	start_expedition(last_request.words, last_request.seed)

func return_to_selection() -> void:
	_discard_expedition()
	selection.show()
	travel_card.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _discard_expedition() -> void:
	get_tree().paused = false
	pause_panel.hide()
	_release_actions()
	if is_instance_valid(expedition):
		remove_child(expedition)
		expedition.queue_free()
		expedition = null

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)

func _label(parent: Node, value: String, size: int, color := Color("d5dedc")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	parent.add_child(button)
	return button
