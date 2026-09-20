extends PanelContainer
class_name ResourceBar
## ResourceBar — credits + the faction's live systems (power, compute or command).
## Which columns show comes from factions.json `resourceIds`; numbers come from
## Simulation.faction_status(), which is a pure read of the same per-tick derivations.

const REFRESH_EVERY_TICKS := 5   # ~3 Hz at 15 tick/s; cheap, but no need for 15 Hz

var sim: Simulation
var events: GameEvents
var faction: String

var _labels: Dictionary = {}   # resource_id -> Label

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction

func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	var fdef: Dictionary = sim.registry.get_faction(faction)
	var ids: Array = fdef.get("resourceIds", ["credits"])
	# Federal Command gates on command capacity; it isn't in resourceIds, so add it.
	if fdef.get("id", "") == "FC" and not ids.has("command"):
		ids = ids + ["command"]
	for rid in ids:
		var label := Label.new()
		label.custom_minimum_size = Vector2(110, 0)
		row.add_child(label)
		_labels[rid] = label
	_refresh()
	events.game_tick.connect(_on_game_tick)
	events.resource_changed.connect(_on_resource_changed)

func _on_game_tick(tick: int, _dt: float) -> void:
	if tick % REFRESH_EVERY_TICKS == 0:
		_refresh()

func _on_resource_changed(f: String, _rid: String, _amount: float) -> void:
	if f == faction:
		_refresh()

func _refresh() -> void:
	var s: Dictionary = sim.faction_status(faction)
	for rid in _labels:
		var label: Label = _labels[rid]
		match rid:
			"credits":
				label.text = "$ %d" % int(s["credits"])
			"power":
				var p: Dictionary = s["power"]
				label.text = "Power %d/%d" % [int(p["produced"]), int(p["drawn"])]
				label.modulate = Color.WHITE if p["powered"] else Color(1.0, 0.45, 0.35)
			"compute":
				var c: Dictionary = s["compute"]
				label.text = "Compute %d/%d" % [int(c["usable"]), int(c["reserved"])]
				label.modulate = Color(1.0, 0.45, 0.35) if c["deficit"] else Color.WHITE
			"command":
				var c: Dictionary = s["command"]
				label.text = "Command %d/%d" % [int(c["reserved"]), int(c["capacity"])]
				label.modulate = Color(1.0, 0.45, 0.35) if c["deficit"] else Color.WHITE
			_:
				label.text = "%s %d" % [rid, int(sim.get_resources(faction).get(rid, 0.0))]
