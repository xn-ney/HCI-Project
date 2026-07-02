extends CharacterBody3D

signal died

# HP ------------------------------------------------
var hp = 40.0
const MAX_HP = 40.0
const EXECUTE_THRESHOLD = 0.3

# Detection / Aggro --------------------------------
const DETECTION_RANGE = 9.0
const AGGRO_LOSS_RANGE = 12.0
const MOVE_SPEED = 5.0

# Lunge Attack --------------------------------------
const LUNGE_DURATION = 3.0
const MIN_DASH_TIME = 0.5
const JUMP_RANGE = 4.5
const LUNGE_SPEED_MULT = 2.0
const MELEE_DAMAGE = 8.0
const MELEE_RANGE = 2.0

# Cry ------------------------------------------------
const CRY_DURATION = 3.0
const CRY_RANGE = 30.0
const CRY_BACKUP_CHANCE = 0.4
const CRY_CHANCE = 0.2

# Reposition ----------------------------------------
const REPOSITION_DURATION = 3.0
const OVERSHOOT_STOP_RANGE = 7.0
const REPOSITION_STAND_DELAY = 0.35
const MOVE_BACK_RANGE = 3.0
const ENCIRCLE_RANGE = 6.0
const MOVE_FORWARD_RANGE = 8.0

# Regroup -------------------------------------------
const REGROUP_DETECTION = 12.0

# Interrupt ------------------------------------------
const INTERRUPT_DURATION = 0.6

# Idle Wander ----------------------------------------
const IDLE_WALK_MIN = 0.5
const IDLE_WALK_MAX = 2.0
const IDLE_PAUSE = 1.0
const IDLE_MOVE_SPEED = 2.0

# Knockback -----------------------------------------
const KNOCKBACK_FRICTION = 10.0
const SEPARATION_RADIUS = 1.0
const SEPARATION_FORCE = 2.0

var knockback_velocity = Vector3.ZERO
var impulse = Vector3.ZERO
var branded_timer = 0.0
var speed_multiplier = 1.0
var stunned_timer = 0.0
var disengage_timer = 0.0

# References ----------------------------------------
var player = null
var _original_player = null
var _target_override: Node3D = null
var _npc_check_done: bool = false

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel
@onready var skeleton = $Basic_Goblin/metarig/Skeleton3D
@onready var anim_player = $AnimationPlayer

# Head tracking -------------------------------------
var _head_idx = -1
var _head_rest_inv = Quaternion.IDENTITY

# Facing ---------------------------------------------
const FACE_OFFSET = deg_to_rad(180)
const ROTATION_SPEED = 10.0

# State machine -------------------------------------
enum State { IDLE, REGROUP, ATTACK, REPOSITION, INTERRUPTED, CRY, DEAD }
enum IdlePhase { WALK, PAUSE }

var state = State.IDLE
var state_timer = 0.0
var idle_phase = IdlePhase.WALK
var idle_walk_timer: float
var idle_pause_timer: float
var wander_dir = Vector3.ZERO

# Attack tracking -----------------------------------
var has_attacked = false
var has_jumped = false
var lunge_dir = Vector3.ZERO
var attack_missed = false

# Animation -----------------------------------------
var hurt_timer = 0.0
var _is_corpse = false

# Reposition tracking -------------------------------
enum RepositionPhase { STAND, MOVE, PAUSE }
var reposition_phase = RepositionPhase.STAND
var reposition_phase_timer = 0.0
var reposition_strafe_dir = 1.0
var strafe_dir = 1.0

# Regroup tracking ----------------------------------
var regroup_used = false

# Cry tracking ---------------------------------------
var has_cried = false
var backup_target = null
var backup_position = Vector3.ZERO


func _ready():
	player = get_tree().get_first_node_in_group("player")
	_original_player = player
	_idle_pick_wander()
	_head_idx = skeleton.find_bone("spine.005")
	if _head_idx >= 0:
		_head_rest_inv = skeleton.get_bone_rest(_head_idx).basis.get_rotation_quaternion().inverse()
	_setup_animations()
	anim_player.play("walk_forward")


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

	if disengage_timer > 0:
		disengage_timer -= delta
		if disengage_timer <= 0:
			if state == State.ATTACK:
				state = State.REPOSITION
				state_timer = REPOSITION_DURATION
				reposition_phase = RepositionPhase.STAND
				reposition_phase_timer = REPOSITION_STAND_DELAY
			elif state == State.REPOSITION:
				state_timer = REPOSITION_DURATION
				reposition_phase = RepositionPhase.STAND
				reposition_phase_timer = REPOSITION_STAND_DELAY

	var distance = global_position.distance_to(player.global_position)

	if distance > AGGRO_LOSS_RANGE:
		if state != State.IDLE and state != State.REGROUP:
			state = State.IDLE
			_idle_pick_wander()

	var can_act = speed_multiplier > 0 and knockback_velocity.length() <= 0.1 and stunned_timer <= 0

	if can_act:
		match state:
			State.IDLE:
				if distance <= DETECTION_RANGE:
					state = State.REPOSITION
					state_timer = REPOSITION_DURATION
					reposition_phase = RepositionPhase.STAND
					reposition_phase_timer = REPOSITION_STAND_DELAY
				else:
					if not regroup_used:
						var target = _find_nearest_scavenger()
						if target != null:
							state = State.REGROUP
							regroup_used = true
							return

					match idle_phase:
						IdlePhase.WALK:
							velocity.x = wander_dir.x * IDLE_MOVE_SPEED
							velocity.z = wander_dir.z * IDLE_MOVE_SPEED
							idle_walk_timer -= delta
							if idle_walk_timer <= 0:
								idle_phase = IdlePhase.PAUSE
								idle_pause_timer = IDLE_PAUSE
								velocity.x = 0.0
								velocity.z = 0.0
						IdlePhase.PAUSE:
							idle_pause_timer -= delta
							if idle_pause_timer <= 0:
								_idle_pick_wander()

			State.REGROUP:
				if backup_target != null and is_instance_valid(backup_target):
					backup_position = backup_target.global_position

				var path_target = null
				var path_pos = Vector3.ZERO

				if backup_target != null and is_instance_valid(backup_target):
					path_target = backup_target
				elif backup_position != Vector3.ZERO:
					path_pos = backup_position
				else:
					path_target = _find_nearest_scavenger()

				if path_target == null and path_pos == Vector3.ZERO:
					if distance <= DETECTION_RANGE:
						_attack_enter()
					else:
						state = State.IDLE
						_idle_pick_wander()
				else:
					if path_target != null:
						nav_agent.target_position = path_target.global_position
					else:
						nav_agent.target_position = path_pos

					var move_speed = MOVE_SPEED * speed_multiplier
					if is_in_group("branded"):
						move_speed *= 0.85
					if backup_target != null or backup_position != Vector3.ZERO:
						move_speed *= 2.0
					var next_pos = nav_agent.get_next_path_position()
					var move_dir = (next_pos - global_position).normalized()
					velocity.x = move_dir.x * move_speed
					velocity.z = move_dir.z * move_speed

					var arrived = false
					if path_target != null:
						if global_position.distance_to(path_target.global_position) <= 2.0:
							arrived = true
							backup_target = null
					else:
						if global_position.distance_to(path_pos) <= 2.0:
							arrived = true

					if arrived:
						backup_position = Vector3.ZERO
						if distance <= DETECTION_RANGE:
							_attack_enter()
						else:
							state = State.IDLE
							_idle_pick_wander()

			State.ATTACK:
				state_timer -= delta

				if not has_jumped and distance <= JUMP_RANGE:
					has_jumped = true
					velocity.y = 7.0

				if has_jumped and not has_attacked and not is_on_floor() and distance <= MELEE_RANGE:
					_melee_attack()
					has_attacked = true
					state = State.REPOSITION
					state_timer = REPOSITION_DURATION
					reposition_phase = RepositionPhase.STAND
					reposition_phase_timer = REPOSITION_STAND_DELAY
				elif not has_attacked:
					var dash_speed = MOVE_SPEED * LUNGE_SPEED_MULT
					if is_in_group("branded"):
						dash_speed *= 0.85
					velocity.x = lunge_dir.x * dash_speed
					velocity.z = lunge_dir.z * dash_speed

				if state == State.ATTACK and distance > OVERSHOOT_STOP_RANGE and LUNGE_DURATION - state_timer > MIN_DASH_TIME:
					state = State.REPOSITION
					state_timer = REPOSITION_DURATION
					reposition_phase = RepositionPhase.STAND
					reposition_phase_timer = REPOSITION_STAND_DELAY
					attack_missed = true

				if state_timer <= 0 and state == State.ATTACK:
					state = State.REPOSITION
					state_timer = REPOSITION_DURATION
					reposition_phase = RepositionPhase.STAND
					reposition_phase_timer = REPOSITION_STAND_DELAY
					attack_missed = true

			State.REPOSITION:
				var move_speed = MOVE_SPEED * speed_multiplier
				if is_in_group("branded"):
					move_speed *= 0.85

				reposition_phase_timer -= delta

				if reposition_phase == RepositionPhase.STAND:
					velocity.x = 0.0
					velocity.z = 0.0
					if reposition_phase_timer <= 0:
						reposition_phase = RepositionPhase.MOVE
						reposition_phase_timer = randf_range(0.5, 1.2)
						reposition_strafe_dir = 1.0 if (randf() < 0.5) else -1.0
						strafe_dir = reposition_strafe_dir
						attack_missed = false

				elif reposition_phase == RepositionPhase.PAUSE:
					velocity.x = 0.0
					velocity.z = 0.0
					if reposition_phase_timer <= 0:
						reposition_phase = RepositionPhase.MOVE
						reposition_phase_timer = randf_range(0.5, 1.2)
						reposition_strafe_dir = 1.0 if (randf() < 0.5) else -1.0
						strafe_dir = reposition_strafe_dir
						attack_missed = false

				else:
					if distance > OVERSHOOT_STOP_RANGE:
						var to_player = (player.global_position - global_position).normalized()
						to_player.y = 0.0
						velocity.x = to_player.x * move_speed
						velocity.z = to_player.z * move_speed
					elif distance <= ENCIRCLE_RANGE:
						var away = (global_position - player.global_position).normalized()
						away.y = 0.0
						velocity.x = away.x * move_speed
						velocity.z = away.z * move_speed
					else:
						var to_player = (player.global_position - global_position).normalized()
						to_player.y = 0.0
						var perp = Vector3(-to_player.z, 0, to_player.x)
						velocity.x = perp.x * move_speed * reposition_strafe_dir
						velocity.z = perp.z * move_speed * reposition_strafe_dir

					if reposition_phase_timer <= 0:
						reposition_phase = RepositionPhase.PAUSE
						reposition_phase_timer = 0.5

				state_timer -= delta
				if state_timer <= 0:
					if randf() < CRY_CHANCE:
						_cry_enter()
					else:
						_attack_enter()

			State.CRY:
				state_timer -= delta
				velocity.x = 0.0
				velocity.z = 0.0
				if not has_cried:
					has_cried = true
					_do_cry_backup()
				if state_timer <= 0:
					state = State.REPOSITION
					state_timer = REPOSITION_DURATION
					reposition_phase = RepositionPhase.STAND
					reposition_phase_timer = REPOSITION_STAND_DELAY

			State.INTERRUPTED:
				velocity.x = 0.0
				velocity.z = 0.0
				state_timer -= delta
				if state_timer <= 0:
					if distance <= DETECTION_RANGE:
						_attack_enter()
					else:
						state = State.IDLE
						_idle_pick_wander()

	if state == State.CRY:
		hp_label.text = "Crying"
	elif state == State.INTERRUPTED:
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

	# Facing --------------------------------------------
	var face_dir := Vector3.FORWARD
	if stunned_timer > 0:
		face_dir = Vector3.ZERO
	elif knockback_velocity.length() > 0.1:
		face_dir = (player.global_position - global_position).normalized()
	else:
		match state:
			State.ATTACK, State.REPOSITION, State.INTERRUPTED:
				face_dir = (player.global_position - global_position).normalized()
			State.IDLE, State.REGROUP:
				var v = Vector3(velocity.x, 0, velocity.z)
				if v.length() > 0.1:
					face_dir = v.normalized()
				else:
					face_dir = wander_dir
	if face_dir:
		face_dir.y = 0.0
		if face_dir.length() < 0.001:
			face_dir = Vector3.FORWARD
		face_dir = face_dir.normalized()
		var target_basis = Basis.looking_at(face_dir, Vector3.UP)
		target_basis = target_basis * Basis(Vector3.UP, FACE_OFFSET)
		global_transform.basis = global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)

	# Head tracking --------------------------------------
	if _head_idx >= 0 and face_dir != Vector3.ZERO:
		var head_global = skeleton.to_global(skeleton.get_bone_global_pose(_head_idx).origin)
		var head_to_player = player.global_position - head_global
		var pitch = -atan2(head_to_player.y, Vector2(head_to_player.x, head_to_player.z).length())
		pitch = clamp(pitch, deg_to_rad(-60), deg_to_rad(60))
		var head_rot = _head_rest_inv * Quaternion(Vector3.RIGHT, pitch)
		skeleton.set_bone_pose_rotation(_head_idx, head_rot)
	elif _head_idx >= 0:
		skeleton.set_bone_pose_rotation(_head_idx, Quaternion.IDENTITY)

	if hurt_timer > 0:
		hurt_timer -= delta

	_update_animation()

	velocity += get_gravity() * delta * 3.0
	move_and_slide()


func _attack_enter() -> void:
	state = State.ATTACK
	state_timer = LUNGE_DURATION
	has_attacked = false
	has_jumped = false
	attack_missed = false
	var dir = (player.global_position - global_position).normalized()
	dir.y = 0.0
	lunge_dir = dir
	var dash_speed = MOVE_SPEED * LUNGE_SPEED_MULT
	if is_in_group("branded"):
		dash_speed *= 0.85
	velocity.x = lunge_dir.x * dash_speed
	velocity.z = lunge_dir.z * dash_speed


func _cry_enter() -> void:
	state = State.CRY
	state_timer = CRY_DURATION
	has_cried = false
	velocity.x = 0.0
	velocity.z = 0.0


func _do_cry_backup() -> void:
	for enemy in get_tree().get_nodes_in_group("scavenger"):
		if enemy == self:
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist <= CRY_RANGE and randf() < CRY_BACKUP_CHANCE:
			enemy._backup_called(self)


func _backup_called(caller: Node3D) -> void:
	if state == State.IDLE:
		backup_target = caller
		state = State.REGROUP


func _find_nearest_scavenger() -> Node3D:
	var nearest = null
	var nearest_dist = REGROUP_DETECTION
	for enemy in get_tree().get_nodes_in_group("scavenger"):
		if enemy == self:
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func _idle_pick_wander() -> void:
	var roll = randf()
	if roll < 0.3:
		if player:
			var to_player = (player.global_position - global_position).normalized()
			to_player.y = 0.0
			wander_dir = to_player
		else:
			var angle = randf_range(0, TAU)
			wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	elif roll < 0.6:
		var target = _find_nearest_scavenger()
		if target != null:
			var to_scav = (target.global_position - global_position).normalized()
			to_scav.y = 0.0
			wander_dir = to_scav
		else:
			var angle = randf_range(0, TAU)
			wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	else:
		var angle = randf_range(0, TAU)
		wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()

	idle_walk_timer = randf_range(IDLE_WALK_MIN, IDLE_WALK_MAX)
	idle_phase = IdlePhase.WALK


func _melee_attack() -> void:
	player.take_damage(MELEE_DAMAGE)


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

func take_damage(amount: float):
	if state == State.DEAD:
		return
	if state == State.CRY:
		hp = 0
		_clear_death_state()
		return
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
	if not _is_corpse:
		_become_corpse()


func _setup_animations() -> void:
	var ANIM_BASE = "res://Assets/3D Models/Goblin Scavenger/Animation/"
	var paths = {
		walk_forward = ANIM_BASE + "Walk Forward.fbx",
		walk_backward = ANIM_BASE + "Walk Backwards.fbx",
		strafe_left = ANIM_BASE + "Left Strafe.fbx",
		strafe_right = ANIM_BASE + "Right Strafe.fbx",
		sprint = ANIM_BASE + "Sprint.fbx",
		surprised = ANIM_BASE + "Spot player.fbx",
		hurt = ANIM_BASE + "Hurt.fbx",
		death = ANIM_BASE + "Death.fbx",
		stunned = ANIM_BASE + "Goblin scav stunned.fbx",
		jump_attack = ANIM_BASE + "Jump attack.fbx",
		attack_missed = ANIM_BASE + "Attack missed.fbx",
		cry = ANIM_BASE + "Cry.fbx",
	}
	var loop_anims = ["walk_forward", "walk_backward", "strafe_left", "strafe_right", "sprint"]
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


func _dir_anim(move_dir: Vector3) -> String:
	if move_dir.length() < 0.1:
		return "walk_forward"
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
	var anim = "walk_forward"
	if state == State.DEAD:
		anim = "death"
	elif speed_multiplier <= 0 or knockback_velocity.length() > 0.1 or stunned_timer > 0:
		anim = "stunned"
	elif hurt_timer > 0:
		anim = "hurt"
	else:
		match state:
			State.REGROUP:
				anim = "sprint"
			State.ATTACK:
				anim = "jump_attack"
			State.CRY:
				anim = "cry"
			State.REPOSITION:
				var move_dir = Vector3(velocity.x, 0, velocity.z)
				if attack_missed and move_dir.length() < 0.1:
					anim = "attack_missed"
				else:
					anim = _dir_anim(move_dir)
			State.IDLE:
				var move_dir = Vector3(velocity.x, 0, velocity.z)
				if move_dir.length() > 0.1:
					anim = _dir_anim(move_dir)
				else:
					anim = "walk_forward"
			State.INTERRUPTED:
				anim = "walk_forward"
	if anim_player.current_animation != anim:
		anim_player.play(anim)
