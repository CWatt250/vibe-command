# p4-01 — Camera feel: arrow/edge/middle-drag pan, cursor-anchored smoothed zoom, H = home

**Tier:** P (DeepSeek Pro) · **Repo:** `~/Dev/vibe-command` (HEAD `bd73d1c`) · **Adds:** `tests/test_camera.gd`, `docs/screenshot_cam_zoom.png` · **Touches:** `presentation/RTSCamera.gd` (replaced in full), `presentation/Game.gd`, `project.godot`. **`core/`, `gameplay/` and `presentation3d/` are not touched — this is presentation only, no sim state is involved.**

Why P and not C: one system (the camera) but it spans two scripts plus a `project.godot` edit, a
new headless test and a capture — more than a single-file fix. Why not O: there is nothing left to
design; the whole new `RTSCamera.gd`, every `Game.gd` edit and the complete test are given below
and were verified green (11/11 suites) in a throwaway copy of the repo before this ticket was
written. Your job is to apply them exactly, run the gates, capture, commit, push.

Read `docs/specs/README.md` first. **Order:** first Phase 4 ticket — the landing order is p4-01,
p4-02, p4-04, p4-03, p4-05. p4-02 (minimap click) and p4-04/p4-03 (A/S/G, control groups) build
on the `RTSCamera` API this ticket introduces (`go_home`, `center_on`, `set_zoom_now`,
`viewport_size`), so land this one first.

## Keys
This ticket binds, and nothing else in the repo may bind these afterwards:

| Input | Action |
|---|---|
| **Arrow keys** (Left/Right/Up/Down, physical) | pan the camera (held; diagonal is normalised) |
| **Screen edge** (cursor within `edge_margin` = 24 px of the window edge) | pan; off while a middle-drag is active, off while an arrow key is held, off when the window is unfocused or the cursor is outside it |
| **Middle mouse button drag** | pan (world follows the cursor 1:1 at any zoom) |
| **Mouse wheel up / down** | zoom in / out one notch (×1.15 / ÷1.15), eased, anchored on the cursor |
| **H** | jump the camera to the player's HQ (Garage Core), zoom unchanged |

Per the Phase 4 key map, **WASD is NOT bound** (A/S/G go to later tickets). Escape is untouched
(PlacementGhost / PauseMenu own it). Ctrl+digit / digit / Shift / double-click are p4-03's.

## Why
Today the camera has edge scroll and a snapping wheel zoom, nothing else. Playing feels like
dragging a window around a map: no keyboard pan, no drag pan, zoom that jumps and drifts the
map under the cursor, no way home. This ticket is the "it feels like an RTS" step.

## Current facts you will rely on (all read at HEAD `bd73d1c`)

`presentation/RTSCamera.gd` (82 lines — you replace the whole file, but know what is there):
- `:6-10` exports `min_zoom 0.5`, `max_zoom 3.0`, `pan_speed 600.0` (world px/s at zoom 1),
  `edge_margin 24`, `zoom_step 0.1`.
- `:12` `var dragging_pan: bool = false` — declared, read at `:23`, **never set anywhere**
  (`grep -rn dragging_pan presentation ui` → only those two lines). Middle-drag does not exist.
- `:21-34` `_process`: edge scroll only. `:32` is the pan formula
  `position += dir.normalized() * pan_speed * delta / zoom.x` — already scaled by 1/zoom; keep
  that formula. `:23` gates on `_mouse_in_window()` (`:79-82`) but **not** on window focus, so an
  unfocused window keeps scrolling from the last known cursor position.
- `:36-41` `_unhandled_input`: wheel up/down call `_zoom_at(mouse, 1.0 ± zoom_step)`.
- `:43-45` `_zoom_at` ignores `screen_pos` entirely — it just sets `zoom`. **No anchoring, no
  smoothing.** (p1-05, `docs/specs/p1-05-camera-clamp.md:30`, deferred exactly this to Phase 4.)
- `:47-59` `_clamp_to_world` — correct since p1-05 (`viewport / (2 * zoom)` half-extents, centres
  the axis when the world is smaller than the view). Keep the logic verbatim.
- `:61-64` `viewport_width()` / `viewport_height()` wrap `get_viewport_rect().size`. No caller
  outside this file (`grep -rn "viewport_width\|viewport_height" presentation ui` → only
  RTSCamera.gd). They go away in favour of one `viewport_size()`.
- `:73-77` `screen_to_world` / `world_to_screen`: `(s - vp/2) / zoom + position` and its inverse —
  the camera is screen-centred (Camera2D default anchor mode). Read by `EntityRenderer.gd:334-338`,
  `MiniMapRenderer.gd:100-104`, `MapRenderer.gd:117-122` (via `get_viewport().get_camera_2d()`),
  `SelectionInput.gd:24-25,40,47,50,54` and `PlacementGhost.gd:65`. Their signatures do not change.
- **Outside a tree `get_viewport_rect()` errors** (`Condition "!is_inside_tree()" is true.
  Returning: Rect2()` from `scene/main/canvas_item.cpp:1231`) and `get_viewport()` /
  `get_window()` return null — verified headless with `RTSCamera.new()`. That is why the new file
  routes every projection through `viewport_size()` with a test-only override.
- `Window.has_focus()` exists in Godot 4.7.2 (`ClassDB.class_has_method("Window","has_focus")`
  → true, verified) and `Input.is_physical_key_pressed` exists (verified).

`presentation/Game.gd`:
- `:24` `const PLAYER_FACTION := "VC"`; `:27` `_world = Vector2(2000, 2000)`.
- `:49-52` creates the camera: `RTSCamera.new()`, `set_world_size`, `position = Vector2(1230, 1230)`,
  `add_child`. Leave the start position alone (it frames both bases).
- `:105-106` the `_spawn_starter_force()` call. `:202` spawns the HQ:
  `sim.spawn_structure("VC-B01", "VC", Vector2(24, 24) * NavGrid.CELL)` = world (960, 960)
  (the verification capture at `--cam=960,960,2.5` centres the Garage Core).
- `:115-143` the debug-arg loop (`--capture=`, `--frame=`, `--capture-frames=`, `--select=`,
  `--train=`, `--place=`, `--pause`, `--motion`, `--attack`). `:138-139` is the `--motion` branch;
  `:140` starts `--attack`. `:144-145` default the capture frame to 180.
- `:158-169` the `--motion` block ends with `:168 rts_cam.zoom = Vector2(2.0, 2.0)` and
  `:169 rts_cam.position = Vector2(900, 475)` — the only place outside RTSCamera that writes
  `zoom` (`grep -rn "\.zoom\s*=" presentation ui`). With smoothed zoom this line must also set the
  target, or the camera eases back to zoom 1 and the p3-03 motion captures change.
- `:238-248` `Game._process` steps the sim on a fixed 15 Hz accumulator. The camera's own
  `_process` (`RTSCamera.gd:21`) already runs once per rendered frame independent of the sim tick,
  so pan/zoom update per frame with no change to `Game._process`.
- There is no `_unhandled_input` in Game.gd; you do not add one.

Input owners today (`grep -rn "_unhandled_input\|_input(" presentation ui`):
- `presentation/SelectionInput.gd:30-47` `_unhandled_input`: Shift tracking, **LEFT** press/release
  (drag-select), **RIGHT** press (context order). Middle button is never referenced.
- `ui/PlacementGhost.gd:48-62` `_input` (only while `active()`): mouse motion tracks the ghost,
  **LEFT** builds, **RIGHT** cancels, **Escape** cancels — each `set_input_as_handled()`.
- `ui/PauseMenu.gd:40-43` `_unhandled_input`: **Escape** toggles and marks handled.
- `presentation/EntityRenderer.gd:247` polls `Input.is_key_pressed(KEY_ALT)` (health bars).
- `ui/HUD.gd:83` tooltip already says `"Halt the selected units (S)"` — S is reserved for a later
  ticket, do not bind it here.
- `project.godot:18-24` defines InputMap actions `move_up/down/left/right` on **W/S/A/D** and
  `zoom_in`/`zoom_out` on keycodes 4194308/4194309 (Backspace/Enter). **No script reads any of
  them** (`grep -rn "move_up\|move_down\|move_left\|move_right\|zoom_in\|zoom_out" --include=*.gd .`
  → nothing). They bind WASD, which this phase leaves unbound, so this ticket deletes them.

HQ identity: `content/data/structures.json:457-475` — `VC-B01` "Garage Core" has `"class": "HQ"`
(`:469`) and `componentFlags` containing `"HQ"` (`:472`). The sim's own HQ test is
`e.def_data.get("class", "") == "HQ"` (`core/simulation/Simulation.gd:213`, inside
`_check_match_over` `:206-228`); `Game._player_home()` below uses the same test.

## Design decisions (made; do not revisit)
- **Wheel is multiplicative** (×`zoom_notch` / ÷`zoom_notch`, 1.15) instead of the old `1 ± 0.1`:
  N notches in then N out lands exactly on the start zoom.
- **Zoom eases toward a target** (`zoom_target`) with a frame-rate-independent exponential step
  `lerp(zoom, target, 1 - exp(-k·dt))`, k = `zoom_smoothing` = 12/s: the weight is always in
  (0, 1) so the zoom moves toward the target every frame and cannot overshoot; it snaps when
  within `ZOOM_SNAP`.
- **Anchoring is re-applied every frame of the ease against the live cursor** (`anchored_zoom`
  shifts `position` by the change in `screen_to_world(anchor)`), not a world point stored at wheel
  time: a pan issued mid-ease does not fight the zoom, and the point under the cursor stays put.
- **H is handled inside RTSCamera** via a `home` vector that `Game.gd` sets once after spawning,
  rather than Game.gd reading the sim on each press: the HQ is pre-placed and losing it ends the
  match (`Simulation.gd:204-228`), so the value never goes stale during a match.
- **Arrow keys are polled** (`Input.is_physical_key_pressed`) in `_process`, matching how
  `EntityRenderer.gd:247` polls Alt, instead of InputMap actions: held keys need per-frame
  polling anyway and the six existing actions are dead.
- **Middle-drag lives in `_input`**, wheel and H in `_unhandled_input`: Controls consume mouse
  events before `_unhandled_input`, so a drag that crosses the HUD or minimap would stall; wheel
  over the HUD *should* stop (RTS convention), and Escape stays with its current owners.

## Change 1 — `presentation/RTSCamera.gd`: replace the file with exactly this

```gdscript
extends Camera2D
class_name RTSCamera
## RTS camera — pan (arrow keys, screen-edge scroll, middle-mouse drag), cursor-anchored
## smoothed zoom (wheel), H = home. Every piece of camera math is a plain method
## (pan_step / edge_dir / anchored_zoom / settle_zoom / _clamp_to_world) that reads the
## viewport size through viewport_size(), so the headless test can drive it without a window
## by setting viewport_size_override.

@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var pan_speed: float = 600.0        # screen px/sec: divided by zoom so it feels constant
@export var edge_margin: int = 24           # screen px edge-scroll zone
@export var zoom_notch: float = 1.15        # one wheel notch multiplies the target zoom by this (or 1/this)
@export var zoom_smoothing: float = 12.0    # 1/s — exponential approach rate toward zoom_target
const ZOOM_SNAP := 0.001                    # closer than this to the target: snap and stop settling

var dragging_pan: bool = false
var home: Vector2 = Vector2.ZERO            # Game.gd sets this to the player's HQ; H jumps here
var zoom_target: float = 1.0
var viewport_size_override: Vector2 = Vector2.ZERO   # tests only: non-zero replaces the real viewport size

## World bounds (set by the map). Used for clamping.
var _world_width: float = 2000.0
var _world_height: float = 2000.0

func _ready() -> void:
	if not is_current():
		make_current()
	zoom_target = zoom.x

func _process(delta: float) -> void:
	var dir := arrow_dir()
	# Edge scrolling: only when no arrow key is held, no middle-drag is active, the window has
	# focus (an unfocused window still reports the last mouse position, which would scroll
	# forever after alt-tab), and the cursor is inside the window.
	if dir == Vector2.ZERO and not dragging_pan and _window_focused() and _mouse_in_window():
		dir = edge_dir(get_viewport().get_mouse_position())
	if dir != Vector2.ZERO:
		pan_step(dir, delta)
	settle_zoom(delta, _zoom_anchor())
	_clamp_to_world()

## Middle-mouse drag lives in _input (not _unhandled_input) so a drag that crosses a HUD
## panel — Controls consume mouse events before they reach _unhandled_input — does not stall.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging_pan = event.pressed
	elif event is InputEventMouseMotion and dragging_pan:
		# Drag the world with the cursor: screen delta -> world delta is / zoom.
		position -= event.relative / zoom.x
		_clamp_to_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_toward(zoom_notch)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_toward(1.0 / zoom_notch)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		go_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging_pan = false   # a release that happens in another window never reaches us

# --- pure camera math (no input, no viewport lookup beyond viewport_size()) ---

## Move by dir (unnormalised is fine) at pan_speed screen px/s: world delta = speed * dt / zoom.
func pan_step(dir: Vector2, dt: float) -> void:
	if dir == Vector2.ZERO:
		return
	position += dir.normalized() * pan_speed * dt / zoom.x

## Edge-scroll direction for a cursor at screen position mpos: -1/0/+1 per axis.
func edge_dir(mpos: Vector2) -> Vector2:
	var vp := viewport_size()
	var dir := Vector2.ZERO
	if mpos.x <= edge_margin: dir.x -= 1
	elif mpos.x >= vp.x - edge_margin: dir.x += 1
	if mpos.y <= edge_margin: dir.y -= 1
	elif mpos.y >= vp.y - edge_margin: dir.y += 1
	return dir

## Arrow keys held right now (physical keys, so it works on any layout).
func arrow_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_physical_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1
	return dir

## One wheel notch: scale the TARGET zoom; settle_zoom eases the real zoom toward it per frame.
func zoom_toward(factor: float) -> void:
	zoom_target = clampf(zoom_target * factor, min_zoom, max_zoom)

## Set zoom and its target at once (debug flags, tests) — no easing, no anchoring.
func set_zoom_now(z: float) -> void:
	z = clampf(z, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	zoom_target = z

## Jump zoom to new_zoom keeping the world point under anchor_screen fixed on screen.
## Derived from screen_to_world: w = (s - vp/2) / zoom + position, so for w to stay put
## position must shift by the change in (s - vp/2) / zoom.
func anchored_zoom(anchor_screen: Vector2, new_zoom: float) -> void:
	var before := screen_to_world(anchor_screen)
	zoom = Vector2(new_zoom, new_zoom)
	position += before - screen_to_world(anchor_screen)

## Per-frame exponential approach of zoom toward zoom_target, anchored at anchor_screen.
## lerp weight 1 - exp(-k dt) is frame-rate independent and always in (0, 1), so the zoom
## moves toward the target every frame and can never overshoot it. Snaps when within ZOOM_SNAP.
func settle_zoom(dt: float, anchor_screen: Vector2) -> void:
	if is_equal_approx(zoom.x, zoom_target):   # Vector2 is float32; never compare with ==
		return
	var z: float
	if absf(zoom_target - zoom.x) < ZOOM_SNAP:
		z = zoom_target
	else:
		z = lerpf(zoom.x, zoom_target, 1.0 - exp(-zoom_smoothing * dt))
	anchored_zoom(anchor_screen, z)

## Snap the view centre to a world point (minimap click p4-02, control-group double-tap
## p4-03, H). Clamped now, not next _process, so the minimap's camera box is right on the
## same frame. Touches position only — zoom and zoom_target are left alone.
func center_on(world_pos: Vector2) -> void:
	position = world_pos
	_clamp_to_world()

## H: centre on home (the player's HQ), keeping the current zoom.
func go_home() -> void:
	center_on(home)

func _clamp_to_world() -> void:
	# Godot 4: a LARGER zoom is closer, so the visible half-extent is viewport / (2 * zoom).
	var vp := viewport_size()
	var half_w := vp.x * 0.5 / zoom.x
	var half_h := vp.y * 0.5 / zoom.y
	# If the world is smaller than the view (zoomed far out), centre it instead of jittering.
	if _world_width <= half_w * 2.0:
		position.x = _world_width * 0.5
	else:
		position.x = clampf(position.x, half_w, _world_width - half_w)
	if _world_height <= half_h * 2.0:
		position.y = _world_height * 0.5
	else:
		position.y = clampf(position.y, half_h, _world_height - half_h)

func set_world_size(w: float, h: float) -> void:
	_world_width = w
	_world_height = h

## The viewport size every projection uses. Tests set viewport_size_override because
## get_viewport_rect() errors on a node that is not inside a tree.
func viewport_size() -> Vector2:
	if viewport_size_override != Vector2.ZERO:
		return viewport_size_override
	return get_viewport_rect().size

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - viewport_size() * 0.5) / zoom + position

func world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - position) * zoom + viewport_size() * 0.5

# --- window / cursor state (never called by the test) ---

func _mouse_in_window() -> bool:
	var mpos := get_viewport().get_mouse_position()
	var vp := viewport_size()
	return mpos.x >= 0 and mpos.x <= vp.x and mpos.y >= 0 and mpos.y <= vp.y

func _window_focused() -> bool:
	var w := get_window()
	return w == null or w.has_focus()

## Zoom anchors on the cursor when it is in the window, else on the screen centre.
func _zoom_anchor() -> Vector2:
	if _mouse_in_window():
		return get_viewport().get_mouse_position()
	return viewport_size() * 0.5
```

Notes on what changed versus HEAD: `zoom_step` → `zoom_notch` (multiplicative); `_zoom_at` →
`zoom_toward` + `anchored_zoom` + `settle_zoom`; `viewport_width/height` → `viewport_size`;
`dragging_pan` is now actually set (middle button); `_clamp_to_world`, `set_world_size`,
`screen_to_world`, `world_to_screen`, `_mouse_in_window` keep their names and semantics.
`center_on(world_pos)` is new and is the one entry point later tickets use to move the camera from
input (p4-02 minimap, p4-03 double-tap). The `class_name RTSCamera` already exists, so **no
`--import` step is needed**.

## Change 2 — `presentation/Game.gd` (five surgical edits; locate by the quoted code)

**2a.** After `:106` `_spawn_starter_force()` add one line:
```gdscript
	_spawn_starter_force()
	rts_cam.home = _player_home()   # H key; the HQ is pre-placed and losing it ends the match
```

**2b.** After `:120` `var debug_motion := false` add:
```gdscript
	var debug_cam := ""
```

**2c.** In the arg loop, directly after the `--motion` branch (`:138-139`) and before
`elif a == "--attack":` (`:140`), add:
```gdscript
		elif a.begins_with("--cam="):
			debug_cam = a.trim_prefix("--cam=")   # x,y,zoom — applied after every other debug flag
```

**2d.** Replace `:168` `rts_cam.zoom = Vector2(2.0, 2.0)` (inside the `if debug_motion:` block)
with `rts_cam.set_zoom_now(2.0)   # zoom AND its target, or settle_zoom eases back to 1`, and
append the `--cam` application as the **last** statement of `_ready()` (after
`:169 rts_cam.position = Vector2(900, 475)`, dedented to the function body):
```gdscript
		rts_cam.set_zoom_now(2.0)   # zoom AND its target, or settle_zoom eases back to 1
		rts_cam.position = Vector2(900, 475)
	if debug_cam != "":
		var p := debug_cam.split(",")
		if p.size() == 3:
			rts_cam.position = Vector2(float(p[0]), float(p[1]))
			rts_cam.set_zoom_now(float(p[2]))
```
(`_clamp_to_world` runs on the camera's first `_process`, so an off-world `--cam` is clamped
before the capture frame.)

**2e.** Add this function between the end of `_spawn_starter_force()` (`:236`
`sim.attach_skirmish_ai("FC", "VC")`) and `func _process` (`:238`):
```gdscript
## Where H sends the camera: the player's HQ-class structure (same test as
## Simulation._check_match_over), else the player's first structure, else the map centre.
func _player_home() -> Vector2:
	var first := Vector2(-1, -1)
	for e in sim.entities.values():
		if e.faction_id != PLAYER_FACTION or e.kind != "structure" or not e.alive:
			continue
		if e.def_data.get("class", "") == "HQ":
			return e.position
		if first.x < 0.0:
			first = e.position
	return first if first.x >= 0.0 else _world * 0.5
```
Nothing else in Game.gd changes. `Game._process` (`:238-248`) is untouched.

## Change 3 — `project.godot`: delete the dead InputMap block
Delete lines 18-25 — the `[input]` header, the six `move_*` / `zoom_*` actions, and the blank
line after them — so `window/stretch/aspect="expand"` is followed by one blank line and then
`[rendering]`. Nothing reads these actions (grep evidence above) and they bind WASD, which
Phase 4 leaves unbound. Do not add any InputMap actions.

## Test — new file `tests/test_camera.gd`
Harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_init`, `_check`, `_fail`,
`RESULT` line, `quit()`). The camera never enters a tree; `viewport_size_override` stands in for
the window. Save exactly this:

```gdscript
extends SceneTree
## test_camera.gd — p4-01: RTSCamera pan / cursor-anchored zoom / smoothing / clamp, headless.
## The camera never enters a tree; viewport_size_override stands in for the window.
## Headless: `godot-4 --headless --path . --script tests/test_camera.gd`

var failures: int = 0
const VP := Vector2(1280, 720)
const DT := 1.0 / 60.0

func _init() -> void:
	var cam := RTSCamera.new()
	cam.viewport_size_override = VP
	cam.set_world_size(2000.0, 2000.0)
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	_check(cam.viewport_size() == VP, "viewport_size() uses the override outside a tree")

	# --- pan: world delta = pan_speed * dt / zoom, direction normalised ---
	cam.pan_step(Vector2.RIGHT, 0.5)
	_check(cam.position.is_equal_approx(Vector2(1000 + cam.pan_speed * 0.5, 1000)),
		"pan right at zoom 1 moves pan_speed*dt (%s)" % cam.position)
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(2.0)
	cam.pan_step(Vector2.RIGHT, 0.5)
	_check(cam.position.is_equal_approx(Vector2(1000 + cam.pan_speed * 0.5 / 2.0, 1000)),
		"pan at zoom 2 covers half the world distance (constant on screen)")
	cam.position = Vector2(1000, 1000)
	cam.pan_step(Vector2(1, 1), 1.0)
	var diag: float = cam.pan_speed / 2.0 * sqrt(0.5)   # zoom is 2 here
	_check(cam.position.is_equal_approx(Vector2(1000 + diag, 1000 + diag)), "diagonal pan is normalised")
	cam.pan_step(Vector2.ZERO, 1.0)
	_check(cam.position.is_equal_approx(Vector2(1000 + diag, 1000 + diag)), "zero dir is a no-op")

	# --- edge scroll direction from a cursor position ---
	_check(cam.edge_dir(Vector2(0, 0)) == Vector2(-1, -1), "cursor at top-left scrolls up-left")
	_check(cam.edge_dir(Vector2(VP.x, VP.y * 0.5)) == Vector2(1, 0), "cursor at right edge scrolls right")
	_check(cam.edge_dir(Vector2(VP.x * 0.5, VP.y - cam.edge_margin)) == Vector2(0, 1), "margin row scrolls down")
	_check(cam.edge_dir(VP * 0.5) == Vector2.ZERO, "cursor at centre does not scroll")

	# --- cursor-anchored zoom: the world point under the cursor stays put ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	var anchor := Vector2(200, 100)
	var w0 := cam.screen_to_world(anchor)
	_check(w0.is_equal_approx(Vector2(560, 740)), "premise: screen (200,100) is world (560,740) (%s)" % w0)
	for z in [2.0, 2.5, 0.7, 3.0, 1.0]:
		cam.anchored_zoom(anchor, z)
		var w1 := cam.screen_to_world(anchor)
		_check(is_equal_approx(cam.zoom.x, z) and w1.distance_to(w0) < 0.5,
			"anchored zoom to %.1f keeps the anchored world point fixed (drift %.3f px)" % [z, w1.distance_to(w0)])
	_check(cam.position.is_equal_approx(Vector2(1000, 1000)), "returning to zoom 1 returns to the start position")

	# --- wheel notches scale the target multiplicatively and round-trip ---
	cam.set_zoom_now(1.0)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.zoom_notch * cam.zoom_notch), "two notches in = notch^2 target")
	_check(is_equal_approx(cam.zoom.x, 1.0), "wheel changes the target, not the zoom, until settle_zoom runs")
	cam.zoom_toward(1.0 / cam.zoom_notch)
	cam.zoom_toward(1.0 / cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, 1.0), "two notches out undo two notches in exactly")
	for i in range(40):
		cam.zoom_toward(cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.max_zoom), "target clamps at max_zoom")
	for i in range(80):
		cam.zoom_toward(1.0 / cam.zoom_notch)
	_check(is_equal_approx(cam.zoom_target, cam.min_zoom), "target clamps at min_zoom")

	# --- smoothing: monotone, never overshoots, converges, stays anchored throughout ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	cam.zoom_toward(cam.zoom_notch)
	var target: float = cam.zoom_target
	var anchor_w := cam.screen_to_world(anchor)
	var monotone := true
	var overshoot := false
	var max_drift := 0.0
	var prev: float = cam.zoom.x
	var frames_to_settle := -1
	for f in range(240):
		cam.settle_zoom(DT, anchor)
		if cam.zoom.x < prev - 1e-6:
			monotone = false
		if cam.zoom.x > target + 1e-6:
			overshoot = true
		max_drift = maxf(max_drift, cam.screen_to_world(anchor).distance_to(anchor_w))
		prev = cam.zoom.x
		if frames_to_settle < 0 and is_equal_approx(cam.zoom.x, target):
			frames_to_settle = f + 1
	_check(monotone, "zoom in approaches the target monotonically")
	_check(not overshoot, "zoom never overshoots the target")
	_check(is_equal_approx(cam.zoom.x, target), "zoom settles onto the target (%.4f vs %.4f)" % [cam.zoom.x, target])
	_check(frames_to_settle > 1 and frames_to_settle < 120,
		"settles in more than one frame and under two seconds (%d frames)" % frames_to_settle)
	_check(max_drift < 0.5, "anchored world point drifts < 0.5 px over the whole ease (%.3f)" % max_drift)
	_check(cam.zoom.y == cam.zoom.x, "zoom stays uniform")
	# First frame moves a fixed fraction: 1 - exp(-k dt) of the remaining gap.
	cam.set_zoom_now(1.0)
	cam.zoom_toward(2.0)
	cam.settle_zoom(DT, anchor)
	var expect: float = lerpf(1.0, 2.0, 1.0 - exp(-cam.zoom_smoothing * DT))
	_check(is_equal_approx(cam.zoom.x, expect), "one frame = exponential step (%.4f vs %.4f)" % [cam.zoom.x, expect])
	# Zoom OUT converges the same way.
	cam.set_zoom_now(2.0)
	cam.zoom_toward(0.5)
	prev = cam.zoom.x
	monotone = true
	for f in range(240):
		cam.settle_zoom(DT, anchor)
		if cam.zoom.x > prev + 1e-6:
			monotone = false
		prev = cam.zoom.x
	_check(monotone and is_equal_approx(cam.zoom.x, 1.0), "zoom out converges monotonically to the target")

	# --- clamp still holds after pans and zooms ---
	cam.position = Vector2(1000, 1000)
	cam.set_zoom_now(1.0)
	cam.pan_step(Vector2.LEFT, 100.0)   # far past the left edge
	cam._clamp_to_world()
	_check(is_equal_approx(cam.position.x, VP.x * 0.5), "pan past the left edge clamps to half the view width")
	cam.position = Vector2(2000, 2000)
	cam.set_zoom_now(2.5)
	cam._clamp_to_world()
	_check(cam.position.is_equal_approx(Vector2(2000 - VP.x * 0.5 / 2.5, 2000 - VP.y * 0.5 / 2.5)),
		"bottom-right corner at zoom 2.5 clamps by viewport/(2*zoom) (%s)" % cam.position)
	cam.position = Vector2(100, 100)
	cam.anchored_zoom(Vector2.ZERO, 3.0)   # zoom in at the top-left corner, position runs off-world
	cam._clamp_to_world()
	var rect_tl := cam.screen_to_world(Vector2.ZERO)
	var rect_br := cam.screen_to_world(VP)
	_check(rect_tl.x >= -0.01 and rect_tl.y >= -0.01 and rect_br.x <= 2000.01 and rect_br.y <= 2000.01,
		"after an anchored zoom the view is still inside the world (%s .. %s)" % [rect_tl, rect_br])
	cam.set_zoom_now(0.5)   # view 2560x1440 on a 2000x2000 world: x centred, y still clamped
	cam._clamp_to_world()
	_check(cam.position.is_equal_approx(Vector2(1000, 720)),
		"zoomed past the world width the view is centred on x and clamped on y (%s)" % cam.position)

	# --- home ---
	cam.set_zoom_now(1.0)
	cam.home = Vector2(960, 960)
	cam.position = Vector2(1800, 1800)
	cam.go_home()
	_check(cam.position.is_equal_approx(Vector2(960, 960)), "go_home centres on home")
	cam.home = Vector2(0, 0)
	cam.go_home()
	_check(cam.position.is_equal_approx(VP * 0.5), "go_home clamps a home near the edge")

	cam.free()   # never entered a tree; free so quit() doesn't report a leaked node
	if failures == 0:
		print("CAMERA_RESULT: ALL PASS")
	else:
		print("CAMERA_RESULT: %d FAILURE(S)" % failures)
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
Expected: 35 `PASS:` lines and `CAMERA_RESULT: ALL PASS`. If any check fails, the bug is in your
transcription of Change 1 — the file above passes as written. Two traps already handled for you:
`Vector2` components are float32 so the code and test compare zoom with `is_equal_approx`, never
`==`; and at zoom 0.5 a 2000×2000 world is narrower than the 2560-wide view but taller than the
1440-high view, so x centres while y still clamps (the last clamp check asserts exactly that).

## Screenshot
Input cannot be driven headlessly, so the capture only shows the new `--cam` flag and that a
zoomed-in camera renders crisp with no black band:
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --cam=960,960,2.5 --capture=$PWD/docs/screenshot_cam_zoom.png --frame=90
```
Console must print `CAPTURED:... size=(1280, 720) err=0`. (The pre-existing
`Error opening file 'res://icon.svg'` line is not yours; ignore it.)

Executor pixel checks (you cannot view PNGs — measure them):
```
python3 - <<'EOF'
from PIL import Image, ImageStat
im = Image.open("docs/screenshot_cam_zoom.png").convert("RGB"); w, h = im.size
assert (w, h) == (1280, 720), im.size
sd = ImageStat.Stat(im).stddev; assert min(sd) > 15, sd            # not blank / not uniform
dark = lambda p: sum(p) < 15
cols = sum(all(dark(im.getpixel((x, y))) for y in range(0, h, 8)) for x in range(40))
rows = sum(all(dark(im.getpixel((x, y))) for x in range(0, w, 8)) for y in range(40))
assert cols == 0 and rows == 0, (cols, rows)                        # no black band left/top
print("cam capture OK", sd)
EOF
```
(The verification run measured stddev ≈ (34, 29, 25), 0 black columns, 0 black rows.)

F eyeballs: the Garage Core dead-centre and 2.5× its normal size, its ring of units filling the
frame, tiles crisp (nearest filter), the minimap's camera box small and inside the explored blob,
no black border on any edge.

## Done when
- `godot-4 --headless --path . --script tests/test_camera.gd` prints `CAMERA_RESULT: ALL PASS`.
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS` (11 suites including
  the new one), no `SCRIPT ERROR`, no `Parse Error`. `tests/test_p3_03_motion.gd` in particular
  must still pass (it does not touch the camera, but Change 2d is what keeps the `--motion`
  captures at zoom 2).
- `git status --short` shows exactly ` M presentation/Game.gd`, ` M presentation/RTSCamera.gd`,
  ` M project.godot`, `?? tests/test_camera.gd`, `?? docs/screenshot_cam_zoom.png` from your
  work. Nothing under `core/`, `gameplay/`, `presentation3d/`. `*.import` and `*.uid` are
  gitignored — do not add them. The tree may carry unrelated untracked files
  (`tools/deepseek_*.py`); leave them alone — `git add` only the five files above, never `-A`.
- `grep -n "zoom_step\|_zoom_at\|viewport_width\|viewport_height" presentation ui -r` returns nothing.
- `grep -n "func center_on" presentation/RTSCamera.gd` returns one line.
- `grep -n "^\[input\]" project.godot` returns nothing.
- `grep -n "KEY_W\|KEY_A\b\|KEY_S\b\|KEY_D\b" presentation/RTSCamera.gd` returns nothing (WASD unbound).
- `docs/screenshot_cam_zoom.png` passes the pixel checks above.
- Commit, then `git push origin master`:
  `feat(camera): arrow/edge/middle-drag pan, cursor-anchored smoothed zoom, H = home; --cam debug flag`
  Body (3–6 lines): camera math split into pure methods testable without a viewport
  (`viewport_size_override`); wheel scales a target zoom that eases exponentially and re-anchors
  on the cursor every frame; middle-drag in `_input` so HUD panels don't stall it; edge scroll
  gated on window focus; H jumps to the player's HQ via `Game._player_home()`; center_on() is the
  shared camera-jump entry point for p4-02/p4-03; dead WASD InputMap actions removed.
- Report: `git log --oneline -1`, the `CAMERA_RESULT` line, the pixel-check output, and the
  path of the screenshot.
