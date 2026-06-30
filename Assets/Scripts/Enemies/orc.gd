extends CharacterBody3D

signal died

# HP ------------------------------------------------
var hp = 100.0
const MAX_HP = 100.0
const EXECUTE_THRESHOLD = 0.3

# Detection / Aggro --------------------------------
const DETECTION_RANGE = 15.0
const AGGRO_LOSS_RANGE = 30.0
const MOVE_SPEED = 3.0

# Melee Combat --------------------------------------
const MELEE_DAMAGE = 20.0
const MELEE_KNOCKBACK = 50.0
const MELEE_RANGE = 3.5
const ATTACK_COOLDOWN = 2.5

# Stun (3rd hit) ------------------------------------
const STUN_DURATION = 0.5

# Prepare State -------------------------------------
const PREPARE_DURATION = 4.0
const PREPARE_PAUSE = 0.8
const PREPARE_WALK_MIN = 0.5
const PREPARE_WALK_MAX = 1.5

# Chase --------------------------------------------
const CHASE_TIMEOUT = 3.5
const CHASE_READY_DELAY = 0.2
const EMPOWERED_READY_DELAY = 0.8
const CHASE_SPEED_MULT = 1.6

# Swing hit timing ------------------------------------
const SWING_HIT_PERCENT = 0.5

# Dodge ---------------------------------------------
const DODGE_SPEED = 2.5
const DODGE_DURATION = 42.0 / 30.0
const DODGE_JUMP_VELOCITY = 3.5
const DODGE_READY_DELAY = 0

# Idle Wander ----------------------------------------
const IDLE_WALK_MIN = 1.0
const IDLE_WALK_MAX = 3.0
const IDLE_PAUSE = 1.5
const IDLE_MOVE_SPEED = 1.5

# Knockback -----------------------------------------
const KNOCKBACK_FRICTION = 8.0
const SEPARATION_RADIUS = 1.5
const SEPARATION_FORCE = 2.0

# Magic Circle --------------------------------------
const MAGIC_CIRCLE_TEXTURE = preload("res://Assets/Objects/magic circle prototype.png")

# Facing ---------------------------------------------
const FACE_OFFSET = deg_to_rad(180)

var knockback_velocity = Vector3.ZERO
var impulse = Vector3.ZERO
var branded_timer = 0.0
var speed_multiplier = 1.0

# References ----------------------------------------
var player = null

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel
@onready var anim_player = $AnimationPlayer
@onready var skeleton = $OrcModel/metarig/Skeleton3D
@onready var collision_shape = $CollisionShape3D

# State machine -------------------------------------
enum State { IDLE, SURPRISED, PREPARE, ATTACK, DEAD }
enum AttackPhase { CHASE, CHASE_READY, SWING, DODGE }
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
var chase_timer = 0.0
var dodge_dir = Vector3.ZERO
var dodge_ready_timer = 0.0
var hurt_timer = 0.0
var stunned_timer = 0.0
var disengage_timer = 0.0
var attack_dealt = false
var swing_len = 0.0
var swing_anim_name = ""


func _ready():
	player = get_tree().get_first_node_in_group("player")
	_idle_pick_wander()
	_setup_animations()


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

	if hurt_timer > 0:
		hurt_timer -= delta

	if stunned_timer > 0:
		stunned_timer -= delta

	if disengage_timer > 0:
		disengage_timer -= delta
		if disengage_timer <= 0:
			if state == State.ATTACK:
				_attack_finished(global_position.distance_to(player.global_position))
			elif state == State.PREPARE:
				state_timer = PREPARE_DURATION
				_prepare_enter()

	if state == State.ATTACK and attack_phase == AttackPhase.SWING:
		state_timer -= delta

	var can_act = speed_multiplier > 0 and knockback_velocity.length() <= 0.1 and hurt_timer <= 0 and stunned_timer <= 0 and state != State.DEAD

	if can_act:
		match state:
			State.IDLE:
				if distance <= DETECTION_RANGE:
					state = State.SURPRISED
					state_timer = anim_player.get_animation("surprised").length
					velocity = Vector3.ZERO
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

			State.SURPRISED:
				velocity.x = 0.0
				velocity.z = 0.0
				state_timer -= delta
				if state_timer <= 0:
					state = State.PREPARE
					state_timer = PREPARE_DURATION
					_prepare_enter()

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
					chase_timer = CHASE_TIMEOUT

			State.ATTACK:
				var move_speed = MOVE_SPEED * speed_multiplier * CHASE_SPEED_MULT
				if is_in_group("branded"):
					move_speed *= 0.85

				match attack_phase:
					AttackPhase.CHASE:
						nav_agent.target_position = player.global_position
						var next_pos = nav_agent.get_next_path_position()
						var move_dir = (next_pos - global_position).normalized()
						velocity.x = move_dir.x * move_speed
						velocity.z = move_dir.z * move_speed
						if distance <= 1.5:
							attack_phase = AttackPhase.CHASE_READY
							var ready_delay = EMPOWERED_READY_DELAY if hit_count % 3 == 2 else CHASE_READY_DELAY
							state_timer = ready_delay
							velocity = Vector3.ZERO
						chase_timer -= delta
						if chase_timer <= 0:
							attack_phase = AttackPhase.CHASE_READY
							var ready_delay = EMPOWERED_READY_DELAY if hit_count % 3 == 2 else CHASE_READY_DELAY
							state_timer = ready_delay
							velocity = Vector3.ZERO

					AttackPhase.CHASE_READY:
						velocity.x = 0.0
						velocity.z = 0.0
						state_timer -= delta
						if state_timer <= 0:
							attack_phase = AttackPhase.SWING
							attack_dealt = false
							swing_anim_name = "empowered_swing" if hit_count % 3 == 2 else "swing"
							swing_len = anim_player.get_animation(swing_anim_name).length
							state_timer = swing_len

					AttackPhase.SWING:
						velocity.x = 0.0
						velocity.z = 0.0
						var hit_pct = 0.35 if swing_anim_name == "empowered_swing" else SWING_HIT_PERCENT
						if not attack_dealt and state_timer <= swing_len * (1.0 - hit_pct):
							attack_dealt = true
							if not _melee_attack():
								_attack_finished(distance)
						if state_timer <= 0:
							if attack_dealt:
								attack_phase = AttackPhase.DODGE
								dodge_dir = (global_position - player.global_position).normalized()
								dodge_dir.y = 0.0
								dodge_ready_timer = DODGE_READY_DELAY
								state_timer = DODGE_DURATION
							else:
								_attack_finished(distance)

					AttackPhase.DODGE:
						if dodge_ready_timer > 0:
							dodge_ready_timer -= delta
							velocity.x = 0.0
							velocity.z = 0.0
						else:
							if state_timer == DODGE_DURATION:
								velocity.y = DODGE_JUMP_VELOCITY
							velocity.x = dodge_dir.x * DODGE_SPEED
							velocity.z = dodge_dir.z * DODGE_SPEED
							state_timer -= delta
							if state_timer <= 0:
								velocity.x = 0.0
								velocity.z = 0.0
								_attack_finished(distance)

	if state == State.DEAD:
		state_timer -= delta
		if state_timer <= 0:
			collision_shape.set_deferred("disabled", true)
			set_physics_process(false)

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

	if speed_multiplier <= 0 and knockback_velocity.length() <= 0.1:
		velocity.x = 0.0
		velocity.z = 0.0

	_separate_from_others()
	_update_animation()

	const ROTATION_SPEED = 10.0
	var face_dir: Vector3
	if knockback_velocity.length() > 0.1:
		face_dir = (player.global_position - global_position).normalized()
	else:
		match state:
			State.SURPRISED, State.PREPARE:
				face_dir = (player.global_position - global_position).normalized()
			State.ATTACK:
				if attack_phase == AttackPhase.DODGE:
					face_dir = (player.global_position - global_position).normalized()
				else:
					var v = Vector3(velocity.x, 0, velocity.z)
					if v.length() > 0.1:
						face_dir = v.normalized()
					elif attack_phase in [AttackPhase.CHASE_READY, AttackPhase.SWING]:
						face_dir = (player.global_position - global_position).normalized()
			_:
				var v = Vector3(velocity.x, 0, velocity.z)
				if v.length() > 0.1:
					face_dir = v.normalized()
	if face_dir:
		face_dir.y = 0.0
		if face_dir.length() < 0.001:
			face_dir = Vector3.FORWARD
		face_dir = face_dir.normalized()
		var target_basis = Basis.looking_at(face_dir, Vector3.UP)
		target_basis = target_basis * Basis(Vector3.UP, FACE_OFFSET)
		global_transform.basis = global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)

	var head_idx = skeleton.find_bone("Head")
	if head_idx >= 0 and face_dir != Vector3.ZERO:
		var head_global = skeleton.to_global(skeleton.get_bone_global_pose(head_idx).origin)
		var head_to_player = player.global_position - head_global
		var pitch = -atan2(head_to_player.y, Vector2(head_to_player.x, head_to_player.z).length())
		pitch = clamp(pitch, deg_to_rad(-60), deg_to_rad(60))
		var head_rot = Quaternion(Vector3.RIGHT, pitch)
		skeleton.set_bone_pose_rotation(head_idx, head_rot)
	elif head_idx >= 0:
		skeleton.set_bone_pose_rotation(head_idx, Quaternion.IDENTITY)

	var grav_mult = 3.0 if state != State.ATTACK or attack_phase != AttackPhase.DODGE else 1.0
	velocity += get_gravity() * delta * grav_mult
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
	if player:
		var dir = (player.global_position - global_position).normalized()
		wander_dir = Vector3(dir.x, 0, dir.z).normalized()
	else:
		var angle = randf_range(0, TAU)
		wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	idle_walk_timer = randf_range(IDLE_WALK_MIN, IDLE_WALK_MAX)
	idle_phase = PreparePhase.WALK


func _prepare_enter() -> void:
	prepare_phase = PreparePhase.WALK
	wander_dir = _pick_wander_dir(global_position.distance_to(player.global_position))
	prepare_move_timer = randf_range(PREPARE_WALK_MIN, PREPARE_WALK_MAX)


func _attack_finished(distance: float) -> void:
	if distance <= DETECTION_RANGE:
		state = State.PREPARE
		state_timer = PREPARE_DURATION
		_prepare_enter()
	else:
		state = State.IDLE
		_idle_pick_wander()


func _make_floor_circle(radius: float) -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.texture = MAGIC_CIRCLE_TEXTURE
	sprite.centered = true
	sprite.billboard = false
	sprite.rotation.x = -PI / 2
	var tex_size = sprite.texture.get_size()
	sprite.pixel_size = (radius * 2.0) / tex_size.x
	sprite.position.y = 0.05
	sprite.visible = false
	add_child(sprite)
	return sprite


func _setup_animations() -> void:
	var paths = {
		idle = "res://Assets/3D Models/Orc/Animations/Orc Idle.fbx",
		walk_forward = "res://Assets/3D Models/Orc/Animations/Orc Forward Walk.fbx",
		walk_backward = "res://Assets/3D Models/Orc/Animations/Walking Backwards.fbx",
		strafe_left = "res://Assets/3D Models/Orc/Animations/Left Strafe Walking.fbx",
		strafe_right = "res://Assets/3D Models/Orc/Animations/Right Strafe Walking.fbx",
		back_dash = "res://Assets/3D Models/Orc/Animations/Back Dash.fbx",
		surprised = "res://Assets/3D Models/Orc/Animations/Spots player.fbx",
		hurt = "res://Assets/3D Models/Orc/Animations/Hurt.fbx",
		swing = "res://Assets/3D Models/Orc/Animations/Swing weapon.fbx",
		empowered_swing = "res://Assets/3D Models/Orc/Animations/Empowered Swing.fbx",
		chase = "res://Assets/3D Models/Orc/Animations/Chase.fbx",
		death = "res://Assets/3D Models/Orc/Animations/On Death.fbx",
		stunned = "res://Assets/3D Models/Orc/Animations/Stunned.fbx",
	}
	var lib = AnimationLibrary.new()
	for anim_name in paths:
		var fbx = load(paths[anim_name]) as PackedScene
		if not fbx:
			continue
		var temp = fbx.instantiate()
		var src_player = temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src_player and src_player.has_animation("mixamo_com"):
			var anim = src_player.get_animation("mixamo_com").duplicate(true)
			anim.loop_mode = Animation.LOOP_LINEAR
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
	if lib.has_animation("swing"):
		lib.get_animation("swing").loop_mode = Animation.LOOP_NONE
	if lib.has_animation("empowered_swing"):
		lib.get_animation("empowered_swing").loop_mode = Animation.LOOP_NONE
	if lib.has_animation("surprised"):
		lib.get_animation("surprised").loop_mode = Animation.LOOP_NONE
	if lib.has_animation("hurt"):
		lib.get_animation("hurt").loop_mode = Animation.LOOP_NONE
	if lib.has_animation("death"):
		lib.get_animation("death").loop_mode = Animation.LOOP_NONE
	anim_player.play("idle")


func _dir_anim(move_dir: Vector3) -> String:
	if move_dir.length() < 0.1:
		return "idle"
	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var angle = fwd.signed_angle_to(move_dir.normalized(), Vector3.UP)
	if abs(angle) > deg_to_rad(120):
		return "walk_backward"
	elif angle > deg_to_rad(60):
		return "strafe_right"
	elif angle < deg_to_rad(-60):
		return "strafe_left"
	else:
		return "walk_forward"


func _update_animation() -> void:
	var anim = "idle"
	if state == State.DEAD:
		anim = "death"
	elif speed_multiplier <= 0 or knockback_velocity.length() > 0.1 or stunned_timer > 0:
		anim = "stunned"
	elif hurt_timer > 0:
		anim = "hurt"
	else:
		match state:
			State.IDLE:
				match idle_phase:
					PreparePhase.WALK:
						anim = _dir_anim(wander_dir)
					PreparePhase.PAUSE:
						anim = "idle"
			State.SURPRISED:
				anim = "surprised"
			State.PREPARE:
				match prepare_phase:
					PreparePhase.WALK:
						anim = _dir_anim(wander_dir)
					PreparePhase.PAUSE:
						anim = "idle"
			State.ATTACK:
				match attack_phase:
					AttackPhase.CHASE:
						anim = "chase"
					AttackPhase.CHASE_READY:
						anim = "idle"
					AttackPhase.SWING:
						anim = swing_anim_name
					AttackPhase.DODGE:
						anim = "back_dash"
	if anim_player.current_animation != anim:
		anim_player.play(anim)


func _melee_attack() -> bool:
	if global_position.distance_to(player.global_position) > MELEE_RANGE:
		return false
	hit_count += 1
	player.take_damage(MELEE_DAMAGE)

	if hit_count % 3 == 0:
		var push_dir = (player.global_position - global_position).normalized()
		push_dir.y = 0.0
		player.knockback_velocity = push_dir * MELEE_KNOCKBACK
		player.stun_timer = STUN_DURATION

	return true


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

func take_damage(amount: float):
	if is_in_group("branded"):
		amount *= 0.7
	hp -= amount
	hp = clamp(hp, 0, MAX_HP)
	hp_label.text = str(round(hp))
	if hp <= 0:
		_clear_death_state()
	else:
		hurt_timer = anim_player.get_animation("hurt").length * 0.5

func _clear_death_state():
	if state == State.DEAD:
		return
	state = State.DEAD
	state_timer = anim_player.get_animation("death").length
	velocity = Vector3.ZERO
	died.emit()
	await get_tree().create_timer(state_timer).timeout
	_become_corpse()

func _become_corpse():
	remove_from_group("enemies")
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	hp_label.queue_free()
	$NameLabel.queue_free()
