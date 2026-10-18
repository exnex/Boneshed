# Engineering audit — experiments and baseline runs (2026-10-18)

Supports [`docs/engineering/CODE_AUDIT.md`](../../engineering/CODE_AUDIT.md). Every experiment ran in
a **scratch copy** made with `git archive HEAD` at `3dbcc08` (main). The repository's gameplay
code, data, scenes and `project.godot` were not modified.

Environment: Linux x86_64 cloud container, Godot **4.7.2.stable.official.ed1daf0bf** installed by
`scripts/tooling/setup.sh` (official SHA-512 verified), Xvfb + Mesa llvmpipe (LLVM 20.1.2) for
rendered runs.

## 1. Baseline: existing suites, unmodified `main`

| Runner | Result |
| --- | --- |
| `bash scripts/tooling/test.sh` (`BONESHED_GRAPHICAL_TIMEOUT=900`) | All 16 runs at expected exit codes: import; 76 integration checks; invalid-startup expected failure; 118 combat checks; 6 combat negative controls (guard, deflect, phase, toggle, rear, poise) each exit 1; 8 encounter regressions; defense negative exit 1; headless timing; visual negative exit 1; 111 rendered graphical checks + 5 PNGs; rendered timing |
| `bash scripts/tooling/test_builds.sh` | 137 checks; 2 example files regenerate byte-identically |
| `bash scripts/tooling/test_worldgen.sh` | 80 checks; 16 example files regenerate byte-identically |
| `bash scripts/tooling/test_anatomy.sh` | 190 checks; 2 example files regenerate byte-identically |

`test_web.sh` was **not** run (needs export templates and Playwright; this task changes no runtime code).

## 2. Silent `Object.set()` with an unknown property

```gdscript
extends SceneTree
class S extends RefCounted:
	var heavy_damage := 32.0
func _initialize() -> void:
	var s := S.new()
	s.set("heavy_damgae", 99.0)          # misspelled
	print(s.heavy_damage, " ", "heavy_damgae" in s)
	quit(0)
```

Output on 4.7.2: `32.0 false`, and **no error or warning is logged**. `build_adapter.gd`
`create_state()` relies on `state.set(field, value)` for every combat parameter.

## 3. Adapter field-name mutation (does any test notice a dropped field?)

For each of the 20 fields `BuildAdapter._from_resolved()` emits, the scratch copy's
`create_state()` was changed so that only that field name received a `_typo` suffix, then
`scripts/qa/combat_build_tests.gd` ran headless:

```sh
sed -i "s|state.set(field, |state.set(field + (\"_typo\" if field == \"$f\" else \"\"), |" \
    scripts/combat/build_adapter.gd
godot --headless --path . --script res://scripts/qa/combat_build_tests.gd | grep -c '"passed":false'
```

| Field silently dropped | Failed checks | Field silently dropped | Failed checks |
| --- | --- | --- | --- |
| max_health | 2 | attack_windup | 3 |
| **max_posture** | **0** | **heavy_windup** | **0** |
| **deflect_window** | **0** | light_active_duration | 2 |
| **guard_chip** | **0** | **heavy_active_duration** | **0** |
| posture_recovery_rate | 1 | light_recovery_duration | 3 |
| **posture_recovery_delay** | **0** | heavy_recovery_duration | 2 |
| deflect_posture | 1 | light_damage / heavy_damage | 1 / 1 |
| guard_posture_overrides | 2 | light_hit_posture / **heavy_hit_posture** | 1 / **0** |
| | | light_guard_posture / **heavy_guard_posture** | 1 / **0** |

**8 of 20 fields can be lost with zero failing checks and zero engine errors**, because the
`CombatState` defaults currently equal the catalog values, so the byte-for-byte runtime trace
still matches. `deflect_window` is the stat the Marrow Arm changes (0.16 → 0.11), and wiring
that arm is the recommended next gameplay PR. Interpretation: no current behavior is wrong;
the safety net has a gap exactly where the next change lands.

## 4. Static-typing warning census

The scratch copy's `project.godot` set `untyped_declaration`, `unsafe_property_access`,
`unsafe_method_access`, `unsafe_cast` and `unsafe_call_argument` to **Error** (warnings are
not printed by `--check-only`, so promoting them to errors is how they were counted), then ran
`godot --headless --check-only --script <file>` for every tracked `scripts/**/*.gd`.

| Scope | Reports |
| --- | --- |
| All scripts | 2,558 |
| Production (non-`scripts/qa/`) | 844 |
| `combat_state.gd` / `fighter.gd` / `player.gd` / `swordsman.gd` | 1 / 4 / 2 / 5 |
| `anatomy_rules.gd` / `blueprint_generator.gd` / `build_rules.gd` / `anatomy_catalog.gd` / `build_catalog.gd` | 235 / 152 / 97 / 96 / 70 |

Of the production reports: 323 untyped declarations, 231 unsafe call arguments, 221 unsafe
method accesses, 60 untyped lambda returns, 9 unsafe property accesses. The four actor/rule scripts are almost fully typed; `build_adapter.gd` adds 28 reports
(40 across combat/characters/AI). These diagnostics are not counts of unique defects. Nearly all reports come from the JSON-shaped `Dictionary` rules
layers, where values are `Variant` by construction. Counts are indicative: a parse error can
stop reporting within a file, so treat them as lower bounds.

## 5. JSON numbers

`JSON.parse_string(JSON.stringify({"a": 1})).a` is a `float` on 4.7.2, consistent with the
class reference ("converting a Variant to JSON text will convert all numerical values to
float"). Default `JSON.stringify` also emits `0.1 + 0.2` as `0.3` (reliable digits only). The
catalogs' canonical-JSON fingerprints therefore depend on the engine's float-to-text output.

## 6. Independent verification

[The independent review](../engineering-review/README.md) reproduced all 20 mutations,
including the same eight undetected fields, and the 2,558/844 warning counts. It also
corrects the API/lifetime advice and adds a reproducible anatomy-catalog reload finding.
F1 is a regression and coverage risk in a validated adapter, not a demonstrated exploit.
