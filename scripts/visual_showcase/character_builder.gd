extends RefCounted
## Builds a showcase character: Skeleton3D (humanoid_rig.gd), a skinned body, an
## optional skinned armor layer per armor id, and the Marrow Arm module. Original
## procedural geometry; no imported assets.
##
## Modular hierarchy (one node per layer, each one draw call per material):
##   Character (Node3D)
##     Skeleton3D ── socket_* (BoneAttachment3D → Marker3D "point")
##       Body      (MeshInstance3D, skin = rest binds)
##       Armor     (MeshInstance3D, only when an armor id is equipped)
##       Module    (MeshInstance3D, Marrow Arm, only when equipped)
##
## Deformation strategy: skin, cloth and mail blend neighbouring bones (elbows, knees,
## waist, shoulders); every plate, buckle, bone and helm is bound 100 % to one bone so
## hard surfaces never bend; skirts split their weights by side between pelvis and
## the matching thigh so a stride drags the hem instead of tearing it.

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")

## Look per (body kind, armor id). Armor ids are the lab's data ids; the look adds
## nothing to the rules (combat_resources.gd derives mass, mitigation and resistances).
const ARMOR_IDS := ["armor.lab_cloth_wraps", "armor.lab_mail_shirt", "armor.lab_bog_iron_plate"]

var p: Dictionary
var kind: String
var j: Dictionary
var rest: Dictionary
var corrupted: bool

func _init(proportions: Dictionary, body_kind: String) -> void:
	p = proportions
	kind = body_kind
	corrupted = body_kind == "corrupted"
	j = Rig.joints(p)
	rest = Rig.rest_globals(p)

static func w(bone: String) -> Dictionary:
	return {Rig.bone_index(bone): 1.0}

static func mix(a: String, b: String, t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	if a == b:
		return w(a)
	return {Rig.bone_index(a): 1.0 - t, Rig.bone_index(b): t}

## Builds the whole character. spec: {armor: Array[String], marrow_arm: bool}.
## Returns {"root": Node3D, "skeleton": Skeleton3D, "triangles": int, "layers": {name: MeshInstance3D}}.
func build(spec: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Character"
	var skeleton := Rig.build_skeleton(p)
	root.add_child(skeleton)
	var skin := skeleton.create_skin_from_rest_transforms()
	var marrow: bool = spec.get("marrow_arm", false)
	var armor: Array = spec.get("armor", [])
	var layers := {}
	var triangles := 0
	var body := MeshKit.new()
	body_layer(body, marrow, armor)
	var pieces := [["Body", body]]
	for armor_id: String in armor:
		var kit := MeshKit.new()
		armor_layer(kit, armor_id, marrow)
		pieces.append(["Armor_" + armor_id.get_slice(".", 1), kit])
	if marrow:
		var module := MeshKit.new()
		marrow_arm(module)
		pieces.append(["Module_marrow_arm", module])
	for piece: Array in pieces:
		var kit: MeshKit = piece[1]
		if kit.is_empty():
			continue
		var instance := MeshInstance3D.new()
		instance.name = piece[0]
		instance.mesh = kit.commit()
		instance.skin = skin
		instance.skeleton = NodePath("..")
		skeleton.add_child(instance)
		layers[piece[0]] = instance
		triangles += kit.triangle_count
	return {"root": root, "skeleton": skeleton, "triangles": triangles, "layers": layers}

## --- Body -----------------------------------------------------------------------

func body_layer(kit: MeshKit, marrow: bool, armor: Array) -> void:
	var g: float = p.girth
	var dress := "skin_corrupted" if corrupted else "cloth_dark"
	var skin := "skin_corrupted" if corrupted else "skin_pilgrim"
	_torso(kit, "skin_corrupted" if corrupted else "cloth_dark", 1.0)
	for side: String in ["l", "r"]:
		if not (marrow and side == "l"):
			_arm(kit, side, dress, 1.0)
			_fist(kit, side, "skin_corrupted" if corrupted else "leather", 1.0)
		_leg(kit, side, "cloth_tattered" if corrupted else "cloth_dark", 1.0)
		_foot(kit, side, "skin_corrupted" if corrupted else "leather", 1.0)
		if not corrupted:
			_boot_shaft(kit, side)
	_neck(kit, skin)
	_head(kit, skin)
	if corrupted:
		_ribs(kit)
		_spurs(kit)
		_shroud(kit)
		_skirt(kit, "cloth_tattered", 0.42, 1.12, true)
		if marrow:
			_deltoid_stump(kit)
	else:
		_belt(kit, "leather", 1.05)
		var helmeted := "armor.lab_bog_iron_plate" in armor or "armor.lab_mail_shirt" in armor
		if not helmeted:
			_hood(kit, "cloth_robe")
			_mantle(kit, "cloth_robe")

## Torso cross-section table: [height fraction from hip to neck, half width, half depth].
const TORSO := [[-0.12, 0.15, 0.10], [-0.04, 0.17, 0.115], [0.06, 0.162, 0.108], [0.16, 0.142, 0.1], [0.3, 0.152, 0.105],
	[0.44, 0.168, 0.112], [0.58, 0.178, 0.112], [0.7, 0.18, 0.105], [0.8, 0.17, 0.09], [0.88, 0.13, 0.07], [0.95, 0.07, 0.055]]

func _torso_ring(f: float, half_width: float, half_depth: float, scale: float) -> Dictionary:
	var hip_y: float = j.thigh_l.y
	var neck_y: float = j.neck_01.y
	var y := lerpf(hip_y, neck_y, f)
	var z := _spine_z(y)
	var g: float = p.girth
	var ring := {"c": Vector3(0.0, y, z), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": half_width * scale * lerpf(g, 1.0, 0.4),
		"rz": half_depth * scale * g, "shape": _boxy.bind(2.6), "w": _spine_weights(y)}
	if f < 0.0:
		ring.wfn = _crotch_weights.bind(y, f)
	return ring

func _spine_z(y: float) -> float:
	var chain := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
	for i in range(chain.size() - 1):
		var a: Vector3 = j[chain[i]]
		var b: Vector3 = j[chain[i + 1]]
		if y <= b.y:
			return lerpf(a.z, b.z, clampf(inverse_lerp(a.y, b.y, y), 0.0, 1.0))
	return (j.neck_01 as Vector3).z

## Weights along the spine, blending between bone centres.
func _spine_weights(y: float) -> Dictionary:
	var centres := [["pelvis", (j.pelvis.y + j.spine_01.y) * 0.5 - 0.04], ["spine_01", (j.spine_01.y + j.spine_02.y) * 0.5],
		["spine_02", (j.spine_02.y + j.spine_03.y) * 0.5], ["spine_03", (j.spine_03.y + j.neck_01.y) * 0.5], ["neck_01", j.neck_01.y + 0.05]]
	if y <= centres[0][1]:
		return w("pelvis")
	for i in range(centres.size() - 1):
		if y <= centres[i + 1][1]:
			return mix(centres[i][0], centres[i + 1][0], inverse_lerp(centres[i][1], centres[i + 1][1], y))
	return w("neck_01")

func _crotch_weights(angle: float, y: float, f: float) -> Dictionary:
	var side := cos(angle)
	var t := clampf(-f / 0.12, 0.0, 1.0) * absf(side) * 0.7
	var thigh := "thigh_r" if side > 0.0 else "thigh_l"
	return {Rig.bone_index("pelvis"): 1.0 - t, Rig.bone_index(thigh): t}

static func _boxy(angle: float, n: float) -> float:
	return 1.0 / pow(pow(absf(cos(angle)), n) + pow(absf(sin(angle)), n), 1.0 / n)

func _torso(kit: MeshKit, material: String, scale: float, from := 0, to := -1) -> void:
	var rings: Array = []
	var last := TORSO.size() - 1 if to < 0 else to
	for i in range(from, last + 1):
		rings.append(_torso_ring(TORSO[i][0], TORSO[i][1], TORSO[i][2], scale))
	kit.loft(material, rings, 20, from == 0, false)

func _arm(kit: MeshKit, side: String, material: String, scale: float, from := 0.0, to := 1.0) -> void:
	var shoulder: Vector3 = j["upperarm_" + side]
	var elbow: Vector3 = j["lowerarm_" + side]
	var wrist: Vector3 = j["hand_" + side]
	var g: float = p.girth
	# [t along shoulder→wrist (0..1 by bone, upper then lower), radius]
	var profile := [[-0.08, 0.05], [0.0, 0.058], [0.18, 0.056], [0.5, 0.047], [0.85, 0.041], [1.0, 0.038],
		[1.25, 0.044], [1.5, 0.041], [1.8, 0.034], [2.0, 0.029]]
	var rings: Array = []
	for entry: Array in profile:
		var t: float = entry[0]
		if t < from * 2.0 - 0.001 or t > to * 2.0 + 0.001:
			continue
		var c: Vector3 = shoulder.lerp(elbow, t) if t <= 1.0 else elbow.lerp(wrist, t - 1.0)
		var axis: Vector3 = (elbow - shoulder).normalized() if t <= 1.0 else (wrist - elbow).normalized()
		var basis := MeshKit.basis_from_y(axis)
		var weights: Dictionary
		if t < 0.0:
			weights = {Rig.bone_index("upperarm_" + side): 0.55, Rig.bone_index("clavicle_" + side): 0.45}
		elif t < 0.85:
			weights = w("upperarm_" + side)
		elif t <= 1.25:
			weights = mix("upperarm_" + side, "lowerarm_" + side, inverse_lerp(0.85, 1.25, t))
		elif t < 1.9:
			weights = w("lowerarm_" + side)
		else:
			weights = mix("lowerarm_" + side, "hand_" + side, 0.3)
		var radius: float = entry[1] * g * scale
		rings.append({"c": c, "x": basis.x, "z": basis.z, "rx": radius, "rz": radius * 0.9, "w": weights})
	kit.loft(material, rings, 14, true, true)
	if from <= 0.0:
		# Deltoid cap over the shoulder joint.
		var cap := Transform3D(MeshKit.basis_from_y((elbow - shoulder).normalized()), shoulder + Vector3(0.0, 0.01, 0.0))
		kit.blob(material, cap, Vector3(0.062, 0.085, 0.06) * g * scale, {Rig.bone_index("upperarm_" + side): 0.75, Rig.bone_index("clavicle_" + side): 0.25}, 12, 8)

## Closed fist around the grip socket; the handle axis is the hand's local Z.
func _fist(kit: MeshKit, side: String, material: String, scale: float) -> void:
	var hand: Transform3D = rest["hand_" + side]
	var x := 1.0 if side == "r" else -1.0
	kit.blob(material, hand * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.045, 0.0)), Vector3(0.042, 0.055, 0.035) * scale, w("hand_" + side), 12, 8, 2.8)
	# Curled fingers as a rounded roll around the handle, thumb along it.
	kit.blob(material, hand * Transform3D(Basis.IDENTITY, Vector3(-x * 0.012, 0.085, 0.0)), Vector3(0.03, 0.025, 0.04) * scale, w("hand_" + side), 10, 6, 2.6)
	kit.tube(material, hand * Vector3(x * 0.03, 0.03, -0.01), hand * Vector3(x * 0.022, 0.075, -0.035), 0.013 * scale, 0.011 * scale, w("hand_" + side), 6)

func _leg(kit: MeshKit, side: String, material: String, scale: float, from := 0.0, to := 2.0) -> void:
	var hip: Vector3 = j["thigh_" + side]
	var knee: Vector3 = j["calf_" + side]
	var ankle: Vector3 = j["foot_" + side]
	var g: float = p.girth
	var profile := [[0.0, 0.088], [0.3, 0.08], [0.7, 0.064], [0.95, 0.052], [1.05, 0.05], [1.3, 0.058], [1.6, 0.047], [1.9, 0.038], [2.0, 0.036]]
	var rings: Array = []
	for entry: Array in profile:
		var t: float = entry[0]
		if t < from - 0.001 or t > to + 0.001:
			continue
		var c: Vector3 = hip.lerp(knee, t) if t <= 1.0 else knee.lerp(ankle, t - 1.0)
		var axis: Vector3 = (knee - hip).normalized() if t <= 1.0 else (ankle - knee).normalized()
		var basis := MeshKit.basis_from_y(axis)
		var weights: Dictionary
		if t <= 0.0:
			weights = {Rig.bone_index("thigh_" + side): 0.6, Rig.bone_index("pelvis"): 0.4}
		elif t < 0.9:
			weights = w("thigh_" + side)
		elif t <= 1.1:
			weights = mix("thigh_" + side, "calf_" + side, inverse_lerp(0.9, 1.1, t))
		elif t < 1.95:
			weights = w("calf_" + side)
		else:
			weights = mix("calf_" + side, "foot_" + side, 0.4)
		var radius: float = entry[1] * lerpf(g, 1.0, 0.3) * scale
		rings.append({"c": c, "x": basis.x, "z": basis.z, "rx": radius, "rz": radius * 1.05, "w": weights})
	kit.loft(material, rings, 14, true, true)

func _foot(kit: MeshKit, side: String, material: String, scale: float) -> void:
	var ankle: Vector3 = j["foot_" + side]
	var ball: Vector3 = j["ball_" + side]
	var centre := Vector3(ankle.x, 0.055, (ankle.z + ball.z) * 0.5 - 0.01)
	var foot_bone := Rig.bone_index("foot_" + side)
	var ball_bone := Rig.bone_index("ball_" + side)
	var split: float = ball.z - centre.z
	kit.blob(material, Transform3D(Basis.IDENTITY, centre), Vector3(0.05, 0.055, 0.135) * scale, {}, 14, 8, 2.6,
		func(u: Vector3) -> float: return 0.8 if u.y < -0.2 else 1.0,
		func(q: Vector3) -> Dictionary:
			var t := clampf(inverse_lerp(split + 0.03, split - 0.02, q.z), 0.0, 1.0)
			return {foot_bone: 1.0 - t, ball_bone: t})

func _boot_shaft(kit: MeshKit, side: String) -> void:
	_leg(kit, side, "leather", 1.18, 1.55, 2.0)

func _neck(kit: MeshKit, material: String) -> void:
	var a: Vector3 = j.neck_01
	var b: Vector3 = j.head + Vector3(0.0, 0.03, 0.0)
	var r := 0.055 * lerpf(p.girth, 1.0, 0.5)
	var basis := MeshKit.basis_from_y((b - a).normalized())
	kit.loft(material, [
		{"c": a - (b - a) * 0.4, "x": basis.x, "z": basis.z, "rx": r * 1.3, "rz": r * 1.1, "w": mix("spine_03", "neck_01", 0.4)},
		{"c": a, "x": basis.x, "z": basis.z, "rx": r, "rz": r, "w": w("neck_01")},
		{"c": b, "x": basis.x, "z": basis.z, "rx": r * 0.92, "rz": r * 0.95, "w": mix("neck_01", "head", 0.7)}], 12, false, false)

func _head(kit: MeshKit, material: String) -> void:
	var centre: Vector3 = j.head + Vector3(0.0, 0.085, -0.012)
	var xf := Transform3D(Basis.IDENTITY, centre)
	var gaunt := corrupted
	kit.blob(material, xf, Vector3(0.078, 0.112, 0.098), w("head"), 20, 14, 2.0, func(u: Vector3) -> float:
		var m := 1.0
		# Jaw and chin narrow toward the front and bottom.
		if u.y < -0.1:
			m *= 1.0 - 0.28 * smoothstep(-0.1, -0.9, u.y) * (0.6 + 0.4 * absf(u.x))
		# Back of the skull.
		if u.z > 0.2 and u.y > -0.2:
			m *= 1.0 + 0.08 * u.z
		# Brow ridge and nose.
		if u.z < -0.6:
			m *= 1.0 + 0.06 * exp(-pow((u.y - 0.25) / 0.12, 2.0))
			if not gaunt:
				m *= 1.0 + 0.16 * exp(-pow(u.x / 0.12, 2.0) - pow((u.y + 0.05) / 0.18, 2.0))
		# Eye sockets (deep and hollow on the corrupted).
		for ex: float in [-0.38, 0.38]:
			var d := pow((u.x - ex) / 0.17, 2.0) + pow((u.y - 0.12) / 0.12, 2.0)
			if u.z < -0.4:
				m *= 1.0 - (0.16 if gaunt else 0.05) * exp(-d)
		# Cheekbones hollow on the corrupted.
		if gaunt and u.z < -0.2 and u.y < 0.0 and u.y > -0.5:
			m *= 1.0 - 0.08 * absf(u.x)
		return m)
	# Ears.
	for x: float in [-1.0, 1.0]:
		kit.blob(material, Transform3D(Basis.IDENTITY, centre + Vector3(x * 0.077, 0.0, 0.01)), Vector3(0.012, 0.03, 0.02), w("head"), 8, 5)
	if gaunt:
		for x: float in [-1.0, 1.0]:
			kit.blob("eye_glow", Transform3D(Basis.IDENTITY, centre + Vector3(x * 0.03, 0.012, -0.082)), Vector3(0.011, 0.008, 0.008), w("head"), 8, 5)
		# Exposed jaw bone.
		kit.blob("bone", Transform3D(Basis.IDENTITY, centre + Vector3(0.0, -0.075, -0.045)), Vector3(0.05, 0.022, 0.045), w("head"), 12, 6, 2.4)
	else:
		for x: float in [-1.0, 1.0]:
			kit.blob("iron_black", Transform3D(Basis.IDENTITY, centre + Vector3(x * 0.03, 0.012, -0.088)), Vector3(0.012, 0.007, 0.006), w("head"), 8, 5)
		# Close-cropped stubble along the jaw (slightly proud of the skin).
		kit.blob("leather", Transform3D(Basis.IDENTITY, centre + Vector3(0.0, -0.058, -0.03)), Vector3(0.066, 0.042, 0.066), w("head"), 14, 6, 2.0,
			func(u: Vector3) -> float: return 1.0 if u.z < 0.2 and u.y < 0.3 else 0.8)

func _hood(kit: MeshKit, material: String) -> void:
	var centre: Vector3 = j.head + Vector3(0.0, 0.09, 0.0)
	kit.blob(material, Transform3D(Basis.IDENTITY, centre), Vector3(0.1, 0.13, 0.118), w("head"), 20, 14, 2.0, func(u: Vector3) -> float:
		# The face opening: front vertices are pulled behind the face surface; the brow
		# of the hood overhangs it so the face sits in shadow.
		if u.z < -0.45 and u.y < 0.4 and u.y > -0.75:
			return 0.72
		if u.z < -0.3 and u.y >= 0.4:
			return 1.12
		return 1.0 + (0.06 if u.y > 0.5 and u.z > 0.0 else 0.0))

func _mantle(kit: MeshKit, material: String) -> void:
	var rings: Array = []
	var neck: Vector3 = j.neck_01
	for entry: Array in [[0.06, 0.08, 0.075], [-0.02, 0.15, 0.12], [-0.1, 0.235, 0.15], [-0.2, 0.25, 0.16]]:
		var y: float = neck.y + entry[0]
		rings.append({"c": Vector3(0.0, y, _spine_z(y) + 0.005), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": entry[1], "rz": entry[2],
			"shape": func(a: float) -> float: return 1.0 + 0.04 * sin(a * 7.0), "wfn": _mantle_weights.bind(y)})
	kit.loft(material, rings, 22, false, false)

func _mantle_weights(angle: float, y: float) -> Dictionary:
	var side := cos(angle)
	var arm := "upperarm_r" if side > 0.0 else "upperarm_l"
	var t := clampf((absf(side) - 0.6) * 1.2, 0.0, 0.45) * clampf((j.neck_01.y - y) / 0.2, 0.0, 1.0)
	return {Rig.bone_index("spine_03"): 1.0 - t, Rig.bone_index(arm): t}

func _belt(kit: MeshKit, material: String, scale: float) -> void:
	var f := -0.02
	var ring := _torso_ring(f, 0.17, 0.115, scale * 1.06)
	var top := _torso_ring(f + 0.07, 0.165, 0.11, scale * 1.06)
	ring.erase("wfn")
	top.erase("wfn")
	ring.w = w("pelvis")
	top.w = w("pelvis")
	kit.loft(material, [ring, top], 20, false, false)
	var buckle_y: float = (ring.c as Vector3).y + 0.03
	kit.box("bronze", Transform3D(Basis.IDENTITY, Vector3(0.0, buckle_y, _spine_z(buckle_y) - 0.125 * scale)), Vector3(0.05, 0.045, 0.012), w("pelvis"))
	# Pouch on the right hip.
	kit.blob("leather", Transform3D(Basis.IDENTITY, Vector3(0.15, buckle_y - 0.07, 0.04)), Vector3(0.04, 0.055, 0.03), w("pelvis"), 10, 6, 3.0)

## Hanging cloth from the waist; `jagged` tatters the hem. Weights split by side.
func _skirt(kit: MeshKit, material: String, length: float, scale: float, jagged: bool) -> void:
	var top_y: float = j.thigh_l.y + 0.06
	var rings: Array = []
	var steps := 5
	for i in range(steps + 1):
		var t := float(i) / steps
		var y := top_y - length * t
		var c := Vector3(0.0, y, _spine_z(top_y))
		var ring := {"c": c, "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": (0.17 + 0.06 * t) * scale, "rz": (0.12 + 0.05 * t) * scale,
			"shape": _boxy.bind(2.2), "wfn": _skirt_weights.bind(t)}
		if jagged and i == steps:
			ring.shape = func(a: float) -> float: return _boxy(a, 2.2)
			ring.c = c + Vector3(0.0, 0.0, 0.0)
		rings.append(ring)
	if jagged:
		var hem: Dictionary = rings[steps]
		var base_c: Vector3 = hem.c
		rings[steps] = hem
		# Tattered hem: per-angle vertical offset applied through a lowered extra ring.
		var tail := hem.duplicate()
		tail.c = base_c - Vector3(0.0, 0.08, 0.0)
		tail.shape = func(a: float) -> float: return _boxy(a, 2.2) * (0.9 + 0.25 * absf(sin(a * 5.0 + 1.3)) * absf(sin(a * 3.0)))
		rings.append(tail)
	kit.loft(material, rings, 24, false, false)

func _skirt_weights(angle: float, t: float) -> Dictionary:
	var side := cos(angle)
	var thigh := "thigh_r" if side > 0.0 else "thigh_l"
	var follow := clampf(t * 1.1, 0.0, 0.85) * (0.35 + 0.65 * absf(side))
	return {Rig.bone_index("pelvis"): 1.0 - follow, Rig.bone_index(thigh): follow}

## --- Corrupted details -------------------------------------------------------------

func _ribs(kit: MeshKit) -> void:
	for i in range(5):
		var f := 0.36 + i * 0.075
		var y := lerpf(j.thigh_l.y, j.neck_01.y, f)
		var z := _spine_z(y)
		var half := 0.15 * float(p.girth) * (1.0 - 0.06 * absf(i - 2.0))
		var bone := "spine_03" if y > j.spine_03.y else "spine_02"
		for side: float in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for k in range(6):
				var a := lerpf(-PI * 0.5, -PI * 0.08, float(k) / 5.0)
				points.append(Vector3(side * cos(a) * half * 1.02, y - 0.012 * k, z + sin(a) * half * 0.72 - 0.004))
			for k in range(points.size() - 1):
				kit.tube("bone", points[k], points[k + 1], 0.0085, 0.0085, w(bone), 5, false)

func _spurs(kit: MeshKit) -> void:
	for i in range(5):
		var y := lerpf(j.spine_01.y, j.neck_01.y, float(i) / 4.0)
		var z := _spine_z(y) + 0.1 * float(p.girth) + 0.01
		var bone := "spine_01" if y < j.spine_02.y else ("spine_02" if y < j.spine_03.y else "spine_03")
		kit.tube("bone", Vector3(0.0, y, z - 0.01), Vector3(0.0, y + 0.03, z + 0.06 + 0.012 * (2 - absf(i - 2))), 0.016, 0.002, w(bone), 6)

func _shroud(kit: MeshKit) -> void:
	var rings: Array = []
	var neck: Vector3 = j.neck_01
	for entry: Array in [[0.04, 0.075, 0.07], [-0.03, 0.15, 0.115], [-0.1, 0.22, 0.14], [-0.24, 0.22, 0.15], [-0.42, 0.2, 0.16]]:
		var y: float = neck.y + entry[0]
		var ring := {"c": Vector3(0.0, y, _spine_z(y) + 0.012), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": entry[1], "rz": entry[2],
			"wfn": _mantle_weights.bind(y)}
		if entry[0] < -0.2:
			# Only the back half hangs down: the front collapses inward behind the ribs.
			ring.shape = func(a: float) -> float: return 1.0 if sin(a) > -0.2 else 0.35
		rings.append(ring)
	kit.loft("cloth_tattered", rings, 22, false, false)

func _deltoid_stump(kit: MeshKit) -> void:
	var shoulder: Vector3 = j.upperarm_l
	kit.blob("skin_corrupted", Transform3D(Basis.IDENTITY, shoulder + Vector3(0.01, 0.0, 0.0)), Vector3(0.06, 0.06, 0.06),
		{Rig.bone_index("clavicle_l"): 0.5, Rig.bone_index("upperarm_l"): 0.5}, 10, 6)

## --- Marrow Arm (anatomical modification, left arm) -----------------------------------

func marrow_arm(kit: MeshKit) -> void:
	var shoulder: Vector3 = j.upperarm_l
	var elbow: Vector3 = j.lowerarm_l
	var wrist: Vector3 = j.hand_l
	var up := w("upperarm_l")
	var low := w("lowerarm_l")
	var hand := w("hand_l")
	# Humerus with knobbed ends.
	kit.tube("marrow", shoulder, elbow, 0.03, 0.024, up, 8)
	kit.blob("bone", Transform3D(Basis.IDENTITY, shoulder), Vector3(0.045, 0.045, 0.045), up, 10, 6)
	kit.blob("bone", Transform3D(Basis.IDENTITY, elbow), Vector3(0.038, 0.034, 0.034), low, 10, 6)
	# Radius and ulna, slightly apart.
	var basis := MeshKit.basis_from_y((wrist - elbow).normalized())
	for offset: float in [-0.017, 0.017]:
		kit.tube("marrow", elbow + basis.z * offset, wrist + basis.z * offset * 0.6, 0.016, 0.013, low, 7)
	# Bone spurs along the forearm.
	for k in range(3):
		var at := elbow.lerp(wrist, 0.25 + 0.25 * k)
		kit.tube("bone", at + basis.x * 0.01, at + basis.x * 0.06 + basis.y * 0.03, 0.012, 0.001, low, 5)
	# Claw: palm knuckle and three long talons, curled forward.
	var hx: Transform3D = rest.hand_l
	kit.blob("bone", hx * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0)), Vector3(0.04, 0.035, 0.025), hand, 10, 6, 2.6)
	for k in range(3):
		var x := (k - 1) * 0.025
		var a := hx * Vector3(x, 0.05, 0.0)
		var b := hx * Vector3(x * 1.3, 0.13, -0.03)
		var c := hx * Vector3(x * 1.4, 0.19, -0.09)
		kit.tube("bone", a, b, 0.011, 0.008, hand, 6, false)
		kit.tube("marrow", b, c, 0.008, 0.001, hand, 6)

## --- Armor --------------------------------------------------------------------------

func armor_layer(kit: MeshKit, armor_id: String, marrow: bool) -> void:
	match armor_id:
		"armor.lab_cloth_wraps":
			_cloth_wraps(kit, marrow)
		"armor.lab_mail_shirt":
			_mail_shirt(kit, marrow)
		"armor.lab_bog_iron_plate":
			_plate(kit, marrow)

func _cloth_wraps(kit: MeshKit, marrow: bool) -> void:
	var cloth := "cloth_tattered" if corrupted else "cloth_robe"
	for side: String in ["l", "r"]:
		if not (marrow and side == "l"):
			_arm(kit, side, cloth, 1.12, 0.62, 0.95)
		_leg(kit, side, cloth, 1.14, 1.25, 1.85)
	_torso(kit, cloth, 1.06, 2, 7)
	if not corrupted:
		_skirt(kit, cloth, 0.36, 1.0, true)
	# Diagonal sash across the chest.
	var a := Vector3(-0.17, j.spine_03.y + 0.06, _spine_z(j.spine_03.y) - 0.02)
	var b := Vector3(0.16, j.spine_01.y, _spine_z(j.spine_01.y) - 0.04)
	kit.tube("leather", a + Vector3(0.0, 0.0, -0.1), b + Vector3(0.0, 0.0, -0.1), 0.018, 0.018, w("spine_02"), 6)

func _mail_shirt(kit: MeshKit, marrow: bool) -> void:
	var mail := "mail_rusted" if corrupted else "mail"
	_torso(kit, mail, 1.1, 1, 9)
	_skirt(kit, mail, 0.3, 1.04, false)
	for side: String in ["l", "r"]:
		if not (marrow and side == "l"):
			_arm(kit, side, mail, 1.14, 0.0, 0.62)
	_belt(kit, "leather", 1.12)
	if not corrupted:
		# Mail coif over a padded cap.
		var centre: Vector3 = j.head + Vector3(0.0, 0.085, 0.0)
		kit.blob(mail, Transform3D(Basis.IDENTITY, centre), Vector3(0.098, 0.128, 0.114), w("head"), 18, 12, 2.0, func(u: Vector3) -> float:
			if u.z < -0.4 and u.y < 0.45 and u.y > -0.6:
				return 0.7
			return 1.0)
		_neck_guard(kit, mail)
		# Padded collar (gambeson) under the mail.
		_mantle(kit, "cloth_dark")

## Collar around the neck: mail blends spine and neck; a plate gorget is rigid on spine_03.
func _neck_guard(kit: MeshKit, material: String, rigid := false) -> void:
	var neck: Vector3 = j.neck_01
	var rings: Array = []
	for entry: Array in [[0.1, 0.075, 0.07], [0.0, 0.1, 0.095], [-0.06, 0.16, 0.12]]:
		var y: float = neck.y + entry[0]
		rings.append({"c": Vector3(0.0, y, _spine_z(y)), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": entry[1], "rz": entry[2],
			"w": w("spine_03") if rigid else mix("spine_03", "neck_01", 0.5 if entry[0] > 0.05 else 0.2)})
	kit.loft(material, rings, 18, false, false)

func _plate(kit: MeshKit, marrow: bool) -> void:
	var plate := "plate_rusted" if corrupted else "plate"
	var mail := "mail_rusted" if corrupted else "mail"
	var trim := "bronze" if not corrupted else "iron_black"
	# Mail underlayer at the joints.
	_torso(kit, mail, 1.08, 0, 4)
	_skirt(kit, mail, 0.24, 1.04, false)
	# Breastplate and backplate: rigid on spine_03 (upper) and spine_02 (lower lames).
	var chest_y: float = (j.spine_03.y + j.neck_01.y) * 0.5 - 0.04
	var chest := Vector3(0.0, chest_y, _spine_z(chest_y))
	var g: float = p.girth
	kit.blob(plate, Transform3D(Basis.IDENTITY, chest + Vector3(0.0, 0.0, -0.01)), Vector3(0.2 * g + 0.02, 0.15, 0.13 * g + 0.02), w("spine_03"), 20, 10, 2.6,
		func(u: Vector3) -> float: return 1.0 + (0.06 if u.z < -0.3 and absf(u.x) < 0.3 else 0.0))
	for k in range(3):
		var y: float = j.spine_02.y + 0.02 - k * 0.06
		var bone := "spine_02" if k < 2 else "spine_01"
		var ring := _torso_ring(inverse_lerp(j.thigh_l.y, j.neck_01.y, y), 0.172, 0.118, 1.16 - k * 0.01)
		var lower := _torso_ring(inverse_lerp(j.thigh_l.y, j.neck_01.y, y - 0.055), 0.175, 0.12, 1.17 - k * 0.01)
		for r: Dictionary in [ring, lower]:
			r.erase("wfn")
			r.w = w(bone)
		kit.loft(plate, [ring, lower], 20, false, false)
	# Fauld lames over the hips.
	for k in range(2):
		var y: float = j.pelvis.y - 0.02 - k * 0.06
		var ring := _torso_ring(inverse_lerp(j.thigh_l.y, j.neck_01.y, y), 0.18, 0.125, 1.18 + k * 0.03)
		var lower := _torso_ring(inverse_lerp(j.thigh_l.y, j.neck_01.y, y - 0.07), 0.2, 0.14, 1.2 + k * 0.03)
		for r: Dictionary in [ring, lower]:
			r.erase("wfn")
			r.w = w("pelvis")
		kit.loft(plate, [ring, lower], 20, false, false)
	for side: String in ["l", "r"]:
		var x := -1.0 if side == "l" else 1.0
		var shoulder: Vector3 = j["upperarm_" + side]
		var elbow: Vector3 = j["lowerarm_" + side]
		var wrist: Vector3 = j["hand_" + side]
		var arm_dir := (elbow - shoulder).normalized()
		if not (marrow and side == "l"):
			# Pauldron: layered shell over the shoulder.
			for k in range(2):
				kit.blob(plate, Transform3D(MeshKit.basis_from_y(arm_dir), shoulder + Vector3(x * 0.012 * k, 0.03 - k * 0.05, 0.0)),
					Vector3(0.09 - k * 0.008, 0.075, 0.085 - k * 0.006) * lerpf(g, 1.0, 0.5), w("upperarm_" + side), 14, 8, 2.4,
					func(u: Vector3) -> float: return 1.0 if u.y > -0.5 else 0.6)
			kit.tube(plate, shoulder.lerp(elbow, 0.35), shoulder.lerp(elbow, 0.85), 0.056 * g + 0.008, 0.05 * g + 0.008, w("upperarm_" + side), 12)
			# Couter (elbow cop) and vambrace.
			kit.blob(plate, Transform3D(MeshKit.basis_from_y(arm_dir), elbow + Vector3(0.0, 0.0, 0.02)), Vector3(0.05, 0.045, 0.05), w("lowerarm_" + side), 12, 8, 2.2)
			kit.tube(plate, elbow.lerp(wrist, 0.18), elbow.lerp(wrist, 0.9), 0.05 * g + 0.006, 0.04 * g + 0.006, w("lowerarm_" + side), 12)
			# Gauntlet cuff and plated knuckles.
			var hand: Transform3D = rest["hand_" + side]
			kit.tube(plate, hand * Vector3(0.0, -0.03, 0.0), hand * Vector3(0.0, 0.03, 0.0), 0.046, 0.05, w("hand_" + side), 10)
			kit.blob(plate, hand * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.06, 0.006)), Vector3(0.047, 0.04, 0.03), w("hand_" + side), 10, 6, 2.6,
				func(u: Vector3) -> float: return 1.0 if u.z > -0.2 else 0.85)
		else:
			kit.blob(plate, Transform3D(MeshKit.basis_from_y(arm_dir), shoulder + Vector3(0.0, 0.03, 0.0)), Vector3(0.07, 0.06, 0.07), w("clavicle_l"), 12, 6, 2.4)
		# Cuisse, poleyn with a wing, greave, sabaton.
		var hip: Vector3 = j["thigh_" + side]
		var knee: Vector3 = j["calf_" + side]
		var ankle: Vector3 = j["foot_" + side]
		kit.tube(plate, hip.lerp(knee, 0.15), hip.lerp(knee, 0.85), 0.088, 0.066, w("thigh_" + side), 12)
		kit.blob(plate, Transform3D(Basis.IDENTITY, knee + Vector3(0.0, 0.0, -0.035)), Vector3(0.055, 0.06, 0.04), w("calf_" + side), 12, 8, 2.2)
		kit.blob(trim, Transform3D(Basis.IDENTITY, knee + Vector3(x * 0.04, 0.0, -0.03)), Vector3(0.012, 0.045, 0.035), w("calf_" + side), 8, 6)
		kit.tube(plate, knee.lerp(ankle, 0.12), knee.lerp(ankle, 0.92), 0.064, 0.045, w("calf_" + side), 12)
		var ball: Vector3 = j["ball_" + side]
		kit.blob(plate, Transform3D(Basis.IDENTITY, Vector3(ankle.x, 0.07, (ankle.z + ball.z) * 0.5)), Vector3(0.056, 0.05, 0.1), w("foot_" + side), 12, 6, 2.6,
			func(u: Vector3) -> float: return 1.0 if u.y > -0.3 else 0.5)
	# Gorget.
	_neck_guard(kit, plate, true)
	if not corrupted:
		_great_helm(kit, plate, trim)
	else:
		# Rusted crown-band over the skull: the soul's face stays visible.
		var centre: Vector3 = j.head + Vector3(0.0, 0.14, -0.01)
		var basis := Basis.IDENTITY
		kit.loft(plate, [{"c": centre, "x": basis.x, "z": basis.z, "rx": 0.086, "rz": 0.104, "w": w("head")},
			{"c": centre + Vector3(0.0, 0.035, 0.0), "x": basis.x, "z": basis.z, "rx": 0.082, "rz": 0.1, "w": w("head"),
				"shape": func(a: float) -> float: return 1.0 + 0.12 * maxf(0.0, sin(a * 6.0))}], 18, false, false)

func _great_helm(kit: MeshKit, plate: String, trim: String) -> void:
	var centre: Vector3 = j.head + Vector3(0.0, 0.09, -0.008)
	var rings: Array = []
	for entry: Array in [[-0.13, 0.095, 0.11], [-0.06, 0.1, 0.118], [0.03, 0.102, 0.12], [0.1, 0.098, 0.115], [0.135, 0.07, 0.085], [0.15, 0.0, 0.0]]:
		rings.append({"c": centre + Vector3(0.0, entry[0], 0.0), "x": Vector3.RIGHT, "z": Vector3.BACK, "rx": entry[1], "rz": entry[2],
			"shape": func(a: float) -> float: return 1.0 + (0.08 if sin(a) < -0.85 else 0.0), "w": w("head")})
	kit.loft(plate, rings, 22, true, false)
	# Eye slit (dark) and breaths, a brass cross on the face.
	kit.box("iron_black", Transform3D(Basis.IDENTITY, centre + Vector3(0.0, 0.03, -0.128)), Vector3(0.15, 0.014, 0.02), w("head"))
	kit.box(trim, Transform3D(Basis.IDENTITY, centre + Vector3(0.0, -0.03, -0.131)), Vector3(0.016, 0.1, 0.012), w("head"))
	kit.box(trim, Transform3D(Basis.IDENTITY, centre + Vector3(0.0, -0.005, -0.13)), Vector3(0.08, 0.014, 0.012), w("head"))
