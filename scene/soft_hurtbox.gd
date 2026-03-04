extends Area2D
## 软体受击盒
## 约定：挂载此脚本的 Area2D 加入组 "enemy_hurtbox"，被武器派发器统一识别。
##
## 与 enemy_hurtbox.gd 的区别：
##   在 get_host() 返回宿主之前，先调用宿主的 _mark_next_hit_soft()。
##   武器派发器的调用顺序保证：get_host() → apply_hit()，
##   因此标记在同一帧内命中前安全写入，apply_hit() 读取后立即清除。

@export var host_path: NodePath = NodePath("..")

func _ready() -> void:
	add_to_group("enemy_hurtbox")

func get_host() -> Node:
	var n := get_node_or_null(host_path)
	if n != null and n.has_method("_mark_next_hit_soft"):
		n._mark_next_hit_soft()
	return n
