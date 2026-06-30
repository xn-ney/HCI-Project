extends Panel

@onready var item_container = $MarginContainer/ScrollContainer/ItemContainer
@onready var close_button = $CloseButton
@onready var shop_title = $ShopTitle
@onready var tab_potions = $TabPotions
@onready var tab_armor = $TabArmor
@onready var tab_sell = $TabSell

var shopkeeper: Node = null
var potion_items: Array[Resource] = []
var armor_items: Array[Resource] = []
var current_tab: String = "potions"
var bought_paths: Dictionary = {}

static var _notif_label: Label = null
static var _notif_tween: Tween = null

func _ready():
	close_button.pressed.connect(_on_close)
	shop_title.text = "Merchant's Wares"
	if tab_potions:
		tab_potions.pressed.connect(_switch_tab.bind("potions"))
	if tab_armor:
		tab_armor.pressed.connect(_switch_tab.bind("armor"))
	if tab_sell:
		tab_sell.pressed.connect(_switch_tab.bind("sell"))

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_close()

func populate(potions: Array[Resource], armor: Array[Resource], keeper_bought: Dictionary, keeper: Node):
	potion_items = potions
	armor_items = armor
	shopkeeper = keeper
	bought_paths = keeper_bought.duplicate()
	_switch_tab("potions")

func _switch_tab(tab: String):
	current_tab = tab
	if tab_potions:
		tab_potions.disabled = (tab == "potions")
	if tab_armor:
		tab_armor.disabled = (tab == "armor")
	if tab_sell:
		tab_sell.disabled = (tab == "sell")
	if tab == "potions":
		_rebuild_list(potion_items)
	elif tab == "armor":
		_rebuild_list(armor_items)
	else:
		_rebuild_sell_list()

func _rebuild_list(items: Array[Resource]):
	for child in item_container.get_children():
		child.queue_free()

	if items.is_empty():
		var empty = Label.new()
		empty.text = "Nothing available."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.add_theme_font_size_override("font_size", 18)
		item_container.add_child(empty)
		return

	var size_order = [
		load("res://Resources/SizeTiers/common.tres"),
		load("res://Resources/SizeTiers/rare.tres"),
		load("res://Resources/SizeTiers/epic.tres"),
	]

	for tier in size_order:
		var items_of_size = items.filter(func(i): return i.rarity == tier)
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
			var bought = bought_paths.has(item.resource_path)

			var name_label = RichTextLabel.new()
			name_label.bbcode_enabled = true
			name_label.text = "[color=#" + tier.color.to_html() + "]" + item.item_name + "[/color]"
			if bought:
				name_label.text = "[u]" + name_label.text + "[/u]"
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_label.add_theme_font_size_override("normal_font_size", 18)
			name_label.size_flags_horizontal = SIZE_EXPAND_FILL
			name_label.custom_minimum_size = Vector2(180, 0)
			row.add_child(name_label)

			var desc = item.description
			if item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != "":
				var stats = ""
				if item.hp_bonus > 0: stats += " HP+" + str(item.hp_bonus)
				if item.stamina_bonus > 0: stats += " STA+" + str(item.stamina_bonus)
				if item.defense > 0: stats += " DEF+" + str(item.defense)
				if stats != "": desc += " |" + stats
				if item.class_unique_effect != "": desc += " [" + item.class_unique_effect + "]"

			var desc_label = Label.new()
			desc_label.text = desc
			desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			desc_label.size_flags_horizontal = SIZE_EXPAND_FILL
			desc_label.custom_minimum_size = Vector2(300, 0)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(desc_label)

			var price_label = Label.new()
			price_label.text = str(item.price) + "g"
			price_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
			price_label.custom_minimum_size = Vector2(60, 0)
			row.add_child(price_label)

			var buy_btn = Button.new()
			if bought:
				buy_btn.text = "Bought"
				buy_btn.disabled = true
			else:
				buy_btn.text = "Buy"
				buy_btn.pressed.connect(_on_buy.bind(item))
			row.add_child(buy_btn)

			item_container.add_child(row)

func _rebuild_sell_list():
	for child in item_container.get_children():
		child.queue_free()

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var sellables: Array[Dictionary] = []
	for i in range(player.bag.size()):
		if player.bag[i] != null:
			sellables.append({ "item": player.bag[i], "slot": i, "source": "bag" })
	for i in range(player.hotkey_slots.size()):
		if player.hotkey_slots[i] != null:
			sellables.append({ "item": player.hotkey_slots[i], "slot": i, "source": "hotkey" })

	if sellables.is_empty():
		var empty = Label.new()
		empty.text = "Nothing to sell."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.add_theme_font_size_override("font_size", 18)
		item_container.add_child(empty)
		return

	var header = Label.new()
	header.text = "--- Click to Sell ---"
	header.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_constant_override("margin", 8)
	item_container.add_child(header)

	for entry in sellables:
		var item = entry.item
		var row = HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = item.item_name
		var color = Color(1, 1, 1)
		if item.has_method("get") and item.get("rarity") != null:
			color = item.rarity.color if item.rarity else Color(1, 1, 1)
		name_label.add_theme_color_override("font_color", color)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(180, 0)
		row.add_child(name_label)

		var sell_price = item.price / 8
		var price_label = Label.new()
		price_label.text = "Sell: " + str(sell_price) + "g"
		price_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.0))
		price_label.custom_minimum_size = Vector2(100, 0)
		row.add_child(price_label)

		var sell_btn = Button.new()
		sell_btn.text = "Sell"
		sell_btn.pressed.connect(_on_sell.bind(entry))
		row.add_child(sell_btn)

		item_container.add_child(row)

func _on_buy(item: Resource):
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("add_item"):
		return
	if player.gold < item.price:
		_show_notification("Not enough gold!")
		return
	if player.add_item(item):
		player.gold -= item.price
		_show_notification("Bought " + item.item_name)
		if shopkeeper and shopkeeper.has_method("mark_bought"):
			shopkeeper.mark_bought(item.resource_path)
		bought_paths[item.resource_path] = true
		_switch_tab(current_tab)
	else:
		_show_notification("Inventory full!")

func _on_sell(entry: Dictionary):
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var item = entry.item
	var sell_price = item.price / 8
	if entry.source == "bag":
		player.bag[entry.slot] = null
	else:
		player.hotkey_slots[entry.slot] = null
	player.gold += sell_price
	player._update_bag_hud()
	player._update_hotkey_hud()
	_show_notification("Sold " + item.item_name + " for " + str(sell_price) + "g")
	_rebuild_sell_list()

func _show_notification(text: String):
	if _notif_tween and _notif_tween.is_valid():
		_notif_tween.kill()
	if _notif_label:
		_notif_label.queue_free()

	_notif_label = Label.new()
	_notif_label.text = text
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
