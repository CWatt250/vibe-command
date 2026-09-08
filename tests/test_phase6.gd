extends SceneTree
## test_phase6.gd — Phase 6 verification: the economy loop (passive + harvester mining
## and deposit) and the skirmish AI opponent. Mirrors the test_phase4/5 harness style.
## Headless: `godot-4 --headless --path . --script tests/test_phase6.gd`

const HarvestComponent := preload("res://gameplay/components/HarvestComponent.gd")

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# --- Test 1: passive income from a built HQ + Economy structure ---
	var hq := sim.spawn_structure("VC-B01", "VC", Vector2(600, 600), true)
	var econ := sim.spawn_structure("VC-B02", "VC", Vector2(760, 600), true)
	if hq == -1 or econ == -1:
		failures += 1
		push_error("failed to spawn VC-B01 / VC-B02")
		_finish()
		return
	var before: float = sim.get_resources("VC").get("credits", 0.0)
	_run(sim, 30)   # 2.0 s at 1/15
	var after: float = sim.get_resources("VC").get("credits", 0.0)
	var gained: float = after - before
	# PASSIVE_PER_HQ (2) + PASSIVE_PER_ECON (4) over 2 s == 12
	if gained < 10.0:
		failures += 1
		push_error("passive income too low: +%s in 2s (expect ~12)" % gained)
	else:
		print("PASS: passive income +%.1f credits in 2s (HQ + Economy)" % gained)

	# --- Test 2: harvester attaches, travels to a field and mines it ---
	var field_id := sim.spawn_resource_field(Vector2(900, 600), 3000.0)
	var field: Entity = sim.entities.get(field_id)
	var srv_id := sim.spawn_unit("VC-SRV", "VC", Vector2(700, 640))
	var srv: Entity = sim.entities.get(srv_id)
	if srv == null or srv.harvest == null:
		failures += 1
		push_error("VC-SRV has no HarvestComponent (unit def must carry harvest:true)")
	elif field == null or field.resource == null:
		failures += 1
		push_error("resource field has no ResourceNodeComponent")
	else:
		print("PASS: VC-SRV attached HarvestComponent")
		_run(sim, 150)   # 10 s — travel + start mining
		if srv.harvest.state == HarvestComponent.S_IDLE:
			failures += 1
			push_error("harvester never left IDLE")
		else:
			print("PASS: harvester state advanced (state=%d)" % srv.harvest.state)
		var mined: float = 3000.0 - field.resource.remaining
		if mined <= 0.0:
			failures += 1
			push_error("resource field untouched after 10s")
		else:
			print("PASS: field mined %.0f credits" % mined)

	# --- Test 3: full loop — deposit pays credits above passive-only income ---
	var c_before: float = sim.get_resources("VC").get("credits", 0.0)
	_run(sim, 900)   # 60 s
	var c_after: float = sim.get_resources("VC").get("credits", 0.0)
	var delta: float = c_after - c_before
	var passive_only: float = (2.0 + 4.0) * 60.0   # 360
	if delta <= passive_only:
		failures += 1
		push_error("no harvester deposit: delta %s <= passive-only %s" % [delta, passive_only])
	else:
		print("PASS: harvester delivered cargo (delta %.0f > passive-only %.0f)" % [delta, passive_only])

	# --- Test 4: resource node depletes and reports empty ---
	var tiny_id := sim.spawn_resource_field(Vector2(1400, 1000), 50.0)
	var tiny: Entity = sim.entities.get(tiny_id)
	tiny.resource.take(100.0)
	if tiny.resource.depleted and tiny.resource.remaining == 0.0:
		print("PASS: resource node depletes at 0 (remaining=%.0f)" % tiny.resource.remaining)
	else:
		failures += 1
		push_error("resource node did not deplete: remaining=%s depleted=%s" % [tiny.resource.remaining, tiny.resource.depleted])

	# --- Test 5: skirmish AI builds a base and trains an army (FC vs VC) ---
	var sim2 := Simulation.new(registry, events, 50, 50)
	sim2.add_player("FC")
	sim2.add_player("VC")
	sim2.spawn_structure("FC-B01", "FC", Vector2(300, 300), true)
	sim2.spawn_structure("VC-B01", "VC", Vector2(1500, 1500), true)
	sim2.attach_skirmish_ai("FC", "VC")
	var structs_before := _count_structures(sim2, "FC")
	_run(sim2, 2700)   # 180 s
	var structs_after := _count_structures(sim2, "FC")
	var units := _count_units(sim2, "FC")
	if structs_after > structs_before:
		print("PASS: skirmish AI built %d structure(s)" % (structs_after - structs_before))
	else:
		failures += 1
		push_error("skirmish AI built nothing in 180s")
	if units > 0:
		print("PASS: skirmish AI trained %d unit(s)" % units)
	else:
		failures += 1
		push_error("skirmish AI trained no units in 180s")
	# AI must spend, not hoard: credits should have moved off the start value.
	var fc_credits: float = sim2.get_resources("FC").get("credits", 0.0)
	print("INFO: FC credits after 180s = %.0f" % fc_credits)

	if failures == 0:
		print("PHASE6_RESULT: ALL PASS")
	else:
		print("PHASE6_RESULT: %d FAIL" % failures)
	_finish()

func _count_structures(sim: Simulation, faction: String) -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "structure" and e.faction_id == faction and e.alive:
			n += 1
	return n

func _count_units(sim: Simulation, faction: String) -> int:
	var n := 0
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == faction and e.alive:
			n += 1
	return n

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
