extends SceneTree
## Selection grammar is independent of blueprint semantics. Compatibility digests
## were captured on main 8025663 BEFORE adding roles/vocabulary (sorted old ids,
## all 16P3 addresses, comma-joined canonical-blueprint fingerprints, FNV-1a).
const Library = preload("res://scripts/worldgen/keyword_library.gd")
const Blueprint = preload("res://scripts/worldgen/blueprint_generator.gd")
const Layout = preload("res://scripts/expedition/expedition_layout.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const Shell = preload("res://scenes/first_expedition.tscn")
const LEGACY_IDS := ["barren", "cathedral", "drowned", "forgotten", "frozen", "gilded", "hallowed", "hollow", "lightless", "ossuary", "profane", "smoldering", "sunken", "tempest", "thorned", "towering"]
const BASELINES := {"0": "9a64ffd6", "1001": "4a368779", "4294967295": "5c677fe4"}
const EXAMPLES := [["ashen", "silent", "sanctuary"], ["moonlit", "thorned", "garden"],
	["weeping", "forgotten", "requiem"], ["frozen", "gilded", "citadel"],
	["smoldering", "pallid", "necropolis"], ["veiled", "forsaken", "dream"]]
var passed := 0
var failed := 0
var output := "res://artifacts/keyword-grammar"
var rendered := false
var library := Library.new()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	rendered = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print(JSON.stringify({"check": label, "passed": value}))

func run() -> void:
	var loaded := library.load_files()
	check(loaded, "library_valid")
	if not loaded:
		quit(1)
		return
	check(library.keywords_for_slot(0).size() == 12 and library.keywords_for_slot(1).size() == 12
		and library.keywords_for_slot(2).size() == 15, "curated_role_counts")
	var all_ids: Array = library.keywords.keys()
	all_ids.sort()
	for slot in 3:
		check(library.keywords_for_slot(slot, true) == all_ids, "legacy_offers_all_recorded_words_slot_" + str(slot))
		for other in range(slot + 1, 3):
			check(not library.keywords_for_slot(slot).any(func(id: String) -> bool: return id in library.keywords_for_slot(other)),
				"disjoint_slot_%d_%d" % [slot, other])
	check(LEGACY_IDS.all(func(id: String) -> bool: return library.has_keyword(id) and library.keywords[id].legacy), "original_vocabulary_preserved")
	check(library.keywords_for_slot(-1).is_empty() and library.keywords_for_slot(3, true).is_empty(), "invalid_slots_empty")
	check(library.is_grammatical([" DROWNED ", &"hollow", "Cathedral"]), "grammar_normalization")
	check(library.is_grammatical(["frozen", "barren", "ossuary"]), "environment_quality_noun")
	for words: Array in [["cathedral", "drowned", "hollow"], ["drowned", "tempest", "cathedral"],
		["drowned", "hollow", "gilded"], ["frozen", "frozen", "ossuary"], ["unknown", "hollow", "cathedral"],
		["drowned", 4, "cathedral"], ["drowned", "hollow"], ["gilded", "frozen", "citadel"],
		["veiled", "sunken", "dream"], ["frozen", "barren", "hollow"]]:
		check(not library.is_grammatical(words), "grammar_rejects_" + str(words))
	for roles: Variant in [null, [], ["place"], ["noun", "noun"], "adjective", [4],
		["environment_adjective", "quality_adjective"], ["quality_adjective", "noun"], ["environment_adjective", "noun"]]:
		var invalid := Library.new()
		invalid.load_files()
		invalid.keywords.drowned.roles = roles
		invalid._validate()
		check(not invalid.errors.is_empty(), "invalid_role_metadata_" + str(roles))
		check(not Blueprint.new(invalid).generate(["drowned", "hollow", "cathedral"], 1001).ok, "invalid_catalog_blocks_generation_" + str(roles))
	var empty_slot := Library.new()
	empty_slot.load_files()
	for entry: Dictionary in empty_slot.keywords.values():
		if entry.roles == ["quality_adjective"]:
			entry.roles = ["environment_adjective"]
	empty_slot._validate()
	check(empty_slot.errors.has("selectable slot quality_adjective has no keywords"), "empty_slot_rejected")
	var gen := Blueprint.new(library)
	# Every previous valid order remains supported, without renaming or reordering.
	if not rendered:
		for seed_text: String in BASELINES:
			var hashes := PackedStringArray()
			for a: String in LEGACY_IDS:
				for b: String in LEGACY_IDS:
					for c: String in LEGACY_IDS:
						if a != b and a != c and b != c:
							hashes.append(gen.generate([a, b, c], int(seed_text)).blueprint.fingerprint)
			check(hashes.size() == 3360 and Stream.hex32(Stream.hash32(",".join(hashes))) == BASELINES[seed_text], "all_old_blueprints_unchanged_seed_" + seed_text)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/qa/fixtures/keyword_slot_baseline.json"))
	# Captured from latest main before this edit: all 8,786 addresses offered by
	# the previous selector, including words added in PR #30, at three seeds.
	if not rendered:
		for seed_text: String in baseline.digests:
			var hashes := PackedStringArray()
			for a: String in baseline.adjectives:
				for b: String in baseline.adjectives:
					for c: String in baseline.nouns:
						if a != b and a != c and b != c:
							hashes.append(gen.generate([a, b, c], int(seed_text)).blueprint.fingerprint)
			check(hashes.size() == int(baseline.digests[seed_text].count) and Stream.hex32(Stream.hash32(",".join(hashes))) == baseline.digests[seed_text].hash,
				"all_previous_grammar_blueprints_unchanged_seed_" + seed_text)
	for record: Dictionary in baseline.examples:
		var layout: Dictionary = Layout.generate(record.address.to_lower().split(" "), int(record.seed)).layout
		check(layout.fingerprint == record.layout and layout.blueprint.fingerprint == record.blueprint and layout.blueprint.identity_fingerprint == record.identity,
			"previous_example_preserved_" + record.address + "_" + record.seed)
	# Every word appears in an address, across 32 seeds; all new nouns work in the
	# existing consumer. The exact same address+seed must reproduce the whole layout.
	for id: String in library.keywords:
		var words: Array = ["drowned", "hollow", "cathedral"]
		words[Library.SLOT_ROLES.find(library.keywords[id].roles[0])] = id
		check(library.is_grammatical(words), "word_in_own_slot_" + id)
		var first: Dictionary = Layout.generate(words, 0).layout
		var variants: Dictionary = {}
		var stable := true
		for seed_value in 32:
			var a: Dictionary = Layout.generate(words, seed_value).layout
			var b: Dictionary = Layout.generate(words, seed_value).layout
			stable = stable and Blueprint.canonical_json(a) == Blueprint.canonical_json(b) and a.identity == first.identity and a.blueprint.identity_fingerprint == first.blueprint.identity_fingerprint
			variants[str(a.modules)] = true
		check(stable and variants.size() >= 12, "stable_identity_replay_and_varied_geography_" + id)
	# Negative control: grammar cannot become a second generation algorithm.
	var changed_roles := Library.new()
	changed_roles.load_files()
	for id: String in changed_roles.keywords:
		changed_roles.keywords[id].roles = ["noun"]
	var alternate := Blueprint.new(changed_roles)
	for words: Array in EXAMPLES:
		check(alternate.generate(words, 1001).blueprint == gen.generate(words, 1001).blueprint, "roles_do_not_change_generation_" + words[2])
	var examples: Array = []
	for words: Array in EXAMPLES:
		check(library.is_grammatical(words), "natural_example_" + str(words))
		for seed_value in [1001, 1002]:
			var layout: Dictionary = Layout.generate(words, seed_value).layout
			var record := {"address": layout.blueprint.address, "seed": str(seed_value), "identity": layout.blueprint.identity_fingerprint,
				"blueprint": layout.blueprint.fingerprint, "layout": layout.fingerprint, "modules": layout.modules, "themes": layout.identity.tags}
			examples.append(record)
			print(JSON.stringify(record))
	write_json("examples.json", examples)
	await test_ui()
	var summary := {"passed": passed, "failed": failed, "rendered": rendered, "engine": Engine.get_version_info().string}
	write_json("summary.json", summary)
	print(JSON.stringify(summary))
	quit(1 if failed else 0)

func test_ui() -> void:
	var shell := Shell.instantiate()
	root.add_child(shell)
	await frame(3)
	check(shell.legacy_check.disabled and not shell.legacy_check.button_pressed, "new_worlds_default_to_grammar")
	check(shell.slot_labels[0].text == "Environment / state" and shell.slot_labels[1].text == "Character / quality" and shell.slot_labels[2].text == "Place / concept noun", "visible_slot_roles")
	var menus_correct := true
	for slot in 3:
		var ids := library.keywords_for_slot(slot)
		var choice: OptionButton = shell.choices[slot]
		menus_correct = menus_correct and choice.item_count == ids.size()
		for index in choice.item_count:
			menus_correct = menus_correct and choice.get_item_text(index).to_lower() == ids[index]
	check(menus_correct, "selector_filters_each_role")
	var offered: Dictionary = {}
	var unique := true
	for choice: OptionButton in shell.choices:
		for index in choice.item_count:
			var id := choice.get_item_text(index).to_lower()
			unique = unique and not offered.has(id)
			offered[id] = true
	check(unique and offered.size() == 39, "visible_menus_are_disjoint_and_complete")
	check(root.get_visible_rect().encloses(shell.selection.get_global_rect()), "desktop_menu_fits_viewport")
	await capture("01_selection")
	# Real keyboard popup navigation, followed by mouse activation of Begin.
	shell.choices[2].grab_focus()
	await key(KEY_ENTER)
	for i in 14:
		await key(KEY_DOWN)
	await key(KEY_ENTER)
	check(shell.choices[2].get_item_text(shell.choices[2].selected) == "Tempest", "keyboard_selects_final_noun")
	select_words(shell, ["ashen", "silent", "sanctuary"])
	shell.replay_check.button_pressed = true
	shell.seed_edit.text = "1001"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	# InputEvent positions are window pixels; headless uses a 64 px dummy window.
	click.position = root.get_final_transform() * shell.begin_button.get_global_rect().get_center()
	click.pressed = true
	Input.parse_input_event(click)
	await frame()
	click.pressed = false
	Input.parse_input_event(click)
	await frame(3)
	check(is_instance_valid(shell.expedition) and shell.expedition.layout.blueprint.address == "Ashen Silent Sanctuary", "mouse_launches_grammatical_address")
	await capture("02_sanctuary")
	shell.return_to_selection()
	shell.legacy_check.button_pressed = true
	check(shell.choices.all(func(c: OptionButton) -> bool: return c.item_count == 39), "legacy_offers_all_words_in_every_slot")
	select_words(shell, ["frozen", "frozen", "ossuary"])
	shell.seed_edit.text = "1001"
	shell._begin_selection()
	check(shell.expedition == null and shell.error_label.text.contains("different supported"), "legacy_duplicates_rejected")
	select_words(shell, ["tempest", "frozen", "towering"])
	shell.seed_edit.text = "1001"
	shell._begin_selection()
	await frame(3)
	check(shell.expedition.layout.fingerprint == Layout.generate(["tempest", "frozen", "towering"], 1001).layout.fingerprint, "legacy_ui_preserves_exact_order_and_seed")
	var fingerprint: String = shell.expedition.layout.fingerprint
	shell.restart_expedition()
	check(shell.expedition.layout.fingerprint == fingerprint, "legacy_restart_preserves_replay")
	shell.return_to_selection()
	await frame(3)
	await capture("03_legacy_selection")
	for words: Array in [["veiled", "sunken", "dream"], ["frozen", "barren", "hollow"], ["gilded", "moonlit", "garden"]]:
		select_words(shell, words)
		shell.seed_edit.text = "1001"
		shell._begin_selection()
		check(is_instance_valid(shell.expedition) and shell.expedition.layout.blueprint.input.keywords == words
			and shell.expedition.layout.fingerprint == Layout.generate(words, 1001).layout.fingerprint, "legacy_replays_previous_roles_" + str(words))
		shell.return_to_selection()
	shell.replay_check.button_pressed = false
	check(not shell.legacy_check.button_pressed and shell.legacy_check.disabled and shell.choices[0].item_count == 12
		and shell.choices[1].item_count == 12 and shell.choices[2].item_count == 15, "fresh_world_restores_grammar")
	# Inject a wrong-slot value to check the launch boundary even if UI filtering breaks.
	shell.choices[1].set_item_text(shell.choices[1].selected, "Frozen")
	shell._begin_selection()
	check(shell.expedition == null and shell.error_label.text.contains("own lists"), "wrong_slot_feedback")
	shell._populate_choices(false)
	select_words(shell, ["weeping", "forgotten", "requiem"])
	shell.replay_check.button_pressed = true
	for seed_text: String in ["-1", "4294967296", "", "1.5"]:
		shell.seed_edit.text = seed_text
		shell._begin_selection()
		check(shell.expedition == null, "rejects_invalid_seed_" + seed_text)
	for seed_text: String in ["0", "4294967295"]:
		shell.seed_edit.text = seed_text
		shell._begin_selection()
		check(shell.expedition.layout.blueprint.input.world_seed == seed_text, "seed_boundary_replays_" + seed_text)
		shell.return_to_selection()
	shell.free()

func select_words(shell: Node, words: Array) -> void:
	for slot in 3:
		var choice: OptionButton = shell.choices[slot]
		var found := false
		for index in choice.item_count:
			if choice.get_item_text(index).to_lower() == words[slot]:
				choice.select(index)
				found = true
		check(found, "requested_word_available_%d_%s" % [slot, words[slot]])

func frame(count := 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frame()
	event.pressed = false
	Input.parse_input_event(event)
	await frame()

func capture(label: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)

func write_json(name: String, value: Variant) -> void:
	FileAccess.open(output.path_join(name), FileAccess.WRITE).store_string(JSON.stringify(value, "\t") + "\n")
