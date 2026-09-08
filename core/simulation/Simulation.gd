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

func spawn_structure(def_id: String, faction: String, pos: Vector2) -> int:
	var def = registry.get_structure(def_id)
	if def.is_empty():
		push_error("Simulation: unknown structure def " + def_id)
		return -1
	var e = Entity.new(def, faction, _next_id)
	e.kind = "structure"
	e._attach_components(registry, def)
	_register_entity(e, def_id, pos)
	events.structure_placed.emit(e.id, def_id, faction, pos)
	return e.id

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

func _tick_entity(e: Entity, dt: float) -> void:
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
