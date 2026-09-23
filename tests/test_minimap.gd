extends SceneTree
## test_minimap.gd — p4-02: MiniMapRenderer screen<->world mapping, hit-test, jump, MOVE order.
## Headless: `godot-4 --headless --path . --script tests/test_minimap.gd`
## The minimap and camera are added to the root so get_viewport_rect() works.

var failures: int = 0
var _ran: bool = false

## MainLoop._process runs once the root is in the tree (SceneTree._init / _initialize are too
## early: get_viewport_rect() returns Rect2() there). First frame only, then quit().
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	var mm := MiniMapRenderer.new(sim, sim.fog_sys, "VC", null)
	get_root().add_child(mm)

	# The headless root window is not the game's 1280x720 (it comes up square); pin it so the
	# numbers below are the same ones the real window produces.
	get_root().size = Vector2i(1280, 720)
	var vp := mm.get_viewport_rect().size
	_check(vp == Vector2(1280, 720), "premise: viewport is 1280x720 (%s)" % vp)
	var r := mm.minimap_rect()
	_check(r.size == Vector2(MiniMapRenderer.MAP_SIZE, MiniMapRenderer.MAP_SIZE), "minimap rect is MAP_SIZE square")
	_check(r.end.is_equal_approx(vp - Vector2(MiniMapRenderer.MARGIN, MiniMapRenderer.MARGIN)), "minimap sits MARGIN in from bottom-right")
	_check(r.position.is_equal_approx(Vector2(1044, 484)), "minimap origin is (1044, 484) at 1280x720 (%s)" % r.position)
	_check(mm.world_size() == Vector2(2000, 2000), "world size is 50x50 cells x 40 = 2000x2000 (%s)" % mm.world_size())

	# --- round trip at the four corners and the centre ---
	var pts := [Vector2(0, 0), Vector2(2000, 0), Vector2(0, 2000), Vector2(2000, 2000), Vector2(1000, 1000)]
	for w in pts:
		var m: Vector2 = mm.world_to_minimap(w)
		_check(mm.minimap_to_world(m).is_equal_approx(w), "round trip world %s -> minimap %s -> world" % [w, m])
	_check(mm.world_to_minimap(Vector2.ZERO).is_equal_approx(r.position), "world origin maps to the minimap top-left")
	_check(mm.world_to_minimap(Vector2(2000, 2000)).is_equal_approx(r.end), "world far corner maps to the minimap bottom-right")
	_check(mm.minimap_to_world(r.get_center()).is_equal_approx(Vector2(1000, 1000)), "minimap centre maps to world centre")
	_check(mm.minimap_to_world(r.position + Vector2(110, 90)).is_equal_approx(Vector2(1000, 818.1818)),
		"local (110, 90) -> world (1000, 818.18) — the screenshot click")

	# --- hit-test ---
	_check(mm.contains_screen(r.get_center()), "centre of the minimap is inside")
	_check(mm.contains_screen(r.position), "top-left corner is inside (inclusive)")
	_check(not mm.contains_screen(r.position - Vector2(1, 1)), "one px up-left of the minimap is outside")
	_check(not mm.contains_screen(r.end), "bottom-right corner is outside (exclusive)")
	_check(not mm.contains_screen(Vector2(640, 360)), "screen centre is the world, not the minimap")
	_check(not mm.contains_screen(Vector2(1100, 400)), "above the minimap is outside")

	# --- right-click: MOVE for the current selection, same dict as SelectionInput ---
	var uid := sim.spawn_unit("VC-U04", "VC", Vector2(900, 900))
	var got: Array = []
	mm.orders_issued.connect(func(o: Array) -> void: got.assign(o))   # lambdas capture by value; mutate in place
	sim.selected_ids = []
	mm.order_move_at(r.get_center())
	_check(got.is_empty(), "no selection -> no order emitted")
	sim.selected_ids = [uid]
	mm.order_move_at(r.get_center())
	_check(got.size() == 1 and got[0].get("type") == "MOVE", "right-click emits one MOVE")
	_check(got.size() == 1 and got[0].get("entityIds") == [uid], "MOVE carries the selected ids")
	_check(got.size() == 1 and got[0].get("targetPosition").is_equal_approx(Vector2(1000, 1000)), "MOVE targets the world point under the cursor")
	sim.run_commands(0, got)
	_check(sim.entities[uid].order == Entity.Order.MOVE and sim.entities[uid].order_dest.is_equal_approx(Vector2(1000, 1000)),
		"sim accepted the minimap MOVE (order_dest %s)" % sim.entities[uid].order_dest)

	# --- left-click: camera jump, clamped like every other camera move ---
	var cam := RTSCamera.new()
	cam.set_world_size(2000, 2000)
	get_root().add_child(cam)
	mm.rts_cam = cam
	mm.jump_to_screen(r.position + Vector2(110, 90))
	_check(cam.position.is_equal_approx(Vector2(1000, 818.1818)), "jump centres the camera on the clicked world point (%s)" % cam.position)
	mm.jump_to_screen(r.position)
	_check(cam.position.is_equal_approx(vp * 0.5), "jump to the map corner clamps to half the view (%s)" % cam.position)
	mm.jump_to_screen(r.end)
	_check(cam.position.is_equal_approx(Vector2(2000, 2000) - vp * 0.5), "jump to the far corner clamps at world - half view (%s)" % cam.position)

	mm.free()
	cam.free()
	if failures == 0:
		print("MINIMAP_RESULT: ALL PASS")
	else:
		print("MINIMAP_RESULT: %d FAILURE(S)" % failures)
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
