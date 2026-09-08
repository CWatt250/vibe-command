extends RefCounted
class_name GarrisonableComponent
## GarrisonableComponent — a unit that can enter a garrison structure (§5.7).
## Set on infantry via `garrisonCapable: true` in the unit def.

var can_garrison: bool = true

func setup(def: Dictionary) -> void:
	can_garrison = bool(def.get("garrisonCapable", true))
