class_name EscortCondition
extends BaseCondition

const NPC_SCENE_PATH = "res://Scenes/NPC/InjuredKnight.tscn"
const ENEMY_SCENES = [
	preload("res://Scenes/Enemies/orc.tscn"),
]

# Bandage -------------------------------------------------
static var player_has_bandage: bool = false

# Spawn config --------------------------------------------
const SPAWN_MAX_FAR = 5.0
const SPAWN_MIN_NEAR_GATE = 1.0

# Phase enum ----------------------------------------------
enum Phase { SEARCHING, ESCORTING, DEFEND, DONE }
var phase: int = Phase.SEARCHING

# State ---------------------------------------------------
var npc: EscortNPC = null
var bandage_carrier: Node = null
var is_finished: bool = false
var progress: float = 0.0
var total_distance: float = 0.0
var spawn_timer: float = 0.0
var active_enemies: Array[Node] = []
var progress_label: Label = null
var spawn_points: Array[Node3D] = []

# Static target for enemy detection -----------------------
static var is_active: bool = false
static var escort_target: Node3D = null
static var npc_target_chance: float = 0.4
static var spawnchase_enabled: bool = false


func start_condition() -> void:
	player_has_bandage = false
	escort_target = null
	is_active = true

	var nodes = get_tree().get_nodes_in_group("spawn_points")
	for n in nodes:
		spawn_points.append(n as Node3D)
	if spawn_points.is_empty():
		print("No spawn points found")

	player = get_tree().get_first_node_in_group("player")
	_spawn_npc()
	_spawn_initial_enemies()


func _spawn_npc() -> void:
	var existing = get_tree().get_first_node_in_group("escort_npc")
	if existing:
		npc = existing
		escort_target = npc
		npc.treated.connect(_on_npc_treated)
		npc.died.connect(_on_npc_died)
		npc.reached_exit.connect(_on_npc_reached_exit)
		print("Found existing knight in scene")
		return

	if spawn_points.is_empty():
		return
	var furthest = _get_furthest_from_player()
	if not ResourceLoader.exists(NPC_SCENE_PATH):
		push_error("EscortCondition: NPC scene not found at ", NPC_SCENE_PATH)
		return
	npc = load(NPC_SCENE_PATH).instantiate()
	escort_target = npc
	get_tree().current_scene.add_child(npc)
	npc.global_position = furthest.global_position + Vector3.UP
	npc.treated.connect(_on_npc_treated)
	npc.died.connect(_on_npc_died)
	npc.reached_exit.connect(_on_npc_reached_exit)



func _get_furthest_from_player() -> Marker3D:
	var best = spawn_points[0]
	var best_dist = 0.0
	var ppos = player.global_position if player else Vector3.ZERO
	for sp in spawn_points:
		var d = sp.global_position.distance_squared_to(ppos)
		if d > best_dist:
			best_dist = d
			best = sp
	return best


func _spawn_initial_enemies() -> void:
	var existing = get_tree().get_nodes_in_group("enemies")
	if existing.is_empty():
		var count = randi() % 4 + 9
		for i in range(count):
			var enemy = _spawn_enemy()
			if i == 0 and enemy:
				_mark_bandage_carrier(enemy)
	else:
		_mark_bandage_carrier(existing[randi() % existing.size()])


func _mark_bandage_carrier(enemy: Node) -> void:
	bandage_carrier = enemy
	if enemy.has_method("add_to_group"):
		enemy.add_to_group("bandage_carrier")
	var label = enemy.get_node_or_null("NameLabel") as Label3D
	if label:
		label.text = "Bandage Carrier"
	if not enemy.died.is_connected(_on_bandage_carrier_died):
		enemy.died.connect(_on_bandage_carrier_died)


func _on_bandage_carrier_died() -> void:
	player_has_bandage = true
	print("Bandage acquired")
	if npc and is_instance_valid(npc):
		npc.bandage_ready = true
		_update_npc_prompt()


func _update_npc_prompt() -> void:
	if not npc or not is_instance_valid(npc):
		return
	var prompt = npc.get_node_or_null("InteractionPrompt") as Label3D
	if prompt and npc.player_in_range:
		prompt.text = "Press F to treat"
		prompt.visible = true


func _on_npc_treated() -> void:
	print("Knight treated — escort begins")
	phase = Phase.ESCORTING
	npc_target_chance = 0.4
	spawnchase_enabled = true
	spawn_timer = randf_range(SPAWN_MAX_FAR * 0.5, SPAWN_MAX_FAR)
	if player:
		progress_label = player.get_node_or_null("HUD/CleanseProgressLabel")
	if npc.exit_target:
		total_distance = npc.global_position.distance_to(npc.exit_target.global_position)
		progress = 0.0


func _on_npc_died() -> void:
	print("Knight died — defend phase")
	escort_target = null
	phase = Phase.DEFEND
	print("  active_enemies count: ", active_enemies.size())


func _on_npc_reached_exit() -> void:
	print("Knight reached exit — defend phase")
	escort_target = null
	phase = Phase.DEFEND


func process_condition(delta: float) -> void:
	if phase == Phase.DONE:
		return

	match phase:
		Phase.SEARCHING:
			pass

		Phase.ESCORTING:
			if not npc or not is_instance_valid(npc):
				print("  ESCORTING: npc invalid (is_instance_valid=false), treating as died")
				_on_npc_died()
				return
			if npc.exit_target:
				var dist = npc.global_position.distance_to(npc.exit_target.global_position)
				progress = 1.0 - (dist / total_distance) if total_distance > 0 else 0.0
				npc_target_chance = 0.4 + progress * 0.5
			if progress_label:
				progress_label.text = "Escort: %d%%" % (progress * 100)
			_spawn_loop(delta)

		Phase.DEFEND:
			if progress_label:
				progress_label.text = "Defend!"
			var remaining = get_tree().get_nodes_in_group("enemies")
			if remaining.is_empty():
				is_active = false
				phase = Phase.DONE
				is_finished = true
				if progress_label:
					progress_label.text = ""
				print("Escort complete")


func _spawn_loop(delta: float) -> void:
	active_enemies = active_enemies.filter(func(e):
		return is_instance_valid(e)
	)
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_enemy()
		var interval = lerp(SPAWN_MAX_FAR, SPAWN_MIN_NEAR_GATE, progress)
		var jitter = interval * 0.25
		spawn_timer = randf_range(interval - jitter, interval + jitter)


func _spawn_enemy() -> Node:
	if spawn_points.is_empty():
		return null
	var spawn: Node3D = spawn_points[randi() % spawn_points.size()]
	var enemy = ENEMY_SCENES[randi() % ENEMY_SCENES.size()].instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn.global_position + Vector3.UP + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	active_enemies.append(enemy)
	return enemy


func is_complete() -> bool:
	return is_finished


func get_progress() -> float:
	return progress
