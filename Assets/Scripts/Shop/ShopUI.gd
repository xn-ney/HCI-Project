extends Panel

@onready var item_container = $MarginContainer/ScrollContainer/ItemContainer
@onready var close_button = $CloseButton
@onready var shop_title = $ShopTitle

var shopkeeper: Node = null
var shop_items: Array[Resource] = []

static var _notif_label: Label = null
static var _notif_tween: Tween = null

func _ready():
	close_button.pressed.connect(_on_close)
	shop_title.text = "Merchant's Wares"

func populate(items: Array[Resource], keeper: Node):
	shop_items = items
	shopkeeper = keeper
	_rebuild_list()

func _rebuild_list():
	for child in item_container.get_children():
		child.queue_free()

	var size_order = [
		load("res://Resources/SizeTiers/small.tres"),
		load("res://Resources/SizeTiers/medium.tres"),
		load("res://Resources/SizeTiers/large.tres"),
	]

	for tier in size_order:
		var items_of_size = shop_items.filter(func(i): return i.rarity == tier)
		if items_of_size.is_empty():
			continue

		var header = Label.new()
		header.text = "--- " + tier.size_name + " ---"
		header.add_theme_color_override("font_color", tier.color)
		header.add_theme_font_size_override("font_size", 22)
		header.add_theme_constant_override("margin", 8)
		item_container.add_child(header)

		for item in items_of_size:
			var row = HBoxContainer.new()
			row.size_flags_horizontal = SIZE_EXPAND_FILL

			var name_label = Label.new()
			name_label.text = item.item_name
			name_label.add_theme_color_override("font_color", tier.color)
			name_label.add_theme_font_size_override("font_size", 18)
			name_label.size_flags_horizontal = SIZE_EXPAND_FILL
			name_label.custom_minimum_size = Vector2(180, 0)
			row.add_child(name_label)

			var desc_label = Label.new()
			desc_label.text = item.description
			desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			desc_label.size_flags_horizontal = SIZE_EXPAND_FILL
			desc_label.custom_minimum_size = Vector2(250, 0)
			row.add_child(desc_label)

			var price_label = Label.new()
			price_label.text = str(item.price) + "g"
			price_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
			price_label.custom_minimum_size = Vector2(60, 0)
			row.add_child(price_label)

			var buy_btn = Button.new()
			buy_btn.text = "Buy"
			buy_btn.pressed.connect(_on_buy.bind(item))
			row.add_child(buy_btn)

			item_container.add_child(row)

func _on_buy(item: Resource):
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("add_item"):
		return
	if player.add_item(item):
		print("Bought: ", item.item_name)
		_show_notification(item.item_name)
		if shopkeeper and shopkeeper.has_method("close_shop"):
			shopkeeper.close_shop()
	else:
		_show_notification("Inventory full!")

func _show_notification(item_name: String):
	if _notif_tween and _notif_tween.is_valid():
		_notif_tween.kill()
	if _notif_label:
		_notif_label.queue_free()

	_notif_label = Label.new()
	_notif_label.text = "Bought " + item_name
	_notif_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notif_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notif_label.add_theme_color_override("font_color", Color(1, 0.8, 0.1))
	_notif_label.add_theme_font_size_override("font_size", 28)
	_notif_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_notif_label.add_theme_constant_override("shadow_offset_x", 2)
	_notif_label.add_theme_constant_override("shadow_offset_y", 2)
	_notif_label.anchor_left = 0.2
	_notif_label.anchor_right = 0.8
	_notif_label.anchor_top = 0.85
	_notif_label.anchor_bottom = 0.92
	get_tree().root.add_child(_notif_label)

	_notif_tween = get_tree().create_tween()
	_notif_tween.tween_property(_notif_label, "modulate:a", 1.0, 0.2)
	_notif_tween.tween_interval(1.3)
	_notif_tween.tween_property(_notif_label, "modulate:a", 0.0, 0.5)
	_notif_tween.tween_callback(_clear_notif)

static func _clear_notif():
	if _notif_label:
		_notif_label.queue_free()
	_notif_label = null
	_notif_tween = null

func _on_close():
	if shopkeeper and shopkeeper.has_method("close_shop"):
		shopkeeper.close_shop()
