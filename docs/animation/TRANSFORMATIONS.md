# Animation plan for extreme transformations

Part of the [animation pipeline proposal](../ANIMATION_PIPELINE.md). Builds on the
proposed anatomy architecture C in [ANATOMY.md](../ANATOMY.md): core-owned anchors, a
constrained socket tree, and curated animation modules per part type. Nothing here is a
confirmed mechanic. DECISIONS.md (2026-10-17) confirms only that extreme transformations
are allowed if attacks, hitboxes, controls and animation stay readable and compatible.

## 1. Approaches compared

| Approach | Works for | Fails for | Small-team cost | Verdict |
| --- | --- | --- | --- | --- |
| **Standardized humanoid rig** | Every humanoid body, replaced arms with human proportions, weapon swaps | Extra limbs (no bones), tails, non-biped gaits | Lowest | **Base layer**: all humanoid-family bodies share it |
| **Modular skeletal attachment** (append bone chains to the family skeleton, skin the part to them) | Extra arms, tails, spines, carapace arms, horns; any part attached at a declared socket | Changes to locomotion or core posture | Low per part: a mesh, weights and one module | **Recommended** for parts. Lab-verified: 8 bones appended at runtime leave every human clip identical on shared bones |
| **Curated animation sets by body category** | A different core/locomotion (digitigrade, lopsided brute, crawler) | Combinatorial explosion if categories multiply | High per category: a full locomotion and reaction set | **Recommended, but keep categories few** (humanoid, plus one or two non-humanoid cores per release) |
| **Retargeting between compatible rigs** (`BoneMap` + `SkeletonProfileHumanoid`, `RetargetModifier3D`) | Third-party humanoid clips onto our humanoid rig; proportions within the humanoid range | Different topology; very different proportions (contact and reach drift) | Low | **Inside a family only** |
| **Procedural adjustment on authored clips** (IK, aim, look-at, springs) | Placing extra hands on targets, foot locking, head tracking, tail/cloth secondary motion, oversized-part counterbalance | Creating readable attacks from nothing | Low–medium | **Recommended as a layer**. Lab-verified: `TwoBoneIK3D` put the extra hands on torso-mounted guard targets that the copied clip missed by ~0.7 m |
| **Hybrid** (all of the above, scoped) | The confirmed direction | — | Bounded by the module count | **Recommended overall** |
| Automatic universal retargeting / generated attacks for arbitrary bodies | — | Readability, telegraphs, fairness | Unbounded | **Rejected** |

## 2. How each Boneshed body case is animated

| Body case | Skeleton | Locomotion | Attacks and defence | Procedural layer |
| --- | --- | --- | --- | --- |
| Humanoid, any weapon | Humanoid family | Family set | Family move set, per weapon class | Foot lock, head look-at |
| Replaced arm (Marrow Arm) | Humanoid; the part's mesh skinned to `upperarm_r…hand_r` or a short appended chain | Family set | **Curated module** (`anim.arm_marrow`) for its signature move; sword moves switch to the left-hand mirror set | Off-hand IK where the clip assumes a grip that no longer exists |
| Missing limb | Humanoid; the limb's bones stay and are driven to a tucked pose | Family set | Clips that need the limb are gated by anatomy capabilities (`check_requirement`) | — |
| Extra arm pair | Humanoid + appended `_low` chains | Family set | Upper pair: family set. Lower pair: **curated layer modules** (guard, parry, light strike), blended with a bone filter | **IK to torso-mounted targets** (lab-verified) and parry targets |
| Asymmetric proportions (oversized arm, long reach) | Humanoid family; per-bone scale on the part's chain, or an appended part | Family set, possibly with a heavier variant | Curated module for the oversized part; its telegraph must be at least as long as a standard swing | Counterbalance spine offset (custom `SkeletonModifier3D`) |
| Oversized weapon | Humanoid | Family "heavy" variant | Weapon-class set (greatsword family) | Two-hand IK to the weapon's secondary grip |
| Non-humanoid silhouette (carapace brute, digitigrade) | **New body family** with its own skeleton standard | Curated set for that family | Curated set for that family | Foot IK on the new gait |

**Rule of thumb:** a new *part* costs one module and one hit-volume review. A new *body
family* costs a full locomotion, reaction and death set. Plan content in those units.

## 3. What the lab proved and did not prove

**Verified (four-armed run on Godot 4.7.2):**
- Appending bones at runtime (`Skeleton3D.add_bone`) does not disturb existing clips. The
  sword tip path on shared bones matched the plain humanoid to < 0.1 mm.
- A procedurally built, skinned limb mesh binds to the appended bones. It needs
  `MeshInstance3D.skeleton = ".."`; meshes created in code leave it empty, and the limb
  then renders frozen in rest pose. That bug happened in the lab and is now tested.
- Copying a human arm's *local* rotations onto the extra pair does **not** reproduce the pose
  when the parent (spine) plays something else. IK fixed it.
- `TwoBoneIK3D` output is visible to `BoneAttachment3D` and `skeleton_updated` listeners,
  but **not** to `Skeleton3D.get_bone_global_pose()` called outside the update
  (tripwire test). Any hurtbox or weapon reader on a modified limb must follow the bone
  through a `BoneAttachment3D`.

**Not proven:** visual quality of extra limbs (the lab's tubes are crude next to the
sculpted mesh); a choreographed four-arm *attack*; combat readability of any
non-baseline body; performance with many modules; blending modules across a live
transformation.

## 4. Transformation transitions

Following ANATOMY.md §4: apply transformations between encounters or behind an
uninterruptible transition. Animation-side steps:
1. Diff old/new resolved bodies (`AnatomyRules.diff`) to get the parts added and removed.
2. Append or remove bone chains and part meshes (appending is lab-verified; removal is untested).
3. Load or unload the parts' animation modules into the family `AnimationLibrary`, and
   rebuild the `AnimationTree` filters for the new part bones.
4. Rebuild hurt volumes from bone attachments, and re-bake the weapon/part traces for
   any attack whose origin moved.
5. Play a dedicated transformation clip, since a body change has no meaningful blend.
