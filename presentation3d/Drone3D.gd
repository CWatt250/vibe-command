extends Node3D
class_name Drone3D
## VC-U02 (Scout Quad) has no kit mesh — built from primitives per p2-01: a dark hull, four
## arms at the diagonals, four spinning rotors, a cyan emissive underlight. Hovers with a
## slow bob and tilts nose-down while moving.

var _rotors: Array = []   # [{node: Node3D, dir: float}]
var _t0: float = 0.0

func _init() -> void:
	var body_mat := _mat(Color(0.10, 0.11, 0.13))
	var rotor_mat := _mat(Color(0.04, 0.04, 0.05))
	add_child(_box("hull", Vector3(10, 3, 10), body_mat))
	for i in range(4):
		var ang := deg_to_rad(45.0 + i * 90.0)
		var arm := _box("arm%d" % i, Vector3(12, 1, 1.5), body_mat)
		arm.rotation.y = ang
		arm.position = Vector3(cos(ang) * 5.0, 0.0, sin(ang) * 5.0)
		add_child(arm)
		# A circular disc spinning about its own vertical axis looks identical at every
		# rotation phase from a near-top-down camera — the showcase's whole point. An
		# elongated blade (long along X, sitting flat) sweeps a visibly different silhouette
		# each frame instead.
		var rotor := _box("rotor%d" % i, Vector3(9.0, 0.4, 1.4), rotor_mat)
		rotor.position = Vector3(cos(ang) * 11.0, 1.0, sin(ang) * 11.0)
		add_child(rotor)
		_rotors.append({"node": rotor, "dir": 1.0 if i % 2 == 0 else -1.0})
	var glow := _sphere("glow", 1.0, _emissive(Color(0.0, 0.85, 1.0)))
	glow.position = Vector3(0.0, -2.0, 0.0)
	add_child(glow)

func animate(dt: float, t: float, speed: float, _turning: float) -> void:
	for r in _rotors:
		(r["node"] as Node3D).rotate_y(40.0 * float(r["dir"]) * dt)
	position.y = 24.0 + sin(t * 2.0) * 1.5
	var target_pitch := -0.15 if speed > 1.0 else 0.0
	rotation.x = lerp_angle(rotation.x, target_pitch, clampf(dt * 6.0, 0.0, 1.0))

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m

func _emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m

func _box(n: String, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func _sphere(n: String, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
