extends RigidBody3D

signal hit_enemy(enemy: Node3D)

# Projectile Speed
var speed = 20.0
var damage = 25.0
var is_enemy_projectile: bool = false
var homing_target: Node3D = null

@onready var dagger_visual = $MeshInstance3D
@onready var sphere_visual = $SphereVisual
@onready var dagger_collision = $DaggerCollision
@onready var sphere_collision = $SphereCollision

func _ready():
	if is_enemy_projectile:
		collision_mask = 1
	else:
		collision_mask = 9
	dagger_visual.visible = not is_enemy_projectile
	sphere_visual.visible = is_enemy_projectile
	dagger_collision.disabled = is_enemy_projectile
	sphere_collision.disabled = not is_enemy_projectile
	if homing_target:
		set_physics_process(true)

func _physics_process(delta):
	if not homing_target or not is_instance_valid(homing_target):
		set_physics_process(false)
		return
	var dir = (homing_target.global_position - global_position).normalized()
	linear_velocity = linear_velocity.lerp(dir * speed, 5.0 * delta)

# Launch physics
func launch(direction: Vector3):
	gravity_scale = 0
	linear_velocity = direction * speed

func _on_body_entered(body):
	if body.is_in_group("player"):
		body.take_damage(damage)
		queue_free()
	elif body.is_in_group("enemies") and not is_enemy_projectile:
		body.take_damage(damage)
		hit_enemy.emit(body)
		queue_free()
	elif not body.is_in_group("enemies"):
		queue_free()
