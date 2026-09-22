extends Node3D
class_name Entity3D
## Wraps one sim Entity for the 3D prototype (p2-01): mirrors its position every frame
## (sim x,y -> 3D x,z per the coordinate contract) with smooth yaw turning at the entity's
## own turn rate, and hands its model (from Models3D) the speed/turning it needs to animate.

var entity: Entity
var model: Node3D

var _yaw: float = 0.0
var _prev_pos: Vector2
var _t: float = 0.0
var speed: float = 0.0     # world units/s, from position delta
var turning: float = 0.0   # signed yaw rate, rad/s

func setup(e: Entity, m: Node3D) -> void:
	entity = e
	model = m
	add_child(model)
	_prev_pos = e.position
	position = Vector3(e.position.x, 0.0, e.position.y)
	var facing: Vector2 = e.movement.facing if e.movement != null else Vector2.RIGHT
	_yaw = atan2(-facing.y, facing.x)
	rotation.y = _yaw

func tick(dt: float) -> void:
	if entity == null or not entity.alive:
		return
	_t += dt
	var new_pos: Vector2 = entity.position
	speed = new_pos.distance_to(_prev_pos) / dt if dt > 0.0 else 0.0
	_prev_pos = new_pos
	position = Vector3(new_pos.x, 0.0, new_pos.y)

	var facing: Vector2 = entity.movement.facing if entity.movement != null else Vector2.RIGHT
	var wanted_yaw := atan2(-facing.y, facing.x)
	if entity.movement == null:
		_yaw = wanted_yaw
		turning = 0.0
	else:
		var diff := wrapf(wanted_yaw - _yaw, -PI, PI)
		var max_step := deg_to_rad(entity.movement.turn_rate_deg) * dt
		var step := clampf(diff, -max_step, max_step)
		_yaw += step
		turning = step / dt if dt > 0.0 else 0.0
	rotation.y = _yaw

	if model.has_method("animate"):
		model.animate(dt, _t, speed, turning)
