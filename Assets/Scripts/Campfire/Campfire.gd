extends Node3D

@export var prompt_text: String = "Press F to rest"

var player_in_range: bool = false
var campfire_ui: Control = null

func _ready():
	var area = $InteractionArea
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	var prompt = $InteractionPrompt
	if prompt:
		prompt.text = ""
		prompt.visible = false

func _input(event):
	if event.is_action_pressed("interact") and player_in_range and not campfire_ui:
		if _is_any_ui_open():
			return
		open_ui()

func _is_any_ui_open() -> bool:
	for c in get_tree().current_scene.get_children():
		if c is CanvasLayer:
			return true
	return false

func open_ui():
	_stop_player_actions()
	var layer = CanvasLayer.new()
	layer.layer = 1
	get_tree().current_scene.add_child(layer)
	var scene = load("res://Scenes/UI/campfire_ui.tscn")
	var instance = scene.instantiate()
	layer.add_child(instance)
	campfire_ui = instance
	if instance.has_method("setup"):
		instance.setup(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameManager.ui_open = true

func _stop_player_actions():
	var player = _find_player()
	if not player:
		return
	player.melee_timer = 0.0
	player.has_hit_this_swing = false
	player.is_dashing = false
	player.is_sprinting = false

func rest():
	var player = _find_player()
	if not player:
		return
	var lost = player.max_hp - player.hp
	player.hp = min(player.hp + lost * 0.5, player.max_hp)

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func close_ui():
	if campfire_ui:
		var parent = campfire_ui.get_parent()
		if parent:
			parent.queue_free()
		campfire_ui = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameManager.ui_open = false

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		var prompt = $InteractionPrompt
		if prompt:
			prompt.text = prompt_text
			prompt.visible = true

func advance_floor():
	GameManager.advance_from_campfire()

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		var prompt = $InteractionPrompt
		if prompt:
			prompt.text = ""
			prompt.visible = false
		if campfire_ui:
			close_ui()
