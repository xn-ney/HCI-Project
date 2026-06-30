extends RigidBody3D

var speed = 20.0
var damage = 15.0

func _ready():
	collision_mask = 1

func launch(direction: Vector3):
	gravity_scale = 0
	linear_velocity = direction * speed

func _on_body_entered(body):
	if body.is_in_group("projectiles"):
		pass
	elif body.is_in_group("player"):
		body.take_damage(damage)
		queue_free()
	elif body.is_in_group("enemies"):
		pass
	else:
		queue_free()
