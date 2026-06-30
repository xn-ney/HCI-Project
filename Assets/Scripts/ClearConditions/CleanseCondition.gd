class_name CleanseCondition
extends BaseCondition

const ENEMY_SCENES = [
	preload("res://Scenes/Enemies/orc.tscn"),
]

const CIRCLE_LIFETIME = 15.0
const CIRCLE_RADIUS = 10.0
const CIRCLE_HEIGHT = 4.0
const FILL_TIME = 40.0
const DECAY_RATE = 0.02
const PENALTY_PER_ENEMY = 0.1
const MAX_PENALTY = 0.95
const KILL_BONUS = 0.02
const BASE_SPAWN_MIN = 4
const BASE_SPAWN_MAX = 7
const SPAWN_REDUCTION_PER_10 = 0.5
const SPAWN_MIN_ABSOLUTE = 0.5

const MAGIC_CIRCLE_TEXTURE = preload("res://Assets/Objects/magic circle prototype.png")

var spawn_points: Array[Node3D] = []
var progress: float = 0.0
var is_finished: bool = false

var active_circle: Area3D = null
var circle_timer: float = 0.0
var spawn_timer: float = 0.0
var last_spawn_index: int = -1

var player_inside: bool = false
var inside_enemies: Array[Node] = []
var progress_label: Label = null
var _kill_callbacks: Dictionary = {}

func start_condition() -> void:
	var nodes = get_tree().get_nodes_in_group("spawn_points")
	for n in nodes:
		spawn_points.append(n as Node3D)
	if spawn_points.is_empty():
		print("No spawn points found — add Marker3D nodes to group 'spawn_points'")
	player = get_tree().get_first_node_in_group("player")
	if player:
		progress_label = player.get_node_or_null("HUD/CleanseProgressLabel")
	progress = 0.0
	is_finished = false
	spawn_circle()
	spawn_timer = randf_range(BASE_SPAWN_MIN, BASE_SPAWN_MAX)

func spawn_circle() -> void:
	if active_circle:
		active_circle.queue_free()
		active_circle = null
	if spawn_points.is_empty():
		return
	var idx = randi() % spawn_points.size()
	if spawn_points.size() > 1:
		while idx == last_spawn_index:
			idx = randi() % spawn_points.size()
	last_spawn_index = idx
	var pos = spawn_points[idx].global_position + Vector3.UP

	var area = Area3D.new()
	area.collision_mask = 9
	var shape = CollisionShape3D.new()
	shape.shape = CylinderShape3D.new()
	shape.shape.radius = CIRCLE_RADIUS
	shape.shape.height = CIRCLE_HEIGHT
	area.add_child(shape)

	var sprite = Sprite3D.new()
	sprite.texture = MAGIC_CIRCLE_TEXTURE
	sprite.centered = true
	sprite.billboard = false
	sprite.rotation.x = -PI / 2
	var tex_size = sprite.texture.get_size()
	sprite.pixel_size = (CIRCLE_RADIUS * 2.0) / tex_size.x
	sprite.position.y = 0.05
	area.add_child(sprite)

	var timer_label = Label3D.new()
	timer_label.name = "TimerLabel"
	timer_label.text = ""
	timer_label.billboard = true
	timer_label.pixel_size = 0.05
	timer_label.position.y = 2.0
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.outline_size = 2
	area.add_child(timer_label)

	add_child(area)
	area.global_position = pos

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	active_circle = area
	circle_timer = CIRCLE_LIFETIME

	player_inside = false
	inside_enemies.clear()
	for enemy in _kill_callbacks:
		var cb = _kill_callbacks[enemy]
		if is_instance_valid(enemy) and enemy.died.is_connected(cb):
			enemy.died.disconnect(cb)
	_kill_callbacks.clear()

func _on_body_entered(body: Node) -> void:
	if body == player:
		player_inside = true
	elif body.is_in_group("enemies"):
		if not inside_enemies.has(body):
			inside_enemies.append(body)
			var cb = _on_enemy_died.bind(body)
			_kill_callbacks[body] = cb
			if not body.died.is_connected(cb):
				body.died.connect(cb)

func _on_body_exited(body: Node) -> void:
	if body == player:
		player_inside = false
	elif body.is_in_group("enemies"):
		inside_enemies.erase(body)
		var cb = _kill_callbacks.get(body)
		if cb != null and body.died.is_connected(cb):
			body.died.disconnect(cb)
		_kill_callbacks.erase(body)

func _on_enemy_died(enemy: Node) -> void:
	progress += KILL_BONUS
	inside_enemies.erase(enemy)
	var cb = _kill_callbacks.get(enemy)
	if cb != null:
		_kill_callbacks.erase(enemy)

func process_condition(delta: float) -> void:
	if is_finished:
		return

	circle_timer -= delta
	if active_circle:
		var label = active_circle.get_node_or_null("TimerLabel") as Label3D
		if label:
			label.text = "%d" % ceil(circle_timer) if circle_timer > 0 else ""
	if circle_timer <= 0:
		spawn_circle()

	if player_inside:
		var penalty = minf(inside_enemies.size() * PENALTY_PER_ENEMY, MAX_PENALTY)
		var rate = 1.0 - penalty if not inside_enemies.is_empty() else 1.0
		progress += delta / FILL_TIME * rate
	else:
		progress -= delta * DECAY_RATE

	progress = clampf(progress, 0.0, 1.0)

	if progress_label:
		progress_label.text = "Cleansing: %d%%" % (progress * 100)

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_enemy()
		var steps = floor(progress / 0.1)
		var reduction = steps * SPAWN_REDUCTION_PER_10
		var min_t = maxf(BASE_SPAWN_MIN - reduction, SPAWN_MIN_ABSOLUTE)
		var max_t = maxf(BASE_SPAWN_MAX - reduction, min_t + 0.5)
		spawn_timer = randf_range(min_t, max_t)

	if progress >= 1.0:
		is_finished = true
		if active_circle:
			active_circle.queue_free()
			active_circle = null
		if progress_label:
			progress_label.text = ""

func _spawn_enemy() -> void:
	if spawn_points.is_empty():
		return
	var spawn: Node3D = spawn_points[randi() % spawn_points.size()]
	var enemy = ENEMY_SCENES[randi() % ENEMY_SCENES.size()].instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn.global_position + Vector3.UP


func is_complete() -> bool:
	return is_finished

func get_progress() -> float:
	return progress
