extends Area2D
class_name NunSnakeEyeHurtbox

## =============================================================================
## NunSnakeEyeHurtbox — 修女蛇眼球受击判定（独立路由）
## =============================================================================
## 与主 Hurtbox 的伤害路由彻底分离。
## 固定在眼窝位置，不随发射出去的眼球移动。
## 只有睁眼系（OPEN_EYE / GUARD_BREAK）期间有效。
## =============================================================================

@export var host_path: NodePath = NodePath("..")


func _ready() -> void:
	# 与常规 Hurtbox 一致：必须进入 enemy_hurtbox 组，
	# 才会被玩家武器与雷花命中分发系统识别。
	add_to_group("enemy_hurtbox")


func get_host() -> Node:
	var host: Node = get_node_or_null(host_path)
	if host != null and host.has_method("_mark_next_hit_eye"):
		host.call("_mark_next_hit_eye")
	return host


func apply_hit(hit: HitData) -> bool:
	## 由链条/武器系统命中时调用，路由到修女蛇的 apply_hit_eye_hurtbox
	var host: Node = get_host()
	if host == null:
		return false
	if host.has_method("apply_hit_eye_hurtbox"):
		return host.call("apply_hit_eye_hurtbox", hit) as bool
	return false
