extends SceneTree
## test_phase7.gd — Phase 7 (HUD) sim-side gates: CANCEL_TRAIN refund, public
## can_place(), faction_status() snapshot. Mirrors the test_phase5/6 harness style.
## Headless: `godot-4 --headless --path . --script tests/test_phase7.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# VC-B01 Garage HQ, VC-B07 Maker Space (trains VC-U01..U03), VC-B03 Generator Bank (power 10).
	var hq := sim.spawn_structure("VC-B01", "VC", Vector2(1000, 1000), true)
	var barracks := sim.spawn_structure("VC-B07", "VC", Vector2(1160, 1000), true)
	var power := sim.spawn_structure("VC-B03", "VC", Vector2(1000, 1160), true)
	if hq == -1 or barracks == -1 or power == -1:
		_fail("failed to spawn VC base")
		_finish()
		return
	_run(sim, 1)

	# --- Test 1: TRAIN reserves credits, CANCEL_TRAIN refunds them exactly ---
	var unit_def: Dictionary = registry.get_unit("VC-U02")
	var cost: float = unit_def.get("costCredits", 0.0)
	var before: float = sim.get_resources("VC")["credits"]
	sim.run_commands(0, [{"type": "TRAIN", "entityIds": [barracks], "unitDefId": "VC-U02"}])
	sim.run_commands(0, [{"type": "TRAIN", "entityIds": [barracks], "unitDefId": "VC-U02"}])
	var b: Entity = sim.entities[barracks]
	_check(b.production.queue_size() == 2, "two items queued (got %d)" % b.production.queue_size())
	var after_train: float = sim.get_resources("VC")["credits"]
	_check(is_equal_approx(before - after_train, cost * 2.0),
		"TRAIN x2 spent %.0f (expected %.0f)" % [before - after_train, cost * 2.0])

	_run(sim, 15)  # head item makes progress
	_check(b.production.progress() > 0.0, "head item progressed (%.2f)" % b.production.progress())

	# Cancel the second (unstarted) item. Measure right before: passive income ticks too.
	var pre_cancel: float = sim.get_resources("VC")["credits"]
	sim.run_commands(0, [{"type": "CANCEL_TRAIN", "entityIds": [barracks], "index": 1}])
	_check(b.production.queue_size() == 1, "queue shrank to 1 after cancel index 1")
	var after_cancel: float = sim.get_resources("VC")["credits"]
	_check(is_equal_approx(after_cancel - pre_cancel, cost),
		"cancel refunded %.0f (expected %.0f)" % [after_cancel - pre_cancel, cost])

	# Cancel the head (in-progress) item: refund full cost, progress forfeited.
	sim.run_commands(0, [{"type": "CANCEL_TRAIN", "entityIds": [barracks], "index": 0}])
	_check(b.production.queue_size() == 0, "queue empty after cancelling head")
	var after_cancel2: float = sim.get_resources("VC")["credits"]
	_check(is_equal_approx(after_cancel2 - after_cancel, cost), "head cancel refunded full cost")

	# Out-of-range index is a no-op, not a crash or a phantom refund.
	sim.run_commands(0, [{"type": "CANCEL_TRAIN", "entityIds": [barracks], "index": 7}])
	_check(is_equal_approx(sim.get_resources("VC")["credits"], after_cancel2), "bad index: no refund")

	# --- Test 2: can_place() mirrors BUILD validation without spending ---
	var credits_before_place: float = sim.get_resources("VC")["credits"]
	_check(sim.can_place("VC-B04", Vector2(1000, 1300), "VC"), "can_place: clear cell in HQ radius")
	_check(not sim.can_place("VC-B04", Vector2(1000, 1000), "VC"), "can_place: rejects HQ footprint")
	_check(not sim.can_place("VC-B04", Vector2(-40, -40), "VC"), "can_place: rejects out of bounds")
	_check(not sim.can_place("NOPE-B99", Vector2(1000, 1300), "VC"), "can_place: rejects unknown def")
	_check(not sim.can_place("FC-B04", Vector2(1000, 1300), "FC"), "can_place: FC has no HQ -> out of radius")
	_check(is_equal_approx(sim.get_resources("VC")["credits"], credits_before_place),
		"can_place spent nothing")

	# --- Test 3: faction_status() snapshot ---
	var s: Dictionary = sim.faction_status("VC")
	_check(s.has("credits") and s.has("power") and s.has("compute") and s.has("command"),
		"faction_status has all four keys")
	_check(is_equal_approx(s["credits"], sim.get_resources("VC")["credits"]), "status credits match")
	_check(s["power"]["produced"] > 0.0, "status power produced > 0 with a power plant (%.0f)" % s["power"]["produced"])
	_check(s["power"].has("powered") and s["compute"].has("deficit") and s["command"].has("capacity"),
		"status sub-dicts carry the HUD flags")

	# --- p1-01: one tick rate ---
	_check(Simulation.ticks_per(3.0) == 5, "ticks_per(3 Hz) at 15 Hz is 5")
	_check(is_equal_approx(Simulation.TICK_DT, 1.0 / 15.0), "TICK_DT derives from TICK_HZ")

	# --- p1-02: selection faction/fog rule (mirrors SelectionInput._pickable) ---
	sim.selected_faction = "VC"
	var far_fc := sim.spawn_unit("FC-U01", "FC", Vector2(200, 200))   # far from every VC sensor
	_run(sim, 2)
	_check(not sim.fog_sys.is_visible("VC", sim.entities[far_fc].position), "hidden FC unit is not visible to VC")
	var near_fc := sim.spawn_unit("FC-U01", "FC", Vector2(1010, 1000))  # next to the VC HQ
	_run(sim, 2)
	_check(sim.fog_sys.is_visible("VC", sim.entities[near_fc].position), "FC unit beside VC HQ is visible")

	# --- p1-03: no acquisition through fog ---
	sim.add_player("FC")
	var shooter := sim.spawn_unit("VC-U01", "VC", Vector2(1400, 1400))   # Trooper, has a weapon
	var s_e: Entity = sim.entities[shooter]
	var vis_r: float = s_e.def_data.get("visionRadius", 200.0)
	var acq_r: float = s_e.weapon.acquire_radius
	_check(acq_r > vis_r, "test premise: acquire radius (%d) exceeds vision (%d)" % [acq_r, vis_r])
	# Enemy inside acquire radius but outside vision -> must NOT be acquired.
	var lurker := sim.spawn_unit("FC-U01", "FC", Vector2(1400 + (vis_r + acq_r) * 0.5, 1400))
	_run(sim, 3)
	_check(s_e.weapon.current_target_id != lurker, "enemy in fog is not acquired")
	# Move it inside vision -> acquired.
	sim.entities[lurker].position = Vector2(1400 + vis_r * 0.5, 1400)
	sim.spatial.update(lurker, sim.entities[lurker].position)
	_run(sim, 3)
	_check(s_e.weapon.current_target_id == lurker, "enemy revealed is acquired")

	if failures == 0:
		print("PHASE7_RESULT: ALL PASS")
	else:
		print("PHASE7_RESULT: %d FAILURE(S)" % failures)
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

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
