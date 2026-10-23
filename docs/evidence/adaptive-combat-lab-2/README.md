# Adaptive Combat Lab 2 — evidence

These files were produced by `BONESHED_LAB_REPO=<ai-game-dev-lab> bash scripts/tooling/test_adaptive_lab.sh`.

| Setting | Value |
| --- | --- |
| Engine | Godot 4.7.2.stable.official.ed1daf0bf |
| Renderer | GL Compatibility on Mesa llvmpipe (software rendering, Xvfb, 1280×720) |
| Physics | Fixed 60 Hz |

The clips render frame by frame, so their speed does not reflect real-time performance. Automated evidence shows that the
pipeline works as specified. It does **not** show that combat feels good; that is the owner's playtest.

## Same inputs, different objects (requirement: visibly different combos)

Every clip runs the same input script against a passive soul, filmed from the same side camera:

1. light, light, light;
2. pause;
3. heavy;
4. light, then heavy (the finisher).

| File | What to look at |
| --- | --- |
| `compare_side_by_side.mp4` / `compare_side_by_side_sheet.jpg` | All six imported Lab objects at the same moments: windup pose, path, body motion, striking part, recovery. |
| `clip_compare_umbrella.mp4` | Canopy bash → rib-tip sweep → rib backhand. The overhead heavy is a rib slam. After a bash, the finisher is a heavy canopy bash. |
| `clip_compare_shovel.mp4` | Pendulum blade-edge chops, each leading with the other edge on the way back. Deep overhead coil, overshoot and head sag on the heavy. |
| `clip_compare_double-ended.mp4` | Alternating ends: butt, then lead sweep, then butt. The windmill heavy lands **twice** (lead end, then rear end). |
| `clip_compare_hinged.mp4` | Double thrust → butt strike. The ~1 m lunge is a gap closer. The unlocked panel swings, but in presentation only. |
| `clip_compare_organic.mp4` | Thrust → sweep. Overhead mace heavy. After a thrust, the finisher is the **hook**, which pulls the target. |
| `clip_compare_awkward.mp4` | The zero-grip, 30 kg object lies on the floor, and the fighter boxes bare-handed (jab, cross, shoulder barge). |
| `poses_<object>.jpg` | Key-pose stills (windup / contact / recovery of each chain step and the heavy, then the guard), one sheet per object. |

The event sequences produced by that one script are in `capture_manifest.json`:

| Object | Sequence |
| --- | --- |
| umbrella | bash, sweep, **heavy overhead**, bash, **heavy bash** |
| shovel | sweep, backhand, heavy (finisher) sweep, sweep, **heavy overhead** |
| double-ended | rear, sweep, rear, **heavy windmill (2 contacts)**, rear, heavy sweep |
| hinged | thrust, thrust, rear, **heavy lunge**, thrust, heavy lunge |
| organic | thrust, sweep, **heavy overhead**, thrust, **heavy hook** |
| awkward | jab, cross, jab, heavy barge, … |

Some whiffs are honest. A butt strike or a fist thrown from 2.2 m cannot reach; such attacks log `whiff` with their closest
gap.

## Camera, HUD, body modification, heavy misses

| File | What it shows |
| --- | --- |
| `clip_gameplay_default_hud.mp4` | AI vs AI, same rules on both sides, locked orbit camera, **default minimal HUD**. |
| `clip_gameplay_debug_layers.mp4` | The same duel with every developer layer toggled on: stats/solver (F2), log (F5), help (H), grip/contact overlay (F3), planned contact path (F6). |
| `clip_camera_orbit_zoom.mp4` | Free orbit (unlocked, no auto-tracking) with smooth zoom in and out. |
| `clip_graft_regeneration.mp4` | Illustrative marrow graft: the hand still grips the pole two-handed, health regenerates (green glow at the hand). |
| `clip_heavy_close_overlay.mp4` | Close-range heavy (shovel) with the overlay and planned contact path, showing what the rules test. |
| `lab1_heavy_diagnostic.jsonl` | Lab 1's own code (base ref `origin/main`): 6 of 32 heavies whiff, each with its closest gap and footwork. See ADAPTIVE_COMBAT_LAB §4. |

## Machine-readable results

| File | Content |
| --- | --- |
| `results.json` | All 55 checks and their details. It is byte-identical across two processes. |
| `metrics.json` | Wall-clock costs on this cloud CPU: bundle import ≈ 80 ms; solve ≈ 0.1–0.3 s per object and body; rules tick ≈ 0.2 ms. |
| `duel_log.json` | A 20 s seeded AI-vs-AI duel log. It is byte-identical across processes. |
| `web_smoke.png` | Browser build (Chromium, SwiftShader). The log line `BONESHED_ADAPTIVE_LAB_IMPORT accepted=6 rejected=9` confirms the bundle verified in the browser. |
