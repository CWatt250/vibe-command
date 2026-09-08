extends RefCounted
## ResourceNodeComponent — a depletable harvestable resource field (Blueprint §5.4).
## Exposes remaining quantity + harvest point(s). EconomySystem reduces remaining as
## harvesters mine; the node is removed when depleted.

var radius: float = 60.0          # spatial footprint for harvest targeting
var min_distance: float = 30.0    # harvester must be within harvest_radius
var harvest_points: Array[Vector2] = []  # approach slots (blueprint §5.4 deadlock grace)
var remaining: float = 3000.0     # credits left in this field
var max_remaining: float = 3000.0
var depleted: bool = false

func setup(def: Dictionary, _self: Entity) -> void:
	max_remaining = def.get("quantity", 3000.0)
	remaining = max_remaining
	radius = def.get("harvestRadius", 60.0)
	min_distance = def.get("minDistance", 30.0)

func take(amount: float) -> float:
	## Extract up to `amount`; returns what was actually taken. Sets depleted when empty.
	if depleted or remaining <= 0.0:
		return 0.0
	var amt: float = minf(amount, remaining)
	remaining -= amt
	if remaining <= 0.01:
		remaining = 0.0
		depleted = true
	return amt

func percent() -> float:
	if max_remaining <= 0.0:
		return 0.0
	return remaining / max_remaining
