extends Node2D
class_name SelectionInput
## RTS selection + order input (Blueprint §7 / master GDD).
## Drag-select box, click-select, shift-add/remove, right-click contextual orders.
## Emits `orders_issued` for the game scene to dispatch to Simulation.
## p4-03: Ctrl+0-9 assign / 0-9 recall control groups (double-tap centres the camera), double-click selects every visible unit of the same type, Shift+order queues it.

signal orders_issued(orders: Array)
signal selection_changed(ids: Array)
## p4-04: the armed click-target mode changed (HUD highlights the matching button).
signal armed_changed(mode: int)

## p4-04 armed command mode. A hotkey or a HUD button arms it, the next left click in the
## world consumes it, Escape or right click cancels it. One enum so the HUD buttons and the
## keys share the same state; add MOVE / RALLY here when those buttons exist.
enum Armed { NONE, ATTACK_MOVE }
const DOUBLE_TAP_MSEC := 400   # same digit twice inside this window -> centre camera on the group

var rts_cam: RTSCamera
var sim: Simulation

var armed: Armed = Armed.NONE
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO   # world
var _drag_current: Vector2 = Vector2.ZERO
var _last_recall_group: int = -1
var _last_recall_msec: int = 0

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

## Escape is taken here, in _input, because PauseMenu consumes it in _unhandled_input and sits
## later in the tree (Game.gd adds it after us), so it would never reach our _unhandled_input.
## PlacementGhost also uses _input and is added later still, so an active placement still wins.
## Only consumed when there is something to cancel: with nothing armed and nothing selected the
## event falls through and Escape still pauses.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if handle_escape():
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# p4-03 control groups: number row only (KEY_0..KEY_9 are contiguous; numpad is KEY_KP_*, unbound).
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var group: int = event.keycode - KEY_0
			if event.ctrl_pressed:
				_assign_group(group)
			else:
				_recall_group(group)
			get_viewport().set_input_as_handled()
			return
		# p4-04: A / S / G. Every other key (H is the camera's) returns false and falls through.
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# p4-04: an armed click consumes the press; _dragging stays false so its release is ignored.
			if handle_left_click(rts_cam.screen_to_world(event.position)):
				get_viewport().set_input_as_handled()
				return
			if event.double_click:
				# p4-03: Godot delivers press, release, press(double_click), release. The first click
				# already single-selected; this press type-selects and _dragging=false skips its release.
				_dragging = false
				_select_same_type_at(rts_cam.screen_to_world(event.position))
				queue_redraw()
				return
			_dragging = true
			_drag_start = rts_cam.screen_to_world(event.position)
			_drag_current = _drag_start
		elif _dragging:
			_dragging = false
			_finish_drag(event.position, event.shift_pressed)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		handle_right_click(rts_cam.screen_to_world(event.position), event.shift_pressed)

	if _dragging:
		_drag_current = rts_cam.screen_to_world(get_viewport().get_mouse_position())
		queue_redraw()

# --- p4-04 armed command mode: pure event → call translation (headless-testable) ---

## Arm a click-target mode. No-op with nothing selected: there is nobody to give the order to,
## and it keeps a stray A press from swallowing the next selection click.
func arm(mode: Armed) -> void:
	if mode == Armed.NONE or sim.selected_ids.is_empty() or armed == mode:
		return
	armed = mode
	armed_changed.emit(armed)

func disarm() -> void:
	if armed == Armed.NONE:
		return
	armed = Armed.NONE
	armed_changed.emit(armed)

## Hotkeys. Returns true when the key did something (the caller marks the event handled).
## A = arm attack-move, S = stop, G = guard (sim HOLD: stay put, engage in range, never chase).
func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_A:
			arm(Armed.ATTACK_MOVE)
			return armed == Armed.ATTACK_MOVE
		KEY_S:
			disarm()
			return issue_simple("STOP")
		KEY_G:
			disarm()
			return issue_simple("HOLD")
	return false

## Escape: cancel the armed mode first; with nothing armed, deselect; with nothing selected
## either, return false so the event falls through to PauseMenu.
func handle_escape() -> bool:
	if armed != Armed.NONE:
		disarm()
		return true
	if not sim.selected_ids.is_empty():
		selection_changed.emit([])
		return true
	return false

## Left click at a world point while armed: issue the armed order for the selection and
## disarm. Returns true when consumed, so the caller must not start a drag-select.
func handle_left_click(world_pos: Vector2) -> bool:
	if armed == Armed.NONE:
		return false
	var mode := armed
	disarm()
	if sim.selected_ids.is_empty():
		return true
	match mode:
		Armed.ATTACK_MOVE:
			orders_issued.emit([{"type": "ATTACK_MOVE", "entityIds": sim.selected_ids.duplicate(), "targetPosition": world_pos}])
	return true

## Right click: cancels an armed mode (and issues nothing — the click was a cancel, not an
## order); otherwise the usual contextual order.
func handle_right_click(world_pos: Vector2, queue: bool = false) -> void:
	if armed != Armed.NONE:
		disarm()
		return
	_issue_context_order(world_pos, queue)

## An order with no target ("STOP", "HOLD") for the current selection. False with no selection.
func issue_simple(cmd_type: String) -> bool:
	if sim.selected_ids.is_empty():
		return false
	orders_issued.emit([{"type": cmd_type, "entityIds": sim.selected_ids.duplicate()}])
	return true

func _finish_drag(mouse_pos: Vector2, shift: bool) -> void:
	var p0 := rts_cam.screen_to_world(mouse_pos)
	var box := Rect2(_drag_start, p0 - _drag_start).abs()
	var sel := _units_in_rect(box)
	if sel.is_empty():
		# Treat a click (no drag) as single-select.
		var single := _unit_at_world(p0)
		if single >= 0:
			sel = [single]
	var final := sel
	if shift:
		final = _merge_selection(sel)
	selection_changed.emit(final)

func _units_in_rect(box: Rect2) -> Array:
	var out: Array = []
	for e in sim.entities.values():
		if e.kind == "unit" and e.faction_id == sim.selected_faction and box.has_point(e.position):
			out.append(e.id)
	return out

## Own entities are always pickable; enemy/neutral only if the player can see them now.
func _pickable(e: Entity) -> bool:
	if e.faction_id == sim.selected_faction:
		return true
	return sim.fog_sys == null or sim.fog_sys.is_visible(sim.selected_faction, e.position)

## Click-select: units win within 24px; otherwise a structure whose footprint contains
## the point. Drag-select stays units-only (C&C convention) via _units_in_rect.
func _unit_at_world(p: Vector2) -> int:
	var best := -1
	var best_d := 24.0 * 24.0
	for e in sim.entities.values():
		if e.kind != "unit":
			continue
		if not _pickable(e):
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
		if not _pickable(e):
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

## Right-click: attack a visible hostile under the cursor, else move. Shift held -> "queue": true,
## which Simulation._split_queued appends behind the unit's current order instead of replacing it.
func _issue_context_order(world_pos: Vector2, queue: bool) -> void:
	var ids: Array = sim.selected_ids
	if ids.is_empty():
		return
	var target_id := _unit_at_world(world_pos)
	var order: Dictionary
	if target_id >= 0 and sim.entities.get(target_id) != null and sim.entities.get(target_id).faction_id != sim.selected_faction \
			and _pickable(sim.entities.get(target_id)):
		order = {"type": "ATTACK", "entityIds": ids, "targetEntityId": target_id}
	else:
		order = {"type": "MOVE", "entityIds": ids, "targetPosition": world_pos}
	if queue:
		order["queue"] = true
	orders_issued.emit([order])

# ---- p4-03: control groups ----

## Ctrl+digit: the current selection becomes group `group` (an empty selection empties it).
## Goes through run_commands like every other sim mutation (CONTROL_ASSIGN).
func _assign_group(group: int) -> void:
	orders_issued.emit([{"type": "CONTROL_ASSIGN", "group": group, "entityIds": sim.selected_ids.duplicate()}])

## Digit: select the group's alive members. Selection is presentation state (Game._on_selection is
## its one writer), so this reads sim.control_groups and emits selection_changed rather than
## sending CONTROL_RECALL. An empty group is a no-op. Same digit twice inside DOUBLE_TAP_MSEC
## also centres the camera on the group (RTSCamera.center_on clamps it now).
func _recall_group(group: int) -> void:
	var ids: Array = []
	for id in sim.control_groups.get(group, []):
		var e: Entity = sim.entities.get(id)
		if e != null and e.alive:
			ids.append(id)
	if ids.is_empty():
		return
	var now := Time.get_ticks_msec()
	if group == _last_recall_group and now - _last_recall_msec <= DOUBLE_TAP_MSEC:
		rts_cam.center_on(_centroid(ids))
	_last_recall_group = group
	_last_recall_msec = now
	selection_changed.emit(ids)

func _centroid(ids: Array) -> Vector2:
	var c := Vector2.ZERO
	for id in ids:
		c += sim.entities[id].position
	return c / float(ids.size())

# ---- p4-03: double-click type select ----

## Double-click on an own unit: select every alive own unit with the same def_id inside the
## camera rect. Enemies and structures are not type-selectable (the first click already did the
## single-select, so nothing else happens).
func _select_same_type_at(p: Vector2) -> void:
	var hit := _unit_at_world(p)
	var e: Entity = sim.entities.get(hit)
	if e == null or e.kind != "unit" or e.faction_id != sim.selected_faction:
		return
	selection_changed.emit(select_same_type(e.id))

## Public so Game.gd's --select-type capture flag can drive the same path.
func select_same_type(src_id: int) -> Array:
	var src: Entity = sim.entities.get(src_id)
	if src == null:
		return []
	var out: Array = []
	for id in _units_in_rect(_camera_world_rect()):
		var e: Entity = sim.entities[id]
		if e.alive and e.def_id == src.def_id:
			out.append(id)
	return out

## The world rect the camera shows now (same projection EntityRenderer._visible_world_rect uses).
func _camera_world_rect() -> Rect2:
	var tl := rts_cam.screen_to_world(Vector2.ZERO)
	var br := rts_cam.screen_to_world(get_viewport_rect().size)
	return Rect2(tl, br - tl)
