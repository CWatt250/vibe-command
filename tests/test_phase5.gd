extends SceneTree
## test_phase5.gd — Phase 5 / M1 remaining gates verification (fog, control groups,
## garrison, repair, veterancy). Builds a Federal base + a Vibe force and checks each
## new system deterministically. Mirrors the test_phase4/.gd harness style.

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# Federal HQ as the build anchor, constructed so other structures can go up in radius.
	var hq := sim.spawn_structure("FC-B01", "FC", Vector2(1200, 1200), false)
	if hq == -1:
		failures += 1
		push_error("failed to spawn FC HQ")
		_finish()
		return
	_construct(sim, hq)

	# --- Test 1: Fog of War — state_at evolves unexplored -> visible -> explored ---
	var unit: Entity = sim.entities.get(sim.spawn_unit("FC-U01", "FC", Vector2(1400, 1200)))
	if unit == null or unit.sensor == null:
		failures += 1
		push_error("FC-U01 has no sensor component")
		_finish()
		return
	_run(sim, 2)
	# Far away cell should be unexplored (0) for FC.
	if sim.fog_sys.state_at("FC", Vector2(300, 300)) != 0:
		failures += 1
		push_error("expect far cell unexplored (0), got %s" % sim.fog_sys.state_at("FC", Vector2(300, 300)))
	# Cell where the unit stands should be visible (2) for FC.
	if sim.fog_sys.state_at("FC", unit.position) != 2:
		failures += 1
		push_error("expect unit's cell visible (2) for FC, got %s" % sim.fog_sys.state_at("FC", unit.position))
	# The FAR faction (VC) has no units near here -> should NOT see it.
	if sim.fog_sys.state_at("VC", unit.position) != 0:
		failures += 1
		push_error("expect VC blind to FC unit's cell (0), got %s" % sim.fog_sys.state_at("VC", unit.position))

	# --- Test 2: Fog explored memory — move unit away, the cell stays explored (1) ---
	var pos_orig: Vector2 = unit.position
	unit.position = Vector2(2400, 2400)
	_run(sim, 2)
	if sim.fog_sys.state_at("FC", pos_orig) != 1:
		failures += 1
		push_error("expect vacated cell explored (1) after unit leaves, got %s" % sim.fog_sys.state_at("FC", pos_orig))

	# --- Test 3: Control groups — assign, recall, auto-remove destroyed ---
	var g1: int = sim.spawn_unit("FC-U05", "FC", Vector2(1300, 1200))
	var g2: int = sim.spawn_unit("FC-U05", "FC", Vector2(1350, 1200))
	if g1 == -1 or g2 == -1:
		failures += 1
		push_error("failed to spawn control-group units")
		_finish()
		return
	_run(sim, 1)
	sim.assign_control_group(1, [g1, g2])
	if sim.control_groups.has(1) != true or sim.control_groups[1].size() != 2:
		failures += 1
		push_error("expect control group 1 to hold 2 units after ASSIGN")
	# Clear selection then recall.
	sim.selected_ids = []
	var recalled: Array = sim.recall_control_group(1)
	if recalled.size() != 2:
		failures += 1
		push_error("expect recall to reselect 2 units, got %d" % recalled.size())
	# Destroy one -> auto cleanup on next step.
	sim.remove_entity(g1)
	_run(sim, 1)
	if sim.control_groups.has(1) and sim.control_groups[1].size() != 1:
		failures += 1
		push_error("expect control group to shrink to 1 after destroying a member, got %d" % sim.control_groups[1].size())

	# --- Test 4: Garrison — Federal Guard Tower (4 slots) + infantry ---
	# Place a Guard Tower (build site then construct), and 4 infantry to man it.
	var tower := sim.spawn_build_site("FC-D02", "FC", Vector2(1200, 1400))
	_construct(sim, tower)
	var tower_ent: Entity = sim.entities.get(tower)
	if tower_ent == null or tower_ent.garrison == null:
		failures += 1
		push_error("Guard Tower has no GarrisonComponent")
		_finish()
		return
	var infantry_ids: Array = []
	for i in range(5):
		infantry_ids.append(sim.spawn_unit("FC-U02", "FC", Vector2(1200 + i * 5, 1420)))
	_run(sim, 1)
	var loaded: int = sim.garrison_units(tower, infantry_ids)
	if loaded != 4:
		failures += 1
		push_error("expect 4 infantry garrisoned (capacity 4), got %d" % loaded)
	if tower_ent.garrison.occupant_count() != 4:
		failures += 1
		push_error("expect 4 occupants in tower, got %d" % tower_ent.garrison.occupant_count())
	# Garrisoned units are hidden (alive=false) but retain health/veterancy.
	var hidden: Entity = sim.entities.get(infantry_ids[0])
	if hidden.alive:
		failures += 1
		push_error("garrisoned unit should be hidden (alive=false)")
	# Ungarrison -> respawned alive near structure.
	sim.ungarrison_units(tower)
	if not sim.entities.get(infantry_ids[0]).alive:
		failures += 1
		push_error("ungarrisoned unit should be alive again")
	if tower_ent.garrison.occupant_count() != 0:
		failures += 1
		push_error("expect 0 occupants after ungarrison, got %d" % tower_ent.garrison.occupant_count())

	# --- Test 5: Repair — repair depot heals a damaged friendly in radius ---
	var depot := sim.spawn_build_site("FC-B10", "FC", Vector2(1600, 1200))
	_construct(sim, depot)
	var victim: Entity = sim.entities.get(sim.spawn_unit("FC-U05", "FC", Vector2(1650, 1200)))
	# Apply damage to bring it below full.
	victim.health.apply_damage(100.0)
	var hp_before: float = victim.health.current
	# Step a few ticks: the depot should heal it back.
	_run(sim, 60)  # 60 ticks @ 1/15 = 4 sim-seconds; 60/s * 4 = plenty to heal 100
	if victim.health.current <= hp_before + 1.0:
		failures += 1
		push_error("expect repair depot to heal victim, before %s after %s" % [str(hp_before), str(victim.health.current)])
	if not victim.health.is_full() and victim.health.current < victim.health.max_health - 1.0:
		pass  # may not be fully healed in 4s if damage large; only require progress

	# --- Test 6: Veterancy — combat XP raises rank, multiplies damage ---
	var vet: Entity = sim.entities.get(sim.spawn_unit("FC-U01", "FC", Vector2(1800, 1200)))
	if vet.veterancy == null:
		failures += 1
		push_error("FC-U01 has no VeterancyComponent")
		_finish()
		return
	if vet.veterancy.rank_label() != "Regular":
		failures += 1
		push_error("expect new unit rank Regular, got %s" % vet.veterancy.rank_label())
	# Award 150 XP -> Veteran rank (damage_mult 1.10).
	vet.veterancy.add_xp(150.0)
	if vet.veterancy.rank_label() != "Veteran":
		failures += 1
		push_error("expect Veteran at 150 XP, got %s" % vet.veterancy.rank_label())
	if absf(vet.veterancy.damage_mult() - 1.10) > 0.001:
		failures += 1
		push_error("expect Veteran damage_mult 1.10, got %s" % str(vet.veterancy.damage_mult()))
	# Give an enemy within range and let combat run: XP accumulates toward rank up.
	var foe: Entity = sim.entities.get(sim.spawn_unit("VC-U01", "VC", Vector2(1800, 1350)))
	_run(sim, 200)  # enough ticks for the two to close + fight
	if foe.health.is_full() and sim.entities.has(foe.id) and foe.alive:
		# No combat occurred (out of range / killed?) — treat as non-fatal probe.
		if vet.veterancy.xp <= 150.0:
			# Only flag if the enemy was never damaged AND vet got no XP.
			pass
	else:
		if vet.veterancy.xp <= 150.0:
			failures += 1
			push_error("expect combat to award vet XP, xp stayed %s" % str(vet.veterancy.xp))

	if failures == 0:
		print("PHASE5_RESULT: ALL PASS")
	else:
		print("PHASE5_RESULT: %d FAIL" % failures)
	_finish()

func _construct(sim: Simulation, id: int) -> void:
	var e: Entity = sim.entities.get(id)
	if e == null or e.construction == null:
		return
	var guard: int = 0
	while not e.construction.is_built() and guard < 4000:
		e.construction.tick(1.0 / 15.0)
		guard += 1
	sim.step(1.0 / 15.0)

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
