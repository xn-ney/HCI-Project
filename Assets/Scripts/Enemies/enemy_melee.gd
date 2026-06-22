extends CharacterBody3D

signal died

# HP ------------------------------------------------
var hp = 100.0
const MAX_HP = 100.0
const EXECUTE_THRESHOLD = 0.3

# Detection / Aggro --------------------------------
const DETECTION_RANGE = 15.0
const AGGRO_LOSS_RANGE = 18.0
const MOVE_SPEED = 3.0

# Melee Combat --------------------------------------
const MELEE_DAMAGE = 20.0
const MELEE_KNOCKBACK = 30.0
const MELEE_RANGE = 3.0
const ATTACK_COOLDOWN = 2.5

# Stun (3rd hit) ------------------------------------
const STUN_DURATION = 0.5

# Prepare State -------------------------------------
const PREPARE_DURATION = 4.0
const PREPARE_PAUSE = 0.8
const PREPARE_WALK_MIN = 0.5
const PREPARE_WALK_MAX = 1.5

# Flee ----------------------------------------------
const FLEE_DURATION = 2.0

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

# References ----------------------------------------
var player = null

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel

# State machine -------------------------------------
enum State { IDLE, PREPARE, ATTACK }
enum AttackPhase { CHASE, FLEE }
enum PreparePhase { WALK, PAUSE }

var state = State.IDLE
var attack_phase = AttackPhase.CHASE
var prepare_phase = PreparePhase.WALK
var state_timer = 0.0
var prepare_move_timer = 0.0
var prepare_pause_timer = 0.0
var idle_phase = PreparePhase.WALK
var idle_walk_timer: float
var idle_pause_timer: float
var wander_dir = Vector3.ZERO
var hit_count = 0


func _ready():
	player = get_tree().get_first_node_in_group("player")
	_idle_pick_wander()


func _physics_process(delta: float) -> void:
	if player == null:
		return

	if branded_timer > 0:
		branded_timer -= delta
		if branded_timer <= 0:
			remove_from_group("branded")

	var distance = global_position.distance_to(player.global_position)

	# Lose aggro if too far -------------------------
	if distance > AGGRO_LOSS_RANGE:
		if state != State.IDLE:
			state = State.IDLE
			_idle_pick_wander()

	# State machine ---------------------------------
	match state:
		State.IDLE:
			if distance <= DETECTION_RANGE:
				state = State.PREPARE
				state_timer = PREPARE_DURATION
				_prepare_enter()
			else:
				match idle_phase:
					PreparePhase.WALK:
						velocity.x = wander_dir.x * IDLE_MOVE_SPEED
						velocity.z = wander_dir.z * IDLE_MOVE_SPEED
						idle_walk_timer -= delta
						if idle_walk_timer <= 0:
							idle_phase = PreparePhase.PAUSE
							idle_pause_timer = IDLE_PAUSE
							velocity.x = 0.0
							velocity.z = 0.0
					PreparePhase.PAUSE:
						idle_pause_timer -= delta
						if idle_pause_timer <= 0:
							_idle_pick_wander()

		State.PREPARE:
			var move_speed = MOVE_SPEED * speed_multiplier
			if is_in_group("branded"):
				move_speed *= 0.85

			match prepare_phase:
				PreparePhase.WALK:
					velocity.x = wander_dir.x * move_speed
					velocity.z = wander_dir.z * move_speed
					prepare_move_timer -= delta
					if prepare_move_timer <= 0:
						prepare_phase = PreparePhase.PAUSE
						prepare_pause_timer = PREPARE_PAUSE
						velocity.x = 0.0
						velocity.z = 0.0

				PreparePhase.PAUSE:
					prepare_pause_timer -= delta
					if prepare_pause_timer <= 0:
						wander_dir = _pick_wander_dir(distance)
						prepare_move_timer = randf_range(PREPARE_WALK_MIN, PREPARE_WALK_MAX)
						prepare_phase = PreparePhase.WALK

			state_timer -= delta
			if state_timer <= 0:
				state = State.ATTACK
				attack_phase = AttackPhase.CHASE

		State.ATTACK:
			var move_speed = MOVE_SPEED * speed_multiplier
			if is_in_group("branded"):
				move_speed *= 0.85

			if attack_phase == AttackPhase.CHASE:
				nav_agent.target_position = player.global_position
				var next_pos = nav_agent.get_next_path_position()
				var move_dir = (next_pos - global_position).normalized()
				velocity.x = move_dir.x * move_speed
				velocity.z = move_dir.z * move_speed
				if distance <= MELEE_RANGE:
					_melee_attack()
					attack_phase = AttackPhase.FLEE
					state_timer = FLEE_DURATION

			elif attack_phase == AttackPhase.FLEE:
				var away = (global_position - player.global_position).normalized()
				away.y = 0.0
				velocity.x = away.x * move_speed
				velocity.z = away.z * move_speed
				state_timer -= delta
				if state_timer <= 0:
					if distance <= DETECTION_RANGE:
						state = State.PREPARE
						state_timer = PREPARE_DURATION
						_prepare_enter()
					else:
						state = State.IDLE
						_idle_pick_wander()

	# Status label ----------------------------------
	if speed_multiplier == 0.0:
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

	_separate_from_others()

	velocity += get_gravity() * delta * 3.0
	move_and_slide()


func _pick_wander_dir(distance: float) -> Vector3:
	var angle = randf_range(0, TAU)
	var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	var edge = DETECTION_RANGE * 0.7
	if distance > edge:
		var bias = (distance - edge) / (DETECTION_RANGE - edge)
		var to_player = (player.global_position - global_position).normalized()
		to_player.y = 0.0
		dir = dir.lerp(to_player, bias).normalized()
	return dir


func _idle_pick_wander() -> void:
	var angle = randf_range(0, TAU)
	wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	idle_walk_timer = randf_range(IDLE_WALK_MIN, IDLE_WALK_MAX)
	idle_phase = PreparePhase.WALK


func _prepare_enter() -> void:
	prepare_phase = PreparePhase.WALK
	wander_dir = _pick_wander_dir(global_position.distance_to(player.global_position))
	prepare_move_timer = randf_range(PREPARE_WALK_MIN, PREPARE_WALK_MAX)


func _melee_attack() -> void:
	hit_count += 1
	player.take_damage(MELEE_DAMAGE)

	if hit_count % 3 == 0:
		var push_dir = (player.global_position - global_position).normalized()
		push_dir.y = 0.0
		player.knockback_velocity = push_dir * MELEE_KNOCKBACK
		player.stun_timer = STUN_DURATION


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


func take_damage(amount: float):
	if is_in_group("branded"):
		amount *= 0.7
	hp -= amount
	hp = clamp(hp, 0, MAX_HP)
	hp_label.text = str(round(hp))
	if hp <= 0:
		died.emit()
		queue_free()
