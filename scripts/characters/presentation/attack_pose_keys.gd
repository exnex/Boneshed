extends RefCounted
## Curated key poses for the articulated placeholder fighter. Presentation data only.
##
## Attack keys use clip time whose whole numbers are the animation-lab markers
## (scripts/animation_lab/phase_warp.gd): 0 start, 1 loaded, 2 release, 3 contact,
## 4 active_end, 5 recovered. CombatState decides when each marker is reached; the
## keys only decide the shape between them. A `hold` key has zero velocity: it
## marks an anticipation peak or a settle, so the body visibly stops there.
##
## Character space: -Z forward, +X right, metres and radians. Light and heavy are
## authored right-handed and mirrored for a left-hand sword; special is authored in
## its final (bone arm right, sword left) space.
## Channels: hand = sword grip point, blade = sword Euler rotation, torso = chest
## Euler rotation, body = Vector4(crouch, lean back, lead-foot step, foot lift),
## grip = off hand on the hilt (0..1), off = free off-hand point.
##
## Contact keys are pinned to the rule geometry: the blade tip reaches the 2.35 m
## sword hit volume on the first ACTIVE tick and stays in it, above 1 m, until
## active_end. attack_timing_test.gd and combat_motion_tests.gd enforce this.

const OFF_REST := Vector3(-0.44, 1.0, -0.18)
const REST := {"hand": Vector3(0.48, 1.1, 0.0), "blade": Vector3(-0.12, -0.18, 0.0), "torso": Vector3.ZERO,
	"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST}

const LIGHT := [
	{"t": 0.0, "hold": true, "hand": Vector3(0.48, 1.1, 0.0), "blade": Vector3(-0.12, -0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
	# Gather: the shoulders turn first and the blade follows out to the side.
	{"t": 0.55, "hand": Vector3(0.66, 1.38, 0.14), "blade": Vector3(0.14, -0.8, -0.2), "torso": Vector3(0.06, -0.45, 0.05),
		"body": Vector4(0.05, 0.05, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.38, 1.12, -0.3)},
	{"t": 1.0, "hold": true, "hand": Vector3(0.72, 1.6, 0.24), "blade": Vector3(0.26, -1.18, -0.28), "torso": Vector3(0.1, -0.7, 0.07),
		"body": Vector4(0.08, 0.08, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.32, 1.18, -0.36)},
	# Committed: a held, still-coiling loaded pose (lab standard: visible hold at `loaded`).
	{"t": 2.0, "hold": true, "hand": Vector3(0.76, 1.66, 0.3), "blade": Vector3(0.32, -1.32, -0.3), "torso": Vector3(0.12, -0.8, 0.08),
		"body": Vector4(0.1, 0.1, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.3, 1.2, -0.4)},
	# Release: hips and lead foot go first, the blade accelerates on an arc.
	{"t": 2.55, "hand": Vector3(0.58, 1.52, -0.3), "blade": Vector3(0.18, -0.78, -0.22), "torso": Vector3(0.02, -0.3, 0.04),
		"body": Vector4(0.08, -0.02, 0.18, 0.07), "grip": 0.0, "off": Vector3(-0.36, 1.1, -0.2)},
	{"t": 3.0, "hand": Vector3(0.15, 1.35, -0.6), "blade": Vector3(0.0, -0.12, 0.0), "torso": Vector3(-0.12, 0.18, 0.0),
		"body": Vector4(0.1, -0.1, 0.3, 0.0), "grip": 0.0, "off": Vector3(-0.42, 1.05, 0.0)},
	{"t": 4.0, "hand": Vector3(-0.16, 1.35, -0.6), "blade": Vector3(0.0, 0.65, 0.0), "torso": Vector3(-0.12, 0.55, -0.05),
		"body": Vector4(0.1, -0.1, 0.3, 0.0), "grip": 0.0, "off": Vector3(-0.44, 1.0, 0.12)},
	# Follow-through carries past the hit volume, then settles back over the lead foot.
	{"t": 4.35, "hand": Vector3(-0.34, 1.2, -0.42), "blade": Vector3(-0.22, 1.0, -0.12), "torso": Vector3(-0.08, 0.68, -0.06),
		"body": Vector4(0.09, -0.06, 0.3, 0.0), "grip": 0.0, "off": Vector3(-0.46, 1.0, 0.1)},
	{"t": 4.8, "hand": Vector3(0.4, 1.06, -0.06), "blade": Vector3(-0.16, -0.1, 0.0), "torso": Vector3(0.0, 0.06, 0.0),
		"body": Vector4(0.02, 0.0, 0.08, 0.04), "grip": 0.0, "off": OFF_REST},
	{"t": 5.0, "hold": true, "hand": Vector3(0.48, 1.1, 0.0), "blade": Vector3(-0.12, -0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
]

const HEAVY := [
	{"t": 0.0, "hold": true, "hand": Vector3(0.48, 1.1, 0.0), "blade": Vector3(-0.12, -0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
	# Two-handed gather: both hands meet on the hilt before the lift.
	{"t": 0.5, "hand": Vector3(0.52, 1.55, 0.16), "blade": Vector3(0.7, -0.5, -0.12), "torso": Vector3(0.08, -0.3, 0.04),
		"body": Vector4(0.06, 0.06, 0.0, 0.0), "grip": 1.0, "off": OFF_REST},
	{"t": 1.0, "hold": true, "hand": Vector3(0.4, 2.12, 0.12), "blade": Vector3(1.28, -0.3, -0.18), "torso": Vector3(0.18, -0.45, 0.07),
		"body": Vector4(0.12, 0.12, 0.0, 0.0), "grip": 1.0, "off": OFF_REST},
	{"t": 2.0, "hold": true, "hand": Vector3(0.38, 2.22, 0.18), "blade": Vector3(1.4, -0.28, -0.2), "torso": Vector3(0.22, -0.5, 0.08),
		"body": Vector4(0.14, 0.14, 0.0, 0.0), "grip": 1.0, "off": OFF_REST},
	{"t": 2.5, "hand": Vector3(0.32, 1.98, -0.32), "blade": Vector3(0.8, -0.22, -0.14), "torso": Vector3(-0.02, -0.18, 0.03),
		"body": Vector4(0.12, 0.0, 0.2, 0.08), "grip": 1.0, "off": OFF_REST},
	{"t": 3.0, "hand": Vector3(0.15, 1.38, -0.62), "blade": Vector3(0.1, -0.1, -0.05), "torso": Vector3(-0.2, 0.08, 0.0),
		"body": Vector4(0.16, -0.12, 0.34, 0.0), "grip": 1.0, "off": OFF_REST},
	{"t": 4.0, "hand": Vector3(-0.16, 1.16, -0.58), "blade": Vector3(-0.03, 0.35, -0.2), "torso": Vector3(-0.26, 0.3, -0.04),
		"body": Vector4(0.18, -0.14, 0.34, 0.0), "grip": 1.0, "off": OFF_REST},
	# The weight of the cut drives the blade low after the hit volume closes.
	{"t": 4.35, "hand": Vector3(-0.24, 0.86, -0.46), "blade": Vector3(-0.62, 0.45, -0.25), "torso": Vector3(-0.32, 0.36, -0.05),
		"body": Vector4(0.2, -0.14, 0.34, 0.0), "grip": 1.0, "off": OFF_REST},
	{"t": 4.8, "hand": Vector3(0.36, 1.0, -0.12), "blade": Vector3(-0.22, -0.1, 0.0), "torso": Vector3(-0.04, 0.06, 0.0),
		"body": Vector4(0.04, 0.0, 0.08, 0.04), "grip": 0.3, "off": OFF_REST},
	{"t": 5.0, "hold": true, "hand": Vector3(0.48, 1.1, 0.0), "blade": Vector3(-0.12, -0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
]

# Marrow Lunge body only; the bone length and sweep stay in fighter_visual.gd.
const SPECIAL := [
	{"t": 0.0, "hold": true, "hand": Vector3(-0.48, 1.1, 0.0), "blade": Vector3(-0.12, 0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
	{"t": 0.6, "hand": Vector3(-0.48, 0.97, 0.02), "blade": Vector3(-0.36, -0.36, 0.0), "torso": Vector3(0.05, -0.45, 0.05),
		"body": Vector4(0.08, 0.08, 0.0, 0.0), "grip": 0.0, "off": OFF_REST},
	{"t": 1.0, "hold": true, "hand": Vector3(-0.48, 0.95, 0.0), "blade": Vector3(-0.4, -0.4, 0.0), "torso": Vector3(0.08, -0.65, 0.08),
		"body": Vector4(0.12, 0.14, 0.0, 0.0), "grip": 0.0, "off": OFF_REST},
	{"t": 2.0, "hold": true, "hand": Vector3(-0.48, 0.95, 0.0), "blade": Vector3(-0.4, -0.4, 0.0), "torso": Vector3(0.1, -0.72, 0.09),
		"body": Vector4(0.14, 0.16, 0.0, 0.0), "grip": 0.0, "off": OFF_REST},
	{"t": 2.5, "hand": Vector3(-0.48, 0.95, 0.0), "blade": Vector3(-0.4, -0.4, 0.0), "torso": Vector3(-0.06, -0.15, 0.03),
		"body": Vector4(0.12, -0.02, 0.22, 0.08), "grip": 0.0, "off": OFF_REST},
	{"t": 3.0, "hold": true, "hand": Vector3(-0.48, 0.95, 0.0), "blade": Vector3(-0.4, -0.4, 0.0), "torso": Vector3(-0.2, 0.3, 0.0),
		"body": Vector4(0.12, -0.16, 0.42, 0.0), "grip": 0.0, "off": OFF_REST},
	{"t": 4.0, "hold": true, "hand": Vector3(-0.48, 0.95, 0.0), "blade": Vector3(-0.4, -0.4, 0.0), "torso": Vector3(-0.2, 0.3, 0.0),
		"body": Vector4(0.12, -0.16, 0.42, 0.0), "grip": 0.0, "off": OFF_REST},
	{"t": 4.5, "hand": Vector3(-0.48, 1.0, 0.0), "blade": Vector3(-0.3, -0.2, 0.0), "torso": Vector3(-0.12, 0.18, 0.0),
		"body": Vector4(0.08, -0.08, 0.3, 0.03), "grip": 0.0, "off": OFF_REST},
	{"t": 5.0, "hold": true, "hand": Vector3(-0.48, 1.1, 0.0), "blade": Vector3(-0.12, 0.18, 0.0), "torso": Vector3.ZERO,
		"body": Vector4.ZERO, "grip": 0.0, "off": OFF_REST},
]

# Single-pose states. Stagger and break poses ease back to REST at the end of
# their rule lockout, so the visual never snaps when control returns.
const GUARD := {"hand": Vector3(0.15, 1.6, -0.35), "blade": Vector3(0.55, -0.4, -0.8), "torso": Vector3(-0.1, -0.18, 0.0),
	"body": Vector4(0.06, 0.02, 0.08, 0.0), "grip": 1.0, "off": OFF_REST}
const STAGGER_HIT := {"hand": Vector3(0.5, 1.0, 0.1), "blade": Vector3(-0.3, 0.25, 0.15), "torso": Vector3(0.18, 0.1, -0.1),
	"body": Vector4(0.1, 0.08, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.5, 1.05, 0.0)}
# A deflected attacker's weapon is thrown up and back; the lead foot gives ground.
const STAGGER_DEFLECTED := {"hand": Vector3(0.68, 1.66, 0.2), "blade": Vector3(0.75, -1.05, -0.45), "torso": Vector3(0.26, -0.45, -0.12),
	"body": Vector4(0.06, 0.14, -0.08, 0.0), "grip": 0.0, "off": Vector3(-0.56, 1.25, 0.05)}
const BROKEN := {"hand": Vector3(0.5, 0.65, -0.1), "blade": Vector3(-0.5, 0.6, 0.3), "torso": Vector3(-0.65, 0.1, 0.12),
	"body": Vector4(0.25, 0.0, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.3, 0.72, -0.25)}
const DODGE := {"hand": Vector3(0.36, 1.0, 0.12), "blade": Vector3(-0.3, -0.05, 0.0), "torso": Vector3(-0.3, 0.0, 0.0),
	"body": Vector4(0.16, -0.06, 0.0, 0.0), "grip": 0.0, "off": Vector3(-0.38, 0.95, -0.05)}
