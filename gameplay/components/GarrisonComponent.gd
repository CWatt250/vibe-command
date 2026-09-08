extends RefCounted
class_name GarrisonComponent
## GarrisonComponent — a structure with N slots that infantry can occupy (§5.7).
## Occupants are hidden (alive=false) and the structure fires for them as a scaling proxy.

var capacity: int = 0
var occupants: Array = []   # unit entity ids, in insertion order

func setup(def: Dictionary) -> void:
	capacity = int(def.get("garrisoned", 0))

func has_space() -> bool:
	return occupants.size() < capacity

func add_occupant(unit_id: int) -> void:
	if has_space():
		occupants.append(unit_id)

func remove_occupant(unit_id: int) -> void:
	occupants.erase(unit_id)

func occupant_count() -> int:
	return occupants.size()

func count() -> int:
	return occupants.size()
