# Boneshed

**A dark fantasy precision-combat action RPG about releasing corrupted souls and inheriting their power.**

Boneshed is a new game concept, separate from an earlier project with the same name. Players use three poetic keywords to enter unpredictable, haunting worlds; master Sekiro-inspired duels; salvage enemy gear and body augmentations; and evolve their builds. In the asynchronous **Tower of Memories**, other players can actively fight AI-operated snapshots of saved builds.

## The central loop

**Generate a world → face a corrupted soul → learn and defeat its build → salvage its signature ability → evolve your own build → face harder encounters.**

The priority is one truly enjoyable duel, not an expansive feature list.

## Project status

**Milestone 1 combat prototype.** A primitive third-person courtyard duel implements
movement, orbit camera, lock-on, light attacks, guard, timed deflection, dodge,
health/posture, a corrupted swordsman, and encounter reset. These combat details
are provisional tuning for evaluation; salvage is a later milestone.

The project requires **Godot 4.7.2 stable** (`4.7.2.stable.official.ed1daf0bf`) and
defaults to GL Compatibility. On the Linux x86_64 cloud image:

```sh
cd /workspace/Boneshed
bash scripts/tooling/setup.sh
bash scripts/tooling/test.sh
bash scripts/tooling/play.sh
```

Use WASD to move, mouse to orbit, Tab to lock, left mouse to attack, right mouse to
guard/tap-deflect, Space to dodge, and R to reset. See
[the prototype guide](docs/COMBAT_PROTOTYPE.md) for setup details, architecture,
timing values, reproducible tests, evidence, and human playtesting limitations.

**[Play the browser preview](https://exnex.github.io/Boneshed/)** or see [the web preview guide](docs/WEB_PREVIEW.md). The hosted single-threaded HTML5 export preserves desktop keyboard/mouse input for desktop keyboard-and-mouse testing only. **Boneshed targets desktop; touchscreen gameplay is not supported**. Human browser feedback highlights promising lock-on/dodge but unresolved parry-spam and swing-impact readability; those are separate combat tasks. The web preview was initially published before combat PR #3; regenerate the hosted export to include the latest main changes.

## Start here

| Document | Purpose |
| --- | --- |
| [Game vision](docs/GAME_VISION.md) | Core identity, pillars, and non-goals |
| [Decision log](docs/DECISIONS.md) | Confirmed vs proposed features |
| [Roadmap](docs/ROADMAP.md) | Prototype sequence and quality gates |
| [Combat prototype](docs/COMBAT_PROTOTYPE.md) | Running the duel, controls, tests and evidence |
| [Combat review](docs/COMBAT_REVIEW.md) | Independent review, exploits, fixes and priorities |
| [Combat iteration 2](docs/COMBAT_ITERATION_2.md) | Attack readability, deflection discipline, enemy defense and provisional tuning |
| [Keyword world blueprints](docs/WORLDGEN_KEYWORDS.md) | Isolated, provisional three-keyword → WorldBlueprint prototype |
| [Shared builds and salvage](docs/SHARED_BUILDS.md) | Isolated, provisional player/enemy build contract and salvage → equip prototype |
| [AGENTS.md](AGENTS.md) | Shared instructions for AI development agents |
| [CLAUDE.md](CLAUDE.md) | Claude-specific handoff |

## First playable milestone

A ruined courtyard, responsive player combat, and one corrupted swordsman wielding a unique salvageable attack. The player learns the move by fighting against it, wins the duel, equips the augmentation, and uses it in a second encounter.

## Collaboration

ChatGPT coordinates design and review; Claude and Codex can implement small PR-scoped tasks, subject to the same repository instructions. Keep work on branches and submit pull requests. Do not assume that headless tests prove game feel.

## Scope discipline

Creature collection, autobattling, housing, and large survival systems are **not part of this game**. Marketplace, events, and leaderboards are possible supporting systems, not first-milestone requirements.
