# Combat presentation, iteration 3

This is a compact presentation slice against main `f722317a03d2dc9b0e0720573f0b44ef34161e95`.
The October 18 human gameplay recording was not supplied in this environment;
the work uses the reported defects, the first-playable evidence, and new renders.

**Confirmed:** the requested focus is a readable precision duel, shared rules,
movement and steering during attacks, immediate defensive cancels, and the existing
salvage/equip loop. **Proposed:** the curated poses and camera values here are
provisional presentation tuning. **Open:** human recognition, responsiveness on
physical devices/high-refresh displays, and first-fight difficulty.

## What changes in play

- The placeholder has a separate chest, head, pelvis, upper/lower arms and legs.
  Bent elbows connect shoulders to weapon hands; knees and alternating steps
  respond to actual travel. Preparation loads the shoulders and stance, release
  rotates the torso, and recovery unwinds the finish instead of snapping to rest.
- Light cuts draw out to the side; heavy cuts lift above the head. Marrow Lunge
  coils the bone shoulder and thrusts straight ahead while the sword stays low.
  Sword active reach still matches the existing timing fixtures; the bone mesh
  reaches the authoritative lunge distance. No animation event enables damage.
- A body hit recoils the chest with the blade low. A deflection braces the defender
  and throws the attacker's weapon outward. A posture break bends the torso and
  knees and drops the weapon. Small, short steel-contact strokes replace the large
  cyan burst and whole-body flash. The gold break halo is debug-only. No hitstop,
  screen shake, new audio, dependencies or imported assets are introduced.
- F3 starts off and reveals the analytical attack volumes, phase/event text and
  break halo. Ordinary combat has no ground attack box or explanatory attack text.
- Health and posture use compact labeled bars. The equipped ability stays visible;
  F1 opens/closes the controls. Salvage, equip, next-duel and death prompts remain
  contextual, and the equipment inspection card remains available after victory.
- The camera uses a 1.2-unit shoulder offset, 1.8-unit pivot height, initial pitch
  -0.32 radians and a restrained 0.12-radian oblique lock view. Lock tracks the target
  rather than the attack-limited facing. Auto yaw is capped at 2.6 rad/s and yields
  for 0.7 seconds after mouse movement; locked pitch stays below the horizon.
  A shoulder-anchor ray with 0.25 clearance supplements the existing swept sphere
  spring arm. Mouse sensitivity, distance, FOV, movement acceleration and attack
  steering remain at their existing values. All new camera numbers are provisional.

All added mutable pose state lives on its fighter (`gait`, reaction kind/time), and
manual orbit time lives on its player. Reset clears them. `fighter_visual.gd` reads
rules, and `Fighter.resolve_attack` forwards only already-resolved feedback. It does
not change the authoritative combat-state implementation, AI, catalog or geometry.

## Collision investigation and next slice

Today `Fighter.valid_attack_target` tests the target center against a forward box
with capsule-radius allowance, then checks an environment ray. Contact is consumed
once during ACTIVE by shared rules. The blade is extended into that reach on the
first active tick; tests cover that alignment. This slice does not replace collision
or use animated triangle meshes. Keeping that contract protects the existing rules
and build fixtures, but does not establish anatomical weapon contact.

Known contradictions remain: the broad box can accept lateral or point-blank hits
that the visible blade does not touch, a late active cut can damage a newly entering
target elsewhere in the box, and the extending bone is a stylized temporary limb.
Changing these acceptance cases would change combat outcomes and needs its own PR.
Do not use these screenshots as evidence that those cases are solved.

Proposed focused follow-up, in priority order:

1. Add curated grip/base/tip markers and a weapon capsule (or a small chain of
   capsules). Store previous/current physics-tick transforms. Sweep between them
   with conservative subdivision for angular motion; one straight tip ray alone
   misses rotating-blade arcs. Use a conservative broad phase, then narrow queries.
2. Use a small body-part capsule set with stable part IDs. Query shape contacts
   against those proxies and environment occlusion. Keep locomotion's body capsule
   separate. Current ordinary humanoids supply a fixed binding; later anatomy must
   supply capability/mount IDs, including extra limbs, without relying on bone names
   or assuming exactly two arms. Do not integrate the anatomy prototype in this PR.
3. Sample swept contacts only for the interval inside ACTIVE, including the
   windup→active boundary. Reset motion history on teleports, equipment replacement
   and defensive cancels so a stale transform cannot sweep across the arena. Pass
   the candidate and incoming direction to existing `CombatState.receive`; animation
   still cannot decide damage, guard windows, posture or one-hit consumption.
4. Compare the current analytic trace with the candidate detector, documenting
   intentional acceptance differences. Exercise fast turns, low render FPS at fixed
   physics rate, close range, lateral entry, walls, dodges, mirrored grips and altered
   limb counts before changing the shipped detector. No triangle-mesh default.

## First encounter and remaining defects

No enemy health, attack timing, defense, AI policy or damage was weakened. The eight
hard-combat strategy fixtures stay in the ordinary courtyard. The playable augmented
encounter remains its separate scene. Its opening lunge is predictable and its
existing windup/recovery offer a learning opportunity, but a timing-aware bot is not
a new player: do not declare beginner difficulty solved from its win.

Priority follow-ups after a human session:

1. Close-range overlap still occurs at some orbit angles, especially the bone arm
   behind the player. Test a stronger oblique view or distance-aware framing before
   adding camera fades. Tight corners can still compress the view; there is no
   automatic alternative-shoulder search or target-occluder fade.
2. The models remain primitive; fixed segment endpoints can stretch, feet can slide
   or clip on uneven surfaces, and reaction/defensive-cancel transitions still have
   abrupt changes. A small authored animation set is the next art step, rather than
   expanding this into a universal procedural rig. There is no audio cue yet.
3. Sweep/contact work described above. Narrow current boxes only with explicit
   acceptance tests; a presentation PR should not silently change defensive fairness.
4. Have a new player try several attempts. If readable cues still leave too little
   learning time, propose a separately named introductory encounter with more idle
   space between attacks; retain the difficult fixture and shared defense rules.
5. Physical mouse/keyboard, high-refresh judder and browser pointer capture need a
   person. Physics interpolation and the 60 Hz camera tick were not silently changed.

## Exact human playtest

Use Godot **4.7.2.stable.official.ed1daf0bf**. Open `project.godot`, press **F5**, or
run `bash scripts/tooling/play.sh`. The default entry is the salvage courtyard.

1. Press **F1** to read controls, then close help. Keep **F3 off**. **WASD** moves,
   **mouse** orbits, **Tab** locks, **LMB** cuts, **C** uses a heavy, **RMB** guards
   (a fresh tap near contact deflects), **Space** dodges, **Esc** releases the mouse.
2. First observe one opening lunge without attacking. Identify the bone draw-back,
   then try a deliberate RMB tap or Space. Do three attempts. Record whether the cue
   was visible, and whether failure came from recognizing it late, timing, overlap,
   or an unexpected hit. Do not enable phase text to teach the timing.
3. Compare an ordinary light cut, the overhead heavy, and the straight bone thrust.
   Recognize successful deflection by the weapon recoil and brief contact effect;
   recognize posture break by the collapsed body and lowered blade. Try one punish.
4. Move/strafe throughout your own attacks, change direction, and cancel each with
   a fresh guard press or dodge. Check whether controls feel connected. Circle at
   close range, orbit while locked, move behind a pillar and back toward each wall.
   Record camera occlusion, recentering or apparent distance errors.
5. Win, press **F** to salvage, **E** to equip, **N** for the next duel, then **Q** to
   use Marrow Lunge. Confirm the new arm and equipped-ability label. **R** retries
   while preserving acquired equipment. Reopening the game starts a fresh session.
6. Only afterward use **F3** to inspect analytical volumes, then turn it off. Repeat
   at the monitor's normal refresh rate. Report recognition and perceived input
   response separately from difficulty and whether the duel was enjoyable.

For the no-HUD recognition criterion, capture a clip with the HUD hidden in an
observational fixture (see evidence) and ask an unfamiliar viewer to identify
incoming attacks, deflections and breaks without the accompanying explanation.
This is still an outstanding human acceptance test.

## Reproduction

Use fresh output directories. Runtime render tests require working local sockets
for Godot/Xvfb; browser tests also require installed export templates and Chromium.
The cloud uses llvmpipe, whose frame times are not desktop GPU performance evidence.

```sh
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test.sh artifacts/native-new
BONESHED_GRAPHICAL_TIMEOUT=1200 bash scripts/tooling/test_marrow.sh artifacts/marrow-new
bash scripts/tooling/test_presentation.sh artifacts/presentation-new
bash scripts/tooling/test_builds.sh artifacts/builds-new
bash scripts/tooling/test_anatomy.sh artifacts/anatomy-new
bash scripts/tooling/test_worldgen.sh artifacts/worldgen-new
bash scripts/tooling/test_web.sh artifacts/web-new
```

For a like-for-like render, run `presentation_capture.gd` with `--fixed-fps 60`
under Xvfb/GL Compatibility and `--evidence-dir=...` after `--`. Run that same
capture-only script in a main worktree and this branch. It freezes simulation and
samples curated timelines, so it complements the real-input/AI playthrough rather
than replacing it. It uses an independent fixed observation camera, hides both HUD
and debug boxes, and saves every second physics sample (30 fps), plus phase stills.

See [executed results and before/after comparisons](evidence/combat-presentation-3/README.md).
