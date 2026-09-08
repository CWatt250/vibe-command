extends SceneTree
## test_phase4_fed.gd — Phase 4 (federal) Command Capacity gate verification (§6.2).
## Verifies the FEDERAL differentiator is a PRODUCTION GUARD: command deficit blocks
## enqueueing new elite units (reserveCapacity > 0), unlike Compute's debuff.
## Uses verified FC content IDs from content/data + the Faction Bible.

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 60, 60)
	sim.add_player("FC")

	# --- FC HQ (FC-B01 Continuity HQ, commandCapacity 20) as the build anchor ---
	var hq := sim.spawn_structure("FC-B01", "FC", Vector2(1200, 1200), false)
	if hq == -1:
		failures += 1
		push_error("failed to spawn FC HQ")
		_finish()
		return
	_construct(sim, hq)

	# --- Motor Pool (FC-B05) trains all FC vehicles incl. T2 elites ---
	var pool := sim.spawn_build_site("FC-B05", "FC", Vector2(1050, 1200))
	_construct(sim, pool)

	# Big credit pool so the only practical limit is the Command gate.
	sim.add_credits("FC", 60000.0)

	# --- Test 1: command state with only the HQ -> capacity 20, reserved 0 ---
	var c0: Dictionary = sim.command_sys._compute(sim.entities, "FC")
	if c0["capacity"] != 20.0:
		failures += 1
		push_error("expect capacity 20 from HQ, got %s" % str(c0["capacity"]))
	if not sim.command_sys.can_produce(c0, 0.0):
		failures += 1
		push_error("ordinary unit (reserve 0) must be producible with no command shortfall")

	# --- Test 2: MBT (FC-U07, reserve 3) — HQ cap 20 gates ~6 before blocking ---
	var mbt := _train(sim, pool, "FC-U07", 9)
	if mbt < 1:
		failures += 1
		push_error("expected at least one MBT enqueue, got %d" % mbt)
	if mbt > 6:
		failures += 1
		push_error("expected command gate to stop MBTs around 6 (cap 20 / 3 each), got %d" % mbt)

	# --- Test 3: ordinary unit (FC-U05 Humvee, reserve 0) NEVER blocked under saturation ---
	var ord := _train(sim, pool, "FC-U05", 2)
	if ord != 2:
		failures += 1
		push_error("ordinary Humvee must enqueue even under command saturation, got %d" % ord)

	# --- Test 4: Command Post (FC-B09, +20) raises capacity to 40 ---
	var cp := sim.spawn_build_site("FC-B09", "FC", Vector2(1050, 1300))
	_construct(sim, cp)
	var c1: Dictionary = sim.command_sys._compute(sim.entities, "FC")
	if c1["capacity"] != 40.0:
		failures += 1
		push_error("expect capacity 40 with HQ+Command Post, got %s" % str(c1["capacity"]))

	# --- Test 5: destroying the Command Post restores cap 20 and blocks a new elite ---
	sim.remove_entity(cp)
	var c2: Dictionary = sim.command_sys._compute(sim.entities, "FC")
	if c2["capacity"] != 20.0:
		failures += 1
		push_error("expect capacity 20 after Command Post destroyed, got %s" % str(c2["capacity"]))
	var extra := _train(sim, pool, "FC-U07", 1)
	if extra != 0:
		failures += 1
		push_error("expect blocked elite enqueue after cap shrinks below reserve, got %d" % extra)

	if failures == 0:
		print("PHASE4_FED_RESULT: ALL PASS")
	else:
		print("PHASE4_FED_RESULT: %d FAIL" % failures)
	_finish()

## Train `count` of `unit_id` on `producer` via run_commands; returns # enqueued.
## The command gate may block some (elite) enqueues; ordinary never blocked.
func _train(sim: Simulation, producer: int, unit_id: String, count: int) -> int:
	var made: int = 0
	for i in range(count):
		var pe: Entity = sim.entities.get(producer)
		var before: int = 0
		if pe != null and pe.production != null:
			before = pe.production.queue_size()
		var cmd := {"type": "TRAIN", "entityIds": [producer], "unitDefId": unit_id}
		sim.run_commands(producer, [cmd])
		var after: int = 0
		if pe != null and pe.production != null:
			after = pe.production.queue_size()
		if after > before:
			made += 1
	return made

func _construct(sim: Simulation, id: int) -> void:
	var e: Entity = sim.entities.get(id)
	if e == null or e.construction == null:
		return
	var guard: int = 0
	while not e.construction.is_built() and guard < 4000:
		e.construction.tick(1.0 / 15.0)
		guard += 1
	sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
