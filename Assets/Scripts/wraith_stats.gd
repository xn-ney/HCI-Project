extends Node

# HUD ---------------------------------------------
@onready var focus_label = get_parent().get_node("HUD/FocusLabel")
@onready var skill_label = get_parent().get_node("HUD/SkillCooldown")
@onready var ult_label = get_parent().get_node("HUD/UltCooldown")

# Wraith Stats (applied to Player on select) ------
const RIGHT_WEAPON = "IronDagger"
const LEFT_WEAPON = "l_hard_rock"
const CLASS_HP = 80.0
const CLASS_MAX_HP = 80.0
const CLASS_SPEED = 5.0
const CLASS_SPRINT_SPEED = 8.0
const CLASS_STAMINA = 120.0
const CLASS_MAX_STAMINA = 120.0
const CLASS_DASH_COST = 25.0
const CLASS_SPRINT_DRAIN = 12.0
const CLASS_EXHAUSTED_SPEED = 3.5

# Melee timing for player.gd -----------------------
const MELEE_ATTACK_SPEED = 0.6

# Focus Resource ----------------------------------
var focus = 0.0
const MAX_FOCUS = 100.0
const FOCUS_PER_HIT_BASE = 12.5
var focus_per_hit = FOCUS_PER_HIT_BASE
const FOCUS_LOSS_RATIO_BASE = 0.5
var focus_loss_ratio = FOCUS_LOSS_RATIO_BASE
const FOCUSED_DURATION_BASE = 10.0
var focused_duration = FOCUSED_DURATION_BASE
const FOCUSED_DAMAGE_REDUCTION = 1.5
var is_focused = false
var focused_timer = 0.0
var equipment_skill_cdr: float = 0.0

# LMB: Claw ---------------------------------------
const CLAW_DAMAGE = 18.0
const CLAW_RANGE = 3.5
const CLAW_ANGLE = 120.0

# RMB: Knives -------------------------------------
const KNIFE_DAMAGE = 12.0
const KNIFE_RATE = 0.5
var knife_timer = 0.0
const PROJECTILE_SCENE = preload("res://Scenes/projectile_player.tscn")

# Q: Ravage ---------------------------------------
const RAVAGE_DAMAGE = 40.0
const RAVAGE_SPEED = 60.0
const RAVAGE_DURATION = 0.06
const RAVAGE_COOLDOWN = 4.5
const RAVAGE_STAMINA_COST = 0.0
var ravage_cooldown = 0.0
var is_ravaging = false
var ravage_time = 0.0
var ravage_dir = Vector3.ZERO
var ravage_hit: Array[Node] = []

# E: Assassinate ----------------------------------
const ASSASSINATE_COOLDOWN = 10.0
const ASSASSINATE_FOCUSED_COOLDOWN = 6.0
const ASSASSINATE_RANGE = 9.0
const ASSASSINATE_DASH_SPEED = 35.0
const ASSASSINATE_EXECUTE_PCT = 0.4
const ASSASSINATE_NORMAL_DMG = 10.0
const ASSASSINATE_BOSS_DMG = 50.0
const ASSASSINATE_AOE_RADIUS = 3.0
var assassinate_cooldown = 0.0
var is_assassinating = false
var assassinate_target: Node3D = null
var assassinate_start: Vector3

# References (set by player.gd) --------------------
var player: CharacterBody3D
var camera: Camera3D


func _ready():
	player = get_parent()
	add_to_group("class_stats")
	while player.get_child_count() == 0 or not player.has_node("Camera3D"):
		await get_tree().process_frame
	camera = player.get_node("Camera3D")


func process_class(delta: float) -> void:
	if knife_timer > 0:
		knife_timer -= delta
	if ravage_cooldown > 0:
		ravage_cooldown -= delta
	if assassinate_cooldown > 0:
		assassinate_cooldown -= delta

	focus_label.text = "Focus: " + str(round(focus)) + "/" + str(MAX_FOCUS)
	skill_label.text = "Skill: Ready" if ravage_cooldown <= 0 else "Skill: " + str(snapped(ravage_cooldown, 0.1)) + "s"
	ult_label.text = "Ult: Ready" if assassinate_cooldown <= 0 else "Ult: " + str(snapped(assassinate_cooldown, 0.1)) + "s"

	if is_focused:
		focused_timer -= delta
		var focused_speed = player.equipment_effects.get("focused_speed_pct", 0.0) if player else 0.0
		if focused_speed > 0:
			player.speed = CLASS_SPEED * (1.0 + focused_speed / 100.0)
		if focused_timer <= 0:
			is_focused = false
			focus = 0.0
			if focused_speed > 0:
				player.speed = CLASS_SPEED

	# Active: Ravage dash ------------------------
	if is_ravaging:
		ravage_time -= delta
		player.velocity = ravage_dir * RAVAGE_SPEED
		for body in player.get_tree().get_nodes_in_group("enemies"):
			if body in ravage_hit:
				continue
			if player.global_position.distance_to(body.global_position) <= 2.0:
				var dmg = RAVAGE_DAMAGE * (0.5 if player.is_exhausted else 1.0)
				body.take_damage(dmg)
				ravage_hit.append(body)
				_gain_focus()
		if ravage_time <= 0:
			is_ravaging = false
			player.velocity.y = 0
			player.set_collision_mask_value(4, true)

	# Active: Assassinate lunge ------------------
	if is_assassinating:
		if not assassinate_target or not is_instance_valid(assassinate_target):
			is_assassinating = false
			assassinate_target = null
			return
		var dir = (assassinate_target.global_position - player.global_position).normalized()
		player.velocity = dir * ASSASSINATE_DASH_SPEED
		var hit: Node3D = null
		for body in player.get_tree().get_nodes_in_group("enemies"):
			if body.hp <= 0:
				continue
			if player.global_position.distance_to(body.global_position) <= 2.0:
				hit = body
				break
		if hit or player.global_position.distance_to(assassinate_start) >= ASSASSINATE_RANGE:
			is_assassinating = false
			if hit:
				for body in player.get_tree().get_nodes_in_group("enemies"):
					if body.hp <= 0:
						continue
					if player.global_position.distance_to(body.global_position) <= ASSASSINATE_AOE_RADIUS:
						_execute_damage(body)
			assassinate_target = null


func _execute_damage(body: Node3D) -> void:
	if body.is_in_group("boss"):
		if body.hp / body.MAX_HP <= ASSASSINATE_EXECUTE_PCT:
			body.take_damage(ASSASSINATE_BOSS_DMG)
		else:
			body.take_damage(ASSASSINATE_NORMAL_DMG)
	else:
		if body.hp / body.MAX_HP <= ASSASSINATE_EXECUTE_PCT:
			body.take_damage(9999.0)
		else:
			body.take_damage(ASSASSINATE_NORMAL_DMG)


func get_assassinate_cooldown() -> float:
	var base = ASSASSINATE_FOCUSED_COOLDOWN if is_focused else ASSASSINATE_COOLDOWN
	return base * (1.0 - equipment_skill_cdr / 100.0)


# LMB: Claw ---------------------------------------
func melee_attack() -> void:
	var space_state = player.get_world_3d().direct_space_state
	for body in player.get_tree().get_nodes_in_group("enemies"):
		var to_enemy = body.global_position - player.global_position
		var distance = to_enemy.length()
		if distance > CLAW_RANGE:
			continue
		var angle = rad_to_deg(to_enemy.normalized().angle_to(-player.global_transform.basis.z))
		if angle > CLAW_ANGLE / 2:
			continue
		var ray_query = PhysicsRayQueryParameters3D.create(
			player.global_position,
			body.global_position,
			2
		)
		var result = space_state.intersect_ray(ray_query)
		if result and result.collider != body:
			continue
		var final_dmg = CLAW_DAMAGE * player.buff_damage_mult
		body.take_damage(final_dmg)
		if player.buff_lifesteal_pct > 0:
			var heal = final_dmg * player.buff_lifesteal_pct
			player.hp = min(player.hp + heal, player.max_hp)
		_gain_focus()


# RMB: Knives -------------------------------------
func ranged_attack() -> void:
	if knife_timer > 0:
		return
	var knife = PROJECTILE_SCENE.instantiate()
	knife.hit_enemy.connect(_on_knife_hit)
	player.get_tree().root.add_child(knife)
	var viewport_size = player.get_viewport().get_visible_rect().size
	var screen_center = viewport_size / 2
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_dir = camera.project_ray_normal(screen_center)
	knife.global_transform.basis = camera.global_transform.basis
	knife.global_position = ray_origin + ray_dir * 0.3
	knife.damage = KNIFE_DAMAGE
	knife.launch(ray_dir)
	knife_timer = KNIFE_RATE


# Q: Ravage ---------------------------------------
func skill() -> void:
	if ravage_cooldown > 0 or is_ravaging:
		return
	if player.stamina < RAVAGE_STAMINA_COST:
		return
	var cam_forward = -camera.global_transform.basis.z
	ravage_dir = cam_forward.normalized()
	player.stamina -= RAVAGE_STAMINA_COST
	ravage_hit.clear()
	is_ravaging = true
	ravage_time = RAVAGE_DURATION * (0.5 if player.is_exhausted else 1.0)
	player.velocity = Vector3.ZERO
	ravage_cooldown = RAVAGE_COOLDOWN * (1.0 - equipment_skill_cdr / 100.0)
	player.set_collision_mask_value(4, false)


# E: Assassinate ----------------------------------
func ult() -> void:
	if assassinate_cooldown > 0 or is_assassinating:
		return
	var space_state = player.get_world_3d().direct_space_state
	var best_body = null
	var best_distance = ASSASSINATE_RANGE
	for body in player.get_tree().get_nodes_in_group("enemies"):
		if body.hp <= 0:
			continue
		var to_enemy = body.global_position - player.global_position
		var distance = to_enemy.length()
		if distance > ASSASSINATE_RANGE:
			continue
		var angle = rad_to_deg(to_enemy.normalized().angle_to(-camera.global_transform.basis.z))
		if angle > 30.0:
			continue
		var ray_query = PhysicsRayQueryParameters3D.create(
			player.global_position,
			body.global_position,
			2
		)
		var result = space_state.intersect_ray(ray_query)
		if result and result.collider != body:
			continue
		if distance < best_distance:
			best_distance = distance
			best_body = body
	if best_body == null:
		return
	assassinate_target = best_body
	assassinate_start = player.global_position
	is_assassinating = true
	player.velocity = Vector3.ZERO
	assassinate_cooldown = get_assassinate_cooldown()


# Status Effects ----------------------------------
func on_take_damage(_amount: float) -> void:
	if is_focused:
		focused_timer -= FOCUSED_DAMAGE_REDUCTION
		if focused_timer <= 0:
			is_focused = false
			focus = 0.0
			print("Focused state broken by damage")
	else:
		focus *= 1.0 - focus_loss_ratio


func _add_focus(amount: float) -> void:
	focus += amount
	focus = min(focus, MAX_FOCUS)
	if focus >= MAX_FOCUS and not is_focused:
		is_focused = true
		focused_timer = focused_duration
		print("Focused state activated — ", focused_duration, "s")


func _gain_focus() -> void:
	_add_focus(focus_per_hit)


func _on_knife_hit(_enemy: Node3D) -> void:
	_add_focus(focus_per_hit * 0.6)


# I-Frames ----------------------------------------
func is_invincible() -> bool:
	return player.is_dashing or is_ravaging or is_assassinating


# Equipment effects --------------------------------
func _on_equipment_changed():
	var eq = player.equipment_effects if player else {}
	focus_per_hit = FOCUS_PER_HIT_BASE * (1.0 + eq.get("focus_gain_pct", 0.0) / 100.0)
	focus_loss_ratio = FOCUS_LOSS_RATIO_BASE * (1.0 - eq.get("focus_loss_reduction_pct", 0.0) / 100.0)
	focused_duration = FOCUSED_DURATION_BASE + eq.get("focused_duration_extend", 0.0)
	equipment_skill_cdr = eq.get("skill_cooldown_reduction_pct", 0.0)
	if eq.get("move_speed_pct", 0.0) != 0.0:
		player.speed = CLASS_SPEED * (1.0 + eq.get("move_speed_pct", 0.0) / 100.0)
	else:
		player.speed = CLASS_SPEED


# Stamina Overrides (called by player.gd) ----------
func get_dash_stamina_cost() -> float:
	var eq = player.equipment_effects if player else {}
	var reduction = eq.get("dash_stamina_reduction", 0.0)
	return max(0.0, (0.0 if is_focused else CLASS_DASH_COST) - reduction)


func get_sprint_stamina_drain() -> float:
	return 0.0 if is_focused else CLASS_SPRINT_DRAIN


# Melee Animation Hooks (called by player.gd) ------
func melee_windup() -> void:
	pass

func melee_follow_through() -> void:
	pass
