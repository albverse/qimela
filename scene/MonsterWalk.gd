extends MonsterBase
class_name MonsterWalk

# ===== 陆行怪：简单左右走动 =====
@export var walk_speed: float = 80.0
@export var dir: int = -1

func _physics_process(dt: float) -> void:
	super._physics_process(dt)

	velocity.y += 1500.0 * dt

	if weak:
		velocity.x = 0.0
		move_and_slide()
		return

	if is_stunned():
		velocity.x = 0.0
		move_and_slide()
		return

	velocity.x = float(dir) * walk_speed
	move_and_slide()

	# 碰到墙就反向（用 CharacterBody2D 的碰撞信息）
	if is_on_wall():
		dir *= -1
