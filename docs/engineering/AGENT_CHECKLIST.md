# Agent change checklist

Use this before opening a PR that changes code. It condenses the [GDScript guide](GDSCRIPT_GUIDE.md),
the [development guide](GODOT_DEVELOPMENT_GUIDE.md) and the [audit](CODE_AUDIT.md). It isn't a
substitute for them, and not every line applies to every change.

## Before editing

- [ ] Read `AGENTS.md`, `DECISIONS.md`, and the guide sections relevant to this change.
- [ ] Is the mechanic **Confirmed**? If it's Proposed or Open, implement only what the task explicitly approves.
- [ ] Check [CODE_AUDIT.md §3](CODE_AUDIT.md#3-prioritized-technical-debt-backlog): does this change touch a
      backlog item whose trigger is "when touched"? Fix it only if it's small and in scope; otherwise note it.
- [ ] Identify the layer: data, rules, adapter, actor, controller or presentation. The change goes in the layer
      that owns the concern, and dependencies point one way only.

## While editing

- [ ] Runtime code is statically typed. `Variant` data is converted at a marked boundary.
- [ ] No new autoload, global mutable state, plugin, asset or dependency without explicit approval.
- [ ] No new string-keyed `set()`/`get()`/`call()`/event codes without validation or an enum.
- [ ] No duplicated state: derive it instead of storing it twice.
- [ ] Shared or loaded data isn't mutated; copy at the point of mutation.
- [ ] Rules don't read input, AI or visuals. Presentation reads rule state and never decides hit timing.
- [ ] Randomness uses a named seeded stream; nothing uses global `randf()`/`randi()` in rules or generation.
- [ ] Persisted or shared data is ids plus primitives only, versioned, and strictly validated.
- [ ] Tuning lives in data or one named owner and is labeled provisional.
- [ ] No abstraction built for a second case that doesn't exist yet.

## Before the PR

- [ ] Run the relevant runners (`test.sh`, `test_builds.sh`, `test_worldgen.sh`, `test_anatomy.sh`;
      `test_web.sh` for export or input changes). Report exactly what ran and what didn't.
- [ ] New behavior has a check **and** a negative control or mutation that makes the check fail.
- [ ] A test that changes data asserts a runtime value that differs from its default.
- [ ] Performance claims come with a measurement on representative hardware (not llvmpipe).
- [ ] Deviations from a guide **MUST** rule are stated and justified in the PR.
- [ ] Don't claim feel, readability or fun from automated runs.
