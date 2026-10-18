# Sources and evidence quality

Retrieved 2026-10-18. **Network note:** `docs.godotengine.org` was blocked by this cloud
environment's network policy. Official documentation was therefore read from its source
repository, [godotengine/godot-docs](https://github.com/godotengine/godot-docs), branch `4.7`
at commit `9adca4c1c729` (2026-09-21). The class reference was read from
[godotengine/godot](https://github.com/godotengine/godot) at tag **`4.7.2-stable`**, the pinned
build. Page links use the expected published 4.7 URLs, which couldn't be opened from this
environment; the source paths are authoritative.

| Quality | Meaning |
| --- | --- |
| **A** | Official documentation or class reference for the pinned version |
| **B** | Reproduced by an experiment in this repo or AI Game Dev Lab |
| **C** | Engine maintainer writing or engine PR (authoritative for mechanism; numbers are microbenchmarks) |
| **D** | Community reports, forum threads, third-party guides: useful signals, not verified here |

## Official documentation (A), godot-docs `4.7`

| Topic | Page (source path) | Used for |
| --- | --- | --- |
| Static typing | [static_typing](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html) (`tutorials/scripting/gdscript/static_typing.rst`) | Typed opcodes, typed collections, nested-type limits, `UNSAFE_*` warnings |
| GDScript basics | `gdscript_basics.rst` | Reference vs value types, lambda capture by value, `for` loop copies |
| Style guide | `gdscript_styleguide.rst` | Naming, code order |
| Autoloads | [autoloads_versus_regular_nodes](https://docs.godotengine.org/en/4.7/tutorials/best_practices/autoloads_versus_regular_nodes.html) | Global state, access and allocation problems; `static func`/`static var` alternatives |
| Scene organization | [scene_organization](https://docs.godotengine.org/en/4.7/tutorials/best_practices/scene_organization.html) | No-dependency scenes, dependency injection, signal-to-respond, Main entry node, configuration warnings |
| Node alternatives | `best_practices/node_alternatives.rst` | Object / RefCounted / Resource roles |
| Load vs preload | `best_practices/logic_preferences.rst` | `preload` semantics and the `@export` caveat |
| Resources | `scripting/resources.rst` | Load-once caching, shared sub-resources |
| Optimization | `performance/general_optimization.rst` | Measure first, profilers, hardware variance |
| Physics interpolation | `physics/interpolation/*.rst` | Tick/refresh mismatch, input-delay trade-off |
| Jolt | `physics/using_jolt_physics.rst` | Default for new projects; behavioral differences (margins, joints) |
| 3D formats | `assets_pipeline/importing_3d_scenes/available_formats.rst` | glTF 2.0 recommended; Blender export |
| Retargeting | `assets_pipeline/retargeting_3d_skeletons.rst` | Bone rest semantics in Godot 4; bone map/profile |
| Mesh LOD, visibility ranges, occlusion | `3d/mesh_lod.rst`, `3d/visibility_ranges.rst`, `3d/occlusion_culling.rst` | Production rendering features |

## Class reference (A), godot `4.7.2-stable`

| Class / member | Used for |
| --- | --- |
| `ProjectSettings.physics/3d/physics_engine` | DEFAULT = GodotPhysics3D "but may change"; Jolt default for 4.6+ projects |
| `ProjectSettings.physics/common/physics_interpolation`, `physics_jitter_fix`, `max_physics_steps_per_frame` | Interpolation default off; jitter fix; spiral of death |
| `ProjectSettings.debug/gdscript/warnings/*` incl. `directory_rules` | Typing warnings and per-directory scoping |
| `Resource.duplicate`, `duplicate_deep`, `resource_local_to_scene` | Shallow vs deep copy rules |
| `RandomNumberGenerator.seed`, `.state` | Reproducibility, no avalanche, state restore rules |
| `@GlobalScope.bytes_to_var_with_objects` | "Deserialized object can contain code which gets executed" |
| `@GDScript.assert` | Not executed in release builds |
| `JSON`, `JSON.stringify` | All numbers become floats; non-finite handling; lax parsing |
| `Dictionary` | Insertion order preserved |
| `Node._ready`, `Node.queue_free`, `Object.free`, `Object.connect`, `@GlobalScope.is_instance_valid` | Lifecycle, deletion and connection semantics |
| `Node.process_priority`, `process_physics_priority` | Explicit processing order |
| `AnimationMixer.callback_mode_process` (default IDLE), `callback_mode_method` | Animation/tick synchronization |

## Experiments (B)

| Experiment | Location |
| --- | --- |
| Silent `Object.set`, adapter field mutation, typing-warning census, JSON number types (4.7.2) | [evidence/engineering-audit](../evidence/engineering-audit/README.md) |
| Baseline suites on `main` (builds 137, worldgen 80, anatomy 190, combat 118, integration 76, graphical 111, all negative controls) | same |
| Untyped `Variant` reassigned `0.0 → 0` quantizes a tween (Signal Yard) | AI Game Dev Lab `11-research-watch/cloud-godot-3d-prototype-2026-10-15.md` |
| `frame_post_draw` hangs headless; `--script` runtime errors don't exit | AI Game Dev Lab `11-research-watch/cloud-godot-evaluation-2026-10-15.md` |
| `SkeletonIK3D` deprecation timeline; `LookAtModifier3D.relative` patch-release default change; agents generate outdated IK APIs | AI Game Dev Lab `13-technology-index/godot-procedural-animation.md` (class-reference diff across tags, not a game test) |

## Maintainer / engine sources (C)

- [GDScript progress report: typed instructions](https://godotengine.org/article/gdscript-progress-report-typed-instructions) — mechanism for typed opcodes.
- [godotengine/godot PR #70838](https://github.com/godotengine/godot/pull/70838) (Jan 2023) — reported >40% speed-up on typed synthetic loops in release builds. Microbenchmark; not a game measurement.
- [Design of the Skeleton Modifier 3D](https://godotengine.org/article/design-of-the-skeleton-modifier-3d/) (2024) — via the lab's procedural-animation index.

## Community and third-party (D) — not verified here

| Claim | Source | Status |
| --- | --- | --- |
| `is_action_just_pressed` in `_physics_process` could drop presses in early 4.x, fixed ~June 2023 | [GameDev.tv thread](https://community.gamedev.tv/t/dropped-inputs-with-is-action-just-pressed-in-physics-process-in-old-godot/231462), [Godot forum: true for two frames](https://forum.godotengine.org/t/input-is-action-just-pressed-report-true-for-two-frames/84942) | **Unverified** against the 4.7.2 source; the guide recommends a buffer for robustness either way |
| Area3D / AnimationPlayer hitbox toggles can be one frame late | [Godot forum: collisions 1 frame late](https://forum.godotengine.org/t/why-are-collisions-happening-1-frame-late/67044), [hack-and-slash thread](https://forum.godotengine.org/t/hack-and-slash-game-physics-and-collisions/133554) | Unresolved threads; consistent with the documented deferred method-call mode |
| Scene-inheritance / editable-children overrides lost or drifting | [forum 142133](https://forum.godotengine.org/t/how-to-save-changes-done-to-an-instanced-scene-with-editable-children/142133), [godotforums 41510](https://godotforums.org/d/41510-scene-changes-saving-resets-after-restarting-godot-to-old-values), [rename breaks inheritance](https://forum.godotengine.org/t/how-to-update-inheritance-after-renaming-parent-scene/46211) | Version-specific reports (4.0–4.7.1); not reproduced |
| Event-bus autoloads hurt traceability; others find them convenient | [Godot forum: Resources vs Autoloads](https://forum.godotengine.org/t/resources-vs-autoloads-for-coupling-systems/141573), [gdscript.com signals](https://gdscript.com/solutions/signals-godot/) | Contested opinion |
| RefCounted cycles leak; signal connections don't hold references | [Godot forum thread](https://forum.godotengine.org/t/do-signal-connections-prevent-refcounted-garbage-collection/111346); cycle behavior is also in the official RefCounted reference | Cycle leak: official. Connection claim: forum only |
| `local_to_scene` duplicates per sub-scene, surprising users | [forum 110037](https://forum.godotengine.org/t/how-to-force-a-resource-to-be-local-to-a-scenes-owner/110037) | Not reproduced |
| GUT vs GdUnit4 are both maintained, Godot-4 compatible | [GUT asset store](https://store.godotengine.org/asset/bitwes/gut/), [gdUnit4 listing](https://dev.co/testing/open-source/gdunit4) | Not evaluated; no dependency proposed |
| Typed GDScript up to 59% faster (Vector2) | [beep.blog 2024](https://www.beep.blog/2024-02-14-gdscript-typing/) via secondary summaries | Microbenchmark; not cited as a reason to type |

## Could not be verified

- Published `docs.godotengine.org` pages (network-blocked; the source repository was used instead).
- Whether the early-4.x input-polling fix covers every platform in 4.7.2.
- Jolt-specific `CharacterBody3D` behavior differences relevant to Boneshed's controller.
- Any frame-time effect of typing, allocation patterns or draw-call counts in Boneshed itself.
