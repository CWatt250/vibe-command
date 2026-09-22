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
			_add_spin_marker(c as Node3D)

## The tire's tread band is rotationally symmetric, so from a near-top-down camera the wheel
## looks identical at every spin phase even though wheel_rot is genuinely changing (the same
## problem Drone3D's rotor discs had). A small off-centre marker breaks that symmetry — its
## swept position visibly differs frame to frame, like a valve stem on a real wheel.
## NOTE: `radius` here is the WORLD-scaled wheel_radius (0.3 * body scale, see Models3D.truck)
## — used for the wheel_spin physics in animate(). The wheel *node* itself still lives in the
## kit's native (pre-scale) local space, since only the Truck3D root carries the uniform scale
## — sizing this marker off `radius` put it ~17x too big. Native wheel radius is ~0.3.
const _NATIVE_WHEEL_RADIUS := 0.3

func _add_spin_marker(wheel: Node3D) -> void:
	# Offset along local Z (the wheel's front/back extent, in the direction rotate_x sweeps),
	# not Y (top of the wheel) — a top-of-wheel marker sits directly under the wheel-well
	# lip and the fender occludes it from every capture angle used here.
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = _NATIVE_WHEEL_RADIUS * 0.3
	sm.height = _NATIVE_WHEEL_RADIUS * 0.6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.78)
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, _NATIVE_WHEEL_RADIUS * 1.25)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wheel.add_child(mi)

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
