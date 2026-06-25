extends Node

# Vessel Stats (applied to Player on select) -------
const RIGHT_WEAPON = "r_hard_rock"
const LEFT_WEAPON = "l_hard_rock"

const CLASS_HP = 120.0
const CLASS_MAX_HP = 120.0
const CLASS_SPEED = 5.0
const CLASS_SPRINT_SPEED = 8.0
const CLASS_STAMINA = 100.0
const CLASS_MAX_STAMINA = 100.0
const CLASS_DASH_COST = 30.0
const CLASS_SPRINT_DRAIN = 12.0
const CLASS_EXHAUSTED_SPEED = 3.5

# Melee timing --------------------------------------
const MELEE_ATTACK_SPEED = 0.8
const MELEE_CONSUMED_SPEED = 0.4

# Influence Resource --------------------------------
var influence = 0.0
const MAX_INFLUENCE = 100.0
const INFLUENCE_PASSIVE_DELAY = 3.0
const INFLUENCE_DECAY_RATE = 15.0
var passive_timer = 0.0

# Berserk & Consumed --------------------------------
const INFLUENCE_DAMAGE_FLAT = 10.0
const BERSERK_THRESHOLD = 80.0
const BERSERK_DAMAGE_MULT = 1.5
const CONSUMED_DAMAGE_TAKEN_MULT = 3.0
const CONSUMED_COOLDOWN_MULT = 1.5
const CONSUMED_DURATION = 5.0
const CONSUMED_DECAY_TARGET = 50.0
const CONSUMED_DECAY_RATE = 10.0
var is_berserk = false
var is_consumed = false
var is_consumed_active = false
var consumed_timer = 0.0
var is_consumed_decaying = false

# LMB: Feral Swing ----------------------------------
const FERAL_DAMAGE = 25.0
const FERAL_DAMAGE_CONSUMED = 35.0
const FERAL_RANGE = 3.0
const FERAL_ANGLE = 120.0
const FERAL_PUSH = 15.0
const FERAL_PUSH_CONSUMED = 25.0

# RMB: Outburst -------------------------------------
const OUTBURST_DAMAGE = 45.0
const OUTBURST_RANGE = 8.0
const OUTBURST_ANGLE = 60.0
const OUTBURST_HP_COST = 0.0
const OUTBURST_PUSH = 50.0
var outburst_timer = 0.0
const OUTBURST_FIRE_RATE = 3.0

# Q: Roar -------------------------------------------
const ROAR_DAMAGE = 0.0
const ROAR_RADIUS = 10.0
const ROAR_HP_COST = 0.0
const ROAR_COOLDOWN = 15.0
const ROAR_SLOW = 0.15
const ROAR_SLOW_DURATION = 3.0
const ROAR_LIFESTEAL_DURATION = 3.0
const ROAR_LIFESTEAL_PCT = 0.8
var roar_cooldown = 0.0
var lifesteal_timer = 0.0

# E: Bloom / Inner Strength -------------------------
const BLOOM_HP_COST = 0.20
const BLOOM_INFLUENCE_FLAT = 20.0
const BLOOM_INFLUENCE_PCT = 0.20
const BLOOM_COOLDOWN = 1.5
var bloom_cooldown = 0.0

const INNER_STRENGTH_DAMAGE = 40.0
const INNER_STRENGTH_CHARGE_TIME = 3.5
const INNER_STRENGTH_COOLDOWN = 60.0
const INNER_STRENGTH_RADIUS = 8.0
const INNER_STRENGTH_KNOCKUP = 20.0
var is_charging_inner_strength = false
var inner_strength_timer = 0.0
var inner_strength_cooldown = 0.0

# Shift: Rampage ------------------------------------
const RAMPAGE_DAMAGE = 15.0
const RAMPAGE_DURATION = 0.35
const RAMPAGE_PUSH = 12.0
const RAMPAGE_HIT_RANGE = 2.0
var rampage_hit: Array[Node] = []

# HUD references ------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var influence_label: Label
var skill_label: Label
var ult_label: Label


func _ready():
	player = get_parent()
	add_to_group("class_stats")
	while player.get_child_count() == 0 or not player.has_node("Camera3D"):
		await get_tree().process_frame
	camera = player.get_node("Camera3D")
	influence_label = player.get_node("HUD/FocusLabel")
	skill_label = player.get_node("HUD/SkillCooldown")
	ult_label = player.get_node("HUD/UltCooldown")
	# Connect to enemy deaths for Influence on kill
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_killed)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemies") and node.has_signal("died"):
		node.died.connect(_on_enemy_killed)


func process_class(delta: float) -> void:
	# Update cooldowns -------------------------------
	if outburst_timer > 0:
		outburst_timer -= delta
	if roar_cooldown > 0:
		roar_cooldown -= delta
	if bloom_cooldown > 0:
		bloom_cooldown -= delta
	if inner_strength_cooldown > 0:
		inner_strength_cooldown -= delta
	if lifesteal_timer > 0:
		lifesteal_timer -= delta

	# Inner Strength charging ------------------------
	if is_charging_inner_strength:
		player.velocity = Vector3.ZERO
		inner_strength_timer -= delta
		if inner_strength_timer <= 0:
			is_charging_inner_strength = false
			inner_strength_cooldown = INNER_STRENGTH_COOLDOWN
			for body in player.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(body):
					continue
				if body.is_on_floor() and player.global_position.distance_to(body.global_position) <= INNER_STRENGTH_RADIUS:
					body.take_damage(_get_damage(INNER_STRENGTH_DAMAGE))
					body.set("impulse", Vector3.UP * INNER_STRENGTH_KNOCKUP)
				body.set("stunned_timer", 1.5)
			print("Vessel: Inner Strength unleashed")

	# Passive decay (paused during forced decay) -----
	if not is_consumed_decaying and not is_charging_inner_strength:
		passive_timer += delta
		if passive_timer >= INFLUENCE_PASSIVE_DELAY:
			influence = max(influence - INFLUENCE_DECAY_RATE * delta, 0.0)

	# Consumed state machine -------------------------
	is_berserk = influence >= BERSERK_THRESHOLD and influence < MAX_INFLUENCE

	if influence >= MAX_INFLUENCE and not is_consumed:
		is_consumed = true
		is_consumed_active = true
		consumed_timer = CONSUMED_DURATION
		is_consumed_decaying = false
		print("Vessel: Consumed — 5s active window")

	if is_consumed_active:
		consumed_timer -= delta
		if consumed_timer <= 0:
			is_consumed_active = false
			is_consumed_decaying = true
			print("Vessel: Consumed decay phase — effects off, draining to ", CONSUMED_DECAY_TARGET)

	if is_consumed_decaying:
		influence = max(influence - CONSUMED_DECAY_RATE * delta, CONSUMED_DECAY_TARGET)
		if influence <= CONSUMED_DECAY_TARGET:
			is_consumed = false
			is_consumed_decaying = false
			print("Vessel: Consumed fully ended")

	# Update melee speed for Consumed ----------------
	player.melee_attack_speed = MELEE_CONSUMED_SPEED if is_consumed_active else MELEE_ATTACK_SPEED

	# Rampage contact damage during dash -------------
	if player.is_dashing:
		for body in player.get_tree().get_nodes_in_group("enemies"):
			if body in rampage_hit:
				continue
			if player.global_position.distance_to(body.global_position) <= RAMPAGE_HIT_RANGE:
				body.take_damage(_get_damage(RAMPAGE_DAMAGE))
				var push_dir = (body.global_position - player.global_position).normalized()
				push_dir.y = 0.0
				body.set("impulse", Vector3.UP * 8.0)
				body.set("knockback_velocity", push_dir * RAMPAGE_PUSH)
				body.set("stunned_timer", 0.8)
				rampage_hit.append(body)
	else:
		rampage_hit.clear()

	# HUD -------------------------------------------
	influence_label.text = "Influence: " + str(round(influence)) + "/" + str(MAX_INFLUENCE)
	skill_label.text = "Skill: Ready" if roar_cooldown <= 0 else "Skill: " + str(snapped(roar_cooldown, 0.1)) + "s"
	if is_charging_inner_strength:
		ult_label.text = "Ult: Charging..."
	elif not _can_gain_influence() or is_consumed:
		ult_label.text = "Ult: DISABLED"
	elif inner_strength_cooldown > 0:
		ult_label.text = "Ult: " + str(snapped(inner_strength_cooldown, 0.1)) + "s"
	elif influence >= BERSERK_THRESHOLD:
		ult_label.text = "Ult: Inner Strength"
	else:
		ult_label.text = "Ult: Ready" if bloom_cooldown <= 0 else "Ult: " + str(snapped(bloom_cooldown, 0.1)) + "s"


# LMB: Feral Swing ----------------------------------
func melee_attack() -> void:
	var dmg = _get_damage(FERAL_DAMAGE_CONSUMED if is_consumed_active else FERAL_DAMAGE)
	var push = FERAL_PUSH_CONSUMED if is_consumed_active else FERAL_PUSH
	var space_state = player.get_world_3d().direct_space_state
	for body in player.get_tree().get_nodes_in_group("enemies"):
		var to_enemy = body.global_position - player.global_position
		var distance = to_enemy.length()
		if distance > FERAL_RANGE:
			continue
		var angle = rad_to_deg(to_enemy.normalized().angle_to(-player.global_transform.basis.z))
		if angle > FERAL_ANGLE / 2:
			continue
		var ray_query = PhysicsRayQueryParameters3D.create(player.global_position, body.global_position, 2)
		var result = space_state.intersect_ray(ray_query)
		if result and result.collider != body:
			continue
		body.take_damage(dmg)
		var push_dir = (body.global_position - player.global_position).normalized()
		push_dir.y = 0.0
		body.set("knockback_velocity", push_dir * push)
		# Lifesteal during Roar buff
		if lifesteal_timer > 0:
			var heal = (player.max_hp - player.hp) * ROAR_LIFESTEAL_PCT
			player.hp = min(player.hp + heal, player.max_hp)
			influence = max(influence - heal * 0.6, 0.0)


# RMB: Outburst -------------------------------------
func ranged_attack() -> void:
	if outburst_timer > 0:
		return
	var fire_rate = _get_cooldown(OUTBURST_FIRE_RATE)
	player.ranged_animation(fire_rate)
	outburst_timer = fire_rate
	var space_state = player.get_world_3d().direct_space_state
	var cam_pos = camera.global_position
	var cam_forward = -camera.global_transform.basis.z
	for body in player.get_tree().get_nodes_in_group("enemies"):
		var to_enemy = body.global_position - cam_pos
		var distance = to_enemy.length()
		if distance > OUTBURST_RANGE:
			continue
		var angle = rad_to_deg(to_enemy.normalized().angle_to(cam_forward))
		if angle > OUTBURST_ANGLE / 2:
			continue
		var ray_query = PhysicsRayQueryParameters3D.create(cam_pos, body.global_position, 2)
		var result = space_state.intersect_ray(ray_query)
		if result and result.collider != body:
			continue
		body.take_damage(_get_damage(OUTBURST_DAMAGE))
		var push_dir = (body.global_position - player.global_position).normalized()
		push_dir.y = 0.0
		body.set("knockback_velocity", push_dir * OUTBURST_PUSH)
		body.set("stunned_timer", 0.8)
		if lifesteal_timer > 0:
			var heal = (player.max_hp - player.hp) * ROAR_LIFESTEAL_PCT
			player.hp = min(player.hp + heal, player.max_hp)
			influence = max(influence - heal * 0.6, 0.0)


# Q: Roar -------------------------------------------
func skill() -> void:
	if roar_cooldown > 0:
		return
	roar_cooldown = _get_cooldown(ROAR_COOLDOWN)
	var slowed: Array[Node] = []
	var stored_speeds: Dictionary = {}
	for body in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(body):
			continue
		if player.global_position.distance_to(body.global_position) <= ROAR_RADIUS:
			var s = body.get("speed_multiplier")
			if s != null:
				body.set("speed_multiplier", s * (1.0 - ROAR_SLOW))
				slowed.append(body)
				stored_speeds[body] = s
	lifesteal_timer = ROAR_LIFESTEAL_DURATION
	await get_tree().create_timer(ROAR_SLOW_DURATION).timeout
	for body in slowed:
		if is_instance_valid(body):
			var s = stored_speeds.get(body)
			if s != null:
				body.set("speed_multiplier", s)


# E: Bloom / Inner Strength ------------------------
func ult() -> void:
	if is_charging_inner_strength:
		return
	if inner_strength_cooldown > 0:
		return
	# Inner Strength at 80+ influence
	if influence >= BERSERK_THRESHOLD and _can_gain_influence():
		if not player.is_on_floor():
			return
		is_charging_inner_strength = true
		inner_strength_timer = INNER_STRENGTH_CHARGE_TIME
		print("Vessel: Inner Strength charging — ", INNER_STRENGTH_CHARGE_TIME, "s")
		return
	# Bloom below 80 influence
	if influence >= BERSERK_THRESHOLD or bloom_cooldown > 0 or not _can_gain_influence():
		return
	var cost = player.hp * BLOOM_HP_COST
	if cost <= 0:
		return
	bloom_cooldown = _get_cooldown(BLOOM_COOLDOWN)
	var old_hp = player.hp
	player.hp = max(player.hp - cost, 0.0)
	_apply_influence(cost, old_hp)
	var lost_hp = player.max_hp - player.hp
	influence = min(influence + BLOOM_INFLUENCE_FLAT + lost_hp * BLOOM_INFLUENCE_PCT, MAX_INFLUENCE)
	_reset_passive_timer()
	print("Vessel: Bloom — Influence spiked")


# Stamina / Sprint overrides ------------------------
func get_dash_stamina_cost() -> float:
	return CLASS_DASH_COST


func get_sprint_stamina_drain() -> float:
	return CLASS_SPRINT_DRAIN


func can_sprint() -> bool:
	return not is_consumed_active


func get_dash_duration() -> float:
	return RAMPAGE_DURATION


func get_damage_taken_mult() -> float:
	return CONSUMED_DAMAGE_TAKEN_MULT if is_consumed_active else 1.0


# Status effects ------------------------------------
func on_take_damage(amount: float) -> void:
	if amount <= 0 or not _can_gain_influence():
		return
	_apply_influence(amount, player.hp + amount)
	influence = min(influence + INFLUENCE_DAMAGE_FLAT, MAX_INFLUENCE)


func on_parry_success() -> void:
	pass


func _on_enemy_killed() -> void:
	if not _can_gain_influence():
		return
	var lost_hp = player.max_hp - player.hp
	var gained = lost_hp * 0.02
	influence = min(influence + gained, MAX_INFLUENCE)
	_reset_passive_timer()


# Internal helpers ----------------------------------
func _get_damage(base: float) -> float:
	return base * BERSERK_DAMAGE_MULT if is_berserk else base


func _get_cooldown(base: float) -> float:
	return base * CONSUMED_COOLDOWN_MULT if is_consumed_active else base


func _apply_hp_cost(percent: float) -> bool:
	var cost = player.hp * percent
	if cost <= 0:
		return false
	var old_hp = player.hp
	player.hp = max(player.hp - cost, 0.0)
	_apply_influence(cost, old_hp)
	return true


func _can_gain_influence() -> bool:
	return not is_consumed_decaying


func _apply_influence(damage: float, hp_before_cost: float) -> void:
	if not _can_gain_influence():
		return
	var lost_hp = player.max_hp - hp_before_cost
	var gained = damage * 0.1 + lost_hp * 0.05
	influence = min(influence + gained, MAX_INFLUENCE)
	_reset_passive_timer()


func _reset_passive_timer() -> void:
	passive_timer = 0.0


func is_invincible() -> bool:
	return player.is_dashing


func melee_windup() -> void:
	pass


func melee_follow_through() -> void:
	pass
