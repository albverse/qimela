extends StaticBody2D
class_name CollapsingPlatform

## 消失平台：玩家触碰后开始倒计时，即使离开也会到时消失，冷却后恢复
## 触发条件：玩家站上平台即触发（触碰即锁定倒计时，中途离开不取消）

@export var collapse_delay: float = 2.0  # 触碰后多久消失
@export var respawn_delay: float = 3.0   # 消失后多久恢复

var _collapse_timer: float = -1.0  # <0 表示未激活
var _respawn_timer: float = -1.0
var _collapsed: bool = false
var _triggered: bool = false  # 是否已触发倒计时（一旦触发不可取消）


func _physics_process(dt: float) -> void:
	if _collapsed:
		# 恢复倒计时
		if _respawn_timer > 0.0:
			_respawn_timer -= dt
			if _respawn_timer <= 0.0:
				_respawn()
		return

	# 尚未触发：检测玩家是否触碰平台
	if not _triggered:
		if _is_player_standing():
			_triggered = true
			_collapse_timer = collapse_delay

	# 已触发：倒计时（即使玩家离开也继续）
	if _triggered:
		_collapse_timer -= dt
		if _collapse_timer <= 0.0:
			_collapse()


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
	_triggered = false
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
