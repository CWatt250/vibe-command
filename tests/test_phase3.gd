extends SceneTree
## Phase 3 (base building + economy) headless verification.
## Vibe defs (verified): VC-B01 Garage Core (HQ), VC-B03 Generator Bank (powerProduced 10),
## VC-B07 Maker Space (trainsUnits VC-U01/02/03), VC-B05 Server Rack Hall (powerDrawn 4).
##  1. BUILD rejects out-of-radius placement (refunds credits).
##  2. BUILD in-radius creates a build site, construction ticks, emits constructed.
##  3. TRAIN reserves credits, spawns unit at rally after build_time.
##  4. Power brownout slows production; unpowered pauses it.

var _registry: ContentRegistry
var _sim: Simulation
var _events: GameEvents

func _init() -> void:
	_registry = ContentRegistry.new("res://content/data/")
	_registry.load_all()
	_events = GameEvents.new()
	_sim = Simulation.new(_registry, _events, 120, 120)
	_sim.add_player("VC")
	var hq := _sim.spawn_structure("VC-B01", "VC", Vector2(1000, 1000))   # HQ
	var gen := _sim.spawn_structure("VC-B03", "VC", Vector2(1180, 1000))  # powerProduced 10
	var barrack := _sim.spawn_structure("VC-B07", "VC", Vector2(1250, 1000))  # trainsUnits
	assert(hq != -1 and gen != -1 and barrack != -1, "pre-placed structures failed")

	var failures: int = 0
	failures += _test_build_reject_out_of_range()
	failures += _test_build_creates_site_and_constructs()
	failures += _test_train_spawns_unit()
	failures += _test_power_brownout()
	print("PHASE3_RESULT: ", "ALL PASS" if failures == 0 else ("%d FAIL" % failures))
	quit()

## Find a structure of def_id that is NOT yet built (a build site), else any match.
func _find_struct(def_id: String, unbuilt_only: bool = false) -> int:
	for eid in _sim.entities:
		var e = _sim.entities[eid]
		if e.def_id == def_id and e.kind == "structure":
			if unbuilt_only and e.construction != null and e.construction.is_built():
				continue
			return eid
	return -1

func _test_build_reject_out_of_range() -> int:
	var before: float = _sim.get_resources("VC")["credits"]
	_sim.run_commands(0, [{
		"type": "BUILD", "structureDefId": "VC-B03", "position": Vector2(9000, 9000),
		"faction": "VC"
	}])
	var after: float = _sim.get_resources("VC")["credits"]
	if after != before:
		push_error("BUILD out-of-radius should refund (before %f, after %f)" % [before, after])
		return 1
	return 0

func _test_build_creates_site_and_constructs() -> int:
	var before: float = _sim.get_resources("VC")["credits"]
	_sim.run_commands(0, [{
		"type": "BUILD", "structureDefId": "VC-B03", "position": Vector2(1350, 1000),
		"faction": "VC"
	}])
	var id := _find_struct("VC-B03", true)
	if id == -1:
		push_error("BUILD in-radius failed to create an unbuilt site")
		return 1
	var cost: float = _registry.get_structure("VC-B03")["costCredits"]
	var after: float = _sim.get_resources("VC")["credits"]
	if absf((before - after) - cost) > 0.001:
		push_error("BUILD should reserve credits (before %f, after %f, cost %f)" % [before, after, cost])
		return 1
	var built := false
	for i in range(400):
		_sim.step(_sim.TICK_DT)
		var e = _sim.entities.get(id)
		if e != null and e.construction != null and e.construction.is_built():
			built = true
			break
	if not built:
		push_error("build site never completed construction")
		return 1
	return 0

func _test_train_spawns_unit() -> int:
	var barrack_id := _find_struct("VC-B07")
	_sim.run_commands(0, [{"type": "SET_RALLY", "entityIds": [barrack_id], "position": Vector2(1420, 1000)}])
	_sim.run_commands(0, [{"type": "TRAIN", "entityIds": [barrack_id], "unitDefId": "VC-U01"}])
	var spawned := false
	for i in range(320):
		_sim.step(_sim.TICK_DT)
		for eid in _sim.entities:
			var e = _sim.entities[eid]
			if e.def_id == "VC-U01" and e.kind == "unit":
				spawned = true
				break
		if spawned:
			break
	if not spawned:
		push_error("TRAIN never spawned VC-U01 at rally")
		return 1
	return 0

func _test_power_brownout() -> int:
	var barrack_id := _find_struct("VC-B07")
	var b = _sim.entities[barrack_id]
	if b.production == null:
		push_error("barrack has no production component")
		return 1
	if b.production.speed_scale != 1.0:
		push_error("expected powered speed_scale 1.0, got %f" % b.production.speed_scale)
		return 1
	# Destroy generator (powerProduced 10) so remaining draw (compute VC-B05) > 0 produced.
	for eid in _sim.entities.keys():
		var e = _sim.entities[eid]
		if e.def_id == "VC-B03" and e.kind == "structure":
			_sim.remove_entity(eid)
	var comp_id := _sim.spawn_structure("VC-B05", "VC", Vector2(1450, 1000))  # powerDrawn 4
	assert(comp_id != -1, "compute spawn failed")
	_sim.step(_sim.TICK_DT)
	_sim.step(_sim.TICK_DT)
	b = _sim.entities[barrack_id]
	if b.production.speed_scale != 0.0:
		push_error("expected critical brownout scale 0.0, got %f" % b.production.speed_scale)
		return 1
	return 0
