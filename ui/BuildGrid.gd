extends GridContainer
class_name BuildGrid
## BuildGrid — TRAIN buttons for the single selected, built, player-owned producer.
## Buttons come from the structure def's `trainsUnits`; cost/tooltip from the unit def.
## Greys out what the faction can't afford. BUILD mode (structures) is step 4.

const REFRESH_EVERY_TICKS := 5

var sim: Simulation
var events: GameEvents
var faction: String

var _producer_id: int = -1
var _buttons: Dictionary = {}   # unit_def_id -> Button

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	columns = 4
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
	var e := _owned_producer(ids)
	if e == null:
		hide()
		return
	var trains: Array = e.def_data.get("trainsUnits", [])
	if trains.is_empty():
		hide()
		return
	_producer_id = e.id
	for uid in trains:
		var d: Dictionary = sim.registry.get_unit(uid)
		if d.is_empty():
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(100, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%s\n$%d" % [d.get("displayName", uid), int(d.get("costCredits", 0.0))]
		b.tooltip_text = "%s\n%s\nHP %d · %s armor · %.0fs" % [
			d.get("displayName", uid), d.get("role", d.get("desc", "")),
			int(d.get("maxHealth", 0)), d.get("armorClass", "?"), d.get("buildTimeSec", 0.0)]
		b.pressed.connect(_on_train.bind(uid))
		add_child(b)
		_buttons[uid] = b
	_refresh_affordability()
	show()

## The one selected entity if it's a built production structure we own; else null.
func _owned_producer(ids: Array) -> Entity:
	if ids.size() != 1:
		return null
	var e: Entity = sim.entities.get(ids[0])
	if e == null or e.kind != "structure" or e.faction_id != faction or e.production == null:
		return null
	if e.construction != null and not e.construction.is_built():
		return null
	return e

func _refresh_affordability() -> void:
	var credits: float = sim.get_resources(faction).get("credits", 0.0)
	for uid in _buttons:
		var cost: float = sim.registry.get_unit(uid).get("costCredits", 0.0)
		_buttons[uid].disabled = credits < cost

func _on_train(uid: String) -> void:
	if _producer_id < 0:
		return
	sim.run_commands(0, [{"type": "TRAIN", "entityIds": [_producer_id], "unitDefId": uid}])
