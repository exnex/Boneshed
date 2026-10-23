extends RefCounted
## Draws an imported Research Lab object (lab_import.gd) from its converted parts, in
## the object's own frame (metres, +Y up, −Z forward — the Lab's frame), so the object
## node's transform is the rules' object transform:
##   box        exact full-size box;
##   rod        elliptical cylinder along its cardinal axis with both transverse radii;
##   cone       elliptical cone, base at the negative axial end, point at the positive;
##   ellipsoid  unit sphere scaled to the three half-sizes.
## Colours come from each material's `color_rgb` (presentation only); stiff materials
## get a metallic sheen, compliant ones a matte cloth look — from the physical
## stiffness, never from a material's id or name.
## Unlocked hinge / flex parts are built under their own pivot node at the joint
## anchor; the actor swings them within the joint limits (presentation only).

const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")
const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const SEGMENTS := 14

## Returns {node: Node3D, canopy: null, articulated: [{node, axis, limits, anchor}], triangles: int}.
static func build(obj: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Object"
	var kit := MeshKit.new(false)
	var articulated: Array = []
	var triangles := 0
	for p: Dictionary in obj.parts:
		if p.articulated:
			var pivot := Node3D.new()
			pivot.name = "Joint_" + str(p.id)
			pivot.position = p.anchor
			pivot.set_meta("part", p.id)
			var sub := MeshKit.new(false)
			sub.base = Transform3D(Basis.IDENTITY, -(p.anchor as Vector3))
			_part(sub, p)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = _commit(sub, obj.materials)
			pivot.add_child(mi)
			root.add_child(pivot)
			triangles += sub.triangle_count
			articulated.append({"node": pivot, "axis": p.joint_axis, "limits": p.limits, "anchor": p.anchor, "part": p.id})
		else:
			_part(kit, p)
	if not kit.is_empty():
		var instance := MeshInstance3D.new()
		instance.name = "Structure"
		instance.mesh = _commit(kit, obj.materials)
		root.add_child(instance)
		triangles += kit.triangle_count
	return {"node": root, "canopy": null, "articulated": articulated, "triangles": triangles}

static func _part(kit: MeshKit, p: Dictionary) -> void:
	var material: String = p.material
	var c: Vector3 = p.center
	var size: Vector3 = p.size
	match str(p.shape):
		"box":
			kit.box(material, Transform3D(Basis.IDENTITY, c), size, {})
		"rod", "cone":
			var t: Array = p.transverse_axes
			var x := Imp.axis_vector(t[0])
			var z := Imp.axis_vector(t[1])
			var r: Vector2 = p.radii
			var tip := 0.0008 if p.shape == "cone" else 1.0
			var rings := []
			for i in range(2):
				var k := tip if (p.shape == "cone" and i == 1) else 1.0
				rings.append({"c": p.a if i == 0 else p.b, "x": x, "z": z, "rx": maxf(r.x * k, 0.0005), "rz": maxf(r.y * k, 0.0005), "w": {}})
			kit.loft(material, rings, SEGMENTS, true, true)
		"ellipsoid":
			kit.blob(material, Transform3D(Basis.IDENTITY, c), size * 0.5, {}, 18, 12)

static func _commit(kit: MeshKit, materials: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var ids: Array = kit._surfaces.keys()
	ids.sort()
	for id: String in ids:
		var st: SurfaceTool = kit._surfaces[id].st
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material_for(materials[id]))
	return mesh

## Presentation material from colour and stiffness (no name lookup).
static func material_for(m: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = m.color
	var stiff := clampf(log(maxf(float(m.stiffness_mpa), 1.0)) / log(200000.0), 0.0, 1.0)
	mat.metallic = 0.75 if stiff > 0.95 else 0.0
	mat.roughness = lerpf(0.95, 0.35, stiff)
	if not m.rigid_material:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
