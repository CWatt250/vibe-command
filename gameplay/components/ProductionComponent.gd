extends RefCounted
## ProductionComponent — a structure's training/construction queue (Blueprint §5, §4.3).
## Items reserve Credits at queue time; progress ticks only when powered.
## Rally point targets ground, friendly structure, or repair structure where sensible.

var queue: Array = []            # [{unit_def_id, progress, duration_total, paid}]
var rally_point: Vector2 = Vector2.ZERO
var _power_ok: bool = true
var building_open: bool = true

func setup(_def: Dictionary, _owner) -> void:
	pass

func can_queue(unit_def_id: String) -> bool:
	# caller validates cost/tech/requirement before enqueue
	return building_open

func enqueue(unit_def_id: String, _cost: float, build_time: float) -> void:
	queue.append({
		"unit": unit_def_id,
		"progress": 0.0,
		"total": build_time,
		"paid": true
	})

func cancel(index: int) -> Dictionary:
	if index < 0 or index >= queue.size():
		return {}
	return queue[index]

func remove_at(index: int) -> void:
	if index >= 0 and index < queue.size():
		queue.remove_at(index)

func set_powered(p: bool) -> void:
	_power_ok = p

func tick(dt: float) -> Array:
	## Advance queue; returns array of completed unit defs this tick.
	var completed: Array = []
	if _power_ok and queue.size() > 0:
		queue[0]["progress"] += dt
		if queue[0]["progress"] >= queue[0]["total"]:
			var done = queue.pop_front()
			completed.append(done["unit"])
	return completed

func peek_first() -> Dictionary:
	return queue[0] if queue.size() > 0 else {}

func queue_size() -> int:
	return queue.size()

func progress() -> float:
	if queue.size() == 0:
		return 0.0
	return queue[0]["progress"] / queue[0]["total"]
