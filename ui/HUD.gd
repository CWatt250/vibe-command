extends CanvasLayer
class_name HUD
## HUD — screen-space shell for the player's faction (Phase 7, hud-inventory.md).
## Owns the corner panels; each panel is a plain Control that reads the sim on demand
## and reacts to GameEvents. Layout mirrors godot-open-rts Match.tscn (MIT): resources
## top-left, selection info bottom-left. Minimap stays bottom-right on its own layer.

var sim: Simulation
var events: GameEvents
var faction: String

var resource_bar: ResourceBar
var _selection_label: Label

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	layer = 30

func _ready() -> void:
	# Top-left: resources.
	var top_left := MarginContainer.new()
	top_left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top_left.add_theme_constant_override("margin_left", 8)
	top_left.add_theme_constant_override("margin_top", 8)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left)
	resource_bar = ResourceBar.new(sim, events, faction)
	top_left.add_child(resource_bar)

	# Bottom-left: selection info (build grid + production queue land here next).
	# Minimap keeps bottom-right. Corner-anchored containers start at zero size, so
	# they must grow toward the screen centre or their children land off-screen.
	var bottom_left := MarginContainer.new()
	bottom_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_left.add_theme_constant_override("margin_left", 8)
	bottom_left.add_theme_constant_override("margin_bottom", 8)
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_left)
	var panel := PanelContainer.new()
	bottom_left.add_child(panel)
	_selection_label = Label.new()
	_selection_label.custom_minimum_size = Vector2(220, 0)
	_selection_label.text = "Nothing selected"
	panel.add_child(_selection_label)

	events.entity_selected.connect(_on_entity_selected)
	events.game_tick.connect(_on_game_tick)

func _on_entity_selected(ids: Array[int]) -> void:
	_refresh_selection(ids)

func _on_game_tick(tick: int, _dt: float) -> void:
	# Health changes without a selection event; refresh at ~3 Hz.
	if tick % 5 == 0:
		_refresh_selection(sim.selected_ids)

func _refresh_selection(ids: Array) -> void:
	if ids.is_empty():
		_selection_label.text = "Nothing selected"
		return
	if ids.size() > 1:
		_selection_label.text = "%d units selected" % ids.size()
		return
	var e: Entity = sim.entities.get(ids[0])
	if e == null:
		_selection_label.text = "Nothing selected"
		return
	var display: String = e.def_data.get("displayName", e.def_id)
	var line := "%s\nHP %d / %d" % [display, int(e.health.current), int(e.health.max_health)]
	if e.construction != null and not e.construction.is_built():
		line += "\nBuilding %d%%" % int(e.construction.fraction() * 100.0)
	elif e.production != null and e.production.queue_size() > 0:
		var head: Dictionary = e.production.peek_first()
		line += "\nTraining %s %d%% (+%d queued)" % [
			head.get("unit", ""), int(e.production.progress() * 100.0), e.production.queue_size() - 1]
	_selection_label.text = line
