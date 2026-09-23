extends SceneTree
## test_camera.gd — p4-01: RTSCamera pan / cursor-anchored zoom / smoothing / clamp, headless.
## The camera never enters a tree; viewport_size_override stands in for the window.
## Headless: `godot-4 --headless --path . --script tests/test_camera.gd`

var failures: int = 0
const VP := Vector2(1280, 720)
const DT := 1.0 / 60.0

func _init() -> void:
	var cam := RTSCamera.new()
	cam.viewport_size_override = VP
	cam.set_world_size(2000.0, 2000.0)
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	_check(cam.viewport_size() == VP, "viewport_size() uses the override outside a tree")

	# --- pan: world delta = pan_speed * dt / zoom, direction normalised ---
	cam.pan_step(Vector2.RIGHT, 0.5)
	_check(cam.position.is_equal_approx(Vector2(1000 + cam.pan_speed * 0.5, 1000)),
		"pan right at zoom 1 moves pan_speed*dt (%s)" % cam.position)
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(2.0)
	cam.pan_step(Vector2.RIGHT, 0.5)
	_check(cam.position.is_equal_approx(Vector2(1000 + cam.pan_speed * 0.5 / 2.0, 1000)),
		"pan at zoom 2 covers half the world distance (constant on screen)")
	cam.position = Vector2(1000, 1000)
	cam.pan_step(Vector2(1, 1), 1.0)
	var diag: float = cam.pan_speed / 2.0 * sqrt(0.5)   # zoom is 2 here
	_check(cam.position.is_equal_approx(Vector2(1000 + diag, 1000 + diag)), "diagonal pan is normalised")
	cam.pan_step(Vector2.ZERO, 1.0)
	_check(cam.position.is_equal_approx(Vector2(1000 + diag, 1000 + diag)), "zero dir is a no-op")

	# --- edge scroll direction from a cursor position ---
	_check(cam.edge_dir(Vector2(0, 0)) == Vector2(-1, -1), "cursor at top-left scrolls up-left")
	_check(cam.edge_dir(Vector2(VP.x, VP.y * 0.5)) == Vector2(1, 0), "cursor at right edge scrolls right")
	_check(cam.edge_dir(Vector2(VP.x * 0.5, VP.y - cam.edge_margin)) == Vector2(0, 1), "margin row scrolls down")
	_check(cam.edge_dir(VP * 0.5) == Vector2.ZERO, "cursor at centre does not scroll")

	# --- cursor-anchored zoom: the world point under the cursor stays put ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	var anchor := Vector2(200, 100)
	var w0 := cam.screen_to_world(anchor)
	_check(w0.is_equal_approx(Vector2(560, 740)), "premise: screen (200,100) is world (560,740) (%s)" % w0)
	for z in [2.0, 2.5, 0.7, 3.0, 1.0]:
		cam.anchored_zoom(anchor, z)
		var w1 := cam.screen_to_world(anchor)
		_check(is_equal_approx(cam.zoom.x, z) and w1.distance_to(w0) < 0.5,
			"anchored zoom to %.1f keeps the anchored world point fixed (drift %.3f px)" % [z, w1.distance_to(w0)])
	_check(cam.position.is_equal_approx(Vector2(1000, 1000)), "returning to zoom 1 returns to the start position")

	# --- wheel notches scale the target multiplicatively and round-trip ---
	cam.set_zoom_now(1.0)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.zoom_notch * cam.zoom_notch), "two notches in = notch^2 target")
	_check(is_equal_approx(cam.zoom.x, 1.0), "wheel changes the target, not the zoom, until settle_zoom runs")
	cam.zoom_toward(1.0 / cam.zoom_notch)
	cam.zoom_toward(1.0 / cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, 1.0), "two notches out undo two notches in exactly")
	for i in range(40):
		cam.zoom_toward(cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.max_zoom), "target clamps at max_zoom")
	for i in range(80):
		cam.zoom_toward(1.0 / cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.min_zoom), "target clamps at min_zoom")

	# --- smoothing: monotone, never overshoots, converges, stays anchored throughout ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	var target: float = cam.zoom_target
	var anchor_w := cam.screen_to_world(anchor)
	var monotone := true
	var overshoot := false
	var max_drift := 0.0
	var prev: float = cam.zoom.x
	var frames_to_settle := -1
	for f in range(240):
		cam.settle_zoom(DT, anchor)
		if cam.zoom.x < prev - 1e-6:
			monotone = false
		if cam.zoom.x > target + 1e-6:
			overshoot = true
		max_drift = maxf(max_drift, cam.screen_to_world(anchor).distance_to(anchor_w))
		prev = cam.zoom.x
		if frames_to_settle < 0 and is_equal_approx(cam.zoom.x, target):
			frames_to_settle = f + 1
	_check(monotone, "zoom in approaches the target monotonically")
	_check(not overshoot, "zoom never overshoots the target")
	_check(is_equal_approx(cam.zoom.x, target), "zoom settles onto the target (%.4f vs %.4f)" % [cam.zoom.x, target])
	_check(frames_to_settle > 1 and frames_to_settle < 120,
		"settles in more than one frame and under two seconds (%d frames)" % frames_to_settle)
	_check(max_drift < 0.5, "anchored world point drifts < 0.5 px over the whole ease (%.3f)" % max_drift)
	_check(cam.zoom.y == cam.zoom.x, "zoom stays uniform")
	# First frame moves a fixed fraction: 1 - exp(-k dt) of the remaining gap.
	cam.set_zoom_now(1.0)
	cam.zoom_toward(2.0)
	cam.settle_zoom(DT, anchor)
	var expect: float = lerpf(1.0, 2.0, 1.0 - exp(-cam.zoom_smoothing * DT))
	_check(is_equal_approx(cam.zoom.x, expect), "one frame = exponential step (%.4f vs %.4f)" % [cam.zoom.x, expect])
	# Zoom OUT converges the same way.
	cam.set_zoom_now(2.0)
	cam.zoom_toward(0.5)
	prev = cam.zoom.x
	monotone = true
	for f in range(240):
		cam.settle_zoom(DT, anchor)
		if cam.zoom.x > prev + 1e-6:
			monotone = false
		prev = cam.zoom.x
	_check(monotone and is_equal_approx(cam.zoom.x, 1.0), "zoom out converges monotonically to the target")

	# --- clamp still holds after pans and zooms ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	cam.pan_step(Vector2.LEFT, 100.0)   # far past the left edge
	cam._clamp_to_world()
	_check(is_equal_approx(cam.position.x, VP.x * 0.5), "pan past the left edge clamps to half the view width")
	cam.position = Vector2(2000, 2000)
	cam.set_zoom_now(2.5)
	cam._clamp_to_world()
	_check(cam.position.is_equal_approx(Vector2(2000 - VP.x * 0.5 / 2.5, 2000 - VP.y * 0.5 / 2.5)),
		"bottom-right corner at zoom 2.5 clamps by viewport/(2*zoom) (%s)" % cam.position)
	cam.position = Vector2(100, 100)
	cam.anchored_zoom(Vector2.ZERO, 3.0)   # zoom in at the top-left corner, position runs off-world
	cam._clamp_to_world()
	var rect_tl := cam.screen_to_world(Vector2.ZERO)
	var rect_br := cam.screen_to_world(VP)
	_check(rect_tl.x >= -0.01 and rect_tl.y >= -0.01 and rect_br.x <= 2000.01 and rect_br.y <= 2000.01,
		"after an anchored zoom the view is still inside the world (%s .. %s)" % [rect_tl, rect_br])
	cam.set_zoom_now(0.5)   # view 2560x1440 on a 2000x2000 world: x centred, y still clamped
	cam._clamp_to_world()
	_check(cam.position.is_equal_approx(Vector2(1000, 720)),
		"zoomed past the world width the view is centred on x and clamped on y (%s)" % cam.position)

	# --- home ---
	cam.set_zoom_now(1.0)
	cam.home = Vector2(960, 960)
	cam.position = Vector2(1800, 1800)
	cam.go_home()
	_check(cam.position.is_equal_approx(Vector2(960, 960)), "go_home centres on home")
	cam.home = Vector2(0, 0)
	cam.go_home()
	_check(cam.position.is_equal_approx(VP * 0.5), "go_home clamps a home near the edge")

	cam.free()   # never entered a tree; free so quit() doesn't report a leaked node
	if failures == 0:
		print("CAMERA_RESULT: ALL PASS")
	else:
		print("CAMERA_RESULT: %d FAILURE(S)" % failures)
	quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)
