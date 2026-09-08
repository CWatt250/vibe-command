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
var combat: CombatSystem
var compute_deficit: Dictionary = {}   # faction -> bool (or global combat penalty source)

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
	power_sys = PowerSystem.new()
	compute_sys = ComputeSystem.new()
	combat = CombatSystem.new(self, registry, events)

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
	# Combat is resolved by the sim itself (authoritative, Blueprint §2) so a
	# headless sim fully simulates without an external driver.
	combat.tick_all()

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
	if n <= 1:
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
