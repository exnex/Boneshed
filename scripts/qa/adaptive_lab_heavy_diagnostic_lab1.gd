extends SceneTree
## Heavy-miss diagnosis for Adaptive Combat Lab 1 (the code on main before Lab 2).
## Runs ONLY inside a disposable worktree of the base ref (the runner copies it there):
## it uses Lab 1's API. For every Lab 1 demonstration object it fires one heavy at a
## passive target from 0.9 m to 2.3 m and records, per tick of the active window, the
## swept feature capsule's closest gap to the target body, the footwork direction and
## the outcome. Output: one JSON line per case plus a summary.
##   godot --headless --path <worktree> --script res://scripts/qa/adaptive_lab_heavy_diagnostic_lab1.gd

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Bodies = preload("res://scripts/adaptive_lab/body_plans.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const AdaptiveFighter = preload("res://scripts/adaptive_lab/adaptive_fighter.gd")
const DT := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var pilgrim := Bodies.build("pilgrim")
	var corrupted := Bodies.build("corrupted")
	var misses := 0
	var cases := 0
	for id: String in Gen.recipe_ids():
		var d := Gen.generate(id, int(Gen.recipe(id).seeds[0]))
		var caps := Solver.solve(d, pilgrim)
		if caps.heavy == null:
			continue
		var target := Gen.generate(Gen.recipe_ids()[0], int(Gen.recipe(Gen.recipe_ids()[0]).seeds[0]))
		var target_caps := Solver.solve(target, corrupted)
		var distance := 0.9
		while distance <= 2.31:
			var a := AdaptiveFighter.new("player")
			var b := AdaptiveFighter.new("soul")
			a.equip(d, pilgrim, caps)
			b.equip(target, corrupted, target_caps)
			a.position = Vector3(0, 0, distance * 0.5)
			b.position = Vector3(0, 0, -distance * 0.5)
			b.yaw = PI
			var closest := INF
			var start_z := a.position.z
			var outcome := "whiff"
			for t in range(120):
				a.step({"heavy": t == 0}, b.position, DT)
				b.step({}, a.position, DT)
				AdaptiveFighter.separate(a, b)
				if a.state == "attack" and a.state_time >= float(a.action.windup) and a.state_time <= float(a.action.windup) + float(a.action.active):
					var cap: Array = a.contact_at(a.state_time)
					var body: Array = b.body_capsule()
					closest = minf(closest, AdaptiveFighter.segment_segment(cap[0], cap[1], body[0], body[1]) - float(cap[2]) - float(body[2]))
				var r := AdaptiveFighter.resolve(a, b, DT)
				if not r.is_empty():
					outcome = r.outcome
			var travelled := start_z - a.position.z
			cases += 1
			misses += int(outcome == "whiff")
			print(JSON.stringify({"object": id, "distance": snappedf(distance, 0.01), "heavy": caps.heavy.id, "reach": caps.heavy.get("reach", 0.0),
				"footwork_m": snappedf(travelled, 0.001), "closest_gap_m": snappedf(closest, 0.001), "outcome": outcome}))
			distance += 0.2
	print(JSON.stringify({"suite": "lab1_heavy_diagnostic", "summary": true, "cases": cases, "whiffs": misses}))
	quit(0)
