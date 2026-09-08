extends RefCounted
class_name SkirmishAI
## Phase 6 — the opposing skirmish AI (Blueprint §7.1). Layered managers issue the
## same run_commands a player would (BUILD/TRAIN/MOVE/ATTACK_MOVE). It claims NO
## hidden info: it behaves from what it can legitimately see/has scouted (fog-aware),
## builds a real economy, expands a base, trains an army, and attacks.

## Tunables (Blueprint §12 allows simplest sane values).
const ECO_TARGET := 2                 # desired Economy structures
const POWER_TARGET := 2               # desired Power structures
const PROD_INFANTRY := 1              # Infantry production structures
const PROD_VEHICLE := 1              # Vehicle production structures
const ARMY_TARGET := 8               # combat units before launching an attack
const ATTACK_KEEP := 3              # leave this many units home as garrison
const BUILD_REPEAT_S := 3.0         # seconds between build-queue pokes

var sim: Simulation
var faction: String               # the faction this AI directs
var enemy: String                 # the hostile faction
var hq_id: int = -1
var decision_timer: float = 0.0
var attack_timer: float = 0.0
var build_order: Array = []       # structureDefIds to build in sequence
var _staging: Vector2 = Vector2.ZERO   # rally/assembly point near base

## Known enemy structure positions this AI has *scouted* (legitimate info only).
var known_enemy_positions: Array[Vector2] = []

func _init(sim_: Simulation, faction_: String, enemy_: String) -> void:
	sim = sim_
	faction = faction_
	enemy = enemy_
	_reset_build_plan()

## Per-faction plans (role-equivalent content IDs differ per faction — never assume VC).
const BUILD_PLANS := {
	"VC": ["VC-B02", "VC-B03", "VC-B07", "VC-B02", "VC-B03", "VC-B08"],
	"FC": ["FC-B02", "FC-B03", "FC-B04", "FC-B02", "FC-B03", "FC-B05"],
}
const UNIT_PLANS := {
	"VC": { "inf": "VC-U01", "veh": "VC-U06", "heavy": "VC-U12" },
	"FC": { "inf": "FC-U01", "veh": "FC-U06", "heavy": "FC-U07" },
}
const TURRET_IDS := { "VC": "VC-D02", "FC": "FC-D02" }

func _reset_build_plan() -> void:
	build_order = (BUILD_PLANS.get(faction, BUILD_PLANS["FC"]) as Array).duplicate()

## Called each sim tick.
func update(dt: float) -> void:
	decision_timer += dt
	attack_timer += dt
	if hq_id < 0:
		hq_id = _find_hq()
		if hq_id < 0:
			return
		_staging = sim.entities[hq_id].position
	# Observe enemy structures we can currently see (fog-aware scouting).
	_observe_enemy()
	# Managers, throttled so we don't issue redundant orders every tick.
	if decision_timer >= 0.5:
		decision_timer = 0.0
		_scout_decision()
		_defense_decision()
		_build_decision()
		_production_decision()
	if attack_timer >= 3.0 and _army_size() >= ARMY_TARGET:
		attack_timer = 0.0
		_launch_attack()
	# Keep a home garrison.
	_defend_home()

# ---- Queries (legitimate sim state only) ----
func _find_hq() -> int:
	for e in sim.entities.values():
		if e.kind == "structure" and e.faction_id == faction:
			var d: Dictionary = e.def_data
			if d.get("class", "") == "HQ" and (e.construction == null or e.construction.is_built()):
				return e.id
	return -1

func _count_structures(cls: String) -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "structure" and e.faction_id == faction and e.alive:
			if e.def_data.get("class", "") == cls and (e.construction == null or e.construction.is_built()):
				n += 1
	return n

func _count_units_with_weapons() -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive:
			if e.weapon != null or (e.def_data.has("weaponSlots") and e.def_data["weaponSlots"].size() > 0):
				n += 1
	return n

func _army_size() -> int:
	return _count_units_with_weapons()

func _production_structures() -> Array:
	var out: Array = []
	for e in sim.entities.values():
		if e.kind == "structure" and e.faction_id == faction and e.alive and e.production != null:
			if e.construction == null or e.construction.is_built():
				out.append(e.id)
	return out

func _credits() -> float:
	return sim.get_resources(faction).get("credits", 0.0)

# ---- Managers ----
func _scout_decision() -> void:
	# If we have >2 combat units and no known enemy base, push a scout-ish attack
	# toward a corner/unknown region. Also update staging near HQ.
	_observe_enemy()

func _defense_decision() -> void:
	# Build a defense turret or wall if enemy has been seen near our base.
	var hpos: Vector2 = sim.entities[hq_id].position
	for p in known_enemy_positions:
		if p.distance_to(hpos) < 520.0:
			if _count_structures("Defense") < 1:
				_build_near_hq(String(TURRET_IDS.get(faction, "FC-D02")))
			return

func _build_decision() -> void:
	if build_order.is_empty():
		return
	var next: String = build_order[0]
	var def = sim.registry.get_structure(next)
	if def.is_empty():
		build_order.pop_front()
		return
	var cls: String = def.get("class", "")
	var target := _target_for(cls)
	if _count_structures(cls) >= target:
		build_order.pop_front()
		return
	if _credits() < def.get("costCredits", 0.0) * 1.05:
		return  # wait to afford
	# Place a structure in a free cell near the HQ.
	var pos := _find_free_near_hq(next)
	if pos.x < 0.0:
		return
	if _try_build(next, pos):
		build_order.pop_front()

func _target_for(cls: String) -> int:
	if cls == "Economy":
		return ECO_TARGET
	if cls == "Power":
		return POWER_TARGET
	if cls == "Infantry":
		return PROD_INFANTRY
	if cls == "Vehicle":
		return PROD_VEHICLE
	if cls == "Defense":
		return 1
	return 1

func _production_decision() -> void:
	var prods := _production_structures()
	if prods.is_empty():
		return
	# Which unit does each production structure build? Infantry -> rifle/maker, Vehicle -> heavy.
	var want_unit := _choose_unit()
	if want_unit == "":
		return
	var def = sim.registry.get_unit(want_unit)
	if def.is_empty():
		return
	var cost: float = def.get("costCredits", 0.0)
	for pid in prods:
		var e: Entity = sim.entities.get(pid)
		if e == null or e.production == null:
			continue
		if e.production.queue_size() >= PROD_QUEUE_MAX:
			continue
		var class_ok := _production_matches(e, want_unit)
		if not class_ok:
			continue
		if _credits() < cost:
			continue
		sim.run_commands(hq_id, [{ "type": "TRAIN", "entityIds": [pid], "unitDefId": want_unit }])
		return  # one train order per poke

const PROD_QUEUE_MAX := 4

## A structure's class must match the unit category (Barracks/Infantry trains infantry,
## MotorPool/Vehicle trains vehicles).
func _production_matches(structure: Entity, unit_id: String) -> bool:
	var cls: String = structure.def_data.get("class", "")
	var u = sim.registry.get_unit(unit_id)
	var armor: String = u.get("armorClass", "")
	if cls == "Infantry":
		return armor == "Infantry" or armor == "HeavyInfantry" or armor == "Cavalry" or armor == "Support"
	if cls == "Vehicle":
		return armor == "Light" or armor == "Medium" or armor == "Heavy"
	return false

func _choose_unit() -> String:
	# Simple army composition: infantry up to a mix, then vehicles, then heavies.
	var plan: Dictionary = UNIT_PLANS.get(faction, UNIT_PLANS["FC"])
	var inf := _count_armor("Infantry") + _count_armor("HeavyInfantry")
	var veh := _count_armor("Light") + _count_armor("Medium") + _count_armor("Heavy")
	if inf < 4:
		return String(plan["inf"])
	if veh < 2:
		return String(plan["veh"])
	return String(plan["heavy"])

func _count_armor(armor: String) -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive:
			if e.def_data.get("armorClass", "") == armor:
				n += 1
	return n

func _count_unit(unit_id: String) -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive and e.def_id == unit_id:
			n += 1
	return n

# ---- Attack / defense ----.
func _launch_attack() -> void:
	var army: Array = []
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive and e.weapon != null:
			army.append(e.id)
	if army.size() < ATTACK_KEEP + 1:
		return
	var assault: Array = []
	for i in range(army.size() - ATTACK_KEEP):
		assault.append(army[i])
	if assault.is_empty():
		return
	var target := _best_attack_target()
	if target.x < 0.0:
		return
	sim.run_commands(hq_id, [{ "type": "ATTACK_MOVE", "entityIds": assault, "targetPosition": target }])

func _best_attack_target() -> Vector2:
	# Prefer a known (scouted) enemy structure; else push toward a distant unexplored zone.
	if known_enemy_positions.size() > 0:
		return known_enemy_positions[0]
	# No scouted enemy: attack toward the far corner (odd diagonal from our base).
	var hpos: Vector2 = sim.entities[hq_id].position
	var world_size := Vector2(50, 50) * NavGrid.CELL
	var diag := Vector2.ZERO
	if hpos.x < world_size.x * 0.5:
		diag.x = world_size.x * 0.72
	else:
		diag.x = world_size.x * 0.28
	if hpos.y < world_size.y * 0.5:
		diag.y = world_size.y * 0.72
	else:
		diag.y = world_size.y * 0.28
	return diag

func _defend_home() -> void:
	# Keep a few units near the HQ (home garrison).
	if _army_size() <= ATTACK_KEEP:
		return
	var home_units: Array = []
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive and e.weapon != null:
			if e.position.distance_to(sim.entities[hq_id].position) > 600.0:
				home_units.append(e.id)
	if home_units.size() <= ATTACK_KEEP:
		return
	var ids: Array = []
	for i in range(ATTACK_KEEP):
		ids.append(home_units[i])
	sim.run_commands(hq_id, [{ "type": "MOVE", "entityIds": ids, "targetPosition": _staging }])

# ---- Placement / build helpers ----
func _build_near_hq(structureDefId: String) -> void:
	var pos := _find_free_near_hq(structureDefId)
	if pos.x >= 0.0:
		_try_build(structureDefId, pos)

func _try_build(structureDefId: String, pos: Vector2) -> bool:
	sim.run_commands(hq_id, [{ "type": "BUILD", "structureDefId": structureDefId, "position": pos, "faction": faction }])
	return true

func _find_free_near_hq(structureDefId: String) -> Vector2:
	var def = sim.registry.get_structure(structureDefId)
	var fp: Array = def.get("footprint", [1, 1])
	var w: int = fp[0] if fp.size() > 0 else 1
	var h: int = fp[1] if fp.size() > 1 else 1
	var hpos: Vector2 = sim.entities[hq_id].position
	var radius := 7
	for r in range(1, radius):
		var step := NavGrid.CELL
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(abs(dx), abs(dy)) != r:
					continue
				var cand: Vector2 = hpos + Vector2(dx, dy) * step
				if _can_place(cand, w, h):
					return cand
	return Vector2(-1.0, -1.0)

func _can_place(pos: Vector2, w: int, h: int) -> bool:
	var c: Vector2i = sim.grid_map.world_to_cell(pos.x, pos.y)
	for dy in range(h):
		for dx in range(w):
			var cx := c.x - w / 2 + dx
			var cy := c.y - h / 2 + dy
			if not sim.grid_map.in_bounds(cx, cy):
				return false
			if sim.grid_map.is_blocked(cx, cy):
				return false
	return true

# ---- Fog-aware scouting: only record enemy structures we can actually see. ----
func _observe_enemy() -> void:
	var seen := false
	for e in sim.entities.values():
		if e.kind != "structure" or e.faction_id != enemy or not e.alive:
			continue
		if sim.fog_sys.is_visible(faction, e.position):
			if not known_enemy_positions.has(e.position):
				known_enemy_positions.append(e.position)
			seen = true
	# Keep the list bounded to the nearest few.
	if known_enemy_positions.size() > 6:
		known_enemy_positions.sort_custom(func(a, b): return a.distance_to(sim.entities[hq_id].position) < b.distance_to(sim.entities[hq_id].position))
		known_enemy_positions.resize(6)
