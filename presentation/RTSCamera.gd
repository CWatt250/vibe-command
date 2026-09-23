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
