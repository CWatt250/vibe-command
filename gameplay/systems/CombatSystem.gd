extends RefCounted
class_name CombatSystem
## CombatSystem — resolves targeting, firing, damage/armor, and death (Blueprint §3.5, §5).

const WeaponComponent := preload("res://gameplay/components/WeaponComponent.gd")

var sim: Simulation
var registry: ContentRegistry
var events: GameEvents

func _init(sim_: Simulation, registry_: ContentRegistry, events_: GameEvents) -> void:
	sim = sim_
	registry = registry_
	events = events_

func tick_all() -> void:
	for id in sim.entities.keys():
		var e: Entity = sim.entities.get(id)
		if e == null or not e.alive:
			continue
		# Repair structures heal friendly entities in radius (§5.7 repair).
		_apply_repair(e)
		# Only entities with a weapon shoot automatically.
		if e.weapon == null:
			continue
		var w: WeaponComponent = e.weapon
		# 1. If no target, acquire one (automatic turret targeting).
		var target_id: int = w.current_target_id
		if target_id < 0 or not _valid_target(e, target_id):
			target_id = _acquire_target(e)
			w.current_target_id = target_id
		if target_id < 0:
			continue
		# 2. If target out of range and this is a unit with movement, chase a little (attack-move leash handled by orders).
		var target: Entity = sim.entities.get(target_id)
		if target == null or not target.alive:
			w.current_target_id = -1
			continue
		# 2b. If the target is out of firing range, chase it (attack pursuit). Only re-path
		#     when not already moving, to avoid repathing every tick.
		if not w.target_in_range(target.position, e.position):
			if e.movement != null and not e.movement.is_moving() and not e.movement.reached_goal(e.position):
				_chase(e, target)
		# 3. Fire when in range and cooldown ready.
		if w.can_fire() and w.target_in_range(target.position, e.position):
			_resolve_fire(e, w, target)

func _apply_repair(structure: Entity) -> void:
	## A repair structure heals all friendly, damaged entities within repairRadius (§5.7).
	var r_radius: float = structure.def_data.get("repairRadius", 0.0)
	var r_per_sec: float = structure.def_data.get("repairPerSec", 0.0)
	if r_radius <= 0.0 or r_per_sec <= 0.0:
		return
	for id in sim.spatial.query_radius(structure.position, r_radius):
		var e: Entity = sim.entities.get(id)
		if e == null or not e.alive or e.faction_id != structure.faction_id:
			continue
		if e.health == null or e.health.is_full():
			continue
		if e == structure:
			continue
		e.health.heal(r_per_sec * sim.dt)

func _chase(e: Entity, target: Entity) -> void:
	# Path toward the target so the attacker closes to firing range.
	if sim.grid_map == null:
		return
	var dst := sim.grid_map.find_path(e.position, target.position, e.movement.path_layer == "air")
	if dst.size() > 0:
		e.movement.set_path(dst, target.position)

## Acquire the highest-scoring valid enemy target within acquisition radius.
func _acquire_target(e: Entity) -> int:
	var w: WeaponComponent = e.weapon
	var candidates := sim.spatial.query_radius(e.position, w.acquire_radius)
	var best_id := -1
	var best_score := -INF
	for cid in candidates:
		var cand: Entity = sim.entities.get(cid)
		if cand == null or not cand.alive or cand.faction_id == e.faction_id:
			continue
		if not _target_tag_valid(w, cand):
			continue
		var sc := _score_target(w, e, cand)
		if sc > best_score:
			best_score = sc
			best_id = cid
	return best_id

func _score_target(w: WeaponComponent, e: Entity, cand: Entity) -> float:
	var d: float = e.position.distance_to(cand.position)
	var score := maxf(0.0, w.acquire_radius - d)   # closer = higher
	var armor: String = cand.def_data.get("armorClass", "Infantry")
	if w.preferred_tags.has(armor) or (w.preferred_tags.has("infantry") and armor == "Infantry"):
		score += 200.0
	if w.preferred_tags.has("vehicle") and cand.kind == "unit" and cand.def_data.has("componentFlags") \
		and "Vehicle" in cand.def_data["componentFlags"]:
		score += 100.0
	if w.preferred_tags.has("structure") and cand.kind == "structure":
		score += 100.0
	return score

func _target_tag_valid(w: WeaponComponent, cand: Entity) -> bool:
	var armor: String = cand.def_data.get("armorClass", "Infantry")
	for tag in w.target_tags:
		if tag == "infantry" and (armor == "Infantry" or armor == "HeavyInfantry"):
			return true
		if tag == "vehicle" and cand.kind == "unit" and cand.def_data.has("componentFlags") \
			and "Vehicle" in cand.def_data["componentFlags"]:
			return true
		if tag == "air" and cand.is_airborne:
			return true
		if tag == "ground" and not cand.is_airborne:
			return true
		if tag == "structure" and cand.kind == "structure":
			return true
		if tag == "heavy" and (armor == "Heavy" or armor == "HeavyInfantry"):
			return true
		if tag == "light" and (armor == "Light" or armor == "AirLight"):
			return true
	return false

func _valid_target(e: Entity, target_id: int) -> bool:
	var t: Entity = sim.entities.get(target_id)
	if t == null or not t.alive or t.faction_id == e.faction_id:
		return false
	return _target_tag_valid(e.weapon, t)

# --- Fire resolution ---
func _resolve_fire(e: Entity, w: WeaponComponent, target: Entity) -> void:
	w.begin_cooldown()
	var mult := registry.armor_multiplier(w.damage_type, target.def_data.get("armorClass", "Infantry"))
	var dmg: float = w.base_damage * mult
	# Garrison fire proxy (§5.7): a garrisoned structure fires harder per occupant
	# (each infantry adds its weapon's base damage as a scaling proxy).
	var garrison_occupants: int = 0
	if e.garrison != null:
		garrison_occupants = e.garrison.occupant_count()
		if garrison_occupants > 0:
			dmg += w.base_damage * 0.5 * float(garrison_occupants)
	# Veteran damage multiplier (§5.9), sim-authoritative.
	if e.veterancy != null:
		dmg *= e.veterancy.damage_mult()
	# Damage contribution award: 1 XP per point of damage dealt.
	if e.veterancy != null:
		e.veterancy.add_xp(dmg)
	var died: bool = target.health.apply_damage(dmg)
	events.combat_occurred.emit(e.id, target.id, w.weapon_id, dmg)
	if w.splash_radius > 0.0:
		_apply_splash(e, w, target.position, target.faction_id)
	if died:
		# Kill award: flat XP bonus to the attacker.
		if e.veterancy != null:
			e.veterancy.add_xp(50.0)
		_sim_destroy(target)

func _apply_splash(e: Entity, w: WeaponComponent, center: Vector2, attacker_faction: String) -> void:
	# Splash arms down over radius: full at center, linear falloff.
	var near := sim.spatial.query_radius(center, w.splash_radius)
	for id in near:
		var t: Entity = sim.entities.get(id)
		if t == null or not t.alive or t.id == e.id:
			continue
		var dist: float = t.position.distance_to(center)
		var dmg: float = w.base_damage * maxf(0.0, 1.0 - dist / w.splash_radius)
		var mult := registry.armor_multiplier(w.damage_type, t.def_data.get("armorClass", "Infantry"))
		dmg *= mult
		var died: bool = t.health.apply_damage(dmg)
		if died:
			_sim_destroy(t)

func _sim_destroy(e: Entity) -> void:
	# Eject any garrisoned occupants before the structure is removed (§5.7) —
	# they retain health/veterancy and are respawned adjacent.
	if e.garrison != null and e.garrison.occupant_count() > 0:
		sim.ungarrison_units(e.id)
	# A destroyed unit removes itself from sim (structural destruction handled via base-destroy gate elsewhere).
	events.unit_died.emit(e.id, e.def_id, e.faction_id, e.position)
	sim.remove_entity(e.id)
