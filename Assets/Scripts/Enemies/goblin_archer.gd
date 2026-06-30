extends CharacterBody3D

signal died

const PROJECTILE_SCENE = preload("res://Scenes/projectile_fireball.tscn")

# HP ------------------------------------------------
var hp = 80.0
const MAX_HP = 80.0
const EXECUTE_THRESHOLD = 0.3

# Detection / Aggro --------------------------------
const DETECTION_RANGE = 18.0
const AGGRO_LOSS_RANGE = 20.0
const MOVE_SPEED = 2.5

# Ranged Combat ------------------------------------
const ARROW_DAMAGE = 15.0
const ARROW_RANGE = 15.0
const ARROW_SPEED = 15.0

# Interrupt ------------------------------------------
const INTERRUPT_DURATION = 1.5

# Attack State (windup + shoot) ---------------------
const ATTACK_CAST_TIME = 1.5

# Reposition ----------------------------------------
const REPOSITION_DURATION = 2.0

# Flee ----------------------------------------------
const FLEE_DURATION = 2.0
const FLEE_TRIGGER_RANGE = 6.0

# Idle Wander ----------------------------------------
const IDLE_WALK_MIN = 1.0
const IDLE_WALK_MAX = 3.0
const IDLE_PAUSE = 1.5
const IDLE_MOVE_SPEED = 1.5

# Knockback -----------------------------------------
const KNOCKBACK_FRICTION = 8.0
const SEPARATION_RADIUS = 1.5
const SEPARATION_FORCE = 2.0

var knockback_velocity = Vector3.ZERO
var impulse = Vector3.ZERO
var branded_timer = 0.0
var speed_multiplier = 1.0
var stunned_timer = 0.0
var disengage_timer = 0.0

# References ----------------------------------------
var player = null

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel
@onready var projectile_spawn = $ProjectileSpawn

# State machine -------------------------------------
enum State { IDLE, ATTACK, REPOSITION, FLEE, INTERRUPTED }
enum WanderPhase { WALK, PAUSE }

var state = State.IDLE
var state_timer = 0.0
var wander_phase = WanderPhase.WALK
var wander_walk_timer: float
var wander_pause_timer: float
var wander_dir = Vector3.ZERO
var flee_mode = false
var strafe_dir = 1.0
var hit_count = 0


func _ready():
	player = get_tree().get_first_node_in_group("player")
	_idle_pick_wander()


func _physics_process(delta: float) -> void:
	if player and player.is_invisible:
		return
	if player == null:
		return

	if branded_timer > 0:
		branded_timer -= delta
		if branded_timer <= 0:
			remove_from_group("branded")

	if stunned_timer > 0:
		stunned_timer -= delta

	if disengage_timer > 0:
		disengage_timer -= delta
		if disengage_timer <= 0:
			if state == State.ATTACK:
				state = State.REPOSITION
				state_timer = REPOSITION_DURATION
				var r = randi() % 3
				if r == 0: strafe_dir = 0.0
				elif r == 1: strafe_dir = 1.0
				else: strafe_dir = -1.0
			elif state == State.REPOSITION:
				state_timer = REPOSITION_DURATION
				var r = randi() % 3
				if r == 0: strafe_dir = 0.0
				elif r == 1: strafe_dir = 1.0
				else: strafe_dir = -1.0

	var distance = global_position.distance_to(player.global_position)

	if distance > AGGRO_LOSS_RANGE:
		if state != State.IDLE:
			state = State.IDLE
			_idle_pick_wander()

	var can_act = speed_multiplier > 0 and knockback_velocity.length() <= 0.1 and stunned_timer <= 0

	if can_act:
		match state:
			State.IDLE:
				if distance <= DETECTION_RANGE:
					state = State.ATTACK
					state_timer = ATTACK_CAST_TIME
					flee_mode = false
				else:
					match wander_phase:
						WanderPhase.WALK:
							velocity.x = wander_dir.x * IDLE_MOVE_SPEED
							velocity.z = wander_dir.z * IDLE_MOVE_SPEED
							wander_walk_timer -= delta
							if wander_walk_timer <= 0:
								wander_phase = WanderPhase.PAUSE
								wander_pause_timer = IDLE_PAUSE
								velocity.x = 0.0
								velocity.z = 0.0
						WanderPhase.PAUSE:
							wander_pause_timer -= delta
							if wander_pause_timer <= 0:
								_idle_pick_wander()

			State.ATTACK:
				velocity.x = 0.0
				velocity.z = 0.0
				if distance < FLEE_TRIGGER_RANGE:
					flee_mode = true
				state_timer -= delta
				if state_timer <= 0:
					_ranged_attack()
					if flee_mode:
						flee_mode = false
						state = State.FLEE
						state_timer = FLEE_DURATION
					else:
						state = State.REPOSITION
						state_timer = REPOSITION_DURATION
						var r = randi() % 3
						if r == 0: strafe_dir = 0.0
						elif r == 1: strafe_dir = 1.0
						else: strafe_dir = -1.0

			State.REPOSITION:
				var move_speed = MOVE_SPEED * speed_multiplier
				if is_in_group("branded"):
					move_speed *= 0.85
				if distance <= 5.0:
					state = State.FLEE
					state_timer = FLEE_DURATION
				elif distance <= 10.0:
					var away = (global_position - player.global_position).normalized()
					away.y = 0.0
					velocity.x = away.x * move_speed
					velocity.z = away.z * move_speed
				elif distance <= ARROW_RANGE:
					if strafe_dir == 0.0:
						var away = (global_position - player.global_position).normalized()
						away.y = 0.0
						velocity.x = away.x * move_speed
						velocity.z = away.z * move_speed
					else:
						var to_player = (player.global_position - global_position).normalized()
						to_player.y = 0.0
						var perp = Vector3(-to_player.z * strafe_dir, 0, to_player.x * strafe_dir)
						velocity.x = perp.x * move_speed
						velocity.z = perp.z * move_speed
				elif distance <= 17.0:
					var to_player = (player.global_position - global_position).normalized()
					to_player.y = 0.0
					velocity.x = to_player.x * move_speed
					velocity.z = to_player.z * move_speed
				else:
					var to_player = (player.global_position - global_position).normalized()
					to_player.y = 0.0
					velocity.x = to_player.x * move_speed * 0.5
					velocity.z = to_player.z * move_speed * 0.5
				state_timer -= delta
				if state_timer <= 0:
					if distance <= ARROW_RANGE:
						state = State.ATTACK
						state_timer = ATTACK_CAST_TIME
						flee_mode = false
					else:
						state_timer = REPOSITION_DURATION

			State.FLEE:
				var move_speed = MOVE_SPEED * speed_multiplier * 2
				if is_in_group("branded"):
					move_speed *= 0.85
				var away = (global_position - player.global_position).normalized()
				away.y = 0.0
				velocity.x = away.x * move_speed
				velocity.z = away.z * move_speed
				state_timer -= delta
				if state_timer <= 0:
					if distance >= 6.0:
						flee_mode = false
						if distance <= DETECTION_RANGE:
							state = State.ATTACK
							state_timer = ATTACK_CAST_TIME
						else:
							state = State.IDLE
							_idle_pick_wander()
					else:
						state_timer = FLEE_DURATION

			State.INTERRUPTED:
				velocity.x = 0.0
				velocity.z = 0.0
				state_timer -= delta
				if state_timer <= 0:
					if distance <= DETECTION_RANGE:
						state = State.ATTACK
						state_timer = ATTACK_CAST_TIME
						flee_mode = false
					else:
						state = State.IDLE
						_idle_pick_wander()

	if state == State.INTERRUPTED:
		hp_label.text = "Interrupted"
	elif speed_multiplier == 0.0:
		hp_label.text = "Petrified"
	else:
		hp_label.text = str(round(hp))
		if is_in_group("branded"):
			hp_label.text += "\nBranded"
		if hp / MAX_HP <= EXECUTE_THRESHOLD:
			hp_label.text += "\nExecute"

	if impulse.length() > 0:
		velocity += impulse
		impulse = Vector3.ZERO

	if knockback_velocity.length() > 0.1:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	if speed_multiplier <= 0 and knockback_velocity.length() <= 0.1:
		velocity.x = 0.0
		velocity.z = 0.0

	_separate_from_others()

	velocity += get_gravity() * delta * 3.0
	move_and_slide()


func _idle_pick_wander() -> void:
	var angle = randf_range(0, TAU)
	wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	wander_walk_timer = randf_range(IDLE_WALK_MIN, IDLE_WALK_MAX)
	wander_phase = WanderPhase.WALK


func _ranged_attack() -> void:
	var p = PROJECTILE_SCENE.instantiate()
	p.damage = ARROW_DAMAGE
	get_tree().root.add_child(p)
	var dir = (player.global_position - projectile_spawn.global_position).normalized()
	p.global_position = projectile_spawn.global_position + dir * 1.0
	p.launch(dir)


func _separate_from_others() -> void:
	var push = Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self:
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < SEPARATION_RADIUS and dist > 0.01:
			var away = (global_position - enemy.global_position).normalized()
			push += away * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	if push != Vector3.ZERO:
		velocity += push * SEPARATION_FORCE


func knocked_airborne(duration: float, knockup_force: float) -> void:
	speed_multiplier = 0.0
	stunned_timer = duration
	knockback_velocity = Vector3.ZERO
	impulse = Vector3.UP * knockup_force

func restore_from_airborne(orig_speed: float) -> void:
	speed_multiplier = orig_speed
	stunned_timer = 0.0

func _become_corpse():
	remove_from_group("enemies")
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	hp_label.queue_free()
	$NameLabel.queue_free()

func take_damage(amount: float):
	if state == State.ATTACK and hit_count % 3 == 2:
		state = State.INTERRUPTED
		state_timer = INTERRUPT_DURATION
		velocity = Vector3.ZERO
		hit_count += 1

	if is_in_group("branded"):
		amount *= 0.7
	hp -= amount
	hp = clamp(hp, 0, MAX_HP)
	hp_label.text = str(round(hp))
	if hp <= 0:
		died.emit()
		_become_corpse()
