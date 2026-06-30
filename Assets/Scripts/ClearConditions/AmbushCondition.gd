class_name AmbushCondition
extends BaseCondition

# Preloads -----------------------------------------
const ENEMY_SCENES = [
	preload("res://Scenes/Enemies/orc.tscn"),
]

# Wave config --------------------------------------
var total_waves: int = 2
var current_wave: int = 0
var wave_duration: float = 60.0
var wave_timer: float = 0.0
var enemies_per_wave: Array[int] = [6, 6]
var active_enemies: Array[Node] = []

# State --------------------------------------------
var is_wave_active: bool = false
var is_finished: bool = false
var spawn_points: Array[Node3D] = []

# Start --------------------------------------------
func start_condition() -> void:
	var nodes = get_tree().get_nodes_in_group("spawn_points")
	for n in nodes:
		spawn_points.append(n as Node3D)
	if spawn_points.is_empty():
		print("No spawn points found — add Marker3D nodes to group 'spawn_points'")
	player = get_tree().get_first_node_in_group("player")
	_start_wave()

# Wave management ----------------------------------
func _start_wave() -> void:
	current_wave += 1
	is_wave_active = true
	wave_timer = wave_duration
	var count = enemies_per_wave[current_wave - 1] if current_wave <= enemies_per_wave.size() else 5
	for i in range(count):
		_spawn_enemy()
	print("Wave ", current_wave, " — ", count, " enemies")

func _spawn_enemy() -> void:
	if spawn_points.is_empty():
		return
	var spawn: Node3D = spawn_points[randi() % spawn_points.size()]
	var enemy = ENEMY_SCENES[randi() % ENEMY_SCENES.size()].instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn.global_position + Vector3.UP
	active_enemies.append(enemy)

# Process loop -------------------------------------
func process_condition(delta: float) -> void:
	if not is_wave_active or is_finished:
		return

	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))
	wave_timer -= delta

	if active_enemies.is_empty() or wave_timer <= 0:
		is_wave_active = false
		if current_wave >= total_waves:
			is_finished = true
			print("Ambush complete")
		else:
			_start_wave()

# Status queries -----------------------------------
func is_complete() -> bool:
	return is_finished

func get_progress() -> float:
	if current_wave == 0:
		return 0.0
	return (current_wave - 1 + (1.0 - wave_timer / wave_duration)) / float(total_waves)
