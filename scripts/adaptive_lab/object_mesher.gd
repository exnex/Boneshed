extends RefCounted
## Builds the visible mesh of a structural object directly from its descriptor, in the
## descriptor's own object frame: a rod is drawn with its radius from a to b, a plate
## with its length, width and thickness about its centre, a lump with its radii, a
## spike tapering to its tip. Sharpened edges (sharpness ≥ the analysis threshold)
## get a bright bevel strip, so what reads as "sharp" is what the rules treat as an
## edge. Nothing is scaled or offset afterwards, so the object node's transform is
## the rules' object transform.
##
## A membrane is a child node ("Canopy") whose openness the presentation animates; the
## folded and opened shapes use the descriptor's folded and open radii.

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")
const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")

## Returns {node: Node3D, canopy: Node3D or null, triangles: int}.
static func build(descriptor: Dictionary) -> Dictionary:
	var mats: Dictionary = Gen.materials()
	var kit := MeshKit.new(false)
	var root := Node3D.new()
	root.name = "Object"
	var canopy: Node3D = null
	var triangles := 0
	for part: Dictionary in descriptor.parts:
		var visual: String = mats[part.material].visual
		match str(part.kind):
			"rod":
				var r: float = part.radius
				kit.tube(visual, Analysis.v(part.a), Analysis.v(part.b), r, r, {}, 10)
				# Close each rod end with a small sphere so joints and hook bends stay solid.
				for end: Vector3 in [Analysis.v(part.a), Analysis.v(part.b)]:
					kit.blob(visual, Transform3D(Basis.IDENTITY, end), Vector3.ONE * r, {}, 8, 5)
			"spike":
				kit.tube(visual, Analysis.v(part.a), Analysis.v(part.b), float(part.radius), 0.0012, {}, 10)
			"plate":
				var u := Analysis.v(part.u)
				var w := Analysis.v(part.v)
				var n := Analysis.v(part.n)
				var xf := Transform3D(Basis(w, u, n), Analysis.v(part.center))
				kit.box(visual, xf, Vector3(float(part.width), float(part.length), float(part.thickness)), {})
				var hardness: float = mats[part.material].hardness
				var half_l := float(part.length) * 0.5
				var half_w := float(part.width) * 0.5
				if float(part.bevel_distal) * hardness >= Analysis.SHARP_MIN:
					kit.box("steel", Transform3D(Basis(w, u, n), Analysis.v(part.center) + u * (half_l - 0.006)),
						Vector3(float(part.width) * 0.98, 0.012, float(part.thickness) * 1.3), {})
				if float(part.bevel_lateral) * hardness >= Analysis.SHARP_MIN:
					for side: float in [-1.0, 1.0]:
						kit.box("steel", Transform3D(Basis(w, u, n), Analysis.v(part.center) + w * side * (half_w - 0.006)),
							Vector3(0.012, float(part.length) * 0.95, float(part.thickness) * 1.3), {})
			"lump":
				var basis := Analysis._lump_basis(part)
				var bumpy := func(unit: Vector3) -> float: return 1.0 + 0.05 * sin(unit.x * 9.0 + unit.y * 5.0) * cos(unit.z * 7.0)
				kit.blob(visual, Transform3D(basis, Analysis.v(part.center)), Analysis.v(part.radii), {}, 16, 10, 2.0, bumpy)
			"membrane":
				canopy = _canopy(part, mats)
	if not kit.is_empty():
		var instance := MeshInstance3D.new()
		instance.name = "Structure"
		instance.mesh = kit.commit()
		root.add_child(instance)
		triangles += kit.triangle_count
	if canopy != null:
		root.add_child(canopy)
		for child: Node in canopy.get_children():
			triangles += int(child.get_meta("triangles", 0))
	return {"node": root, "canopy": canopy, "triangles": triangles}

## Canopy node: local +Y runs from the membrane's a to b. "Folded" is the furled
## bundle; "Open" is the deployed cone (apex at b), scaled radially by openness.
static func _canopy(part: Dictionary, mats: Dictionary) -> Node3D:
	var a := Analysis.v(part.a)
	var b := Analysis.v(part.b)
	var length := a.distance_to(b)
	var node := Node3D.new()
	node.name = "Canopy"
	node.transform = Transform3D(MeshKit.basis_from_y((b - a).normalized()), a)
	node.set_meta("open_radius", float(part.open_radius))
	node.set_meta("folded_radius", float(part.folded_radius))
	var cloth: String = mats[part.material].visual
	var rib: String = mats[part.rib_material].visual
	var folded := MeshKit.new(false)
	var fr: float = part.folded_radius
	var rings: Array = []
	for entry: Array in [[0.0, 0.35], [0.25, 0.85], [0.6, 1.0], [0.85, 0.8], [1.0, 0.12]]:
		var c := Vector3(0.0, length * float(entry[0]), 0.0)
		var wobble := func(angle: float) -> float: return 1.0 + 0.12 * sin(angle * float(int(part.ribs)))
		rings.append({"c": c, "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": fr * float(entry[1]), "rz": fr * float(entry[1]), "w": {}, "shape": wobble})
	folded.loft(cloth, rings, 16, true, true)
	var open := MeshKit.new(false)
	var radius: float = part.open_radius
	var rim_y := length * 0.5
	var open_rings: Array = []
	for entry: Array in [[1.0, 0.0], [0.86, 0.45], [0.7, 0.8], [0.5, 1.0]]:
		var t := float(entry[0])
		var c := Vector3(0.0, lerpf(rim_y, length, (t - 0.5) / 0.5), 0.0)
		var scallop := func(angle: float) -> float: return 1.0 - 0.06 * absf(sin(angle * float(int(part.ribs)) * 0.5))
		open_rings.append({"c": c, "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": maxf(0.004, radius * float(entry[1])),
			"rz": maxf(0.004, radius * float(entry[1])), "w": {}, "shape": scallop})
	open.loft(cloth, open_rings, int(part.ribs) * 4, false, false)
	for i in range(int(part.ribs)):
		var angle := TAU * float(i) / int(part.ribs)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var previous := Vector3(0.0, length, 0.0)
		for entry: Array in [[0.86, 0.45], [0.7, 0.8], [0.5, 1.0]]:
			var t := float(entry[0])
			var p := Vector3(0.0, lerpf(rim_y, length, (t - 0.5) / 0.5), 0.0) + out * radius * float(entry[1]) * 1.01
			open.tube(rib, previous, p, 0.003, 0.003, {}, 5, false)
			previous = p
	for entry: Array in [["Folded", folded], ["Open", open]]:
		var kit: MeshKit = entry[1]
		var instance := MeshInstance3D.new()
		instance.name = entry[0]
		instance.mesh = kit.commit()
		instance.set_meta("triangles", kit.triangle_count)
		node.add_child(instance)
	set_openness(node, 0.0)
	return node

## 0 = furled, 1 = fully deployed. Matches the guard's coverage radius in the rules.
static func set_openness(canopy: Node3D, openness: float) -> void:
	var folded: MeshInstance3D = canopy.get_node("Folded")
	var open: MeshInstance3D = canopy.get_node("Open")
	var ratio: float = float(canopy.get_meta("folded_radius")) / float(canopy.get_meta("open_radius"))
	var s := lerpf(ratio, 1.0, clampf(openness, 0.0, 1.0))
	open.visible = openness > 0.02
	folded.visible = openness < 0.6
	open.scale = Vector3(s, 1.0, s)
