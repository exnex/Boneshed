# Boneshed

**A dark fantasy precision-combat action RPG about releasing corrupted souls and inheriting their power.**

Boneshed is a new game concept, separate from an earlier project with the same name. Players use three poetic keywords to enter unpredictable, haunting worlds; master Sekiro-inspired duels; salvage enemy gear and body augmentations; and evolve their builds. In the asynchronous **Tower of Memories**, other players can actively fight AI-operated snapshots of saved builds.

## The central loop

**Generate a world → face a corrupted soul → learn and defeat its build → salvage its signature ability → evolve your own build → face harder encounters.**

The priority is one truly enjoyable duel, not an expansive feature list.

## Project status

**First Expedition vertical slice.** Choose an environment adjective, a quality adjective and a place or concept noun from
distinct curated lists, enter a fresh seeded
world, explore a bounded ruined causeway, and release the corrupted swordsman.
Salvage/equip Marrow Arm and use its inherited power in a rematch. Use the address
and seed to reproduce a world. Geometry, keyword algorithms and balance remain
provisional. See [the expedition guide](docs/FIRST_EXPEDITION.md) for controls,
architecture, tests and limitations. Human acceptance of this new slice is pending.

The project requires **Godot 4.7.2 stable** (`4.7.2.stable.official.ed1daf0bf`) and
defaults to GL Compatibility. On the Linux x86_64 cloud image:

```sh
cd /workspace/Boneshed
bash scripts/tooling/setup.sh
bash scripts/tooling/test.sh
bash scripts/tooling/play.sh
```

Use WASD to move, mouse to orbit, wheel to zoom, Tab to lock, left mouse to attack, right mouse to
guard/tap-deflect, Space to dodge, C for heavy, R to retry, and Esc for the expedition menu. After victory: F to
salvage, E to equip the left-arm Marrow modification, N for the next duel, Q for the legacy Marrow Lunge. See
[the prototype guide](docs/COMBAT_PROTOTYPE.md) for setup details, architecture,
timing values, reproducible tests, evidence, and human playtesting limitations.

**[Older hosted browser preview](https://exnex.github.io/Boneshed/)** — this task does not publish it; use the local Godot entry point above for the new loop. See [the web preview guide](docs/WEB_PREVIEW.md). The hosted single-threaded HTML5 export preserves desktop keyboard/mouse input for desktop keyboard-and-mouse testing only. **Boneshed targets desktop; touchscreen gameplay is not supported**. Human browser feedback highlights promising lock-on/dodge but unresolved parry-spam and swing-impact readability; those are separate combat tasks. The web preview was initially published before combat PR #3; regenerate the hosted export to include the latest main changes.

## Start here

| Document | Purpose |
| --- | --- |
| [Game vision](docs/GAME_VISION.md) | Core identity, pillars, and non-goals |
| [Decision log](docs/DECISIONS.md) | Confirmed vs proposed features |
| [Roadmap](docs/ROADMAP.md) | Prototype sequence and quality gates |
| [Combat prototype](docs/COMBAT_PROTOTYPE.md) | Running the duel, controls, tests and evidence |
| [Combat review](docs/COMBAT_REVIEW.md) | Independent review, exploits, fixes and priorities |
| [Combat iteration 2](docs/COMBAT_ITERATION_2.md) | Attack readability, deflection discipline, enemy defense and provisional tuning |
| [Combat presentation 3](docs/COMBAT_PRESENTATION_3.md) | Articulated placeholder poses, restrained reactions, camera/HUD cleanup and human playtest |
| [Camera zoom](docs/CAMERA_ZOOM.md) | Smooth wheel zoom, tuning, collision/persistence contract, tests and human playtest |
| [Keyword grammar](docs/KEYWORD_GRAMMAR.md) | Adjective/adjective/noun vocabulary, desktop selection and old-address replay |
| [Keyword world blueprints](docs/WORLDGEN_KEYWORDS.md) | Provisional three-keyword → WorldBlueprint contract consumed by First Expedition |
| [Combat build integration](docs/COMBAT_BUILD_INTEGRATION.md) | Live courtyard adapter, exact parity and validation |
| [Enemy survival AI](docs/ENEMY_SURVIVAL_AI.md) | Provisional reaction-delayed defense, counters, spacing and retreat for the corrupted swordsman; fairness bounds and evidence |
| [First playable loop](docs/FIRST_PLAYABLE.md) | Human controls, inherited attack, salvage/equip progression and evidence |
| [First Expedition](docs/FIRST_EXPEDITION.md) | Desktop keyword selection, replayable generated world, exploration/duel integration and validation |
| [Expedition preview](docs/EXPEDITION_PREVIEW.md) | Isolated prototype (`bash scripts/tooling/play_expedition_preview.sh`): seeded multi-region surface, validated room-graph dungeon, guardian, finds and extraction; not the default scene |
| [Directional expedition](docs/DIRECTIONAL_EXPEDITION.md) | Experimental integration (`bash scripts/tooling/play_directional_expedition.sh`): the expedition preview's world and dungeon played with the directional melee lab's combat, stamina, armor weight and poison/slow; not the default scene |
| [Visual showcase](docs/VISUAL_SHOWCASE.md) | Experimental, desktop-only presentation slice (`bash scripts/tooling/play_visual_showcase.sh [--forward]`): rigged procedural characters, fitted weapons/armor/Marrow Arm and a modular crypt over the melee lab's unchanged directional combat; not the default scene |
| [Adaptive combat lab](docs/ADAPTIVE_COMBAT_LAB.md) | Experimental, desktop-only, isolated scene (`bash scripts/tooling/play_adaptive_lab.sh`): seeded structural objects (shovel-, umbrella-, pole-like, organic, awkward) whose grips, light/heavy/guard actions, timing and contact are derived from geometry and the wielder's body (incl. Marrow Arm), never from names; shared player/enemy rules; not the default scene |
| [Shared builds and salvage](docs/SHARED_BUILDS.md) | Shared player/enemy build contract and its historical foundation |
| [Equipment foundation](docs/EQUIPMENT_FOUNDATION.md) | Weapons vs body modifications, grips and limbs, left-arm Marrow Arm, data format and migration |
| [Anatomy and transformation](docs/ANATOMY.md) | Isolated, provisional body-graph prototype: extra limbs, replacements, equipment mounts, capability requirements, transformations and a proposed combat contract |
| [Directional melee lab](docs/DIRECTIONAL_MELEE_LAB.md) | Isolated, experimental playable scene for mouse-directed attacks/guards, weapon inertia and swept weapon contact (`bash scripts/tooling/play_melee_lab.sh`); not production combat |
| [Animation pipeline](docs/ANIMATION_PIPELINE.md) | Isolated research prototype: recommended Blender → glTF → AnimationTree pipeline, rule-timed clips, collision contract, transformations, rendered evidence |
| [Engineering standards](docs/engineering/README.md) | GDScript and Godot architecture guides, agent checklist, code audit and debt backlog |
| [AGENTS.md](AGENTS.md) | Shared instructions for AI development agents |
| [CLAUDE.md](CLAUDE.md) | Claude-specific handoff |

## First playable milestone

A ruined courtyard, responsive player combat, and one corrupted swordsman wielding a unique salvageable attack. The player learns the move by fighting against it, wins the duel, equips the augmentation, and uses it in a second encounter.

## Collaboration

ChatGPT coordinates design and review; Claude and Codex can implement small PR-scoped tasks, subject to the same repository instructions. Keep work on branches and submit pull requests. Do not assume that headless tests prove game feel.

## Scope discipline

Creature collection, autobattling, housing, and large survival systems are **not part of this game**. Marketplace, events, and leaderboards are possible supporting systems, not first-milestone requirements.

**Adaptive Combat Lab browser preview (experimental):** https://exnex.github.io/Boneshed/adaptive-combat/ — separate from the existing game and directional expedition. Publication requires a successful `Publish Boneshed desktop web preview` workflow run; the URL is not confirmed live until deployed.
