extends CharacterBody2D
class_name HookHead

@export var speed: float = 1400.0
@export var max_range: float = 450.0
@export var ttl: float = 0.40
@export var linger_time: float = 0.30

var owner_player: Node = null
var slot_idx: int = -1
var dir: Vector2 = Vector2.RIGHT

var start_pos: Vector2
var time_left: float

var attached := false
var attached_mode := ""  # "monster" / "anchor"
var attached_target: Node2D = null
var attached_offset: Vector2 = Vector2.ZERO
var anchor_pos: Vector2 = Vector2.ZERO

var lingering := false
var linger_left: float = 0.0

func fire(from_pos: Vector2, direction: Vector2, owner_ref: Node, idx: int) -> void:
	global_position = from_pos
	start_pos = from_pos
	time_left = ttl
	lingering = false
	linger_left = linger_time

	dir = direction.normalized()
	owner_player = owner_ref
	slot_idx = idx

	# 关键：避免一出生就撞到玩家导致“卡在手上”
	if owner_player is CollisionObject2D:
		add_collision_exception_with(owner_player as CollisionObject2D)

	velocity = dir * speed

func _physics_process(delta: float) -> void:
	if attached:
		if attached_mode == "monster":
			if is_instance_valid(attached_target):
				global_position = attached_target.global_position + attached_offset
			else:
				_notify_owner_clear()
				queue_free()
		elif attached_mode == "anchor":
			global_position = anchor_pos
		return

	if lingering:
		linger_left -= delta
		if linger_left <= 0.0:
			_notify_owner_clear()
			queue_free()
		return

	# 飞行阶段：到射程/超时 -> 进入停留窗口（可二段F拉人）
	time_left -= delta
	if time_left <= 0.0 or global_position.distance_to(start_pos) >= max_range:
		lingering = true
		linger_left = linger_time
		velocity = Vector2.ZERO
		if owner_player:
			owner_player.call("on_hook_miss_linger", slot_idx, global_position)
		return

	# 子弹式运动
	var col := move_and_collide(velocity * delta)
	if col:
		_on_hit(col.get_collider(), col.get_position())

func _on_hit(collider: Object, hit_pos: Vector2) -> void:
	if owner_player == null:
		queue_free()
		return

	# 命中怪物
	if collider is Node and (collider as Node).is_in_group("monster"):
		var m := collider as Node
		var weakened := false
		if m.has_variable("is_weakened"):
			weakened = m.get("is_weakened")

		if weakened:
			attached = true
			attached_mode = "monster"
			attached_target = m as Node2D
			attached_offset = hit_pos - (m as Node2D).global_position
			global_position = hit_pos
			velocity = Vector2.ZERO
			owner_player.call("on_hook_attached_monster", slot_idx, attached_target)
			return
		else:
			_notify_owner_clear()
			queue_free()
			return

	# 命中障碍物B
	if collider is Node and (collider as Node).is_in_group("hookable_b"):
		attached = true
		attached_mode = "anchor"
		anchor_pos = hit_pos
		global_position = hit_pos
		velocity = Vector2.ZERO
		owner_player.call("on_hook_attached_anchor", slot_idx, anchor_pos)
		return

	# 其它墙/障碍：直接消失
	_notify_owner_clear()
	queue_free()

func _notify_owner_clear() -> void:
	if owner_player:
		owner_player.call("on_hook_cleared", slot_idx)
