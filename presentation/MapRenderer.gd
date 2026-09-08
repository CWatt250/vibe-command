extends Node2D
class_name MapRenderer
## Renders the industrial skirmish map: terrain grid + spawn markers + building footprints.
## Pure presentation — reads opaque terrain from a shared land-type grid (Blueprint §3.6).

var grid: NavGrid
var land_grid: Array = []     # Array[Array[int]] land types (0 = open, 1 = building footprint, 2 = rubble/blocked)
var cell: float = 20.0
var world_w: int = 0
var world_h: int = 0

const COL_OPEN := Color(0.28, 0.30, 0.26)
const COL_STREET := Color(0.36, 0.34, 0.28)
const COL_BLOCK := Color(0.16, 0.17, 0.16)

func setup(g: NavGrid, w: int, h: int, c: float) -> void:
	grid = g
	world_w = w
	world_h = h
	cell = c
	land_grid = grid.land_types

func _draw() -> void:
	var vp_rect := _visible_world_rect()
	var x0: int = maxi(0, int(vp_rect.position.x / cell))
	var y0: int = maxi(0, int(vp_rect.position.y / cell))
	var x1: int = mini(world_w - 1, int((vp_rect.end.x) / cell))
	var y1: int = mini(world_h - 1, int((vp_rect.end.y) / cell))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var lt: int = land_grid[y][x]
			var col := COL_OPEN
			if lt == 1: col = COL_STREET
			elif lt >= 2: col = COL_BLOCK
			draw_rect(Rect2(x * cell, y * cell, cell, cell), col)
	# Border
	draw_rect(Rect2(0, 0, world_w * cell, world_h * cell), Color(0.4, 0.2, 0.1), false, 2.0)

func _visible_world_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(0, 0, world_w * cell, world_h * cell)
	var vp := get_viewport_rect().size
	var topleft: Vector2 = cam.screen_to_world(Vector2.ZERO)
	return Rect2(topleft, vp / cam.zoom)
