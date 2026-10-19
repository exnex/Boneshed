# Evidence: combat presentation iteration 4

Rendered 2026-10-19 with Godot 4.7.2.stable.official.ed1daf0bf, GL Compatibility and
llvmpipe under Xvfb at 1280×720. All images are cropped.

**Before** is main `79289f0`; **after** is this branch. Both come from the same script,
[`combat_motion_capture.gd`](../../../scripts/qa/combat_motion_capture.gd), copied into a
main worktree for the before run, with the same fixed cameras and the same 60 Hz rule
ticks. The HUD and F3 volumes are hidden. Simulation is stepped in isolation, so this is
**not a playtest** and shows nothing about input feel.

| File | Shows |
| --- | --- |
| `light-stages-before-after.png` | Courtyard swordsman light attack, side view. Columns: first frame of *early*, *committed*, *release*, *active*, *recovery*. Top row before, bottom row after |
| `heavy-stages-before-after.png` | Same for the heavy |
| `special-stages-before-after.png` | Marrow Lunge (salvage courtyard, left-hand sword) |
| `react-{hit,deflect,guard,break}-before-after.png` | Reaction at 0, 4, 9 and 18 ticks after contact (side view), plus tick 2 over the defender's shoulder |
| `side-by-side-light-heavy.mp4` | 30 fps, before (left) and after (right): light, then heavy |
| `shoulder-view-light.mp4` | 30 fps light attack from over the defender's shoulder, before (left) and after (right) |
| `after-sheet-side-{light,heavy}.png` | Every second tick of the full attack, after |

## What to look for, and what the renders do not show

- **Anticipation.** The *committed* column holds a coiled, crouched pose with a brief tip
  glint. Before, the pose was still travelling. The light's *early* stage is only
  0.10 s long for the player (0.38 s for the courtyard swordsman), so its gather is
  short by rule.
- **Contact.** In the *active* column the lead foot has landed and the bright trail covers
  the arc. The trail starts at the rule's ACTIVE tick and is faint during *release*.
  The blade tip is in the 2.35 m hit volume on every active tick (asserted, not just
  pictured).
- **Recovery.** The follow-through continues past the volume, then settles. Before, the
  blade swung back across the body from the finish pose.
- **Hits.** The chest snaps away and the knees give on the contact frame, followed by a
  damped settle and a short streak on the struck body. Deflection shows the defender's
  brace, the flash and the attacker's rebound.
- **Not shown.** Real input and AI movement while attacking, high-refresh judder and
  human recognition time. The streak is mostly hidden behind the player when the player
  is the one struck. llvmpipe timing is not GPU performance.

Re-create the after set (with contact sheets) with
`bash scripts/tooling/test_combat_motion.sh artifacts/combat-motion-new`.
