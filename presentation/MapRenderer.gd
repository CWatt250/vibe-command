extends Node2D
class_name MapRenderer
## Renders the skirmish map from the shared land-type grid (Blueprint §3.6):
## dirt with seeded variation, auto-tiled roads, concrete pads under anything blocked,
## and a seeded prop scatter (rocks / scrap / bushes / tire marks) on open cells.
## Pure presentation. Tiles come from tools/generate_terrain.py (assets/terrain/).

const MANIFEST_PATH := "res://assets/terrain/manifest.json"
const TERRAIN_DIR := "res://assets/terrain"
const PROP_DENSITY := 0.035        # fraction of open cells that get a prop
const PROP_SEED := 7               # fixed so screenshots are reproducible

var grid: NavGrid
var land_grid: Array = []     # Array[Array[int]] land types (0 = open, 1 = street, 2 = blocked)
var cell: float = 40.0
var world_w: int = 0
var world_h: int = 0

# Flat-colour fallback if the tile set is missing (keeps the old look, not a crash).
const COL_OPEN := Color(0.28, 0.30, 0.26)
const COL_STREET := Color(0.36, 0.34, 0.28)
const COL_BLOCK := Color(0.16, 0.17, 0.16)

var _tiles: Dictionary = {}          # name -> Texture2D
var _dirt: Array = []                # dirt variants
var _prop_names: Array = ["rock_0", "rock_1", "scrap_0", "scrap_1", "bush", "tiremarks"]
var _props: Dictionary = {}          # Vector2i cell -> prop name

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # tiles stay crisp when zoomed
	_load_tiles()

func setup(g: NavGrid, w: int, h: int, c: float) -> void:
	grid = g
	world_w = w
	world_h = h
	cell = c
	land_grid = grid.land_types
	_scatter_props()

func _load_tiles() -> void:
	var mf := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if mf == null:
		return
	var data: Variant = JSON.parse_string(mf.get_as_text())
	if not (data is Dictionary):
		return
	for key in data.keys():
		var tex := load(TERRAIN_DIR + "/" + String(data[key]))
		if tex is Texture2D:
			_tiles[key] = tex
	for i in range(8):
		if _tiles.has("dirt_%d" % i):
			_dirt.append(_tiles["dirt_%d" % i])

## Props only on open cells, chosen once from a fixed seed. Structures that go up
## later simply draw over them (pad + sprite), so no re-scatter is needed.
func _scatter_props() -> void:
	_props.clear()
	if _tiles.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	for y in range(world_h):
		for x in range(world_w):
			if land_grid[y][x] == 0 and rng.randf() < PROP_DENSITY:
				_props[Vector2i(x, y)] = _prop_names[rng.randi_range(0, _prop_names.size() - 1)]

func _draw() -> void:
	var vp_rect := _visible_world_rect()
	var x0: int = maxi(0, int(vp_rect.position.x / cell))
	var y0: int = maxi(0, int(vp_rect.position.y / cell))
	var x1: int = mini(world_w - 1, int((vp_rect.end.x) / cell))
	var y1: int = mini(world_h - 1, int((vp_rect.end.y) / cell))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var r := Rect2(x * cell, y * cell, cell, cell)
			var lt: int = grid.render_type(x, y)
			var tex := _tile_for(x, y, lt)
			if tex != null:
				draw_texture_rect(tex, r, false)
			else:
				draw_rect(r, COL_STREET if lt == 1 else (COL_BLOCK if lt >= 2 else COL_OPEN))
	# Props over the ground, under entities.
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var key := Vector2i(x, y)
			if _props.has(key) and land_grid[y][x] == 0:
				draw_texture_rect(_tiles[_props[key]], Rect2(x * cell, y * cell, cell, cell), false)
	# Border
	draw_rect(Rect2(0, 0, world_w * cell, world_h * cell), Color(0.4, 0.2, 0.1), false, 2.0)

func _tile_for(x: int, y: int, lt: int) -> Texture2D:
	if _tiles.is_empty():
		return null
	if lt >= 2:
		return _tiles.get("pad")
	if lt == 1:
		# Auto-tile by road neighbours: horizontal, vertical, or crossing.
		var h := _is_road(x - 1, y) or _is_road(x + 1, y)
		var v := _is_road(x, y - 1) or _is_road(x, y + 1)
		if h and v:
			return _tiles.get("road_x")
		if v:
			return _tiles.get("road_v")
		return _tiles.get("road_h")
	if _dirt.is_empty():
		return null
	# Cheap integer hash so variation is stable per cell.
	var hsh := int((x * 73856093) ^ (y * 19349663)) & 0x7fffffff
	return _dirt[hsh % _dirt.size()]

func _is_road(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < world_w and y < world_h and land_grid[y][x] == 1

func _visible_world_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(0, 0, world_w * cell, world_h * cell)
	var vp := get_viewport_rect().size
	var topleft: Vector2 = cam.screen_to_world(Vector2.ZERO)
	return Rect2(topleft, vp / cam.zoom)
