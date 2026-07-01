extends CharacterBody3D

var speed = 20.0
var damage = 15.0
var _dir := Vector3.ZERO

func _ready():
	collision_layer = 0
	collision_mask = 1

func launch(direction: Vector3):
	_dir = direction
	look_at(position + direction, Vector3.UP)

func _physics_process(delta: float):
	var collision = move_and_collide(_dir * speed * delta)
	if collision:
		var body = collision.get_collider()
		if body.is_in_group("player"):
			body.take_damage(damage)
		queue_free()
