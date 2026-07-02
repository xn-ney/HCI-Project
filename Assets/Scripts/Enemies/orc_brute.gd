extends CharacterBody3D

signal died

# HP ------------------------------------------------
var hp = 200.0
const MAX_HP = 200.0
const EXECUTE_THRESHOLD = 0.3

# Detection / Aggro --------------------------------
const DETECTION_RANGE = 15.0
const AGGRO_LOSS_RANGE = 18.0
const MOVE_SPEED = 2.5

# Normal Swing --------------------------------------
const MELEE_DAMAGE = 30.0
const MELEE_KNOCKBACK = 30.0
const MELEE_RANGE = 5.0
const ATTACK_COOLDOWN = 2.5

# Chase --------------------------------------------
const CHASE_TIMEOUT = 5.0
const CHASE_READY_DELAY = 0.3
const CHASE_SPEED_MULT = 1.9

# Dash and Slam -------------------------------------
const DASH_CHANCE = 0.3
const DASH_CHARGE_TIME = 2.5
const DASH_SPEED = 30.0
const DASH_DURATION = 0.35
const DASH_STOP_RANGE = 2.0
const SLAM_DAMAGE = 40.0
const SLAM_KNOCKUP = 15.0
const SLAM_RANGE = 7
const SLAM_KNOCKBACK = 30.0

# Interrupt ------------------------------------------
const INTERRUPT_DURATION = 1.5

# Prepare State -------------------------------------
const PREPARE_DURATION = 4.0
const PREPARE_PAUSE = 0.8
const PREPARE_WALK_MIN = 0.5
const PREPARE_WALK_MAX = 1.5

# Idle Wander ----------------------------------------
const IDLE_WALK_MIN = 1.0
const IDLE_WALK_MAX = 3.0
const IDLE_PAUSE = 1.5
const IDLE_MOVE_SPEED = 1.5

# Magic Circle --------------------------------------
const MAGIC_CIRCLE_TEXTURE = preload("res://Assets/Objects/magic circle prototype.png")

# Knockback -----------------------------------------
const KNOCKBACK_FRICTION = 8.0
const SEPARATION_RADIUS = 1.5
const SEPARATION_FORCE = 2.0

# Facing ---------------------------------------------
const FACE_OFFSET = deg_to_rad(180)

var knockback_velocity = Vector3.ZERO
var impulse = Vector3.ZERO
var branded_timer = 0.0
var speed_multiplier = 1.0
var stunned_timer = 0.0
var hurt_timer = 0.0
var disengage_timer = 0.0
var dash_dir = Vector3.ZERO

# References ----------------------------------------
var player = null
var _original_player = null
var _target_override: Node3D = null
var _npc_check_done: bool = false
var slam_indicator: Sprite3D = null
var melee_indicator: Sprite3D = null

@onready var nav_agent = $NavigationAgent3D
@onready var hp_label = $HPLabel
@onready var anim_player = $AnimationPlayer
@onready var skeleton = $Ironbound_Marauder/metarig/Skeleton3D
@onready var collision_shape = $CollisionShape3D

# State machine -------------------------------------
enum State { IDLE, SPAWNCHASE, SURPRISED, PREPARE, ATTACK, DEAD }
enum AttackPhase { CHASE, CHASE_READY, SWING, DASH_CHARGE, DASHING, SLAMMING }
enum PreparePhase { WALK, PAUSE }

var state = State.IDLE
var attack_phase = AttackPhase.CHASE
var chase_timer = 0.0
var prepare_phase = PreparePhase.WALK
var state_timer = 0.0
var prepare_move_timer = 0.0
var prepare_pause_timer = 0.0
var idle_phase = PreparePhase.WALK
var idle_walk_timer: float
var idle_pause_timer: float
var wander_dir = Vector3.ZERO

# Swing tracking ------------------------------------
var swing_hit_dealt = false

# Head tracking -------------------------------------
var _head_idx = -1

# Corpse guard --------------------------------------
var _is_corpse := false


func _ready():
	player = get_tree().get_first_node_in_group("player")
	_original_player = player
	if EscortCondition.spawnchase_enabled:
		state = State.SPAWNCHASE
	else:
		state = State.IDLE
		_idle_pick_wander()
	_slam_indicator_create()
	_melee_indicator_create()
	_setup_animations()
	_head_idx = skeleton.find_bone("Head")


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
				_attack_finished(global_position.distance_to(player.global_position))
			elif state == State.PREPARE:
				state_timer = PREPARE_DURATION
				_prepare_enter()

	var distance = global_position.distance_to(player.global_position)

	# Lose aggro if too far -------------------------
	if distance > AGGRO_LOSS_RANGE and state != State.SURPRISED:
		if state != State.IDLE and state != State.SPAWNCHASE and state != State.ATTACK:
			state = State.IDLE
			_idle_pick_wander()

	if state == State.DEAD:
		state_timer -= delta
		if state_timer <= 0:
			collision_shape.set_deferred("disabled", true)
			set_physics_process(false)

	var can_act = speed_multiplier > 0 and knockback_velocity.length() <= 0.1 and stunned_timer <= 0 and hurt_timer <= 0 and state != State.DEAD

	if can_act:
		match state:
			State.SPAWNCHASE:
				var move_speed = MOVE_SPEED * speed_multiplier * CHASE_SPEED_MULT
				if is_in_group("branded"):
					move_speed *= 0.85
				nav_agent.target_position = player.global_position
				var next_pos = nav_agent.get_next_path_position()
				var move_dir = (next_pos - global_position).normalized()
				velocity.x = move_dir.x * move_speed
				velocity.z = move_dir.z * move_speed
				if distance <= MELEE_RANGE:
					state = State.ATTACK
					attack_phase = AttackPhase.CHASE_READY
					state_timer = CHASE_READY_DELAY
					velocity = Vector3.ZERO
					melee_indicator.visible = true

			State.IDLE:
				if distance <= DETECTION_RANGE:
					state = State.SURPRISED
					state_timer = anim_player.get_animation("surprised").length * 0.4
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
					if randf() < DASH_CHANCE:
						attack_phase = AttackPhase.DASH_CHARGE
						state_timer = anim_player.get_animation("charging").length
						velocity = Vector3.ZERO
					else:
						attack_phase = AttackPhase.CHASE
						chase_timer = CHASE_TIMEOUT

			State.ATTACK:
				match attack_phase:
					AttackPhase.CHASE:
						var move_speed = MOVE_SPEED * speed_multiplier * CHASE_SPEED_MULT
						if is_in_group("branded"):
							move_speed *= 0.85
						nav_agent.target_position = player.global_position
						var next_pos = nav_agent.get_next_path_position()
						var move_dir = (next_pos - global_position).normalized()
						velocity.x = move_dir.x * move_speed
						velocity.z = move_dir.z * move_speed
						if distance <= MELEE_RANGE:
							velocity = Vector3.ZERO
							attack_phase = AttackPhase.CHASE_READY
							state_timer = CHASE_READY_DELAY
							melee_indicator.visible = true
						chase_timer -= delta
						if chase_timer <= 0:
							_melee_attack_hit()
							_attack_finished(distance)

					AttackPhase.CHASE_READY:
						velocity.x = 0.0
						velocity.z = 0.0
						state_timer -= delta
						if state_timer <= 0:
							melee_indicator.visible = false
							attack_phase = AttackPhase.SWING
							swing_hit_dealt = false
							state_timer = anim_player.get_animation("normal_attack").length

					AttackPhase.SWING:
						velocity.x = 0.0
						velocity.z = 0.0
						state_timer -= delta
						if not swing_hit_dealt and state_timer <= anim_player.get_animation("normal_attack").length * 0.75:
							swing_hit_dealt = true
							_melee_attack_hit()
						if state_timer <= 0:
							_attack_finished(distance)

					AttackPhase.DASH_CHARGE:
						velocity.x = 0.0
						velocity.z = 0.0
						state_timer -= delta
						if state_timer <= 0:
							dash_dir = (player.global_position - global_position).normalized()
							dash_dir.y = 0.0
							attack_phase = AttackPhase.DASHING
							state_timer = DASH_DURATION

					AttackPhase.DASHING:
						velocity.x = dash_dir.x * DASH_SPEED
						velocity.z = dash_dir.z * DASH_SPEED
						state_timer -= delta
						if distance <= DASH_STOP_RANGE or state_timer <= 0:
							velocity = Vector3.ZERO
							attack_phase = AttackPhase.SLAMMING
							swing_hit_dealt = false
							state_timer = anim_player.get_animation("slam").length

					AttackPhase.SLAMMING:
						velocity.x = 0.0
						velocity.z = 0.0
						slam_indicator.visible = true
						state_timer -= delta
						if not swing_hit_dealt and state_timer <= anim_player.get_animation("slam").length * 0.85:
							swing_hit_dealt = true
							_slam_attack()
							slam_indicator.visible = false
							state_timer = 0.3
						if state_timer <= 0:
							slam_indicator.visible = false
							_attack_finished(distance)

		# Status label ----------------------------------
	if speed_multiplier == 0.0:
		hp_label.text = "Petrified"
	elif state == State.ATTACK and attack_phase == AttackPhase.DASH_CHARGE:
		hp_label.text = "Charging"
	elif state == State.ATTACK and attack_phase == AttackPhase.SLAMMING:
		hp_label.text = "Slamming"
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

	# Facing --------------------------------------------
	var face_dir: Vector3
	if stunned_timer > 0:
		face_dir = Vector3.ZERO
	elif knockback_velocity.length() > 0.1:
		face_dir = (player.global_position - global_position).normalized()
	else:
		match state:
			State.SURPRISED, State.PREPARE:
				face_dir = (player.global_position - global_position).normalized()
			State.ATTACK:
				match attack_phase:
					AttackPhase.DASHING:
						face_dir = dash_dir
					AttackPhase.CHASE:
						var v = Vector3(velocity.x, 0, velocity.z)
						face_dir = v.normalized() if v.length() > 0.1 else Vector3.FORWARD
					_:
						face_dir = (player.global_position - global_position).normalized()
			_:
				var v = Vector3(velocity.x, 0, velocity.z)
				face_dir = v.normalized() if v.length() > 0.1 else wander_dir if wander_dir.length() > 0.1 else Vector3.FORWARD
	if face_dir:
		face_dir.y = 0.0
		if face_dir.length() < 0.001:
			face_dir = Vector3.FORWARD
		face_dir = face_dir.normalized()
		var target_basis = Basis.looking_at(face_dir, Vector3.UP)
		target_basis = target_basis * Basis(Vector3.UP, FACE_OFFSET)
		global_transform.basis = global_transform.basis.slerp(target_basis, 10.0 * delta)

	# Head tracking --------------------------------------
	if _head_idx >= 0 and face_dir != Vector3.ZERO:
		var head_global = skeleton.to_global(skeleton.get_bone_global_pose(_head_idx).origin)
		var head_to_player = player.global_position - head_global
		var pitch = -atan2(head_to_player.y, Vector2(head_to_player.x, head_to_player.z).length())
		pitch = clamp(pitch, deg_to_rad(-60), deg_to_rad(60))
		skeleton.set_bone_pose_rotation(_head_idx, Quaternion(Vector3.RIGHT, pitch))
	elif _head_idx >= 0:
		skeleton.set_bone_pose_rotation(_head_idx, Quaternion.IDENTITY)

	velocity += get_gravity() * delta * 3.0
	move_and_slide()


func _attack_finished(distance: float) -> void:
	if distance <= DETECTION_RANGE:
		state = State.PREPARE
		state_timer = PREPARE_DURATION
		_prepare_enter()
	else:
		state = State.IDLE
		_idle_pick_wander()


func _pick_wander_dir(distance: float) -> Vector3:
	var to_player = (player.global_position - global_position).normalized()
	to_player.y = 0.0
	if distance > DETECTION_RANGE * 0.5:
		return to_player
	else:
		return -to_player


func _idle_pick_wander() -> void:
	var angle = randf_range(0, TAU)
	wander_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
	idle_walk_timer = randf_range(IDLE_WALK_MIN, IDLE_WALK_MAX)
	idle_phase = PreparePhase.WALK


func _prepare_enter() -> void:
	prepare_phase = PreparePhase.WALK
	wander_dir = _pick_wander_dir(global_position.distance_to(player.global_position))
	prepare_move_timer = randf_range(PREPARE_WALK_MIN, PREPARE_WALK_MAX)


func _melee_attack_hit() -> void:
	if global_position.distance_to(player.global_position) > MELEE_RANGE:
		return
	player.take_damage(MELEE_DAMAGE)
	if player.is_in_group("player"):
		var push_dir = (player.global_position - global_position).normalized()
		push_dir.y = 0.0
		player.knockback_velocity = push_dir * MELEE_KNOCKBACK


func _slam_attack() -> void:
	if global_position.distance_to(player.global_position) > SLAM_RANGE:
		return
	player.take_damage(SLAM_DAMAGE)
	if player.is_in_group("player"):
		player.knock_up = SLAM_KNOCKUP
		var push_dir = (player.global_position - global_position).normalized()
		push_dir.y = 0.0
		player.knockback_velocity = push_dir * SLAM_KNOCKBACK


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


func _slam_indicator_create() -> void:
	slam_indicator = _make_floor_circle(SLAM_RANGE)


func _melee_indicator_create() -> void:
	melee_indicator = _make_floor_circle(MELEE_RANGE)


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

func take_damage(amount: float):
	if state == State.DEAD:
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
	slam_indicator.visible = false
	melee_indicator.visible = false
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
	if has_node("NameLabel"):
		$NameLabel.queue_free()


func _setup_animations() -> void:
	var paths = {
		idle = "res://Assets/3D Models/Orc Brute/Animations/Orc Idle.fbx",
		walk_forward = "res://Assets/3D Models/Orc Brute/Animations/Walk forward.fbx",
		walk_backward = "res://Assets/3D Models/Orc Brute/Animations/Walk Backwards.fbx",
		chase = "res://Assets/3D Models/Orc Brute/Animations/Chase.fbx",
		charging = "res://Assets/3D Models/Orc Brute/Animations/Charging.fbx",
		dash = "res://Assets/3D Models/Orc Brute/Animations/Dash.fbx",
		normal_attack = "res://Assets/3D Models/Orc Brute/Animations/Normal Attack V3.fbx",
		slam = "res://Assets/3D Models/Orc Brute/Animations/Slam attack.fbx",
		surprised = "res://Assets/3D Models/Orc Brute/Animations/Spots player.fbx",
		hurt = "res://Assets/3D Models/Orc Brute/Animations/Hurt.fbx",
		death = "res://Assets/3D Models/Orc Brute/Animations/Death.fbx",
		stunned = "res://Assets/3D Models/Orc Brute/Animations/Stunned.fbx",
	}
	var loop_anims = ["idle", "walk_forward", "walk_backward", "chase"]
	var lib = AnimationLibrary.new()
	for anim_name in paths:
		var fbx = load(paths[anim_name]) as PackedScene
		if not fbx:
			continue
		var temp = fbx.instantiate()
		var src_player = temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if not src_player:
			src_player = temp.find_child("AnimationPlayer", true, true) as AnimationPlayer
		if not src_player:
			var all_ap = temp.find_children("*", "AnimationPlayer", true, false)
			if all_ap.size() > 0:
				src_player = all_ap[0] as AnimationPlayer
		if src_player:
			var anim_name_src = ""
			for c in ["mixamo_com", "mixamo.com", anim_name, anim_name.capitalize()]:
				if src_player.has_animation(c):
					anim_name_src = c
					break
			if anim_name_src.is_empty():
				var list = src_player.get_animation_list()
				if list.size() > 0:
					anim_name_src = list[0]
			if not anim_name_src.is_empty() and src_player.has_animation(anim_name_src):
				var anim = src_player.get_animation(anim_name_src).duplicate(true)
				anim.loop_mode = Animation.LOOP_LINEAR if anim_name in loop_anims else Animation.LOOP_NONE
				for i in range(anim.get_track_count() - 1, -1, -1):
					var p = str(anim.track_get_path(i))
					if p.ends_with("metarig") or p == "metarig":
						if anim_name == "death":
							anim.track_set_path(i, NodePath(".."))
						else:
							anim.remove_track(i)
					elif p.contains("Skeleton3D:"):
						var parts = p.split("Skeleton3D:")
						if parts.size() >= 2:
							anim.track_set_path(i, NodePath(":" + parts[-1]))
				lib.add_animation(anim_name, anim)
		temp.queue_free()
	anim_player.add_animation_library("", lib)
	anim_player.play("idle")


func _dir_anim(move_dir: Vector3) -> String:
	if move_dir.length() < 0.1:
		return "idle"
	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var dot = move_dir.normalized().dot(fwd)
	if dot >= 0.5:
		return "walk_forward"
	elif dot <= -0.5:
		return "walk_backward"
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
			State.SPAWNCHASE:
				anim = "chase"
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
						anim = "normal_attack"
					AttackPhase.DASH_CHARGE:
						anim = "charging"
					AttackPhase.DASHING:
						anim = "dash"
					AttackPhase.SLAMMING:
						anim = "slam"
	if anim_player.current_animation != anim:
		anim_player.play(anim)
