extends SceneTree
## test_phase4.gd — Phase 4 (compute system) verification.
## Builds a Vibe base, verifies ComputeSystem: production, cooling multiplier, brownout
## reduction, and reserve-deficit -> deterministic global cooldown penalty.
## Mirrors the test harness in test_phase3.gd.

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	# load_all() pulls content JSON from res://content/data (see ContentRegistry).
	registry.load_all()

	var events := GameEvents.new()
	# 50x50 grid; big enough that build sites are within build radius of an HQ.
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# Pre-place a Vibe HQ (VC-B01 Garage Core, cost 500, build 20s, maxHealth 800).
	# It is the build-radius anchor. Placed as a build site then constructed, OR start_built.
	# We place it start_built=false so the sim constructs it like the Phase 3 test, then
	# build everything else within its radius.
	var hq := sim.spawn_structure("VC-B01", "VC", Vector2(1200, 1200), false)
	if hq == -1:
		failures += 1
		push_error("failed to spawn HQ")
		_finish()
		return
	# Construct the HQ to completion.
	_construct(sim, hq)

	# --- Test 1: Server Rack Hall produces compute; no cooling -> reduced usable ---
	var rack := sim.spawn_build_site("VC-B05", "VC", Vector2(1100, 1200))
	_construct(sim, rack)
	var c1 := sim.compute_sys._compute(sim.entities, "VC", 1.0)
	if c1["produced"] != 15.0:
		failures += 1
		push_error("expect Server Rack produces 15, got %s" % str(c1["produced"]))
	if c1["cooling_ratio"] >= 1.0:
		failures += 1
		push_error("expect cooling shortfall (cooling_ratio < 1) with a rack and no cooling plant, got %s" % str(c1["cooling_ratio"]))

	# --- Test 2: Cooling Plant satisfies cooling -> usable = produced ---
	var cool := sim.spawn_build_site("VC-B04", "VC", Vector2(1100, 1300))
	_construct(sim, cool)
	var c2 := sim.compute_sys._compute(sim.entities, "VC", 1.0)
	if c2["cooling_ratio"] != 1.0:
		failures += 1
		push_error("expect cooling_ratio 1 with a cooling plant, got %s" % str(c2["cooling_ratio"]))
	if c2["usable"] != 15.0:
		failures += 1
		push_error("expect usable compute 15 with cooling satisfied, got %s" % str(c2["usable"]))

	# --- Test 3: brownout reduces usable compute ---
	var c3 := sim.compute_sys._compute(sim.entities, "VC", 0.5)
	# Rack draws 4, cooling plant draws 2 = 6 drawn. One generator (10) -> ratio ~1.67.
	# Manually force brownout via the power_ratio arg here: usable should drop to 7.5.
	if absf(c3["usable"] - 7.5) > 0.001:
		failures += 1
		push_error("expect usable 7.5 at 0.5 power ratio, got %s" % str(c3["usable"]))

	# --- Test 4: reserve-demand + deficit -> cooldown penalty ---
	# Spawn an autonomous bot (VC-U06 Sentry Bot, reserveCapacity 3, Bot flag).
	var bot := sim.spawn_unit("VC-U06", "VC", Vector2(1300, 1200))
	if bot == -1:
		failures += 1
		push_error("failed to spawn VC-U06 bot")
		_finish()
		return
	# Run enough ticks so _recompute_compute() computes deficit. With 15 produced, usable
	# at 1.0 power/1.0 cooling = 15, but reserved = 3 (one bot) => NO deficit.
	_run(sim, 20)
	var c4 := sim.compute_sys._compute(sim.entities, "VC", 1.0)
	var bot_ent: Entity = sim.entities.get(bot)
	var penalty: float = sim.compute_sys.reaction_scale(c4["deficit"])
	if c4["deficit"]:
		failures += 1
		push_error("expect NO deficit with 15 compute vs 3 reserved, but deficit=true")
	if penalty != 1.0:
		failures += 1
		push_error("expect penalty 1.0 (no deficit), got %s" % str(penalty))

	# Now simulate heavy reserve: spawn many bots to exceed 15 usable.
	var ids: Array = []
	for i in range(8):
		var bid := sim.spawn_unit("VC-U06", "VC", Vector2(1320 + i * 5, 1200))
		ids.append(bid)
	_run(sim, 20)
	var c5 := sim.compute_sys._compute(sim.entities, "VC", 1.0)
	# reserved = 9 bots * 3 = 27 > usable 15 => deficit.
	if not c5["deficit"]:
		failures += 1
		push_error("expect deficit with 27 reserved vs 15 usable, but deficit=false")
	var penalty2: float = sim.compute_sys.reaction_scale(c5["deficit"])
	if penalty2 <= 1.0:
		failures += 1
		push_error("expect cooldown penalty > 1.0 under deficit, got %s" % str(penalty2))

	if failures == 0:
		print("PHASE4_RESULT: ALL PASS")
	else:
		print("PHASE4_RESULT: %d FAIL" % failures)
	_finish()

# Construct a build site to completion by ticking its construction component.
func _construct(sim: Simulation, id: int) -> void:
	var e: Entity = sim.entities.get(id)
	if e == null or e.construction == null:
		return
	var guard: int = 0
	while not e.construction.is_built() and guard < 4000:
		e.construction.tick(1.0 / 15.0)
		guard += 1
	# One extra full sim step so the sim marks it built (emits building_constructed).
	sim.step(1.0 / 15.0)

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
