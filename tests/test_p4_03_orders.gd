extends SceneTree
## test_p4_03_orders.gd — p4-03: Shift order queue (Entity.order_queue) + control-group sim facts.
## Headless: `godot-4 --headless --path . --script tests/test_p4_03_orders.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# --- 1. Two queued MOVEs: reach the first, then the second ---
	# VC-U04 = prof_vehicle_fast, 120 px/s: each 200 px leg is under 2 s (30 ticks).
	var u := sim.spawn_unit("VC-U04", "VC", Vector2(400, 400))
	var a := Vector2(600, 400)
	var b := Vector2(600, 600)
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [u], "targetPosition": a}])
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [u], "targetPosition": b, "queue": true}])
	var e: Entity = sim.entities[u]
	_check(e.order == Entity.Order.MOVE and e.order_dest == a, "first MOVE is active")
	_check(e.order_queue.size() == 1 and e.order_queue[0]["targetPosition"] == b, "second MOVE is queued")
	var popped_at_a := false
	for i in range(120):
		sim.step(1.0 / 15.0)
		if e.order_dest == b:
			popped_at_a = e.position.distance_to(a) <= e.movement.footprint_radius
			break
	_check(popped_at_a, "queue popped when the unit arrived at the first dest (pos %s)" % e.position)
	_check(e.order == Entity.Order.MOVE and e.order_queue.is_empty(), "second MOVE active, queue empty")
	_run(sim, 60)
	# MovementComponent.update drops the last waypoint once inside footprint_radius (9 px for this
	# profile), so "arrived" is measured against that, not the old 4 px.
	_check(e.order == Entity.Order.IDLE and e.position.distance_to(b) <= e.movement.footprint_radius,
		"arrived at the second dest and went IDLE (pos %s)" % e.position)

	# --- 2. Queued ATTACK after a MOVE ---
	# Victim 100 px past the MOVE dest: inside VC-U04 vision (250) and wpn_autocannon range (160).
	var atk := sim.spawn_unit("VC-U04", "VC", Vector2(400, 900))
	var victim := sim.spawn_unit("FC-U01", "FC", Vector2(600, 900))
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [atk], "targetPosition": Vector2(500, 900)}])
	sim.run_commands(0, [{"type": "ATTACK", "entityIds": [atk], "targetEntityId": victim, "queue": true}])
	var ae: Entity = sim.entities[atk]
	_check(ae.order == Entity.Order.MOVE and ae.order_queue.size() == 1
		and ae.order_queue[0]["targetEntityId"] == victim, "ATTACK queued behind MOVE")
	var popped_attack := false
	for i in range(120):
		sim.step(1.0 / 15.0)
		if ae.order == Entity.Order.ATTACK:
			popped_attack = true
			break
	_check(popped_attack and ae.order_target == victim and ae.weapon.current_target_id == victim,
		"queued ATTACK popped after the MOVE with the right target")
	_check(ae.position.distance_to(Vector2(500, 900)) <= ae.movement.footprint_radius,
		"the MOVE completed before the ATTACK started")

	# --- 3. A fresh non-queued order clears the queue ---
	var c := sim.spawn_unit("VC-U04", "VC", Vector2(400, 1200))
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1200)}])
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1300), "queue": true}])
	sim.run_commands(0, [{"type": "ATTACK_MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1400), "queue": true}])
	var ce: Entity = sim.entities[c]
	_check(ce.order_queue.size() == 2 and ce.order_queue[1]["type"] == "ATTACK_MOVE", "two orders queued in order")
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(500, 1200)}])
	_check(ce.order_queue.is_empty() and ce.order_dest == Vector2(500, 1200), "non-queued MOVE replaced the queue")

	# --- 4. STOP / HOLD clear the queue ---
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1200), "queue": true}])
	_check(ce.order_queue.size() == 1, "premise: one order queued behind the active MOVE")
	sim.run_commands(0, [{"type": "STOP", "entityIds": [c]}])
	_check(ce.order_queue.is_empty() and ce.order == Entity.Order.IDLE, "STOP cleared the queue")
	_run(sim, 3)
	_check(ce.order == Entity.Order.IDLE and not ce.movement.is_moving(), "nothing popped after STOP")
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1200)}])
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [c], "targetPosition": Vector2(900, 1300), "queue": true}])
	sim.run_commands(0, [{"type": "HOLD", "entityIds": [c]}])
	_check(ce.order_queue.is_empty() and ce.order == Entity.Order.HOLD, "HOLD cleared the queue")
	_run(sim, 3)
	_check(ce.order == Entity.Order.HOLD, "HOLD stays HOLD (nothing pops)")

	# --- 5. Shift-order on an idle unit runs immediately ---
	var idle := sim.spawn_unit("VC-U04", "VC", Vector2(400, 1500))
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [idle], "targetPosition": Vector2(600, 1500), "queue": true}])
	var ie: Entity = sim.entities[idle]
	_check(ie.order == Entity.Order.MOVE and ie.order_queue.is_empty(), "queued order on an idle unit runs now")

	# --- 6. Queued group move keeps per-unit formation slots ---
	var g1 := sim.spawn_unit("VC-U01", "VC", Vector2(400, 1700))
	var g2 := sim.spawn_unit("VC-U01", "VC", Vector2(420, 1700))
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [g1, g2], "targetPosition": Vector2(700, 1700)}])
	sim.run_commands(0, [{"type": "MOVE", "entityIds": [g1, g2], "targetPosition": Vector2(700, 1800), "queue": true}])
	var q1: Vector2 = sim.entities[g1].order_queue[0]["targetPosition"]
	var q2: Vector2 = sim.entities[g2].order_queue[0]["targetPosition"]
	_check(q1 != q2 and q1.distance_to(Vector2(700, 1800)) < 30.0,
		"queued group move stores per-unit formation slots (%s vs %s)" % [q1, q2])

	# --- 7. Control groups (existing sim, Simulation.gd control_groups): assign / cleanup / overwrite ---
	sim.run_commands(0, [{"type": "CONTROL_ASSIGN", "group": 1, "entityIds": [g1, g2]}])
	_check(sim.control_groups[1] == [g1, g2], "CONTROL_ASSIGN stored both ids")
	sim.remove_entity(g2)
	_run(sim, 1)
	_check(sim.control_groups[1] == [g1], "dead member dropped by _cleanup_control_groups on the next step")
	sim.run_commands(0, [{"type": "CONTROL_ASSIGN", "group": 1, "entityIds": [idle]}])
	_check(sim.control_groups[1] == [idle], "reassign overwrites the group")
	sim.run_commands(0, [{"type": "CONTROL_ASSIGN", "group": 1, "entityIds": []}])
	_check(sim.control_groups.has(1) and sim.control_groups[1].is_empty(), "assign with an empty selection empties the group")

	if failures == 0:
		print("P4_03_RESULT: ALL PASS")
	else:
		print("P4_03_RESULT: %d FAILURE(S)" % failures)
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
