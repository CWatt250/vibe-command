extends Node2D
class_name MiniMapRenderer
## MiniMapRenderer — screen-space minimap in the bottom-right corner (§5.6 / M1 gate).
## Shows the player faction's fog (unexplored=black, explored=dim, visible=terrain),
## live unit dots (faction-colored), and a box for the current camera viewport.
## Reads the authoritative sim + fog_sys; pure presentation.

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

func _draw() -> void:
	if sim == null or fog_sys == null:
		return
	var vp := get_viewport_rect().size
	var origin := Vector2(vp.x - MAP_SIZE - MARGIN, vp.y - MAP_SIZE - MARGIN)
	var rect := Rect2(origin, Vector2(MAP_SIZE, MAP_SIZE))

	# Terrain silhouette (built once from the nav grid's land types), then the shared
	# fog texture over it — same authority as the world overlay.
	var gw := fog_sys.grid_width()
	var gh := fog_sys.grid_height()
	var cell := fog_sys.cell_size()
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
		var px: float = origin.x + (e.position.x / (gw * cell)) * MAP_SIZE
		var py: float = origin.y + (e.position.y / (gh * cell)) * MAP_SIZE
		var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
		var r: float = 2.5 if e.kind == "unit" else 4.0
		draw_circle(Vector2(px, py), r, col)

	# Camera viewport box.
	if rts_cam != null:
		var cam_rect := _camera_world_rect()
		var bx := origin.x + (cam_rect.position.x / (gw * cell)) * MAP_SIZE
		var by := origin.y + (cam_rect.position.y / (gh * cell)) * MAP_SIZE
		var bw := (cam_rect.size.x / (gw * cell)) * MAP_SIZE
		var bh := (cam_rect.size.y / (gh * cell)) * MAP_SIZE
		draw_rect(Rect2(bx, by, bw, bh), COL_CAM_BOX, false, 1.5)

func _camera_world_rect() -> Rect2:
	if rts_cam == null:
		return Rect2(Vector2.ZERO, Vector2(2000, 2000))
	var vp := get_viewport_rect().size
	var tl := rts_cam.screen_to_world(Vector2.ZERO)
	return Rect2(tl, vp / rts_cam.zoom)
