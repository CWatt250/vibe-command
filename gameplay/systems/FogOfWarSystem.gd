extends RefCounted
class_name FogOfWarSystem
## FogOfWarSystem — per-faction visibility grid (§5.6). Three states per cell:
##  0 = Unexplored (never seen)   1 = Explored/Fogged (seen before)   2 = Visible (this tick)
## Vision sources are entities with a SensorComponent (vision_radius > 0). Terrain/structures
## stay as last-known silhouettes in explored fog; units disappear unless re-visible.
## Pure logic, no Node — the sim owns it and the minimap reads the same data.

var _grid_w: int = 0
var _grid_h: int = 0
var _cell: float = 40.0
var _explored: Dictionary = {}   # faction -> PackedByteArray (0/1), "seen ever"
var _visible: Dictionary = {}    # faction -> PackedByteArray (0/1), "visible this tick"

func _init(w: int, h: int, cell: float) -> void:
	_grid_w = w
	_grid_h = h
	_cell = cell

func _ensure(faction: String) -> void:
	if not _explored.has(faction):
		var e := PackedByteArray()
		e.resize(_grid_w * _grid_h)
		_explored[faction] = e
	if not _visible.has(faction):
		var v := PackedByteArray()
		v.resize(_grid_w * _grid_h)
		_visible[faction] = v

## Recompute this tick's visibility from all the faction's entities that carry vision.
## Fills _visible (this-tick state) and ORs it into _explored (persistent memory).
func update(entities: Dictionary, faction: String) -> void:
	_ensure(faction)
	var vis: PackedByteArray = _visible[faction]
	var exp: PackedByteArray = _explored[faction]
	# Clear this-tick visible flags first.
	for i in range(vis.size()):
		vis[i] = 0
	# Mark visible cells around every vision source.
	for id in entities:
		var e = entities[id]
		if e == null or not e.alive or e.faction_id != faction:
			continue
		if e.sensor == null or e.sensor.vision_radius <= 0.0:
			continue
		_stamp_circle(vis, e.position, e.sensor.vision_radius)
	# Persist: anything visible this tick was seen ever.
	for i in range(vis.size()):
		if vis[i] == 1:
			exp[i] = 1

func _stamp_circle(vis: PackedByteArray, pos: Vector2, radius: float) -> void:
	var c := Vector2i(int(floor(pos.x / _cell)), int(floor(pos.y / _cell)))
	var r_cells := int(ceil(radius / _cell))
	var r2 := radius * radius
	for dy in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var cx := c.x + dx
			var cy := c.y + dy
			if cx < 0 or cy < 0 or cx >= _grid_w or cy >= _grid_h:
				continue
			# Cheap circle test on the cell center in world space.
			var wx := (cx + 0.5) * _cell
			var wy := (cy + 0.5) * _cell
			var ddx := wx - pos.x
			var ddy := wy - pos.y
			if ddx * ddx + ddy * ddy <= r2:
				vis[cy * _grid_w + cx] = 1

## 0/1/2 state (Unexplored / Explored / Visible) for a world position.
func state_at(faction: String, pos: Vector2) -> int:
	_ensure(faction)
	var c := Vector2i(int(floor(pos.x / _cell)), int(floor(pos.y / _cell)))
	if c.x < 0 or c.y < 0 or c.x >= _grid_w or c.y >= _grid_h:
		return 0
	var i := c.y * _grid_w + c.x
	if _visible[faction][i] == 1:
		return 2
	if _explored[faction][i] == 1:
		return 1
	return 0

## Is this world position currently visible to the faction? (units render only when true.)
func is_visible(faction: String, pos: Vector2) -> bool:
	return state_at(faction, pos) == 2

## Raw state bytes for the minimap (0=unexplored,1=explored,2=visible).
func state_bytes(faction: String) -> PackedByteArray:
	_ensure(faction)
	var vis: PackedByteArray = _visible[faction]
	var exp: PackedByteArray = _explored[faction]
	var out := PackedByteArray()
	out.resize(vis.size())
	for i in range(vis.size()):
		if vis[i] == 1:
			out[i] = 2
		elif exp[i] == 1:
			out[i] = 1
		else:
			out[i] = 0
	return out

func grid_width() -> int:
	return _grid_w
func grid_height() -> int:
	return _grid_h
func cell_size() -> float:
	return _cell
