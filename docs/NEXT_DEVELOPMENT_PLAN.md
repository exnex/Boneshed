# Development milestones after directional-combat and ranked-ghost design — 2026-10-20

**Status:** Coordinator's staged implementation recommendation, not final authorization of every future rule. Owner has approved directional lab hold-to-release and described the asynchronous ghost/optional entrance-exam vision. All milestones past the immediate isolated AI refinement require follow-up playtest/decision gates. Main repo source of truth remains `docs/ROADMAP.md`, `docs/DECISIONS.md`, and `docs/ASYNC_RANKED_GHOSTS.md`.

## Stage 1 — Immediately next: fair readable, configurable lab combat intelligence

- **Claude / Boneshed**: In isolated `scenes/melee_lab.tscn`, improve AI opponent visible-telegraph responses, sensible footwork, recovery punishment, directional guard, strategic release/feints, fairness/perceptual lag. Distinguish a small set (2-3) of data-configured tactics profiles (e.g. aggressive/defensive/opportunist) and express decisions as legal combat intents, with capability checks rather than hidden overrides. Keep implementation lightweight, focused, tested and browser-playable. Preserve player-controlled indefinite chamber and held guard, fresh parry age, no input-reading and original game.
- **Codex / ai-game-dev-lab**: Independent design/benchmark for future build-conditioned rule policies. Prototype validated priority-rule grammar, perceptual inputs with age, capability filtering from equipment, deterministic tie order, CPU budget, anti-omniscience tests and measurable fighting-style divergence. Reference current lab contracts and compare implementation/proposal; no changes in Boneshed.
- **Gate:** repeatable agent tests, rendered traces, owner browser-playtest; owner can recognize different styles and explain why they were hit/defended, while attack and guard feel remain good. No promise of production integration or backend.

## Stage 2 — Small local programmable tactics prototype

- Build a concise editor/presets for prioritized conditions/actions: guard by observed threat, move to spacing, punish recovery, retreat under posture pressure, etc. Validate compiled policy against resolved build actions and report disabled tactics upfront. Policy changes affect AI only; avatar/equipment unchanged.
- Provide test/simulation mode, human-readable decision traces, deterministic replays, versioned policy/format, fair reaction and bounded evaluation costs. Demonstrate two different AI defenses on same frozen local build.
- **Gate:** controlled player A/B verifies policies act differently without input cheating. Keep as lab/offline; UI architecture and naming are provisional.

## Stage 3 — Production precision combat adoption gate

- Only after explicit owner playtest acceptance, plan small integration of lab directional mechanics into the real First Expedition, preserve expedition keyword, salvage, equipment, Enemy AI, camera and default web entry; verify shared player/AI combat actions, reach/weight/grip, changing body anatomy. Use feature flags/migration and complete regression suite.
- **Gate:** playable production slice retains reliable hitboxes, deflections and salvage, with demonstrably good feel. Do not replace default before approval.

## Stage 4 — Character economics and immutable build foundation

- Confirm which inventory and equipment are surrendered in imprint and what account/stash progression survives; distinguish stored gear from semi-permanent body modifications that require replacement to change.
- Add local inventory/equipment legality, anatomy reset and irreversible transactional snapshot prototype, versioned frozen build record and separately editable policy record. Prevent item duplication and enforce compatibility.
- **Gate:** deterministic replay, one active snapshot, retirement history and safe rollback/error cases in offline fixture.

## Stage 5 — Offline optional Tower entrance trial

- Use current *unsacrificed* human-controlled build vs progressively higher-ranked AI ghosts; **five sequential opponents, three defeats of each same opponent, three shared player lives across whole run**. Any player HP-zero costs one life; three deaths end attempt. It is optional and not a submission prerequisite. Ten-opponent option and rewards remain undecided. Recovery of HP/posture/resources and progress after player death must be clarified before implementation.
- Simulated/local opponent ranking samples until real backend. Expose why human-controlled trial is not proof of an AI-oriented build's potential.
- **Gate:** local user-playtested 15-win endurance prototype without invoking real matchmaking or sacrificing the build.

## Stage 6 — Persistent online asynchronous ranked system

- Owner ranks by winning offense with their **frozen active submitted Echo** against others' AI ghosts, and earns defense results when their own AI ghost defeats challengers. After imprint physical live build is sacrificed/reset. One active submitted ghost; later submissions retire previous ones but preserve historical stats. Frozen build may never be edited post-submission; owner can update separate tactics policy.
- Requires deliberate backend choices: authoritative validation, immutable snapshot/equipment transaction, anti-farming matchmaking, policy-version pinning, deterministic audit, server-run combat/results, accounts/auth/security, leaderboards, scoring and retired-record retention. Naming still open.
- **Gate:** security audit and owner-approved rating/economy before public ranked launch.

## Immediate parallel ownership / non-overlap

- Claude: `exnex/Boneshed`, suggested branch `feat/melee-lab-ai-styles`; lab AI/controller/data, minimal QA/doc updates. New agent branch/PR; never self-merge, never publish unreviewed changes, do not edit `docs/ROADMAP.md` or `docs/DECISIONS.md`.
- Codex: `exnex/ai-game-dev-lab`, suggested branch `research/ghost-tactics-contract`; narrow research+deterministic policy fixtures, sources/evidence; no Boneshed game source. New PR; never self-merge.
- Command Center: review both open PRs, cross-compare AI policy implications, merge independently when safe, update both durable statuses, verify Pages Actions after gameplay merge and source-branch assets; owner plays test URL.
- Both repos had no open PRs when this plan was prepared. Prompts are supplied to owner; recording the plan does **not** dispatch external coding agents.

## Avoid scope creep

No online ranked, tower entrance exam, production combat replacement, inventory economy, new anatomy parts, shield balancing or graphical overhaul in Stage 1. Do not give omniscient decisions or perfect reaction to opponents. Do not impose a time limit on human-held attacks/guards. AI should use intentional release via its policy, not physical auto-attack.

## 2026-10-20 design amendment: soul-seeded tactical graph

- **Before implementing Stage 2**, read [Soulbound Tactics](SOULBOUND_TACTICS.md) and revised [ASYNC_RANKED_GHOSTS.md](ASYNC_RANKED_GHOSTS.md). Owner now wants a **required collected soul** defining default AI temperament, with **build-granted tactic points and capability-specific nodes**. Players invest a finite budget into a **modular procedural cause/effect behavior graph**, rather than merely editing a universal generic rules list.
- **Stage 1 unchanged in size, amended in intent:** Claude's isolated melee lab styles should be treated as prototypes of different innate **soul behaviors**, using legal combat intents and readable perception; Codex's independent research should test a soul+build+point-budget graph compiler and meaningful style divergence. Neither agent has a new job automatically just because docs change; if existing prompts were handed off, share this amendment with them before assumptions harden.
- **Stage 2 replaces generic priority-rule-only editor** with a bounded, deterministic, pre-submission-previewable soul+build-generated graph and mutable investment policy, cost validation and clear action availability. Do not draw a giant PoE-style passive grid until evaluation and player UX are validated. Preserve frozen build, legal actions, anti-omniscience, versioning, and editing after imprint.

## Amendment — soul-rooted tactical graph, 2026-10-20

Stage 1 should treat its prototype AI styles as sample **soul defaults**, maintaining readable, fair perception and legal combat intent. Independent Codex tactics research should use **soul + resolved build capabilities + limited point budget** as inputs, and test generated options and policy outcomes on identical and varied builds. Stage 2 is no longer just a generic priority-rule editor: prototype a deterministic bounded graph generated from soul and build, with pre-imprint preview, investment costs, clear WHEN/IF/THEN action routing and post-imprint editing. Do not build a huge passive node atlas, implement production soul drops or ranked economy yet. Read [Soulbound Tactics](SOULBOUND_TACTICS.md) before agent implementation. Previously supplied agent prompts need this update if already dispatched.

## Priority amendment — stamina before advanced tactics, 2026-10-20

- Owner confirms **stamina as required core combat resource**: dodges/rolls and attacks expend build-modified stamina; heavy armor slows movement; heavy weapons swing slower and cost more stamina; light weapons favor quick low-impact barrages. See [STAMINA_AND_WEIGHT.md](STAMINA_AND_WEIGHT.md).
- **Stage 1 should include a tightly scoped isolated lab stamina/weight validation before locking AI tactic policy grammar or deep opponent balance.** Sequence: (1) weapon/armor derived action-cost legality + stamina meter + basic movement impact, (2) human-playtested light/heavy and dodge/roll tradeoffs with existing responsive cancel/indefinite chamber preserved, (3) AI styles using legal stamina constraints and perception, (4) soul/build-generated tactics research integrating stamina-aware conditions. Avoid assuming ongoing agent prompts have been changed unless owner sends amendment.
- Do not broaden to full inventory, armor content pipeline, ranked backend or Tower stamina recovery rules. Stamina numbers and zero-stamina behavior remain provisional until playtest.
