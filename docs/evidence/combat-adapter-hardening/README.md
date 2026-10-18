# Combat adapter hardening — F1

**Confirmed task:** harden the existing shared-build/combat boundary and its regression
coverage. **Proposed:** existing numerical tuning stays provisional. **Open:** subjective
feel, future augmentation/module design, and cross-platform replay guarantees.

Baseline: fetched `main` at `b83d73138b80a55f7f57491046c68356af7b0b84` (2026-10-18).
All reported final runs use **`4.7.2.stable.official.ed1daf0bf`**, Linux x86_64,
GL Compatibility, Xvfb and llvmpipe (LLVM 19.1.7). Browser checks use real Chromium
with SwiftShader. Native runs use the unchanged 1280×720 project resolution.
The installed engine executable was compared against its ZIP entry; the archive
matched both the cached official manifest and the pinned SHA-512:

```text
9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
```

## What changed

The adapter validates the complete configuration and runtime property contract before
20 explicit typed assignments. Construction returns `{ok, errors, state}` with `null`
on failure. Preparation constructs both states before returning success; any error
returns empty configurations, resolutions and states. The courtyard then attaches the
prepared states before adding either fighter. The state-validation failure subprocess
confirms that an invalid second actor produces one clear startup error and exit 1,
with no fighters, world, input bindings or active courtyard physics processing.

Resolved builds and their temporary configurations remain JSON-shaped dictionaries.
This preserves the boundary between build resolution and simulation. Generated attack
keys are checked against the complete schema. The sparse `guard_posture_overrides`
dictionary is data keyed by incoming binding, not an Object property dispatch table;
its supported bindings and finite nonnegative costs are validated and copied per state.
No dynamic Object assignment remains. Catalog data, combat rules, AI, movement,
input, equipment, animations, rendering and confirmed gameplay decisions are unchanged.

## Regression coverage and controls

The integration suite grows from 76 to **532 checks**. For each of the 20 parameters,
on **both profiles**, it starts from a valid resolved build, changes one input away
from both its original value and the runtime default, constructs a state and checks
the exact value. It separately changes the catalog/profile and checks the live scene.
Each case also rejects missing and misspelled configuration keys. The matrix must
cover exactly the prepared combat configuration, so a newly added field needs coverage.
Movement is checked through both live profiles as a separate Fighter parameter.

The cases cover health/posture, deflection window and pressure, guard chip, posture
recovery delay/rate, both attacks' independent windup/active/recovery durations,
health and posture damage, incoming block costs, and profile-specific overrides.
Additional checks cover numeric types, booleans, nonfinite/negative values, supported
zero values, invalid timing/ranges, configuration shapes, unsupported defense
bindings, state reset and dictionary ownership. A `0.11` deflection window blocks,
rather than deflects, a hit arriving after `0.13` seconds of guard.

`test.sh` now runs the isolated source mutations in
[`adapter_mutations.py`](../../../scripts/qa/adapter_mutations.py). It copies only the
current project sources/data into a temporary project and never edits the checkout:

| Mutation | Count | Required detection |
| --- | --- | --- |
| Omit one explicit assignment | 20 | Exit 1, the named non-default application assertion fails, no engine errors |
| Misspell one explicit assignment target | 20 | Exit 1 and the engine identifies the invalid target assignment |
| Rename a CombatState member and all its internal references | 20 | Structured `missing_state_property`, empty configs/resolutions/states, no engine errors |
| Change a target's runtime type | 1 | Structured `invalid_state_property_type`, no partial result |
| Misspell a generated configuration key | 1 | Structured `unknown_combat_parameter`, no partial result |
| Omit resolver profile overrides | 1 | Exit 1 and `enemy_per_attack_timing_preserved` fails |

All **63 controls** must pass their detection requirements. Ordinary positive runs
reject engine/script errors. Deliberate target-typo subprocesses specifically require
an engine error and use a short SceneTree timer to exit 1 if a script frame aborts;
a timeout or process crash is not accepted as successful detection. Godot 4.7.2
accepted the typed target typos under `--check-only`, then rejected them at execution.
Typed syntax alone therefore does not provide the whole contract: the runtime
property/type preflight and the non-default regression cases remain necessary.

[`mutations/results.json`](mutations/results.json) records every control's result;
[`mutations/excerpts.json`](mutations/excerpts.json) retains failed assertions or
expected engine errors and hashes of the full local logs. Full logs remain in
`/workspace/work/adapter-after/native-final/adapter-mutations/`.

## Validation

Every runner used a fresh artifact directory. Successful before/after commands:

```sh
bash scripts/tooling/test_builds.sh NEW_BUILDS_DIR
bash scripts/tooling/test_anatomy.sh NEW_ANATOMY_DIR
bash scripts/tooling/test_worldgen.sh NEW_WORLDGEN_DIR
BONESHED_GRAPHICAL_TIMEOUT=900 bash scripts/tooling/test.sh NEW_NATIVE_DIR
bash scripts/tooling/test_web.sh NEW_WEB_DIR
```

The native runner also executes the new integration/mutation checks. Browser tests
build fresh production and QA release exports and audit their packed resources.
No preview is published and no PR is merged by this task.

| Check | Before | After |
| --- | --- | --- |
| Build/salvage | 137 passed; 2 examples identical | 137 passed; 2 examples identical |
| Anatomy | 190 passed; 2 examples identical | 190 passed; 2 examples identical |
| Worldgen | 80 passed; 16 examples identical | 80 passed; 16 examples identical |
| Combat build integration | 76 passed | 532 passed |
| Combat rules | 118 passed | 118 passed |
| Encounter regression gates | 8 passed | 8 passed |
| Headless / rendered weapon timing | 159 / 209 passed | 159 / 209 passed |
| Graphical/input | 111 passed | 111 passed |
| Desktop browser, fresh release + QA exports | 18 passed | 18 passed |
| Native runner subprocesses | 16 expected exits | 18 expected exits, including 63 mutation controls |

The committed `before/` and `after/` logs, native exit manifests, browser checks and
export audits retain these results. Large exported ZIPs and duplicate PNGs remain
in the local artifact directories, not the PR. Raw artifacts:
`/workspace/work/adapter-baseline/` and `/workspace/work/adapter-after/` (successful
native after-run: `native-final/`).

## Behavioral comparison

[`comparison.json`](comparison.json) records hashes and exact comparisons. One copy
of each byte-identical trace is committed in `parity/`:

- Complete resolved player/enemy builds and translated configurations are identical,
  including effective attacks, overrides, identities and fingerprints. The baseline
  was captured independently from an archive of the fetched `main` commit.
- The runtime trace matches byte for byte for both actors' configuration, phase
  transitions and hit/block/deflect/rear/dodge/posture-break outcomes.
- All eight live-strategy records and eight encounter regression records are identical.
  Attack-only strategies still lose; blind guard toggling earns zero deflections and
  loses at 1,574 ticks. Skilled deflect/punish wins untouched in **418 ticks**, with
  three successful deflections, in both the probe and rendered duel.
- Headless and rendered basic/heavy weapon transform samples, phase timing records
  and the complete graphical state/check records compare exactly.

All **55 native PNGs are byte-identical**. The manifest records hashes for those
and the four browser captures. One browser PNG is identical; the other three differ
in 1,113, 177 and 86 RGB pixels out of 518,400. Inspection shows a small enemy pose
shift in the first capture and a few rendered edges in the others. Seventeen of the
18 browser check records are exactly equal; the keyboard-movement capture occurs at
tick 166 before / 174 after, with different final movement distances but both passing
the same input assertion. Attack travel, turning and defense check records agree.
Browser input uses wall-clock waits, so these captures are not a synchronized timing
benchmark; the deterministic native comparison is the visual-parity evidence.

The runtime snapshot can be regenerated with `source scripts/tooling/env.sh` followed by:

```sh
"$GODOT_BIN" --headless --path . \
  --script res://scripts/qa/combat_build_snapshot.gd -- --out=NEW_RUNTIME_JSON
```

The resolution comparison captured `Adapter.load_encounter()` from each checkout,
then serialized only `{configs: prepared.configs, resolved: prepared.resolved}` with
`JSON.stringify(value, "\t", true) + "\n"`; state objects are deliberately excluded.

## Development attempts and remaining limits

Early attempts were not counted as successful validation: the restricted execution
sandbox blocked the editor's local sockets and the initial Git fetch; the commands
passed after granting socket/network access. A direct scratch engine invocation omitted
the tooling's XDG directories and logged unwritable user-data paths; sourcing `env.sh`
fixed it, and the runtime snapshot was regenerated with a clean log.

Draft tests initially sorted mixed String/StringName keys differently; the coverage
matrix now normalizes keys to String. The first mutation implementation also matched
the temporary dictionary assignment, and initially assumed typed target typos would
fail parse checks; it now targets only explicit writes and verifies actual execution.
An omitted-defense mutation exposed a fixture's unchecked dictionary read; changing
that read to `get()` preserves the named assertion failure without unrelated script
errors. The first after-run stopped at that harness failure; the successful fresh
`native-final/` run is the only after native result reported above.

Automation proves parity for these deterministic fixtures, not human feel, attack
readability, hardware input latency, desktop GPU performance or cross-platform replay
identity. No human playtest was performed. Existing unrelated audit findings and gameplay
weaknesses remain outside this change. New parameters still need a schema entry, explicit
assignment and non-default matrix case. `create_state` is a preparation API, not an
untrusted snapshot loader or a live state mutation API; catalog stat bounds and build
validation remain owned by the existing catalog/resolver.
