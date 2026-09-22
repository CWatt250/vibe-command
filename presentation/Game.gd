extends Node2D
## Vibe Command — Milestone 0 Combat Sandbox game scene.
## Wires the pure-logic simulation to the presentation layer (camera, input, render),
## builds an industrial skirmish map, spawns a starting Vibe Coder force, and drives
## the fixed-tick sim loop. This is the playable entry point.

var registry: ContentRegistry
var events: GameEvents
var sim: Simulation

var rts_cam: RTSCamera
var selection_input: SelectionInput
var map_renderer: MapRenderer
var entity_renderer: EntityRenderer
var fx_renderer: FxRenderer
var fog_renderer: FogRenderer
var minimap_layer: CanvasLayer
var minimap: MiniMapRenderer
var hud: HUD
var placement_ghost: PlacementGhost
var pause_menu: PauseMenu
var motion: UnitMotion

const PLAYER_FACTION := "VC"

var _accum: float = 0.0
var _world: Vector2 = Vector2(2000, 2000)
var _frame: int = 0
var _capture_at: int = -1
var _capture_frames: Array[int] = []
var _capture_out: String = ""
var _debug_pause: bool = false

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
	# Effects over the entities; renderer reads hit flashes from it.
	fx_renderer = FxRenderer.new(sim, events)
	add_child(fx_renderer)
	entity_renderer.fx = fx_renderer
	# Shared procedural motion (p3-03): one speed sampler, read by both presenters.
	motion = UnitMotion.new()
	entity_renderer.motion = motion
	fx_renderer.motion = motion
	# Sun: a warm tint on the world canvas only (CanvasLayers — HUD, minimap — are unaffected).
	var sun := CanvasModulate.new()
	sun.color = Color(1.0, 0.97, 0.91)
	add_child(sun)

	# Fog overlay (world space) + minimap (screen space). Both key off the player faction.
	var player_faction := PLAYER_FACTION
	sim.selected_faction = player_faction
	fog_renderer = FogRenderer.new(sim.fog_sys, player_faction)
	add_child(fog_renderer)
	entity_renderer.fog_sys = sim.fog_sys
	entity_renderer.player_faction = player_faction
	minimap_layer = CanvasLayer.new()
	minimap_layer.layer = 20
	add_child(minimap_layer)
	minimap = MiniMapRenderer.new(sim, sim.fog_sys, player_faction, rts_cam)
	minimap.fog_texture = fog_renderer.texture
	minimap_layer.add_child(minimap)

	# HUD shell (Phase 7): resources top-left, selection info bottom-right.
	hud = HUD.new(sim, events, player_faction)
	add_child(hud)

	# Input
	selection_input = SelectionInput.new(rts_cam, sim)
	add_child(selection_input)
	selection_input.orders_issued.connect(_on_orders)
	selection_input.selection_changed.connect(_on_selection)

	# Structure placement: HUD build grid asks, the ghost previews + issues BUILD.
	placement_ghost = PlacementGhost.new(sim, rts_cam, player_faction)
	add_child(placement_ghost)
	hud.build_grid.place_requested.connect(placement_ghost.begin)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)

	# Spawn starter forces: 12 Vibe Coder infantry + a Garage Core (Vibe base)
	_spawn_starter_force()

	events.game_tick.connect(_on_game_tick)

	# Optional screenshot capture: godot -- --capture=/abs/out.png [--frame=N]
	# Debug selection for HUD captures: --select=<def_id> [--train=<unit_id>] selects the
	# first entity with that def and (optionally) queues that unit on it twice.
	# --place=<structure_def_id> starts the placement ghost with the cursor warped to centre.
	# --attack spawns an enemy squad next to the base; --pause opens the pause menu at capture.
	var args := OS.get_cmdline_user_args()
	var debug_select := ""
	var debug_train := ""
	var debug_place := ""
	var debug_pause := false
	var debug_motion := false
	for a in args:
		if a.begins_with("--capture="):
			_capture_out = a.trim_prefix("--capture=")
		elif a.begins_with("--frame="):
			_capture_at = int(a.trim_prefix("--frame="))
		elif a.begins_with("--capture-frames="):
			for s in a.trim_prefix("--capture-frames=").split(","):
				if s != "":
					_capture_frames.append(int(s))
		elif a.begins_with("--select="):
			debug_select = a.trim_prefix("--select=")
		elif a.begins_with("--train="):
			debug_train = a.trim_prefix("--train=")
		elif a.begins_with("--place="):
			debug_place = a.trim_prefix("--place=")
		elif a == "--pause":
			debug_pause = true
		elif a == "--motion":
			debug_motion = true
		elif a == "--attack":
			# Drop an FC squad inside the VC roster's acquire radius so combat FX show.
			for i in range(6):
				sim.spawn_unit("FC-U01", "FC", Vector2(33, 22 + i) * NavGrid.CELL)
	if _capture_frames.is_empty() and _capture_at < 0:
		_capture_at = 180
	if debug_select != "":
		for e in sim.entities.values():
			if e.def_id == debug_select:
				_on_selection([e.id])
				if debug_train != "":
					var order := {"type": "TRAIN", "entityIds": [e.id], "unitDefId": debug_train}
					sim.run_commands(0, [order, order])
				break
	if debug_place != "":
		Input.warp_mouse(get_viewport_rect().size * 0.5)
		placement_ghost.begin(debug_place)
	_debug_pause = debug_pause  # applied at capture time; pausing now would stall _process
	if debug_motion:
		# Four exemplars, one per motion rule, each in its own lane on open dirt and sent
		# 600 px east so nothing arrives inside the capture window. Fastest first, so the
		# leftmost travels furthest.
		var lanes := [["VC-U02", Vector2(620, 380)], ["VC-U04", Vector2(720, 460)],
					["VC-U01", Vector2(820, 540)], ["VC-U12", Vector2(920, 620)]]
		for l in lanes:
			var id: int = sim.spawn_unit(l[0], "VC", l[1])
			if id >= 0:
				sim.run_commands(0, [{"type": "MOVE", "entityIds": [id], "targetPosition": l[1] + Vector2(600, 0)}])
		rts_cam.zoom = Vector2(2.0, 2.0)
		rts_cam.position = Vector2(900, 475)

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
	# Roads (land type 1, purely visual — passability is unchanged). One east-west
	# artery south of both bases, two north-south feeders; painted before structures
	# so pads win where they overlap.
	_paint_road(grid, 0, 33, 50, 1)
	_paint_road(grid, 10, 0, 1, 50)
	_paint_road(grid, 38, 0, 1, 34)

func _paint_road(grid: NavGrid, cx: int, cy: int, w: int, h: int) -> void:
	for y in range(cy, cy + h):
		for x in range(cx, cx + w):
			if grid.in_bounds(x, y) and grid.land_types[y][x] == 0:
				grid.land_types[y][x] = 1

func _spawn_starter_force() -> void:
	sim.add_player("VC")
	sim.add_player("FC")
	sim.selected_faction = "VC"

	# --- Vibe Coder home base (The Garage) ---
	sim.spawn_structure("VC-B01", "VC", Vector2(24, 24) * NavGrid.CELL)
	sim.spawn_structure("VC-B02", "VC", Vector2(21, 27) * NavGrid.CELL)
	sim.spawn_structure("VC-B03", "VC", Vector2(27, 27) * NavGrid.CELL)
	sim.spawn_structure("VC-B07", "VC", Vector2(24, 17) * NavGrid.CELL)  # Maker Space: trains U01-U03

	# Garage roster showcase: one of every Vibe Coder unit rings the HQ.
	var roster: Array = ["VC-U02", "VC-U03", "VC-U04", "VC-U05", "VC-U06", "VC-U07",
		"VC-U08", "VC-U09", "VC-U10", "VC-U11", "VC-U12", "VC-U13", "VC-U14"]
	for i in range(roster.size()):
		var ang := TAU * i / float(roster.size())
		var pos := Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(cos(ang), sin(ang)) * 215.0
		sim.spawn_unit(String(roster[i]), "VC", pos)

	# Maker crew + harvester crew.
	for i in range(8):
		var ang2 := TAU * i / 8.0
		sim.spawn_unit("VC-U01", "VC", Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(cos(ang2), sin(ang2)) * 125.0)
	for i in range(2):
		sim.spawn_unit("VC-SRV", "VC", Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(-150.0 + i * 44.0, 165.0))

	# --- Resource fields (economy is a real system, not decoration) ---
	sim.spawn_resource_field(Vector2(18, 20) * NavGrid.CELL, 4000.0)
	sim.spawn_resource_field(Vector2(30, 20) * NavGrid.CELL, 4000.0)

	# --- Federal Command base + garrison ---
	sim.spawn_structure("FC-B01", "FC", Vector2(48, 48) * NavGrid.CELL)
	sim.spawn_structure("FC-B03", "FC", Vector2(45, 51) * NavGrid.CELL)
	for i in range(2):
		sim.spawn_unit("FC-SRV", "FC", Vector2(48.5, 48.5) * NavGrid.CELL + Vector2(-125.0 + i * 44.0, 135.0))
	for i in range(6):
		var ang3 := TAU * i / 6.0
		sim.spawn_unit("FC-U01", "FC", Vector2(48.5, 48.5) * NavGrid.CELL + Vector2(cos(ang3), sin(ang3)) * 110.0)

	# Skirmish AI drives Federal Command against the Vibe Coder player.
	sim.attach_skirmish_ai("FC", "VC")

func _process(delta: float) -> void:
	_accum += delta
	var step := Simulation.TICK_DT
	while _accum >= step:
		sim.step(step)
		motion.sample(sim, step)   # this tick's speed, before the redraw that draws it
		_accum -= step
		entity_renderer.queue_redraw()
		fog_renderer.queue_redraw()
		minimap.queue_redraw()
		_frame += 1
	if not _capture_frames.is_empty():
		if _frame >= _capture_frames[0]:
			var n: int = _capture_frames.pop_front()
			_capture_now("_%03d" % n, _capture_frames.is_empty())
	elif _capture_at > 0 and _frame >= _capture_at:
		_capture_at = -1  # prevent re-entry
		if _debug_pause:
			pause_menu.toggle()  # menu draws on the frame _capture_now awaits
		_capture_now("", true)

func _capture_now(suffix: String, should_quit: bool) -> void:
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
	var path := _capture_out
	if suffix != "":
		path = "%s%s.%s" % [_capture_out.get_basename(), suffix, _capture_out.get_extension()]
	var err := img.save_png(path)
	print("CAPTURED:", path, " size=", img.get_size(), " err=", err)
	if should_quit:
		get_tree().quit()

func _on_game_tick(_n: int, _dt: float) -> void:
	pass

func _on_orders(orders: Array) -> void:
	sim.run_commands(0, orders)

func _on_selection(ids: Array) -> void:
	sim.selected_ids = ids
	entity_renderer.queue_redraw()
	# Put selection on the event bus so HUD panels can rebind without touching input.
	var typed: Array[int] = []
	typed.assign(ids)
	events.entity_selected.emit(typed)
