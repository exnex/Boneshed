extends SceneTree
## Rendered close-ups of equipment placement on both fighters, reached through the
## real victory → salvage → equip → next-duel path. Uses only APIs that predate the
## equipment foundation, so the same shots can be taken on an older revision for a
## before/after comparison. Writes PNGs plus placement.json; exits 1 on a reported
## build/visual disagreement (when the revision has the agreement check).
## Usage: godot --path . --script res://scripts/qa/equipment_capture.gd -- --evidence-dir=<dir>
const Playable = preload("res://scenes/salvage_courtyard.tscn")
const Rules = preload("res://scripts/combat/combat_state.gd")
const LOOK_PATH := "res://scripts/characters/presentation/equipment_look.gd"
var output := "res://artifacts/equipment-capture"
var arena: Node3D
var camera: Camera3D
var report := []
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func run() -> void:
	arena = Playable.instantiate()
	root.add_child(arena)
	for i in range(3):
		await physics_frame
	camera = Camera3D.new()
	camera.fov = 40.0
	arena.add_child(camera)
	await showcase("1_before_salvage")
	victory()
	arena.progression.acquire()
	arena.progression.equip()
	arena._start_duel(true)
	await showcase("2_after_equip")
	# Legacy Marrow Lunge on the new body: committed draw-back, then full extension.
	for fighter: Fighter in [arena.player, arena.enemy]:
		fighter.combat.attack_special()
		fighter.combat.tick(0.55)
	await shot("3_lunge_drawback_front", Vector3(0.0, 1.6, 6.0))
	for fighter: Fighter in [arena.player, arena.enemy]:
		fighter.combat.tick(0.16)
	await shot("4_lunge_active_side", Vector3(6.5, 1.8, 2.5))
	var file := FileAccess.open(output.path_join("placement.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print(JSON.stringify({"summary": true, "failed": failed, "shots": report.size(), "engine": Engine.get_version_info().string}))
	arena.free()
	quit(1 if failed else 0)

## Idle, side by side, facing the camera; then the same pose from behind.
func showcase(label: String) -> void:
	await shot(label + "_front", Vector3(0.0, 1.6, 6.0))
	await shot(label + "_rear", Vector3(0.0, 1.9, -6.0))

func pose_fighters() -> void:
	arena.set_physics_process(false)
	arena.hud.visible = false
	for fighter: Fighter in [arena.player, arena.enemy]:
		fighter.set_physics_process(false)
		fighter.reset_at(Vector3(-1.2 if fighter == arena.player else 1.2, 0.02, 0.0))
		fighter.facing = Vector3.BACK
		fighter.visual.rotation.y = PI
	arena.enemy.enabled = false

func shot(label: String, eye: Vector3) -> void:
	if label.ends_with("_front") and not label.begins_with("3_"):
		pose_fighters()
	for fighter: Fighter in [arena.player, arena.enemy]:
		fighter.sync_visual(0.0)
	camera.position = eye
	camera.look_at(Vector3(0.0, 1.15, 0.0))
	camera.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var entry := {"shot": label, "fighters": {}}
	for fighter: Fighter in [arena.player, arena.enemy]:
		var record := {"equipped": (arena.progression.builds.player if fighter == arena.player else arena.progression.builds.enemy).equipped,
			"sword_hand_x": snappedf(fighter.sword_pivot.position.x, 0.001), "marrow_visible": fighter.marrow_pivot.visible,
			"marrow_root_x": snappedf(fighter.marrow_pivot.position.x, 0.001), "off_arm_visible": fighter.free_arm.visible}
		if ResourceLoader.exists(LOOK_PATH):
			record.disagreements = load(LOOK_PATH).disagreements(fighter)
			failed += int(not record.disagreements.is_empty())
		entry.fighters[fighter.name] = record
	report.append(entry)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(output.path_join(label + ".png"))

## Real attacks through the production resolver, as in marrow_tests.gd.
func victory() -> void:
	arena.reset_encounter()
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	for fighter: Fighter in [p, e]:
		fighter.set_physics_process(false)
	arena.set_physics_process(false)
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	while e.combat.phase != Rules.Phase.DEAD:
		p.combat.tick(5.0)
		p.combat.attack()
		p.combat.tick(p.combat.remaining + 0.001)
		arena._resolve_duel()
