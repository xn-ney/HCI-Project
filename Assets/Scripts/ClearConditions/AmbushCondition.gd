class_name AmbushCondition
extends BaseCondition

# Preloads -----------------------------------------
const ENEMY_SCENES = [
	preload("res://Scenes/Enemies/fire_witch.tscn")
]

# Wave config --------------------------------------
var total_waves: int = 2
var current_wave: int = 0
var active_enemies: Array[Node] = []
var _spawn_queue: Array[PackedScene] = []
var _spawn_index: int = 0
var _spawn_stagger: float = 0.0
var _wave_time: float = 0.0

# State --------------------------------------------
var is_wave_active: bool = false
var is_finished: bool = false

# Start --------------------------------------------
func start_condition() -> void:
	player = get_tree().get_first_node_in_group("player")
	_start_wave()

# Wave management ----------------------------------
func _start_wave() -> void:
	current_wave += 1
	is_wave_active = true
	_wave_time = 0.0
	var count = randi() % 6 + 10
	_spawn_queue = []
	for i in range(count):
		_spawn_queue.append(ENEMY_SCENES[randi() % ENEMY_SCENES.size()])
	_spawn_index = 0
	_spawn_stagger = 0.0
	print("Wave ", current_wave, " — ", count, " enemies queued")

func _spawn_next() -> void:
	if _spawn_index >= _spawn_queue.size() or not player:
		return
	var enemy = _spawn_queue[_spawn_index].instantiate()
	_spawn_index += 1
	get_tree().current_scene.add_child(enemy)
	var angle = randf_range(0, TAU)
	var dist = randf_range(4.0, 8.0)
	var offset = Vector3(cos(angle), 0, sin(angle)) * dist
	enemy.global_position = player.global_position + offset + Vector3.UP
	active_enemies.append(enemy)

# Process loop -------------------------------------
func process_condition(delta: float) -> void:
	if not is_wave_active or is_finished:
		return

	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))
	_wave_time += delta

	if _spawn_index < _spawn_queue.size():
		_spawn_stagger -= delta
		if _spawn_stagger <= 0:
			_spawn_next()
			_spawn_stagger = randf_range(0.3, 0.8)

	if active_enemies.is_empty() or _wave_time >= 30.0:
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
	return float(current_wave - 1) / float(total_waves)
