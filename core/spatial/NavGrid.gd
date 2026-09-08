extends RefCounted
class_name NavGrid
## NavGrid — occupancy/passability terrain grid + A* pathfinding (Blueprint §3.6).
## PathLayer separation: ground vs air units use different passability rules.
## Entities register/unregister obstacle cells as they spawn/die, so building
## placement and destruction update navigation within a bounded delay.

const CELL: float = 40.0  # world units per grid cell

var width: int
var height: int
var _blocked: PackedByteArray      # 0 passable, 1 blocked (ground layer only)
var _air_blocked: PackedByteArray  # 0 passable, 1 blocked (air layer)
var _cell_index: Dictionary = {}   # cell key -> WorldCell data (resource/height)
var land_types: Array = []         # Array[Array[int]] terrain for rendering: 0 open, 1 street, 2 blocked

func _init(w: int, h: int) -> void:
	width = w
	height = h
	_blocked = PackedByteArray()
	_blocked.resize(w * h)
	_air_blocked = PackedByteArray()
	_air_blocked.resize(w * h)
	land_types = []
	for y in range(h):
		var row: Array[int] = []
		row.resize(w)
		row.fill(0)
		land_types.append(row)

func idx(cx: int, cy: int) -> int:
	return cy * width + cx

func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < width and cy < height

func world_to_cell(x: float, y: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(y / CELL)))

func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

func is_blocked(cx: int, cy: int, air: bool = false) -> bool:
	if not in_bounds(cx, cy):
		return true
	if air:
		return _air_blocked[idx(cx, cy)] == 1
	return _blocked[idx(cx, cy)] == 1

func set_blocked(cx: int, cy: int, blocked: bool, air: bool = false) -> void:
	if not in_bounds(cx, cy):
		return
	if air:
		_air_blocked[idx(cx, cy)] = 1 if blocked else 0
	else:
		_blocked[idx(cx, cy)] = 1 if blocked else 0
		# Keep the render land-type in sync for ground blocking (2 = blocked).
		if blocked:
			land_types[cy][cx] = 2
		elif land_types[cy][cx] == 2:
			land_types[cy][cx] = 0

## Register a rectangular footprint as blocked (for structures / map obstacles).
func block_rect(cx: int, cy: int, w: int, h: int, air: bool = false) -> void:
	for dy in range(h):
		for dx in range(w):
			set_blocked(cx + dx, cy + dy, true, air)

func unblock_rect(cx: int, cy: int, w: int, h: int, air: bool = false) -> void:
	for dy in range(h):
		for dx in range(w):
			set_blocked(cx + dx, cy + dy, false, air)

# --- A* pathfinding (breadth-grid, 8-dir, no corner cutting) ---
func find_path(start: Vector2, goal: Vector2, air: bool = false) -> Array[Vector2]:
	var sc = world_to_cell(start.x, start.y)
	var gc = world_to_cell(goal.x, goal.y)
	# If the target cell is blocked, find nearest passable neighbor.
	if not air and is_blocked(gc.x, gc.y):
		gc = _nearest_open(gc, air)
		if gc.x < 0:
			return []
	if not air and is_blocked(sc.x, sc.y):
		sc = _nearest_open(sc, air)
		if sc.x < 0:
			return []

	var open: Array[Vector2i] = [sc]
	var came_from: Dictionary = {}
	var gscore: Dictionary = {sc: 0.0}
	var fscore: Dictionary = {sc: _heuristic(sc, gc)}
	var closed: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)
	]

	while open.size() > 0:
		# find lowest f
		var best_idx := 0
		var best_f: float = fscore.get(open[0], INF)
		for i in range(1, open.size()):
			var f: float = fscore.get(open[i], INF)
			if f < best_f:
				best_f = f
				best_idx = i
		var current: Vector2i = open[best_idx]
		open.remove_at(best_idx)

		if current == gc:
			return _reconstruct(came_from, current, start, goal)

		closed[current] = true
		for d in dirs:
			var n: Vector2i = current + d
			if not in_bounds(n.x, n.y):
				continue
			if closed.has(n):
				continue
			# no corner cutting: diag requires both orthogonals open
			if d.x != 0 and d.y != 0:
				if is_blocked(n.x, current.y, air) or is_blocked(current.x, n.y, air):
					continue
			if is_blocked(n.x, n.y, air):
				continue
			var cost := 1.414 if (d.x != 0 and d.y != 0) else 1.0
			var tentative: float = gscore[current] + cost
			if tentative < gscore.get(n, INF):
				came_from[n] = current
				gscore[n] = tentative
				fscore[n] = tentative + _heuristic(n, gc)
				if not open.has(n):
					open.append(n)
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: float = absf(float(a.x - b.x))
	var dy: float = absf(float(a.y - b.y))
	return maxf(dx, dy) + 0.414 * minf(dx, dy)

func _nearest_open(c: Vector2i, air: bool) -> Vector2i:
	if not is_blocked(c.x, c.y, air):
		return c
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cx := c.x + dx
				var cy := c.y + dy
				if in_bounds(cx, cy) and not is_blocked(cx, cy, air):
					return Vector2i(cx, cy)
	return Vector2i(-1, -1)

func _reconstruct(came_from: Dictionary, current: Vector2i, start: Vector2, goal: Vector2) -> Array[Vector2]:
	var cells: Array[Vector2i] = [current]
	while came_from.has(cells[cells.size() - 1]):
		cells.append(came_from[cells[cells.size() - 1]])
	cells.reverse()
	var path: Array[Vector2] = []
	# First world point = actual start; last = actual goal (tolerance).
	path.append(start)
	for i in range(1, cells.size() - 1):
		path.append(cell_to_world(cells[i]))
	path.append(goal)
	return path
