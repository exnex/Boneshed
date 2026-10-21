extends RefCounted
## Stamina for one lab fighter: capacity, spending, refunds and recovery. Pure and
## deterministic; owned by duelist_state.gd, which decides *when* an action is charged.
##
## Rules (experimental, centrally tuned in tuning.json):
##   - An action is affordable when `current >= cost` (an exact match is affordable).
##   - Unaffordable actions are refused, never partially charged; the refusal is kept
##     in `last_refusal` (and counted) so HUD, AI and tests read the same result.
##   - Every charge is recorded once in `ledger` with the action's serial.
##   - Recovery starts `regen_delay` after the last charge (`empty_regen_delay` if that
##     charge emptied the pool) at `regen` per second. Holding a chamber or a guard
##     neither drains nor slows recovery unless the hold scales are set below 1.

const EPSILON := 1e-6

var max_stamina := 100.0
var current := 100.0
var regen := 28.0
var regen_delay := 0.6
var empty_regen_delay := 1.2
var since_spend := 99.0
var emptied := false
var refusals := 0
var last_refusal := {}
var ledger: Array[Dictionary] = []

func configure(capacity: float, regen_rate: float, delay: float, empty_delay: float) -> void:
	max_stamina = capacity
	regen = regen_rate
	regen_delay = delay
	empty_regen_delay = empty_delay
	reset()

func reset() -> void:
	current = max_stamina
	since_spend = 99.0
	emptied = false
	refusals = 0
	last_refusal = {}
	ledger.clear()

func can_afford(cost: float, extra := 0.0) -> bool:
	return current + extra + EPSILON >= cost

## Charges `cost` for `action` (serial distinguishes repeated actions). Returns false and
## records a refusal instead when unaffordable. `extra` is stamina the same action
## returns first (a cancel refund), so it counts toward affordability.
func spend(action: String, cost: float, serial: int, clock: float, extra := 0.0) -> bool:
	if not can_afford(cost, extra):
		refuse(action, cost, clock)
		return false
	current = clampf(current + extra - cost, 0.0, max_stamina)
	since_spend = 0.0
	emptied = current <= EPSILON
	ledger.append({"action": action, "cost": cost, "refund": extra, "serial": serial, "at": snappedf(clock, 0.0001)})
	return true

func refuse(action: String, cost: float, clock: float) -> void:
	refusals += 1
	last_refusal = {"action": action, "cost": cost, "stamina": current, "at": clock, "count": refusals}

## Returns stamina for a voluntary feint cancel (recorded; never above capacity).
func refund(amount: float, serial: int, clock: float) -> void:
	if amount <= 0.0:
		return
	current = minf(max_stamina, current + amount)
	ledger.append({"action": "refund", "cost": -amount, "refund": amount, "serial": serial, "at": snappedf(clock, 0.0001)})

## `scale` lets the owner slow recovery in a state (1 = unchanged).
func tick(delta: float, scale := 1.0) -> void:
	since_spend += delta
	var delay := empty_regen_delay if emptied else regen_delay
	if since_spend >= delay and current < max_stamina:
		current = minf(max_stamina, current + regen * scale * delta)
		emptied = false

func fraction() -> float:
	return current / max_stamina if max_stamina > 0.0 else 0.0
