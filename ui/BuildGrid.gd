extends GridContainer
class_name BuildGrid
## BuildGrid — context buttons for the single selected, built, player-owned structure.
## TRAIN mode: the def's `trainsUnits` as unit buttons (issues TRAIN on this producer).
## BUILD mode: a BuilderNetwork structure (the HQ) lists the faction's structures; a
## press emits place_requested and the PlacementGhost takes over. Greys out what the
## faction can't afford. Tech tier isn't gated here because the sim doesn't gate it yet.

signal place_requested(structure_def_id: String)

var REFRESH_EVERY_TICKS := Simulation.ticks_per(3.0)

var sim: Simulation
var events: GameEvents
var faction: String

var _producer_id: int = -1
var _buttons: Dictionary = {}   # def_id -> Button
var _costs: Dictionary = {}     # def_id -> cost, so affordability doesn't care which mode

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	columns = 5
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)

func _ready() -> void:
	hide()
	events.entity_selected.connect(_on_entity_selected)
	events.game_tick.connect(_on_game_tick)

func _on_entity_selected(ids: Array[int]) -> void:
	_rebind(ids)

func _on_game_tick(tick: int, _dt: float) -> void:
	if _producer_id < 0 or tick % REFRESH_EVERY_TICKS != 0:
		return
	if not sim.entities.has(_producer_id):
		_rebind([])
		return
	_refresh_affordability()

func _rebind(ids: Array) -> void:
	_producer_id = -1
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_costs.clear()
	var e := _owned_built_structure(ids)
	if e == null:
		hide()
		return
	var trains: Array = e.def_data.get("trainsUnits", [])
	var flags: Array = e.def_data.get("componentFlags", [])
	if e.production != null and not trains.is_empty():
		_producer_id = e.id
		for uid in trains:
			var d: Dictionary = sim.registry.get_unit(uid)
			if not d.is_empty():
				_add_button(uid, d, _on_train.bind(uid))
	elif flags.has("BuilderNetwork"):
		_producer_id = e.id
		for sid in sim.registry.all_structures():
			var d: Dictionary = sim.registry.get_structure(sid)
			if d.get("factionId", "") == faction:
				_add_button(sid, d, _on_place.bind(sid))
	if _buttons.is_empty():
		_producer_id = -1
		hide()
		return
	_refresh_affordability()
	show()

func _add_button(id: String, d: Dictionary, on_pressed: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.focus_mode = Control.FOCUS_NONE
	# Sprite on top, cost underneath; the name lives in the tooltip.
	var icon := UiTheme.icon_for(id)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.text = "$" + UiTheme.money(d.get("costCredits", 0.0))
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = "%s\n%s\nHP %d · %s · %.0fs" % [
		d.get("displayName", id), d.get("role", d.get("function", d.get("desc", ""))),
		int(d.get("maxHealth", 0)), d.get("armorClass", "?"), d.get("buildTimeSec", 0.0)]
	UiTheme.style_button(b, faction)
	b.pressed.connect(on_pressed)
	add_child(b)
	_buttons[id] = b
	_costs[id] = d.get("costCredits", 0.0)

## The one selected entity if it's a built structure we own; else null.
func _owned_built_structure(ids: Array) -> Entity:
	if ids.size() != 1:
		return null
	var e: Entity = sim.entities.get(ids[0])
	if e == null or e.kind != "structure" or e.faction_id != faction:
		return null
	if e.construction != null and not e.construction.is_built():
		return null
	return e

func _refresh_affordability() -> void:
	var credits: float = sim.get_resources(faction).get("credits", 0.0)
	for id in _buttons:
		_buttons[id].disabled = credits < _costs[id]

func _on_place(sid: String) -> void:
	if _producer_id < 0:
		return
	place_requested.emit(sid)

func _on_train(uid: String) -> void:
	if _producer_id < 0:
		return
	sim.run_commands(0, [{"type": "TRAIN", "entityIds": [_producer_id], "unitDefId": uid}])
