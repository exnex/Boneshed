# Boneshed — Living Roadmap & Handoff

> **Last reconciled:** 2026-10-19 | **Verified `main` before this coordination update:** `0d500e9` (merged PR #21).
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
| **1. Excellent duel** | **Playable, provisionally human-accepted for continued development (2026-10-19)**: movement, lock, camera/zoom, attacks, guard/parry, dodge, posture, enemy AI and visual feedback. | Physical desktop playtest: recognition, fair hit timing, parry pressure, contact, responsiveness and overall enjoyment. |
| **2. Take the enemy's power** | **First loop implemented; full loop-specific human acceptance unconfirmed**: same player/enemy build model; Marrow Lunge → victory → salvage Marrow Arm → equip → use in second duel. | Check that the inheritance feels valuable, readable and balanced; actual augmentation tradeoffs are not approved. |
| **3. Compact expedition** | **First bounded integration implemented (PR #26), not yet human-accepted.** Isolated anatomy/body-graph prototype remains separate. | After combat feel gate: small atmospheric world, meaningful encounter, replayable seeded variation; extraction/carrying is still only a proposal. |
| **Later** | **Deferred**: broad procedural worlds, large build catalog, Tower of Memories, persistence/backend, trading/economy. | Define only after the core loop earns expansion. |

## Active priority queue

- [ ] **P0 — Human playtest on current `main`.** Use the default Godot F5 scene with F3 diagnostics **off** first. Test the light/heavy/lunge tells, precise point of impact, timed guard/parry, attack/movement/cancel/dodge feel, lock/orbit, close-range overlap, wall/corner obstruction and mouse-wheel zoom. Complete the salvage/equip/rematch sequence. Capture what feels unfair vs merely difficult. Use [presentation test](COMBAT_PRESENTATION_3.md) and [zoom test](CAMERA_ZOOM.md) as checklists.
- [ ] **P0 — Recheck the user's earlier browser feedback rather than assuming it is fixed or current.** The user liked lock and dodge, but reported hard-to-time parries, weak exact-impact telegraphs, and no apparent cost for parry spamming. That feedback came from an **older hosted build**; PRs #9/#19 changed the combat/presentation since. Confirm each issue on latest native gameplay and rank *reproducible* defects before assigning a balance PR.
- [ ] **P1 — Choose the next *single* combat fix from playtest evidence.** Known candidate: the current forward-box hit acceptance can disagree with a visible weapon arc at point-blank/lateral range. Investigate an independently tested swept weapon/body-proxy detector; **do not silently change combat rules or make animation authoritative**. See [presentation collision notes](COMBAT_PRESENTATION_3.md).
- [ ] **P1 — Evaluate one authored-animation vertical slice**, informed by the isolated [animation lab](ANIMATION_PIPELINE.md), after deciding clip rights and scope. No full animation overhaul or licensed asset commitment has been approved.
- [ ] **P2 — Refresh desktop browser preview only when deliberately requested/tested.** Existing GitHub Pages export is older than current `main`; source merges do not publish it automatically. Keep touch gameplay out of scope.
- [ ] **P3 — Only once Gates 1–2 pass human feel review**, plan the bounded first expedition by integrating, not mistaking, the isolated keyword/anatomy experiments for finished game systems.

## Review / delegation inbox

- **Open PRs:** none as of the 2026-10-19 GitHub check (PRs #1–#21 merged). **Recheck each session.**
- **Known delegated task currently awaiting outcome:** none verified. Write assignments here *before* sending prompts to agents: owner, task, expected PR, review requirement and the exact next action.
- **Outstanding review:** human native-gameplay judgement of combat presentation and camera zoom on current `main`. Automated and rendered tests were reported by the implementing PRs; a physical high-refresh playtest remains open.
- **Next handoff action:** run/collect current-build desktop playtest feedback, then propose one tightly scoped fix with acceptance criteria. Do **not** jump to worldgen integration solely because the combat PRs are merged.

## Verified completion checkpoints

- **PRs #1–#6:** foundation, courtyard duel, independent combat fixes/review, browser preview; touchscreen support subsequently removed in #6.
- **PRs #7–#15:** isolated keyword blueprint and shared builds; combat iteration 2; approved keyword identity and transformation *principles*; anatomy prototype; runtime build integration/hardening; engineering standards.
- **PR #16 (merged Oct 18):** playable Marrow Lunge salvage/equip/second-duel loop. **#17:** GDScript parser fix for combat fields.
- **PR #18 (merged Oct 18):** isolated animation research/lab; recommendations are **not approved production assets/mechanics**.
- **PR #19 (merged Oct 18):** articulated placeholder attack poses and reactions, restrained HUD, more readable camera. **Still needs human evaluation.**
- **PR #21 (merged Oct 19):** Living roadmap and desync-resistant handoff rules.
- **PR #20 (merged Oct 19):** smooth mouse-wheel camera zoom, 3.25–7.5 m selected range, 6 m initial, wall collision and per-session selection across encounters. **Still needs human evaluation.**

## Open design decisions / guardrails

- **Confirmed:** Sekiro-inspired active precision combat; corrupted souls; three-keyword worlds whose theme stays recognizable while seeded content varies; player/enemy shared builds; extreme transforms only if readable and fair; async Tower concept. See [decisions](DECISIONS.md).
- **Not confirmed:** final combat timings/balance, body slot taxonomy/tradeoffs, authored animation production policy, extraction loss/carry limits, worldgen numerical formulas, Tower reward/security mechanics, full platform/backend/economy scope.
- **Non-goals:** mobile/touch gameplay, creature collection and autobattlers, housing, broad survival scope.

## Recent handoff notes

- **2026-10-19:** Reconciled old roadmap against `main` and PRs #1–#20 after chat desynchronization. No open PRs. Moved stale “PR #3 awaiting review” state to completed history; kept combat feel and PR #19/#20 physical testing open. Established the rule that coordination changes must be persisted here during the same substantive project exchange.

## Command Center coordination — 2026-10-19

- **Review:** no open Boneshed PRs at check time; main `0d500e9`. No fresh Godot execution performed by ChatGPT.
- **Next Up (P0):** human desktop F5 playtest on current main, including parry-spam penalty, exact swing impact, dodge/lock/zoom and salvage/equip/rematch. Preserve findings before choosing fixes.
- **In Progress:** none verified. **Awaiting Review:** this coordination documentation PR; human feel gate. **Blocked:** gameplay prioritization depends on current-build observations.
- **Proposed Codex assignment (not dispatched):** focused reproducible combat-readability/parry-pressure diagnostic review; do not change balance before confirming defects; submit scoped PR only for independently justified fixes.
- **Proposed Claude assignment (not dispatched):** independent review of combat timing, presentation alignment and existing animation lab integration boundaries; report prioritized findings without implementing broad animation changes.
- **Decision:** no procedural-world or Tower expansion until excellent-duel and salvage-loop human acceptance. Research lab remains separate.

## Development continuation — 2026-10-19

- **User playtest:** owner reports the current build 'plays good for now' and requests continued development. This is provisional acceptance to advance, not confirmation of each combat mechanic or complete salvage/rematch loop. Earlier combat concerns remain watch items, not automatic blockers.
- **Next Up (P0):** build a **small first-expedition vertical slice**, connecting the existing isolated three-keyword WorldBlueprint to one traversable, atmospheric, seeded level and the existing duel. Reuse the current enemy/build/salvage loop; do not implement broad terrain generation, inventory/extraction loss, Tower, backend, or unapproved keyword algorithms as final design.
- **In Progress:** none externally dispatched or verified. **Awaiting Review:** next Codex implementation PR and Claude independent review after dispatch. **Blocked:** any asset licensing or consequential gameplay changes require approval; full human acceptance of salvage/rematch remains unconfirmed.
- **Codex proposed assignment (not yet dispatched):** implement a narrowly bounded expedition slice on `feat/first-expedition-slice`, preserving deterministic address+seed replay, stable keyword identity, readable combat geometry and current courtyard regression tests. Submit focused PR with rendered and headless evidence.
- **Claude proposed assignment (not yet dispatched):** independently inspect worldgen-to-gameplay integration contract and provide a bounded architectural/QA review on a separate branch; avoid editing the same gameplay files. Submit review findings or docs-only PR.
- **Decision:** prioritize a playable expedition over additional speculative combat tuning or infrastructure; no irreversible generator rules or licensed art approved.

## Parallel implementation ownership — 2026-10-19 (supersedes earlier proposed review assignments)

- **Owner direction:** current build plays well enough to continue. ChatGPT Command Center, **not Claude or Codex**, reviews both PRs and performs merges after validation. Agents work independently on separate feature branches; neither merges its own PR.
- **Codex — proposed, not dispatched:** `feat/first-expedition-slice`: keyword selection, seeded bounded layout/traversal, existing encounter integration. Own expedition/worldgen UI and level files. Do not modify combat animation/presentation files. PR with tests, rendered evidence, risks.
- **Claude — proposed, not dispatched:** `feat/combat-presentation-slice`: self-contained attack animation/telegraph/hit-reaction presentation improvements using existing animation lab, with no gameplay timing, hitboxes, damage, guard/parry or dodge balance changes. Own character visual/presentation resources and related tests. Do not modify worldgen, expedition UI or generated levels. PR with tests, rendered evidence, asset provenance.
- **Integration guardrails:** both branch from latest main, avoid shared scenes/resources and coordination docs (Command Center updates roadmap). If changes to common combat scene/scripts are unavoidable, isolate via new visual resources or flag blocker before editing. ChatGPT reviews diffs/tests/screenshots independently, then merges sequentially with post-merge regression checks; human playtest remains final feel gate.
- **Status:** assignments drafted; no external agent execution verified. Previous Claude architecture-review-only proposal is superseded.

## Parallel PR review and merge — 2026-10-19

- **Claude PR #25:** reviewed implementation source and file boundaries; merged squash as `913f390`. Adds presentation-only attack key poses, IK, active trails and reactions. Agent reports 63 motion assertions and existing gameplay suites passing. No GitHub Actions/status checks were associated with submitted commit; Command Center did not freshly execute Godot. Human presentation/performance checks remain pending; estimated CPU visual work increases according to PR.
- **Codex PR #26:** reviewed expedition entry/session lifecycle, deterministic layout consumer, world builder, evidence and file boundaries; merged squash as `7cd0654`. Adds First Expedition selection, seeded bounded causeway, arena encounter and inherited-augment rematch, plus deterministic/collision/playthrough tests. Agent reports 671/679 generation checks, 18 physics fixtures, legal-input rematch trace, existing suites and browser tests passing. No GitHub Actions/status checks were associated with submitted commit; Command Center did not freshly execute Godot.
- **Combined integration:** two PRs touch disjoint runtime source paths; GitHub merged both successfully, with #25 before #26. **Post-merge combined headless/rendered suite not yet executed**; agent tests were against separate branches, so interaction remains a verification task. User must playtest current merged desktop F5 build using two seeds and contrasting keywords, including updated animations, camera/lock and salvage/equip/rematch. Confirm performance at target refresh rate.
- **Next Up:** combine-regression test + user native build validation, then prioritize one gameplay/expedition limitation observed. Retain keyword algorithm, extraction and asset policy as provisional; no Tower/backend expansion.
- **PR queue:** both #25/#26 merged. **No assigned agent work currently verified.**

## Web preview refresh — 2026-10-19

- **User request:** the GitHub Pages URL is live but still serves the older courtyard. Refresh `gh-pages` with current First Expedition and merged combat-presentation code, as a desktop browser test only.
- **Blocker:** `project.godot` explicitly routes Web to `scenes/salvage_courtyard.tscn`; changing Pages branch alone does not change compiled PCK/WASM. The web export must be rebuilt with the pinned Godot 4.7.2 templates and audited. The Command Center cannot run the build in its current environment.
- **Proposed Codex assignment (not dispatched):** branch `feat/web-first-expedition-preview` from latest main; point production Web to `scenes/first_expedition.tscn`, retain existing Web QA courtyard fixtures and browser test coverage, add real-browser release expedition selector/launch/controls smoke tests, verify single-threaded Godot export, and use existing `publish_web_preview.sh` to publish audited export **only to `gh-pages`**, not `main` or `preview/browser-courtyard`. Preserve mobile non-goal. Provide export evidence, source commit and deployed commit; confirm live URL launches the expedition before claiming completion. Submit a source PR for Command Center review/merge; do not merge it yourself.
- **Owner coordination:** first review/merge source PR, then stage/publish web artifact. Avoid claiming `gh-pages` is up to date until served build is checked. No changes to game rules, worldgen or combat presentation.

## Owner gameplay review and parallel next work — 2026-10-19 (latest)

- **Human feedback:** owner played combined post-PR #25/#26 build and liked it. This supports continuing development and closes the basic 'does it run and feel promising' gate, not exhaustive performance/regression testing. The three chosen keywords currently sound like three descriptors, not a poetic **adjective + adjective + noun** place name.
- **Confirmed direction:** world addresses should read naturally as evocative place names; expose adjective/adjective/noun roles in the selection UI. Keep identity stable across seeds and never silently mutate the underlying seed-independent identity. Provisional vocabulary and positional semantics require explicit migration/test coverage.
- **Confirmed future combat direction, not yet implemented:** draw heavily from Last Oasis directional mouse-selected attacks/defenses and Mordhau-like blade trajectory, inertia, angular manipulation and weight. Retain responsive, intuitive Sekiro-speed deflections, dodge/cancels and posture. Desired families: short/medium/long reach; light/medium/heavy mass; blades/staves; one-handed plus shield or two-handed weapon guard. Input scheme, physics/hit authority, stamina and tuning are *not approved*; prototype in isolation before replacing production combat.
- **Confirmed NPC direction:** seek survival and counterplay, not just passive blocking: intelligently defend, evade/retreat, punish recovery and riposte, with readable, fair commitment and bounded reaction capability. Avoid omniscience or input-reading.
- **Parallel Codex proposed assignment (not dispatched):** `feat/keyword-grammar` — adjective/adjective/noun selector, curated supported terms/nouns, address formation and deterministic migration/compatibility tests; own selection and worldgen vocabulary/grammar only. No enemy AI or combat modifications. Preserve saved seeds and previous supported addresses where possible; document breaking cases.
- **Parallel Claude proposed assignment (not dispatched):** `feat/enemy-survival-ai` — focused survival/riposte/dodge/spacing changes for the current single swordsman, driven by observable combat cues and existing rules. Own AI/AI fixtures only; no selector/worldgen changes, no new weapon-swing system yet. Existing player combat and salvage loop remain intact. Evidence-backed headless/rendered checks; report timing fairness and potential balance concerns.
- **Command Center:** reviews both agent PRs and merges them; agent self-merge/review is prohibited. Follow previous branch boundaries. After both land, human-check combined native build. No open PRs at this check in either repo. Earlier web-preview refresh assignment remains **proposed/not dispatched**, not completed; do not falsely mark Pages published.
- **Next research/design slice (not delegated yet):** build an isolated mouse-direction combat input + swept-weapon prototype with clearly articulated constraints/acceptance before planning production integration. Preserve current baseline as fallback.
