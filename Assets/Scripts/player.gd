extends CharacterBody3D

# Camera ------------------------------------------
var sensitivity = 0.003
@onready var camera = $Camera3D
@onready var stamina_label = $HUD/StaminaLabel
@onready var class_label = $HUD/ClassLabel

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

# I-Frames ----------------------------------------
const IFRAME_DURATION = 0.4
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
func _process(_delta):
	if Input.is_action_just_pressed("terminate"):
		get_tree().quit()
	if Input.is_action_just_pressed("switch"):
		_cycle_class()
	
	var joy_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	
	if abs(joy_x) > 0.1 or abs(joy_y) > 0.1:
		rotate_y(-joy_x * sensitivity * 12)
		camera.rotate_x(-joy_y * sensitivity * 12)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(70))


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
				print("Exhausted state ended — stamina: ", stamina)
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
	hp_label.text = "HP: " + str(round(hp)) + "/" + str(max_hp)

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
	iframe_timer = IFRAME_DURATION
	var dmg_mult = 1.0
	if active_class.has_method("get_damage_taken_mult"):
		dmg_mult = active_class.get_damage_taken_mult()
	hp -= amount * dmg_mult
	hp = clamp(hp, 0, max_hp)
	print("Player HP: ", hp)
	active_class.on_take_damage(amount)
	if hp <= 0:
		print("Player died!")
