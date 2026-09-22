extends Node3D
class_name Truck3D
## Attached (via set_script, post-instantiate) to the Kenney car-kit truck.glb instance used
## for VC-U04 in the 3D prototype (p2-01). Wheels spin, body rolls into turns and pitches
## under acceleration — driven each frame by Entity3D from the sim's own speed/turn rate.

var wheel_radius: float = 5.0
var _wheels: Array = []
var _body: Node3D
var _prev_speed: float = 0.0

func setup(radius: float) -> void:
	wheel_radius = radius
	_body = get_node_or_null("body")
	for c in get_children():
		if String(c.name).begins_with("wheel"):
			_wheels.append(c)

func animate(dt: float, _t: float, speed: float, turning: float) -> void:
	var wheel_spin := speed / maxf(wheel_radius, 0.01)
	for w in _wheels:
		(w as Node3D).rotate_x(wheel_spin * dt)
	if _body == null:
		return
	var accel := (speed - _prev_speed) / maxf(dt, 0.001)
	_prev_speed = speed
	var lerp_w := clampf(dt * 6.0, 0.0, 1.0)
	var target_roll := clampf(-turning * 0.02, -0.12, 0.12)
	var target_pitch := clampf(-accel * 0.002, -0.2, 0.2)
	_body.rotation.z = lerp_angle(_body.rotation.z, target_roll, lerp_w)
	_body.rotation.x = lerp_angle(_body.rotation.x, target_pitch, lerp_w)
