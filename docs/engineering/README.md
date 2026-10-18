# Engineering standards

How to write and structure Boneshed code in Godot 4.7.2. These are **proposed engineering**
standards until PR #14 is merged.
They don't approve gameplay mechanics; [DECISIONS.md](../DECISIONS.md) does.

| Document | Read when |
| --- | --- |
| [AGENT_CHECKLIST.md](AGENT_CHECKLIST.md) | Before every code PR (one page) |
| [GDSCRIPT_GUIDE.md](GDSCRIPT_GUIDE.md) | Writing or reviewing GDScript: typing, errors, data sharing, determinism, serialization, footguns, common agent mistakes |
| [GODOT_DEVELOPMENT_GUIDE.md](GODOT_DEVELOPMENT_GUIDE.md) | Adding a system, scene, actor, module, AI, asset or test layer |
| [CODE_AUDIT.md](CODE_AUDIT.md) | Before touching a file: known findings and the prioritized debt backlog |
| [SOURCES.md](SOURCES.md) | Checking the evidence behind a recommendation |
| [Independent review](../evidence/engineering-review/README.md) | Corrections, verification limits and PR #14 merge assessment |

Each recommendation is tagged **[Official]**, **[Measured]**, **[Consensus]**, **[Boneshed]** or
**[Opinion]**. Only **MUST** items are enforced; everything else is a default you may deviate from
with a stated reason.

**Daily use:** start with the checklist, then open only the sections relevant to the change.
The longer guides and audit are references, not required cover-to-cover reading for every PR.

**Updating these documents.** Re-check them on every engine version change. When a finding is
fixed, mark it in CODE_AUDIT.md rather than deleting it.
