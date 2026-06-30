extends Panel

var player: Node = null

func populate(p: Node):
	player = p
	_update_ui()


func _update_ui():
	if not player:
		return

	_build_bag_grid()
	_build_equipment_slots()
	_build_hotkey_bar()


func _build_bag_grid():
	var grid = get_node_or_null("MarginContainer/VBox/BagGrid")
	if not grid:
		return
	for child in grid.get_children():
		child.queue_free()

	for i in range(12):
		var slot = Panel.new()
		slot.name = "BagSlot" + str(i)
		slot.size_flags_horizontal = SIZE_EXPAND_FILL
		slot.size_flags_vertical = SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(0, 24)

		var lbl = Label.new()
		lbl.name = "BagLabel" + str(i)
		lbl.anchor_left = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_top = 0.0
		lbl.anchor_bottom = 1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		var slot_idx = i
		lbl.gui_input.connect(func(event): _on_bag_slot_click(event, slot_idx))

		var item = player.bag[i] if i < player.bag.size() else null
		if item:
			var clr = item.rarity.color if item.rarity else Color(1, 1, 1)
			lbl.add_theme_color_override("font_color", clr)
			lbl.text = str(i + 1) + ": " + item.item_name
		else:
			lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			lbl.text = str(i + 1) + ": Empty"
		lbl.clip_text = true

		slot.add_child(lbl)
		grid.add_child(slot)


func _build_equipment_slots():
	var chest_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/ChestLabel")
	var torso_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/TorsoLabel")
	var acc_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/AccessoryLabel")
	if not chest_lbl or not torso_lbl or not acc_lbl:
		return

	var chest_item = player.equipment_chest if player else null
	var torso_item = player.equipment_torso if player else null
	var acc_item = player.equipment_accessory if player else null

	chest_lbl.text = "Chest: " + (chest_item.item_name if chest_item else "Empty")
	var chest_clr = chest_item.rarity.color if chest_item else Color(0.5, 0.5, 0.5)
	chest_lbl.add_theme_color_override("font_color", chest_clr)

	torso_lbl.text = "Torso: " + (torso_item.item_name if torso_item else "Empty")
	var torso_clr = torso_item.rarity.color if torso_item else Color(0.5, 0.5, 0.5)
	torso_lbl.add_theme_color_override("font_color", torso_clr)

	acc_lbl.text = "Acc: " + (acc_item.item_name if acc_item else "Empty")
	var acc_clr = acc_item.rarity.color if acc_item else Color(0.5, 0.5, 0.5)
	acc_lbl.add_theme_color_override("font_color", acc_clr)


func _build_hotkey_bar():
	var container = get_node_or_null("MarginContainer/VBox/HotkeyContainer")
	if not container:
		return
	for child in container.get_children():
		child.queue_free()

	for i in range(4):
		var slot = Panel.new()
		slot.name = "HotkeySlot" + str(i)
		slot.size_flags_horizontal = SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(0, 24)

		var lbl = Label.new()
		lbl.name = "HotkeyLabel" + str(i)
		lbl.anchor_left = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_top = 0.0
		lbl.anchor_bottom = 1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		var slot_idx = i
		lbl.gui_input.connect(func(event): _on_hotkey_click(event, slot_idx))

		var item = player.hotkey_slots[i] if player and i < player.hotkey_slots.size() else null
		if item:
			var clr = item.rarity.color if item.rarity else Color(1, 1, 1)
			lbl.add_theme_color_override("font_color", clr)
			var tag = ""
			if item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != "":
				tag = " [" + item.equipment_type.capitalize() + "]"
			lbl.text = str(i + 1) + ": " + item.item_name + tag
		else:
			lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			lbl.text = str(i + 1) + ": Empty"

		slot.add_child(lbl)
		container.add_child(slot)


func _on_bag_slot_click(event: InputEvent, slot: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not player:
			return
		var item = player.bag[slot] if slot < player.bag.size() else null
		if not item:
			return
		if item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != "":
			player.equip_from_bag(slot)
		else:
			player.move_to_hotkey(slot)
		_update_ui()


func _on_hotkey_click(event: InputEvent, slot: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if player:
			player.move_to_bag(slot)
		_update_ui()


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_close()


func _on_close():
	if player:
		player._toggle_inventory()


func _ready():
	var close_btn = get_node_or_null("CloseButton")
	if close_btn:
		close_btn.pressed.connect(_on_close)
	var chest_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/ChestLabel")
	var torso_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/TorsoLabel")
	var acc_lbl = get_node_or_null("MarginContainer/VBox/EquipmentRow/AccessoryLabel")
	if chest_lbl:
		chest_lbl.gui_input.connect(_on_inv_chest_click)
	if torso_lbl:
		torso_lbl.gui_input.connect(_on_inv_torso_click)
	if acc_lbl:
		acc_lbl.gui_input.connect(_on_inv_accessory_click)


func _on_inv_chest_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if player:
			player.unequip_item("equipment_chest")
		_update_ui()


func _on_inv_torso_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if player:
			player.unequip_item("equipment_torso")
		_update_ui()


func _on_inv_accessory_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if player:
			player.unequip_item("equipment_accessory")
		_update_ui()
