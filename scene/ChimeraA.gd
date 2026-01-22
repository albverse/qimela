extends CharacterBody2D
class_name ChimeraA
# ChimeraA：只有在“锁链 LINKED 到奇美拉期间”才触发互动效果（跟随玩家X）

@export var gravity: float = 1500.0             # 重力
@export var move_speed: float = 170.0           # 比玩家慢一些，便于解除链接
@export var accel: float = 1400.0               # 加速度
@export var stop_threshold_x: float = 6.0       # 与玩家X差距小于此就停
@export var x_offset: float = 0.0               # 站玩家左/右边偏移

@export var visual_path: NodePath = ^"Visual"   # 可选：用于未来做闪白/动画

var _player: Node2D = null
var _linked_slots: Dictionary = {} # slot -> true（未来允许两条链同时链接）

func set_player(p: Node2D) -> void:
	_player = p

# 兼容你之前的 setup(self) 调用
func setup(p: Node2D) -> void:
	set_player(p)

# 锁链命中时：允许进入 LINKED（返回 1），不扣血
func on_chain_hit(_player_node: Node, _slot: int, _hit_world: Vector2) -> int:
	return 1

func on_chain_attached(slot: int, player: Node, _hit_world: Vector2) -> void:
	_linked_slots[slot] = true
	if _player == null:
		var p2d := player as Node2D
		if p2d != null:
			_player = p2d

func on_chain_detached(slot: int) -> void:
	_linked_slots.erase(slot)

func _physics_process(dt: float) -> void:
	velocity.y += gravity * dt

	var linked: bool = _linked_slots.size() > 0
	if linked and _player != null and is_instance_valid(_player):
		var target_x: float = _player.global_position.x + x_offset
		var dx: float = target_x - global_position.x

		if absf(dx) <= stop_threshold_x:
			velocity.x = move_toward(velocity.x, 0.0, accel * dt)
		else:
			var dir: float = signf(dx)
			var desired: float = dir * move_speed
			velocity.x = move_toward(velocity.x, desired, accel * dt)
	else:
		velocity.x = move_toward(velocity.x, 0.0, accel * dt)

	move_and_slide()
