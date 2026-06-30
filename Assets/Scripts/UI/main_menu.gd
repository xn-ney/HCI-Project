extends Control


func _ready():
	$VBoxContainer/Start.pressed.connect(_on_start)
	$VBoxContainer/Options.pressed.connect(_on_options)
	$VBoxContainer/Exit.pressed.connect(_on_exit)


func _on_start():
	get_tree().change_scene_to_file("res://Scenes/UI/class_menu.tscn")


func _on_options():
	pass


func _on_exit():
	get_tree().quit()
