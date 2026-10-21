# Directional expedition validation — 2026-10-21

Base: `main` at `026ee27`. Linux x86_64 cloud container (4 CPUs), Godot
`4.7.2.stable.official.ed1daf0bf` installed by `scripts/tooling/setup.sh` (official
archive, pinned SHA-512), GL Compatibility, Xvfb 1280×720, Mesa **llvmpipe** software
rendering, 60 Hz fixed simulation. Browser smoke: Playwright + Chromium 1194 (SwiftShader).
No desktop GPU, physical mouse, audio or human gameplay was tested.

Reproduce:

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/test_directional_expedition.sh artifacts/directional-expedition   # ≈ 18 min here
bash scripts/tooling/setup_web.sh
bash scripts/tooling/export_web_directional.sh artifacts/web-directional
python3 scripts/tooling/smoke_web_directional.py artifacts/web-directional artifacts/web-directional-shots
```

## Integration runner (`runner.log`)

| Step | Result |
| --- | --- |
| Parse check (10 integration scripts + 2 QA scripts), import, scene boot | Passed, no engine/script errors |
| Fixture suite `directional_expedition_tests.gd` | **94 / 94** passed ([`tests-results.json`](tests-results.json)); second process byte-identical |
| Playthrough Drowned Hollow Cathedral 1001, headless | 27 / 27, 9354 ticks |
| Same, rendered (llvmpipe) | 27 / 27 + 10 capture checks; **trace identical** to headless |
| Same, replayed in a second headless process | trace.json and contacts.json **byte-identical** |
| Smoldering Pallid Necropolis 7 · Frozen Gilded Citadel 1002 · Drowned Hollow Cathedral 424242 | 27 / 27 each (8960 / 8872 / 10003 ticks) |
| Mutation: contact resolution removed | fails `cut_right_to_left_vs_guard_left_is_block`, `lethal_contact_releases_soul` (exit 1) |
| Mutation: second stamina charge in `press_attack` | fails `lmb_press_charges_attack_once` |
| Mutation: AI reaction delay 0 | fails `soul_sees_windup_only_after_reaction_delay` |
| Mutation: status routed on block | fails `guarded_poison_attack_applies_no_status` |

Mutation logs: `negative-*.log` (failed checks only).

### Duels (input-driven bot, visible cues only)

| Address / seed | Sentinel (Venom Knife + Marrow Arm + cloth) | Guardian (Greatsword + plate) | Contacts |
| --- | --- | --- | --- |
| Drowned Hollow Cathedral 1001 | won, 386 ticks, 0 retries, 100 HP left | won, 598 ticks, 0 retries, 100 HP | 16 |
| Smoldering Pallid Necropolis 7 | won, 313 ticks | won, 543 ticks, 100 HP | 16 |
| Frozen Gilded Citadel 1002 | won, 389 ticks | won, 505 ticks, 100 HP | 15 |
| Drowned Hollow Cathedral 424242 | won, 391 ticks | won, 794 ticks, **36.6 HP** (hit by the greatsword) | 19 |

Contact log for 1001: [`playthrough-contacts-drowned-1001.json`](playthrough-contacts-drowned-1001.json) —
souls' attacks deflected by the bot, punishing hits (18.7 on cloth, 13.8 through plate's
30 % mitigation; doubled while guard-broken), the Marrow Lunge blocked by the guardian
(`signature: true`). Dodge 4.64 m for 20.32 stamina and roll 4.98 m for 33.02 stamina in
the dungeon's first room, each charged once and ending on the floor.

The bot deflects almost perfectly (it re-presses the guard from the blade's visible
angle and speed). That proves the loop and rules are reachable by input, **not** that
the duels are fair or fun for a human.

## Captures and clips (rendered, llvmpipe)

| | |
| --- | --- |
| [`rendered/01_arrival.png`](rendered/01_arrival.png) | Arrival with F1 help, HUD build line (costs, speed, mitigation) |
| [`rendered/02_vigil_duel.png`](rendered/02_vigil_duel.png) | Sentinel engaged: both health / posture / stamina bars with cost ticks, status resistances |
| [`rendered/03_salvage_equipped.png`](rendered/03_salvage_equipped.png) | Marrow Arm equipped: Q lunge cost and reach |
| [`rendered/04_descent.png`](rendered/04_descent.png) · [`05_dungeon_entry.png`](rendered/05_dungeon_entry.png) · [`05b_dungeon_evasion.png`](rendered/05b_dungeon_evasion.png) | Descent, dungeon, after dodge + roll |
| [`rendered/06_guardian_duel.png`](rendered/06_guardian_duel.png) · [`07_guardian_released.png`](rendered/07_guardian_released.png) | Iron guardian (60 % resistances), released |
| [`rendered/08_reliquary.png`](rendered/08_reliquary.png) · [`09_extracted.png`](rendered/09_extracted.png) | Reliquary, extraction summary (4 finds, equipped arm, souls 2/2) |
| [`clip_exterior.mp4`](clip_exterior.mp4) · [`sheet_clip_exterior.jpg`](sheet_clip_exterior.jpg) | Sentinel duel, 6 s real time |
| [`clip_guardian.mp4`](clip_guardian.mp4) · [`sheet_clip_guardian.jpg`](sheet_clip_guardian.jpg) | Guardian duel: lunge chamber and block, greatsword deflections, hits |
| [`web_directional_selection.png`](web_directional_selection.png) · [`web_directional_session.png`](web_directional_session.png) | Real Chromium: selection screen, session after W / LMB / RMB / Space |

## Performance (bounded, not a GPU prediction)

| Measure | Value |
| --- | --- |
| Headless, standing (1001) | 0.79 ms median frame surface, 1.43 ms dungeon |
| Rendered llvmpipe, standing (1001) | 90 ms median surface (831 draw calls), 93 ms dungeon (509) |
| Scene nodes | 948 surface (preview + 2 lab souls, HUD) |

Draw calls are the preview's placeholder geometry; the combat layer adds a few meshes
per fighter.

## Browser

`export_web_directional.sh` exported a 167-resource pack (audited by
`package_web.py`, no QA/tooling/docs) from a disposable copy with the start scene and
data filter patched; `smoke_web_directional.py` passed in Chromium: boot, a real click
on **Begin expedition**, the session-ready console marker, then W, LMB hold + move +
release, RMB and Space with no page or script errors (stamina visibly charged). A
dry run of the modified `publish_web_dual.sh` (push replaced by a tree listing) staged
exactly root + `melee-lab/` + `directional-expedition/` export files. **Nothing was
published**; the Pages path appears only after merge and a successful workflow run.

## Existing suites on this branch (head of this PR, same container)

| Command | Result |
| --- | --- |
| `bash scripts/tooling/test_melee_lab.sh` | melee lab 90/90, resources 73/73, both replays identical, all four negative controls caught, 23 rendered clips — **all passed**; the script's trailing branch-isolation guard then exits 1 because `.github/workflows/publish-web.yml` changed (the intentional `/directional-expedition/` Pages path). No other protected file changed (checked with the same regex) |
| `bash scripts/tooling/test_expedition_preview.sh` | passed: 1078 fixture checks, 15/15 loop headless + rendered with identical traces, three addresses, three mutations |
| `bash scripts/tooling/test_expedition.sh` | passed (First Expedition determinism, collision, traversal, selection, pause, salvage/rematch, negatives) |
| `bash scripts/tooling/test_marrow.sh` | passed (shared lunge, progression, mutations, rendered input trace) |
| `bash scripts/tooling/test_builds.sh` | passed, 205 checks |
| `BONESHED_GRAPHICAL_TIMEOUT=900 bash scripts/tooling/test.sh` | passed (combat 118, combat builds 532, adapter mutations, negatives, encounters, timing, graphical 111) |

Not run: anatomy, animation lab, camera zoom, combat motion, enemy AI, equipment,
presentation, worldgen, keyword grammar and production Web suites (no files they cover
changed).
