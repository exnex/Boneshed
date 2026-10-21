extends RefCounted
## Status runtime for one lab fighter: buildup → activation → duration/periodic update →
## expiry, with per-effect resistance. Pure and deterministic: clocks only advance in
## `tick`, nothing is random, and effects update in sorted id order. Routing (whether a
## contact may apply status at all) happens before this, in duelist_state.gd; this file
## only sees amounts that were allowed through.
##
## Definitions come from data/melee_lab/combat_resources.json (`effects`), validated by
## combat_resources.gd. Kinds: `damage_over_time` (tick_damage every tick_interval) and
## `impairment` (move_scale / handling_scale while active). `while_active` is "refresh"
## (reaching the threshold again restarts the duration; magnitude never stacks) or
## "ignore" (no buildup while active). `immunity_after` blocks buildup after expiry.
## Hard control (stun, freeze, paralysis) is deliberately not a supported kind.

const EPSILON := 1e-6

var defs: Dictionary = {}
var resistances: Dictionary = {}
var buildup := {}
var active := {}
var immune := {}
## Events since the owner last drained them: {effect, event, amount, source}.
var events: Array[Dictionary] = []

func _init(definitions: Dictionary, resisted: Dictionary) -> void:
	defs = definitions
	resistances = resisted
	reset()

func reset() -> void:
	buildup.clear()
	active.clear()
	immune.clear()
	events.clear()
	for effect: String in defs:
		buildup[effect] = 0.0

func resistance(effect: String) -> float:
	return float(resistances.get(effect, 0.0))

## Adds routed buildup. Resistance scales it here, once. Returns the amount applied.
func add_buildup(effect: String, amount: float, source: String) -> float:
	if not defs.has(effect) or amount <= 0.0:
		return 0.0
	var def: Dictionary = defs[effect]
	if immune.get(effect, 0.0) > 0.0:
		_event(effect, "immune", 0.0, source)
		return 0.0
	if active.has(effect) and def.while_active == "ignore":
		_event(effect, "ignored_active", 0.0, source)
		return 0.0
	var applied := amount * (1.0 - resistance(effect))
	buildup[effect] += applied
	_event(effect, "buildup", applied, source)
	if buildup[effect] + EPSILON >= def.threshold:
		buildup[effect] = 0.0
		_activate(effect, source)
	return applied

func _activate(effect: String, source: String) -> void:
	var def: Dictionary = defs[effect]
	if active.has(effect):
		active[effect].remaining = def.duration
		active[effect].source = source
		_event(effect, "refreshed", def.duration, source)
		return
	active[effect] = {"remaining": def.duration, "tick_in": float(def.get("tick_interval", 0.0)), "source": source, "ticks": 0}
	_event(effect, "activated", def.duration, source)

## Advances every clock by `delta`. Returns the periodic damage due this tick as
## [{effect, damage, can_kill, source}] for the owner to apply.
func tick(delta: float) -> Array[Dictionary]:
	var damage: Array[Dictionary] = []
	var ids := defs.keys()
	ids.sort()
	for effect: String in ids:
		var def: Dictionary = defs[effect]
		if immune.get(effect, 0.0) > 0.0:
			immune[effect] = maxf(0.0, immune[effect] - delta)
		if not active.has(effect):
			buildup[effect] = maxf(0.0, buildup[effect] - def.decay_per_second * delta)
			continue
		var entry: Dictionary = active[effect]
		entry.remaining -= delta
		if def.kind == "damage_over_time":
			entry.tick_in -= delta
			while entry.tick_in <= EPSILON:
				entry.tick_in += def.tick_interval
				entry.ticks += 1
				damage.append({"effect": effect, "damage": def.tick_damage, "can_kill": def.can_kill, "source": entry.source})
				_event(effect, "tick", def.tick_damage, entry.source)
		if entry.remaining <= EPSILON:
			active.erase(effect)
			immune[effect] = def.immunity_after
			_event(effect, "expired", 0.0, entry.source)
	return damage

func is_active(effect: String) -> bool:
	return active.has(effect)

func move_scale() -> float:
	return _product("move_scale")

func handling_scale() -> float:
	return _product("handling_scale")

func _product(key: String) -> float:
	var scale := 1.0
	for effect: String in active:
		scale *= float(defs[effect].get(key, 1.0))
	return scale

## Public view for HUD, AI self-knowledge and an eventual Echo policy.
func view() -> Dictionary:
	var out := {}
	var ids := defs.keys()
	ids.sort()
	for effect: String in ids:
		out[effect] = {"buildup": buildup[effect], "threshold": defs[effect].threshold, "active": active.has(effect),
			"remaining": active[effect].remaining if active.has(effect) else 0.0, "immune": immune.get(effect, 0.0),
			"resistance": resistance(effect)}
	return out

func drain_events() -> Array[Dictionary]:
	var out := events.duplicate()
	events.clear()
	return out

func _event(effect: String, event: String, amount: float, source: String) -> void:
	events.append({"effect": effect, "event": event, "amount": amount, "source": source})
