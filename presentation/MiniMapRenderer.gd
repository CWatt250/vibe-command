extends Node2D
class_name MiniMapRenderer
## MiniMapRenderer — screen-space minimap in the bottom-right corner (§5.6 / M1 gate).
## Shows the player faction's fog (unexplored=black, explored=dim, visible=terrain),
## live unit dots (faction-colored), and a box for the current camera viewport.
## Reads the authoritative sim + fog_sys; pure presentation.
## p4-02: left-click / left-drag jumps the camera, right-click orders a MOVE for the
## current selection. Handled in _input (before GUI and every _unhandled_input) so the
## world's drag-select never starts on a minimap click.

signal orders_issued(orders: Array)
var sim: Simulation
var fog_sys: FogOfWarSystem
var player_faction: String = "VC"
var rts_cam: RTSCamera

const MAP_SIZE := 220.0
const MARGIN := 16.0

const COL_TERRAIN := Color(0.28, 0.30, 0.26)   # match MapRenderer so the silhouette is honest
const COL_STREET := Color(0.36, 0.34, 0.28)
const COL_BLOCK := Color(0.14, 0.15, 0.14)

var fog_texture: Texture2D = null          # FogRenderer.texture, set by Game.gd
var _terrain_tex: ImageTexture = null      # built lazily once the nav grid exists
var _drag_jump: bool = false               # left button held after a press on the minimap
const COL_BORDER := Color(0.5, 0.5, 0.45)
const COL_CAM_BOX := Color(0.9, 0.9, 0.8, 0.85)

const FC_COLORS := {
	"VC": Color(0.0, 0.82, 1.0),
	"FC": Color(0.95, 0.75, 0.15),
}

func _init(_sim: Simulation, fog: FogOfWarSystem, faction: String, cam: RTSCamera) -> void:
	sim = _sim
	fog_sys = fog
	player_faction = faction
	rts_cam = cam
	# Draw above everything (Control-free, plain Node2D in screen space).
	z_index = 100

## One texel per cell from NavGrid.render_type(): open / street / pad (occupancy included).
func _build_terrain_texture(gw: int, gh: int) -> void:
	if sim.grid_map == null or sim.grid_map.land_types.is_empty():
		return
	var img := Image.create_empty(gw, gh, false, Image.FORMAT_RGBA8)
	for y in range(gh):
		for x in range(gw):
			var lt: int = sim.grid_map.render_type(x, y)
			var col := COL_TERRAIN
			if lt == 1:
				col = COL_STREET
			elif lt >= 2:
				col = COL_BLOCK
			img.set_pixel(x, y, col)
	_terrain_tex = ImageTexture.create_from_image(img)

# --- p4-02: screen<->world mapping. One source of truth for _draw, the hit-test and input. ---

## Screen-space rect the minimap occupies: MAP_SIZE square, MARGIN in from the bottom-right.
func minimap_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2(vp.x - MAP_SIZE - MARGIN, vp.y - MAP_SIZE - MARGIN), Vector2(MAP_SIZE, MAP_SIZE))

## World extent the minimap covers (grid cells x cell size), from the fog system's grid.
func world_size() -> Vector2:
	return Vector2(fog_sys.grid_width(), fog_sys.grid_height()) * fog_sys.cell_size()

## True when a screen point lands on the minimap (Rect2.has_point: top/left edges inclusive,
## bottom/right exclusive).
func contains_screen(screen_pos: Vector2) -> bool:
	return minimap_rect().has_point(screen_pos)

## Screen point -> world point. Pure affine; not clamped (a drag can leave the rect).
func minimap_to_world(screen_pos: Vector2) -> Vector2:
	var r := minimap_rect()
	return (screen_pos - r.position) / r.size * world_size()

## World point -> screen point on the minimap. Inverse of minimap_to_world.
func world_to_minimap(world_pos: Vector2) -> Vector2:
	var r := minimap_rect()
	return r.position + world_pos / world_size() * r.size

## Left click / drag: centre the camera on the world point under the cursor.
func jump_to_screen(screen_pos: Vector2) -> void:
	if rts_cam == null:
		return
	rts_cam.center_on(minimap_to_world(screen_pos))
	queue_redraw()

## Right click: MOVE the current selection to the world point under the cursor.
## Same command dict SelectionInput._issue_context_order builds for a ground click.
func order_move_at(screen_pos: Vector2) -> void:
	var ids: Array = sim.selected_ids
	if ids.is_empty():
		return
	orders_issued.emit([{"type": "MOVE", "entityIds": ids, "targetPosition": minimap_to_world(screen_pos)}])

## _input (not _unhandled_input): runs before the GUI pass and before SelectionInput /
## RTSCamera see the event, regardless of tree order. Anything that lands on the minimap
## is consumed here so no drag-select box starts under it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and contains_screen(event.position):
				_drag_jump = true
				jump_to_screen(event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _drag_jump:
				# Eat the release too: SelectionInput._finish_drag runs on ANY left release.
				_drag_jump = false
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and contains_screen(event.position):
			order_move_at(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_jump:
		jump_to_screen(event.position)   # keeps following even if the cursor leaves the rect
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if sim == null or fog_sys == null:
		return
	var rect := minimap_rect()

	# Terrain silhouette (built once from the nav grid's land types), then the shared
	# fog texture over it — same authority as the world overlay.
	var gw := fog_sys.grid_width()
	var gh := fog_sys.grid_height()
	if _terrain_tex == null:
		_build_terrain_texture(gw, gh)
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, rect, false)
	else:
		draw_rect(rect, COL_TERRAIN)
	if fog_texture != null:
		draw_texture_rect(fog_texture, rect, false)

	# Border
	draw_rect(rect, COL_BORDER, false, 2.0)

	# Live unit dots (only those visible to the player faction).
	for e in sim.entities.values():
		if not e.alive:
			continue
		if fog_sys != null and e.faction_id != player_faction and not fog_sys.is_visible(player_faction, e.position):
			continue
		var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
		var r: float = 2.5 if e.kind == "unit" else 4.0
		draw_circle(world_to_minimap(e.position), r, col)

	# Camera viewport box.
	if rts_cam != null:
		var cam_rect := _camera_world_rect()
		var tl := world_to_minimap(cam_rect.position)
		var br := world_to_minimap(cam_rect.end)
		draw_rect(Rect2(tl, br - tl), COL_CAM_BOX, false, 1.5)

func _camera_world_rect() -> Rect2:
	if rts_cam == null:
		return Rect2(Vector2.ZERO, Vector2(2000, 2000))
	var vp := get_viewport_rect().size
	var tl := rts_cam.screen_to_world(Vector2.ZERO)
	return Rect2(tl, vp / rts_cam.zoom)
