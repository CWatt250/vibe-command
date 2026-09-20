extends Node2D
class_name SelectionInput
## RTS selection + order input (Blueprint §7 / master GDD).
## Drag-select box, click-select, shift-add/remove, right-click contextual orders.
## Emits `orders_issued` for the game scene to dispatch to Simulation.

signal orders_issued(orders: Array)
signal selection_changed(ids: Array)

var rts_cam: RTSCamera
var sim: Simulation

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO   # world
var _drag_current: Vector2 = Vector2.ZERO
var _shift: bool = false

func _init(cam: RTSCamera, simulation: Simulation) -> void:
	rts_cam = cam
	sim = simulation

func _draw() -> void:
	if _dragging:
		var w0 := rts_cam.world_to_screen(_drag_start)
		var w1 := rts_cam.world_to_screen(_drag_current)
		var rect := Rect2(w0, w1 - w0).abs()
		draw_rect(rect, Color(0.0, 0.85, 1.0, 0.18), true)
		draw_rect(rect, Color(0.0, 0.85, 1.0, 0.9), false, 1.5)

func _unhandled_input(event: InputEvent) -> void:
	_shift = event is InputEventKey and event.keycode == KEY_SHIFT # fallback; tracked via state
	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT:
		_shift = true
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_SHIFT:
		_shift = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = rts_cam.screen_to_world(event.position)
			_drag_current = _drag_start
		else:
			_dragging = false
			_finish_drag(event.position)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_context_order(rts_cam.screen_to_world(event.position))

	if _dragging:
		_drag_current = rts_cam.screen_to_world(get_viewport().get_mouse_position())
		queue_redraw()

func _finish_drag(mouse_pos: Vector2) -> void:
	var p0 := rts_cam.screen_to_world(mouse_pos)
	var box := Rect2(_drag_start, p0 - _drag_start).abs()
	var sel := _units_in_rect(box)
	if sel.is_empty():
		# Treat a click (no drag) as single-select.
		var single := _unit_at_world(p0)
		if single >= 0:
			sel = [single]
	var final := sel
	if _shift:
		final = _merge_selection(sel)
	selection_changed.emit(final)

func _units_in_rect(box: Rect2) -> Array:
	var out: Array = []
	for e in sim.entities.values():
		if e.kind == "unit" and box.has_point(e.position):
			out.append(e.id)
	return out

## Click-select: units win within 24px; otherwise a structure whose footprint contains
## the point. Drag-select stays units-only (C&C convention) via _units_in_rect.
func _unit_at_world(p: Vector2) -> int:
	var best := -1
	var best_d := 24.0 * 24.0
	for e in sim.entities.values():
		if e.kind != "unit":
			continue
		var d: float = (e.position - p).length_squared()
		if d < best_d:
			best_d = d
			best = e.id
	if best >= 0:
		return best
	return _structure_at_world(p)

func _structure_at_world(p: Vector2) -> int:
	for e in sim.entities.values():
		if e.kind != "structure":
			continue
		var fp: Array = e.def_data.get("footprint", [1, 1])
		var half := Vector2(fp[0], fp[1] if fp.size() > 1 else fp[0]) * NavGrid.CELL * 0.5
		if Rect2(e.position - half, half * 2.0).has_point(p):
			return e.id
	return -1

func _merge_selection(add: Array) -> Array:
	var cur: Array = sim.selected_ids
	var result: Array = cur.duplicate()
	for id in add:
		var idx := result.find(id)
		if idx >= 0:
			result.remove_at(idx)
		else:
			result.append(id)
	return result

func _issue_context_order(world_pos: Vector2) -> void:
	var ids: Array = sim.selected_ids
	if ids.is_empty():
		return
	# Attack if a hostile unit is under the cursor; else move.
	var target_id := _unit_at_world(world_pos)
	var orders: Array = []
	if target_id >= 0 and sim.entities.get(target_id) != null and sim.entities.get(target_id).faction_id != sim.selected_faction:
		orders.append({"type": "ATTACK", "entityIds": ids, "targetEntityId": target_id})
	else:
		orders.append({"type": "MOVE", "entityIds": ids, "targetPosition": world_pos})
	orders_issued.emit(orders)
