extends CharacterBody3D

signal died

const PROJECTILE_SCENE = preload("res://Scenes/arrow_enemy.tscn")

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

# Reposition ----------------------------------------
const REPOSITION_DURATION = 2.0

# Flee ----------------------------------------------
const FLEE_STOP_RANGE = 13.0
const FLEE_TRIGGER_RANGE = 6.0

# Idle Wander ----------------------------------------
const IDLE_WALK_MIN = 1.0
const IDLE_WALK_MAX = 3.0
const IDLE_PAUSE = 1.5
const IDLE_MOVE_SPEED = 1.5

# Facing ---------------------------------------------
const FACE_OFFSET = deg_to_rad(180)

# Knockback -----------------------------------------
const KNOCKBACK_FRICTION = 8.0
const SEPARATION_RADIUS = 1.5
const SEPARATION_FORCE = 2.0

var knockback_velocity = Vector3.ZERO
var impulse = Vector3.ZERO
var branded_timer = 0.0
var speed_multiplier = 1.0
var stunned_timer = 0.0
var hurt_timer = 0.0
var disengage_timer = 0.0

# References ----------------------------------------
var player = null
var _original_player = null
var _target_override: Node3D = null
var _npc_check_done: bool = false

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel
@onready var projectile_spawn = $ProjectileSpawn
@onready var anim_player = $AnimationPlayer
@onready var skeleton = $Goblin_Archer/metarig/Skeleton3D
@onready var _head_idx = -1
@onready var _head_rest_inv = Quaternion.IDENTITY

# State machine -------------------------------------
enum State { IDLE, SURPRISED, ATTACK, REPOSITION, FLEE, INTERRUPTED, DEAD }
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
	_original_player = player
	_idle_pick_wander()
	_setup_animations()
	_head_idx = skeleton.find_bone("spine.005")
	if _head_idx >= 0:
		_head_rest_inv = skeleton.get_bone_rest(_head_idx).basis.get_rotation_quaternion().inverse()


func _physics_process(delta: float) -> void:
	if player == null:
		return

	if _target_override:
		if not is_instance_valid(_target_override) or EscortCondition.escort_target == null:
			_target_override = null
			_npc_check_done = true
			player = _original_player
		else:
			player = _target_override

	if branded_timer > 0:
		branded_timer -= delta
		if branded_timer <= 0:
			remove_from_group("branded")

	if stunned_timer > 0:
		stunned_timer -= delta

	if hurt_timer > 0:
		hurt_timer -= delta

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

	if state == State.DEAD:
		state_timer -= delta
		if state_timer <= 0:
			collision_layer = 0
			collision_mask = 0
			set_physics_process(false)

	var distance = global_position.distance_to(player.global_position)

	if distance > AGGRO_LOSS_RANGE and state != State.SURPRISED:
		if state != State.IDLE:
			state = State.IDLE
			_idle_pick_wander()

	var can_act = speed_multiplier > 0 and knockback_velocity.length() <= 0.1 and stunned_timer <= 0 and hurt_timer <= 0

	if can_act:
		match state:
			State.IDLE:
				if distance <= DETECTION_RANGE:
					state = State.SURPRISED
					state_timer = anim_player.get_animation("surprised").length * 0.4
					velocity = Vector3.ZERO
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

			State.SURPRISED:
				velocity.x = 0.0
				velocity.z = 0.0
				state_timer -= delta
				if state_timer <= 0:
					state = State.ATTACK
					state_timer = anim_player.get_animation("shoot").length
					flee_mode = false
					strafe_dir = 1.0

			State.ATTACK:
				velocity.x = 0.0
				velocity.z = 0.0
				if distance < FLEE_TRIGGER_RANGE:
					flee_mode = true
				state_timer -= delta
				var can_shoot = false
				var shoot_len = anim_player.get_animation("shoot").length
				if anim_player.current_animation == "shoot" and anim_player.current_animation_position >= shoot_len - 0.05:
					can_shoot = true
				elif state_timer <= 0:
					can_shoot = true
				if can_shoot:
					_ranged_attack()
					if flee_mode:
						flee_mode = false
						state = State.FLEE
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
						state_timer = anim_player.get_animation("shoot").length
						flee_mode = false
						strafe_dir = 1.0
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
				if distance >= FLEE_STOP_RANGE:
					flee_mode = false
					state = State.ATTACK
					state_timer = anim_player.get_animation("shoot").length
					strafe_dir = 1.0

			State.INTERRUPTED:
				velocity.x = 0.0
				velocity.z = 0.0
				state_timer -= delta
				if state_timer <= 0:
					if distance <= DETECTION_RANGE:
						state = State.SURPRISED
						state_timer = anim_player.get_animation("surprised").length * 0.4
						velocity = Vector3.ZERO
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
	_update_animation()

	const ROTATION_SPEED = 10.0
	var face_dir := Vector3.FORWARD
	if knockback_velocity.length() > 0.1:
		face_dir = (player.global_position - global_position).normalized()
	else:
		match state:
			State.ATTACK:
				var to_player = (player.global_position - global_position).normalized()
				to_player.y = 0.0
				face_dir = Vector3(-to_player.z, 0, to_player.x) * strafe_dir
				if face_dir.length() < 0.001:
					face_dir = Vector3.FORWARD
			State.FLEE:
				var v = Vector3(velocity.x, 0, velocity.z)
				if v.length() > 0.1:
					face_dir = v.normalized()
				else:
					face_dir = (player.global_position - global_position).normalized()
			State.SURPRISED, State.REPOSITION:
				face_dir = (player.global_position - global_position).normalized()
			State.IDLE:
				var v = Vector3(velocity.x, 0, velocity.z)
				if v.length() > 0.1:
					face_dir = v.normalized()
				else:
					face_dir = wander_dir
			State.INTERRUPTED:
				face_dir = (player.global_position - global_position).normalized()
	if face_dir:
		face_dir.y = 0.0
		if face_dir.length() < 0.001:
			face_dir = Vector3.FORWARD
		face_dir = face_dir.normalized()
		var target_basis = Basis.looking_at(face_dir, Vector3.UP)
		target_basis = target_basis * Basis(Vector3.UP, FACE_OFFSET)
		global_transform.basis = global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)

	if _head_idx >= 0 and face_dir != Vector3.ZERO:
		var head_global = skeleton.to_global(skeleton.get_bone_global_pose(_head_idx).origin)
		var head_to_player = player.global_position - head_global
		var pitch = -atan2(head_to_player.y, Vector2(head_to_player.x, head_to_player.z).length())
		pitch = clamp(pitch, deg_to_rad(-60), deg_to_rad(60))
		var head_rot = _head_rest_inv * Quaternion(Vector3.RIGHT, pitch)
		skeleton.set_bone_pose_rotation(_head_idx, head_rot)
	elif _head_idx >= 0:
		skeleton.set_bone_pose_rotation(_head_idx, Quaternion.IDENTITY)


	velocity += get_gravity() * delta * 3.0
	move_and_slide()


func _idle_pick_wander() -> void:
	if player and randf() < 0.4:
		var to_player = (player.global_position - global_position).normalized()
		to_player.y = 0.0
		wander_dir = to_player
	else:
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

func switch_to_npc_target(npc_node: Node3D):
	if _npc_check_done:
		return
	_npc_check_done = true
	_target_override = npc_node
	player = _target_override
	state = State.SURPRISED
	state_timer = anim_player.get_animation("surprised").length * 0.4
	velocity = Vector3.ZERO


var _is_corpse := false

func _clear_death_state():
	if state == State.DEAD:
		return
	state = State.DEAD
	state_timer = anim_player.get_animation("death").length
	velocity = Vector3.ZERO
	died.emit()
	await get_tree().create_timer(state_timer).timeout
	if not _is_corpse:
		_become_corpse()

func _become_corpse():
	if _is_corpse:
		return
	_is_corpse = true
	remove_from_group("enemies")
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	hp_label.queue_free()
	$NameLabel.queue_free()


func _setup_animations() -> void:
	var paths = {
		idle = "res://Assets/3D Models/Goblin Archer/Animations/Idle.fbx",
		death = "res://Assets/3D Models/Goblin Archer/Animations/On Death.fbx",
		shoot = "res://Assets/3D Models/Goblin Archer/Animations/Shooting Arrow.fbx",
		sprint = "res://Assets/3D Models/Goblin Archer/Animations/Sprint.fbx",
		walk_forward = "res://Assets/3D Models/Goblin Archer/Animations/Strafe Forward.fbx",
		walk_backward = "res://Assets/3D Models/Goblin Archer/Animations/Strafe Back.fbx",
		strafe_left = "res://Assets/3D Models/Goblin Archer/Animations/Strafe Left.fbx",
		strafe_right = "res://Assets/3D Models/Goblin Archer/Animations/Strafe Right.fbx",
		surprised = "res://Assets/3D Models/Goblin Archer/Animations/Spots Player.fbx",
		hurt = "res://Assets/3D Models/Goblin Archer/Animations/When hit.fbx",
	}
	var loop_anims = ["idle", "sprint", "walk_forward", "walk_backward", "strafe_left", "strafe_right"]
	var lib = AnimationLibrary.new()
	for anim_name in paths:
		var fbx = load(paths[anim_name]) as PackedScene
		if not fbx:
			continue
		var temp = fbx.instantiate()
		var src_player = temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src_player and src_player.has_animation("mixamo_com"):
			var anim = src_player.get_animation("mixamo_com").duplicate(true)
			anim.loop_mode = Animation.LOOP_LINEAR if anim_name in loop_anims else Animation.LOOP_NONE
			for i in range(anim.get_track_count() - 1, -1, -1):
				var p = str(anim.track_get_path(i))
				if p == "metarig":
					if anim_name == "death":
						anim.track_set_path(i, NodePath(".."))
					else:
						anim.remove_track(i)
				elif p.begins_with("metarig/Skeleton3D:"):
					anim.track_set_path(i, NodePath(":" + p.trim_prefix("metarig/Skeleton3D:")))
			lib.add_animation(anim_name, anim)
		temp.queue_free()
	anim_player.add_animation_library("", lib)
	anim_player.play("idle")


func _dir_anim(move_dir: Vector3) -> String:
	if move_dir.length() < 0.1:
		return "idle"
	var forward = -global_transform.basis.z.normalized()
	forward.y = 0.0
	var dot = move_dir.normalized().dot(forward)
	if dot >= 0.5:
		return "walk_forward"
	elif dot <= -0.5:
		return "walk_backward"
	elif strafe_dir > 0:
		return "strafe_right"
	else:
		return "strafe_left"


func _update_animation() -> void:
	var anim = "idle"
	if state == State.DEAD:
		anim = "death"
	elif speed_multiplier <= 0 or knockback_velocity.length() > 0.1 or stunned_timer > 0:
		anim = "idle"
	elif hurt_timer > 0:
		anim = "hurt"
	else:
		match state:
			State.SURPRISED:
				anim = "surprised"
			State.IDLE:
				match wander_phase:
					WanderPhase.WALK:
						anim = _dir_anim(wander_dir)
					WanderPhase.PAUSE:
						anim = "idle"
			State.ATTACK:
				anim = "shoot"
			State.REPOSITION:
				var move_dir = Vector3(velocity.x, 0, velocity.z)
				anim = _dir_anim(move_dir)
			State.FLEE:
				anim = "sprint"
			State.INTERRUPTED:
				anim = "idle"
	if anim_player.current_animation != anim:
		anim_player.play(anim)


func take_damage(amount: float):
	if state == State.DEAD:
		return
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
		_clear_death_state()
	else:
		hurt_timer = anim_player.get_animation("hurt").length * 0.5
