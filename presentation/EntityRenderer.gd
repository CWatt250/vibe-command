extends Node2D
class_name EntityRenderer
## Renders sim entities as colored shapes (faction-colored), with health bars and
## selection rings. Reads the authoritative sim state each frame (presentation-only).

var sim: Simulation
var rts_cam: RTSCamera
var fog_sys: FogOfWarSystem = null
var player_faction: String = "VC"
var fx: FxRenderer = null            # hit-flash source (set by Game.gd)

const HIT_FLASH := Color(1.0, 1.0, 1.0, 0.65)

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

# --- Readability (visual-roadmap V1) ---
# Unit sprite size (max dimension, world px) by armor class. Infantry stays small so
# armies read as armies; vehicles and air get the room they need to be identified.
const UNIT_PX := {
	"Infantry": 30.0, "HeavyInfantry": 36.0,
	"Light": 46.0, "Medium": 56.0, "Heavy": 68.0,
	"AirLight": 40.0, "AirHeavy": 64.0,
}
const UNIT_PX_DEFAULT := 46.0
const STRUCTURE_FILL := 0.94          # of the footprint rect; leaves a sliver of pad visible
const SHADOW_GROUND := Color(0, 0, 0, 0.42)
const SHADOW_AIR := Color(0, 0, 0, 0.22)
const SEL_COLOR := Color(0.0, 1.0, 0.4)

func _draw_structure(e: Entity) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	var fp := _footprint_rect(e)
	var center := fp.get_center()
	# Contact shadow: the footprint, nudged toward lower-right (sun upper-left).
	draw_rect(Rect2(fp.position + Vector2(3, 4), fp.size), SHADOW_GROUND)
	var tex := SpriteAtlas.texture(e.def_id)
	if tex != null:
		var region := SpriteAtlas.region(e.def_id)
		# Width fits the footprint; height follows the art. A 3/4-view building stands on
		# its pad and rises above it, a top-down one just fills it (aspect ≈ 1).
		var w: float = fp.size.x * STRUCTURE_FILL * SpriteAtlas.scale(e.def_id)
		var h: float = w * region.size.y / maxf(region.size.x, 1.0)
		var box := Rect2(Vector2(center.x - w * 0.5, fp.end.y - fp.size.y * (1.0 - STRUCTURE_FILL) * 0.5 - h), Vector2(w, h))
		var tint := Color.WHITE.lerp(col, SpriteAtlas.tint(e.def_id, 0.22))
		if e.construction != null and not e.construction.is_built():
			tint.a = 0.45 + 0.55 * e.construction.fraction()   # build site fades in
		draw_texture_rect_region(tex, box, region, tint)
	else:
		draw_rect(fp, col.darkened(0.45))
		draw_rect(fp, col, false, 3.0)
	if fx != null and fx.flash_left(e.id) > 0.0:
		draw_rect(fp.grow(-fp.size.x * 0.06), HIT_FLASH)
	if _show_health(e):
		_draw_health(Vector2(center.x, fp.position.y - 4.0), e.health.current / e.health.max_health, fp.size.x * 0.8)
	if sim.selected_ids.has(e.id):
		_draw_brackets(fp.grow(3.0))

func _draw_unit(e: Entity, cam_rect: Rect2) -> void:
	var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
	var size_px: float = UNIT_PX.get(e.def_data.get("armorClass", ""), UNIT_PX_DEFAULT) * SpriteAtlas.scale(e.def_id)
	# Contact shadow: tight and dark on the ground, wide and faint for airborne (reads as hover).
	var shadow_off := Vector2(6, 10) if e.is_airborne else Vector2(2, 3)
	var shadow_col := SHADOW_AIR if e.is_airborne else SHADOW_GROUND
	draw_set_transform(e.position + shadow_off, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, size_px * 0.42, shadow_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex := SpriteAtlas.texture(e.def_id)
	var facings := SpriteAtlas.facings(e.def_id)
	if tex != null and facings > 0:
		# Pre-rendered 3/4-view strip: pick the frame for the heading, never rotate.
		# Frame 0 faces up (-Y); frames advance clockwise on screen, which in Godot's
		# y-down convention is increasing angle. Same law as tools/render_sprites.py.
		var a := _facing_angle(e) - PI * 0.5           # 0 when facing up
		var k := int(roundf(a / TAU * facings)) % facings
		if k < 0:
			k += facings
		var region := SpriteAtlas.facing_region(e.def_id, k)
		var box := _scaled_sprite_box(e, region.size, size_px)
		draw_texture_rect_region(tex, box, region, Color.WHITE)
	elif tex != null:
		var angle := _facing_angle(e)
		var region := SpriteAtlas.region(e.def_id)
		var box := _scaled_sprite_box(e, region.size, size_px)
		var draw_pos := box.get_center()
		var tint := Color.WHITE
		# Character/vehicle tint: faction hue washed over a mostly-neutral sprite.
		if SpriteAtlas.is_humanoid(e.def_id):
			tint = Color(1.0, 1.0, 1.0).lerp(col, 0.55)
		# Rotation: sprites face up (-Y). Godot rotation 0 = up; angle from facing.
		draw_set_transform(draw_pos, angle, Vector2.ONE)
		draw_texture_rect_region(tex, Rect2(-box.size * 0.5, box.size), region, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(e.position, size_px * 0.3, col)
		draw_arc(e.position, size_px * 0.3, 0, TAU, 24, col.darkened(0.4), 1.5)
	if fx != null and fx.flash_left(e.id) > 0.0:
		draw_circle(e.position, size_px * 0.45, HIT_FLASH)
	if _show_health(e):
		_draw_health(Vector2(e.position.x, e.position.y - size_px * 0.5 - 5.0), e.health.current / e.health.max_health, size_px * 0.8)
	if sim.selected_ids.has(e.id):
		draw_arc(e.position, size_px * 0.55, 0, TAU, 32, SEL_COLOR, 2.0)

## Health bars are noise at full HP. Show when selected, hurt, or Alt is held.
func _show_health(e: Entity) -> bool:
	if e.health == null:
		return false
	if sim.selected_ids.has(e.id) or Input.is_key_pressed(KEY_ALT):
		return true
	return e.health.current < e.health.max_health

## The structure's blocked cells in world space — same anchor-cell math as the sim
## (Simulation._block_footprint / PlacementGhost), so sprites sit on what they block.
## Even footprints are offset half a cell from e.position; this is where they really are.
func _footprint_rect(e: Entity) -> Rect2:
	var fp: Array = e.def_data.get("footprint", [1, 1])
	var w: int = int(fp[0]) if fp.size() > 0 else 1
	var h: int = int(fp[1]) if fp.size() > 1 else w
	var c: Vector2i = sim.grid_map.world_to_cell(e.position.x, e.position.y)
	return Rect2(Vector2(c.x - w / 2, c.y - h / 2) * NavGrid.CELL, Vector2(w, h) * NavGrid.CELL)

## C&C-style corner brackets around a selected structure.
func _draw_brackets(r: Rect2) -> void:
	var len := minf(r.size.x, r.size.y) * 0.25
	var corners := [
		[r.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
		[r.end, Vector2(-1, 0), Vector2(0, -1)],
	]
	for c in corners:
		draw_line(c[0], c[0] + c[1] * len, SEL_COLOR, 2.0)
		draw_line(c[0], c[0] + c[2] * len, SEL_COLOR, 2.0)

## World-space rect to draw a sprite of source size `sz` at its entity position,
## scaled so the max dimension is `target_px` world units.
func _scaled_sprite_box(e: Entity, sz: Vector2, target_px: float) -> Rect2:
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

## Bar centred on pos.x with its top edge at pos.y; width scales with the entity.
func _draw_health(pos: Vector2, pct: float, w: float = 24.0) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y, w, 4.0), Color(0.1, 0.1, 0.1))
	var col := Color(0.2, 0.9, 0.3) if pct > 0.5 else (Color(0.9, 0.8, 0.2) if pct > 0.25 else Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(pos.x - w * 0.5, pos.y, w * pct, 4.0), col)

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
