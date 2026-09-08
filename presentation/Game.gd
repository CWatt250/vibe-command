extends Node2D
## Vibe Command — Milestone 0 Combat Sandbox game scene.
## Wires the pure-logic simulation to the presentation layer (camera, input, render),
## builds an industrial skirmish map, spawns a starting Vibe Coder force, and drives
## the fixed-tick sim loop. This is the playable entry point.

const TICK_RATE: float = 30.0   # sim steps per second

var registry: ContentRegistry
var events: GameEvents
var sim: Simulation

var rts_cam: RTSCamera
var selection_input: SelectionInput
var map_renderer: MapRenderer
var entity_renderer: EntityRenderer

var _accum: float = 0.0
var _world: Vector2 = Vector2(2000, 2000)
var _frame: int = 0
var _capture_at: int = -1
var _capture_out: String = ""

func _ready() -> void:
	# Load content
	registry = ContentRegistry.new("res://content/data")
	registry.load_all()
	events = GameEvents.new()
	add_child(events)

	# Build simulation world (50x50 cells at 40u = 2000u world)
	var grid = NavGrid.new(50, 50)
	sim = Simulation.new(registry, events, 50, 50)

	# Build the industrial map: roads + scattered blocked structures
	_build_map(grid)

	# Camera
	rts_cam = RTSCamera.new()
	rts_cam.set_world_size(_world.x, _world.y)
	rts_cam.position = Vector2(1230, 1230)  # frame both factions' starts
	add_child(rts_cam)

	# Presenters
	map_renderer = MapRenderer.new()
	map_renderer.setup(grid, 50, 50, NavGrid.CELL)
	add_child(map_renderer)
	entity_renderer = EntityRenderer.new(sim, rts_cam)
	add_child(entity_renderer)

	# Input
	selection_input = SelectionInput.new(rts_cam, sim)
	add_child(selection_input)
	selection_input.orders_issued.connect(_on_orders)
	selection_input.selection_changed.connect(_on_selection)

	# Spawn starter forces: 12 Vibe Coder infantry + a Garage Core (Vibe base)
	_spawn_starter_force()

	events.game_tick.connect(_on_game_tick)

	# Optional screenshot capture: godot -- --capture=/abs/out.png [--frame=N]
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--capture="):
			_capture_out = a.trim_prefix("--capture=")
		elif a.begins_with("--frame="):
			_capture_at = int(a.trim_prefix("--frame="))
	if _capture_at < 0:
		_capture_at = 180

func _build_map(grid: NavGrid) -> void:
	sim.grid_map = grid
	# Sprinkle building footprints / rubble across the map for cover + pathing interest.
	# Cells 2 = blocked; render dark.
	var obstacles := [
		Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 9), Vector2i(20, 15), Vector2i(21, 15),
		Vector2i(20, 16), Vector2i(35, 6), Vector2i(36, 6), Vector2i(35, 7), Vector2i(12, 30),
		Vector2i(13, 30), Vector2i(12, 31), Vector2i(28, 28), Vector2i(28, 29), Vector2i(29, 28),
		Vector2i(40, 34), Vector2i(41, 34), Vector2i(40, 35), Vector2i(15, 40), Vector2i(16, 40),
	]
	for o in obstacles:
		grid.block_rect(o.x, o.y, 2, 2)

func _spawn_starter_force() -> void:
	sim.add_player("VC")
	sim.add_player("FC")
	sim.selected_faction = "VC"
	# Vibe base + infantry in one cluster
	var base_cell := Vector2i(24, 24)
	sim.spawn_structure("VC-B01", "VC", Vector2(24, 24) * NavGrid.CELL)
	for i in range(12):
		var ang := TAU * i / 12.0
		var pos := Vector2(960, 960) + Vector2(cos(ang), sin(ang)) * 120.0
		sim.spawn_unit("VC-U01", "VC", pos)
	# Hostile Federal picket in direct contact range so combat is immediately visible.
	for i in range(6):
		var ang := TAU * i / 6.0
		var pos := Vector2(1290, 1290) + Vector2(cos(ang), sin(ang)) * 90.0
		sim.spawn_unit("FC-U01", "FC", pos)
	# Drive the Vibe force into the Federal picket so the sandbox shows a live engagement.
	var vc_ids: Array = []
	for e in sim.entities.values():
		if e.faction_id == "VC" and e.kind == "unit":
			vc_ids.append(e.id)
	if vc_ids.size() > 0:
		sim.run_commands(0, [{ "type": "ATTACK_MOVE", "entityIds": vc_ids, "targetPosition": Vector2(1290, 1290) }])

func _process(delta: float) -> void:
	_accum += delta
	var step := 1.0 / TICK_RATE
	while _accum >= step:
		sim.step(step)
		_accum -= step
		entity_renderer.queue_redraw()
	_frame += 1
	if _capture_at > 0 and _frame >= _capture_at:
		_capture_at = -1  # prevent re-entry
		_capture_now()

func _capture_now() -> void:
	if _capture_out == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.is_empty():
		print("CAPTURE_FAILED: empty image")
		get_tree().quit()
		return
	# Debug: report a couple VC unit positions so we can see if the force advanced.
	var seen := 0
	for e in sim.entities.values():
		if e.faction_id == "VC" and e.kind == "unit" and seen < 3:
			print("VCU pos=", e.position, " hp=", e.health.current, "/", e.health.max_health)
			seen += 1
	if seen == 0:
		print("VCU none")
	# Also log the healthiest enemy to prove whether combat is landing.
	for e in sim.entities.values():
		if e.faction_id == "FC" and e.kind == "unit":
			print("FCU hp=", e.health.current, "/", e.health.max_health)
	var err := img.save_png(_capture_out)
	print("CAPTURED:", _capture_out, " size=", img.get_size(), " err=", err)
	get_tree().quit()

func _on_game_tick(_n: int, _dt: float) -> void:
	pass

func _on_orders(orders: Array) -> void:
	sim.run_commands(0, orders)

func _on_selection(ids: Array) -> void:
	sim.selected_ids = ids
	entity_renderer.queue_redraw()
