# Expedition preview validation — 2026-10-21

Base: `main` at `e55a1f2`. Linux x86_64 cloud container (4 CPUs), Godot
`4.7.2.stable.official.ed1daf0bf` installed by `scripts/tooling/setup.sh` (official
archive, pinned SHA-512), GL Compatibility, Xvfb 1280×720, Mesa **llvmpipe** software
rendering, 60 Hz fixed simulation. No desktop GPU, physical input, audio or human
gameplay was tested.

Reproduce:

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/test_expedition_preview.sh artifacts/expedition-preview
```

## Results

| Check | Result |
| --- | --- |
| Import, boot of `expedition_preview.tscn` | Passed, no engine/script errors |
| Fixture suite (`expedition_preview_tests.gd`) | **1078 headless / 1087 rendered** assertions passed, 0 failed |
| Determinism | 144 plans (6 grammatical addresses × 24 seeds) generated twice, canonical JSON identical; 3 golden fingerprints (`7f003420`, `0a90a3d5`, `310b0809`) |
| Seed variation | Every address: 24/24 distinct region graphs (slots, templates, levels, bridges), 24/24 distinct dungeons, 24/24 fingerprints |
| Keyword identity | Identity (tags, biome, axes) identical across all seeds of an address; six addresses keep six distinct identities; arrival always uses the primary biome; for every tag with contrast in the set (cold, fire, water, wealth, bone), the tagged landmark is more frequent where the keywords carry the tag |
| Old addresses | `tempest frozen towering`, `smoldering frozen ossuary`, `veiled sunken dream` (seeds 1, 1001) generate valid plans with the exact blueprint fingerprint/address of the existing generator; duplicate/unknown words produce no plan |
| Topology | All 144 plans validate: regions connected, bridges on aligned sockets, ramps ≤ 2 levels, all floor reachable from spawn, descent/extraction/sites/finds reachable, 5×5 site clearance; dungeon roles once each, no overlapping or door-less touching pieces, every corridor end opens onto 3 room cells, all floor reachable, reward unreachable without the guardian room, 22 m guardian floor clear, 2 gates; no dungeon fallback needed |
| Validator negative controls | Removing a bridge, a landmark on spawn, an off-floor extraction, overlapping rooms, a blocked door, a bypassable guardian, an obstructed guardian floor and a missing gate are each rejected with their specific code |
| Built-geometry physics (3 fixtures) | Floor ray under every walkable cell at the planned height; capsule clear at every cell centre and every shared edge (doors included); every rim/boundary edge stops a horizontal ray (parapet/wall); every planned solid has collision; each guardian gate blocks only while closed |
| Isolation | Default main scene still `first_expedition.tscn`; preview is a separate scene |
| Input-driven loop, Drowned Hollow Cathedral 1001 | **15/15** loop checks headless and rendered (rendered also passes its 9 capture checks), **identical traces** (8485 ticks): selection UI → sentinel duel → F/E → surface find → descent → guardian duel using Q → gates open → reliquary → side cache → ascent → extraction summary |
| Same loop, Smoldering Pallid Necropolis 7 and Frozen Gilded Citadel 1002 | 15/15 each, headless (8195 / 8179 ticks) |
| Source mutations (isolated copies) | Seed removed from the blueprint → region diversity fails; one-cell separation weakened → plan validity fails; environment collision disabled → floor/physics checks fail |
| Regression runners | See the PR description for the exact list run on this branch |

The bot reads the plan to route (like a player reading a map) and reads visible
combat timing to choose key events; it writes no position, combat, AI, reward or
inventory state. Both duels were won at full health by deflection, which says the
bot's timing is reliable, **not** that the duels are fair or fun.

## Performance (bounded test, not a GPU prediction)

| Measure | Value |
| --- | --- |
| Plan generation (blueprint + regions + dungeon + validation) | 27 ms mean over 144 plans |
| Build (`preview_builder.gd`) | 14–16 ms per fixture |
| Built scene (Drowned 1001) | 809 nodes, 489 mesh instances, 274 collision shapes, 17 lights (smoldering 7: 696/434/217/15) |
| Static memory (whole process) | headless ~43 MB surface / ~48 MB after the dungeon; rendered ~51 / ~56 MB |
| Headless simulation, standing | 0.56 ms/frame surface, 0.44 ms/frame dungeon (wall clock, physics + scripts) |
| Rendered, llvmpipe, standing at arrival | 70 ms mean / 83 ms p95 per frame; 872 draw calls, 1153 objects, 91k primitives |
| Rendered, llvmpipe, dungeon entry | 62 ms mean / 72 ms p95; 528 draw calls (surface hidden), 1008 objects, 85k primitives |
| Physics step (monitor) | ~1.8–2.0 ms |

Hiding the inactive area removes its draw calls. llvmpipe numbers measure the
container's CPU rasteriser and do not predict desktop GPU frame time. Draw calls are
the clear next cost: every placeholder box is its own `MeshInstance3D`; merging static
geometry per region (one mesh per material) or `MultiMesh` would be the first step
before larger worlds. Not done here (no measured need on target hardware yet).

## Captures

Playthrough (rendered, same run as the trace): [arrival](rendered/01_arrival.png),
[sentinel duel](rendered/02_sentinel_duel.png), [salvaged/equipped](rendered/03_salvage_equipped.png),
[descent](rendered/04_descent.png), [dungeon entry](rendered/05_dungeon_entry.png),
[guardian duel](rendered/06_guardian_duel.png), [guardian released](rendered/07_guardian_released.png),
[reliquary](rendered/08_reliquary.png), [extraction summary](rendered/09_extracted.png).

Generated structure: surface maps and oblique views for
[Drowned 1001](rendered/oblique_world_drowned_1001.png) ([map](rendered/map_world_drowned_1001.png),
[dungeon](rendered/map_dungeon_drowned_1001.png)),
[Smoldering 7](rendered/oblique_world_smoldering_7.png) ([map](rendered/map_world_smoldering_7.png),
[dungeon](rendered/map_dungeon_smoldering_7.png)) and
[Moonlit 3](rendered/oblique_world_moonlit_3.png) ([map](rendered/map_world_moonlit_3.png),
[dungeon](rendered/map_dungeon_moonlit_3.png)).

Inspection notes: biomes give each region a distinct palette (sanctum tan,
ashfield brown, fen/briar green); the descent (violet) and extraction (pale gold)
beams are visible across regions; dungeons read as a procession of rooms with one
large guardian chamber. Standing beside the descent, its beam can fill part of the
view (see the descent capture). These are observations of placeholder renders, not
claims about how exploration feels.
