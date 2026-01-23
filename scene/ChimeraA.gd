extends CharacterBody2D
class_name ChimeraA

# ===== 互动移动参数 =====
@export var gravity: float = 1500.0
@export var move_speed: float = 170.0
@export var accel: float = 1400.0
@export var stop_threshold_x: float = 6.0
@export var x_offset: float = 0.0

var _player: Node2D = null
var _linked: bool = false
var _linked_slot: int = -1


func _ready() -> void:
	# 让 Player 的锁链射线识别它（Player 里检测 group: "chimera"）
	add_to_group("chimera")

# 兼容 Player：spawn 后会调用 setup(self)
func setup(p: Node2D) -> void:
	set_player(p)

func set_player(p: Node2D) -> void:
	_player = p


# Player 的射线命中后会先调用 on_chain_hit。
# 返回 1 表示：锁链进入 LINKED（保持链接），并触发互动。
func on_chain_hit(_player_ref: Node, slot: int) -> int:
	on_chain_attached(slot)
	return 1

# Player：锁链链接到奇美拉时调用
func on_chain_attached(slot: int) -> void:
	_linked = true
	_linked_slot = slot

# Player：锁链断裂/溶解/结束时调用
func on_chain_detached(slot: int) -> void:
	if slot == _linked_slot:
		_linked = false
		_linked_slot = -1

func _physics_process(dt: float) -> void:
	velocity.y += gravity * dt

	if _linked and _player != null and is_instance_valid(_player):
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
