extends Camera2D
class_name RTSCamera
## RTS camera — pan (edge + arrow keys), zoom (wheel), follow (control groups).
## World-space; drag-select box and minimap both need to project via this.

@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var pan_speed: float = 600.0        # world px/sec at zoom 1
@export var edge_margin: int = 24           # screen px edge-scroll zone
@export var zoom_step: float = 0.1

var dragging_pan: bool = false

func _ready() -> void:
	if not is_current():
		make_current()

func _init() -> void:
	pass

func _process(delta: float) -> void:
	# Edge scrolling — only when mouse is near the window edge and not dragging.
	if not dragging_pan and _mouse_in_window():
		var mpos := get_viewport().get_mouse_position()
		var vp := get_viewport_rect().size
		var dir := Vector2.ZERO
		if mpos.x <= edge_margin: dir.x -= 1
		elif mpos.x >= vp.x - edge_margin: dir.x += 1
		if mpos.y <= edge_margin: dir.y -= 1
		elif mpos.y >= vp.y - edge_margin: dir.y += 1
		if dir != Vector2.ZERO:
			position += dir.normalized() * pan_speed * delta / zoom.x
	# Keep camera clamped to world bounds.
	_clamp_to_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(get_viewport().get_mouse_position(), 1.0 + zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(get_viewport().get_mouse_position(), 1.0 - zoom_step)

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

func _clamp_to_world() -> void:
	position.x = clampf(position.x, zoom.x * viewport_width() * 0.5, _world_width - zoom.x * viewport_width() * 0.5)
	position.y = clampf(position.y, zoom.y * viewport_height() * 0.5, _world_height - zoom.y * viewport_height() * 0.5)

func viewport_width() -> float:
	return get_viewport_rect().size.x
func viewport_height() -> float:
	return get_viewport_rect().size.y

## World bounds (set by the map). Centers for clamping.
var _world_width: float = 2000.0
var _world_height: float = 2000.0
func set_world_size(w: float, h: float) -> void:
	_world_width = w
	_world_height = h

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - get_viewport_rect().size * 0.5) / zoom + position

func world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - position) * zoom + get_viewport_rect().size * 0.5

func _mouse_in_window() -> bool:
	var mpos := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	return mpos.x >= 0 and mpos.x <= vp.x and mpos.y >= 0 and mpos.y <= vp.y
