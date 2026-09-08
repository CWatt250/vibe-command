extends RefCounted
## HarvestComponent — data + state for a harvester unit (Blueprint §5.4 economy).
## The EconomySystem drives the state machine; this component holds the current state,
## cargo, and target references. States => next action, verified by tests.

enum State { IDLE, TRAVEL_FIELD, HARVEST, TRAVEL_DROPOFF, DEPOSIT }

var state: int = State.IDLE
var capacity: float = 500.0        # max credits carried per trip
var harvest_rate: float = 60.0     # credits harvested per second at full rate
var harvest_radius: float = 40.0   # how close to a resource node it must be to harvest
var deposit_radius: float = 60.0   # how close to a dropoff it must be to deposit
var cargo: float = 0.0
var target_field_id: int = -1      # resource node id being mined
var dropoff_id: int = -1           # dropoff structure id being delivered to

func setup(def: Dictionary, _self: Entity) -> void:
	capacity = def.get("harvestCapacity", 500.0)
	harvest_rate = def.get("harvestRatePerSec", 60.0)
	harvest_radius = def.get("harvestRadius", 40.0)
	deposit_radius = def.get("depositRadius", 60.0)

func is_busy() -> bool:
	return state != State.IDLE

func reset() -> void:
	state = State.IDLE
	cargo = 0.0
	target_field_id = -1
	dropoff_id = -1

## True when the harvester carries a full (or near-full) load and should return.
func is_full() -> bool:
	return cargo >= capacity - 0.01

func is_empty() -> bool:
	return cargo <= 0.01
