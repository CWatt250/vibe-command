extends RefCounted
class_name CommandCapacitySystem
## CommandCapacitySystem — per-faction Federal Command Capacity economy (§6.2).
## Command Posts / HQ produce capacity (`commandCapacity`); elite units reserve it
## (`reserveCapacity`) while alive. Unlike Compute (§6.1), a Command DEFICIT BLOCKS
## new elite production rather than debuffing existing units — the faction differentiator.

var _registry: ContentRegistry

func _init(registry: ContentRegistry = null) -> void:
	_registry = registry

func _compute(entities: Dictionary, faction: String) -> Dictionary:
	## Returns {capacity, reserved, available, deficit}.
	## capacity   = commandCapacity supplied by the faction's built command/HQ structures.
	## reserved   = Command held by the faction's LIVING units PLUS units still queued
	##              for production (reserved-but-not-yet-spawned). Both must count or an
	##              elite train could slip past the gate before its entity exists.
	## available  = capacity - reserved.
	## deficit    = the faction HAS command infra but reserved exceeds capacity.
	var produced: float = 0.0
	var reserved: float = 0.0
	for id in entities:
		var e: Entity = entities[id]
		if e.faction_id != faction:
			continue
		var def: Dictionary = e.def_data
		if e.kind == "structure":
			if e.construction != null and not e.construction.is_built():
				continue
			produced += def.get("commandCapacity", 0.0) + def.get("commandProduced", 0.0)
			# Account for reserve committed to units waiting in this structure's queue.
			if e.production != null:
				for item in e.production.queue:
					var qdef: String = item.get("unit", "")
					var q := _unit_reserve(entities, qdef)
					if q > 0.0:
						reserved += q
		elif e.kind == "unit":
			reserved += def.get("reserveCapacity", 0.0)
	var available: float = produced - reserved
	var deficit: bool = produced > 0.0 and available < 0.0
	return {"capacity": produced, "reserved": reserved,
		"available": available, "deficit": deficit}

func _unit_reserve(_entities: Dictionary, unit_id: String) -> float:
	## Resolve reserveCapacity for a unit id from the registry. Unknown/ordinary units
	## resolve to 0 so they stay producible; a missing registry is a safe 0 as well.
	if _registry == null:
		return 0.0
	var d: Dictionary = _registry.get_unit(unit_id)
	if d.is_empty():
		return 0.0
	return d.get("reserveCapacity", 0.0)

func can_produce(c: Dictionary, unit_reserve: float) -> bool:
	## Gate for enqueueing a new unit with the given command reserve.
	## No command infra at all -> only units that reserve zero Command (ordinary) are allowed.
	## Otherwise require enough free capacity for this unit's reserve.
	if c.get("capacity", 0.0) <= 0.0:
		return unit_reserve <= 0.0
	return c["available"] >= unit_reserve
