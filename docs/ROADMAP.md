# Boneshed — Living Roadmap & Handoff

> **Last reconciled:** 2026-10-19 | **Verified `main`:** `a4363d3` (merged PR #20).
> **Purpose:** one short, durable record of what is done, what remains open, who is doing what, and the next decision. This is a *dependency order*, not a delivery schedule. Git history preserves prior revisions.
> **Authority:** `docs/DECISIONS.md` for approved design; merged code/PRs for implementation status; this page for current coordination. A passing automated test or merged PR is **not** proof that game feel is good.

## Resume protocol (for any new ChatGPT, Claude, or Codex session)

1. Read `AGENTS.md`, this page, and the relevant vision/decision documents. **Recheck GitHub's latest `main` and open PRs** before relying on the dated snapshot below.
2. Keep **implemented**, **human-validated**, **proposed**, and **unconfirmed** separate. Do not assume old browser feedback describes the latest native build.
3. **Before delegating a substantial task**, record its intended result, scope and review status here. **After each substantive project exchange** (decision, review, task assignment, completed PR, bug report or changed priority), reconcile and persist this page in GitHub during that exchange. A trivial acknowledgement need not create a commit.
4. Record review findings and **unfinished next actions**, not just completed PRs. Never erase an open item without noting completion, supersession or deliberate deferral. When several agents work in parallel, the coordinator owns reconciliation to avoid competing edits.
5. If GitHub cannot be updated, clearly say **“roadmap update not persisted”** and provide the exact pending change in the response. Do not claim a change was saved.

## Goal and release discipline

**Make one excellent, readable, demanding third-person duel with a satisfying defeat → salvage → equip → rematch loop before expanding scope.** Desktop keyboard/mouse is the target; desktop browser export is a **test convenience**, not a mobile release. Pin Godot **4.7.2.stable.official.ed1daf0bf**; verify engine/version when working in a new environment.

## Milestone board

| Gate | State | Acceptance still needed |
| --- | --- | --- |
| **0. Foundation** | **Implemented**: Godot project, shared agent/engineering rules, deterministic test tooling. | Keep tests and documentation aligned with actual entry scene. |
| **1. Excellent duel** | **Playable, not human-accepted**: movement, lock, camera/zoom, attacks, guard/parry, dodge, posture, enemy AI and visual feedback. | Physical desktop playtest: recognition, fair hit timing, parry pressure, contact, responsiveness and overall enjoyment. |
| **2. Take the enemy's power** | **First loop implemented, not human-accepted**: same player/enemy build model; Marrow Lunge → victory → salvage Marrow Arm → equip → use in second duel. | Check that the inheritance feels valuable, readable and balanced; actual augmentation tradeoffs are not approved. |
| **3. Compact expedition** | **Not integrated.** Isolated keyword WorldBlueprint and anatomy/body-graph prototypes exist. | After combat feel gate: small atmospheric world, meaningful encounter, replayable seeded variation; extraction/carrying is still only a proposal. |
| **Later** | **Deferred**: broad procedural worlds, large build catalog, Tower of Memories, persistence/backend, trading/economy. | Define only after the core loop earns expansion. |

## Active priority queue

- [ ] **P0 — Human playtest on current `main`.** Use the default Godot F5 scene with F3 diagnostics **off** first. Test the light/heavy/lunge tells, precise point of impact, timed guard/parry, attack/movement/cancel/dodge feel, lock/orbit, close-range overlap, wall/corner obstruction and mouse-wheel zoom. Complete the salvage/equip/rematch sequence. Capture what feels unfair vs merely difficult. Use [presentation test](COMBAT_PRESENTATION_3.md) and [zoom test](CAMERA_ZOOM.md) as checklists.
- [ ] **P0 — Recheck the user's earlier browser feedback rather than assuming it is fixed or current.** The user liked lock and dodge, but reported hard-to-time parries, weak exact-impact telegraphs, and no apparent cost for parry spamming. That feedback came from an **older hosted build**; PRs #9/#19 changed the combat/presentation since. Confirm each issue on latest native gameplay and rank *reproducible* defects before assigning a balance PR.
- [ ] **P1 — Choose the next *single* combat fix from playtest evidence.** Known candidate: the current forward-box hit acceptance can disagree with a visible weapon arc at point-blank/lateral range. Investigate an independently tested swept weapon/body-proxy detector; **do not silently change combat rules or make animation authoritative**. See [presentation collision notes](COMBAT_PRESENTATION_3.md).
- [ ] **P1 — Evaluate one authored-animation vertical slice**, informed by the isolated [animation lab](ANIMATION_PIPELINE.md), after deciding clip rights and scope. No full animation overhaul or licensed asset commitment has been approved.
- [ ] **P2 — Refresh desktop browser preview only when deliberately requested/tested.** Existing GitHub Pages export is older than current `main`; source merges do not publish it automatically. Keep touch gameplay out of scope.
- [ ] **P3 — Only once Gates 1–2 pass human feel review**, plan the bounded first expedition by integrating, not mistaking, the isolated keyword/anatomy experiments for finished game systems.

## Review / delegation inbox

- **Open PRs:** none as of the 2026-10-19 GitHub check (PRs #1–#20 merged). **Recheck each session.**
- **Known delegated task currently awaiting outcome:** none verified. Write assignments here *before* sending prompts to agents: owner, task, expected PR, review requirement and the exact next action.
- **Outstanding review:** human native-gameplay judgement of combat presentation and camera zoom on current `main`. Automated and rendered tests were reported by the implementing PRs; a physical high-refresh playtest remains open.
- **Next handoff action:** run/collect current-build desktop playtest feedback, then propose one tightly scoped fix with acceptance criteria. Do **not** jump to worldgen integration solely because the combat PRs are merged.

## Verified completion checkpoints

- **PRs #1–#6:** foundation, courtyard duel, independent combat fixes/review, browser preview; touchscreen support subsequently removed in #6.
- **PRs #7–#15:** isolated keyword blueprint and shared builds; combat iteration 2; approved keyword identity and transformation *principles*; anatomy prototype; runtime build integration/hardening; engineering standards.
- **PR #16 (merged Oct 18):** playable Marrow Lunge salvage/equip/second-duel loop. **#17:** GDScript parser fix for combat fields.
- **PR #18 (merged Oct 18):** isolated animation research/lab; recommendations are **not approved production assets/mechanics**.
- **PR #19 (merged Oct 18):** articulated placeholder attack poses and reactions, restrained HUD, more readable camera. **Still needs human evaluation.**
- **PR #20 (merged Oct 19):** smooth mouse-wheel camera zoom, 3.25–7.5 m selected range, 6 m initial, wall collision and per-session selection across encounters. **Still needs human evaluation.**

## Open design decisions / guardrails

- **Confirmed:** Sekiro-inspired active precision combat; corrupted souls; three-keyword worlds whose theme stays recognizable while seeded content varies; player/enemy shared builds; extreme transforms only if readable and fair; async Tower concept. See [decisions](DECISIONS.md).
- **Not confirmed:** final combat timings/balance, body slot taxonomy/tradeoffs, authored animation production policy, extraction loss/carry limits, worldgen numerical formulas, Tower reward/security mechanics, full platform/backend/economy scope.
- **Non-goals:** mobile/touch gameplay, creature collection and autobattlers, housing, broad survival scope.

## Recent handoff notes

- **2026-10-19:** Reconciled old roadmap against `main` and PRs #1–#20 after chat desynchronization. No open PRs. Moved stale “PR #3 awaiting review” state to completed history; kept combat feel and PR #19/#20 physical testing open. Established the rule that coordination changes must be persisted here during the same substantive project exchange.
