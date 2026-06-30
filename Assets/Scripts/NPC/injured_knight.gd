extends CharacterBody3D

class_name EscortNPC

# Stats
var hp: float = 500.0
var melee_timer: float = 0.0
var swing_timer: float = 0.0

# Config (adjust these) ---------------------------------
const MAX_HP = 500.0
const SPEED = 1.5
const MELEE_RANGE = 3.5
const MELEE_DAMAGE = 15.0
const MELEE_COOLDOWN = 3.8
const INTERACT_RADIUS = 3.0
const ESCORT_DETECT_RANGE = 15.0

# State
var is_treated: bool = false
var is_moving: bool = false
var exit_target: Node3D = null
var bandage_ready: bool = false
var combat_timer: float = 0.0

# Interaction
var player_in_range: bool = false

# HP label
var hp_label: Label3D = null

# Signals
signal died()
signal reached_exit()
signal treated()


func _ready():
	add_to_group("npcs")
	add_to_group("escort_npc")
	_find_exit_target()
	_ensure_collision_shape()

	var interaction_area = get_node_or_null("InteractionArea")
	if not interaction_area:
		interaction_area = Area3D.new()
		interaction_area.name = "InteractionArea"
		var shape = CollisionShape3D.new()
		shape.shape = SphereShape3D.new()
		shape.shape.radius = INTERACT_RADIUS
		interaction_area.add_child(shape)
		add_child(interaction_area)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	var prompt = get_node_or_null("InteractionPrompt")
	if not prompt:
		prompt = Label3D.new()
		prompt.name = "InteractionPrompt"
		prompt.text = ""
		prompt.visible = false
		prompt.position = Vector3(0, 3.0, 0)
		prompt.pixel_size = 0.02
		prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(prompt)

	_setup_hp_label()
	_setup_enemy_detector()


func _setup_hp_label():
	hp_label = Label3D.new()
	hp_label.name = "HPLabel"
	hp_label.text = str(round(hp))
	hp_label.position = Vector3(0, 3.8, 0)
	hp_label.pixel_size = 0.015
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hp_label)


func _setup_enemy_detector():
	var detector = Area3D.new()
	detector.name = "EnemyDetector"
	detector.collision_mask = 8
	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = ESCORT_DETECT_RANGE
	detector.add_child(shape)
	add_child(detector)
	detector.body_entered.connect(_on_enemy_detected)


func _on_enemy_detected(body: Node):
	if not EscortCondition.is_active:
		return
	if not body.has_method("switch_to_npc_target"):
		return
	if randf() < EscortCondition.npc_target_chance:
		body.switch_to_npc_target(self)


func _find_exit_target():
	var exits = get_tree().get_nodes_in_group("exit_point")
	if exits.size() > 0:
		exit_target = exits[0] as Node3D
		return
	for node in get_tree().get_nodes_in_group("fence"):
		exit_target = node as Node3D
		return
	for candidate in ["Exit", "Gate", "Fence", "Finish"]:
		var found = get_tree().get_first_node_in_group(candidate.to_lower())
		if found:
			exit_target = found as Node3D
			return
	if not exit_target:
		var world = get_tree().current_scene
		if world:
			for child in world.get_children():
				var name_lower = child.name.to_lower()
				if "exit" in name_lower or "gate" in name_lower or "fence" in name_lower:
					exit_target = child as Node3D
					if exit_target:
						return
	if not exit_target:
		push_error("No exit target found for knight. Add a node to the 'exit_point' group.")


func _ensure_collision_shape():
	for child in get_children():
		if child is CollisionShape3D:
			return
	var cs = CollisionShape3D.new()
	cs.name = "KnightHitbox"
	cs.shape = CapsuleShape3D.new()
	cs.shape.height = 2.0
	cs.shape.radius = 0.5
	add_child(cs)


func start_escort():
	is_treated = true
	is_moving = true
	treated.emit()
	var prompt = $InteractionPrompt
	if prompt:
		prompt.text = ""
		prompt.visible = false


func take_damage(amount: float):
	combat_timer = 3.0
	hp -= amount
	if hp_label:
		hp_label.text = str(round(hp))
	if hp <= 0:
		died.emit()


func _physics_process(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

	if not is_treated and player_in_range and Input.is_action_just_pressed("interact"):
		if bandage_ready:
			start_escort()

	combat_timer = max(0, combat_timer - delta)

	var nearby_enemies: Array[Node] = []
	for body in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(body.global_position) <= MELEE_RANGE:
			nearby_enemies.append(body)

	melee_timer -= delta
	if melee_timer <= 0 and nearby_enemies:
		nearby_enemies[0].take_damage(MELEE_DAMAGE)
		melee_timer = MELEE_COOLDOWN
		swing_timer = 1

	swing_timer = max(0, swing_timer - delta)

	if is_moving and exit_target and swing_timer <= 0:
		var speed = SPEED * (0.5 if nearby_enemies else 1.0)
		var dir = (exit_target.global_position - global_position).normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

		if global_position.distance_to(exit_target.global_position) <= 2.0:
			is_moving = false
			velocity.x = 0
			velocity.z = 0
			reached_exit.emit()
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		if not is_treated:
			var prompt = $InteractionPrompt
			if prompt:
				prompt.text = "Press 'F' to treat" if bandage_ready else "Find bandage"
				prompt.visible = true


func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		var prompt = $InteractionPrompt
		if prompt:
			prompt.text = ""
			prompt.visible = false
