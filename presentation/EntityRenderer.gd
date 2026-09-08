extends Node2D
class_name EntityRenderer
## Renders sim entities as colored shapes (faction-colored), with health bars and
## selection rings. Reads the authoritative sim state each frame (presentation-only).

var sim: Simulation
var rts_cam: RTSCamera

const FC_COLORS := {
	"VC": Color(0.0, 0.82, 1.0),       # Vibe Coder (00d1ff)
	"FC": Color(0.95, 0.75, 0.15),     # Federal Command (amber)
}

func _init(simulation: Simulation, cam: RTSCamera) -> void:
	sim = simulation
	rts_cam = cam

func _draw() -> void:
	if sim == null:
		return
	var cam_rect := _visible_world_rect()
	for e in sim.entities.values():
		if e.position.x < cam_rect.position.x or e.position.x > cam_rect.end.x:
			continue
		if e.position.y < cam_rect.position.y or e.position.y > cam_rect.end.y:
			continue
		if e.kind == "structure":
			_draw_structure(e)
		elif e.kind == "unit":
			_draw_unit(e, cam_rect)

func _draw_structure(e: Entity) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	# Structure footprint (square), faction-colored with a roof accent.
	var half := 28.0
	draw_rect(Rect2(e.position.x - half, e.position.y - half, half * 2.0, half * 2.0), col.darkened(0.45))
	draw_rect(Rect2(e.position.x - half, e.position.y - half, half * 2.0, half * 2.0), col, false, 3.0)
	# Roof accent (inner)
	draw_rect(Rect2(e.position.x - half * 0.6, e.position.y - half * 0.6, half * 1.2, half * 1.2), col.darkened(0.15))
	if e.health != null:
		_draw_health(e.position, e.health.current / e.health.max_health)
	if sim.selected_ids.has(e.id):
		draw_arc(e.position, half + 6.0, 0, TAU, 24, Color(0.0, 1.0, 0.4), 2.0)

func _draw_unit(e: Entity, cam_rect: Rect2) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	# Body
	draw_circle(e.position, 12.0, col)
	draw_arc(e.position, 12.0, 0, TAU, 24, col.darkened(0.4), 1.5)
	# Facing / weapon nose
	var facing := _facing_for(e)
	draw_line(e.position, e.position + facing * 16.0, col.lightened(0.35), 2.0)
	# Health bar (always shown for units)
	if e.health != null:
		_draw_health(e.position, e.health.current / e.health.max_health)
	# Selection ring
	if sim.selected_ids.has(e.id):
		draw_arc(e.position, 16.0, 0, TAU, 24, Color(0.0, 1.0, 0.4), 2.0)

func _draw_health(pos: Vector2, pct: float) -> void:
	var w := 24.0
	var y := pos.y - 20.0
	draw_rect(Rect2(pos.x - w * 0.5, y, w, 4.0), Color(0.1, 0.1, 0.1))
	var col := Color(0.2, 0.9, 0.3) if pct > 0.5 else (Color(0.9, 0.8, 0.2) if pct > 0.25 else Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(pos.x - w * 0.5, y, w * pct, 4.0), col)

func _facing_for(e: Entity) -> Vector2:
	if e.movement != null and not e.movement.facing.is_zero_approx():
		return e.movement.facing
	return Vector2.RIGHT

func _visible_world_rect() -> Rect2:
	if rts_cam == null:
		return Rect2(Vector2.ZERO, Vector2(10000, 10000))
	var vp := get_viewport_rect().size
	var tl := rts_cam.screen_to_world(Vector2.ZERO)
	return Rect2(tl, vp / rts_cam.zoom)
