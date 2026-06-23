extends CharacterBody3D

@export var item_pool: Array[Resource] = []
@export var prompt_text: String = "Press F to shop"

var available_items: Array[Resource] = []
var player_in_range: bool = false
var shop_ui: Control = null

func _ready():
	var area = $InteractionArea
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	var prompt = $InteractionPrompt
	if prompt:
		prompt.text = ""
		prompt.visible = false
	pick_random_items()

func pick_random_items():
	available_items.clear()
	var pool = item_pool.duplicate()
	pool.shuffle()
	var count = randi_range(4, 6)
	available_items = pool.slice(0, count)

func _input(event):
	if event.is_action_pressed("interact") and player_in_range and not shop_ui:
		if _is_any_ui_open():
			return
		open_shop()

func _is_any_ui_open() -> bool:
	for c in get_tree().current_scene.get_children():
		if c is CanvasLayer:
			return true
	return false

func _input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and player_in_range and not shop_ui:
		if _is_any_ui_open():
			return
		open_shop()

func open_shop():
	_stop_player_actions()
	var layer = CanvasLayer.new()
	layer.layer = 1
	get_tree().current_scene.add_child(layer)
	var scene = load("res://Scenes/UI/shop_ui.tscn")
	var instance = scene.instantiate()
	layer.add_child(instance)
	shop_ui = instance
	if instance.has_method("populate"):
		instance.populate(available_items, self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameManager.ui_open = true

func _stop_player_actions():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	player.melee_timer = 0.0
	player.has_hit_this_swing = false
	player.is_dashing = false
	player.is_sprinting = false

func close_shop():
	if shop_ui:
		var parent = shop_ui.get_parent()
		if parent:
			parent.queue_free()
		else:
			shop_ui.queue_free()
		shop_ui = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameManager.ui_open = false

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		var prompt = $InteractionPrompt
		if prompt:
			prompt.text = prompt_text
			prompt.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		var prompt = $InteractionPrompt
		if prompt:
			prompt.text = ""
			prompt.visible = false
