extends Node2D
class_name EntityRenderer
## Renders sim entities as colored shapes (faction-colored), with health bars and
## selection rings. Reads the authoritative sim state each frame (presentation-only).

var sim: Simulation
var rts_cam: RTSCamera
var fog_sys: FogOfWarSystem = null
var player_faction: String = "VC"

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
		if not e.alive:
			continue   # garrisoned occupants are hidden; skip them
		if e.position.x < cam_rect.position.x or e.position.x > cam_rect.end.x:
			continue
		if e.position.y < cam_rect.position.y or e.position.y > cam_rect.end.y:
			continue
		# Fog: structures persist as silhouettes through explored fog; units vanish
		# unless currently visible to the player (§5.6).
		if fog_sys != null and e.faction_id != player_faction:
			var vis := fog_sys.is_visible(player_faction, e.position)
			if e.kind == "unit" and not vis:
				continue
			if e.kind == "structure" and fog_sys.state_at(player_faction, e.position) == 0:
				continue
		if e.kind == "structure":
			_draw_structure(e)
		elif e.kind == "unit":
			_draw_unit(e, cam_rect)

func _draw_structure(e: Entity) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	var tex := SpriteAtlas.texture(e.def_id)
	if tex != null:
		# faction-tint the structure sprite, draw centered on footprint
		var box := _scaled_sprite_box(e, tex, 60.0)
		var tint := col.darkened(0.35).lerp(Color.WHITE, 0.2)
		draw_texture_rect(tex, box, false, tint)
	else:
		var half := 28.0
		draw_rect(Rect2(e.position.x - half, e.position.y - half, half * 2.0, half * 2.0), col.darkened(0.45))
		draw_rect(Rect2(e.position.x - half, e.position.y - half, half * 2.0, half * 2.0), col, false, 3.0)
	if e.health != null:
		_draw_health(e.position, e.health.current / e.health.max_health)
	if sim.selected_ids.has(e.id):
		var half := 28.0
		draw_arc(e.position, half + 6.0, 0, TAU, 24, Color(0.0, 1.0, 0.4), 2.0)

func _draw_unit(e: Entity, cam_rect: Rect2) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	var tex := SpriteAtlas.texture(e.def_id)
	if tex != null:
		var angle := _facing_angle(e)
		var box := _scaled_sprite_box(e, tex, 42.0)
		var draw_pos := box.get_center()
		var tint := Color.WHITE
		# Character/vehicle tint: faction hue washed over a mostly-neutral sprite.
		if SpriteAtlas.is_humanoid(e.def_id):
			tint = Color(1.0, 1.0, 1.0).lerp(col, 0.55)
		# Rotation: sprites face up (-Y). Godot rotation 0 = up; angle from facing.
		draw_set_transform(draw_pos, angle, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-box.size * 0.5, box.size), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(e.position, 12.0, col)
		draw_arc(e.position, 12.0, 0, TAU, 24, col.darkened(0.4), 1.5)
	if e.health != null:
		_draw_health(e.position, e.health.current / e.health.max_health)
	if sim.selected_ids.has(e.id):
		draw_arc(e.position, 16.0, 0, TAU, 24, Color(0.0, 1.0, 0.4), 2.0)

## World-space rect to draw a sprite at its entity position, scaled so the max
## dimension is `target_px` world units (keeps unit readable at cell=20).
func _scaled_sprite_box(e: Entity, tex: Texture2D, target_px: float) -> Rect2:
	var sz := tex.get_size()
	var scale := 1.0
	if sz.x > 0 and sz.y > 0:
		scale = target_px / max(sz.x, sz.y)
	var w := sz.x * scale
	var h := sz.y * scale
	return Rect2(e.position - Vector2(w, h) * 0.5, Vector2(w, h))

func _facing_angle(e: Entity) -> float:
	if e.movement != null and not e.movement.facing.is_zero_approx():
		# sprites face up (-Y) == +90deg in Godot's rotate-down convention.
		# facing is a world direction; rotation = facing.angle() + PI/2.
		return e.movement.facing.angle() + PI * 0.5
	return 0.0

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
