# Visual showcase validation — 2026-10-21

Base: `main` at `f1e9957`. Linux x86_64 cloud container (4 CPUs, Intel Xeon @ 2.80 GHz),
Godot `4.7.2.stable.official.ed1daf0bf` installed by `scripts/tooling/setup.sh` (official
archive, pinned SHA-512), Xvfb 1280×720, 60 Hz fixed simulation. **No GPU:** GL
Compatibility rendered with Mesa **llvmpipe**; Forward+ with Mesa **lavapipe** (installed
only inside the disposable container). No desktop GPU, physical mouse, audio or human
gameplay was tested. Images show presentation only; they say nothing about game feel.

Reproduce:

```sh
bash scripts/tooling/setup.sh
bash scripts/tooling/test_visual_showcase.sh artifacts/visual-showcase       # ≈ 45 min here
bash scripts/tooling/bench_visual_showcase.sh artifacts/visual-showcase-bench # ≈ 35 min here
```

## Runner (`test_visual_showcase.sh`)

| Step | Result |
| --- | --- |
| Import, parse check of every showcase script | Passed, no engine or script errors |
| `visual_showcase_tests.gd` | **49 / 49** ([`tests-results.json`](tests-results.json)); second process byte-identical |
| Mutation: weapon drawn 5 cm off the rules hand | fails `drawn_weapon_equals_rules_segment_every_tick`, `engine_weapon_tip_on_rules_tip` ([log](negative-weapon-offset.log)) |
| Mutation: fist aimed 5 cm off the grip | fails `right_fist_on_grip_all_weapons_directions_guards`, `engine_grip_socket_on_rules_hand` ([log](negative-fist-off-grip.log)) |
| Mutation: presentation writes rules state | fails `combat_outcomes_identical_to_melee_lab` ([log](negative-presentation-touches-rules.log)) |
| Rendered capture, GL Compatibility | 42 stills + 8 clips, all capture checks passed (deflect, guard break and release contacts asserted) |
| Rendered capture, Forward+ | 5 hero shots |
| Isolation versus `origin/main` | No protected production, lab, shared-data or coordination file changed |

Key measurements from the suite: drawn weapon vs rules segment **≤ 2.5e-7 m** over 11700
solved poses; right fist on grip **< 1e-5 m**; second fist on the greatsword hilt 70 % of
ticks (≤ 0.9 mm when on it); arm stretch **1.0** (none); engine socket vs rules hand
**5e-7 m**, tip marker vs rules tip **3e-7 m**; trunk offset inside the hurt capsule
**0.274 m** (radius 0.32); crypt 108 pieces / 54808 triangles / 8 surfaces / 59 collision boxes.
Contact logs: [`outcomes_lab.txt`](outcomes_lab.txt) and [`outcomes_showcase.txt`](outcomes_showcase.txt) are identical.

## Before / after (same scripted moments, loadouts and camera)

Left: melee lab (capsule fighters, lab defaults: arcs and labels on). Right: showcase
(pilgrim in mail vs corrupted soul in cloth with the Marrow Arm; edge glow and trail,
arcs/labels off). Both: Notched Sword, GL Compatibility.

| Moment | Image |
| --- | --- |
| Idle face-off | [pair_1_faceoff.jpg](pair_1_faceoff.jpg) |
| Held right chamber | [pair_2_chamber_right.jpg](pair_2_chamber_right.jpg) |
| Redirected to the left chamber through neutral | [pair_3_rechamber_left.jpg](pair_3_rechamber_left.jpg) |
| Mid swing | [pair_4_swing.jpg](pair_4_swing.jpg) |
| Player guards left, soul guards high | [pair_5_guards.jpg](pair_5_guards.jpg) |
| Dodge roll | [pair_6_roll.jpg](pair_6_roll.jpg) |
| Overhead hit and reaction | [pair_7_hit.jpg](pair_7_hit.jpg) |
| Gameplay camera | [pair_8_player_view.jpg](pair_8_player_view.jpg) |

## Close-ups

- Characters: [pilgrim cloth](char_pilgrim_cloth_front.jpg) · [pilgrim mail](char_pilgrim_mail_front.jpg) · [pilgrim mail side](char_pilgrim_mail_side.jpg) · [pilgrim plate](char_pilgrim_plate_front.jpg) · heads [cloth hood](char_pilgrim_cloth_head.jpg) / [great helm](char_pilgrim_plate_head.jpg) · soul [Marrow Arm](char_soul_marrow_front.jpg) · [soul head](char_soul_marrow_head.jpg) · [soul plate](char_soul_plate_front.jpg) · [soul mail, no arm](char_soul_mail_no_arm_front.jpg)
- Weapons at a right chamber with the **F3 contact-segment overlay** drawn over the blade: [light](weapon_light_chamber_segment.jpg) · [medium](weapon_medium_chamber_segment.jpg) · [heavy](weapon_heavy_chamber_segment.jpg); grip close-ups [light](weapon_light_grip_closeup.jpg) · [medium](weapon_medium_grip_closeup.jpg) · [heavy, two hands](weapon_heavy_grip_closeup.jpg)
- Crypt: [entrance](crypt_wide_entrance.jpg) · [from the dais](crypt_wide_dais.jpg) · [high](crypt_high.jpg) · [dais detail](crypt_detail_dais.jpg) · [ossuary niche](crypt_detail_niche.jpg)
- Renderers (left Compatibility, right Forward+, same frame): [crypt](forward_vs_compat_crypt_wide.jpg) · [dais](forward_vs_compat_dais.jpg) · [face-off](forward_vs_compat_faceoff.jpg) · [swing](forward_vs_compat_swing.jpg) · [soul](forward_vs_compat_soul.jpg)

## Clips (30 fps of every second simulation tick, 640 px; contact sheets beside them)

| Clip | Shows |
| --- | --- |
| [chamber_switch.mp4](clip_chamber_switch.mp4) ([sheet](sheet_clip_chamber_switch.jpg)) | Right chamber held, flick to left (through neutral), then overhead, release (100 frames) |
| [guard_deflect.mp4](clip_guard_deflect.mp4) ([sheet](sheet_clip_guard_deflect.jpg)) | Player cuts into the soul's guard: timed re-press deflects (recoil, sparks), then a block (85 frames) |
| [weapon_mass_light.mp4](clip_weapon_mass_light.mp4) ([sheet](sheet_clip_weapon_mass_light.jpg)) | Knife overhead into a high guard (55 frames) |
| [weapon_mass_heavy.mp4](clip_weapon_mass_heavy.mp4) ([sheet](sheet_clip_weapon_mass_heavy.jpg)) | Greatsword overhead into a high guard (slower trunk, longer settle) (55 frames) |
| [dodge_and_roll.mp4](clip_dodge_and_roll.mp4) ([sheet](sheet_clip_dodge_and_roll.jpg)) | Dodge step right, roll left (tumble, weapon back on the rules pose) (75 frames) |
| [guard_break_and_hit.mp4](clip_guard_break_and_hit.mp4) ([sheet](sheet_clip_guard_break_and_hit.jpg)) | Greatsword breaks a knife guard (posture), follow-up cut (110 frames) |
| [death_release.mp4](clip_death_release.mp4) ([sheet](sheet_clip_death_release.jpg)) | Final cut; the soul buckles, falls, its light fades, wisps rise (100 frames) |
| [duel_player_camera.mp4](clip_duel_player_camera.mp4) ([sheet](sheet_clip_duel_player_camera.jpg)) | Six seconds of the seeded AI duel from the gameplay camera (180 frames) |

## Benchmarks

[`bench_gl_compatibility.json`](bench_gl_compatibility.json), [`bench_forward_plus.json`](bench_forward_plus.json);
tables and caveats in [VISUAL_SHOWCASE.md §7](../../VISUAL_SHOWCASE.md#7-rendering-evaluation-and-benchmarks).
Software rasterisers: frame times rank configurations only; they are not desktop GPU numbers.
