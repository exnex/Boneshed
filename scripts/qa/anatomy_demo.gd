extends SceneTree
## Runs the isolated anatomy demonstration and writes flow.json + SUMMARY.md.
## Usage: godot --headless --path . --script res://scripts/qa/anatomy_demo.gd -- --out=<dir>

const AnatomyCatalog := preload("res://scripts/anatomy/anatomy_catalog.gd")
const BuildCatalog := preload("res://scripts/builds/build_catalog.gd")
const Fixture := preload("res://scripts/qa/anatomy_fixture.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := "res://docs/anatomy/examples"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var anatomy = AnatomyCatalog.new()
	var builds = BuildCatalog.new()
	if not anatomy.load_file() or not builds.load_file():
		print(JSON.stringify({"demo": "anatomy", "ok": false, "errors": anatomy.errors + builds.errors}))
		quit(1)
		return
	var result := Fixture.run(anatomy, builds)
	if not result.ok:
		print(JSON.stringify({"demo": "anatomy", "ok": false, "errors": result.errors}))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_write(out.path_join("flow.json"), JSON.stringify(result.flow, "\t", true) + "\n")
	_write(out.path_join("SUMMARY.md"), Fixture.summary(result.flow))
	print(Fixture.summary(result.flow))
	print(JSON.stringify({"demo": "anatomy", "ok": true, "out": out}))
	quit(0)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
