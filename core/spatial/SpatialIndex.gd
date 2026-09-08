extends RefCounted
class_name SpatialIndex
## SpatialIndex — grid-bucket spatial hash for fast range/nearest queries (Blueprint §11).
## Queries (units-in-radius, nearest enemy, acquisition) avoid scanning all entities.

const BUCKET: float = 160.0  # bucket size in world units

var _buckets: Dictionary = {}   # Vector2i -> Array[int] (entity ids)
var _positions: Dictionary = {} # entity id -> Vector2

func update(id: int, pos: Vector2) -> void:
	if _positions.has(id):
		_remove(id)
	_positions[id] = pos
	var key := _key_for(pos)
	if not _buckets.has(key):
		_buckets[key] = []
	_buckets[key].append(id)

func remove(id: int) -> void:
	if _positions.has(id):
		_remove(id)

func _remove(id: int) -> void:
	var pos: Vector2 = _positions[id]
	var key := _key_for(pos)
	_positions.erase(id)
	if _buckets.has(key):
		_buckets[key].erase(id)
		if _buckets[key].is_empty():
			_buckets.erase(key)

func _key_for(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / BUCKET)), int(floor(pos.y / BUCKET)))

func position_of(id: int) -> Vector2:
	return _positions.get(id, Vector2.ZERO)

## Return entity ids within 'radius' of 'pos'.
func query_radius(pos: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var r2 := radius * radius
	var min_key := _key_for(pos - Vector2(radius, radius))
	var max_key := _key_for(pos + Vector2(radius, radius))
	for ky in range(min_key.y, max_key.y + 1):
		for kx in range(min_key.x, max_key.x + 1):
			var key := Vector2i(kx, ky)
			if _buckets.has(key):
				for id in _buckets[key]:
					var target_pos: Vector2 = _positions[id]
					var d: Vector2 = target_pos - pos
					if d.length_squared() <= r2:
						result.append(id)
	return result
