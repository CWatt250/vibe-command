extends HBoxContainer
class_name ProductionQueuePanel
## ProductionQueuePanel — the selected producer's queue as a row of buttons.
## Head item shows live %, click any item to CANCEL_TRAIN it (credits refund in sim).
## Observer pattern after godot-open-rts ProductionQueue.gd (MIT), rebuilt on our
## event bus: rebind on selection, rebuild on enqueue or size change, tick the %.

var REFRESH_EVERY_TICKS := Simulation.ticks_per(3.0)

var sim: Simulation
var events: GameEvents
var faction: String

var _producer_id: int = -1

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	add_theme_constant_override("separation", 4)

func _ready() -> void:
	hide()
	events.entity_selected.connect(_on_entity_selected)
	events.production_queued.connect(_on_production_queued)
	events.game_tick.connect(_on_game_tick)

func _on_entity_selected(ids: Array[int]) -> void:
	_producer_id = -1
	if ids.size() == 1:
		var e: Entity = sim.entities.get(ids[0])
		if e != null and e.kind == "structure" and e.faction_id == faction and e.production != null:
			_producer_id = e.id
	_rebuild()

func _on_production_queued(entity_id: int, _unit_id: String, _cost: float) -> void:
	if entity_id == _producer_id:
		_rebuild()

func _on_game_tick(tick: int, _dt: float) -> void:
	if _producer_id < 0 or tick % REFRESH_EVERY_TICKS != 0:
		return
	var e: Entity = sim.entities.get(_producer_id)
	if e == null:
		_producer_id = -1
		_rebuild()
		return
	# Completed/cancelled items change the size; otherwise only the head % moves.
	if get_child_count() != e.production.queue_size():
		_rebuild()
	elif get_child_count() > 0:
		get_child(0).text = _label(e.production.queue[0], e.production.progress())

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var e: Entity = sim.entities.get(_producer_id) if _producer_id >= 0 else null
	if e == null or e.production.queue_size() == 0:
		hide()
		return
	for i in range(e.production.queue_size()):
		var item: Dictionary = e.production.queue[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		var icon := UiTheme.icon_for(item.get("unit", ""))
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.text = _label(item, e.production.progress() if i == 0 else 0.0)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var unit_name: String = sim.registry.get_unit(item.get("unit", "")).get("displayName", "?")
		b.tooltip_text = "%s — click to cancel (refunds $%d)" % [unit_name, int(item.get("paid_cost", 0.0))]
		UiTheme.style_button(b, faction)
		b.pressed.connect(_on_cancel.bind(i))
		add_child(b)
	show()

func _label(_item: Dictionary, progress: float) -> String:
	return "%d%%" % int(progress * 100.0)

func _on_cancel(index: int) -> void:
	if _producer_id < 0:
		return
	sim.run_commands(0, [{"type": "CANCEL_TRAIN", "entityIds": [_producer_id], "index": index}])
	_rebuild()
