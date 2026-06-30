extends Node

# Sentinel Stats (applied to Player on select) ------
const RIGHT_WEAPON = "IronDagger"
const LEFT_WEAPON = "l_hard_rock"
const CLASS_HP = 100.0
const CLASS_MAX_HP = 100.0
const CLASS_SPEED = 5.0
const CLASS_SPRINT_SPEED = 8.0
const CLASS_STAMINA = 80.0
const CLASS_MAX_STAMINA = 80.0
const CLASS_DASH_COST = 30.0
const CLASS_SPRINT_DRAIN = 12.0
const CLASS_EXHAUSTED_SPEED = 3.5

# Melee timing for player.gd -----------------------
const MELEE_ATTACK_SPEED = 0.7

# Mana Resource ------------------------------------
var mana = 100.0
const MAX_MANA = 100.0
const MANA_REGEN_BASE_CONST = 8.0
var mana_regen_base = MANA_REGEN_BASE_CONST
const MANA_REGEN_CIRCLE_BONUS = 15.0
const COMBAT_TIMEOUT = 2.0
var combat_timer = 0.0
var equipment_dmg_bonus = 0.0
var equipment_revive_pct = 0.0
var equipment_branded_dmg_bonus: float = 0.0
var equipment_branded_duration_extend: float = 0.0
var equipment_ult_charge_rate: float = 0.0
var equipment_skill_cdr: float = 0.0

# Branded ------------------------------------------
const BRANDED_DURATION = 5.0

# LMB: Banishment ---------------------------------
const BANISHMENT_DAMAGE = 14.0
const BANISHMENT_PUSH = 25.0
const BANISHMENT_KNOCKUP = 8.0
const BANISHMENT_RANGE = 4.0
var parry_window = false
const PARRY_WINDOW = 0.2
var post_parry_immunity = 0.0
const POST_PARRY_IMMUNITY = 2.5

# RMB: Punishment ---------------------------------
const PUNISHMENT_DAMAGE = 35.0
const PUNISHMENT_SPEED = 30.0
const PUNISHMENT_FIRE_RATE = 0.6
var punishment_cooldown = 0.0
const PROJECTILE_SCENE = preload("res://Scenes/projectile_player.tscn")
const MAGIC_CIRCLE_TEXTURE = preload("res://Assets/Objects/magic circle prototype.png")

# Q: Denouncement ---------------------------------
const DENOUNCE_DURATION = 5.0
const DENOUNCE_COOLDOWN = 16.0
var denounce_cooldown = 0.0
const DENOUNCE_SLOW = 0.4
const DENOUNCE_RADIUS = 5.0
var denounce_circle = null
var is_in_own_circle = false

# E: Judgement ------------------------------------
var judgement_charges = 0.0
const JUDGEMENT_MAX_CHARGES = 100.0
const JUDGEMENT_CHARGE_RATE = 5.0
const JUDGEMENT_CHARGE_BONUS = 0.35
const JUDGEMENT_STUN_DURATION = 5.0
const JUDGEMENT_RADIUS = 10.0
const JUDGEMENT_DELAY = 3.0

# References --------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var mana_label: Label
var skill_label: Label
var ult_label: Label

func _ready():
	player = get_parent()
	add_to_group("class_stats")
	while player.get_child_count() == 0 or not player.has_node("Camera3D"):
		await get_tree().process_frame
	camera = player.get_node("Camera3D")
	mana_label = player.get_node("HUD/FocusLabel")
	skill_label = player.get_node("HUD/SkillCooldown")
	ult_label = player.get_node("HUD/UltCooldown")

func process_class(delta: float) -> void:
	mana_label.text = "Mana: " + str(round(mana)) + "/" + str(MAX_MANA)
	skill_label.text = "Skill: Ready" if denounce_cooldown <= 0 else "Skill: " + str(snapped(denounce_cooldown, 0.1)) + "s"
	if judgement_charges >= JUDGEMENT_MAX_CHARGES:
		ult_label.text = "Ult: READY"
	else:
		ult_label.text = "Ult: " + str(round(judgement_charges)) + "/" + str(JUDGEMENT_MAX_CHARGES)

	if combat_timer > 0:
		combat_timer = max(combat_timer - delta, 0.0)

	if denounce_circle and is_instance_valid(denounce_circle):
		is_in_own_circle = player.global_position.distance_to(denounce_circle.global_position) <= DENOUNCE_RADIUS
	else:
		is_in_own_circle = false

	if combat_timer <= 0 or is_in_own_circle:
		mana = min(mana + mana_regen_base * delta, MAX_MANA)
	if is_in_own_circle:
		mana = min(mana + MANA_REGEN_CIRCLE_BONUS * delta, MAX_MANA)

	judgement_charges = min(judgement_charges + _get_judgement_charge_rate() * delta, JUDGEMENT_MAX_CHARGES)
	punishment_cooldown = max(punishment_cooldown - delta, 0.0)
	denounce_cooldown = max(denounce_cooldown - delta, 0.0)
	post_parry_immunity = max(post_parry_immunity - delta, 0.0)
	if player.melee_timer > 0:
		var hit_threshold = player.melee_attack_speed * (1.0 - 0.425)
		var time_before_hit = player.melee_timer - hit_threshold
		parry_window = time_before_hit > -0.15 and time_before_hit <= PARRY_WINDOW
	else:
		parry_window = false

func _get_judgement_charge_rate() -> float:
	var circle_bonus = JUDGEMENT_CHARGE_BONUS if is_in_own_circle else 0.0
	return JUDGEMENT_CHARGE_RATE * (1.0 + circle_bonus + equipment_ult_charge_rate / 100.0)

# LMB: Banishment ---------------------------------
func melee_attack() -> void:
	var space_state = player.get_world_3d().direct_space_state
	var first_unbranded: Node3D = null
	var first_branded: Node3D = null
	for body in player.get_tree().get_nodes_in_group("enemies"):
		var to_enemy = body.global_position - player.global_position
		var distance = to_enemy.length()
		if distance > BANISHMENT_RANGE:
			continue
		var angle = rad_to_deg(to_enemy.normalized().angle_to(-player.global_transform.basis.z))
		if angle > 120.0 / 2:
			continue
		var ray_query = PhysicsRayQueryParameters3D.create(player.global_position, body.global_position, 2)
		var result = space_state.intersect_ray(ray_query)
		if result and result.collider != body:
			continue
		combat_timer = COMBAT_TIMEOUT
		var branded_bonus = (1.0 + equipment_branded_dmg_bonus / 100.0) if body.is_in_group("branded") else 1.0
		var final_dmg = BANISHMENT_DAMAGE * player.buff_damage_mult * (1.0 + equipment_dmg_bonus / 100.0) * branded_bonus
		body.take_damage(final_dmg)
		var push_dir = (body.global_position - player.global_position).normalized()
		push_dir.y = 0.0
		body.set("impulse", Vector3.UP * BANISHMENT_KNOCKUP)
		body.set("knockback_velocity", push_dir * BANISHMENT_PUSH)
		body.set("stunned_timer", 1.2)
		if not body.is_in_group("branded") and not first_unbranded:
			first_unbranded = body
		if not first_branded:
			first_branded = body
	var brand_target = first_unbranded if first_unbranded else first_branded
	if brand_target:
		brand_target.add_to_group("branded")
		brand_target.set("branded_timer", BRANDED_DURATION + equipment_branded_duration_extend)

# RMB: Punishment ---------------------------------
func ranged_attack() -> void:
	if mana < 10.0 or punishment_cooldown > 0:
		return
	combat_timer = COMBAT_TIMEOUT
	punishment_cooldown = PUNISHMENT_FIRE_RATE
	mana -= 10.0
	var has_branded = false
	var branded: Node3D = null
	var nearest_dist = INF
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy.is_in_group("branded"):
			has_branded = true
			var d = player.global_position.distance_to(enemy.global_position)
			if d < nearest_dist:
				nearest_dist = d
				branded = enemy
	var proj = PROJECTILE_SCENE.instantiate()
	proj.damage = PUNISHMENT_DAMAGE * (1.0 + equipment_dmg_bonus / 100.0)
	proj.speed = PUNISHMENT_SPEED * 2 if has_branded else PUNISHMENT_SPEED
	player.get_tree().root.add_child(proj)
	var viewport_size = player.get_viewport().get_visible_rect().size
	var screen_center = viewport_size / 2
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_dir = camera.project_ray_normal(screen_center)
	proj.global_transform.basis = camera.global_transform.basis
	proj.global_position = ray_origin + ray_dir * 0.3
	if branded:
		proj.homing_target = branded
	proj.launch(ray_dir)

# Q: Denouncement ---------------------------------
func skill() -> void:
	if mana < 30.0 or denounce_cooldown > 0:
		return
	denounce_cooldown = DENOUNCE_COOLDOWN * (1.0 - equipment_skill_cdr / 100.0)
	mana -= 30.0
	if denounce_circle and is_instance_valid(denounce_circle):
		denounce_circle.queue_free()
	denounce_circle = Area3D.new()
	denounce_circle.name = "DenounceCircle"
	denounce_circle.collision_mask = 8
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = DENOUNCE_RADIUS
	shape.height = 3.0
	collision.shape = shape
	denounce_circle.add_child(collision)
	_add_circle_visual(denounce_circle, DENOUNCE_RADIUS)
	denounce_circle.body_entered.connect(_on_denounce_entered)
	denounce_circle.body_exited.connect(_on_denounce_exited)
	player.get_tree().current_scene.add_child(denounce_circle)
	denounce_circle.global_position = player.global_position
	await get_tree().create_timer(DENOUNCE_DURATION).timeout
	if denounce_circle and is_instance_valid(denounce_circle):
		denounce_circle.queue_free()
		denounce_circle = null

func _on_denounce_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		var current = body.get("speed_multiplier")
		if current != null:
			body.set("speed_multiplier", current * (1.0 - DENOUNCE_SLOW))

func _on_denounce_exited(body: Node) -> void:
	if body.is_in_group("enemies"):
		var current = body.get("speed_multiplier")
		if current != null:
			body.set("speed_multiplier", current / (1.0 - DENOUNCE_SLOW))

# E: Judgement ------------------------------------
func ult() -> void:
	if judgement_charges < JUDGEMENT_MAX_CHARGES or mana < 50.0:
		return
	mana -= 50.0
	judgement_charges = 0.0
	combat_timer = COMBAT_TIMEOUT
	var aerial = Area3D.new()
	aerial.name = "JudgementCircle"
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = JUDGEMENT_RADIUS
	shape.height = 1.0
	collision.shape = shape
	aerial.add_child(collision)
	_add_circle_visual(aerial, JUDGEMENT_RADIUS)
	player.get_tree().current_scene.add_child(aerial)
	aerial.global_position = player.global_position + Vector3.UP * 5.0
	await get_tree().create_timer(JUDGEMENT_DELAY).timeout
	if not is_instance_valid(aerial):
		return
	var affected = []
	var stored_speeds = {}
	for body in player.get_tree().get_nodes_in_group("enemies"):
		if aerial.global_position.distance_to(body.global_position) <= JUDGEMENT_RADIUS:
			body.add_to_group("branded")
			body.set("branded_timer", JUDGEMENT_STUN_DURATION)
			var stored = body.get("speed_multiplier")
			if stored != null:
				stored_speeds[body] = stored
				body.set("speed_multiplier", 0.0)
				body.set("stunned_timer", 2.0)
				body.set("disengage_timer", JUDGEMENT_STUN_DURATION)
				affected.append(body)
	await get_tree().create_timer(JUDGEMENT_STUN_DURATION).timeout
	for body in affected:
		if is_instance_valid(body):
			var current = body.get("speed_multiplier")
			if current == 0.0:
				body.set("speed_multiplier", stored_speeds.get(body, 1.0))
	aerial.queue_free()

# Status Effects ----------------------------------
func on_take_damage(_amount: float) -> void:
	combat_timer = COMBAT_TIMEOUT

func _add_circle_visual(parent: Node3D, radius: float) -> void:
	var sprite = Sprite3D.new()
	sprite.texture = MAGIC_CIRCLE_TEXTURE
	sprite.centered = true
	sprite.billboard = false
	sprite.rotation.x = -PI / 2
	var tex_size = sprite.texture.get_size()
	sprite.pixel_size = (radius * 2.0) / tex_size.x
	parent.add_child(sprite)

# Equipment effects --------------------------------
func _on_equipment_changed():
	var eq = player.equipment_effects if player else {}
	mana_regen_base = MANA_REGEN_BASE_CONST * (1.0 + eq.get("mana_regen_pct", 0.0) / 100.0)
	equipment_dmg_bonus = eq.get("dmg_bonus_pct", 0.0)
	equipment_revive_pct = eq.get("revive_pct", 0.0)
	equipment_branded_dmg_bonus = eq.get("branded_dmg_bonus_pct", 0.0)
	equipment_branded_duration_extend = eq.get("branded_duration_extend", 0.0)
	equipment_ult_charge_rate = eq.get("ult_charge_rate_pct", 0.0)
	equipment_skill_cdr = eq.get("skill_cooldown_reduction_pct", 0.0)
	if eq.get("move_speed_pct", 0.0) != 0.0:
		player.speed = CLASS_SPEED * (1.0 + eq.get("move_speed_pct", 0.0) / 100.0)
	else:
		player.speed = CLASS_SPEED


func should_revive() -> bool:
	var eq = player.equipment_effects if player else {}
	var roll = randf() * 100.0
	var chance = eq.get("revive_pct", 0.0)
	if chance > 0 and roll <= chance:
		player.hp = player.max_hp * 0.25
		return true
	return false


func get_dash_stamina_cost() -> float:
	return CLASS_DASH_COST

func get_sprint_stamina_drain() -> float:
	return CLASS_SPRINT_DRAIN

func is_invincible() -> bool:
	return parry_window or post_parry_immunity > 0

func on_parry_success() -> void:
	parry_window = false
	post_parry_immunity = POST_PARRY_IMMUNITY
	print("Parry successful — 2.5s immunity")

func melee_windup() -> void:
	pass

func melee_follow_through() -> void:
	pass
