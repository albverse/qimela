extends StaticBody2D
class_name CollapsingPlatform

## 消失平台：玩家站上后 2 秒消失，3 秒后恢复
## 蓝图 §3.4: Timer + set_deferred("disabled", true/false)

@export var collapse_delay: float = 2.0  # 站上后多久消失
@export var respawn_delay: float = 3.0   # 消失后多久恢复

var _collapse_timer: float = -1.0  # <0 表示未激活
var _respawn_timer: float = -1.0
var _collapsed: bool = false
var _player_on: bool = false


func _physics_process(dt: float) -> void:
	if _collapsed:
		# 恢复倒计时
		if _respawn_timer > 0.0:
			_respawn_timer -= dt
			if _respawn_timer <= 0.0:
				_respawn()
		return

	# 检测玩家是否在平台上（通过碰撞检测）
	_player_on = _is_player_standing()

	if _player_on:
		if _collapse_timer < 0.0:
			_collapse_timer = collapse_delay
		_collapse_timer -= dt
		if _collapse_timer <= 0.0:
			_collapse()
	else:
		_collapse_timer = -1.0


func _is_player_standing() -> bool:
	## 检查是否有玩家站在本平台上
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		var cb: CharacterBody2D = p as CharacterBody2D
		if cb == null:
			continue
		if not cb.is_on_floor():
			continue
		# 检查玩家的地面碰撞是否来自本平台
		for i in cb.get_slide_collision_count():
			var col: KinematicCollision2D = cb.get_slide_collision(i)
			if col != null and col.get_collider() == self:
				return true
	return false


func _collapse() -> void:
	_collapsed = true
	_collapse_timer = -1.0
	_respawn_timer = respawn_delay
	# 禁用碰撞形状
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	visible = false


func _respawn() -> void:
	_collapsed = false
	_respawn_timer = -1.0
	# 恢复碰撞形状
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", false)
	visible = true
