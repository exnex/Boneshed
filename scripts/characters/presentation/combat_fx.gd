extends RefCounted
## Cosmetic combat cues on the placeholder fighter. Every cue is computed from rule
## state and already-resolved results each frame; none keeps history, so cancels,
## resets and teleports cannot leave a stale trail. Nothing here affects combat.
const Sampler = preload("res://scripts/characters/presentation/pose_sampler.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")

const TRAIL_SECONDS := 0.1 # Rule seconds of blade path shown behind the sword.
const TRAIL_FADE := 0.1 # The trail stops growing at active_end and drains over this.
const TRAIL_SAMPLES := 12
const RELEASE_ALPHA := 0.22 # Faint while the blade accelerates (no damage yet).
const ACTIVE_ALPHA := 0.7 # Bright exactly over the rule's ACTIVE window.
const GLINT_SECONDS := 0.14 # From the start of the committed stage.
const HIT_MARK_SECONDS := 0.14

static var _star: ImageTexture

static func build(actor: Fighter) -> void:
	var trail := MeshInstance3D.new()
	trail.name = "BladeTrail"
	trail.mesh = ImmediateMesh.new()
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail_material := StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = trail_material
	actor.visual.add_child(trail)
	var glint := _billboard("Glint", Color(1.0, 0.97, 0.9))
	actor.visual.add_child(glint)
	var flash := _billboard("Flash", Color(1.0, 0.93, 0.78))
	actor.impact.add_child(flash)
	var mark := MeshInstance3D.new()
	mark.name = "HitMark"
	mark.mesh = QuadMesh.new()
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mark_material := StandardMaterial3D.new()
	mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark_material.albedo_color = Color(1.0, 0.88, 0.74)
	mark.material_override = mark_material
	mark.visible = false
	actor.add_child(mark)

static func _billboard(node_name: String, color: Color) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = node_name
	quad.mesh = QuadMesh.new()
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = star_texture()
	mat.albedo_color = color
	quad.material_override = mat
	quad.visible = false
	return quad

## A four-point glint generated in code (no imported asset).
static func star_texture() -> ImageTexture:
	if _star:
		return _star
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var u := (x + 0.5) / size * 2.0 - 1.0
			var v := (y + 0.5) / size * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var core := exp(-r * r * 22.0)
			var rays := exp(-absf(u) * 26.0) * maxf(0.0, 1.0 - absf(v)) + exp(-absf(v) * 26.0) * maxf(0.0, 1.0 - absf(u))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(core + rays * 0.8, 0.0, 1.0)))
	_star = ImageTexture.create_from_image(image)
	return _star

static func sync(actor: Fighter, mirrored: bool, incoming_world: Vector3) -> void:
	var state := actor.combat
	_sync_trail(actor, state, mirrored)
	_sync_glint(actor, state)
	_sync_hit_mark(actor, incoming_world)
	var flash: MeshInstance3D = actor.impact.get_node("Flash")
	flash.visible = actor.impact.visible and actor.last_result == Rules.DEFLECTED
	if flash.visible:
		flash.scale = Vector3.ONE * (0.25 + 0.6 * clampf((actor.flash_time - 0.18) / 0.14, 0.0, 1.0))

static func _sync_trail(actor: Fighter, state: Rules, mirrored: bool) -> void:
	var mesh: ImmediateMesh = actor.visual.get_node("BladeTrail").mesh
	mesh.clear_surfaces()
	var now := Sampler.attack_rule_time(state)
	if now < 0.0 or state.is_signature():
		return
	var timing := Sampler.timing_of(state)
	var release_start: float = timing.windup - timing.release
	var active_start: float = timing.windup
	var active_end: float = timing.windup + timing.active
	var newest := minf(now, active_end)
	var oldest := maxf(release_start, now - TRAIL_SECONDS)
	if newest - oldest < 0.004:
		return
	var drain := 1.0 - clampf((now - active_end) / TRAIL_FADE, 0.0, 1.0)
	var binding := Sampler.binding_of(state)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(TRAIL_SAMPLES):
		var along := float(i) / (TRAIL_SAMPLES - 1)
		var rule_time := lerpf(oldest, newest, along)
		var pose := Sampler.attack_pose(binding, timing, rule_time)
		if mirrored:
			pose = Sampler.mirror(pose)
		var points := Sampler.blade_points(pose)
		var live := rule_time >= active_start
		var color := Color(1.0, 0.95, 0.84) if live else Color(0.78, 0.86, 0.95)
		color.a = (ACTIVE_ALPHA if live else RELEASE_ALPHA) * pow(along, 1.4) * drain
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(points[0])
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(points[1])
	mesh.surface_end()

static func _sync_glint(actor: Fighter, state: Rules) -> void:
	var glint: MeshInstance3D = actor.visual.get_node("Glint")
	var stage := state.attack_stage()
	glint.visible = false
	if state.phase != Rules.Phase.WINDUP or stage == "early":
		return
	var progress := (state.commitment_duration - state.remaining) / GLINT_SECONDS
	if progress < 0.0 or progress > 1.0:
		return
	glint.visible = true
	var size := 0.55 if state.heavy else 0.4
	glint.scale = Vector3.ONE * size * sin(progress * PI)
	if state.is_signature():
		glint.position = actor.marrow_pivot.position + actor.marrow_pivot.basis * actor.marrow_tip.position
	else:
		glint.position = actor.sword_pivot.position + actor.sword_pivot.basis * Vector3(0.0, 0.0, -1.6)

static func _sync_hit_mark(actor: Fighter, incoming_world: Vector3) -> void:
	var mark: MeshInstance3D = actor.get_node("HitMark")
	var elapsed := Sampler.REACTION_SECONDS - actor.reaction_time
	mark.visible = actor.reaction_time > 0.0 and actor.reaction_kind in [Rules.HIT, "punish", Rules.DEFEATED] and elapsed < HIT_MARK_SECONDS
	if not mark.visible:
		return
	var grow := clampf(elapsed / 0.04, 0.0, 1.0)
	var fade := 1.0 - clampf((elapsed - 0.04) / (HIT_MARK_SECONDS - 0.04), 0.0, 1.0)
	var attacker: Fighter = actor.opponent if is_instance_valid(actor.opponent) else null
	# Light cuts read as a diagonal, heavy as a near-vertical chop, a thrust as a short stab.
	var roll := 0.4
	var length := 0.75
	if attacker and attacker.combat.is_signature():
		roll = 0.0
		length = 0.35
	elif attacker and attacker.combat.heavy:
		roll = 1.2
	if attacker and attacker.combat.signature.size() > 0 and not attacker.combat.is_signature():
		roll = -roll # Left-hand sword cuts the other way.
	var toward := incoming_world if incoming_world.length_squared() > 0.0001 else Vector3.FORWARD
	mark.position = Vector3(0.0, 1.3, 0.0) + toward * 0.32
	mark.basis = Basis.looking_at(toward, Vector3.UP) * Basis(Vector3.BACK, roll)
	mark.scale = Vector3(length * (0.35 + 0.65 * grow), 0.07 * (0.5 + 0.5 * fade), 1.0)
	(mark.material_override as StandardMaterial3D).albedo_color.a = 0.95 * fade
