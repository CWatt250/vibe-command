extends Node
class_name GameEvents
## GameEvents — global signal bus. Simulation systems emit; presentation observes.
## This decouples the pure sim from Godot visuals (Blueprint §2: simulation/presentation split).

signal game_tick(tick: int, dt: float)
signal entity_created(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal entity_destroyed(entity_id: int, pos: Vector2)
signal entity_selected(entity_ids: Array[int])
signal entity_command(entity_ids: Array[int], command: Dictionary)
signal resource_changed(faction: String, resource_id: String, amount: float)
signal structure_placed(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal structure_order(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal structure_destroyed(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal production_queued(entity_id: int, unit_id: String, cost: float)
signal production_progress(entity_id: int, def_id: String, progress: float)
signal building_constructed(entity_id: int, def_id: String, faction: String)
signal unit_spawned(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal combat_occurred(attacker_id: int, target_id: int, def_id: String, damage: float)
signal unit_died(entity_id: int, def_id: String, faction: String, pos: Vector2)
signal match_over(loser: String, winner: String)
signal log(msg: String)

func emit_log(msg: String) -> void:
	log.emit(msg)
