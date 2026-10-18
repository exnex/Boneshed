# Gate 2 — courtyard combat from shared builds

**Confirmed task:** integrate PR #8's shared build foundation without changing the
Combat Iteration 2 duel. Baseline: `4c651e3` on `main`, fetched before implementation;
PR #8 and Combat Iteration 2 are merged, and no open PRs were returned at preparation.
**Proposed:** all existing combat numbers remain evaluation tuning. **Open:** human
judgment of feel and the later signature-ability/equipment flow.

## Runtime path

`data/builds/courtyard.json` holds two ordinary id-only builds. Both reference the
same Notched Sword and ability definitions in `data/builds/catalog.json`.
`Courtyard.prepare_builds()` loads/validates the catalog once, then the combat
adapter uses one `BuildRules` resolver instance to resolve both actors.

The adapter translates only fresh successful resolutions into runtime parameters.
It prepares **both** configurations and constructs both validated combat states before the courtyard creates input bindings,
world geometry or fighters. A catalog/build/compatibility failure reports
`Courtyard build initialization failed` with actor/error context and exits 1.
There is no fallback to a partly configured fighter. A newly configured combat
state resets health from the resolved maximum before being attached to its actor.
Encounter resets retain the prepared configuration, as before; this is not a live
item-equipping or hot-reload API.

`CombatState` still owns the shared phase, defense, damage and cancellation rules.
`Fighter` still owns movement integration, steering, geometry, hit validation and
procedural presentation. `Player` owns input/camera; `Swordsman` owns behavior. The
adapter has no node creation, controller or animation responsibilities. Fighter
walk speed is the one movement parameter copied from resolved stats; acceleration,
braking, dodge travel, gravity and attack footwork remain in their existing layer.

## Exact values and per-attack differences

| Parameter | Player | Corrupted swordsman |
| --- | --- | --- |
| Health / posture maximum | 100 / 100 | 100 / 100 |
| Walk speed | 5.5 | 2.7 |
| Basic / heavy windup | 0.34 / 0.85 s | 0.62 / 0.85 s |
| Basic / heavy active | 0.16 / 0.16 s | 0.16 / 0.16 s |
| Basic / heavy recovery | 0.45 / 0.45 s | 0.65 / 0.65 s |
| Basic / heavy health damage | 18 / 32 | 18 / 32 |
| Unguarded hit posture, either attack | 18 | 18 |
| Basic / heavy incoming block cost | 28 / 42 | 10 / 15 |
| Guard chip / deflection window | 12% / 0.16 s | 12% / 0.16 s |
| Deflection pressure on attacker | 42 | 42 |
| Posture recovery delay / rate | 1.5 s / 12 per second | 1.5 s / 12 per second |

The old sample enemy profile had 120 posture and global windup/recovery scales of
1.5/1.4. Those were approximations, never the live courtyard values. Catalog 0.2.0
replaces them with the live 100 posture, unit scales and explicit per-ability
`ability_overrides`. Override values replace definition values **before** applying
wielder windup/recovery scales, then round using the existing resolver precision.
This allows a slower basic windup without slowing the heavy windup.

`hit.posture_damage` now carries ordinary hit posture pressure. Incoming block
pressure normally comes from the incoming ability's `hit.guard_posture`. A profile
may supply `guard_posture_overrides` keyed by incoming binding, expressing the
swordsman's existing braced costs without changing outgoing attacks or duplicating
defense rules. Deflection pressure and posture recovery delay/rate are actor stats.

Basic and heavy active/recovery durations are independent runtime parameters.
The existing `active_duration`/`recovery_duration` accessors select the current
attack for phase stepping and presentation. Shared mechanics such as rearm, frontal
protection, heavy commitment, dodge/cancel priority and stagger floors stay in the
rules. No telegraph, movement, cancellation, AI policy or steering rule changed.

## Compatibility and scope

The adapter supports the two existing curated sword modules. Both are required by
this encounter. Unsupported equipped modules/bindings, incompatible hit geometry,
timings shorter than the current commitment pose, and invalid/nonfinite effective
values fail before startup. Sword reach/width remain 2.35/1.6 in the geometry and
presentation layer; changing those data fields requires a compatible attack module.
An unequipped experimental ability can remain in the catalog. Equipping Marrow Arm
in the live encounter is rejected because its module is not implemented.

Catalog 0.2.0 invalidates old versioned fixtures rather than silently accepting
changed definitions. Generated salvage examples were regenerated: identities and
fingerprints change with the catalog, the sample enemy's posture is now 100, and
its experimental lunge no longer inherits the old approximate global slowdowns.
No lunge executes in gameplay. The 137 build checks retain their coverage, with
expected values/version updated to this exact courtyard profile.

The current three slots, augmentation-penalty check and three catalog bindings
remain provisional fixtures. The two-module restriction is a capability check of
this adapter, not a permanent anatomy or input design. This PR does not implement
anatomy architecture, signature attacks, salvage prompts, inventory, customization,
new enemies, keyword changes, touchscreen gameplay or preview publication.

## Validation

Use the checksum-verified **4.7.2.stable.official.ed1daf0bf** engine:

```sh
bash scripts/tooling/setup.sh
BONESHED_GRAPHICAL_TIMEOUT=900 bash scripts/tooling/test.sh artifacts/gate2-native
bash scripts/tooling/test_builds.sh artifacts/gate2-builds
bash scripts/tooling/test_worldgen.sh artifacts/gate2-worldgen
bash scripts/tooling/test_web.sh artifacts/gate2-web
```

The native runner now also runs 76 integration checks and an expected-failure
startup subprocess. The integration fixture captures pre-integration values,
60 Hz basic/heavy phase transitions and hit/block/deflect/rear/dodge/break outcomes
for both actors. It was generated with the same snapshot script against the
untouched main checkout, and is compared byte for byte against the live scene.
The snapshot can be captured independently with:

```sh
Godot_v4.7.2-stable_linux.x86_64 --headless --path /path/to/checkout \
  --script /path/to/combat_build_snapshot.gd -- --out=/tmp/runtime.json
```

Controlled test catalogs prove actual runtime changes to health, walk speed, hit
and block posture, damage, deflection pressure, posture recovery, and independent
basic/heavy phase timing. Tests also reject invalid second actors, stale versions,
missing attacks, unsupported modules/shapes, malformed overrides and numeric overflow.
Two independent source-mutation controls omit damage application and profile
overrides; each must fail its designated regression while sources are restored.

Results, before/after strategy measurements, rendered comparisons and environment
limitations are indexed in [the evidence record](evidence/combat-build-integration/README.md).
Automation establishes rule/input parity in these fixtures, not a human feel verdict.

## Smallest recommended next PR

Implement one curated Marrow Lunge execution module and a deterministic **test-only**
victory → acquire → equip → resolve → second-duel fixture. Both enemy and player
should execute the same module from the same ability definition. Extend adapter
compatibility only for that integrated module and prove atomic rebuilds, the
provisional tradeoff and ability identity end to end. Defer salvage prompts,
inventory, customization and anatomy expansion. Human playtesting should assess
its telegraph and controls before a general equipment flow is added.

## Adapter correctness follow-up (F1)

`create_state(config)` now returns `{ok, errors, state}`. It rejects unknown/missing
configuration fields, invalid values and missing or mistyped runtime properties before
applying the 20 supported parameters through explicit typed assignments. Failure returns
`state: null`. `prepare_encounter()` constructs both states transactionally and returns
`states.player` / `states.enemy`; any error returns empty configs, resolutions and states.
The courtyard attaches these prepared states before each fighter enters the tree.

The JSON-shaped resolved/configuration dictionaries stay at the build boundary. Their
keys are validated before runtime use; none is passed to `Object.set()`. The one sparse
runtime dictionary, `guard_posture_overrides`, describes costs by incoming binding and
is validated and deep-copied per state. No combat tuning, rule, movement, AI, input or
presentation change is intended.

The integration suite now runs 532 checks, including a non-default value for every
parameter on both profiles through direct construction and a live scene, plus missing
and misspelled keys and invalid values. The native runner adds 63 source mutation
controls and a state-validation startup failure subprocess. See the
[hardening evidence](evidence/combat-adapter-hardening/README.md) for before/after suites,
deterministic traces, controls and limitations. The earlier validation counts above
record the original integration PR.
