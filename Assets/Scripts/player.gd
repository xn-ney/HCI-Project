extends CharacterBody3D

# Camera ------------------------------------------
var sensitivity = 0.003
@onready var camera = $Camera3D
@onready var stamina_label = $HUD/StaminaLabel
@onready var class_label = $HUD/ClassLabel
@onready var hud = $HUD
@onready var player_mesh = $MeshInstance3D

# Audio ----(disabled)------------------------------
#@onready var walk_footstep = $WalkSFX
#@onready var sprint_footstep = $SprintSFX
#@onready var dash_sfx = $DashSFX

# Footstep SFX --(disabled)-------------------------
#var footstep_timer = 0.0
#const WALK_STEP_INTERVAL = 0
#const SPRINT_STEP_INTERVAL = 0

# Weapon Holder -----------------------------------
@onready var weapon_holder = $Camera3D/RWeaponHolder
@onready var fist_holder = $Camera3D/LWeaponHolder

# Class System ------------------------------------
@onready var active_class: Node = $WraithStats

# Melee Attack Stats ------------------------------
var melee_attack_speed = 0.5
var melee_timer = 0.0
var has_hit_this_swing = false
const HIT_TIMING = 0.425

# Melee test animation ----------------------------
const FIST_REST_POS = Vector3(0, 0, 0)
const FIST_WINDUP_POS = Vector3(0, 0.1, 0.2)
const FIST_LUNGE_POS = Vector3(0, -0.05, -0.2)
var right_rest_pos = Vector3.ZERO

# Dash to sprint ----------------------------------
var is_dashing = false
var is_sprinting = false
var dash_hold_time = 0.0
var dash_timer = 0.0
var dash_cooldown = 0.0
var dash_direction = Vector3.ZERO
var sprint_boost_active = false

const DASH_SPEED = 20.0
var sprint_speed = 7.8
const DASH_DURATION = 0.2
const DASH_HOLD_THRESHOLD = 0.2
const DASH_COOLDOWN_TIME = 0.3

# HP ----------------------------------------------
var hp = 100.0
var max_hp = 100.0
@onready var hp_label = $HUD/HPLabel

# Inventory ----------------------------------------
var bag: Array = [null, null, null, null, null, null, null, null, null, null, null, null]
var hotkey_slots: Array = [null, null, null, null]
var hotkey_labels: Array = []
var bag_slot_labels: Array = []
var gold: int = 0
var gold_label: Label = null
var inv_ui: Control = null

# Equipment Slots ----------------------------------
var equipment_chest: Resource = null
var equipment_torso: Resource = null
var equipment_accessory: Resource = null
var hp_bonus: int = 0
var stamina_bonus: int = 0
var defense_stat: int = 0
var equipment_effects: Dictionary = {}
@onready var chest_slot_label: Label = null
@onready var torso_slot_label: Label = null
@onready var accessory_slot_label: Label = null

var buff_damage_mult: float = 1.0
var buff_lifesteal_pct: float = 0.0

# Shield -------------------------------------------
var shield_hits: int = 0

# Regen over time ----------------------------------
var regen_rate: float = 0.0
var regen_timer: float = 0.0

# Invisibility -------------------------------------
var is_invisible: bool = false
var invis_timer: float = 0.0

# I-Frames ----------------------------------------
const IFRAME_DURATION = 1.5
var iframe_timer = 0.0

# Stun -------------------------------------------
var stun_timer = 0.0

# Knockback ----------------------------------------
var knockback_velocity = Vector3.ZERO
const KNOCKBACK_FRICTION = 8.0
var knock_up = 0.0

# Stamina -----------------------------------------
var stamina = 100.0
var max_stamina = 100.0
const WALK_STAMINA_RECOVERY = 8.0
const IDLE_STAMINA_RECOVERY = 30.0

var exhausted_timer = 0.0
const EXHAUSTED_DELAY = 1.5
const EXHAUSTED_RECOVERY = 8.0
const EXHAUSTED_THRESHOLD = 60.0
var exhausted_speed = 3.5
var is_exhausted = false

# Walk and Jump height/speed ----------------------
var jump_count = 0

var speed = 5.0
const JUMP_VELOCITY = 9.5
const DJUMP_VELOCITY = 6.8

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	right_rest_pos = weapon_holder.position
	_apply_class_stats()
	_build_inventory_hud()
	GameManager.restore_player_state()


func _cycle_class() -> void:
	var classes: Array[Node] = []
	for child in get_children():
		if child.is_in_group("class_stats"):
			classes.append(child)
	if classes.size() < 2:
		return
	var idx = classes.find(active_class)
	if idx < 0:
		idx = 0
	var next_idx = (idx + 1) % classes.size()
	active_class = classes[next_idx]
	_apply_class_stats()
	is_dashing = false
	is_sprinting = false
	is_exhausted = false
	class_label.text = "Class: " + active_class.name.replace("Stats", "")


func _apply_class_stats():
	hp = active_class.CLASS_HP
	max_hp = active_class.CLASS_MAX_HP
	stamina = active_class.CLASS_STAMINA
	max_stamina = active_class.CLASS_MAX_STAMINA
	speed = active_class.CLASS_SPEED
	sprint_speed = active_class.CLASS_SPRINT_SPEED
	exhausted_speed = active_class.CLASS_EXHAUSTED_SPEED
	melee_attack_speed = active_class.MELEE_ATTACK_SPEED
	class_label.text = "Class: " + active_class.name.replace("Stats", "")
	_recalc_equipment_stats()
	_apply_weapons()


func _apply_weapons():
	for child in weapon_holder.get_children():
		child.visible = child.name == active_class.RIGHT_WEAPON
	for child in fist_holder.get_children():
		child.visible = child.name == active_class.LEFT_WEAPON


# Mouse Look --------------------------------------
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(85))

# Terminate Input ---------------------------------
func _process(delta):
	if GameManager.ui_open:
		if Input.is_action_just_pressed("inventory"):
			_toggle_inventory()
		_process_effects(delta)
		return
	if Input.is_action_just_pressed("terminate"):
		get_tree().quit()
	if Input.is_action_just_pressed("switch"):
		_cycle_class()

	if Input.is_action_just_pressed("item_slot_1"):
		use_item(0)
	if Input.is_action_just_pressed("item_slot_2"):
		use_item(1)
	if Input.is_action_just_pressed("item_slot_3"):
		use_item(2)
	if Input.is_action_just_pressed("item_slot_4"):
		use_item(3)
	if Input.is_action_just_pressed("inventory"):
		_toggle_inventory()

	var joy_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	
	if abs(joy_x) > 0.1 or abs(joy_y) > 0.1:
		rotate_y(-joy_x * sensitivity * 12)
		camera.rotate_x(-joy_y * sensitivity * 12)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(70))

	_process_effects(delta)


func _process_effects(delta: float):
	if regen_timer > 0:
		regen_timer -= delta
		hp = min(hp + regen_rate * delta, max_hp)
		if regen_timer <= 0:
			regen_rate = 0.0

	if invis_timer > 0:
		invis_timer -= delta
		player_mesh.visible = false
		if invis_timer <= 0:
			is_invisible = false
			player_mesh.visible = true

	if gold_label:
		gold_label.text = "Gold: " + str(gold)


# MOVEMENT ----------------------------------------
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta * 3.0

# Stun --------------------------------------------
	if stun_timer > 0:
		stun_timer -= delta
		if melee_timer > 0:
			melee_timer = max(melee_timer - delta, 0.0)
			if not has_hit_this_swing and melee_timer <= melee_attack_speed * (1.0 - HIT_TIMING):
				has_hit_this_swing = true
				active_class.melee_attack()
				_melee_hit_animation()
				active_class.melee_follow_through()
		active_class.process_class(delta)
		_apply_knockback(delta)
		move_and_slide()
		return

# Jump --------------------------------------------
	if is_on_floor():
		jump_count = 0
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			jump_count = 1
		elif jump_count < 2:
			velocity.y = DJUMP_VELOCITY
			jump_count = 2

# Dash and Sprint calculations --------------------
	if dash_cooldown > 0:
		dash_cooldown -= delta
	
	var dash_cost = active_class.get_dash_stamina_cost()
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0 and not is_exhausted and stamina >= dash_cost:
		is_dashing = true
		is_sprinting = false
		sprint_boost_active = false
		dash_hold_time = 0.0
		dash_timer = DASH_DURATION
		if active_class.has_method("get_dash_duration"):
			var custom = active_class.get_dash_duration()
			if custom > 0:
				dash_timer = custom
		stamina -= dash_cost
		# dash_sfx.play()
		set_collision_mask_value(4, false)
		var input_dir_dash := Input.get_vector("left", "right", "up", "down")
		var raw_dir = (transform.basis * Vector3(input_dir_dash.x, 0, input_dir_dash.y)).normalized()
		if raw_dir != Vector3.ZERO:
			dash_direction = raw_dir
		else:
			dash_direction = -global_transform.basis.z
		velocity.x = 0
		velocity.z = 0

	if is_dashing and not is_sprinting:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			set_collision_mask_value(4, true)

	var can_sprint = true
	if active_class.has_method("can_sprint"):
		can_sprint = active_class.can_sprint()
	if Input.is_action_pressed("dash") and not is_sprinting and not is_exhausted and can_sprint:
		dash_hold_time += delta
		if dash_hold_time >= DASH_HOLD_THRESHOLD:
			is_sprinting = true
			is_dashing = false
			set_collision_mask_value(4, true)
			dash_direction = -camera.global_transform.basis.z
	
	if is_sprinting and not Input.is_action_pressed("dash"):
		is_dashing = false
		is_sprinting = false
		sprint_boost_active = false
		dash_cooldown = DASH_COOLDOWN_TIME
		dash_direction = Vector3.ZERO

# Basic movement ----------------------------------
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Stamina system ------------------------------
	if is_exhausted:
		if exhausted_timer > 0:
			exhausted_timer -= delta
		else:
			stamina += EXHAUSTED_RECOVERY * delta
			if stamina >= EXHAUSTED_THRESHOLD:
				is_exhausted = false
				print("Exhausted state ended ΓÇö stamina: ", stamina)
	elif is_sprinting:
		stamina -= active_class.get_sprint_stamina_drain() * delta
		if stamina <= 0:
			stamina = 0
			is_exhausted = true
			exhausted_timer = EXHAUSTED_DELAY
			is_sprinting = false
			sprint_boost_active = false
			dash_direction = Vector3.ZERO
			print("Entered exhausted state")
	elif direction != Vector3.ZERO:
		stamina += WALK_STAMINA_RECOVERY * delta
	else:
		stamina += IDLE_STAMINA_RECOVERY * delta
	stamina = clamp(stamina, 0, max_stamina)
	stamina_label.text = "Stamina: " + str(round(stamina)) + "/" + str(max_stamina)

	# Health HUD ---------------------------------
	hp_label.text = "HP: " + str(round(hp)) + "/" + str(max_hp) + "  DEF: " + str(defense_stat)

	if iframe_timer > 0:
		iframe_timer -= delta

	# Movement selection --------------------------
	if is_dashing:
		if not is_on_floor():
			if dash_hold_time < delta * 2:
				velocity.x = dash_direction.x * DASH_SPEED
				velocity.z = dash_direction.z * DASH_SPEED
			else:
				velocity.x = move_toward(velocity.x, 0, DASH_SPEED * 1.5 * delta)
				velocity.z = move_toward(velocity.z, 0, DASH_SPEED * 1.5 * delta)
		else:
			velocity.x = dash_direction.x * DASH_SPEED
			velocity.z = dash_direction.z * DASH_SPEED
	elif is_sprinting:
		if not sprint_boost_active:
			if dash_hold_time >= DASH_HOLD_THRESHOLD:
				sprint_boost_active = true
		if sprint_boost_active:
			var sprint_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			if sprint_dir != Vector3.ZERO:
				dash_direction = sprint_dir
			else:
				dash_direction = -camera.global_transform.basis.z
			velocity.x = dash_direction.x * sprint_speed
			velocity.z = dash_direction.z * sprint_speed
	elif direction:
		var current_speed = exhausted_speed if is_exhausted else speed
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		var current_speed = exhausted_speed if is_exhausted else speed
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

# Melee timing ------------------------------------
	if melee_timer > 0:
		melee_timer = max(melee_timer - delta, 0.0)
		if not has_hit_this_swing and melee_timer <= melee_attack_speed * (1.0 - HIT_TIMING):
			has_hit_this_swing = true
			active_class.melee_attack()
			_melee_hit_animation()
			active_class.melee_follow_through()
	if not GameManager.ui_open:
		if Input.is_action_just_pressed("meleeATK") and melee_timer <= 0:
			melee_timer = melee_attack_speed
			has_hit_this_swing = false
			_melee_start_animation()
			active_class.melee_windup()

	# Ranged Input ------------------------------------
		if Input.is_action_pressed("rangedATK"):
			active_class.ranged_attack()

# Skill Input (Q) ---------------------------------
	if Input.is_action_just_pressed("skill"):
		active_class.skill()

# Ult Input (E) -----------------------------------
	if Input.is_action_just_pressed("ult"):
		active_class.ult()

# Process active abilities (may override velocity) -
	active_class.process_class(delta)

	_apply_knockback(delta)
	move_and_slide()


# Melee Animation ----------------------------------
func _melee_start_animation():
	var t = melee_attack_speed * HIT_TIMING
	var tw = create_tween()
	tw.tween_property(fist_holder, "position", FIST_WINDUP_POS, t * 0.3)
	tw.tween_property(fist_holder, "position", FIST_LUNGE_POS, t * 0.7)


func _melee_hit_animation():
	var dur = melee_attack_speed * (1.0 - HIT_TIMING)
	var tw = create_tween()
	tw.tween_property(fist_holder, "position", FIST_REST_POS, dur)


func ranged_animation(duration: float = 0.2):
	var tw = create_tween()
	tw.tween_property(weapon_holder, "position", FIST_LUNGE_POS, 0.1)
	tw.tween_property(weapon_holder, "position", right_rest_pos, max(duration - 0.1, 0.05))


# Knockback Processing ---------------------------
func _apply_knockback(delta: float):
	if knock_up > 0:
		velocity.y = knock_up
		knock_up = 0.0

	if knockback_velocity.length() > 0.1:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, KNOCKBACK_FRICTION * delta)


# DMG Taken ---------------------------------------
func take_damage(amount: float):
	if iframe_timer > 0:
		return
	if active_class.has_method("is_invincible") and active_class.is_invincible():
		if active_class.has_method("on_parry_success") and active_class.get("parry_window"):
			active_class.on_parry_success()
		return
	if shield_hits > 0:
		shield_hits -= 1
		print("Shield blocked hit, ", shield_hits, " remaining")
		return
	iframe_timer = IFRAME_DURATION
	var dmg_mult = 1.0
	if active_class.has_method("get_damage_taken_mult"):
		dmg_mult = active_class.get_damage_taken_mult()
	var reduced = max(amount * dmg_mult - defense_stat, 1)
	hp -= reduced
	hp = clamp(hp, 0, max_hp)
	print("Player HP: ", hp)
	active_class.on_take_damage(amount)
	if hp <= 0:
		if active_class and active_class.has_method("should_revive") and active_class.should_revive():
			hp = max_hp * 0.25
			print("Player revived!")
		else:
			print("Player died!")


# Inventory HUD ------------------------------------
func _build_inventory_hud():
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.offset_left = 0.0
	gold_label.offset_right = 226.0
	gold_label.offset_top = 150.0
	gold_label.offset_bottom = 174.0
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1, 0.8, 0.0))
	gold_label.text = "Gold: 0"
	$HUD.add_child(gold_label)

	var eq_container = Panel.new()
	eq_container.name = "EqContainer"
	eq_container.anchor_left = 0.15
	eq_container.anchor_right = 0.85
	eq_container.anchor_top = 0.82
	eq_container.anchor_bottom = 0.87
	eq_container.modulate = Color(1, 1, 1, 0.7)
	$HUD.add_child(eq_container)

	chest_slot_label = Label.new()
	chest_slot_label.name = "ChestLabel"
	chest_slot_label.anchor_left = 0.0
	chest_slot_label.anchor_right = 0.33
	chest_slot_label.anchor_top = 0.0
	chest_slot_label.anchor_bottom = 1.0
	chest_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chest_slot_label.add_theme_font_size_override("font_size", 13)
	chest_slot_label.add_theme_color_override("font_color", Color(1, 1, 1))
	chest_slot_label.mouse_filter = Control.MOUSE_FILTER_STOP
	chest_slot_label.gui_input.connect(_on_chest_label_click)
	eq_container.add_child(chest_slot_label)

	torso_slot_label = Label.new()
	torso_slot_label.name = "TorsoLabel"
	torso_slot_label.anchor_left = 0.33
	torso_slot_label.anchor_right = 0.66
	torso_slot_label.anchor_top = 0.0
	torso_slot_label.anchor_bottom = 1.0
	torso_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	torso_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	torso_slot_label.add_theme_font_size_override("font_size", 13)
	torso_slot_label.add_theme_color_override("font_color", Color(1, 1, 1))
	torso_slot_label.mouse_filter = Control.MOUSE_FILTER_STOP
	torso_slot_label.gui_input.connect(_on_torso_label_click)
	eq_container.add_child(torso_slot_label)

	accessory_slot_label = Label.new()
	accessory_slot_label.name = "AccessoryLabel"
	accessory_slot_label.anchor_left = 0.66
	accessory_slot_label.anchor_right = 1.0
	accessory_slot_label.anchor_top = 0.0
	accessory_slot_label.anchor_bottom = 1.0
	accessory_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	accessory_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	accessory_slot_label.add_theme_font_size_override("font_size", 13)
	accessory_slot_label.add_theme_color_override("font_color", Color(1, 1, 1))
	accessory_slot_label.mouse_filter = Control.MOUSE_FILTER_STOP
	accessory_slot_label.gui_input.connect(_on_accessory_label_click)
	eq_container.add_child(accessory_slot_label)

	var container = Panel.new()
	container.name = "InvContainer"
	container.anchor_left = 0.15
	container.anchor_right = 0.85
	container.anchor_top = 0.88
	container.anchor_bottom = 0.96
	container.modulate = Color(1, 1, 1, 0.7)
	$HUD.add_child(container)

	for i in range(4):
		var slot = Panel.new()
		slot.name = "Slot" + str(i)
		slot.anchor_left = i * 0.25
		slot.anchor_right = (i + 1) * 0.25 - 0.005
		slot.anchor_top = 0.0
		slot.anchor_bottom = 1.0
		slot.modulate = Color(1, 1, 1, 1.0)
		container.add_child(slot)

		var lbl = Label.new()
		lbl.name = "Label" + str(i)
		lbl.anchor_left = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_top = 0.0
		lbl.anchor_bottom = 1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		lbl.text = ""
		slot.add_child(lbl)
		hotkey_labels.append(lbl)

	_update_hotkey_hud()
	_update_equipment_hud()


func _update_hotkey_hud():
	for i in range(4):
		var lbl = hotkey_labels[i]
		if not lbl:
			continue
		var item = hotkey_slots[i] if i < hotkey_slots.size() else null
		if item:
			var clr = item.rarity.color if item.rarity else Color(1, 1, 1)
			lbl.add_theme_color_override("font_color", clr)
			var hotkey = str(i + 1) + ": " if i < 4 else ""
			var tag = ""
			if item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != "":
				tag = " [" + item.equipment_type.capitalize() + "]"
			lbl.text = hotkey + item.item_name + tag
		else:
			var hotkey = str(i + 1) + ": " if i < 4 else ""
			lbl.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
			lbl.text = hotkey + "Empty"


# Equipment System ----------------------------------
func equip_item(hotkey_slot: int):
	var item = hotkey_slots[hotkey_slot]
	if not item:
		return
	if not _can_use_item(item):
		return
	var eq_type = item.equipment_type
	var target_slot = null
	if eq_type == "chest":
		target_slot = "equipment_chest"
	elif eq_type == "torso":
		target_slot = "equipment_torso"
	elif eq_type == "accessory":
		target_slot = "equipment_accessory"
	else:
		return

	var equipped = get(target_slot)
	if equipped:
		hotkey_slots[hotkey_slot] = equipped
		set(target_slot, item)
	else:
		set(target_slot, item)
		hotkey_slots[hotkey_slot] = null

	_recalc_equipment_stats()
	_update_hotkey_hud()
	_update_equipment_hud()


func unequip_item(eq_slot: String):
	if get_tree().get_nodes_in_group("enemies").size() > 0:
		return
	var item = get(eq_slot)
	if not item:
		return
	var free_slot = -1
	for i in range(bag.size()):
		if bag[i] == null:
			free_slot = i
			break
	if free_slot < 0:
		return
	bag[free_slot] = item
	set(eq_slot, null)
	_recalc_equipment_stats()
	_update_hotkey_hud()
	_update_equipment_hud()
	if inv_ui and inv_ui.has_method("_update_ui"):
		inv_ui._update_ui()


func _recalc_equipment_stats():
	hp_bonus = 0
	stamina_bonus = 0
	defense_stat = 0
	for eq in [equipment_chest, equipment_torso, equipment_accessory]:
		if eq:
			hp_bonus += eq.hp_bonus
			stamina_bonus += eq.stamina_bonus
			defense_stat += eq.defense
	max_hp = active_class.CLASS_MAX_HP + hp_bonus
	max_stamina = active_class.CLASS_MAX_STAMINA + stamina_bonus
	hp = min(hp, max_hp)
	stamina = min(stamina, max_stamina)
	_recalc_equipment_effects()
	if active_class.has_method("_on_equipment_changed"):
		active_class._on_equipment_changed()


func _recalc_equipment_effects():
	equipment_effects.clear()
	for eq in [equipment_chest, equipment_torso, equipment_accessory]:
		if not eq:
			continue
		for key in ["dmg_bonus_pct", "move_speed_pct", "focus_gain_pct", "focused_duration_extend",
			"focused_speed_pct", "dash_stamina_reduction", "influence_gain_pct",
			"berserk_threshold_reduction", "influence_decay_reduction", "consumed_dmg_taken_reduction",
			"lifesteal_on_kill_pct", "mana_regen_pct", "branded_dmg_bonus_pct",
			"branded_duration_extend", "ult_charge_rate_pct", "skill_cooldown_reduction_pct"]:
			var val = eq.get(key)
			if val == null:
				val = 0.0
			if val != 0.0:
				equipment_effects[key] = equipment_effects.get(key, 0.0) + val


func _update_equipment_hud():
	var chest_name = "Chest: " + equipment_chest.item_name if equipment_chest else "Chest: Empty"
	var torso_name = "Torso: " + equipment_torso.item_name if equipment_torso else "Torso: Empty"
	var acc_name = "Acc: " + equipment_accessory.item_name if equipment_accessory else "Acc: Empty"
	if equipment_chest:
		chest_name += " [Click]"
	if equipment_torso:
		torso_name += " [Click]"
	if equipment_accessory:
		acc_name += " [Click]"
	if chest_slot_label:
		var clr = equipment_chest.rarity.color if equipment_chest else Color(0.5, 0.5, 0.5)
		chest_slot_label.add_theme_color_override("font_color", clr)
		chest_slot_label.text = chest_name
	if torso_slot_label:
		var clr = equipment_torso.rarity.color if equipment_torso else Color(0.5, 0.5, 0.5)
		torso_slot_label.add_theme_color_override("font_color", clr)
		torso_slot_label.text = torso_name
	if accessory_slot_label:
		var clr = equipment_accessory.rarity.color if equipment_accessory else Color(0.5, 0.5, 0.5)
		accessory_slot_label.add_theme_color_override("font_color", clr)
		accessory_slot_label.text = acc_name


# Add item to bag (first empty slot) ----------------
func add_item(item: Resource) -> bool:
	for i in range(bag.size()):
		if bag[i] == null:
			bag[i] = item
			_update_bag_hud()
			return true
	return false


# Use item from hotkey slot -------------------------
func use_item(slot: int):
	if slot < 0 or slot >= hotkey_slots.size():
		return
	var item = hotkey_slots[slot]
	if not item:
		return
	if item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != "":
		equip_item(slot)
		return
	if not _can_use_item(item):
		return
	_apply_item_effect(item)
	hotkey_slots[slot] = null
	_update_hotkey_hud()


func _can_use_item(item: Resource) -> bool:
	if item.class_restriction != "":
		var current_class = active_class.name.replace("Stats", "").to_lower()
		var restrict = item.class_restriction.to_lower()
		if current_class != restrict:
			var display = restrict.capitalize()
			print("Only ", display, " can use ", item.item_name)
			return false
	return true


# Item effect application ---------------------------
func _apply_item_effect(item: Resource):
	var tier = item.rarity.sort_order if item.rarity else 0
	var type = item.item_type

	match type:
		"potion":
			_apply_potion(item, tier)
		"class_potion":
			_apply_class_potion(item, tier)
		"combat_tool":
			_apply_combat_tool(item, tier)


# Bag / Hotkey Transfer ------------------------------
func _update_bag_hud():
	if inv_ui and inv_ui.has_method("_update_ui"):
		inv_ui._update_ui()


func move_to_hotkey(bag_slot: int):
	if bag_slot < 0 or bag_slot >= bag.size():
		return
	var item = bag[bag_slot]
	if not item:
		return
	bag[bag_slot] = null
	var placed = false
	for i in range(hotkey_slots.size()):
		if hotkey_slots[i] == null:
			hotkey_slots[i] = item
			placed = true
			break
	if not placed:
		bag[bag_slot] = item
		return
	_update_hotkey_hud()
	_update_bag_hud()


func move_to_bag(hotkey_slot: int):
	if hotkey_slot < 0 or hotkey_slot >= hotkey_slots.size():
		return
	var item = hotkey_slots[hotkey_slot]
	if not item:
		return
	hotkey_slots[hotkey_slot] = null
	var placed = false
	for i in range(bag.size()):
		if bag[i] == null:
			bag[i] = item
			placed = true
			break
	if not placed:
		hotkey_slots[hotkey_slot] = item
		return
	_update_hotkey_hud()
	_update_bag_hud()


func equip_from_bag(bag_slot: int):
	if bag_slot < 0 or bag_slot >= bag.size():
		return
	var item = bag[bag_slot]
	if not item:
		return
	if not (item.has_method("get") and item.get("equipment_type") != null and item.equipment_type != ""):
		return
	if not _can_use_item(item):
		return
	var eq_type = item.equipment_type
	var target_slot = null
	if eq_type == "chest":
		target_slot = "equipment_chest"
	elif eq_type == "torso":
		target_slot = "equipment_torso"
	elif eq_type == "accessory":
		target_slot = "equipment_accessory"
	else:
		return
	var equipped = get(target_slot)
	if equipped:
		bag[bag_slot] = equipped
		set(target_slot, item)
	else:
		set(target_slot, item)
		bag[bag_slot] = null
	_recalc_equipment_stats()
	_update_hotkey_hud()
	_update_equipment_hud()
	_update_bag_hud()


func _stop_player_actions():
	is_dashing = false
	is_sprinting = false
	dash_timer = 0.0
	melee_timer = 0.0
	has_hit_this_swing = false


func _toggle_inventory():
	if GameManager.ui_open and not inv_ui:
		return
	if inv_ui:
		var parent = inv_ui.get_parent()
		if parent:
			parent.queue_free()
		else:
			inv_ui.queue_free()
		inv_ui = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GameManager.ui_open = false
		return
	_stop_player_actions()
	var layer = CanvasLayer.new()
	layer.layer = 1
	get_tree().current_scene.add_child(layer)
	var scene = load("res://Scenes/UI/inventory_ui.tscn")
	var instance = scene.instantiate()
	layer.add_child(instance)
	inv_ui = instance
	if instance.has_method("populate"):
		instance.populate(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameManager.ui_open = true


func _on_chest_label_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unequip_item("equipment_chest")


func _on_torso_label_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unequip_item("equipment_torso")


func _on_accessory_label_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unequip_item("equipment_accessory")


# Potion effects ------------------------------------
func _apply_potion(item: Resource, tier: int):
	match item.item_name:
		"Healing Potion":
			var amounts = [20, 50, 100]
			var heal = amounts[tier] if tier < amounts.size() else 50
			hp = min(hp + heal, max_hp)
			print("Healed for ", heal, " HP")
		"Stamina Potion":
			var amounts = [30, 60, max_stamina]
			var restore = amounts[tier] if tier < amounts.size() else 60
			stamina = min(stamina + restore, max_stamina)
			if is_exhausted and stamina >= EXHAUSTED_THRESHOLD:
				is_exhausted = false
			print("Restored ", restore, " stamina")
		"Shield Potion":
			var hits = [1, 2, 3]
			shield_hits += hits[tier] if tier < hits.size() else 1
			print("Gained ", shield_hits, " shield hits")
		"Regeneration Potion":
			var rates = [2.0, 5.0, 10.0]
			var durs = [8.0, 10.0, 12.0]
			regen_rate = rates[tier] if tier < rates.size() else 5.0
			regen_timer = durs[tier] if tier < durs.size() else 10.0
			print("Regen ", regen_rate, " HP/s for ", regen_timer, "s")


# Class potion effects ------------------------------
func _apply_class_potion(item: Resource, tier: int):
	match item.item_name:
		"Mana Potion":
			var amounts = [30, 60, active_class.MAX_MANA]
			var restore = amounts[tier] if tier < amounts.size() else 60
			active_class.mana = min(active_class.mana + restore, active_class.MAX_MANA)
			print("Restored ", restore, " mana")
		"Calming Potion":
			var pcts = [0.15, 0.30, 0.50]
			var reduction = pcts[tier] if tier < pcts.size() else 0.3
			active_class.influence = max(active_class.influence - active_class.MAX_INFLUENCE * reduction, 0.0)
			print("Reduced Influence by ", reduction * 100, "%")
		"Invisibility Potion":
			var durs = [3.0, 5.0, 8.0]
			is_invisible = true
			invis_timer = durs[tier] if tier < durs.size() else 5.0
			player_mesh.visible = false
			print("Invisible for ", invis_timer, "s")


# Combat tool effects -------------------------------
func _apply_combat_tool(item: Resource, tier: int):
	match item.item_name:
		"Bomb":
			var dmgs = [15, 30, 50]
			var pushes = [12.0, 18.0, 25.0]
			var _rads = [3.0, 4.0, 5.0]
			var dmg = dmgs[tier] if tier < dmgs.size() else 30
			var push = pushes[tier] if tier < pushes.size() else 18.0
			var rad = _rads[tier] if tier < _rads.size() else 4.0
			var explosion = preload("res://Scenes/Effects/bomb_explosion.tscn").instantiate()
			get_tree().root.add_child(explosion)
			explosion.global_position = global_position
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_instance_valid(explosion):
					explosion.queue_free())
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if global_position.distance_to(enemy.global_position) <= rad:
					enemy.take_damage(dmg)
					var push_dir = (enemy.global_position - global_position).normalized()
					push_dir.y = 0.0
					enemy.set("knockback_velocity", push_dir * push)
			print("Bomb: ", dmg, " AOE damage in ", rad, "m, push ", push)
		"Throwing Knife":
			var dmgs = [15, 25, 40]
			var dmg = dmgs[tier] if tier < dmgs.size() else 25
			var enemies = get_tree().get_nodes_in_group("enemies")
			var targets: Array[Node3D] = []
			for enemy in enemies:
				targets.append(enemy)
			targets.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
			var thrown = 0
			for t in targets:
				var knife = preload("res://Scenes/projectile_player.tscn").instantiate()
				knife.homing_target = t
				knife.damage = dmg
				get_tree().root.add_child(knife)
				knife.collision_mask = 8
				var dir = (t.global_position - global_position).normalized()
				dir.y = 0.0
				knife.global_position = global_position + dir * 1.0 + Vector3(0, 1.0, 0)
				knife.launch(dir)
				thrown += 1
				if thrown >= 2:
					break
			print("Throwing Knife: ", dmg, " dmg x", thrown)
		"Bear Trap":
			var stun_durs = [2.0, 3.0, 5.0]
			var stun = stun_durs[tier] if tier < stun_durs.size() else 3.0
			var trap = preload("res://Scenes/Effects/bear_trap.tscn").instantiate()
			get_tree().root.add_child(trap)
			trap.global_position = global_position
			get_tree().create_timer(15.0).timeout.connect(func():
				if is_instance_valid(trap):
					trap.queue_free())
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if global_position.distance_to(enemy.global_position) <= 2.0:
					enemy.set("stunned_timer", stun)
			print("Bear Trap: stunned enemies for ", stun, "s")
