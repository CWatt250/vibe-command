extends SceneTree
## test_p3_03_motion.gd — p3-03: UnitMotion's pure helpers (bob/rock/hover/rotor/dust cadence)
## plus speed measured from the presenter's own position delta against the real sim.
## Headless: `godot-4 --headless --path . --script tests/test_p3_03_motion.gd`

var failures: int = 0

func _init() -> void:
	# --- pure helpers: 0 at rest, non-zero moving, bounded ---
	for armor in ["Infantry", "HeavyInfantry", "Light", "Medium", "Heavy", "AirLight", "AirHeavy", ""]:
		var at_rest_zero := true
		for i in range(60):
			if UnitMotion.bob_offset(armor, i / 60.0, 0.0, 3) != 0.0 or UnitMotion.rock_angle(armor, i / 60.0, 0.0, 3) != 0.0:
				at_rest_zero = false
		_check(at_rest_zero, "%s: bob and rock are 0 at rest" % armor)
	for armor in ["Light", "Medium", "Heavy"]:
		var amp: float = UnitMotion.P[armor]["bob_px"]
		var seen_nonzero := false
		var bounded := true
		for i in range(60):
			var v := UnitMotion.bob_offset(armor, i / 60.0, 100.0, 3)
			seen_nonzero = seen_nonzero or v != 0.0
			bounded = bounded and absf(v) <= amp + 0.0001
		_check(seen_nonzero and bounded, "%s: bob moves and stays within +-%.1f px" % [armor, amp])
		_check(UnitMotion.rock_angle(armor, 0.13, 100.0, 3) != 0.0, "%s: rocks while moving" % armor)
	var infantry_vals := {}
	for i in range(120):
		infantry_vals[UnitMotion.bob_offset("Infantry", i / 60.0, 60.0, 3)] = true
	_check(infantry_vals.size() == 2 and infantry_vals.has(0.0) and infantry_vals.has(-1.5), "Infantry: 2-frame walk bob (0 / -1.5)")
	_check(UnitMotion.hover_offset("AirLight", 0.2, 3) != 0.0 and UnitMotion.hover_offset("Light", 0.2, 3) == 0.0, "hover: air only, on at rest")
	_check(UnitMotion.rotor_angle(1.0 / 15.0) != UnitMotion.rotor_angle(2.0 / 15.0), "rotor phase changes every tick")
	# --- dust cadence ---
	var dust_rest := 0
	var dust_move := 0
	for t in range(60):
		if UnitMotion.dust_due("Light", t, 7, 0.0): dust_rest += 1
		if UnitMotion.dust_due("Light", t, 7, 100.0): dust_move += 1
	_check(dust_rest == 0, "no dust at rest")
	_check(dust_move == 15, "Light dust every 4 ticks -> 15 in 60 (got %d)" % dust_move)
	_check(not UnitMotion.dust_due("AirLight", 4, 0, 100.0) and not UnitMotion.dust_due("Infantry", 4, 0, 100.0), "no dust for air / infantry")
	# --- speed from position delta, against the real sim ---
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var sim := Simulation.new(registry, GameEvents.new(), 50, 50)
	sim.add_player("VC")
	var motion := UnitMotion.new()
	var tech := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1500))
	for i in range(3):
		sim.step(1.0 / 15.0); motion.sample(sim, 1.0 / 15.0)
	_check(motion.speed_of(tech) == 0.0, "idle unit: speed 0")
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [tech], "targetPosition": Vector2(1400, 1500)}])
	for i in range(10):
		sim.step(1.0 / 15.0); motion.sample(sim, 1.0 / 15.0)
	_check(motion.speed_of(tech) >= UnitMotion.MOVING_SPEED, "moving unit: speed %.1f >= MOVING_SPEED" % motion.speed_of(tech))
	_check(motion.speed_of(99999) == 0.0, "unknown id: speed 0")

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
	if failures == 0:
		print("P3_03_RESULT: ALL PASS")
	else:
		print("P3_03_RESULT: %d FAILED" % failures)
	quit()
