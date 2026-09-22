extends CanvasLayer
class_name HUD
## HUD — screen-space shell for the player's faction (Phase 7 + V7 skin).
## Owns the corner panels; each panel is a plain Control that reads the sim on demand
## and reacts to GameEvents. Resources top-left as chips; a selection card with
## portrait, queue and build grid bottom-left that collapses when nothing is selected.
## Minimap stays bottom-right on its own layer. Look comes from UiTheme.

var sim: Simulation
var events: GameEvents
var faction: String

var resource_bar: ResourceBar
var queue_panel: ProductionQueuePanel
var build_grid: BuildGrid
var _card: PanelContainer
var _portrait: TextureRect
var _title: Label
var _stats: Label
var _stop_button: Button
var _match_panel: Control
var _result_label: Label

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	layer = 30

func _ready() -> void:
	# Top-left: resource chips.
	var top_left := MarginContainer.new()
	top_left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top_left.add_theme_constant_override("margin_left", 8)
	top_left.add_theme_constant_override("margin_top", 8)
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left)
	resource_bar = ResourceBar.new(sim, events, faction)
	top_left.add_child(resource_bar)

	# Bottom-left: selection card. Corner-anchored containers start at zero size, so
	# they must grow toward the screen centre or their children land off-screen.
	var bottom_left := MarginContainer.new()
	bottom_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_left.add_theme_constant_override("margin_left", 8)
	bottom_left.add_theme_constant_override("margin_bottom", 8)
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_left)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.panel(faction))
	bottom_left.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)

	# Header: portrait + name/stats + Stop.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.add_child(_portrait)
	var text_col := VBoxContainer.new()
	text_col.custom_minimum_size = Vector2(180, 0)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(text_col)
	_title = Label.new()
	_title.add_theme_color_override("font_color", UiTheme.accent(faction))
	_title.add_theme_font_size_override("font_size", 14)
	text_col.add_child(_title)
	_stats = Label.new()
	_stats.add_theme_color_override("font_color", UiTheme.TEXT)
	_stats.add_theme_font_size_override("font_size", 12)
	text_col.add_child(_stats)
	_stop_button = Button.new()
	_stop_button.text = "STOP"
	_stop_button.custom_minimum_size = Vector2(56, 0)
	_stop_button.focus_mode = Control.FOCUS_NONE
	_stop_button.tooltip_text = "Halt the selected units (S)"
	UiTheme.style_button(_stop_button, faction)
	_stop_button.pressed.connect(_on_stop)
	header.add_child(_stop_button)

	queue_panel = ProductionQueuePanel.new(sim, events, faction)
	column.add_child(queue_panel)
	build_grid = BuildGrid.new(sim, events, faction)
	column.add_child(build_grid)

	_card.hide()
	_match_panel = _build_match_panel()
	events.entity_selected.connect(_on_entity_selected)
	events.game_tick.connect(_on_game_tick)
	events.match_over.connect(_on_match_over)

## Centred result card. PROCESS_MODE_ALWAYS so its Restart button still takes input
## after the tree is paused (same pattern as PauseMenu, which owns Esc).
func _build_match_panel() -> Control:
	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(faction))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(260, 0)
	panel.add_child(column)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 32)
	column.add_child(_result_label)
	var restart := Button.new()
	restart.text = "Restart"
	restart.focus_mode = Control.FOCUS_NONE
	restart.tooltip_text = "Reload the skirmish"
	UiTheme.style_button(restart, faction)
	restart.pressed.connect(_on_restart)
	column.add_child(restart)
	root.hide()
	return root

func _on_match_over(loser: String, winner: String) -> void:
	var won := winner == faction
	_result_label.text = "VICTORY" if won else "DEFEAT"
	_result_label.add_theme_color_override("font_color", UiTheme.accent(faction) if won else UiTheme.WARN)
	_match_panel.show()
	# The sim stops ticking with the tree; the panel above keeps processing input.
	get_tree().paused = true

func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_entity_selected(ids: Array[int]) -> void:
	_refresh_selection(ids)

func _on_game_tick(tick: int, _dt: float) -> void:
	# Health changes without a selection event; refresh at ~3 Hz.
	if tick % Simulation.ticks_per(3.0) == 0 and _card.visible:
		_refresh_selection(sim.selected_ids)

func _on_stop() -> void:
	if not sim.selected_ids.is_empty():
		sim.run_commands(0, [{"type": "STOP", "entityIds": sim.selected_ids.duplicate()}])

func _refresh_selection(ids: Array) -> void:
	if ids.is_empty():
		_card.hide()
		return
	_card.show()
	if ids.size() > 1:
		_portrait.texture = UiTheme.icon_for(sim.entities[ids[0]].def_id) if sim.entities.has(ids[0]) else null
		_title.text = "%d units" % ids.size()
		_stats.text = _group_summary(ids)
		_stop_button.visible = true
		return
	var e: Entity = sim.entities.get(ids[0])
	if e == null:
		_card.hide()
		return
	_portrait.texture = UiTheme.icon_for(e.def_id)
	_title.text = e.def_data.get("displayName", e.def_id)
	var line := "HP %d / %d" % [int(e.health.current), int(e.health.max_health)]
	var armor: String = e.def_data.get("armorClass", "")
	if armor != "":
		line += "   %s" % armor
	if e.construction != null and not e.construction.is_built():
		line += "\nBuilding %d%%" % int(e.construction.fraction() * 100.0)
	elif e.production != null and e.production.queue_size() > 0:
		var head: Dictionary = e.production.peek_first()
		var unit_name: String = sim.registry.get_unit(head.get("unit", "")).get("displayName", head.get("unit", "?"))
		line += "\nTraining %s %d%%" % [unit_name, int(e.production.progress() * 100.0)]
	elif e.kind == "unit" and e.movement != null and e.movement.is_moving():
		line += "\nMoving"
	_stats.text = line
	_stop_button.visible = e.kind == "unit"

func _group_summary(ids: Array) -> String:
	var counts: Dictionary = {}
	var hp := 0.0
	var hp_max := 0.0
	for id in ids:
		var e: Entity = sim.entities.get(id)
		if e == null:
			continue
		var n: String = e.def_data.get("displayName", e.def_id)
		counts[n] = counts.get(n, 0) + 1
		if e.health != null:
			hp += e.health.current
			hp_max += e.health.max_health
	var parts: Array = []
	for n in counts:
		parts.append("%d× %s" % [counts[n], n])
	var text := ", ".join(parts)
	if hp_max > 0.0:
		text += "\nHP %d / %d" % [int(hp), int(hp_max)]
	return text
