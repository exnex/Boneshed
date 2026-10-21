# Pull request lifecycle and agent completion contract

Applies to Claude, Codex, ChatGPT and other automated contributors to this repository. The coordinator reviews and merges; authors never self-merge.

## States

| State | Meaning | What the agent does |
| --- | --- | --- |
| **Draft / work in progress** | Code or analysis is incomplete, evidence is being gathered, or an author-side blocker exists. | Open/keep a draft, document remaining work, do **not** say the assignment is finished. |
| **Ready for review** | All assigned scoped work has been pushed; test results and caveats are documented. Human approval/merge may still be pending. | Use **Ready for review** explicitly (if a draft); reread GitHub and verify `draft=false`. |
| **Blocked — draft** | Agent cannot finish or lacks permission to mark ready. | Leave draft, state the concrete blocker and PR URL, explicitly request coordinator intervention. |
| **Merged** | Coordinator reviewed and merged. | Only coordinator confirms after GitHub reports merged. |

## Required author workflow

1. Read AGENTS.md, this guide, the current repo state and relevant instructions; reconcile any prior PRs.
2. Create a dedicated branch; open a **draft** PR early if iterative feedback helps, or create a non-draft PR on completion.
3. Use [the pull request template](../.github/PULL_REQUEST_TEMPLATE.md), including change scope, exact tests/results, risks, omitted tests, follow-up and owner-playtest instructions.
4. Complete the assigned work. Re-run checks against the final head as practical and disclose any missing or failing checks; failure is not silently acceptable.
5. **Last mandatory step:** publish final commits; inspect the PR in GitHub. If it is Draft and complete, invoke **Ready for review**. **Verify the new live status**, not merely the tool invocation or checklist text. Do not declare completion while `draft=true`.
6. Final handoff must include the **PR URL, exact head SHA, verified state (Ready for review / Blocked — draft), tests, known issues and next action**. Never claim the PR is merged; never self-merge or self-approve.
7. Coordinator reviews the implementation/evidence, checks CI and conflicts, chooses merge or requests changes, and updates durable roadmap/status files. **Ready for review does not mean approved or merged.**

**Special case:** A review finding or source-accuracy uncertainty is not automatically an author-side blocker; complete analysis with explicit evidence limits can be Ready for review. A missing deliverable, failing mandatory check, unresolved required change, or incomplete task should stay Draft.

If the PR UI/API does not permit changing state, report the precise obstacle and leave it Draft. Do not ask the user to manually mark it ready unless you lack the necessary permission/tool. Do not fabricate readiness.

## End-of-task report example

```text
Repository:
PR URL:
Head commit SHA:
Verified GitHub state: READY FOR REVIEW (draft=false) / BLOCKED — DRAFT
Implemented:
Tests run (exact commands/results):
Tests not run / open risks:
Human validation needed:
Next coordinator action: review PR; do not assume merge.
```
