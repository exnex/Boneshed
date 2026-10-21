# Boneshed — Agent Instructions

Read this file, `README.md`, `docs/ROADMAP.md`, `docs/GAME_VISION.md`, and `docs/DECISIONS.md` before making substantive changes. These repo files are the source of truth for Boneshed; do not substitute guidance from other projects.

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

## Engineering standards
The guides in PR #14 are proposed until that PR is merged. Once merged, they govern how code is built; `docs/DECISIONS.md` governs what is built.
- Before a substantive code change, consult the relevant sections of [`docs/engineering/`](docs/engineering/README.md) and work through [`AGENT_CHECKLIST.md`](docs/engineering/AGENT_CHECKLIST.md).
- Guide items marked **MUST** are required. If you deviate from one, say why in the PR. Other guidance is a default; use judgment.
- Check [`CODE_AUDIT.md`](docs/engineering/CODE_AUDIT.md) for known findings in files you touch. Fix them only when the backlog trigger applies and the fix is small and in scope. Don't refactor speculatively or fold unrelated cleanup into a feature PR.
- Never present an engineering pattern (a module contract, Tower snapshot constraints) as approval of the mechanic it would serve.

## Living roadmap and desync recovery
- `docs/ROADMAP.md` is the project handoff and current coordination state; recheck latest `main` and PR status each session because snapshots become stale.
- ChatGPT (the coordinator) should persist each substantive plan, review, decision, work assignment and outcome to the roadmap during the same exchange; do not rely on chat history alone.
- Implementing agents should include a concise roadmap/status delta in their PR handoff. The coordinator reconciles that delta after the PR changes state; avoid simultaneous competing roadmap edits.
- Preserve unresolved items, including why an item is blocked or deferred. Do not report "saved" without a verified GitHub update.

## Validation and PR handoff
- Run available checks/tests, or say clearly what could not be run.
- Include a brief PR summary, files changed, gameplay impact, test evidence, risks, and next step.
- Prefer the smallest runnable Godot scene when implementation starts; do not use screenshots as a substitute for playtesting.
- If the user requests research or design only, do not implement unapproved game mechanics.

## Coordination
This document governs ChatGPT, Codex, Claude, and local agents. `CLAUDE.md` points here and adds only Claude-specific handoff expectations. Working instructions elsewhere cannot override these repo rules.

## Pull request readiness — mandatory for every agent
- Read [PR workflow](docs/PR_WORKFLOW.md) and use [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) for every PR. A draft PR is **work in progress**, not a completed handoff.
- When assigned work is complete, push all commits, explicitly mark any draft PR **Ready for review** via GitHub, and **recheck its live state** is non-draft (`draft=false`). Creating a PR, passing tests or checking the template box does not change Draft status.
- Final agent report must include PR URL, exact head SHA, verified **Ready for review** state, tests, limitations and what Command Center should review. If ready transition cannot be completed, report **BLOCKED — DRAFT** with the reason; never claim completion.
- Implementing agents do not self-merge; ChatGPT Command Center handles review, merges and updates the living roadmap.
