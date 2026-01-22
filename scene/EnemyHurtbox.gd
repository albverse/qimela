extends Area2D
class_name EnemyHurtbox
# 受击盒：锁链射线只需要命中这个 Area2D（而不需要与怪物本体发生刚体碰撞）
# 约定：把该节点加入组 "enemy_hurtbox"

@export var host_path: NodePath = NodePath("..") # 默认父节点

func _ready() -> void:
	add_to_group("enemy_hurtbox")

func get_host() -> Node:
	var n := get_node_or_null(host_path)
	return n
