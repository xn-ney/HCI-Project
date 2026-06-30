extends RigidBody3D

signal landed

var damage = 15.0
var arc_height = 0.5

const LAUNCH_SPEED = 12.0

func _ready():
	collision_mask = 1

func launch(direction: Vector3):
	gravity_scale = 1
	var arc_dir = direction + Vector3.UP * arc_height
	linear_velocity = arc_dir.normalized() * LAUNCH_SPEED

func _on_body_entered(body):
	if body.is_in_group("projectiles"):
		pass
	elif body.is_in_group("player"):
		body.take_damage(damage)
		landed.emit()
		queue_free()
	elif body.is_in_group("enemies"):
		pass
	else:
		landed.emit()
		queue_free()
