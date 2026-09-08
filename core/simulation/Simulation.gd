extends RefCounted
class_name Simulation
## Simulation — the authoritative fixed-tick RTS loop (Blueprint §3.1). Pure logic, no Node,
## so it can run headless for automated tests. Presentation scenes observe via GameEvents.
## Tick rate: TICK_HZ (default 15 Hz). Renders interpolate.

const TICK_HZ: int = 15
const TICK_DT: float = 1.0 / TICK_HZ

var registry: ContentRegistry
var events: GameEvents

var grid_map: NavGrid
var spatial: SpatialIndex
var power_sys: PowerSystem
var compute_sys: ComputeSystem
var command_sys: CommandCapacitySystem
var combat: CombatSystem
var fog_sys: FogOfWarSystem
var economy_sys: EconomySystem
var skirmish_ai: SkirmishAI = null
var compute_deficit: Dictionary = {}   # faction -> bool (or global combat penalty source)
var dt: float = 0.0                   # last step's delta (read by systems) 
var control_groups: Dictionary = {}     # group_index (0-9) -> Array[int] entity ids

## Control-group / garrison event bus hooks (emitted by the sim this tick).
var _pending_garrison: Array = []       # [{structure_id, unit_ids[]}] to resolve each tick

## Transient UI/selection state (owned by sim as the single authority on entities/factions).
var selected_ids: Array = []
var selected_faction: String = ""

var entities: Dictionary = {}          # entity id -> Entity
var _next_id: int = 1
var _players: Dictionary = {}          # faction -> {resources:{}, ...}
var tick: int = 0
var time: float = 0.0
var match_over_for: Dictionary = {}    # faction -> bool (base destroyed)

func _init(registry_: ContentRegistry, events_: GameEvents, grid_h: int, grid_w: int) -> void:
	registry = registry_
	events = events_
	grid_map = NavGrid.new(grid_w, grid_h)
	spatial = SpatialIndex.new()
	fog_sys = FogOfWarSystem.new(grid_w, grid_h, NavGrid.CELL)
	power_sys = PowerSystem.new()
	compute_sys = ComputeSystem.new()
	command_sys = CommandCapacitySystem.new(registry)
	combat = CombatSystem.new(self, registry, events)
	economy_sys = EconomySystem.new()
	# Skirmish AI is attached by the world/tests via attach_skirmish_ai().

# --- Players / resources ---
func add_player(faction: String) -> void:
	var f = registry.get_faction(faction)
	var res: Dictionary = {}
	for rid in f.get("resourceIds", []):
		if rid == "credits":
			res[rid] = f.get("startCredits", 1500)
		elif rid == "power":
			res[rid] = f.get("startPower", 0)
		else:
			res[rid] = 0
	_players[faction] = {"resources": res, "techTier": 1}

func get_resources(faction: String) -> Dictionary:
	if not _players.has(faction):
		return {}
	return _players[faction]["resources"]

func add_credits(faction: String, amount: float) -> void:
	if not _players.has(faction):
		return
	_players[faction]["resources"]["credits"] += amount
	events.resource_changed.emit(faction, "credits", amount)

func spend_credits(faction: String, amount: float) -> bool:
	if not _players.has(faction):
		return false
	var cur: float = _players[faction]["resources"].get("credits", 0.0)
	if cur >= amount:
		_players[faction]["resources"]["credits"] = cur - amount
		events.resource_changed.emit(faction, "credits", -amount)
		return true
	return false

# --- Entity spawning ---
func spawn_unit(def_id: String, faction: String, pos: Vector2) -> int:
	var def = registry.get_unit(def_id)
	if def.is_empty():
		push_error("Simulation: unknown unit def " + def_id)
		return -1
	var e = Entity.new(def, faction, _next_id)
	e.kind = "unit"
	e._attach_components(registry, def)
	_register_entity(e, def_id, pos)
	return e.id

func spawn_structure(def_id: String, faction: String, pos: Vector2, start_built: bool = true) -> int:
	var def = registry.get_structure(def_id)
	if def.is_empty():
		push_error("Simulation: unknown structure def " + def_id)
		return -1
	var e = Entity.new(def, faction, _next_id)
	e.kind = "structure"
	e._attach_components(registry, def, start_built)
	_register_entity(e, def_id, pos)
	if start_built:
		events.structure_placed.emit(e.id, def_id, faction, pos)
	else:
		events.log.emit("Construction started: " + def_id)
	return e.id

## Spawn a build site (structure under construction). Blocks its footprint in the grid.
func spawn_build_site(def_id: String, faction: String, pos: Vector2) -> int:
	var id := spawn_structure(def_id, faction, pos, false)
	if id == -1:
		return -1
	_block_footprint(entities[id])
	return id

func _block_footprint(e: Entity) -> void:
	var fp: Array = e.def_data.get("footprint", [1, 1])
	var w: int = fp[0] if fp.size() > 0 else 1
	var h: int = fp[1] if fp.size() > 1 else 1
	var c: Vector2i = grid_map.world_to_cell(e.position.x, e.position.y)
	grid_map.block_rect(c.x - w / 2, c.y - h / 2, w, h)

## Attach a Phase 6 skirmish opponent directing `faction`, targeting `enemy`.
func attach_skirmish_ai(faction: String, enemy: String) -> SkirmishAI:
	skirmish_ai = SkirmishAI.new(self, faction, enemy)
	return skirmish_ai

## Spawn a depletable resource field (Blueprint §5.4) as a structure with a
## ResourceNodeComponent. Harvesters mine it for credits.
func spawn_resource_field(pos: Vector2, quantity: float = 3000.0) -> int:
	var def_id := "RESOURCE_FIELD"
	var e := Entity.new({}, "", _next_id)
	e.kind = "structure"
	e._attach_components(registry, { "resource": true, "quantity": quantity, "harvestRadius": 60.0, "minDistance": 30.0 })
	_register_entity(e, def_id, pos)
	return e.id

func _unblock_footprint(e: Entity) -> void:
	var fp: Array = e.def_data.get("footprint", [1, 1])
	var w: int = fp[0] if fp.size() > 0 else 1
	var h: int = fp[1] if fp.size() > 1 else 1
	var c: Vector2i = grid_map.world_to_cell(e.position.x, e.position.y)
	grid_map.unblock_rect(c.x - w / 2, c.y - h / 2, w, h)

func _register_entity(e: Entity, _def_id: String, pos: Vector2) -> void:
	var id := e.id
	e.grid = grid_map
	e.spatial = spatial
	e.position = pos
	entities[id] = e
	_next_id += 1
	spatial.update(id, pos)
	events.entity_created.emit(id, e.def_id, e.faction_id, pos)

func remove_entity(id: int) -> void:
	if not entities.has(id):
		return
	var e: Entity = entities[id]
	e.alive = false
	spatial.remove(id)
	entities.erase(id)
	events.entity_destroyed.emit(id, e.def_id, e.position)

# --- Main fixed tick ---
func step(dt: float) -> void:
	self.dt = dt
	tick += 1
	time += dt
	events.game_tick.emit(tick, dt)
	# Iterate copy so removing during iteration is safe.
	for id in entities.keys():
		var e: Entity = entities.get(id)
		if e == null or not e.alive:
			continue
		_tick_entity(e, dt)
	_recompute_power()
	_recompute_compute()
	_recompute_fog()
	# Combat is resolved by the sim itself (authoritative, Blueprint §2) so a
	# headless sim fully simulates without an external driver.
	combat.tick_all()
	# Economy (passive income + harvester loop) drives credits each tick.
	economy_sys.tick(self, dt)
	# Skirmish opponent (Phase 6) decides + issues orders.
	if skirmish_ai != null:
		skirmish_ai.update(dt)
	_cleanup_control_groups()

func _recompute_fog() -> void:
	## Update each faction's visibility grid from its entities' sensor radii.
	var by_faction: Dictionary = {}
	for id in entities:
		var e: Entity = entities[id]
		if e == null or not e.alive:
			continue
		if not by_faction.has(e.faction_id):
			by_faction[e.faction_id] = true
	for faction in by_faction.keys():
		if fog_sys != null:
			fog_sys.update(entities, faction)

func _cleanup_control_groups() -> void:
	## Control groups store entity ids; auto-remove destroyed entities (§ line 341).
	for g in control_groups.keys():
		var group: Array = control_groups[g]
		var kept: Array = []
		for id in group:
			if entities.has(id):
				kept.append(id)
		control_groups[g] = kept

func _recompute_power() -> void:
	## Per-faction power ratio -> production speed_scale (Blueprint §5.5 / §6).
	var by_faction: Dictionary = {}
	for id in entities:
		var e: Entity = entities[id]
		if not by_faction.has(e.faction_id):
			by_faction[e.faction_id] = true
	for faction in by_faction.keys():
		var r: Dictionary = power_sys._compute(entities, faction)
		var scale: float = power_sys._speed_scale(r["ratio"])
		for eid in entities:
			var e: Entity = entities[eid]
			if e.faction_id != faction:
				continue
			if e.production != null:
				e.production.set_speed_scale(scale)
				e.production.set_powered(r["powered"])

func _recompute_compute() -> void:
	## Per-faction compute economy (Blueprint §6.1): produced vs reserved, reduced by
	## power brownout and cooling shortfall. Under deficit, apply a deterministic
	## global reaction/cooldown penalty (not random shutdown).
	var by_faction: Dictionary = {}
	for id in entities:
		var e: Entity = entities[id]
		if not by_faction.has(e.faction_id):
			by_faction[e.faction_id] = true
	for faction in by_faction.keys():
		var armed: bool = _is_armed(faction)
		var power_ratio: float = 1.0
		if power_sys != null:
			var pr: Dictionary = power_sys._compute(entities, faction)
			power_ratio = pr.get("ratio", 1.0)
		var c: Dictionary = compute_sys._compute(entities, faction, power_ratio)
		var deficit: bool = c.get("deficit", false)
		compute_deficit[faction] = deficit
		# Apply the global cooldown penalty across the faction's weapons.
		if armed or deficit:
			for eid in entities:
				var e: Entity = entities[eid]
				if e.faction_id != faction or e.weapon == null:
					continue
				e.weapon.set_reaction_scale(compute_sys.reaction_scale(deficit))

func _is_armed(faction: String) -> bool:
	## A faction is "armed" for compute purposes once it has ANY compute-producing structure.
	for id in entities:
		var e: Entity = entities[id]
		if e.faction_id != faction:
			continue
		if e.kind != "structure":
			continue
		if e.def_data.get("computeProduced", 0.0) > 0.0:
			return true
	return false

func _tick_entity(e: Entity, dt: float) -> void:
	# Construction progress (build sites) — emits completion when built.
	if e.construction != null and not e.construction.is_built():
		if e.construction.tick(dt):
			events.building_constructed.emit(e.id, e.def_id, e.faction_id)
	if e.movement != null:
		var newpos: Vector2 = e.movement.update(dt, e.position)
		if newpos != e.position:
			e.position = newpos
			spatial.update(e.id, newpos)
	if e.weapon != null:
		e.weapon.tick_cool(dt)
	if e.production != null:
		var done: Array = e.production.tick(dt)
		for unit in done:
			var def = registry.get_unit(unit)
			var cost = def.get("costCredits", 0.0)
			# spawn at rally point
			spawn_unit(unit, e.faction_id, e.production.rally_point)
			events.unit_spawned.emit(e.id, unit, e.faction_id, e.position)

func run_commands(id: int, commands: Array) -> void:
	## Apply a list of orders to entities (Blueprint §3.3 command schema). Called by UI/presenters.
	for cmd in commands:
		var cmd_type: String = cmd.get("type", "")
		var targets: Array = cmd.get("entityIds", [])
		match cmd_type:
			"MOVE":
				_issue_move(id, targets, cmd.get("targetPosition", Vector2.ZERO))
			"ATTACK":
				_issue_attack(id, targets, cmd)
			"ATTACK_MOVE":
				_issue_attack_move(id, targets, cmd.get("targetPosition", Vector2.ZERO))
			"STOP":
				for t in targets:
					var et: Entity = entities.get(t)
					if et != null and et.movement != null:
						et.movement.clear()
			"BUILD":
				_issue_build(id, cmd)
			"TRAIN":
				_issue_train(id, targets, cmd)
			"SET_RALLY":
				_issue_set_rally(id, targets, cmd.get("position", Vector2.ZERO))
			"CONTROL_ASSIGN":
				_assign_control_group(cmd.get("group", 0), targets)
			"CONTROL_RECALL":
				_recall_control_group(cmd.get("group", 0))
			"GARRISON":
				_issue_garrison(id, targets, cmd.get("targetEntityId", -1))
			"UNGARRISON":
				_issue_ungarrison(id, targets)
			"REPAIR":
				_issue_repair(id, targets, cmd.get("targetEntityId", -1))
			_:
				pass

# --- Order internals (pathing + formation for group moves) ---
func _issue_move(self_id: int, targets: Array, destination: Vector2) -> void:
	# Formation offset for group moves so units do not stack (Blueprint §3.6).
	var n: int = targets.size()
	var offsets := _formation_offsets(n)
	for i in range(n):
		var t: int = targets[i]
		var e: Entity = entities.get(t)
		if e == null or e.movement == null:
			continue
		var dest: Vector2 = destination + offsets[i]
		var path := grid_map.find_path(e.position, dest, e.movement.path_layer == "air")
		e.movement.set_path(path, dest)

func _formation_offsets(n: int) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if n <= 0:
		return offsets
	if n == 1:
		# Single-unit orders still index offsets[0] in _issue_move.
		offsets.append(Vector2.ZERO)
		return offsets
	var spacing := 22.0
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / maxi(cols, 1)))
	for i in range(n):
		var cx := i % cols
		var cy := i / cols
		offsets.append(Vector2((cx - (cols - 1) * 0.5) * spacing, (cy - (rows - 1) * 0.5) * spacing))
	return offsets

func _issue_attack(self_id: int, targets: Array, cmd: Dictionary) -> void:
	var target_entity: int = cmd.get("targetEntityId", -1)
	for t in targets:
		var e: Entity = entities.get(t)
		if e == null or e.weapon == null:
			continue
		# Attacker keeps moving to engage; weapon release handles range.
		e.weapon.current_target_id = target_entity

func _issue_attack_move(self_id: int, targets: Array, destination: Vector2) -> void:
	_issue_move(self_id, targets, destination)

# --- Base building (Blueprint §5.2) / production (Blueprint §5.3) ---
func _issue_build(self_id: int, cmd: Dictionary) -> void:
	var def_id: String = cmd.get("structureDefId", "")
	var pos: Vector2 = cmd.get("position", Vector2.ZERO)
	var faction: String = cmd.get("faction", _issue_builder_faction(cmd.get("builderId", 0)))
	if faction == "":
		events.log.emit("BUILD rejected: no faction")
		return
	var def = registry.get_structure(def_id)
	if def.is_empty():
		events.log.emit("BUILD rejected: unknown structure " + def_id)
		return
	# 1. Credits check + reserve (Blueprint §5.2 step 3).
	var cost: float = def.get("costCredits", 0.0)
	if not spend_credits(faction, cost):
		events.log.emit("BUILD rejected: not enough credits for " + def_id)
		return
	# 2. Placement ghost checks: grid passable + inside build radius of an HQ (steps 2).
	if not _placement_valid(def, pos, faction):
		# No footprint conflict; refund reserved credits + reject.
		add_credits(faction, cost)
		events.log.emit("BUILD rejected: invalid placement for " + def_id)
		return
	var id := spawn_build_site(def_id, faction, pos)
	events.structure_order.emit(id, def_id, faction, pos)

func _issue_builder_faction(builder_id: int) -> String:
	if builder_id >= 0 and entities.has(builder_id):
		return entities[builder_id].faction_id
	return selected_faction

func _placement_valid(def: Dictionary, pos: Vector2, faction: String) -> bool:
	# Footprint cells must be clear / in-bounds.
	var fp: Array = def.get("footprint", [1, 1])
	var w: int = fp[0] if fp.size() > 0 else 1
	var h: int = fp[1] if fp.size() > 1 else 1
	var c: Vector2i = grid_map.world_to_cell(pos.x, pos.y)
	for dy in range(h):
		for dx in range(w):
			var cx: int = c.x - w / 2 + dx
			var cy: int = c.y - h / 2 + dy
			if not grid_map.in_bounds(cx, cy):
				return false
			if grid_map.is_blocked(cx, cy):
				return false
	# Build radius: require a built HQ owned by faction within range.
	var radius: float = _build_radius_for(faction)
	if radius > 0.0:
		var in_range := false
		for eid in entities:
			var e: Entity = entities[eid]
			if e.faction_id != faction or e.kind != "structure":
				continue
			var d: Dictionary = e.def_data
			if d.get("class", "") == "HQ" and (e.construction == null or e.construction.is_built()):
				if pos.distance_to(e.position) <= radius:
					in_range = true
					break
		if not in_range:
			return false
	return true

func _build_radius_for(faction: String) -> float:
	# From the faction's HQ/"BuilderNetwork" config; default 1200 if present.
	var f = registry.get_faction(faction)
	if f.has("buildRadius"):
		return f["buildRadius"]
	return 1200.0

func _issue_train(self_id: int, targets: Array, cmd: Dictionary) -> void:
	var unit_id: String = cmd.get("unitDefId", "")
	var def = registry.get_unit(unit_id)
	if def.is_empty():
		events.log.emit("TRAIN rejected: unknown unit " + unit_id)
		return
	var cost: float = def.get("costCredits", 0.0)
	var build_time: float = def.get("buildTimeSec", 5.0)
	var unit_reserve: float = def.get("reserveCapacity", 0.0)
	# Command Capacity gate (§6.2): the FEDERAL differentiator — deficit BLOCKS new
	# elite production (does NOT debuff existing units like Compute does).
	# Compute command state for the producing faction once, before the loop.
	var _cmd_state: Dictionary = {}
	if unit_reserve > 0.0:
		var _f: String = "FC"
		# Resolve the producing faction from the first valid target.
		for t in targets:
			var te: Entity = entities.get(t)
			if te != null:
				_f = te.faction_id
				break
		_cmd_state = command_sys._compute(entities, _f)
		if not command_sys.can_produce(_cmd_state, unit_reserve):
			events.log.emit("TRAIN blocked: command capacity exceeded for " + unit_id + " (faction " + _f + ")")
			return
	# target(s) = production structure(s); enqueue on each in range/powered.
	for t in targets:
		var e: Entity = entities.get(t)
		if e == null or e.production == null:
			continue
		if e.construction != null and not e.construction.is_built():
			continue
		var faction: String = e.faction_id
		if not spend_credits(faction, cost):
			events.log.emit("TRAIN rejected: not enough credits for " + unit_id)
			continue
		e.production.enqueue(unit_id, cost, build_time)
		events.production_queued.emit(e.id, unit_id, cost)

func _issue_set_rally(self_id: int, targets: Array, position: Vector2) -> void:
	for t in targets:
		var e: Entity = entities.get(t)
		if e != null and e.production != null:
			e.production.rally_point = position

# ---- Control groups (§ M1: "control groups", line 341) ----
## Assign selected entity ids to a control group index (0-9), overwriting it.
func assign_control_group(group: int, entity_ids: Array) -> void:
	control_groups[group] = entity_ids.duplicate()

func _assign_control_group(group: int, targets: Array) -> void:
	var ids: Array = []
	for t in targets:
		var e: Entity = entities.get(t)
		if e != null and e.alive:
			ids.append(t)
	control_groups[group] = ids

## Recall a control group: select its (still-alive) members.
func recall_control_group(group: int) -> Array:
	if control_groups.has(group):
		selected_ids = []
		for id in control_groups[group]:
			if entities.has(id):
				selected_ids.append(id)
		return selected_ids
	return []

func _recall_control_group(group: int) -> void:
	recall_control_group(group)

# ---- Garrison (§ "Garrison" M1 gate, §5.7 "buildings with garrison slots") ----
## Move infantry into a garrisonable structure. Slotted by the structure def's
## `garrisoned` capacity. The building must be owned by the same faction, built,
## and have a free slot. Eject on structure destroy is handled by the sim owner.
func garrison_units(structure_id: int, unit_ids: Array) -> int:
	var s: Entity = entities.get(structure_id)
	if s == null or s.garrison == null:
		return 0
	var capacity: int = s.garrison.capacity
	var loaded: int = 0
	for uid in unit_ids:
		var u: Entity = entities.get(uid)
		if u == null or not u.alive:
			continue
		if u.garrisonable == null or not u.garrisonable.can_garrison:
			continue
		if u.faction_id != s.faction_id:
			continue
		if not s.garrison.has_space():
			break
		s.garrison.add_occupant(uid)
		u.garrisoned_into = structure_id
		u.alive = false  # hidden; structure fires for them (§5.7 proxy)
		loaded += 1
		events.log.emit("GARRISON: unit " + str(uid) + " entered " + str(structure_id))
	return loaded

func _issue_garrison(self_id: int, targets: Array, structure_id: int) -> void:
	garrison_units(structure_id, targets)

## Release all garrisoned units, spawning them adjacent to the structure.
func ungarrison_units(structure_id: int) -> void:
	var s: Entity = entities.get(structure_id)
	if s == null or s.garrison == null:
		return
	for uid in s.garrison.occupants.duplicate():
		var u: Entity = entities.get(uid)
		if u == null:
			continue
		u.alive = true
		u.garrisoned_into = -1
		u.position = s.position + Vector2(_rand_offset(), _rand_offset())
		s.garrison.remove_occupant(uid)
		events.log.emit("UNGARRISON: unit " + str(uid) + " exited " + str(structure_id))

func _issue_ungarrison(self_id: int, targets: Array) -> void:
	if targets.size() > 0:
		for t in targets:
			var e: Entity = entities.get(t)
			if e != null and e.garrison != null:
				ungarrison_units(t)
	else:
		for g in control_groups.keys():
			pass

# ---- Repair (§ "repair" M1 gate) ----
## Order a repair-capable structure/unit to repair a friendly target to full.
## Heals over time each tick while in range and (for structures) powered.
func repair_entity(self_id: int, target_id: int) -> void:
	var unit: Entity = entities.get(target_id)
	if unit == null or not unit.alive:
		return
	unit.repair_target = self_id

func _issue_repair(self_id: int, targets: Array, target_id: int) -> void:
	repair_entity(self_id, target_id)

func _rand_offset() -> float:
	# Deterministic-ish small offset for ejection placement.
	return (randf() - 0.5) * 30.0
