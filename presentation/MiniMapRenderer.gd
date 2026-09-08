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

const COL_UNEXPLORED := Color(0.03, 0.035, 0.04)
const COL_EXPLORED := Color(0.10, 0.12, 0.11)
const COL_TERRAIN := Color(0.20, 0.22, 0.18)
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

func _draw() -> void:
	if sim == null or fog_sys == null:
		return
	var vp := get_viewport_rect().size
	var origin := Vector2(vp.x - MAP_SIZE - MARGIN, vp.y - MAP_SIZE - MARGIN)
	var rect := Rect2(origin, Vector2(MAP_SIZE, MAP_SIZE))

	# Fog + terrain background (one pixel rect per cell).
	var gw := fog_sys.grid_width()
	var gh := fog_sys.grid_height()
	var cell := fog_sys.cell_size()
	var xscale := MAP_SIZE / (gw * cell)
	var yscale := MAP_SIZE / (gh * cell)
	var bytes := fog_sys.state_bytes(player_faction)
	for y in range(gh):
		for x in range(gw):
			var st: int = bytes[y * gw + x]
			var col := COL_TERRAIN
			if st == 0:
				col = COL_UNEXPLORED
			elif st == 1:
				col = COL_EXPLORED
			draw_rect(Rect2(origin.x + x * xscale, origin.y + y * yscale, xscale + 0.5, yscale + 0.5), col)

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
