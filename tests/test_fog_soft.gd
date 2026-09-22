extends SceneTree
## test_fog_soft.gd — p3-02: FogRenderer's world overlay is a soft 3-cell gradient while
## `texture` (minimap) stays crisp and the sim's fog state is untouched.
## Headless: `godot-4 --headless --path . --script tests/test_fog_soft.gd`

const SensorComponent := preload("res://gameplay/components/SensorComponent.gd")

var failures: int = 0

class Eye:
	var alive := true
	var faction_id := "VC"
	var position := Vector2.ZERO
	var sensor = null

func _init() -> void:
	# 9x9 grid, 40-px cells, one eye at the centre of cell (4,4) with a 10-px vision radius:
	# _stamp_circle reaches only that one cell (neighbour centres are 40 px away).
	var fog := FogOfWarSystem.new(9, 9, 40.0)
	var eye := Eye.new()
	eye.position = Vector2(4.5 * 40.0, 4.5 * 40.0)
	eye.sensor = SensorComponent.new()
	eye.sensor.vision_radius = 10.0
	fog.update({1: eye}, "VC")
	_check(fog.state_bytes("VC").count(2) == 1, "test premise: exactly one visible cell")

	var fr := FogRenderer.new(fog, "VC")
	fr._refresh_texture()

	# --- soft overlay: 0 at the eye, intermediate on the two neighbours, opaque beyond ---
	var c := fr.soft_alpha_at(4, 4)
	var n1 := fr.soft_alpha_at(5, 4)
	var n2 := fr.soft_alpha_at(6, 4)
	var n3 := fr.soft_alpha_at(7, 4)
	var far := fr.soft_alpha_at(0, 0)
	print("soft alpha row y=4 from centre: %d %d %d %d ; corner %d" % [c, n1, n2, n3, far])
	_check(c == 0, "centre texel is fully clear (got %d)" % c)
	_check(n1 > 0 and n1 < 255, "1st neighbour is intermediate (got %d)" % n1)
	_check(n2 > n1 and n2 < 255, "2nd neighbour is intermediate and darker (got %d)" % n2)
	_check(n3 == 255, "3rd cell out is opaque (got %d)" % n3)
	_check(far == 255, "far cell is opaque (got %d)" % far)
	_check(n1 == 85 and n2 == 170, "exact ramp 0/85/170/255 (got %d/%d)" % [n1, n2])

	# --- crisp texture (minimap) unchanged: hard 0/255 step ---
	var crisp_c := int(round(fr._image.get_pixel(4, 4).a * 255.0))
	var crisp_n := int(round(fr._image.get_pixel(5, 4).a * 255.0))
	_check(crisp_c == 0 and crisp_n == 255, "crisp texture keeps the 1-texel step (%d/%d)" % [crisp_c, crisp_n])

	# --- sim untouched: the dilated ring is still unexplored to the simulation ---
	_check(fog.state_at("VC", Vector2(5.5 * 40.0, 4.5 * 40.0)) == 0, "sim still reports neighbour unexplored")

	# --- explored cells stay dimmed, not black: move the eye, re-pack ---
	eye.position = Vector2(7.5 * 40.0, 7.5 * 40.0)
	fog.update({1: eye}, "VC")
	fr._refresh_texture()
	var explored := fr.soft_alpha_at(4, 4)
	_check(explored > 0 and explored <= 165, "vacated cell is dimmed, not opaque (got %d)" % explored)

	# Informational: re-pack cost on the real 50x50 grid (no assertion; ~1.5 ms expected).
	var fog50 := FogOfWarSystem.new(50, 50, 40.0)
	eye.position = Vector2(1000, 1000)
	eye.sensor.vision_radius = 280.0
	fog50.update({1: eye}, "VC")
	var fr50 := FogRenderer.new(fog50, "VC")
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		fr50._last_states = PackedByteArray()
		fr50._refresh_texture()
	print("repack 50x50: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))

	fr.free()
	fr50.free()
	if failures == 0:
		print("FOGSOFT_RESULT: ALL PASS")
	else:
		print("FOGSOFT_RESULT: %d FAILURE(S)" % failures)
	_finish()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)

func _finish() -> void:
	quit()
