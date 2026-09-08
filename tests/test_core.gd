extends SceneTree
## Headless smoke test for the VIBE COMMAND core simulation.
## Run:  godot-4 --headless --script res://tests/test_core.gd
## Verifies: content loads, entities spawn, MOVE order paths units, armor damage model,
## combat auto-acquires and kills an enemy.

func _init() -> void:
	var errors := 0

	# 1. Content registry
	var registry := ContentRegistry.new("res://content/data")
	registry.load_all()
	if registry.all_units().is_empty():
		print("FAIL: registry units empty")
		errors += 1
	else:
		print("PASS: registry units=", registry.all_units().size(), " structures=", registry.all_structures().size(), " weapons=", registry.all_weapons().size())

	# 2. Simulation (owns its CombatSystem per Blueprint §2 — authoritative)
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 40, 40)
	sim.add_player("VC")
	sim.add_player("FC")

	# 3. Spawn 3 VC infantry
	var u1 := sim.spawn_unit("VC-U01", "VC", Vector2(80, 80))
	var u2 := sim.spawn_unit("VC-U01", "VC", Vector2(90, 90))
	var u3 := sim.spawn_unit("VC-U01", "VC", Vector2(100, 80))
	if u1 < 1 or u2 < 1 or u3 < 1:
		print("FAIL: spawn returned ", u1, "/", u2, "/", u3)
		errors += 1
	else:
		print("PASS: spawned ", u1, u2, u3)

	# 4. MOVE order — group of 3 to a far destination (A* + non-stacking)
	var dest := Vector2(800, 700)
	sim.run_commands(0, [{"type":"MOVE","entityIds":[u1,u2,u3],"targetPosition":dest}])
	var reached := 0
	var start := Time.get_ticks_usec()
	for t in range(15 * 60):
		sim.step(sim.TICK_DT)
		var m1: Entity = sim.entities.get(u1)
		if m1 != null and m1.position.distance_to(dest) <= 30.0:
			reached = 1
			break
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	if reached == 1:
		print("PASS: move order reached destination in ", ms, " ms; u1 pos=", sim.entities.get(u1).position)
	else:
		print("FAIL: move order did not reach dest; u1 dist=", sim.entities.get(u1).position.distance_to(dest))
		errors += 1

	# 5. Combat: three VC infantry auto-acquire & destroy one FC (FC-U01 is tankier, HD110).
	# Prove auto-acquire + damage + destruction with real firepower.
	var a := sim.spawn_unit("VC-U01", "VC", Vector2(400, 400))
	var a2 := sim.spawn_unit("VC-U01", "VC", Vector2(410, 395))
	var a3 := sim.spawn_unit("VC-U01", "VC", Vector2(395, 405))
	var b := sim.spawn_unit("FC-U01", "FC", Vector2(430, 410))  # ~31 units out, in range
	var b_health = sim.entities.get(b).health
	var b_max: float = b_health.max_health
	b_health.current = b_max  # ensure full
	var enemy_died := false
	for t in range(30 * 60):  # up to 30s
		sim.step(sim.TICK_DT)
		var eb: Entity = sim.entities.get(b)
		if eb == null:
			enemy_died = true
			break
	if enemy_died:
		print("PASS: 3x VC auto-acquired & DESTROYED FC-U01 (targeting, damage, death all work)")
	else:
		print("FAIL: enemy survived; hp=", sim.entities.get(b).health.current, "/", b_max)
		errors += 1

	# 6. Armor multiplier
	var mult := registry.armor_multiplier("SmallArms", "Infantry")
	if mult >= 0.9:
		print("PASS: armor multiplier SmallArms->Infantry=", mult)
	else:
		print("FAIL: armor mult ", mult)
		errors += 1

	print("RESULT: ", "ALL PASS" if errors == 0 else ("FAILURES=" + str(errors)))
	quit(0 if errors == 0 else 1)
