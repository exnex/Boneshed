extends RefCounted
## Quality presets for the visual showcase (proposed, provisional). One table, read by
## the crypt builder and the arena; select with `-- --quality=high|medium|low`.
## msaa is a Viewport.MSAA value (0 off, 1 = 2×, 2 = 4×); shadow sizes are atlas texels.
## Features the GL Compatibility renderer does not have (SSAO, SSIL, volumetric fog,
## positional-light shadows at acceptable cost) are switched off there automatically;
## the Compatibility path uses depth fog and fog cards instead of volumetric fog.

const PRESETS := {
	"high": {"texture_size": 256, "environment_texture_size": 512, "directional_shadow": 4096, "positional_shadows": 2, "shadow_atlas": 4096, "msaa": 2,
		"glow": true, "ssao": true, "ssil": true, "volumetric_fog": true, "fog_cards": true, "torches": true, "particles": 1.0},
	"medium": {"texture_size": 256, "environment_texture_size": 256, "directional_shadow": 2048, "positional_shadows": 0, "shadow_atlas": 2048, "msaa": 1,
		"glow": true, "ssao": true, "ssil": false, "volumetric_fog": true, "fog_cards": true, "torches": true, "particles": 0.6},
	"low": {"texture_size": 128, "environment_texture_size": 128, "directional_shadow": 1024, "positional_shadows": 0, "shadow_atlas": 0, "msaa": 0,
		"glow": false, "ssao": false, "ssil": false, "volumetric_fog": false, "fog_cards": false, "torches": false, "particles": 0.3},
}

## Set by benchmarks and tests to choose a preset without command-line arguments.
static var override: String = ""

static func requested_preset() -> String:
	if PRESETS.has(override):
		return override
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			var name := arg.trim_prefix("--quality=")
			if PRESETS.has(name):
				return name
	return "high" if RenderingServer.get_current_rendering_method() == "forward_plus" else "medium"

## The preset with renderer-unsupported features disabled. `name` and `renderer` added.
static func preset(name: String, renderer: String) -> Dictionary:
	var out: Dictionary = (PRESETS.get(name, PRESETS.medium) as Dictionary).duplicate()
	out.name = name if PRESETS.has(name) else "medium"
	out.renderer = renderer
	if renderer != "forward_plus":
		out.ssao = false
		out.ssil = false
		out.volumetric_fog = false
		out.positional_shadows = mini(int(out.positional_shadows), 1)
	else:
		out.fog_cards = false if out.volumetric_fog else out.fog_cards
	return out
