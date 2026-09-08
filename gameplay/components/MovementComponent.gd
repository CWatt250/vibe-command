extends RefCounted
## MovementComponent — follows a path toward a goal, respecting speed/accel/turn and grid nav.
## Movement only; the move is issued by the Simulation's order system which computes the path.

var speed: float = 60.0
var acceleration: float = 200.0
var turn_rate_deg: float = 160.0
var footprint_radius: float = 6.0
var path_layer: String = "ground"

var path: Array[Vector2] = []
var path_index: int = 0
var goal: Vector2 = Vector2.ZERO
var has_goal: bool = false
var _current_speed: float = 0.0

func setup(def: Dictionary, profile: Dictionary) -> void:
	speed = profile.get("speed", 60.0)
	acceleration = profile.get("acceleration", 200.0)
	turn_rate_deg = profile.get("turnRateDeg", 160.0)
	footprint_radius = profile.get("footprintRadius", 6.0)
	path_layer = profile.get("pathLayer", "ground")

func set_path(new_path: Array[Vector2], new_goal: Vector2) -> void:
	path = new_path
	path_index = 0
	goal = new_goal
	has_goal = true

func clear() -> void:
	path = []
	path_index = 0
	has_goal = false
	_current_speed = 0.0

func is_moving() -> bool:
	return has_goal and path_index < path.size()

func reached_goal(pos: Vector2) -> bool:
	return has_goal and pos.distance_to(goal) <= 4.0

## Advance movement toward the current path waypoint. Returns new position.
func update(dt: float, pos: Vector2) -> Vector2:
	if not is_moving():
		return pos
	# skip waypoints already reached
	while path_index < path.size() and pos.distance_to(path[path_index]) <= footprint_radius:
		path_index += 1
	if path_index >= path.size():
		has_goal = false
		return pos
	var target: Vector2 = path[path_index]
	var dir := target - pos
	var dist := dir.length()
	if dist <= 1.0:
		path_index += 1
		return pos
	# accelerate toward speed
	if _current_speed < speed:
		_current_speed = minf(speed, _current_speed + acceleration * dt)
	# don't overshoot the final segment
	var move := _current_speed * dt
	if move >= dist:
		path_index += 1
		if path_index >= path.size():
			has_goal = false
		return target
	return pos + dir.normalized() * move
