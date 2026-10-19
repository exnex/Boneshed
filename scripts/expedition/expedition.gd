extends "res://scripts/courtyard.gd"
## World-specific lifecycle hooks over the existing encounter. No parallel combat,
## salvage, equipment or rematch implementation.
const WorldBuilder = preload("res://scripts/expedition/world_builder.gd")

var layout: Dictionary
var encounter_started := false
var world_builder: WorldBuilder

func _build_courtyard() -> void:
	world_builder = WorldBuilder.new()
	world_builder.layout = layout
	add_child(world_builder)

func _reset_positions() -> void:
	var center := WorldBuilder.point(layout.arena)
	player.reset_at(center + Vector3(0, 0.02, 4) if encounter_started else WorldBuilder.point(layout.spawn) + Vector3.UP * 0.02)
	enemy.reset_at(center + Vector3(0, 0.02, -3))
	enemy.enabled = encounter_started
	world_builder.set_arena_sealed(encounter_started)
	encounter_time = 0.0
	event_text = "Follow the inlay to the corrupted soul."
	event_time = 3.0
	player.sync_visual()
	enemy.sync_visual()

func _physics_process(delta: float) -> void:
	if not encounter_started and player.position.distance_to(WorldBuilder.point(layout.arena)) < 8.5:
		encounter_started = true
		enemy.enabled = true
		world_builder.set_arena_sealed(true)
		event_text = "The corrupted soul stirs."
		event_time = 3.0
	super._physics_process(delta)

func _resolve_duel() -> void:
	# The shell can remove this scene before a previously queued contact flushes.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	super._resolve_duel()
	if progression.stage == Progression.Stage.VICTORY:
		world_builder.set_arena_sealed(false)

func progression_prompt() -> String:
	var prompt := super.progression_prompt()
	if not prompt.is_empty():
		return prompt
	return "Follow the inlay · reach the ring" if not encounter_started else ""
