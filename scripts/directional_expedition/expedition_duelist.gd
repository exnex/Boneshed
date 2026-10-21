extends RefCounted
## Shared setup for the expedition's player and souls, so both sides get the same
## rules state class and presentation from the same resolved build view.

## Replaces the lab rules state built by lab_duelist.equip with the expedition state
## (same tuning, handling, stats and derived resources, plus the build's signature).
static func state_for(tuning: Dictionary, lab_state: RefCounted, resolved: Dictionary, state_class: GDScript) -> RefCounted:
	return state_class.new(tuning, lab_state.base_h, resolved.stats, lab_state.resources, resolved.get("signature", {}))

static func has_marrow_arm(resolved: Dictionary) -> bool:
	return "item.marrow_arm" in resolved.get("build", {}).get("equipped", {}).values()

## lab_duelist._ready builds the lab visual; swap in the expedition visual once.
static func swap_visual(actor: Node3D, old: Node3D, visual_class: GDScript) -> Node3D:
	var flags: Dictionary = old.flags
	actor.remove_child(old)
	old.queue_free()
	var visual: Node3D = visual_class.new()
	visual.actor = actor
	visual.flags = flags
	actor.add_child(visual)
	return visual
