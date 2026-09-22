extends Node3D
class_name Soldier3D
## Attached (via set_script, post-instantiate) to the Kenney blocky-characters character-c.glb
## instance used for VC-U01 in the 3D prototype (p2-01). Procedural walk cycle driven each
## frame by Entity3D from the sim's own speed; idle relaxes back to a neutral pose.

var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _root: Node3D

func setup() -> void:
	_leg_l = find_child("leg-left", true, false)
	_leg_r = find_child("leg-right", true, false)
	_arm_l = find_child("arm-left", true, false)
	_arm_r = find_child("arm-right", true, false)
	_root = find_child("root", true, false)
	# The kit ships its own walk/idle/etc. AnimationPlayer; stop it so it doesn't fight our
	# procedural pose.
	var players := find_children("*", "AnimationPlayer", true, false)
	for p in players:
		(p as AnimationPlayer).stop()

func animate(dt: float, t: float, speed: float, _turning: float) -> void:
	var walking := speed > 1.0
	var swing := sin(t * 8.0) * 0.6 if walking else 0.0
	var arm_swing := sin(t * 8.0) * 0.4 if walking else 0.0
	var bob := sin(t * 16.0) * 0.6 if walking else 0.0
	var lerp_w := clampf(dt * 10.0, 0.0, 1.0)  # idle relaxes back rather than snapping to zero
	if _leg_l: _leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, swing, lerp_w)
	if _leg_r: _leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, -swing, lerp_w)
	if _arm_l: _arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, -arm_swing, lerp_w)
	if _arm_r: _arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, arm_swing, lerp_w)
	if _root: _root.position.y = lerp(_root.position.y, bob, lerp_w)
