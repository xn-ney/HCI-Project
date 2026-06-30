extends Control


func _ready():
	for col in $HBoxContainer.get_children():
		var panel = col.get_node("Panel")
		panel.focus_mode = FOCUS_NONE
		panel.mouse_entered.connect(_on_panel_hover.bind(panel))
		panel.mouse_exited.connect(_on_panel_unhover.bind(panel))
		panel.gui_input.connect(_on_panel_input.bind(panel, col.name.replace("Column", "")))


func _on_panel_hover(panel: Panel):
	panel.modulate = Color(1.2, 1.2, 1.2)


func _on_panel_unhover(panel: Panel):
	panel.modulate = Color.WHITE


func _on_panel_input(event: InputEvent, panel: Panel, class_type: String):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_class(class_type)


func _select_class(class_type: String):
	GameManager.selected_class = class_type
	GameManager.start_run()
	get_tree().change_scene_to_file("res://Scenes/world.tscn")
