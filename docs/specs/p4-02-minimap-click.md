# p4-02 — Minimap interaction: left-click/drag jumps the camera, right-click orders MOVE

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/MiniMapRenderer.gd` (the real work), `presentation/Game.gd` (+13 lines: one signal connect, one debug flag), new `tests/test_minimap.gd`, new `docs/screenshot_minimap_jump.png`

Why C: one presentation file gets the feature, the `Game.gd` edit is mechanical and given verbatim below, the new behaviour is a pure affine screen<->world mapping that a headless test pins exactly, and the capture is a fixed recipe with a pixel check. No sim code, no new systems, no design judgement. **This ticket does NOT change `core/` or `gameplay/`** — the only sim call is the existing `Simulation.run_commands` with the existing `MOVE` dict, sent through `Game._on_orders` exactly like `SelectionInput` does.

Read `docs/specs/README.md` first. Do NOT touch `core/`, `gameplay/`, or `presentation3d/` (shelved). The game is 2D.

**Order:** Lands second, after p4-01, which ships `RTSCamera.center_on(world_pos)` (position only; p4-01's smoothing is on zoom, not position, so there is no position target to set). Before p4-03/p4-04, whose SelectionInput rewrite does not affect this ticket. Phase 4 landing order: p4-01, p4-02, p4-04, p4-03, p4-05.

## Why
The minimap (`presentation/MiniMapRenderer.gd`) is display-only today. There is no `_input`/`_unhandled_input` anywhere in that file (`grep -rn "_unhandled_input\|func _input(" presentation ui` lists only `RTSCamera.gd:36`, `SelectionInput.gd:30`, `ui/PlacementGhost.gd:48`, `ui/PauseMenu.gd:40`). Consequences today:

- **Bug:** `presentation/SelectionInput.gd:37-41` starts a drag-select box on *any* left press — no hit-test — so clicking the minimap begins a selection box in the world under the minimap, and `SelectionInput.gd:42-44` runs `_finish_drag` on *any* left release, so releasing over the minimap click-selects whatever is under it in world space. A right press anywhere (`SelectionInput.gd:46-47`) issues a world-space context order, so right-clicking the minimap sends units to the world point *behind* the minimap.
- C&C convention (what this ticket adds): left-click or left-drag on the minimap centres the camera on that map point; right-click on the minimap sends the current selection there.

## Current facts you will rely on (HEAD `bd73d1c`)

`presentation/MiniMapRenderer.gd`
- `extends Node2D`, `class_name MiniMapRenderer` (1-2). Constructor `_init(_sim, fog, faction, cam)` (30-36) stores `sim`, `fog_sys`, `player_faction`, `rts_cam` (8-11) and sets `z_index = 100` (36). `rts_cam` may be null — `_camera_world_rect` guards it (99-101).
- `MAP_SIZE := 220.0`, `MARGIN := 16.0` (13-14). `_draw()` (54-97) computes `vp = get_viewport_rect().size`, `origin = (vp.x - MAP_SIZE - MARGIN, vp.y - MAP_SIZE - MARGIN)`, `rect = Rect2(origin, MAP_SIZE²)` (57-59). At 1280x720 that is origin **(1044, 484)**, rect **(1044, 484, 220, 220)**.
- World extent comes from the fog grid: `gw = fog_sys.grid_width()`, `gh = fog_sys.grid_height()`, `cell = fog_sys.cell_size()` (63-65); dots map with `origin.x + (e.position.x / (gw * cell)) * MAP_SIZE` (84-85); the camera box uses the same formula on `_camera_world_rect()` (90-97), which is `Rect2(rts_cam.screen_to_world(Vector2.ZERO), vp / rts_cam.zoom)` (99-104).
- `COL_CAM_BOX := Color(0.9, 0.9, 0.8, 0.85)` drawn 1.5 px wide (23, 97) — the thing F checks in the screenshot.
- The minimap lives on its own `CanvasLayer` at `layer = 20` (`presentation/Game.gd:80-85`); the HUD is `layer = 30` (`ui/HUD.gd:28`) but only owns top-left and bottom-left panels (`ui/HUD.gd:33, 44`, both `MOUSE_FILTER_IGNORE` at 36/48; docstring at 7: "Minimap stays bottom-right on its own layer"). Its match-over panel is full-rect (`ui/HUD.gd:101-104`) but only shows once the tree is paused, and paused nodes get no input. So nothing GUI-side overlaps the minimap rect.

World size: `Game.gd:41-43` builds `NavGrid.new(50, 50)` / `Simulation.new(registry, events, 50, 50)`; `Simulation._init` (`core/simulation/Simulation.gd:45-50`) creates `fog_sys = FogOfWarSystem.new(grid_w, grid_h, NavGrid.CELL)`; `NavGrid.CELL = 40.0` (`core/spatial/NavGrid.gd:8`); accessors `grid_width()/grid_height()/cell_size()` at `gameplay/systems/FogOfWarSystem.gd:103-108`. So the map is **2000x2000 world px** and one minimap px = 2000/220 = 9.0909 world px.

`presentation/RTSCamera.gd`
- `position` is the view centre; `screen_to_world(p) = (p - viewport_size()/2) / zoom + position`. `center_on(world_pos)` (p4-01) sets `position` and calls `_clamp_to_world()` immediately, which clamps to `[half_view, world - half_view]` per axis (half_view = viewport_size()/(2*zoom)); at 1280x720, zoom 1, the legal centre range is x 640..1360, y 360..1640. RTSCamera's `_unhandled_input` handles the wheel and H, its `_input` handles the middle button only — nothing in the camera competes for LMB/RMB.

`presentation/SelectionInput.gd`
- `signal orders_issued(orders: Array)` (7). The ground right-click builds **exactly** `{"type": "MOVE", "entityIds": ids, "targetPosition": world_pos}` with `ids = sim.selected_ids` and returns early when the selection is empty (121-133; the dict is line 132). `Game.gd:94` connects `orders_issued` to `_on_orders`, which is `sim.run_commands(0, orders)` (291-292). `Simulation.run_commands` dispatches `"MOVE"` to `_issue_move(id, targets, cmd.get("targetPosition"))` (339-346), which sets `e.order = Entity.Order.MOVE` and `e.order_dest` (385-398).

`presentation/Game.gd`
- Node creation order in `_ready`: `rts_cam` (49-52), … `minimap_layer`/`minimap` (80-85), `hud` (88-89), `selection_input` (92-95), `placement_ghost` (98-99), `pause_menu` (102-103).
- Debug arg loop 115-143: locals `debug_select/debug_train/debug_place/debug_pause/debug_motion` (116-120), `--motion` handled at 138-139, `--attack` at 140-143. Default capture frame set at 144-145. The `if debug_motion:` block (158-169) ends with `rts_cam.set_zoom_now(2.0)` / `rts_cam.position = Vector2(900, 475)` followed by p4-01's `if debug_cam != "":` block, which is the **last** statement of `_ready` once p4-01 has landed.
- `_capture_now` (259-286) prints `CAPTURED:<path>` and quits.

**Godot input order (verified in Godot 4.7.2 with a throwaway probe, 2026-09-22):** every node's `_input` runs (last-added node first) before *any* node's `_unhandled_input`; `get_viewport().set_input_as_handled()` inside `_input` stops every later callback, `_input` and `_unhandled_input` alike. That is why the minimap uses `_input`: it beats `SelectionInput`/`RTSCamera` (both `_unhandled_input`) no matter where it sits in the tree. `PlacementGhost` also uses `_input` (`ui/PlacementGhost.gd:48-62`) and is added after the minimap (`Game.gd:99` vs `85`), so **while a placement is active the ghost still wins** — that is the existing priority (ghost > everything) and this ticket keeps it. Resulting priority for a mouse button: PlacementGhost (if active) → **MiniMap (if the cursor is on it)** → SelectionInput / RTSCamera.

## Change 1 — `presentation/MiniMapRenderer.gd`

### 1a. Header
Extend the docstring (after line 6) with:
```gdscript
## p4-02: left-click / left-drag jumps the camera, right-click orders a MOVE for the
## current selection. Handled in _input (before GUI and every _unhandled_input) so the
## world's drag-select never starts on a minimap click.
```
Add after the docstring, before `var sim` (line 8):
```gdscript
signal orders_issued(orders: Array)
```
Add after `var _terrain_tex` (line 21):
```gdscript
var _drag_jump: bool = false               # left button held after a press on the minimap
```

### 1b. Mapping, hit-test, actions, input — insert between `_build_terrain_texture` (ends line 52) and `_draw` (line 54)
```gdscript
# --- p4-02: screen<->world mapping. One source of truth for _draw, the hit-test and input. ---

## Screen-space rect the minimap occupies: MAP_SIZE square, MARGIN in from the bottom-right.
func minimap_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2(vp.x - MAP_SIZE - MARGIN, vp.y - MAP_SIZE - MARGIN), Vector2(MAP_SIZE, MAP_SIZE))

## World extent the minimap covers (grid cells x cell size), from the fog system's grid.
func world_size() -> Vector2:
	return Vector2(fog_sys.grid_width(), fog_sys.grid_height()) * fog_sys.cell_size()

## True when a screen point lands on the minimap (Rect2.has_point: top/left edges inclusive,
## bottom/right exclusive).
func contains_screen(screen_pos: Vector2) -> bool:
	return minimap_rect().has_point(screen_pos)

## Screen point -> world point. Pure affine; not clamped (a drag can leave the rect).
func minimap_to_world(screen_pos: Vector2) -> Vector2:
	var r := minimap_rect()
	return (screen_pos - r.position) / r.size * world_size()

## World point -> screen point on the minimap. Inverse of minimap_to_world.
func world_to_minimap(world_pos: Vector2) -> Vector2:
	var r := minimap_rect()
	return r.position + world_pos / world_size() * r.size

## Left click / drag: centre the camera on the world point under the cursor.
func jump_to_screen(screen_pos: Vector2) -> void:
	if rts_cam == null:
		return
	rts_cam.center_on(minimap_to_world(screen_pos))
	queue_redraw()

## Right click: MOVE the current selection to the world point under the cursor.
## Same command dict SelectionInput._issue_context_order builds for a ground click.
func order_move_at(screen_pos: Vector2) -> void:
	var ids: Array = sim.selected_ids
	if ids.is_empty():
		return
	orders_issued.emit([{"type": "MOVE", "entityIds": ids, "targetPosition": minimap_to_world(screen_pos)}])

## _input (not _unhandled_input): runs before the GUI pass and before SelectionInput /
## RTSCamera see the event, regardless of tree order. Anything that lands on the minimap
## is consumed here so no drag-select box starts under it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and contains_screen(event.position):
				_drag_jump = true
				jump_to_screen(event.position)
				get_viewport().set_input_as_handled()
			elif not event.pressed and _drag_jump:
				# Eat the release too: SelectionInput._finish_drag runs on ANY left release.
				_drag_jump = false
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and contains_screen(event.position):
			order_move_at(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_jump:
		jump_to_screen(event.position)   # keeps following even if the cursor leaves the rect
		get_viewport().set_input_as_handled()
```
Design notes (do not change): the mapping is unclamped on purpose — a drag that leaves the rect keeps panning and `RTSCamera.center_on` clamps; the right-click is always inside the rect so it always lands on the map. Right-click on the minimap is MOVE only (no attack targeting), C&C convention. Wheel events are not consumed, so zooming over the minimap still zooms the world as today.

### 1c. `_draw()` uses the helpers (same pixels, one formula)
- Replace lines 57-59 (`var vp`, `var origin`, `var rect`) with a single `var rect := minimap_rect()`.
- Delete line 65 (`var cell := fog_sys.cell_size()`) — `gw`/`gh` (63-64) stay, `_build_terrain_texture` needs them.
- Replace lines 84-88 (the `px`/`py` maths and `draw_circle`) with:
```gdscript
		var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
		var r: float = 2.5 if e.kind == "unit" else 4.0
		draw_circle(world_to_minimap(e.position), r, col)
```
- Replace lines 92-97 (the camera box) with:
```gdscript
		var cam_rect := _camera_world_rect()
		var tl := world_to_minimap(cam_rect.position)
		var br := world_to_minimap(cam_rect.end)
		draw_rect(Rect2(tl, br - tl), COL_CAM_BOX, false, 1.5)
```
`_camera_world_rect` (99-104) is unchanged. Everything else in the file (terrain texture, fog texture, border) is unchanged.

## Change 2 — `presentation/Game.gd`
1. After `minimap_layer.add_child(minimap)` (line 85) add:
```gdscript
	minimap.orders_issued.connect(_on_orders)   # p4-02: right-click on the minimap = MOVE
```
2. In the debug locals, after the existing debug locals — directly after p4-01's `var debug_cam := ""` — add:
```gdscript
	var debug_minimap_click := Vector2(-1, -1)
```
3. In the arg loop, directly after p4-01's `elif a.begins_with("--cam="):` branch and before `elif a == "--attack":`, add:
```gdscript
		elif a.begins_with("--minimap-click="):
			var parts := a.trim_prefix("--minimap-click=").split(",")
			if parts.size() == 2:
				debug_minimap_click = Vector2(float(parts[0]), float(parts[1]))
```
4. At the very end of `_ready`, after p4-01's `if debug_cam != "":` block, which is now the last statement of `_ready`; at the same indentation as that `if`, add:
```gdscript
	if debug_minimap_click.x >= 0.0:
		# p4-02: same path a real left click takes (hit-test, jump, clamp). After --motion so
		# it wins over that flag's camera placement. Logged so the capture can be checked.
		var hit := minimap.contains_screen(debug_minimap_click)
		if hit:
			minimap.jump_to_screen(debug_minimap_click)
		print("MINIMAP_CLICK: screen=", debug_minimap_click, " hit=", hit,
			" world=", minimap.minimap_to_world(debug_minimap_click), " cam=", rts_cam.position)
```
Update the debug-flag comment block (lines 110-114) with one line: `# --minimap-click=<x>,<y> (screen px) performs a minimap left-click before the capture.`

## Test — new file `tests/test_minimap.gd`
Copy the harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_check`, `_fail`, `RESULT` line, `quit()`), with one deliberate difference: `get_viewport_rect()` needs the node inside the tree, and in a `--script` SceneTree the root is not in the tree during `_init` or `_initialize` (returns `Rect2()` with a "!is_inside_tree()" error — verified). So the body runs from `MainLoop._process` on the first frame. Also the headless root window comes up 1280x1280, not 720 — the test pins it to 1280x720 so the numbers match the real window. Use this file verbatim:

```gdscript
extends SceneTree
## test_minimap.gd — p4-02: MiniMapRenderer screen<->world mapping, hit-test, jump, MOVE order.
## Headless: `godot-4 --headless --path . --script tests/test_minimap.gd`
## The minimap and camera are added to the root so get_viewport_rect() works.

var failures: int = 0
var _ran: bool = false

## MainLoop._process runs once the root is in the tree (SceneTree._init / _initialize are too
## early: get_viewport_rect() returns Rect2() there). First frame only, then quit().
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	var mm := MiniMapRenderer.new(sim, sim.fog_sys, "VC", null)
	get_root().add_child(mm)

	# The headless root window is not the game's 1280x720 (it comes up square); pin it so the
	# numbers below are the same ones the real window produces.
	get_root().size = Vector2i(1280, 720)
	var vp := mm.get_viewport_rect().size
	_check(vp == Vector2(1280, 720), "premise: viewport is 1280x720 (%s)" % vp)
	var r := mm.minimap_rect()
	_check(r.size == Vector2(MiniMapRenderer.MAP_SIZE, MiniMapRenderer.MAP_SIZE), "minimap rect is MAP_SIZE square")
	_check(r.end.is_equal_approx(vp - Vector2(MiniMapRenderer.MARGIN, MiniMapRenderer.MARGIN)), "minimap sits MARGIN in from bottom-right")
	_check(r.position.is_equal_approx(Vector2(1044, 484)), "minimap origin is (1044, 484) at 1280x720 (%s)" % r.position)
	_check(mm.world_size() == Vector2(2000, 2000), "world size is 50x50 cells x 40 = 2000x2000 (%s)" % mm.world_size())

	# --- round trip at the four corners and the centre ---
	var pts := [Vector2(0, 0), Vector2(2000, 0), Vector2(0, 2000), Vector2(2000, 2000), Vector2(1000, 1000)]
	for w in pts:
		var m: Vector2 = mm.world_to_minimap(w)
		_check(mm.minimap_to_world(m).is_equal_approx(w), "round trip world %s -> minimap %s -> world" % [w, m])
	_check(mm.world_to_minimap(Vector2.ZERO).is_equal_approx(r.position), "world origin maps to the minimap top-left")
	_check(mm.world_to_minimap(Vector2(2000, 2000)).is_equal_approx(r.end), "world far corner maps to the minimap bottom-right")
	_check(mm.minimap_to_world(r.get_center()).is_equal_approx(Vector2(1000, 1000)), "minimap centre maps to world centre")
	_check(mm.minimap_to_world(r.position + Vector2(110, 90)).is_equal_approx(Vector2(1000, 818.1818)),
		"local (110, 90) -> world (1000, 818.18) — the screenshot click")

	# --- hit-test ---
	_check(mm.contains_screen(r.get_center()), "centre of the minimap is inside")
	_check(mm.contains_screen(r.position), "top-left corner is inside (inclusive)")
	_check(not mm.contains_screen(r.position - Vector2(1, 1)), "one px up-left of the minimap is outside")
	_check(not mm.contains_screen(r.end), "bottom-right corner is outside (exclusive)")
	_check(not mm.contains_screen(Vector2(640, 360)), "screen centre is the world, not the minimap")
	_check(not mm.contains_screen(Vector2(1100, 400)), "above the minimap is outside")

	# --- right-click: MOVE for the current selection, same dict as SelectionInput ---
	var uid := sim.spawn_unit("VC-U04", "VC", Vector2(900, 900))
	var got: Array = []
	mm.orders_issued.connect(func(o: Array) -> void: got.assign(o))   # lambdas capture by value; mutate in place
	sim.selected_ids = []
	mm.order_move_at(r.get_center())
	_check(got.is_empty(), "no selection -> no order emitted")
	sim.selected_ids = [uid]
	mm.order_move_at(r.get_center())
	_check(got.size() == 1 and got[0].get("type") == "MOVE", "right-click emits one MOVE")
	_check(got.size() == 1 and got[0].get("entityIds") == [uid], "MOVE carries the selected ids")
	_check(got.size() == 1 and got[0].get("targetPosition").is_equal_approx(Vector2(1000, 1000)), "MOVE targets the world point under the cursor")
	sim.run_commands(0, got)
	_check(sim.entities[uid].order == Entity.Order.MOVE and sim.entities[uid].order_dest.is_equal_approx(Vector2(1000, 1000)),
		"sim accepted the minimap MOVE (order_dest %s)" % sim.entities[uid].order_dest)

	# --- left-click: camera jump, clamped like every other camera move ---
	var cam := RTSCamera.new()
	cam.set_world_size(2000, 2000)
	get_root().add_child(cam)
	mm.rts_cam = cam
	mm.jump_to_screen(r.position + Vector2(110, 90))
	_check(cam.position.is_equal_approx(Vector2(1000, 818.1818)), "jump centres the camera on the clicked world point (%s)" % cam.position)
	mm.jump_to_screen(r.position)
	_check(cam.position.is_equal_approx(vp * 0.5), "jump to the map corner clamps to half the view (%s)" % cam.position)
	mm.jump_to_screen(r.end)
	_check(cam.position.is_equal_approx(Vector2(2000, 2000) - vp * 0.5), "jump to the far corner clamps at world - half view (%s)" % cam.position)

	mm.free()
	cam.free()
	if failures == 0:
		print("MINIMAP_RESULT: ALL PASS")
	else:
		print("MINIMAP_RESULT: %d FAILURE(S)" % failures)
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
```
This exact file printed `MINIMAP_RESULT: ALL PASS` (28 PASS lines) against the code above in a throwaway copy. No new `class_name` is introduced, so no `--import` step is needed. The trailing `ERROR: N resources still in use at exit` line is pre-existing — every suite in the repo prints it — and is not a gate.

The 28-PASS run was against HEAD's RTSCamera; re-run after p4-01 (the camera in the test now runs p4-01's `_ready`/`_process`; `viewport_size()` reads `get_viewport_rect()` because the node is in the tree). Expected count is unchanged.

## Screenshot
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_minimap_jump.png --frame=90 --minimap-click=1154,574
```
Screen (1154, 574) is minimap-local (110, 90) → world **(1000, 818.18)**, which is inside the clamp range so the camera lands exactly there and the Garage base (VC-B01 at world 960,960) sits mid-screen. The run must print
`MINIMAP_CLICK: screen=(1154.0, 574.0) hit=true world=(1000.0, 818.1818) cam=(1000.0, 818.1818)` and then `CAPTURED:…/docs/screenshot_minimap_jump.png size=(1280, 720) err=0`.

**Pixel check (executor, no image viewing needed).** At zoom 1 the camera box covers world x 360..1640, y 458.2..1178.2, i.e. minimap screen columns **1083.6 and 1224.4** and rows **534.4 and 613.6**. Run:
```
~/AI_Agent/venv/bin/python - <<'EOF'
from PIL import Image
im = Image.open("docs/screenshot_minimap_jump.png").convert("RGB")
lum = lambda x, y: sum(im.getpixel((x, y))) // 3
cols = [x for x in range(1046, 1262) if sum(1 for y in range(486, 702) if lum(x, y) > 170) > 40]
rows = [y for y in range(486, 702) if sum(1 for x in range(1046, 1262) if lum(x, y) > 170) > 60]
print("box columns", cols, "box rows", rows)
EOF
```
Expected `box columns [1083, 1224] box rows [534, 613]` (±1 px each; a value may appear twice where the 1.5 px line straddles two pixels). Without the flag the box is at columns ~1108/1109 and 1249, rows ~579 and 658/659 (camera at 1230,1230) — if you see those, the jump did not happen. Verified in a throwaway copy on 2026-09-22.

**F eyeballs:** the pale camera box on the minimap is centred on the click point, up-left of the cyan unit dots, not on them; the Garage Core and the Maker Space are both on screen; nothing else in the frame changed.

## Keys
- **LMB click on the minimap** — centre the camera on that map point (instant snap, clamped).
- **LMB drag on the minimap** — keeps centring the camera under the cursor until release (continues if the cursor leaves the rect).
- **RMB click on the minimap** — MOVE the current selection to that map point (no-op with an empty selection).
- No keyboard keys. Wheel over the minimap is left to `RTSCamera` (zooms the world, as today).
- Shift+RMB queueing: p4-03 extends `order_move_at(screen_pos, queue)`; this ticket emits the plain MOVE.

## Done when
- `godot-4 --headless --path . --script tests/test_minimap.gd` prints `MINIMAP_RESULT: ALL PASS`.
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS`, no `SCRIPT ERROR` — 12 suites including the new one.
- `git status --short` shows exactly ` M presentation/Game.gd`, ` M presentation/MiniMapRenderer.gd`, `?? tests/test_minimap.gd`, `?? docs/screenshot_minimap_jump.png` from your work (four files). Nothing under `core/`, `gameplay/`, `presentation3d/`, and `presentation/RTSCamera.gd` untouched (p4-01 owns it). `*.import` and `*.uid` are gitignored — do not add them. The tree may carry unrelated untracked files (e.g. `tools/deepseek_*.py`); leave them alone — `git add` only the four files above, never `-A`.
- `grep -n "func _input" presentation/MiniMapRenderer.gd` returns one line; `grep -n "func center_on" presentation/RTSCamera.gd` returns one line (p4-01's method); `grep -n "orders_issued.connect" presentation/Game.gd` returns two lines (SelectionInput's and the minimap's).
- The `MINIMAP_CLICK:` log line and the pixel check above match.
- Commit, then `git push origin master`:
  `feat(input): minimap click-to-jump and right-click MOVE; minimap consumes its clicks`
  Body (3–6 lines): MiniMapRenderer gains minimap_rect/contains_screen/minimap_to_world/world_to_minimap (also used by _draw); _input handles LMB press/drag/release (camera jump via RTSCamera.center_on (p4-01)) and RMB (MOVE through Game._on_orders) and marks them handled so SelectionInput's drag-select never starts under the minimap; --minimap-click debug flag; headless test of the mapping, hit-test, jump clamp and order shape.
- Report: `git log --oneline -1`, the `MINIMAP_RESULT` line, the `MINIMAP_CLICK` line, the pixel-check output, and the path of the screenshot.
