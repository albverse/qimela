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


func get_host() -> Node:
	return get_node_or_null(host_path)


func apply_hit(hit: HitData) -> bool:
	## 由链条/武器系统命中时调用，路由到修女蛇的 apply_hit_eye_hurtbox
	var host: Node = get_host()
	if host == null:
		return false
	if host.has_method("apply_hit_eye_hurtbox"):
		return host.call("apply_hit_eye_hurtbox", hit) as bool
	return false
