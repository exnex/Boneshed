# Boneshed

**A dark fantasy precision-combat action RPG about releasing corrupted souls and inheriting their power.**

Boneshed is a new game concept, separate from an earlier project with the same name. Players use three poetic keywords to enter unpredictable, haunting worlds; master Sekiro-inspired duels; salvage enemy gear and body augmentations; and evolve their builds. In the asynchronous **Tower of Memories**, other players can actively fight AI-operated snapshots of saved builds.

## The central loop

**Generate a world → face a corrupted soul → learn and defeat its build → salvage its signature ability → evolve your own build → face harder encounters.**

The priority is one truly enjoyable duel, not an expansive feature list.

## Project status

**Preproduction / design foundation.** No playable Godot project yet. Exact Godot version must be chosen and pinned when development begins.

## Start here

| Document | Purpose |
| --- | --- |
| [Game vision](docs/GAME_VISION.md) | Core identity, pillars, and non-goals |
| [Decision log](docs/DECISIONS.md) | Confirmed vs proposed features |
| [Roadmap](docs/ROADMAP.md) | Prototype sequence and quality gates |
| [AGENTS.md](AGENTS.md) | Shared instructions for AI development agents |
| [CLAUDE.md](CLAUDE.md) | Claude-specific handoff |

## First playable milestone

A ruined courtyard, responsive player combat, and one corrupted swordsman wielding a unique salvageable attack. The player learns the move by fighting against it, wins the duel, equips the augmentation, and uses it in a second encounter.

## Collaboration

ChatGPT coordinates design and review; Claude and Codex can implement small PR-scoped tasks, subject to the same repository instructions. Keep work on branches and submit pull requests. Do not assume that headless tests prove game feel.

## Scope discipline

Creature collection, autobattling, housing, and large survival systems are **not part of this game**. Marketplace, events, and leaderboards are possible supporting systems, not first-milestone requirements.
