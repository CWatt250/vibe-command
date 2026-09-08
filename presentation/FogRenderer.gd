extends Node2D
class_name FogRenderer
## FogRenderer — draws the player faction's fog of war as a world-space overlay.
## Unexplored cells are fully black, explored/fogged cells are dimmed, visible cells
## are clear. Reads the same FogOfWarSystem state the sim owns (single authority).
## Sits above the map but below entities so only visible units appear.

var fog_sys: FogOfWarSystem
var player_faction: String = "VC"

const COL_UNEXPLORED := Color(0.0, 0.0, 0.0, 1.0)
const COL_EXPLORED := Color(0.0, 0.0, 0.0, 0.62)

func _init(fog: FogOfWarSystem, faction: String) -> void:
	fog_sys = fog
	player_faction = faction
	z_index = 5   # above map(z=0) below entities(z=6)

func _draw() -> void:
	if fog_sys == null:
		return
	var vp_rect := _visible_world_rect()
	var cell := fog_sys.cell_size()
	var x0: int = maxi(0, int(vp_rect.position.x / cell))
	var y0: int = maxi(0, int(vp_rect.position.y / cell))
	var x1: int = mini(fog_sys.grid_width() - 1, int(vp_rect.end.x / cell))
	var y1: int = mini(fog_sys.grid_height() - 1, int(vp_rect.end.y / cell))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var state := fog_sys.state_at(player_faction, Vector2((x + 0.5) * cell, (y + 0.5) * cell))
			if state == 0:
				draw_rect(Rect2(x * cell, y * cell, cell, cell), COL_UNEXPLORED)
			elif state == 1:
				draw_rect(Rect2(x * cell, y * cell, cell, cell), COL_EXPLORED)

func _visible_world_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(0, 0, fog_sys.grid_width() * fog_sys.cell_size(), fog_sys.grid_height() * fog_sys.cell_size())
	var vp := get_viewport_rect().size
	return Rect2(cam.screen_to_world(Vector2.ZERO), vp / cam.zoom)
