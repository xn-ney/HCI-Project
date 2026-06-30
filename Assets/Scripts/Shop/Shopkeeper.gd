extends CharacterBody3D

@export var item_pool: Array[Resource] = []
@export var equipment_pool: Array[Resource] = []
@export var prompt_text: String = "Press F to shop"

var available_items: Array[Resource] = []
var available_equipment: Array[Resource] = []
var player_in_range: bool = false
var shop_ui: Control = null
var bought_paths: Dictionary = {}

func _ready():
	bought_paths.clear()
	var area = $InteractionArea
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	var prompt = $InteractionPrompt
	if prompt:
		prompt.text = ""
		prompt.visible = false
	pick_random_items()
	pick_random_equipment()

func pick_random_items():
	available_items.clear()
	var player = get_tree().get_first_node_in_group("player")
	var player_class = ""
	if player and player.active_class:
		player_class = player.active_class.name.replace("Stats", "").to_lower()

	var pool = item_pool.duplicate()
	pool = pool.filter(func(item):
		var restrict = item.class_restriction.to_lower()
		return restrict == "" or restrict == player_class
	)

	var common: Array[Resource] = []
	var rare: Array[Resource] = []
	var epic: Array[Resource] = []
	for item in pool:
		var order = 0
		if item.rarity:
			order = item.rarity.sort_order
		if order == 2:
			epic.append(item)
		elif order == 1:
			rare.append(item)
		else:
			common.append(item)

	var count = randi_range(4, 6)
	for _i in range(count):
		var chosen = _pick_rarity_item(common, rare, epic)
		if chosen:
			available_items.append(chosen)

func pick_random_equipment():
	available_equipment.clear()
	var player = get_tree().get_first_node_in_group("player")
	var player_class = ""
	if player and player.active_class:
		player_class = player.active_class.name.replace("Stats", "").to_lower()

	var pool = equipment_pool.duplicate()
	pool = pool.filter(func(item):
		var restrict = item.class_restriction.to_lower()
		return restrict == "" or restrict == player_class
	)

	var common: Array[Resource] = []
	var rare: Array[Resource] = []
	var epic: Array[Resource] = []
	for item in pool:
		var order = 0
		if item.rarity:
			order = item.rarity.sort_order
		if order == 2:
			epic.append(item)
		elif order == 1:
			rare.append(item)
		else:
			common.append(item)

	var count = randi_range(3, 5)
	for _i in range(count):
		var chosen = _pick_rarity_item(common, rare, epic)
		if chosen:
			available_equipment.append(chosen)

func _pick_rarity_item(common: Array, rare: Array, epic: Array) -> Resource:
	var roll = randf()
	var bucket: Array
	if roll < 0.03 and not epic.is_empty():
		bucket = epic
	elif roll < 0.15 and not rare.is_empty():
		bucket = rare
	else:
		bucket = common
	if bucket.is_empty():
		if not rare.is_empty():
			bucket = rare
		elif not common.is_empty():
			bucket = common
		else:
			return null
	var idx = randi() % bucket.size()
	var chosen = bucket[idx]
	bucket.remove_at(idx)
	return chosen

func _input(event):
	if event.is_action_pressed("interact") and player_in_range and not shop_ui:
		if _is_any_ui_open():
			return
		open_shop()

func _is_any_ui_open() -> bool:
	return GameManager.ui_open

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
		instance.populate(available_items, available_equipment, bought_paths, self)
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

func mark_bought(path: String):
	bought_paths[path] = true

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
		if shop_ui:
			close_shop()
