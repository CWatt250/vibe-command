extends HBoxContainer
class_name ResourceBar
## ResourceBar — credits + the faction's live systems (power, compute or command) as chips.
## Which chips show comes from factions.json `resourceIds`; numbers come from
## Simulation.faction_status(), which is a pure read of the same per-tick derivations.

var REFRESH_EVERY_TICKS := Simulation.ticks_per(3.0)   # ~3 Hz; cheap, but no need for 15 Hz

var sim: Simulation
var events: GameEvents
var faction: String

var _labels: Dictionary = {}   # resource_id -> Label

func _init(simulation: Simulation, ev: GameEvents, player_faction: String) -> void:
	sim = simulation
	events = ev
	faction = player_faction
	add_theme_constant_override("separation", 6)

func _ready() -> void:
	var fdef: Dictionary = sim.registry.get_faction(faction)
	var ids: Array = fdef.get("resourceIds", ["credits"])
	# Federal Command gates on command capacity; it isn't in resourceIds, so add it.
	if fdef.get("id", "") == "FC" and not ids.has("command"):
		ids = ids + ["command"]
	for rid in ids:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.chip(faction))
		add_child(chip)
		var label := Label.new()
		label.custom_minimum_size = Vector2(96, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", UiTheme.TEXT)
		label.add_theme_font_size_override("font_size", 13)
		chip.add_child(label)
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
		var warn := false
		match rid:
			"credits":
				label.text = "$ " + UiTheme.money(s["credits"])
			"power":
				var p: Dictionary = s["power"]
				label.text = "POWER  %d / %d" % [int(p["produced"]), int(p["drawn"])]
				warn = not p["powered"]
			"compute":
				var c: Dictionary = s["compute"]
				label.text = "COMPUTE  %d / %d" % [int(c["usable"]), int(c["reserved"])]
				warn = c["deficit"]
			"command":
				var c: Dictionary = s["command"]
				label.text = "COMMAND  %d / %d" % [int(c["reserved"]), int(c["capacity"])]
				warn = c["deficit"]
			_:
				label.text = "%s %d" % [String(rid).to_upper(), int(sim.get_resources(faction).get(rid, 0.0))]
		label.add_theme_color_override("font_color", UiTheme.WARN if warn else UiTheme.TEXT)
