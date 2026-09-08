extends RefCounted
class_name EconomySystem
## Per-faction economy (Blueprint §5.4). Two income channels:
##   1. Passive income from Economy-class structures + HQ (ticks every interval).
##   2. Harvester loop: drives each harvester unit's state machine to mine a
##      nearby ResourceNode field, then deposit credits at a Dropoff structure.
## Deterministic; driven by Simulation.step() (headless-friendly).

const HarvestComponent := preload("res://gameplay/components/HarvestComponent.gd")

const HARVEST_INTERVAL := 1.0      # seconds between deposit increments (passive)
const PASSIVE_PER_ECON := 4.0       # credits/s from an Economy structure
const PASSIVE_PER_HQ := 2.0         # credits/s from HQ

## Called each tick. Returns nothing; mutates faction credits via sim.add_credits.
func tick(sim, dt: float) -> void:
	_passive_income(sim, dt)
	_pump_harvesters(sim, dt)

func _passive_income(sim, dt: float) -> void:
	# Per-faction income based on built Economy structures + HQ.
	var by_faction := {}
	for e in sim.entities.values():
		if e.kind != "structure" or not e.alive:
			continue
		if e.construction != null and not e.construction.is_built():
			continue
		var cls: String = e.def_data.get("class", "")
		if cls != "Economy" and cls != "HQ":
			continue
		var f: String = e.faction_id
		var rate: float = PASSIVE_PER_ECON if cls == "Economy" else PASSIVE_PER_HQ
		by_faction[f] = by_faction.get(f, 0.0) + rate
	for f in by_faction:
		sim.add_credits(f, by_faction[f] * dt)

func _pump_harvesters(sim, dt: float) -> void:
	for e in sim.entities.values():
		if e.kind != "unit" or e.harvest == null or not e.alive:
			continue
		_pump_harvester(sim, e, dt)

func _pump_harvester(sim, e: Entity, dt: float) -> void:
	var h := e.harvest
	match h.state:
		HarvestComponent.S_IDLE:
			# Find the nearest reachable resource field with remaining quantity.
			var field := _nearest_field(sim, e, 1.0)
			if field == null:
				return
			h.target_field_id = field.id
			h.state = HarvestComponent.S_TO_FIELD
		HarvestComponent.S_TO_FIELD:
			var field: Entity = sim.entities.get(h.target_field_id)
			if field == null or field.resource == null or field.resource.depleted:
				_reset_harvester(sim, e)
				return
			if e.position.distance_to(field.position) <= h.harvest_radius:
				h.state = HarvestComponent.S_HARVESTING
			else:
				# Move toward the field (simple steering; MovementComponent handles pathing).
				_drive_to(sim, e, field.position)
		HarvestComponent.S_HARVESTING:
			var field: Entity = sim.entities.get(h.target_field_id)
			if field == null or field.resource == null or field.resource.depleted:
				_reset_harvester(sim, e)
				return
			h.cargo = min(h.capacity, h.cargo + h.harvest_rate * dt)
			field.resource.take(h.harvest_rate * dt)
			if h.cargo >= h.capacity or field.resource.remaining <= 0.5:
				h.state = HarvestComponent.S_TO_DROPOFF
		HarvestComponent.S_TO_DROPOFF:
			var drop: Entity = _nearest_dropoff(sim, e)
			if drop == null:
				_reset_harvester(sim, e)
				return
			h.dropoff_id = drop.id
			if e.position.distance_to(drop.position) <= h.harvest_radius:
				h.state = HarvestComponent.S_DEPOSIT
				_drive_to(sim, e, drop.position)  # stop adjacent
			else:
				_drive_to(sim, e, drop.position)
		HarvestComponent.S_DEPOSIT:
			var dropoff: Entity = sim.entities.get(h.dropoff_id)
			if dropoff == null or not dropoff.alive:
				_reset_harvester(sim, e)
				return
			var amt := h.cargo
			sim.add_credits(e.faction_id, amt)
			h.cargo = 0.0
			h.state = HarvestComponent.S_IDLE
			h.target_field_id = -1
			h.dropoff_id = -1

func _nearest_field(sim, e: Entity, min_qty: float) -> Entity:
	var best: Entity = null
	var best_d := INF
	for f in sim.entities.values():
		if f.kind != "structure" or f.resource == null or not f.alive:
			continue
		if f.resource.depleted or f.resource.remaining < min_qty:
			continue
		var d := e.position.distance_squared_to(f.position)
		if d < best_d:
			best_d = d
			best = f
	return best

func _nearest_dropoff(sim, e: Entity) -> Entity:
	var best: Entity = null
	var best_d := INF
	for f in sim.entities.values():
		if f.kind != "structure" or not f.alive:
			continue
		if f.faction_id != e.faction_id:
			continue
		if not ("Dropoff" in f.def_data.get("componentFlags", [])):
			continue
		var d := e.position.distance_squared_to(f.position)
		if d < best_d:
			best_d = d
			best = f
	return best

func _drive_to(sim, e: Entity, dest: Vector2) -> void:
	if e.movement == null:
		return
	# Only issue a fresh path when idle/not already moving, so we don't re-path every tick.
	if e.movement.is_moving() and e.movement.goal.distance_to(dest) <= 4.0:
		return
	sim.run_commands(e.id, [{ "type": "MOVE", "entityIds": [e.id], "targetPosition": dest }])

func _reset_harvester(sim, e: Entity) -> void:
	var h := e.harvest
	h.state = HarvestComponent.S_IDLE
	h.target_field_id = -1
	h.dropoff_id = -1
	h.cargo = 0.0
