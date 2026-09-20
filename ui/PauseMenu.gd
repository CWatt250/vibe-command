extends CanvasLayer
class_name PauseMenu
## PauseMenu — Esc toggles a centred panel and get_tree().paused. Port of godot-open-rts
## match/Menu.gd (MIT) minus the main-menu handoff (there is no main menu yet; Quit exits).
## Runs with PROCESS_MODE_ALWAYS so it still hears Esc while the tree is paused. Uses
## _unhandled_input so an active PlacementGhost (which consumes Esc) wins.

func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	hide()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(220, 0)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(toggle)
	column.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
