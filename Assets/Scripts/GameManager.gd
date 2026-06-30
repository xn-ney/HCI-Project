extends Node

# Signals ------------------------------------------
signal floor_changed(floor_number: int)
signal floor_cleared(floor_number: int)

# State --------------------------------------------
var current_floor: int = 0
var is_running: bool = false
var current_condition_type: int = 1
var ui_open: bool = false

# Scene paths --------------------------------------
const COMBAT_SCENE: String = "res://Scenes/world.tscn"
const REST_SCENE: String = "res://Scenes/rest_area.tscn"

# Saved player state (persists across scene changes)
var saved_hp: float = -1.0
var saved_max_hp: float = -1.0
var saved_stamina: float = -1.0
var saved_max_stamina: float = -1.0
var saved_hotkey_slots: Array = []
var saved_bag: Array = []
var saved_gold: int = -1
var saved_equipment_chest: Resource = null
var saved_equipment_torso: Resource = null
var saved_equipment_accessory: Resource = null

# Condition registry -------------------------------
var condition_scripts: Dictionary = {
	1: AmbushCondition,
	2: CleanseCondition,
}

# Auto-start on game launch ------------------------
func _ready():
	call_deferred("start_run")

# Run lifecycle ------------------------------------
func start_run():
	current_floor = 0
	is_running = true
	saved_gold = -1
	_roll_condition()
	print("=== LEVEL START ===")
	go_to_next_floor()


func go_to_next_floor():
	current_floor += 1
	floor_changed.emit(current_floor)
	print("Entering floor ", current_floor)

func save_player_state():
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		return
	saved_hp = p.hp
	saved_max_hp = p.max_hp
	saved_stamina = p.stamina
	saved_max_stamina = p.max_stamina
	if "hotkey_slots" in p:
		saved_hotkey_slots = p.hotkey_slots.duplicate()
	if "bag" in p:
		saved_bag = p.bag.duplicate()
	if "gold" in p:
		saved_gold = p.gold
	if "equipment_chest" in p:
		saved_equipment_chest = p.equipment_chest
	if "equipment_torso" in p:
		saved_equipment_torso = p.equipment_torso
	if "equipment_accessory" in p:
		saved_equipment_accessory = p.equipment_accessory

func restore_player_state():
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		return
	if saved_hp >= 0:
		p.hp = saved_hp
		p.max_hp = saved_max_hp
		p.stamina = saved_stamina
		p.max_stamina = saved_max_stamina
	if saved_hotkey_slots.size() > 0 and "hotkey_slots" in p:
		p.hotkey_slots = saved_hotkey_slots.duplicate()
	if saved_bag.size() > 0 and "bag" in p:
		p.bag = saved_bag.duplicate()
	if saved_gold >= 0 and "gold" in p:
		p.gold = saved_gold
	if "equipment_chest" in p:
		p.equipment_chest = saved_equipment_chest
	if "equipment_torso" in p:
		p.equipment_torso = saved_equipment_torso
	if "equipment_accessory" in p:
		p.equipment_accessory = saved_equipment_accessory
	if saved_equipment_chest or saved_equipment_torso or saved_equipment_accessory or saved_hotkey_slots.size() > 0 or saved_bag.size() > 0:
		p._recalc_equipment_stats()
		p._update_equipment_hud()
	p._update_bag_hud()
	p._update_hotkey_hud()

func on_floor_cleared():
	floor_cleared.emit(current_floor)
	print("Floor ", current_floor, " cleared")
	print("=== LEVEL COMPLETE ===")
	call_deferred("go_to_rest_area")

func go_to_rest_area():
	save_player_state()
	get_tree().change_scene_to_file(REST_SCENE)

func advance_from_campfire():
	current_floor += 1
	floor_changed.emit(current_floor)
	_roll_condition()
	save_player_state()
	get_tree().change_scene_to_file(COMBAT_SCENE)

# Condition selection ------------------------------
func _roll_condition():
	current_condition_type = 2  # Force Cleanse for testing

func get_condition_script() -> Script:
	return condition_scripts.get(current_condition_type, AmbushCondition)
