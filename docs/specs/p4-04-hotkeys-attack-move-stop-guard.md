# p4-04 — A attack-move, S stop, G guard; one armed click-target mode shared by keys and HUD buttons

**Tier:** P (DeepSeek Pro) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/SelectionInput.gd`, `ui/HUD.gd`, `presentation/Game.gd`, new `tests/test_p4_04_armed_commands.gd`, new `docs/screenshot_armed_attack.png`

Why P, not C: three source files with a cross-file wiring (HUD buttons drive SelectionInput's state and light up from its signal) and one input-priority subtlety (Escape must beat PauseMenu). Not O: there is no judgement left — every function below is written out and was verified headless plus by capture before this ticket was written. **No sim change:** `core/` and `gameplay/` are untouched — the sim already has every order this needs (evidence below).

Read `docs/specs/README.md` first. Do NOT touch `core/`, `gameplay/` or `presentation3d/`.

**Order:** Lands third, after p4-01 and p4-02, BEFORE p4-03. This ticket owns SelectionInput's input entry point: the `Armed` enum, `armed_changed`, `_input` (Escape), the pure `arm/disarm/handle_key/handle_escape/handle_left_click/handle_right_click/issue_simple` API and the `elif _dragging:` release guard. p4-03 extends `_unhandled_input` and `handle_right_click` afterwards; apply this ticket verbatim and do not restructure beyond it. The `_shift` variable and its three tracking lines are kept here only so this ticket stays a pure addition — p4-03 deletes them. Full landing order: p4-01, p4-02, p4-04, p4-03, p4-05. It binds A, S, G, Escape (and the mouse buttons only while armed) — see **Keys** at the end.

## Why
The game has right-click move/attack and nothing else. An RTS needs attack-move (advance and fight what you meet), stop, and guard as one-key orders, and the HUD's selection card needs order buttons that put the game into a "click a target" mode (`docs/visual-roadmap.md:80`: "Move / Attack / Rally buttons need a click-target mode in `SelectionInput`"; `docs/execution-plan.md:93`: the Phase 4 row "`A` attack-move, `S` stop, `G` guard"). The STOP button's tooltip already promises "(S)" (`ui/HUD.gd:83`) but no key is bound anywhere (`grep -rn "KEY_" presentation ui` → only KEY_SHIFT, KEY_ALT, KEY_ESCAPE).

## Current facts you will rely on (HEAD `bd73d1c`)

### The sim already has every order (no change needed)
- `core/simulation/Entity.gd:33-36` — `enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD }`, `order`, `order_target`, `order_dest`.
- `core/simulation/Simulation.gd:339-383` — `run_commands(id, commands)`: each command is a Dictionary with `"type"` and `"entityIds"` (line 342-343). Relevant branches:
  - `"ATTACK_MOVE"` (349-350) → `_issue_attack_move(id, targets, cmd.get("targetPosition", Vector2.ZERO))` (431-445): paths each unit to `targetPosition + formation offset`, sets `order = ATTACK_MOVE`, `order_dest`. **Dict shape:** `{"type": "ATTACK_MOVE", "entityIds": [..], "targetPosition": Vector2}` (this is what `tests/test_phase7.gd:134` sends).
  - `"STOP"` (351-360) — handled inline, there is no `_issue_stop`: `order = IDLE`, `movement.clear()`, `weapon.current_target_id = -1`. **Dict shape:** `{"type": "STOP", "entityIds": [..]}` (what `ui/HUD.gd:156` sends today). So S = STOP; nothing to add.
  - `"HOLD"` (361-362) → `_issue_hold` (447-454): `order = HOLD`, `movement.clear()`. **Dict shape:** `{"type": "HOLD", "entityIds": [..]}`.
- **HOLD already means "guard": stay put, engage anything in range, never chase.** `gameplay/systems/CombatSystem.gd:35-46` — acquisition runs for every order except ATTACK, so a HOLD unit acquires; `:54-59` — the chase step is skipped when `e.order == Entity.Order.HOLD` (comment on line 55: "HOLD never chases"); `:60-62` — fires when in range. `tests/test_phase7.gd:152-159` pins "HOLD never chases". Therefore **G maps to HOLD and no sim change is needed.** (The p1-07 table in `docs/specs/p1-07-order-state-attack-move.md` says the same: HOLD = "yes, but never chases".)
- `Simulation.gd:34` — `selected_ids: Array` is owned by the sim; `presentation/Game.gd:294-300` `_on_selection(ids)` writes it and re-emits `events.entity_selected` (`core/simulation/GameEvents.gd:9`) for the HUD.
- `gameplay/components/MovementComponent.gd:31-38` — `clear()` / `is_moving()`; `gameplay/components/WeaponComponent.gd:26-27` — `current_target_id`, `acquire_radius`. VC-U04 (Technical) has `wpn_autocannon` range 160 (`tests/test_phase7.gd:150`).

### How presentation issues orders today
- `presentation/SelectionInput.gd` (Node2D, `class_name SelectionInput`): signals `orders_issued(orders)` and `selection_changed(ids)` (7-8); `_init(cam, simulation)` just stores both (18-20), so `SelectionInput.new(null, sim)` works headless. `_unhandled_input` (30-51): shift tracking (31-35), **left press always starts a drag** (37-41), **left release always calls `_finish_drag`** even when no press was seen (42-45), **right press → `_issue_context_order`** (46-47). `_issue_context_order` (121-133): ATTACK if a visible hostile unit is under the cursor (`{"type":"ATTACK","entityIds":ids,"targetEntityId":id}`, line 130), else MOVE (`{"type":"MOVE","entityIds":ids,"targetPosition":world_pos}`, line 132). There is no attack-move, stop or hold anywhere in presentation.
- `presentation/Game.gd:92-95` — creates `SelectionInput`, connects `orders_issued → _on_orders` (291-292: `sim.run_commands(0, orders)`) and `selection_changed → _on_selection`. Tree order of the input nodes (all children of Game): `hud` (88-89), `selection_input` (92-93), `placement_ghost` (98-99), `pause_menu` (102-103).
- `ui/HUD.gd` — the selection card has **one order button, STOP** (`_stop_button` var line 20; built 79-86; `_on_stop` 154-156 calls `sim.run_commands` directly, bypassing `orders_issued`). Its visibility is set in two places: 167 (group: always) and 188 (single: `e.kind == "unit"`). **There are no Move / Attack / Rally buttons** and `SET_RALLY` has no presentation wiring at all (`grep -rn -i rally ui presentation` → nothing). This ticket adds ATTACK and GUARD next to STOP; MOVE / RALLY buttons are a later ticket and the enum below has room for them.
- `ui/UiTheme.gd:50-60` `style_button()` already defines a `"pressed"` stylebox (line 54: accent at 0.35 alpha, accent border), so a `toggle_mode` Button lights up with no new theme code.
- **Escape today:** `ui/PauseMenu.gd:40-43` consumes Escape in `_unhandled_input`; `ui/PlacementGhost.gd:48-62` consumes Escape / clicks in `_input` while placing. Godot dispatches `_input` and `_unhandled_input` bottom-up (later siblings first), so PauseMenu — added after SelectionInput — would see Escape before SelectionInput's `_unhandled_input` ever does. That is why the Escape handler below lives in `_input`.
- p4-01 already deleted the `[input]` block from project.godot (nothing read it) and gave RTSCamera an `_input` (middle button) and an `_unhandled_input` that handles the wheel and H. RTSCamera sits earlier in the tree than SelectionInput, so SelectionInput's `_unhandled_input` sees keys first: `handle_key` must return false for every key but A/S/G (it does), which lets H fall through to the camera.
- Debug flags: `presentation/Game.gd:115-143` arg loop (`--capture=`, `--frame=`, `--capture-frames=`, `--select=`, `--train=`, `--place=`, `--pause`, `--motion`, `--attack`); `--select=<def_id>` (146-153) calls `_on_selection([e.id])` for the first entity with that def.

## Design (implement exactly this)
One state machine in `SelectionInput`: `enum Armed { NONE, ATTACK_MOVE }`. A key (A) or the HUD ATTACK button arms it; the next **left click in the world** consumes it and emits the order; **Escape or right click** cancel it (right click while armed issues nothing — it was a cancel, not an order). S and G are instant orders (STOP / HOLD) and also clear any armed mode. Escape with nothing armed deselects; with nothing selected either it is not consumed, so it still reaches PauseMenu. `arm()` is a no-op with nothing selected (nobody to order; a stray A must not swallow the next selection click). Every input event is translated into a public call (`handle_key`, `handle_left_click`, `handle_right_click`, `handle_escape`, `arm`, `disarm`, `issue_simple`) so the test drives the logic with no viewport.

Two reasonable designs existed for Escape: `_input` (chosen) vs. reordering the nodes so SelectionInput precedes PauseMenu — `_input` is chosen because it does not change any other node's behaviour and PlacementGhost already uses the same trick.

## Change 1 — `presentation/SelectionInput.gd`

### 1a. Signals, enum, state (replace lines 7-16)
```gdscript
signal orders_issued(orders: Array)
signal selection_changed(ids: Array)
## p4-04: the armed click-target mode changed (HUD highlights the matching button).
signal armed_changed(mode: int)

## p4-04 armed command mode. A hotkey or a HUD button arms it, the next left click in the
## world consumes it, Escape or right click cancels it. One enum so the HUD buttons and the
## keys share the same state; add MOVE / RALLY here when those buttons exist.
enum Armed { NONE, ATTACK_MOVE }

var rts_cam: RTSCamera
var sim: Simulation

var armed: Armed = Armed.NONE
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO   # world
var _drag_current: Vector2 = Vector2.ZERO
var _shift: bool = false
```

### 1b. Escape in `_input` (new function, insert right before `_unhandled_input`)
```gdscript
## Escape is taken here, in _input, because PauseMenu consumes it in _unhandled_input and sits
## later in the tree (Game.gd adds it after us), so it would never reach our _unhandled_input.
## PlacementGhost also uses _input and is added later still, so an active placement still wins.
## Only consumed when there is something to cancel: with nothing armed and nothing selected the
## event falls through and Escape still pauses.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if handle_escape():
			get_viewport().set_input_as_handled()
```

### 1c. `_unhandled_input` (replace lines 30-51 with this; the shift lines are unchanged)
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	_shift = event is InputEventKey and event.keycode == KEY_SHIFT # fallback; tracked via state
	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT:
		_shift = true
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_SHIFT:
		_shift = false

	if event is InputEventKey and event.pressed and not event.echo:
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if handle_left_click(rts_cam.screen_to_world(event.position)):
				get_viewport().set_input_as_handled()
				return
			_dragging = true
			_drag_start = rts_cam.screen_to_world(event.position)
			_drag_current = _drag_start
		elif _dragging:
			_dragging = false
			_finish_drag(event.position)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		handle_right_click(rts_cam.screen_to_world(event.position))

	if _dragging:
		_drag_current = rts_cam.screen_to_world(get_viewport().get_mouse_position())
		queue_redraw()
```
The `elif _dragging:` guard is required: an armed click consumes the press, so its release must not run `_finish_drag` and replace the selection.

### 1d. The pure API (insert right after `_unhandled_input`, before `_finish_drag`)
```gdscript
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
func handle_right_click(world_pos: Vector2) -> void:
	if armed != Armed.NONE:
		disarm()
		return
	_issue_context_order(world_pos)

## An order with no target ("STOP", "HOLD") for the current selection. False with no selection.
func issue_simple(cmd_type: String) -> bool:
	if sim.selected_ids.is_empty():
		return false
	orders_issued.emit([{"type": cmd_type, "entityIds": sim.selected_ids.duplicate()}])
	return true
```
Nothing else in the file changes: `_draw`, `_finish_drag`, `_units_in_rect`, `_pickable`, `_unit_at_world`, `_structure_at_world`, `_merge_selection`, `_issue_context_order` stay byte-identical.

## Change 2 — `ui/HUD.gd`

### 2a. Vars (after line 20 `var _stop_button: Button`)
```gdscript
var _attack_button: Button   # p4-04: toggle, lit while SelectionInput is armed ATTACK_MOVE
var _guard_button: Button
var selection_input: SelectionInput = null   # p4-04: set by Game.gd via bind_input()
```

### 2b. Buttons (insert right after line 86 `header.add_child(_stop_button)`)
```gdscript
	# p4-04: ATTACK arms the click-target mode (same state as the A key); GUARD = HOLD (G).
	_attack_button = Button.new()
	_attack_button.text = "ATTACK"
	_attack_button.toggle_mode = true
	_attack_button.custom_minimum_size = Vector2(56, 0)
	_attack_button.focus_mode = Control.FOCUS_NONE
	_attack_button.tooltip_text = "Attack-move: then click a point (A)"
	UiTheme.style_button(_attack_button, faction)
	_attack_button.toggled.connect(_on_attack_toggled)
	header.add_child(_attack_button)
	_guard_button = Button.new()
	_guard_button.text = "GUARD"
	_guard_button.custom_minimum_size = Vector2(56, 0)
	_guard_button.focus_mode = Control.FOCUS_NONE
	_guard_button.tooltip_text = "Hold position, return fire (G)"
	UiTheme.style_button(_guard_button, faction)
	_guard_button.pressed.connect(_on_guard)
	header.add_child(_guard_button)
```

### 2c. Replace `_on_stop` (lines 154-156) with
```gdscript
## p4-04: the order buttons share SelectionInput's armed state and its orders_issued path
## (Game._on_orders -> sim.run_commands) instead of talking to the sim directly.
func bind_input(si: SelectionInput) -> void:
	selection_input = si
	si.armed_changed.connect(_on_armed_changed)

func _on_stop() -> void:
	selection_input.issue_simple("STOP")

func _on_guard() -> void:
	selection_input.issue_simple("HOLD")

func _on_attack_toggled(on: bool) -> void:
	if on:
		selection_input.arm(SelectionInput.Armed.ATTACK_MOVE)
		if selection_input.armed != SelectionInput.Armed.ATTACK_MOVE:
			_attack_button.set_pressed_no_signal(false)   # arm() refused (nothing selected)
	else:
		selection_input.disarm()

func _on_armed_changed(mode: int) -> void:
	_attack_button.set_pressed_no_signal(mode == SelectionInput.Armed.ATTACK_MOVE)
```
(`set_pressed_no_signal` avoids the toggle → arm → armed_changed → toggle loop.)

### 2d. Visibility — the three buttons show and hide together
Line 167 `_stop_button.visible = true` → `_set_order_buttons_visible(true)`.
Line 188 `_stop_button.visible = e.kind == "unit"` → `_set_order_buttons_visible(e.kind == "unit")`, and add after `_refresh_selection`:
```gdscript
func _set_order_buttons_visible(on: bool) -> void:
	_stop_button.visible = on
	_attack_button.visible = on
	_guard_button.visible = on
```
Nothing else in HUD.gd changes.

## Change 3 — `presentation/Game.gd`
1. After line 95 (`selection_input.selection_changed.connect(_on_selection)`) add:
   ```gdscript
   	hud.bind_input(selection_input)   # p4-04: HUD order buttons share the armed state
   ```
   (`hud` exists since line 88, `selection_input` since line 92 — both are ready here.)
2. Debug flag `--armed` (cheap: three lines) so the capture shows the lit button. Locate by quoted code, not line number — p4-01 and p4-02 have already shifted the file:
   - after the existing debug locals (p4-01's `debug_cam`, p4-02's `debug_minimap_click`) add `var debug_armed := false`;
   - in the arg loop, directly after p4-02's `elif a.begins_with("--minimap-click="):` branch, before `elif a == "--attack":` add
     ```gdscript
     		elif a == "--armed":
     			debug_armed = true   # p4-04: arm ATTACK_MOVE after --select so the HUD button lights
     ```
   - after the `debug_select` block, before `if debug_place != "":` (p4-03 will later insert its `if debug_select_type` block between the two) add
     ```gdscript
     	if debug_armed:
     		selection_input.arm(SelectionInput.Armed.ATTACK_MOVE)
     ```
   Nothing else in Game.gd changes.

## Test — new file `tests/test_p4_04_armed_commands.gd`
Harness copied from `tests/test_phase7.gd:167-183` (`extends SceneTree`, `_init`, `_check`, `_fail`, `_run`, `RESULT` line, `quit()`). The node never enters the tree; `free()` it at the end like `tests/test_shadows.gd` does. No new `class_name`, so no `--import` step.

```gdscript
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
```
Expected: 28 `PASS` lines and `P4_04_RESULT: ALL PASS`. The trailing `ERROR: N resources still in use at exit` line is pre-existing on every suite (test_shadows / test_phase7 print it too) and is not a failure. Dictionary `==` is a deep compare in Godot 4.7, so the exact-dict checks are exact.

## Screenshot — `docs/screenshot_armed_attack.png`
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_armed_attack.png --frame=90 --select=VC-U04 --armed
```
Expect `CAPTURED:... size=(1280, 720) err=0`. The selection card (bottom-left) shows the Technical with three buttons `STOP | ATTACK | GUARD`; ATTACK is lit (accent-tinted, `UiTheme.style_button` "pressed" box) and the other two are dim glass.

**Executor's pixel check** (you cannot view the PNG; measure it). Scan the row through the button faces:
```
~/AI_Agent/venv/bin/python - <<'EOF'
from PIL import Image
im = Image.open("docs/screenshot_armed_attack.png").convert("RGB")
lit  = [x for x in range(255, 450) if (lambda p: p[2] > 80 and p[2] > 2 * p[0])(im.getpixel((x, 663)))]
dim  = [x for x in range(255, 450) if (lambda p: abs(p[0]-29) < 8 and abs(p[2]-43) < 8)(im.getpixel((x, 663)))]
print("lit run:", (min(lit), max(lit)) if lit else None, "width", len(lit), "| dim px:", len(dim))
print("contiguous:", bool(lit) and max(lit)-min(lit)+1 == len(lit))
EOF
```
Pass when `contiguous: True` and `50 <= len(lit) <= 60` — one contiguous lit run about 50-60 px wide (measured ~x 324-380 at HEAD's layout: face colour ≈ (7, 82, 101)) and roughly 100+ dim pixels split on both sides of it (STOP and GUARD faces ≈ (29, 33, 43)). If the card's font or layout has shifted a few px, scan rows 660-668 instead of 663 only (row 658 lands on the chips' accent hairline border and matches scattered pixels across all three chips — not a valid row). **F eyeballs:** the ATTACK chip reads as the one lit button, the card is not clipped by the new width, and the tooltips make sense on hover.

## Manual checks (F, in a live run — the viewport path is not headless-testable)
Run `godot-4 --path .`, drag-select a few units: **A** → cursor click on open ground → units advance and engage the FC squad they meet (attack-move) — the ATTACK chip lights while armed and goes dark on the click. **Right click while armed** → chip goes dark, units do nothing. **S** → units stop mid-walk. **G** → units stop and shoot anything that comes in range without chasing. **Escape** while armed → cancels only; Escape again → deselects (card collapses); Escape a third time → pause menu. Clicking the HUD ATTACK chip behaves exactly like A; STOP / GUARD chips like S / G. Placing a building (build grid → click) still cancels with Escape / right click first.

## Done when
- `godot-4 --headless --path . --script tests/test_p4_04_armed_commands.gd` prints `P4_04_RESULT: ALL PASS`.
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS`, no `SCRIPT ERROR` / `Parse Error` (13 suites after this one — test_camera and test_minimap already landed).
- `git status --short` shows exactly ` M presentation/SelectionInput.gd`, ` M ui/HUD.gd`, ` M presentation/Game.gd`, `?? tests/test_p4_04_armed_commands.gd`, `?? docs/screenshot_armed_attack.png` from your work. Nothing under `core/`, `gameplay/`, `presentation3d/`. `*.import` and `*.uid` are gitignored — do not add them. The tree may carry unrelated untracked files (e.g. `tools/deepseek_*.py`); leave them alone — `git add` only the five files above, never `-A`.
- `grep -n "sim.run_commands(" ui/HUD.gd` returns nothing (the HUD now orders only through SelectionInput; the paren matches only a call — the 2c doc comment mentions `sim.run_commands` in prose and is fine).
- `docs/screenshot_armed_attack.png` passes the pixel check above.
- Commit, then `git push origin master`:
  `feat(input): A attack-move, S stop, G guard; armed click-target mode shared by keys and HUD buttons`
  Body (3–6 lines): SelectionInput gains an `Armed` state machine (NONE / ATTACK_MOVE) with a pure handle_* API; A arms, next left click issues ATTACK_MOVE, Escape / right click cancel; S = STOP, G = HOLD (sim already treats HOLD as guard — no sim change); HUD ATTACK (toggle, lit from armed_changed) and GUARD chips next to STOP, all routed through orders_issued; Escape handled in _input so it beats PauseMenu; `--armed` debug flag for the capture.
- Report: `git log --oneline -1`, the `P4_04_RESULT` line, the pixel-check output, and the screenshot path.

## Keys
| Key / button | Action | Where |
|---|---|---|
| **A** | arm ATTACK_MOVE (no-op with nothing selected) | `SelectionInput.handle_key` via `_unhandled_input` |
| **S** | STOP the selection; clears any armed mode | same |
| **G** | HOLD (guard) the selection; clears any armed mode | same |
| **Escape** | cancel armed → else deselect → else not consumed (PauseMenu) | `SelectionInput._input` |
| **LMB** (only while armed) | consumed: issues the armed order at the click, no drag-select | `_unhandled_input` |
| **RMB** (only while armed) | cancel, no order; unarmed RMB is the existing context ATTACK/MOVE | `_unhandled_input` |
| HUD **ATTACK** toggle / **GUARD** / **STOP** chips | same as A / G / S | `ui/HUD.gd` → `SelectionInput` |

LMB/RMB on the minimap rect are p4-02's (`MiniMapRenderer._input` runs before this node's `_unhandled_input`); they jump the camera / issue a plain MOVE and leave the armed mode as it is — intended.

Not bound here, on purpose: WASD (camera ticket uses arrows / MMB / edge), H, digits, Shift (the p4-03 queue ticket), Ctrl. The old InputMap actions on W/S/A/D are gone (p4-01); nothing to read.
