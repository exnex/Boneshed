extends RefCounted
## Weapon meshes for the visual showcase. Local frame = the melee lab's weapon frame:
## origin at the primary grip (the rules `hand` point), blade along −Z, and the tip at
## exactly z = −length, where `length` is the rules handling length. The contact
## segment hand → tip is therefore the drawn grip → tip line; nothing is rescaled.
##
## Each weapon also gets thin edge strips with its own material: the presentation
## lights them with the lab's telegraph colours (direction, live, guard) instead of
## recolouring the whole blade.
##
## Visual class is chosen from the item id (shared catalog / lab data); handling
## numbers come from weapon_handling.gd, never from this file.

const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
## Offset of the second hand behind the primary grip (+Z, toward the pommel). The lab
## draws its second hand 0.2 m toward the blade; at the end of a cross-body cut that
## point is ~0.9 m from the left shoulder, beyond a human arm. The pommel-side grip is
## the anatomical two-handed grip. The hilt behind the primary fist is not part of the
## contact segment (hand → tip), exactly as the lab's own pommel is not.
const SECOND_HAND := 0.2

const STYLES := {
	"item.lab_long_knife": "knife", "item.lab_venom_knife": "venom_knife", "item.notched_sword": "sword",
	"item.lab_greatsword": "greatsword", "item.lab_quarterstaff": "staff",
}

static func style_for(item: String) -> String:
	return STYLES.get(item, "sword")

## Returns {"node": Node3D, "edge": StandardMaterial3D, "triangles": int, "style": String,
## "tip": Vector3 (local), "second_grip": Vector3 or null}.
static func build(item: String, length: float, two_handed: bool, rusted: bool) -> Dictionary:
	var style := style_for(item)
	var kit := MeshKit.new(false)
	var steel := "steel_dark" if rusted else "steel"
	var grip_mat := "wood_grip"
	var trim := "iron_black" if rusted else "bronze"
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("c8d0cc")
	edge.metallic = 0.9
	edge.roughness = 0.25
	edge.emission_enabled = true
	edge.emission = Color.BLACK
	edge.emission_energy_multiplier = 0.0
	var edge_kit := MeshKit.new(false)
	var guard_z := -0.065
	var handle_end := 0.065
	if two_handed:
		handle_end = SECOND_HAND + 0.07
	match style:
		"staff":
			_staff(kit, length, trim)
		_:
			var widths := {"knife": [0.05, 0.034], "venom_knife": [0.05, 0.034], "sword": [0.056, 0.034], "greatsword": [0.08, 0.05]}
			var thick := {"knife": 0.009, "venom_knife": 0.009, "sword": 0.008, "greatsword": 0.011}
			var w: Array = widths.get(style, [0.05, 0.03])
			var blade_start := guard_z - 0.012
			_handle(kit, grip_mat, handle_end, guard_z + 0.012, 0.016 if not two_handed else 0.018)
			_pommel(kit, trim if style != "greatsword" else steel, handle_end)
			_crossguard(kit, trim if style != "greatsword" else steel, guard_z, style)
			if style == "greatsword":
				# Ricasso: an unsharpened stretch above the guard, then parrying lugs.
				_blade(kit, edge_kit, steel, blade_start, -length, w[0], w[1], thick[style], style, rusted)
				kit.blob(steel, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, blade_start - 0.2)), Vector3(0.06, 0.01, 0.012), {}, 8, 4, 2.6)
			else:
				_blade(kit, edge_kit, steel, blade_start, -length, w[0], w[1], thick[style], style, rusted)
	var node := Node3D.new()
	node.name = "Weapon"
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = kit.commit()
	node.add_child(instance)
	var triangles := kit.triangle_count
	if not edge_kit.is_empty():
		var edges := MeshInstance3D.new()
		edges.name = "Edge"
		var edge_mesh := edge_kit.commit()
		for i in range(edge_mesh.get_surface_count()):
			edge_mesh.surface_set_material(i, edge)
		edges.mesh = edge_mesh
		edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(edges)
		triangles += edge_kit.triangle_count
	var tip_marker := Marker3D.new()
	tip_marker.name = "tip"
	tip_marker.position = Vector3(0.0, 0.0, -length)
	node.add_child(tip_marker)
	return {"node": node, "edge": edge, "triangles": triangles, "style": style, "tip": Vector3(0.0, 0.0, -length),
		"second_grip": Vector3(0.0, 0.0, SECOND_HAND) if two_handed else null}

static func _handle(kit: MeshKit, material: String, back: float, front: float, radius: float) -> void:
	var rings: Array = []
	var steps := 6
	for i in range(steps + 1):
		var z := lerpf(back, front, float(i) / steps)
		var bulge := 1.0 + 0.12 * sin(PI * float(i) / steps)
		rings.append({"c": Vector3(0.0, 0.0, z), "x": Vector3.RIGHT, "z": Vector3.UP, "rx": radius * bulge, "rz": radius * 0.85 * bulge, "w": {}})
	kit.loft(material, rings, 10, false, false, false, 3.0)

static func _pommel(kit: MeshKit, material: String, z: float) -> void:
	kit.blob(material, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z + 0.022)), Vector3(0.028, 0.022, 0.026), {}, 12, 8, 2.4)

static func _crossguard(kit: MeshKit, material: String, z: float, style: String) -> void:
	var half := {"knife": 0.045, "venom_knife": 0.045, "sword": 0.11, "greatsword": 0.16}.get(style, 0.1) as float
	# A bar that thickens toward slightly down-swept quillon tips.
	var rings: Array = []
	for i in range(7):
		var t := float(i) / 6.0
		var x := lerpf(-half, half, t)
		var droop := 0.012 * pow(absf(t - 0.5) * 2.0, 2.0)
		var r := lerpf(0.011, 0.016, pow(absf(t - 0.5) * 2.0, 3.0))
		rings.append({"c": Vector3(x, 0.0, z + droop), "x": Vector3.UP, "z": Vector3.BACK, "rx": r, "rz": r * 0.8, "w": {}})
	kit.loft(material, rings, 8, true, true)
	kit.blob(material, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)), Vector3(0.025, 0.02, 0.02), {}, 10, 6, 2.6)

## Hexagonal-section blade (flat faces with bevelled edges) tapering to the tip, with
## a fuller groove suggested by a darker inset strip and edge strips for telegraphs.
static func _blade(kit: MeshKit, edge_kit: MeshKit, steel: String, from: float, to: float, base_width: float, tip_width: float,
		thickness: float, style: String, rusted: bool) -> void:
	var rings: Array = []
	var steps := 14
	var single_edge := style in ["knife", "venom_knife"]
	for i in range(steps + 1):
		var t := float(i) / steps
		var z := lerpf(from, to, t)
		var half := lerpf(base_width, tip_width, t) * 0.5
		if t > 0.82:
			half *= 1.0 - smoothstep(0.82, 1.0, t)
		if single_edge:
			# Seax profile: broken back, curved belly.
			half *= 1.0 + 0.15 * sin(PI * t)
		var thick := thickness * 0.5 * (1.0 - 0.5 * t)
		var notch := style == "sword" and i in [4, 7, 10]
		rings.append({"c": Vector3(0.0, 0.0, z), "x": Vector3.RIGHT, "z": Vector3.UP, "rx": maxf(half, 0.0005), "rz": maxf(thick, 0.0004),
			"w": {}, "shape": _blade_section.bind(0.84 if notch else 1.0), "notch": notch})
	kit.loft(steel, rings, 6, true, false, false, 2.0)
	# Edge strips (both edges; knife: back is unsharpened, still drawn for readability).
	for side: float in [-1.0, 1.0]:
		var strip: Array = []
		for i in range(steps + 1):
			var ring: Dictionary = rings[i]
			var half: float = ring.rx * (0.84 if ring.notch and side > 0.0 else 1.0)
			strip.append({"c": ring.c + Vector3(side * half * 0.97, 0.0, 0.0), "x": Vector3.RIGHT, "z": Vector3.UP,
				"rx": 0.0028, "rz": maxf(ring.rz * 0.6, 0.0006), "w": {}})
		edge_kit.loft("steel", strip, 4, false, true)
	# Fuller: a darker narrow strip on both faces of the forte.
	if not single_edge:
		for face: float in [-1.0, 1.0]:
			var length := absf(to - from)
			var start := Vector3(0.0, face * thickness * 0.5 * 0.92, from - 0.02)
			kit.box("steel_dark" if not rusted else "iron_black", Transform3D(Basis.IDENTITY, start + Vector3(0.0, 0.0, -length * 0.3)),
				Vector3(base_width * 0.18, 0.0015, length * 0.58), {})

static func _blade_section(angle: float, notch: float) -> float:
	# Six vertices: two edges (±x) and four bevel shoulders. Flatten the faces.
	var c := absf(cos(angle))
	return (1.0 if c > 0.99 else 0.62) * (notch if c > 0.99 and cos(angle) > 0.0 else 1.0)

static func _staff(kit: MeshKit, length: float, trim: String) -> void:
	var rings: Array = []
	for i in range(9):
		var t := float(i) / 8.0
		var z := lerpf(0.35, -length, t)
		var r := 0.019 * (1.0 + 0.06 * sin(t * 23.0))
		rings.append({"c": Vector3(0.0, 0.0, z), "x": Vector3.RIGHT, "z": Vector3.UP, "rx": r, "rz": r, "w": {}})
	kit.loft("wood_grip", rings, 10, true, true, false, 0.5)
	for z: float in [0.31, -length + 0.04, -length * 0.5 + 0.05]:
		kit.tube(trim, Vector3(0.0, 0.0, z + 0.04), Vector3(0.0, 0.0, z - 0.04), 0.022, 0.022, {}, 10)
