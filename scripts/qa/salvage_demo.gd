extends SceneTree
## Runs the isolated salvage flow and writes flow.json + SUMMARY.md.
## Usage: godot --headless --path . --script res://scripts/qa/salvage_demo.gd -- --out=<dir>

const Catalog := preload("res://scripts/builds/build_catalog.gd")
const Flow := preload("res://scripts/qa/salvage_flow_fixture.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := "res://docs/salvage/examples"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var catalog = Catalog.new()
	if not catalog.load_file():
		print(JSON.stringify({"demo": "salvage", "ok": false, "errors": catalog.errors}))
		quit(1)
		return
	var result := Flow.run(catalog)
	if not result.ok:
		print(JSON.stringify({"demo": "salvage", "ok": false, "errors": result.errors}))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_write(out.path_join("flow.json"), JSON.stringify(result.flow, "\t", true) + "\n")
	_write(out.path_join("SUMMARY.md"), Flow.summary(result.flow))
	print(Flow.summary(result.flow))
	print(JSON.stringify({"demo": "salvage", "ok": true, "out": out}))
	quit(0)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
