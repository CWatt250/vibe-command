extends SceneTree
## test_p4_04_armed_commands.gd — p4-04: SelectionInput armed command mode (A / S / G / Escape /
## right-click cancel) drives pure calls with no viewport, and the dicts it emits are accepted
## by Simulation.run_commands. Headless: `godot-4 --headless --path . --script tests/test_p4_04_armed_commands.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")
	sim.selected_faction = "VC"

	var si := SelectionInput.new(null, sim)   # camera unused by the pure calls
	var got: Array = []            # every orders_issued payload, in order
	var armed_log: Array = []      # every armed_changed mode
	si.orders_issued.connect(func(orders: Array) -> void: got.append(orders))
	si.armed_changed.connect(func(mode: int) -> void: armed_log.append(mode))
	# Mirror Game._on_selection: the sim owns the selection.
	si.selection_changed.connect(func(ids: Array) -> void: sim.selected_ids = ids)

	var u := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1500))
	var e: Entity = sim.entities[u]
	_check(u >= 0 and e.weapon != null and e.movement != null, "premise: VC-U04 spawned with weapon + movement")

	# --- nothing selected: keys do nothing, nothing armed, nothing emitted ---
	_check(not si.handle_key(KEY_A) and si.armed == SelectionInput.Armed.NONE, "A with no selection does not arm")
	_check(not si.handle_key(KEY_S) and not si.handle_key(KEY_G) and got.is_empty(), "S / G with no selection emit nothing")
	_check(not si.handle_escape(), "Escape with nothing armed or selected is not consumed (falls through to PauseMenu)")
	_check(not si.handle_left_click(Vector2(100, 100)) and got.is_empty(), "left click while unarmed is not consumed")

	# --- A then left click -> ATTACK_MOVE for the selection ---
	sim.selected_ids = [u]
	_check(si.handle_key(KEY_A) and si.armed == SelectionInput.Armed.ATTACK_MOVE, "A arms ATTACK_MOVE")
	_check(armed_log == [SelectionInput.Armed.ATTACK_MOVE], "armed_changed emitted ATTACK_MOVE once")
	_check(si.handle_key(KEY_A) and armed_log.size() == 1, "second A is idempotent (no second signal)")
	_check(si.handle_left_click(Vector2(1400, 1500)), "armed left click is consumed")
	_check(si.armed == SelectionInput.Armed.NONE and armed_log == [SelectionInput.Armed.ATTACK_MOVE, SelectionInput.Armed.NONE],
		"click disarms and signals NONE")
	_check(got.size() == 1 and got[0] == [{"type": "ATTACK_MOVE", "entityIds": [u], "targetPosition": Vector2(1400, 1500)}],
		"A+click emits exactly the ATTACK_MOVE dict (%s)" % str(got))
	sim.run_commands(0, got[0])
	_check(e.order == Entity.Order.ATTACK_MOVE and e.order_dest == Vector2(1400, 1500) and e.movement.is_moving(),
		"sim accepts it: order ATTACK_MOVE toward the click, moving")

	# --- S -> STOP ---
	_check(si.handle_key(KEY_S), "S is consumed with a selection")
	_check(got.size() == 2 and got[1] == [{"type": "STOP", "entityIds": [u]}], "S emits exactly the STOP dict (%s)" % str(got[1]))
	sim.run_commands(0, got[1])
	_check(e.order == Entity.Order.IDLE and not e.movement.is_moving() and e.weapon.current_target_id == -1,
		"sim accepts STOP: IDLE, path cleared, target cleared")

	# --- G -> HOLD (= guard: stay put, engage anything in range, never chase) ---
	_check(si.handle_key(KEY_G), "G is consumed with a selection")
	_check(got.size() == 3 and got[2] == [{"type": "HOLD", "entityIds": [u]}], "G emits exactly the HOLD dict (%s)" % str(got[2]))
	sim.run_commands(0, got[2])
	_check(e.order == Entity.Order.HOLD and not e.movement.is_moving(), "sim accepts HOLD: order HOLD, not moving")
	# VC-U04 wpn_autocannon range 160 (tests/test_phase7.gd:150): an enemy 60 px away is in range.
	var enemy := sim.spawn_unit("FC-U01", "FC", Vector2(660, 1500))
	_run(sim, 20)
	_check(e.order == Entity.Order.HOLD and not e.movement.is_moving(), "guard held position for 20 ticks")
	_check(e.weapon.current_target_id == enemy or not sim.entities.has(enemy), "guard engaged the enemy in range")

	# --- Escape: cancels armed first, then deselects, then falls through ---
	var n_before := got.size()
	_check(si.handle_key(KEY_A) and si.armed == SelectionInput.Armed.ATTACK_MOVE, "re-armed for the Escape test")
	_check(si.handle_escape() and si.armed == SelectionInput.Armed.NONE and got.size() == n_before,
		"Escape cancels the armed mode and emits no order")
	_check(sim.selected_ids == [u], "Escape-cancel keeps the selection")
	_check(si.handle_escape() and sim.selected_ids.is_empty(), "second Escape deselects (selection_changed([]))")
	_check(not si.handle_escape(), "third Escape is not consumed")

	# --- right click: cancels armed and issues nothing; unarmed right click is the context order ---
	sim.selected_ids = [u]
	si.handle_key(KEY_A)
	si.handle_right_click(Vector2(700, 1500))
	_check(si.armed == SelectionInput.Armed.NONE and got.size() == n_before, "right click cancels the armed mode without ordering")
	si.handle_right_click(Vector2(700, 1500))
	_check(got.size() == n_before + 1 and got.back()[0]["type"] == "MOVE", "unarmed right click still issues the context MOVE")

	# --- armed, then the selection vanished before the click: consumed, nothing emitted ---
	si.handle_key(KEY_A)
	sim.selected_ids = []
	_check(si.handle_left_click(Vector2(1400, 1500)) and got.size() == n_before + 1 and si.armed == SelectionInput.Armed.NONE,
		"armed click with an emptied selection is swallowed, not ordered")

	si.free()   # Node2D never entered the tree; free it so quit() doesn't report a leak
	if failures == 0:
		print("P4_04_RESULT: ALL PASS")
	else:
		print("P4_04_RESULT: %d FAILURE(S)" % failures)
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

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)
