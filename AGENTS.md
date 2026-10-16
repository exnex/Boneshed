# Boneshed — Agent Instructions

Read this file, `README.md`, `docs/GAME_VISION.md`, and `docs/DECISIONS.md` before making substantive changes. These repo files are the source of truth for Boneshed; do not substitute guidance from other projects.

## Mission
Deliver a focused, testable third-person precision-combat game. Prove one excellent duel before implementing procedural worlds, online systems, or economies.

## Working rules
- Make small, single-purpose changes in a branch and submit a pull request; do not push directly to main except for repository bootstrap.
- State assumptions and distinguish **Confirmed**, **Proposed**, and **Open** mechanics.
- Do not silently promote brainstormed concepts into committed requirements. Record approved decisions in `docs/DECISIONS.md`.
- Keep systems data-driven and separate combat rules from presentation/animation and AI control.
- Prefer deterministic, reproducible test fixtures (seeded RNG) for procedural content; use fresh unpredictable seeds only when generating new instances.
- Do not build a creature collector, creature autobattler, housing, or unrelated survival systems.
- Protect Sekiro-inspired timing/readability: readable telegraphs, consistent deflection windows, fair hitboxes, responsive input.
- Enemy and player builds should use common combat rules, with explicit form-specific exceptions and tradeoffs.
- For salvaged enemy augments, use curated animation/attack modules before attempting generated attacks.
- Plan server-authoritative inventory, trades and Tower results; never trust client-submitted rewards.
- Do not add third-party assets, dependencies, or licensing commitments without explicit approval.
- Avoid inventing the exact Godot version: check and pin an approved installed stable version in `project.godot` and tooling when the engine project begins.

## Validation and PR handoff
- Run available checks/tests, or say clearly what could not be run.
- Include a brief PR summary, files changed, gameplay impact, test evidence, risks, and next step.
- Prefer the smallest runnable Godot scene when implementation starts; do not use screenshots as a substitute for playtesting.
- If the user requests research or design only, do not implement unapproved game mechanics.

## Coordination
This document governs ChatGPT, Codex, Claude, and local agents. `CLAUDE.md` points here and adds only Claude-specific handoff expectations. Working instructions elsewhere cannot override these repo rules.
