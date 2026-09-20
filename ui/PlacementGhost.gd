extends Node2D
class_name PlacementGhost
## PlacementGhost — world-space footprint preview while placing a structure.
## Snaps to the nav grid using the same anchor-cell math as Simulation._placement_valid
## (anchor = cell under the cursor; footprint spans c - w/2 .. c - w/2 + w), so what you
## see green is exactly what the sim will accept. Left click BUILDs, right click / Esc
## cancels. Consumes input while active so SelectionInput doesn't also act on the click.

signal placement_finished

const COL_OK := Color(0.2, 1.0, 0.4, 0.35)
const COL_BAD := Color(1.0, 0.25, 0.2, 0.35)

var sim: Simulation
var rts_cam: RTSCamera
var faction: String

var def_id: String = ""
var _anchor: Vector2i = Vector2i.ZERO
var _footprint: Vector2i = Vector2i.ONE

func _init(simulation: Simulation, cam: RTSCamera, player_faction: String) -> void:
	sim = simulation
	rts_cam = cam
	faction = player_faction
	z_index = 50

func active() -> bool:
	return def_id != ""

func begin(structure_def_id: String) -> void:
	var def: Dictionary = sim.registry.get_structure(structure_def_id)
	if def.is_empty():
		return
	def_id = structure_def_id
	var fp: Array = def.get("footprint", [1, 1])
	_footprint = Vector2i(int(fp[0]), int(fp[1]) if fp.size() > 1 else int(fp[0]))
	_track(get_viewport().get_mouse_position())
	queue_redraw()

func cancel() -> void:
	if not active():
		return
	def_id = ""
	queue_redraw()
	placement_finished.emit()

func _input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventMouseMotion:
		_track(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_build()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()

func _track(screen_pos: Vector2) -> void:
	var world := rts_cam.screen_to_world(screen_pos)
	_anchor = sim.grid_map.world_to_cell(world.x, world.y)
	queue_redraw()

## Sim-side position for this anchor: the anchor cell's centre (what BUILD receives).
func _anchor_world() -> Vector2:
	return sim.grid_map.cell_to_world(_anchor)

func _footprint_rect() -> Rect2:
	var origin := Vector2(_anchor.x - _footprint.x / 2, _anchor.y - _footprint.y / 2) * NavGrid.CELL
	return Rect2(origin, Vector2(_footprint) * NavGrid.CELL)

func _try_build() -> void:
	var pos := _anchor_world()
	if not sim.can_place(def_id, pos, faction):
		return
	sim.run_commands(0, [{"type": "BUILD", "structureDefId": def_id, "position": pos, "faction": faction}])
	cancel()

func _process(_delta: float) -> void:
	# Camera pans under a still cursor; keep the ghost glued to the grid.
	if active():
		_track(get_viewport().get_mouse_position())

func _draw() -> void:
	if not active():
		return
	var ok := sim.can_place(def_id, _anchor_world(), faction)
	var rect := _footprint_rect()
	draw_rect(rect, COL_OK if ok else COL_BAD, true)
	draw_rect(rect, (COL_OK if ok else COL_BAD).lightened(0.3) * Color(1, 1, 1, 2.5), false, 2.0)
	# Cell grid inside the footprint so the snap is legible.
	for x in range(1, _footprint.x):
		var gx := rect.position.x + x * NavGrid.CELL
		draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(1, 1, 1, 0.15))
	for y in range(1, _footprint.y):
		var gy := rect.position.y + y * NavGrid.CELL
		draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), Color(1, 1, 1, 0.15))
