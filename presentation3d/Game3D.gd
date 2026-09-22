extends Node3D
## Game3D — p2-01 runtime-3D presentation prototype (the decision gate). Same sim setup as
## presentation/Game.gd (registry, events, sim, map, starter force, fixed tick, --capture),
## with the 2D presenters replaced by a Camera3D + sun/shadows + terrain reused via a
## SubViewport (MapRenderer + FogRenderer unchanged) + real 3D entities (Entity3D + Models3D).
## Does not touch presentation/, core/, or gameplay/; scenes/Main.tscn stays the main scene.
##
## Coordinate contract (Blueprint p2-01): sim e.position = Vector2(x, y), 1 unit = 1 world px.
## 3D mapping: Vector3(x, 0, y) — sim y becomes 3D z. Sim facing (Vector2) -> 3D yaw =
## atan2(-facing.y, facing.x) (Godot: +X right, -Z forward).

var registry: ContentRegistry
var events: GameEvents
var sim: Simulation

const PLAYER_FACTION := "VC"

var _accum: float = 0.0
var _world: Vector2 = Vector2(2000, 2000)
var _frame: int = 0
var _capture_at: int = -1
var _capture_out: String = ""
var _capture_frames: Array[int] = []

var _entity_root: Node3D
var _entities: Dictionary = {}   # id -> Entity3D
var _map_renderer: MapRenderer
var _fog_renderer: FogRenderer
var hud: HUD

func _ready() -> void:
	registry = ContentRegistry.new("res://content/data")
	registry.load_all()
	events = GameEvents.new()
	add_child(events)

	var grid := NavGrid.new(50, 50)
	sim = Simulation.new(registry, events, 50, 50)
	_build_map(grid)

	_build_camera()
	_build_lighting()
	_build_terrain(grid)

	_entity_root = Node3D.new()
	add_child(_entity_root)

	sim.selected_faction = PLAYER_FACTION
	events.entity_created.connect(_on_entity_created)
	events.entity_destroyed.connect(_on_entity_destroyed)

	hud = HUD.new(sim, events, PLAYER_FACTION)
	add_child(hud)

	_spawn_starter_force()
	events.game_tick.connect(_on_game_tick)

	# Send the roster on a short advance so the animated exemplars (wheels, legs, rotors)
	# show real motion across the --capture-frames window instead of standing idle — the
	# whole point of the multi-frame capture (p2-01 Step 3).
	var mover_ids: Array = []
	for e in sim.entities.values():
		if e.faction_id == "VC" and e.kind == "unit":
			mover_ids.append(e.id)
	if not mover_ids.is_empty():
		sim.run_commands(0, [{"type": "MOVE", "entityIds": mover_ids, "targetPosition": Vector2(34, 34) * NavGrid.CELL}])

	# Optional screenshot capture: godot -- --capture=/abs/out.png [--frame=N] |
	# [--capture-frames=60,75,90] (saves out_NNN.png per frame, motion visible across the set).
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--capture="):
			_capture_out = a.trim_prefix("--capture=")
		elif a.begins_with("--frame="):
			_capture_at = int(a.trim_prefix("--frame="))
		elif a.begins_with("--capture-frames="):
			for s in a.trim_prefix("--capture-frames=").split(","):
				if s != "":
					_capture_frames.append(int(s))
		elif a == "--attack":
			# Same enemy-squad drop as Game.gd's --attack, so units move and turn on camera.
			for i in range(6):
				sim.spawn_unit("FC-U01", "FC", Vector2(33, 22 + i) * NavGrid.CELL)
	if _capture_frames.is_empty() and _capture_at < 0:
		_capture_at = 180

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 720.0
	cam.near = 1.0
	cam.far = 4000.0
	cam.current = true
	add_child(cam)
	var center := Vector3(1230.0, 0.0, 1230.0)
	var pitch := deg_to_rad(40.0)   # from straight down
	var dist := 1200.0
	# Straight down (pitch 0) sits directly above; as pitch grows the camera moves toward
	# -Z (behind) so its look vector tips forward into +Z while still looking down.
	var offset := Vector3(0.0, cos(pitch) * dist, -sin(pitch) * dist)
	cam.position = center + offset
	cam.look_at(center, Vector3.UP)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	# Screen's upper-left, matching the sprite rig's sun (render_sprites.build_scene).
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-135.0), 0.0)
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.ambient_light_energy = 0.35
	env.ssao_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_terrain(grid: NavGrid) -> void:
	# Reuse the 2D MapRenderer + FogRenderer verbatim, rendered into a SubViewport whose
	# texture is projected onto a ground plane — tiles, roads, pads and feathered fog for
	# zero new terrain code.
	var sv := SubViewport.new()
	sv.size = Vector2i(2000, 2000)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)

	_map_renderer = MapRenderer.new()
	_map_renderer.setup(grid, 50, 50, NavGrid.CELL)
	sv.add_child(_map_renderer)
	_fog_renderer = FogRenderer.new(sim.fog_sys, PLAYER_FACTION)
	sv.add_child(_fog_renderer)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	mesh_inst.mesh = plane
	mesh_inst.position = Vector3(1000.0, 0.0, 1000.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = sv.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

func _build_map(grid: NavGrid) -> void:
	# Verbatim from presentation/Game.gd — sim-side map data (pathing + the 2D renderer this
	# scene reuses inside the terrain SubViewport read the same grid).
	sim.grid_map = grid
	var obstacles := [
		Vector2i(6, 8), Vector2i(7, 8), Vector2i(6, 9), Vector2i(20, 15), Vector2i(21, 15),
		Vector2i(20, 16), Vector2i(35, 6), Vector2i(36, 6), Vector2i(35, 7), Vector2i(12, 30),
		Vector2i(13, 30), Vector2i(12, 31), Vector2i(28, 28), Vector2i(28, 29), Vector2i(29, 28),
		Vector2i(40, 34), Vector2i(41, 34), Vector2i(40, 35), Vector2i(15, 40), Vector2i(16, 40),
	]
	for o in obstacles:
		grid.block_rect(o.x, o.y, 2, 2)
	_paint_road(grid, 0, 33, 50, 1)
	_paint_road(grid, 10, 0, 1, 50)
	_paint_road(grid, 38, 0, 1, 34)

func _paint_road(grid: NavGrid, cx: int, cy: int, w: int, h: int) -> void:
	for y in range(cy, cy + h):
		for x in range(cx, cx + w):
			if grid.in_bounds(x, y) and grid.land_types[y][x] == 0:
				grid.land_types[y][x] = 1

func _spawn_starter_force() -> void:
	# Verbatim from presentation/Game.gd.
	sim.add_player("VC")
	sim.add_player("FC")
	sim.selected_faction = "VC"

	sim.spawn_structure("VC-B01", "VC", Vector2(24, 24) * NavGrid.CELL)
	sim.spawn_structure("VC-B02", "VC", Vector2(21, 27) * NavGrid.CELL)
	sim.spawn_structure("VC-B03", "VC", Vector2(27, 27) * NavGrid.CELL)
	sim.spawn_structure("VC-B07", "VC", Vector2(24, 17) * NavGrid.CELL)

	var roster: Array = ["VC-U02", "VC-U03", "VC-U04", "VC-U05", "VC-U06", "VC-U07",
		"VC-U08", "VC-U09", "VC-U10", "VC-U11", "VC-U12", "VC-U13", "VC-U14"]
	for i in range(roster.size()):
		var ang := TAU * i / float(roster.size())
		var pos := Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(cos(ang), sin(ang)) * 215.0
		sim.spawn_unit(String(roster[i]), "VC", pos)

	for i in range(8):
		var ang2 := TAU * i / 8.0
		sim.spawn_unit("VC-U01", "VC", Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(cos(ang2), sin(ang2)) * 125.0)
	for i in range(2):
		sim.spawn_unit("VC-SRV", "VC", Vector2(24.5, 24.5) * NavGrid.CELL + Vector2(-150.0 + i * 44.0, 165.0))

	sim.spawn_resource_field(Vector2(18, 20) * NavGrid.CELL, 4000.0)
	sim.spawn_resource_field(Vector2(30, 20) * NavGrid.CELL, 4000.0)

	sim.spawn_structure("FC-B01", "FC", Vector2(48, 48) * NavGrid.CELL)
	sim.spawn_structure("FC-B03", "FC", Vector2(45, 51) * NavGrid.CELL)
	for i in range(2):
		sim.spawn_unit("FC-SRV", "FC", Vector2(48.5, 48.5) * NavGrid.CELL + Vector2(-125.0 + i * 44.0, 135.0))
	for i in range(6):
		var ang3 := TAU * i / 6.0
		sim.spawn_unit("FC-U01", "FC", Vector2(48.5, 48.5) * NavGrid.CELL + Vector2(cos(ang3), sin(ang3)) * 110.0)

	sim.attach_skirmish_ai("FC", "VC")

func _on_entity_created(entity_id: int, def_id: String, faction: String, _pos: Vector2) -> void:
	var e: Entity = sim.entities.get(entity_id)
	if e == null:
		return
	var model: Node3D
	if e.kind == "structure":
		var sdef: Dictionary = registry.get_structure(def_id)
		model = Models3D.structure(def_id, faction, sdef.get("footprint", [1, 1]))
	elif def_id == "VC-U04":
		model = Models3D.truck()
	elif def_id == "VC-U01":
		model = Models3D.soldier()
	elif def_id == "VC-U02":
		model = Models3D.drone()
	else:
		model = Models3D.fallback(e)
	var ent3d := Entity3D.new()
	ent3d.setup(e, model)
	_entity_root.add_child(ent3d)
	_entities[entity_id] = ent3d

func _on_entity_destroyed(entity_id: int, _def_id: String, _pos: Vector2) -> void:
	# GameEvents.entity_destroyed is declared (entity_id, pos) but Simulation.remove_entity
	# actually emits (id, def_id, position) — a pre-existing mismatch in core/ this ticket
	# does not touch (sim is out of scope); matching the real emit call here is the fix on
	# our side of that boundary.
	var ent3d: Entity3D = _entities.get(entity_id)
	if ent3d != null:
		ent3d.queue_free()
		_entities.erase(entity_id)

func _process(delta: float) -> void:
	_accum += delta
	var step := Simulation.TICK_DT
	while _accum >= step:
		sim.step(step)
		_accum -= step
		_map_renderer.queue_redraw()
		_fog_renderer.queue_redraw()
		for ent3d in _entities.values():
			(ent3d as Entity3D).tick(step)
		_frame += 1
	if not _capture_frames.is_empty():
		if _frame >= _capture_frames[0]:
			var n: int = _capture_frames.pop_front()
			_capture_now("_%03d" % n, _capture_frames.is_empty())
	elif _capture_at > 0 and _frame >= _capture_at:
		_capture_at = -1
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
	var path := _capture_out
	if suffix != "":
		path = "%s%s.%s" % [_capture_out.get_basename(), suffix, _capture_out.get_extension()]
	var err := img.save_png(path)
	print("CAPTURED:", path, " size=", img.get_size(), " err=", err)
	if should_quit:
		get_tree().quit()

func _on_game_tick(_n: int, _dt: float) -> void:
	pass
