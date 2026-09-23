# p4-03 — Control groups (Ctrl+0–9 / 0–9), double-click type select, Shift order queue

**Tier:** O (Sonnet via Claude Code `/model sonnet`) · **Repo:** `~/Dev/vibe-command` (HEAD `bd73d1c`) · **Touches:** `core/simulation/Entity.gd`, `core/simulation/Simulation.gd`, `presentation/SelectionInput.gd`, `presentation/MiniMapRenderer.gd`, `presentation/Game.gd`, new `tests/test_p4_03_orders.gd`, new `docs/screenshot_p4_type_select.png`

Why O: this is the one Phase 4 ticket that changes the simulation (an order queue on `Entity`, a queue/replace decision in `run_commands`, a pop point in `_tick_entity`, and a one-line arrival-tolerance fix that the queue exposes), plus an input rewrite in `presentation/`, a capture flag in `Game.gd`, a new headless test and a screenshot. Five files (the minimap edit is two lines) with a design invariant ("the queue pops in exactly one place") that a single-file executor cannot hold. Every snippet below was run in a throwaway copy against HEAD: the new test passes, the README loop must show all thirteen existing suites (p4-01, p4-02, p4-04 have landed) still passing; fourteen with the new one (the probe at HEAD `bd73d1c` ran the ten suites that existed then — all green), and the capture produces the numbers quoted.

Read `docs/specs/README.md` first. **This ticket changes `core/`** — deliberately and minimally; `gameplay/` (CombatSystem, MovementComponent) is NOT touched. `presentation3d/` is shelved — do not edit it. Lands fourth: after p4-01 (uses `RTSCamera.center_on`), p4-02 (extends the minimap right-click) and p4-04 (extends its `_unhandled_input`); before p4-05 (which reads p4-04's `armed` and p4-02's `contains_screen`, nothing from this ticket). Every SelectionInput line number in this ticket (7-16, 30-51, 53-65, 121-133) is stale after p4-04 — locate by function name. Keep p4-04's `_input`, `enum Armed`, `armed_changed`, `arm`, `disarm`, `handle_key`, `handle_escape`, `handle_left_click`, `issue_simple` byte-identical.

## Keys
| Key | Action | Where |
|---|---|---|
| `Ctrl` + `0`–`9` | assign current selection to control group N (empty selection empties the group) | `SelectionInput._unhandled_input` |
| `0`–`9` | recall group N: select its alive members (empty group: no-op, selection unchanged) | same |
| `0`–`9` twice within 400 ms | recall **and** centre the camera on the group (yes, we do this) | same |
| LMB double-click on an own unit | select every alive own unit with the same `def_id` inside the camera rect | same |
| `Shift` + RMB (order) | queue the MOVE / ATTACK behind the unit's current order | same |
| `Shift` + LMB (select) | add/remove from selection — already intended, now actually works (see "current facts" #5) | same |
| `Shift` + RMB on the minimap | queued MOVE (same flag) | `MiniMapRenderer._input` → `order_move_at` (Change 3f) |

Number-row digits only (`KEY_0`..`KEY_9`); the numpad (`KEY_KP_*`) stays unbound. Not bound here: `A`/`S`/`G` (p4-04), arrows / `H` / MMB (p4-01), `Escape` (p4-04's `SelectionInput._input`, then PlacementGhost / PauseMenu own it — keep `_input` byte-identical), wheel (`RTSCamera._unhandled_input`, p4-01), `Alt` held (EntityRenderer.gd:247 shows all health bars). `ui/PlacementGhost.gd:48-62` uses `_input` and calls `set_input_as_handled()` for LMB/RMB/Escape while a ghost is active, so those never reach this node during placement; Ctrl+digit and digits still do, which is fine.

## Why
`docs/execution-plan.md:92` lists this row as "Double-click type-select, Ctrl+0–9 groups (sim already has control groups), Shift order queue — O". The sim half of control groups exists and is unused by any input; nothing in the game lets the player queue an order; nothing selects by type.

## Current facts you will rely on (all read at HEAD `bd73d1c`)

1. **Control groups already exist in the sim.** `core/simulation/Simulation.gd:28` `var control_groups: Dictionary = {}` (group index → Array of entity ids). Command handlers: `run_commands` dispatches `"CONTROL_ASSIGN"` → `_assign_control_group(cmd.get("group", 0), targets)` (371-372) and `"CONTROL_RECALL"` → `_recall_control_group` (373-374). `_assign_control_group` (611-617) keeps only ids that exist and are `alive`, then **overwrites** the group. `recall_control_group` (620-627) writes `selected_ids` directly and filters only `entities.has(id)`. `_cleanup_control_groups` (243-251) runs every `step()` (called at 201) and drops any id no longer in `entities` — `remove_entity` (167-176) erases the id, so **dead units leave every group by the end of the step in which they die**. Garrisoned units are the exception: `garrison_units` sets `alive = false` but leaves the entity in `entities` (654), so they survive cleanup — the recall code below filters `alive` for that reason. `presentation/RTSCamera.gd:3` promises "follow (control groups)" but nothing implements it; `RTSCamera._unhandled_input` (36-41) handles only the wheel.
2. **Selection is presentation state with one writer.** `Simulation.gd:33-35` calls `selected_ids` / `selected_faction` "transient UI/selection state". The only place that sets it in the game is `presentation/Game.gd:294-300` `_on_selection(ids)`: sets `sim.selected_ids`, redraws, and emits `events.entity_selected` for the HUD. `SelectionInput` never touches `sim.selected_ids`; it emits `selection_changed` (Game.gd:95 connects it) and `orders_issued` (Game.gd:94 → `_on_orders` → `sim.run_commands(0, orders)` at 291-292).
3. **Order state (p1-07).** `core/simulation/Entity.gd:33-36`: `enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD }`, `order`, `order_target`, `order_dest`. **There is no notion of a next/queued order anywhere** — `grep -rn "queue" core gameplay` hits only the production queue. Where each order *ends*:
   - MOVE / ATTACK_MOVE arrival: `Simulation._tick_entity` 314-327 — after `movement.update`, `if was_moving and not e.movement.is_moving() and (order == MOVE or ATTACK_MOVE) and e.position.distance_to(e.order_dest) <= 4.0: e.order = IDLE` (324-327).
   - ATTACK target dead/invalid: `gameplay/systems/CombatSystem.gd:38-43` — sets `current_target_id = -1`, `order = IDLE`, `order_target = -1`. `combat.tick_all()` runs at `Simulation.step` 195, i.e. **after** the entity loop (185-189) in the same step.
   - STOP: `run_commands` 351-360 sets IDLE, clears movement and target. HOLD: `_issue_hold` 447-454.
   - Issuers: `_issue_move` 385-398 (formation offsets via `_formation_offsets`, 400-415; **n == 1 yields `Vector2.ZERO`**, 404-407), `_issue_attack` 417-429 (clears movement at 425-426), `_issue_attack_move` 431-445. `run_commands` 339-382 reads `type` and `entityIds` (342-343) then `match`es.
4. **Latent p1-07 bug the queue exposes (fix it here).** `gameplay/components/MovementComponent.gd:48-52`: `update()` skips any waypoint within `footprint_radius` of the unit, including the final one, so a unit stops up to `footprint_radius` short of its goal (`content/data/moveprofiles.json`: 6 px infantry, 9 px `prof_vehicle_fast`, 10 vehicle, 12 heavy). The arrival check at `Simulation.gd:326` demands `<= 4.0`. Measured in the probe: a VC-U04 (`prof_vehicle_fast`, `units.json:1339`) sent (600,400)→(600,600) stopped at (594.7, 593.2) — 8.6 px out — and stayed `order == MOVE` forever, so a queued order behind it would never start. Today this is invisible because an un-IDLE'd stopped MOVE still acquires targets (CombatSystem.gd:29 only skips while `is_moving()`). `NavGrid._reconstruct` (core/spatial/NavGrid.gd:158-162) does end the path on the exact goal, so the only source of the shortfall is the footprint skip. Fix: tolerance becomes `maxf(4.0, e.movement.footprint_radius)`. ATTACK_MOVE's guard (a chase to a waypoint short of `order_dest` must not count as arrival, comment at 320-323) is preserved: chase goals are a weapon range (≥ 120 px) away, not 12. (`prof_vehicle_fast` is `content/data/moveprofiles.json:7`.)
5. **Shift tracking in SelectionInput is dead.** `presentation/SelectionInput.gd:31`: `_shift = event is InputEventKey and event.keycode == KEY_SHIFT` runs on **every** event, so any mouse motion or button resets `_shift` to false before the click at 37-45 reads it; lines 32-35 then only matter for the Shift key event itself. Replace the whole mechanism with `event.shift_pressed` on the mouse event (`InputEventMouseButton` extends `InputEventWithModifiers`, which also carries `ctrl_pressed`; `InputEventMouseButton.double_click` is a bool; `InputEventKey.echo` filters key repeat).
6. **Existing rect/visibility helpers (p1-02) to reuse, not duplicate:** `_units_in_rect(box)` 67-72 (units only, own faction only, `box.has_point(e.position)`), `_pickable(e)` 75-78 (own always; enemies only if `fog_sys.is_visible`), `_unit_at_world(p)` 82-96 (nearest own/visible unit within 24 px, else `_structure_at_world`), `_merge_selection` 110-119, `_issue_context_order` 121-133 (ATTACK if a visible hostile is under the cursor, else MOVE; dicts at 130 and 132). Camera projection: `RTSCamera.screen_to_world` / `world_to_screen` (RTSCamera.gd:73-77). `EntityRenderer._visible_world_rect()` (333-338) is the renderer's own copy of "camera rect" — `SelectionInput` builds the same rect from `rts_cam.screen_to_world` (two calls; no cross-node dependency).
7. **Camera:** `RTSCamera.center_on(world_pos)` (p4-01) sets `position` and clamps immediately. `Game.gd` starts the camera at (1230, 1230); at 1280x720, zoom 1, the camera rect is x 590..1870, y 870..1590.
8. **Capture plumbing:** `Game.gd:115-143` arg loop; `--select=` branch at 130-131 (`debug_select` declared at 116, applied at 146-153 by finding the first entity with that `def_id` and calling `_on_selection([e.id])`); `--place` handling at 154-156. Selection ring: `EntityRenderer.gd:215-216` `draw_arc(e.position, size_px * 0.55, 0, TAU, 32, SEL_COLOR, 2.0)` with `SEL_COLOR := Color(0.0, 1.0, 0.4)` (124), under the `CanvasModulate` sun tint (1.0, 0.97, 0.91) at Game.gd:69-71 → rings sample at about (0, 247, 93). Starter force (Game.gd:216-218): 8 × VC-U01 "Maker Crew" on a 125 px ring around (980, 980); the one at 270° sits at y = 855, above the camera rect's top edge (870), so an on-screen type-select of VC-U01 yields **7** units — this is the deterministic number the screenshot step checks.
9. **Weapon facts used by the test:** VC-U04 uses `wpn_autocannon` range 160 (`content/data/weapons.json:8`), `visionRadius` 250 (`units.json:1340`), `acquire_radius = max(range, 220)` (`gameplay/components/WeaponComponent.gd:47`). `prof_vehicle_fast` speed 120 px/s (`moveprofiles.json:7`).

## Design (implement exactly this; one-sentence reasons where two designs were possible)

- **Assign** goes through `run_commands` as `CONTROL_ASSIGN` (it mutates sim state). **Recall** reads `sim.control_groups` and emits `selection_changed` instead of sending `CONTROL_RECALL`, because selection is presentation state with one writer (fact #2) and `recall_control_group` would bypass `Game._on_selection` and so the HUD's `entity_selected`. `CONTROL_RECALL` / `recall_control_group` stay in the sim untouched (tests and any AI may use them).
- **Dead members:** the sim already drops them next tick (fact #1); recall additionally skips `not alive` so garrisoned members are not selected. **Same digit twice** (≤ 400 ms): yes — centre the camera on the members' centroid. C&C/StarCraft do this and the camera clamp makes it free (fact #7).
- **Double-click** = every alive own unit with the clicked unit's `def_id` inside the current camera rect, via `_units_in_rect(_camera_world_rect())`. Double-clicking an enemy or a structure does nothing beyond the single-select the first click already did (enemies are not "yours to select by type"; structures are one-per-type anyway).
- **Queue:** `"queue": true` on a MOVE / ATTACK / ATTACK_MOVE command dict. A unit is *busy* if `order != IDLE` **or** its queue is non-empty (covers the one-tick window between CombatSystem setting IDLE and `_tick_entity` popping). Busy + queue → append; not busy → issue now (Shift on an idle unit just runs the order, like every RTS); no `queue` flag → clear the queue, then issue (replace). STOP and HOLD clear the queue. Queued position orders store the unit's own formation slot (`_formation_offsets(n)[i]`) at queue time, so a queued group move fans out when it pops one unit at a time (`_issue_move` with one target adds `Vector2.ZERO`, fact #3). **The queue pops in exactly one place:** `Simulation._tick_entity`, right after the movement block, when `order == IDLE and not order_queue.is_empty()`. MOVE / ATTACK_MOVE arrival sets IDLE a few lines above and pops the same tick; ATTACK ends in `CombatSystem.tick_all` later in the same step and pops on the next tick (one tick = 67 ms, deterministic). No change to `CombatSystem`.
- A popped ATTACK on an already-dead target: `_issue_attack` sets `order = ATTACK`, CombatSystem.gd:38-43 finds it invalid and sets IDLE, the next queued order pops next tick — the queue drains itself. A popped order on a unit without movement/weapon is skipped by the existing `continue`s in the issuers and the order stays IDLE, so the next one pops next tick — same self-draining behaviour.

## Change 1 — `core/simulation/Entity.gd`
After line 36 (`var order_dest: Vector2 = Vector2.ZERO  # for MOVE / ATTACK_MOVE`) add:
```gdscript
## p4-03: orders waiting behind the current one (Shift = queue). Each entry is a command dict
## in run_commands' own shape: {"type": "MOVE"|"ATTACK_MOVE", "targetPosition": Vector2} or
## {"type": "ATTACK", "targetEntityId": int}. Drained by Simulation._tick_entity once `order` is
## back to IDLE; cleared by any non-queued order, STOP or HOLD.
var order_queue: Array = []
```
Nothing else in the file changes.

## Change 2 — `core/simulation/Simulation.gd` (four edits)

**2a. `run_commands` (339-382):** between line 343 (`var targets: Array = cmd.get("entityIds", [])`) and line 344 (`match cmd_type:`) insert:
```gdscript
		# p4-03: Shift-queued orders. A busy unit gets the order appended to its queue instead of
		# issued now; a non-queued order (and STOP / HOLD) clears the queue first.
		if cmd_type == "MOVE" or cmd_type == "ATTACK" or cmd_type == "ATTACK_MOVE":
			targets = _split_queued(cmd_type, targets, cmd)
		elif cmd_type == "STOP" or cmd_type == "HOLD":
			for t in targets:
				var eq: Entity = entities.get(t)
				if eq != null:
					eq.order_queue.clear()
```
The `match` block itself is unchanged — the three movement branches simply receive the reduced `targets`.

**2b. `_tick_entity` (309-337):** replace line 326
```gdscript
				and e.position.distance_to(e.order_dest) <= 4.0:
```
with
```gdscript
				and e.position.distance_to(e.order_dest) <= maxf(4.0, e.movement.footprint_radius):
```
(fact #4), and immediately after line 327 (`e.order = Entity.Order.IDLE`), **dedented to the level of `if e.movement != null:`** (i.e. one tab), insert:
```gdscript
	# p4-03: the current order is finished (IDLE) and more are queued -> start the next one now.
	# This is the ONE place the queue pops. ATTACK ends in CombatSystem.tick_all (later in the
	# same step), so its successor starts on the next tick.
	if e.order == Entity.Order.IDLE and not e.order_queue.is_empty():
		_pop_order_queue(e)
```
so the file reads `...e.order = Entity.Order.IDLE` / blank / the new block / `if e.weapon != null:` (old 328).

**2c. New helpers:** insert immediately before the comment line 456 `# --- Base building (Blueprint §5.2) / production (Blueprint §5.3) ---` (i.e. after `_issue_hold`):
```gdscript
# ---- Order queue (p4-03: Shift = queue) ----
## Returns the subset of `targets` to issue right now. With "queue": true, a unit that is busy
## (order != IDLE, or still holding queued orders) gets the order appended instead. Without it,
## the queue is cleared so the new order replaces everything. Position orders store the unit's own
## formation slot (same _formation_offsets as an immediate group move) so a queued group move
## fans out instead of stacking when it pops one unit at a time.
func _split_queued(cmd_type: String, targets: Array, cmd: Dictionary) -> Array:
	var queue: bool = cmd.get("queue", false)
	var now: Array = []
	var offsets := _formation_offsets(targets.size())
	for i in range(targets.size()):
		var e: Entity = entities.get(targets[i])
		if e == null:
			continue
		if queue and (e.order != Entity.Order.IDLE or not e.order_queue.is_empty()):
			var entry: Dictionary = {"type": cmd_type}
			if cmd_type == "ATTACK":
				entry["targetEntityId"] = cmd.get("targetEntityId", -1)
			else:
				entry["targetPosition"] = cmd.get("targetPosition", Vector2.ZERO) + offsets[i]
			e.order_queue.append(entry)
		else:
			if not queue:
				e.order_queue.clear()
			now.append(targets[i])
	return now

## Start the next queued order on one entity. Single-target calls, so _formation_offsets(1)
## contributes Vector2.ZERO and the stored slot is used as-is.
func _pop_order_queue(e: Entity) -> void:
	var next: Dictionary = e.order_queue.pop_front()
	match next.get("type", ""):
		"MOVE":
			_issue_move(0, [e.id], next.get("targetPosition", e.position))
		"ATTACK":
			_issue_attack(0, [e.id], next)
		"ATTACK_MOVE":
			_issue_attack_move(0, [e.id], next.get("targetPosition", e.position))

```
Do not touch `_issue_move`, `_issue_attack`, `_issue_attack_move`, `_issue_hold`, the STOP branch, or anything under "Control groups" (606-630). `gameplay/systems/CombatSystem.gd` and `gameplay/components/MovementComponent.gd` are not edited.

## Change 3 — `presentation/SelectionInput.gd`
Keep `_units_in_rect`, `_pickable`, `_unit_at_world`, `_structure_at_world`, `_merge_selection` byte-identical. Make these edits:

**3a. Header + state.** Extend the doc comment with the p4-03 line: `## p4-03: Ctrl+0-9 assign / 0-9 recall control groups (double-tap centres the camera), double-click selects every visible unit of the same type, Shift+order queues it.` Add `const DOUBLE_TAP_MSEC := 400   # same digit twice inside this window -> centre camera on the group` directly after the `enum Armed { NONE, ATTACK_MOVE }` line. Delete `var _shift: bool = false` (p4-04 left it in; its three tracking lines live in the `_unhandled_input` that 3b replaces). Add:
```gdscript
var _last_recall_group: int = -1
var _last_recall_msec: int = 0
```
Do NOT add `_skip_release` — p4-04's `elif _dragging:` guard already ignores the release after a consumed or double-click press.

**3b. Replace p4-04's `_unhandled_input` (from `func _unhandled_input` up to but not including `# --- p4-04 armed command mode`) with exactly:**
```gdscript
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
```

**3c. `_finish_drag` (53-65):** signature becomes `func _finish_drag(mouse_pos: Vector2, shift: bool) -> void:` and line 63 `if _shift:` becomes `if shift:`. Body otherwise unchanged.

**3d. Replace `_issue_context_order` (121-133) with:**
```gdscript
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
```
Change p4-04's `handle_right_click` to `func handle_right_click(world_pos: Vector2, queue: bool = false) -> void:` and its last line to `_issue_context_order(world_pos, queue)`; nothing else in it changes. p4-04's test calls it with one argument and must still print `P4_04_RESULT: ALL PASS`.

**3e. Append at the end of the file:**
```gdscript
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
```
`grep -n "_shift\|_skip_release" presentation/SelectionInput.gd` must return nothing afterwards. `godot-4 --headless --path . --check-only --script presentation/SelectionInput.gd` must exit 0 (it did in the probe).

**3f. `presentation/MiniMapRenderer.gd`** (Shift = queue applies to the minimap order too). Change p4-02's `func order_move_at(screen_pos: Vector2) -> void:` to `func order_move_at(screen_pos: Vector2, queue: bool = false) -> void:`, build the dict in a `var order: Dictionary = {...}`, and add `if queue: order["queue"] = true` before `orders_issued.emit([order])`, so the function body becomes:
```gdscript
func order_move_at(screen_pos: Vector2, queue: bool = false) -> void:
	var ids: Array = sim.selected_ids
	if ids.is_empty():
		return
	var order: Dictionary = {"type": "MOVE", "entityIds": ids, "targetPosition": minimap_to_world(screen_pos)}
	if queue:
		order["queue"] = true
	orders_issued.emit([order])
```
In `_input`'s RMB branch call `order_move_at(event.position, event.shift_pressed)` instead of `order_move_at(event.position)`. Nothing else in the file changes. p4-02's test (one-arg call, no `queue` key) is unchanged and must stay ALL PASS.

## Change 4 — `presentation/Game.gd` (capture flag only)
- After `var debug_select := ""` add `var debug_select_type := ""`.
- In the arg loop, directly after the `--select=` branch add:
  ```gdscript
  		elif a.begins_with("--select-type="):
  			debug_select_type = a.trim_prefix("--select-type=")
  ```
- After the `debug_select` block (the `if debug_select != "":` block) and BEFORE p4-04's `if debug_armed:` block — so `--select-type=X --armed` arms the typed selection — add:
  ```gdscript
  	if debug_select_type != "":
  		# p4-03: drive the double-click type-select from the first entity with that def, so a
  		# capture shows every on-screen unit of the type ringed. Prints the count for pixel checks.
  		for e in sim.entities.values():
  			if e.def_id == debug_select_type:
  				var ids: Array = selection_input.select_same_type(e.id)
  				print("SELECT_TYPE: %s -> %d units" % [debug_select_type, ids.size()])
  				_on_selection(ids)
  				break
  ```
  `selection_input` is already in the tree at this point (added at 93), so `get_viewport_rect()` inside `_camera_world_rect` is valid. Also add `--select-type=<def_id>` to the flag comment at 111-114.

## Test — new file `tests/test_p4_03_orders.gd`
Harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_init`, `_check`, `_fail`, `_run`, one `RESULT` line, `quit()`). No new `class_name`, so no `--import` step.
```gdscript
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
```
This exact file (with a 4 px tolerance in the two "arrived" checks that the probe showed to be flaky for a 9 px footprint — hence `footprint_radius` above) printed `P4_03_RESULT: ALL PASS` against Changes 1-2, and `test_phase5/6/7` stayed `ALL PASS` with the tolerance change.

## Screenshot
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_p4_type_select.png --frame=2 --select-type=VC-U01
```
`--frame=2`, not 90, on purpose: an unrelated pre-existing bug makes the idle trooper nearest the northern resource field walk off toward it within a few seconds (see the notes at the end), and this capture is about static selection rings. Stdout must contain `SELECT_TYPE: VC-U01 -> 7 units` (fact #8) and `CAPTURED:` with `err=0`.

Pixel check (executors cannot view PNGs; `~/AI_Agent/venv/bin/python` has Pillow):
```
~/AI_Agent/venv/bin/python - <<'EOF'
from PIL import Image
im = Image.open("docs/screenshot_p4_type_select.png").convert("RGB"); px = im.load(); w, h = im.size
n = sum(1 for y in range(h) for x in range(w) if px[x,y][0] < 60 and px[x,y][1] > 190 and 50 < px[x,y][2] < 150)
print("ring-green px:", n)
EOF
```
Expected ≥ 2000 (probe measured 2610; the same recipe **without** `--select-type` measures 0, so any count above ~200 proves rings are drawn — 2000 proves several). Then the things F eyeballs: five full green rings around the Maker Crew troopers ringing the Garage (two more troopers sit under the top-left resource bar, so their rings are clipped — expected); the bottom-left HUD panel reads `7 units` / `7× Maker Crew`; none of the 13 one-of-a-kind roster vehicles/drones on the outer ring carries a ring; no structure carries brackets.

## Done when
- `godot-4 --headless --path . --script tests/test_p4_03_orders.gd` prints `P4_03_RESULT: ALL PASS`.
- `godot-4 --headless --path . --script tests/test_p4_04_armed_commands.gd` still prints `P4_04_RESULT: ALL PASS` (p4-04's SelectionInput API survives the 3b/3d merge).
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS` — 14 suites including the new one — no `SCRIPT ERROR` (test_phase6 and test_phase7 exercise ATTACK_MOVE / HOLD and must stay green with the tolerance change).
- `godot-4 --headless --path . --check-only --script presentation/SelectionInput.gd` and the same for `presentation/Game.gd` exit 0.
- `grep -n "_shift\|_skip_release" presentation/SelectionInput.gd` returns nothing; `grep -n "order_queue" gameplay/` returns nothing (CombatSystem untouched).
- `git status --short` shows exactly ` M core/simulation/Entity.gd`, ` M core/simulation/Simulation.gd`, ` M presentation/Game.gd`, ` M presentation/MiniMapRenderer.gd`, ` M presentation/SelectionInput.gd`, `?? tests/test_p4_03_orders.gd`, `?? docs/screenshot_p4_type_select.png` from your work. Nothing under `gameplay/`, `presentation3d/`, `ui/`. `*.import` and `*.uid` are gitignored — do not add them. The tree already carries unrelated untracked files (`tools/deepseek_id_probe.py`, `tools/deepseek_vision_check.py`); leave them alone — `git add` only the seven files above, never `-A`.
- `docs/screenshot_p4_type_select.png` passes the pixel check and the stdout line says 7.
- Commit, then push:
  `feat(controls): control groups 0-9, double-click type select, Shift order queue`
  Body (3–6 lines): Entity.order_queue + "queue": true on MOVE/ATTACK/ATTACK_MOVE, popped in _tick_entity only; STOP/HOLD/non-queued orders clear it; MOVE arrival tolerance = footprint_radius (p1-07 stopped vehicles 4–12 px short and never went IDLE); Ctrl+digit assigns via CONTROL_ASSIGN, digit recalls (double-tap centres camera via RTSCamera.center_on); double-click selects same def_id in the camera rect; Shift is read from the mouse event (old _shift flag was reset by every event) and also queues the minimap MOVE (MiniMapRenderer.order_move_at queue flag).
  `git push origin master`
- Report: `git log --oneline -1`, the `P4_03_RESULT` line, the `P4_04_RESULT` line, the `SELECT_TYPE` line, the ring-green pixel count, and the screenshot path.

## Notes for F (not part of this ticket)
- **Units attack resource fields.** `spawn_resource_field` (Simulation.gd:142-148) creates the field with faction `""`; `CombatSystem._acquire_target` (109-126) only excludes `cand.faction_id == e.faction_id` (116) and `_target_tag_valid` defaults a missing `armorClass` to `"Infantry"` (142), so every idle unit with an infantry-capable weapon acquires the nearest field and shoots it. Probe: a VC-U01 spawned at (1105, 980) next to a field at (1200, 800) had `current_target_id == field`, was moving, and the field's HP had dropped to 92 after 30 ticks. That is why `--frame=90` captures lose the 0° trooper. Own C ticket: skip `faction_id == ""` (or `e.resource != null`) in `_acquire_target`, plus a headless check.
- `_units_in_rect` (SelectionInput.gd:67-72) does not filter `alive`, so a drag box can select garrisoned units (alive=false, still in `entities`, Simulation.gd:654). The type-select filters `alive` itself; a one-word fix to `_units_in_rect` is a separate C tweak.
