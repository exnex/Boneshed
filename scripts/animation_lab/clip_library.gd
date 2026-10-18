extends RefCounted
## Import step for the animation lab. Loads the pinned trial glTF files at runtime and
## turns their raw clips into a Boneshed clip library described by
## data/animation_lab/clip_manifest.json: rename, loop flags, root policy, markers and
## additive conversion. In production the same rules would run in an
## EditorScenePostImport script; here they run at load so nothing third-party is committed.

const MANIFEST_PATH := "res://data/animation_lab/clip_manifest.json"
const ASSET_PATH := "res://data/animation_lab/trial_asset.json"
const DEFAULT_TOOLS := "/workspace/tools"
const FILES := {"base": "human-base-animations.glb", "addon": "human-addon-animations.glb"}

static func load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## Directory holding the verified trial files (see scripts/tooling/fetch_animation_trial.sh).
static func trial_dir() -> String:
	var asset := load_json(ASSET_PATH)
	var tools := OS.get_environment("BONESHED_TOOLS")
	return (tools if not tools.is_empty() else DEFAULT_TOOLS).path_join("animation-trial").path_join(str(asset.get("commit", "")))

## Empty when every pinned file exists with its pinned SHA-256.
static func verify_trial(dir: String) -> PackedStringArray:
	var errors := PackedStringArray()
	for entry in load_json(ASSET_PATH).get("files", []):
		var path := dir.path_join(str(entry.name))
		if not FileAccess.file_exists(path):
			errors.append("missing %s (run scripts/tooling/fetch_animation_trial.sh)" % path)
		elif FileAccess.get_sha256(path) != str(entry.sha256):
			errors.append("checksum mismatch %s" % path)
	return errors

## Generates the scene for one trial file. Caller owns the returned node.
static func load_scene(dir: String, file_key: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(dir.path_join(FILES[file_key]), state) != OK:
		return null
	return document.generate_scene(state) as Node3D

static func source_player(scene: Node) -> AnimationPlayer:
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	return players[0] as AnimationPlayer if not players.is_empty() else null

## Builds the processed library. `sources` maps file keys to their AnimationPlayers;
## `skeleton` supplies rest poses for additive conversion.
static func build_library(manifest: Dictionary, sources: Dictionary, skeleton: Skeleton3D) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var root_bone: String = manifest.skeleton.root_bone
	for clip_name in manifest.clips:
		var spec: Dictionary = manifest.clips[clip_name]
		var player: AnimationPlayer = sources[spec.file]
		var animation := player.get_animation(spec.source).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if spec.loop else Animation.LOOP_NONE
		strip_non_bone_tracks(animation, skeleton)
		if spec.root == "in_place":
			flatten_root(animation, root_bone)
		if spec.get("additive", false):
			make_additive(animation, skeleton)
		for marker in spec.get("markers", {}):
			animation.add_marker(marker, float(spec.markers[marker]))
		library.add_animation(clip_name, animation)
	return library

static func bone_of(animation: Animation, track: int) -> String:
	return str(animation.track_get_path(track)).get_slice(":", 1)

## Keeps only skeleton bone tracks, like the importer's "Remove Tracks: Except Bone
## Transform" retarget option. Some trial clips (Hit_Chest) also key the Armature node's
## own position; as an additive layer that offset lifted the whole body by ~0.58 m.
## Returns the number of tracks removed.
static func strip_non_bone_tracks(animation: Animation, skeleton: Skeleton3D) -> int:
	var removed := 0
	for track in range(animation.get_track_count() - 1, -1, -1):
		if skeleton.find_bone(bone_of(animation, track)) < 0:
			animation.remove_track(track)
			removed += 1
	return removed

## Code-driven movement: the root bone may not translate. Holds every root position
## key at the first key so the clip plays in place.
static func flatten_root(animation: Animation, root_bone: String) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and bone_of(animation, track) == root_bone:
			var first: Vector3 = animation.track_get_key_value(track, 0)
			for key in animation.track_get_key_count(track):
				animation.track_set_key_value(track, key, first)

## Converts a full-body clip into a delta from its first frame, re-expressed on the bone
## rest pose, which is the reference AnimationNodeAdd2 / OneShot ADD measure against.
static func make_additive(animation: Animation, skeleton: Skeleton3D) -> void:
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(bone_of(animation, track))
		if bone < 0 or animation.track_get_key_count(track) == 0:
			continue
		var rest := skeleton.get_bone_rest(bone)
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				var first: Quaternion = animation.track_get_key_value(track, 0)
				for key in animation.track_get_key_count(track):
					var value: Quaternion = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, (rest.basis.get_rotation_quaternion() * (first.inverse() * value)).normalized())
			Animation.TYPE_POSITION_3D:
				var first_position: Vector3 = animation.track_get_key_value(track, 0)
				for key in animation.track_get_key_count(track):
					var position: Vector3 = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, rest.origin + (position - first_position))
			Animation.TYPE_SCALE_3D:
				for key in animation.track_get_key_count(track):
					animation.track_set_key_value(track, key, rest.basis.get_scale())
